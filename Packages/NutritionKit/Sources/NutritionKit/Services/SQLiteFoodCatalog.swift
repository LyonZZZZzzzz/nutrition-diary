import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct CatalogManifest: Codable, Sendable {
    public struct DatabaseInfo: Codable, Sendable {
        public let path: String
        public let sha256: String
        public let bytes: Int
    }
    public struct SourceInfo: Codable, Sendable {
        public let name: String
        public let version: String
        public let license: String
        public let url: String
    }
    public let schemaVersion: Int
    public let generatedAt: String
    public let recordCount: Int
    public let nameZhCount: Int?
    public let nameEnCount: Int?
    public let nameZhCuratedCount: Int?
    public let nameZhTaiwanCount: Int?
    public let nameZhMachineCount: Int?
    public let nameZhMissingCount: Int?
    public let translationCacheVersion: Int?
    public let translationCacheSHA256: String?
    public let translationSourceSHA256: String?
    public let database: DatabaseInfo
    public let sources: [SourceInfo]

    public static func bundled() -> CatalogManifest? {
        guard let url = Bundle.module.url(forResource: "catalog-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CatalogManifest.self, from: data)
    }
}

private final class SQLiteConnection {
    let pointer: OpaquePointer
    init?(url: URL) {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else { return nil }
        pointer = handle
    }
    deinit { sqlite3_close(pointer) }
}

public actor SQLiteFoodCatalog: FoodSearching {
    public static let maximumCandidateCount = 200
    private let connection: SQLiteConnection?
    private var userFoods: [FoodItem] = []
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init?(url: URL) {
        guard let connection = SQLiteConnection(url: url) else { return nil }
        self.connection = connection
    }

    public static func bundled() -> SQLiteFoodCatalog? {
        guard let url = Bundle.module.url(forResource: "Catalog", withExtension: "sqlite") else { return nil }
        return SQLiteFoodCatalog(url: url)
    }

    public func search(query: String, limit: Int = 20, language: AppLanguage = .simplifiedChinese) async -> [FoodItem] {
        Array((await searchResults(query: query, limit: limit, language: language)).map(\.food))
    }

    public func searchResults(query: String, limit: Int = 20, language: AppLanguage = .simplifiedChinese) async -> [FoodSearchResult] {
        let normalized = FoodTextScorer.normalize(query)
        if normalized.isEmpty {
            // Empty-query browsing is paged by the caller and is used by catalog
            // audit tests; the anti-scan cap applies to text candidate searches.
            return deduplicated(emptyQueryResults(limit: max(1, min(limit, 20_000)), language: language))
        }
        let boundedLimit = max(1, min(limit, Self.maximumCandidateCount))
        var candidates: [FoodItem] = []
        candidates.append(contentsOf: userFoods
            .filter { FoodTextScorer.bestMatch(query: query, food: $0, language: language).score > 0 }
            .prefix(Self.maximumCandidateCount))
        let tokens = searchTokens(normalized)
        let fts = tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " OR ")
        let candidateLimit = min(max(boundedLimit * 10, 50), Self.maximumCandidateCount)
        candidates.append(contentsOf: fetchFoods(ftsQuery: fts, limit: candidateLimit))
        var unique: [UUID: FoodItem] = [:]
        for food in candidates { unique[food.id] = food }
        let results = unique.values.compactMap { food -> FoodSearchResult? in
            let match = FoodTextScorer.detailedMatch(query: query, food: food, language: language)
            guard match.score > 0 else { return nil }
            let sourceBoost = food.source.kind == .custom ? 0.05 : (food.source.kind == .bundled ? 0.02 : 0)
            let exactSemanticMatch = [.displayName, .alias, .pinyin].contains(match.reason)
            let preparedBoost = food.preparationState == .prepared && exactSemanticMatch ? 0.04 : 0
            let priorityBoost = exactSemanticMatch ? min(0.08, Double(food.searchPriority ?? 0) / 1000) : 0
            let commonalityBoost = min(0.03, max(0, (food.commonality ?? 0) - 0.5) * 0.06)
            return FoodSearchResult(
                food: food,
                score: min(1, match.score + sourceBoost + preparedBoost + priorityBoost + commonalityBoost),
                matchedTerm: match.term,
                matchReason: match.reason
            )
        }.sorted {
            if abs($0.score - $1.score) < 0.0001 {
                let rank: (FoodMatchReason) -> Int = { reason in
                    switch reason {
                    case .displayName: 4
                    case .alias: 3
                    case .pinyin: 2
                    case .prefix: 1
                    case .fuzzy: 0
                    }
                }
                if rank($0.matchReason) != rank($1.matchReason) { return rank($0.matchReason) > rank($1.matchReason) }
                return $0.food.localizedName(for: language).localizedStandardCompare($1.food.localizedName(for: language)) == .orderedAscending
            }
            return $0.score > $1.score
        }
        return deduplicated(results).prefix(boundedLimit).map { $0 }
    }

    private func deduplicated(_ results: [FoodSearchResult]) -> [FoodSearchResult] {
        var seenGroups: Set<String> = []
        return results.filter { result in
            guard let group = result.canonicalGroupID, !group.isEmpty else { return true }
            return seenGroups.insert(group).inserted
        }
    }

    public func food(id: UUID) async -> FoodItem? {
        if let user = userFoods.first(where: { $0.id == id }) { return user }
        guard let database = connection?.pointer else { return nil }
        let safeID = id.uuidString.lowercased().filter { $0.isHexDigit || $0 == "-" }
        let sql = "SELECT payload FROM foods WHERE id = '\(safeID)' LIMIT 1"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return decodeFood(String(cString: text))
    }

    public func upsert(_ food: FoodItem) async {
        if let index = userFoods.firstIndex(where: { $0.id == food.id }) { userFoods[index] = food }
        else { userFoods.append(food) }
    }

    private func fetchFoods(ftsQuery: String, limit: Int) -> [FoodItem] {
        guard let database = connection?.pointer else { return [] }
        let safeFTS = ftsQuery.filter { $0 != "'" }
        let sql = "SELECT foods.payload FROM food_search JOIN foods ON foods.id = food_search.food_id WHERE food_search MATCH '\(safeFTS)' LIMIT \(max(1, limit))"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        var foods: [FoodItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0), let food = decodeFood(String(cString: text)) { foods.append(food) }
        }
        return foods
    }

    private func emptyQueryResults(limit: Int, language: AppLanguage) -> [FoodSearchResult] {
        guard let database = connection?.pointer else { return [] }
        var items = userFoods.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            return $0.localizedName(for: language).localizedStandardCompare($1.localizedName(for: language)) == .orderedAscending
        }
        let column = language.isChinese ? "name_zh" : "name_en"
        let localizedSQL = "SELECT payload FROM foods WHERE \(column) IS NOT NULL AND \(column) != '' ORDER BY \(column) LIMIT ?"
        let fallbackSQL = "SELECT payload FROM foods ORDER BY name LIMIT ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        var prepared = sqlite3_prepare_v2(database, localizedSQL, -1, &statement, nil) == SQLITE_OK
        if !prepared {
            sqlite3_finalize(statement)
            statement = nil
            prepared = sqlite3_prepare_v2(database, fallbackSQL, -1, &statement, nil) == SQLITE_OK
        }
        guard prepared else { return [] }
        sqlite3_bind_int(statement, 1, Int32(limit))
        while sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0), let food = decodeFood(String(cString: text)) {
            items.append(food)
        }
        return items.prefix(limit).map {
            FoodSearchResult(food: $0, score: 1, matchedTerm: $0.localizedName(for: language))
        }
    }

    private func decodeFood(_ payload: String) -> FoodItem? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? decoder.decode(FoodItem.self, from: data)
    }

    private func searchTokens(_ normalized: String) -> [String] {
        var tokens: Set<String> = [normalized]
        let cjk = normalized.filter { $0.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains(Int($0.value)) } }
        if !cjk.isEmpty {
            let chars = Array(cjk)
            if chars.count == 1 {
                tokens.insert(cjk)
            } else if chars.count >= 2 {
                // Avoid single-character OR terms for multi-character Chinese queries:
                // they match too many unrelated names and can push the intended food
                // outside the FTS candidate limit.
                tokens.formUnion((0...(chars.count - 2)).map { String(chars[$0...($0 + 1)]) })
            }
        }
        return tokens.filter { !$0.isEmpty }.sorted()
    }
}
