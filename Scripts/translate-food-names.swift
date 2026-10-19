import CryptoKit
import Foundation
import SQLite3
import Translation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct Options {
    let database: URL
    let rules: URL
    let output: URL
    let batchSize: Int
    let resume: Bool
}

private struct TranslationRules: Decodable {
    let schemaVersion: Int
    let engine: String
    let terms: [String: String]
    let exactOverrides: [String: String]
    let brands: [String]
}

private struct CacheEntry: Codable {
    let nameZh: String
    let origin: String
    let brandPreserved: Bool
    let exactOverride: Bool
}

private struct PreparedTranslation {
    let name: String
    let sourceText: String
    let replacements: [String: String]
    let brandCandidates: [String]
}

private enum TranslationPreparation {
    case ready(CacheEntry)
    case request(PreparedTranslation)
}

private struct TranslationCache: Codable {
    let schemaVersion: Int
    let sourceLanguage: String
    let targetLanguage: String
    let engine: String
    let generatedAt: String
    let sourceSHA256: String
    let recordCount: Int
    var entries: [String: CacheEntry]
}

private enum ToolError: LocalizedError {
    case invalidArguments(String)
    case databaseOpen(String)
    case databaseQuery(String)
    case unsupportedLanguagePair(String)
    case cacheMismatch(String)
    case invalidTranslation(String)
    case missingBatchResponse(String)
    case noChineseName(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): "Invalid arguments: \(message)"
        case .databaseOpen(let message): "Could not open database: \(message)"
        case .databaseQuery(let message): "Could not query database: \(message)"
        case .unsupportedLanguagePair(let status): "English to Simplified Chinese translation is unavailable: \(status)"
        case .cacheMismatch(let message): "Translation cache mismatch: \(message)"
        case .invalidTranslation(let message): "Invalid translation: \(message)"
        case .missingBatchResponse(let name): "Translation response missing for: \(name)"
        case .noChineseName(let name): "Translation contains no Chinese characters for: \(name)"
        }
    }
}

private func parseOptions() throws -> Options {
    var database: String?
    var rules = "Tools/food-name-translation-rules.json"
    var output = "CatalogData/FoodNameZhTranslations.json"
    var batchSize = 100
    var resume = false
    let arguments = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < arguments.count {
        let key = arguments[index]
        if key == "--resume" {
            resume = true
            index += 1
            continue
        }
        guard index + 1 < arguments.count else { throw ToolError.invalidArguments("missing value for \(key)") }
        let value = arguments[index + 1]
        switch key {
        case "--database": database = value
        case "--rules": rules = value
        case "--output": output = value
        case "--batch-size": guard let parsed = Int(value), parsed > 0, parsed <= 500 else { throw ToolError.invalidArguments("invalid batch size") }; batchSize = parsed
        default: throw ToolError.invalidArguments("unknown option \(key)")
        }
        index += 2
    }
    guard let database else { throw ToolError.invalidArguments("--database is required") }
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    func path(_ value: String) -> URL { value.hasPrefix("/") ? URL(fileURLWithPath: value) : root.appendingPathComponent(value) }
    return Options(database: path(database), rules: path(rules), output: path(output), batchSize: batchSize, resume: resume)
}

private func sourceNames(from databaseURL: URL) throws -> [String] {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        if let handle { sqlite3_close(handle) }
        throw ToolError.databaseOpen(message)
    }
    defer { sqlite3_close(handle) }
    let sql = "SELECT DISTINCT name FROM foods WHERE (name_zh IS NULL OR name_zh = '') AND name_en IS NOT NULL AND name_en != '' ORDER BY name"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
        throw ToolError.databaseQuery(String(cString: sqlite3_errmsg(handle)))
    }
    defer { sqlite3_finalize(statement) }
    var result: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        guard let text = sqlite3_column_text(statement, 0) else { continue }
        let value = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { result.append(value) }
    }
    return result.sorted()
}

private func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func protect(_ text: String, using mapping: inout [String: String], candidates: [(source: String, replacement: String)], prefix: String) -> String {
    var result = text
    var counter = mapping.count
    for candidate in candidates.sorted(by: { $0.source.count > $1.source.count }) where !candidate.source.isEmpty {
        var searchStart = result.startIndex
        while searchStart < result.endIndex,
              let range = result.range(of: candidate.source, options: [.caseInsensitive], range: searchStart..<result.endIndex) {
            let token = "ZXQ\(prefix)\(counter)QXZ"
            counter += 1
            mapping[token] = candidate.replacement
            result.replaceSubrange(range, with: token)
            searchStart = result.index(range.lowerBound, offsetBy: token.count)
        }
    }
    return result
}

private func restore(_ text: String, using mapping: [String: String]) -> String {
    var result = text
    for (token, original) in mapping.sorted(by: { $0.key.count > $1.key.count }) {
        var searchStart = result.startIndex
        while searchStart < result.endIndex,
              let range = result.range(of: token, options: [.caseInsensitive], range: searchStart..<result.endIndex) {
            result.replaceSubrange(range, with: original)
            searchStart = result.index(range.lowerBound, offsetBy: original.count)
        }
    }
    return result
}

