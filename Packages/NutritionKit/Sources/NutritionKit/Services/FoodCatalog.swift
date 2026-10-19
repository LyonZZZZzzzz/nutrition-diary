import Foundation

public enum FoodMatchReason: String, Codable, Hashable, Sendable {
    case displayName
    case alias
    case pinyin
    case prefix
    case fuzzy

    public func localizedTitle(for language: AppLanguage) -> String {
        if language.isChinese {
            switch self {
            case .displayName: "名称精确"
            case .alias: "别名"
            case .pinyin: "拼音"
            case .prefix: "前缀"
            case .fuzzy: "模糊匹配"
            }
        } else {
            switch self {
            case .displayName: "Exact name"
            case .alias: "Alias"
            case .pinyin: "Pinyin"
            case .prefix: "Prefix"
            case .fuzzy: "Fuzzy match"
            }
        }
    }
}

public struct FoodSearchResult: Identifiable, Hashable, Sendable {
    public var id: UUID { food.id }
    public let food: FoodItem
    public let score: Double
    public let matchedTerm: String
    public let matchReason: FoodMatchReason
    public let canonicalGroupID: String?
    public let dataQuality: FoodDataQuality?

    public init(
        food: FoodItem,
        score: Double,
        matchedTerm: String,
        matchReason: FoodMatchReason = .displayName,
        canonicalGroupID: String? = nil,
        dataQuality: FoodDataQuality? = nil
    ) {
        self.food = food
        self.score = score
        self.matchedTerm = matchedTerm
        self.matchReason = matchReason
        self.canonicalGroupID = canonicalGroupID ?? food.canonicalGroupID
        self.dataQuality = dataQuality ?? food.dataQuality
    }
}

public protocol FoodSearching: Sendable {
    func search(query: String, limit: Int, language: AppLanguage) async -> [FoodItem]
    func searchResults(query: String, limit: Int, language: AppLanguage) async -> [FoodSearchResult]
    func food(id: UUID) async -> FoodItem?
    func upsert(_ food: FoodItem) async
}

public struct FoodTextMatch: Hashable, Sendable {
    public let score: Double
    public let term: String
    public let reason: FoodMatchReason

    public init(score: Double, term: String, reason: FoodMatchReason) {
        self.score = score
        self.term = term
        self.reason = reason
    }
}

public enum FoodTextScorer {
    public static func bestMatch(
        query: String,
        food: FoodItem,
        language: AppLanguage = .simplifiedChinese
    ) -> (score: Double, term: String) {
        let match = detailedMatch(query: query, food: food, language: language)
        return (match.score, match.term)
    }

    public static func detailedMatch(
        query: String,
        food: FoodItem,
        language: AppLanguage = .simplifiedChinese
    ) -> FoodTextMatch {
        let fullQuery = normalize(query)
        let displayName = food.localizedName(for: language)
        guard !fullQuery.isEmpty else { return FoodTextMatch(score: 1, term: displayName, reason: .displayName) }
        let coreQuery = removePreparationModifiers(from: fullQuery)
        let displayNormalized = normalize(displayName)
        let aliases = Set(food.aliases.map(normalize))
        let pinyin = Set((food.pinyin ?? []).map(normalize))
        var best = FoodTextMatch(score: 0, term: displayName, reason: .displayName)

        for term in food.searchableNames {
            let candidate = normalize(term)
            guard !candidate.isEmpty else { continue }
            var reason: FoodMatchReason = .fuzzy
            var score = phraseScore(query: fullQuery, coreQuery: coreQuery, candidate: candidate)

            if score > 0 {
                if candidate == displayNormalized {
                    reason = .displayName
                } else if aliases.contains(candidate) {
                    score = max(score, fullQuery == candidate ? 0.97 : 0.95)
                    reason = .alias
                } else if pinyin.contains(candidate) {
                    score = fullQuery == candidate ? 0.94 : min(score, candidate.hasPrefix(fullQuery) ? 0.90 : 0.86)
                    reason = .pinyin
                } else if candidate.hasPrefix(fullQuery) || coreQuery.hasPrefix(candidate) {
                    score = max(score, 0.82)
                    reason = .prefix
                }
            }

            if candidate.count >= 2 && coreQuery.contains(candidate) {
                score = max(score, min(0.96, 0.80 + 0.16 * Double(candidate.count) / Double(max(coreQuery.count, 1))))
            }
            if score > best.score { best = FoodTextMatch(score: score, term: term, reason: reason) }
        }
        return best
    }