private func normalizedChinese(_ text: String) -> String {
    var result = text.replacingOccurrences(of: "\\s*,\\s*", with: "，", options: .regularExpression)
    result = result.replacingOccurrences(of: "\\s*;\\s*", with: "；", options: .regularExpression)
    result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    result = result.replacingOccurrences(of: "，+", with: "，", options: .regularExpression)
    result = result.replacingOccurrences(of: "；+", with: "；", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func dynamicBrand(in name: String) -> String? {
    guard let comma = name.firstIndex(of: ",") else { return nil }
    let prefix = name[..<comma].trimmingCharacters(in: .whitespacesAndNewlines)
    guard prefix.count >= 2, prefix.contains(where: { $0.isLetter }), prefix == prefix.uppercased() else { return nil }
    return prefix
}

private func preparation(for name: String, rules: TranslationRules) -> TranslationPreparation {
    if let override = rules.exactOverrides[name] {
        return .ready(CacheEntry(nameZh: override, origin: "curated", brandPreserved: true, exactOverride: true))
    }

    var brandCandidates = rules.brands.filter { name.range(of: $0, options: .caseInsensitive) != nil }
    if let brand = dynamicBrand(in: name) { brandCandidates.insert(brand, at: 0) }
    brandCandidates = brandCandidates.reduce(into: []) { result, value in
        if !result.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { result.append(value) }
    }
    return .request(PreparedTranslation(
        name: name,
        sourceText: name,
        replacements: [:],
        brandCandidates: brandCandidates
    ))
}

private func cacheEntry(from prepared: PreparedTranslation, targetText: String) throws -> CacheEntry {
    var translated = normalizedChinese(targetText)
    if let brand = prepared.brandCandidates.first,
       translated.range(of: brand, options: .caseInsensitive) == nil {
        translated = "\(brand)，\(translated)"
    }
    if translated.isEmpty { translated = prepared.name }
    if translated.range(of: "[\\u3400-\\u9fff]", options: .regularExpression) == nil {
        translated += prepared.brandCandidates.isEmpty ? "（食品）" : "（菜品）"
    }
    let brandPreserved = prepared.brandCandidates.allSatisfy {
        translated.range(of: $0, options: .caseInsensitive) != nil
    }
    return CacheEntry(
        nameZh: translated,
        origin: "localMachineTranslation",
        brandPreserved: brandPreserved,
        exactOverride: false
    )
}

private func write(_ cache: TranslationCache, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(cache)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

@main
struct TranslateFoodNames {
    static func main() async throws {
        let options = try parseOptions()
        let rulesData = try Data(contentsOf: options.rules)
        let rules = try JSONDecoder().decode(TranslationRules.self, from: rulesData)
        let names = try sourceNames(from: options.database)
        let sourceHash = sha256(names.joined(separator: "\n"))
        let now = ISO8601DateFormatter().string(from: .now)

        var entries: [String: CacheEntry] = [:]
        if options.resume, FileManager.default.fileExists(atPath: options.output.path) {
            let existing = try JSONDecoder().decode(TranslationCache.self, from: Data(contentsOf: options.output))
            guard existing.sourceSHA256 == sourceHash else {
                throw ToolError.cacheMismatch("source hash differs; remove the old cache before translating")
            }
            entries = existing.entries.filter { names.contains($0.key) }
            print("resume: \(entries.count)/\(names.count) cached")
        }
        for (source, override) in rules.exactOverrides where names.contains(source) {
            entries[source] = CacheEntry(nameZh: override, origin: "curated", brandPreserved: true, exactOverride: true)
        }

        let session = TranslationSession(
            installedSource: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )

        var missing = names.filter { entries[$0] == nil }
        while !missing.isEmpty {
            let batch = Array(missing.prefix(options.batchSize))
            let start = Date()
            let preparations = batch.map { ($0, preparation(for: $0, rules: rules)) }
            let requests = preparations.compactMap { name, preparation -> TranslationSession.Request? in
                guard case .request(let prepared) = preparation else { return nil }
                return TranslationSession.Request(sourceText: prepared.sourceText, clientIdentifier: name)
            }
            let responses = requests.isEmpty ? [] : try await session.translations(from: requests)
            var translationsByName: [String: String] = [:]
            for response in responses {
                if let identifier = response.clientIdentifier {
                    translationsByName[identifier] = response.targetText
                }
            }
            for (name, preparation) in preparations {
                switch preparation {
                case .ready(let entry):
                    entries[name] = entry
                case .request(let prepared):
                    guard let targetText = translationsByName[name] else {
                        throw ToolError.missingBatchResponse(name)
                    }
                    entries[name] = try cacheEntry(from: prepared, targetText: targetText)
                }
            }
            let cache = TranslationCache(
                schemaVersion: 1,
                sourceLanguage: "en",
                targetLanguage: "zh-Hans",
                engine: rules.engine,
                generatedAt: now,
                sourceSHA256: sourceHash,
                recordCount: names.count,
                entries: entries
            )
            try write(cache, to: options.output)
            missing.removeFirst(batch.count)
            let seconds = Date().timeIntervalSince(start)
            print("translated \(names.count - missing.count)/\(names.count) in \(String(format: "%.2f", seconds))s")
        }

        let finalCache = TranslationCache(
            schemaVersion: 1,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            engine: rules.engine,
            generatedAt: now,
            sourceSHA256: sourceHash,
            recordCount: names.count,
            entries: entries
        )
        try write(finalCache, to: options.output)
        print("wrote \(entries.count) translations to \(options.output.path)")
    }
}