    public static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }

    private static func phraseScore(query: String, coreQuery: String, candidate: String) -> Double {
        if query == candidate { return 1.0 }
        if coreQuery == candidate { return 0.98 }
        let genericTerms: Set<String> = ["食物", "食品", "饮料", "菜品", "餐食", "东西"]
        let shorter = coreQuery.count <= candidate.count ? coreQuery : candidate
        let longer = coreQuery.count <= candidate.count ? candidate : coreQuery
        let coverage = Double(shorter.count) / Double(max(longer.count, 1))
        if shorter.count == 1 && longer.hasPrefix(shorter) {
            return 0.78
        }
        if longer.hasPrefix(shorter), shorter.count >= 2, coverage >= 0.5 {
            return min(0.92, 0.72 + 0.20 * coverage)
        }
        if longer.contains(shorter), shorter.count >= 2, !genericTerms.contains(shorter) {
            return min(0.90, 0.72 + 0.18 * coverage)
        }
        guard coreQuery.count >= 2, candidate.count >= 2,
              abs(coreQuery.count - candidate.count) <= 2 else { return 0 }
        let distance = editDistance(coreQuery, candidate)
        let limit = max(coreQuery.count, candidate.count) >= 7 ? 2 : 1
        if distance <= limit {
            return max(0.55, 0.75 - Double(distance) * 0.10)
        }
        return 0
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs), right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var previous = Array(0...right.count)
        for i in 1...left.count {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = i
            for j in 1...right.count {
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func removePreparationModifiers(from value: String) -> String {
        let modifiers = ["无焦糖","去冰","少冰","多冰","加冰","常温","热饮","冷饮","无糖","少糖","半糖","低脂","脱脂","大杯","中杯","小杯","冰","热"]
        var result = value
        for modifier in modifiers { result = result.replacingOccurrences(of: modifier, with: "") }
        return result.isEmpty ? value : result
    }

    private static func longestCommonSubstringLength(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs), right = Array(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: right.count + 1), best = 0
        for i in 1...left.count {
            var current = Array(repeating: 0, count: right.count + 1)
            for j in 1...right.count where left[i-1] == right[j-1] {
                current[j] = previous[j-1] + 1
                best = max(best, current[j])
            }
            previous = current
        }
        return best
    }
}

public actor FoodCatalog: FoodSearching {
    private var foods: [FoodItem]
    public init(foods: [FoodItem] = SeedCatalog.foods) { self.foods = foods }

    public func search(query: String, limit: Int = 20, language: AppLanguage = .simplifiedChinese) -> [FoodItem] {
        Array(searchResultsSync(query: query, limit: limit, language: language).map(\.food))
    }

    public func searchResults(query: String, limit: Int = 20, language: AppLanguage = .simplifiedChinese) -> [FoodSearchResult] {
        searchResultsSync(query: query, limit: limit, language: language)
    }

    public func food(id: UUID) -> FoodItem? { foods.first { $0.id == id } }

    public func upsert(_ food: FoodItem) {
        if let index = foods.firstIndex(where: { $0.id == food.id }) { foods[index] = food }
        else { foods.append(food) }
    }

    private func searchResultsSync(query: String, limit: Int, language: AppLanguage) -> [FoodSearchResult] {
        let normalized = FoodTextScorer.normalize(query)
        if normalized.isEmpty {
            let sortedFoods = foods.sorted {
                let leftName = $0.localizedName(for: language)
                let rightName = $1.localizedName(for: language)
                let leftLocalized = $0.hasLocalizedName(for: language)
                let rightLocalized = $1.hasLocalizedName(for: language)
                if leftLocalized != rightLocalized { return leftLocalized && !rightLocalized }
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
                if ($0.searchPriority ?? 0) != ($1.searchPriority ?? 0) { return ($0.searchPriority ?? 0) > ($1.searchPriority ?? 0) }
                return leftName.localizedStandardCompare(rightName) == .orderedAscending
            }
            return deduplicatedFoods(sortedFoods).prefix(limit).map {
                FoodSearchResult(food: $0, score: 1, matchedTerm: $0.localizedName(for: language))
            }
        }
        let results = foods.compactMap { food -> FoodSearchResult? in
            let match = FoodTextScorer.detailedMatch(query: query, food: food, language: language)
            guard match.score > 0 else { return nil }
            let favoriteBonus = food.isFavorite ? 0.03 : 0
            let exactSemanticMatch = [.displayName, .alias, .pinyin].contains(match.reason)
            let preparedBonus = food.preparationState == .prepared && exactSemanticMatch ? 0.04 : 0
            let priorityBonus = exactSemanticMatch ? min(0.08, Double(food.searchPriority ?? 0) / 1000) : 0
            let commonalityBonus = min(0.03, max(0, (food.commonality ?? 0) - 0.5) * 0.06)
            return FoodSearchResult(
                food: food,
                score: min(1, match.score + favoriteBonus + preparedBonus + priorityBonus + commonalityBonus),
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
        return deduplicated(results).prefix(limit).map { $0 }
    }

    private func deduplicatedFoods(_ foods: [FoodItem]) -> [FoodItem] {
        var seenGroups: Set<String> = []
        return foods.filter { food in
            guard let group = food.canonicalGroupID, !group.isEmpty else { return true }
            return seenGroups.insert(group).inserted
        }
    }

    private func deduplicated(_ results: [FoodSearchResult]) -> [FoodSearchResult] {
        var seenGroups: Set<String> = []
        return results.filter { result in
            guard let group = result.canonicalGroupID, !group.isEmpty else { return true }
            return seenGroups.insert(group).inserted
        }
    }
}
