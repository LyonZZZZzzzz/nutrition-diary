import Foundation

public struct PhotoFoodMatcher: Sendable {
    private let catalog: any FoodSearching
    private let language: AppLanguage

    public init(catalog: any FoodSearching, language: AppLanguage = .simplifiedChinese) {
        self.catalog = catalog
        self.language = language
    }

    public func candidates(for dish: AnalyzedDish, limit: Int = 3) async -> [PhotoFoodMatch] {
        var queries: [String] = []
        let aliases = dish.candidateAliases ?? []
        for value in [dish.name] + aliases + dish.visibleIngredients {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !queries.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) { queries.append(trimmed) }
        }
        var matches: [UUID: PhotoFoodMatch] = [:]
        for (queryIndex, query) in queries.enumerated() {
            let sourceWeight: Double
            if queryIndex == 0 {
                sourceWeight = 1.0
            } else if queryIndex <= aliases.count {
                sourceWeight = 0.86
            } else {
                sourceWeight = 0.55
            }
            let searchResults = await catalog.searchResults(query: query, limit: max(30, limit * 10), language: language)
            for result in searchResults {
                let local = FoodTextScorer.bestMatch(query: query, food: result.food, language: language)
                let score = min(1, max(0, max(local.score, result.score) * sourceWeight - Double(queryIndex) * 0.01))
                if score < 0.28 { continue }
                if let existing = matches[result.food.id], existing.score >= score { continue }
                matches[result.food.id] = PhotoFoodMatch(dish: dish, food: result.food, score: score, matchedTerm: local.term.isEmpty ? result.matchedTerm : local.term)
            }
        }
        return matches.values.sorted {
            if abs($0.score - $1.score) < 0.001 {
                return $0.food.localizedName(for: language).localizedStandardCompare($1.food.localizedName(for: language)) == .orderedAscending
            }
            return $0.score > $1.score
        }.prefix(limit).map { $0 }
    }

    public static func preferredCandidate(from candidates: [PhotoFoodMatch], minimumScore: Double = 0.80, minimumGap: Double = 0.10) -> PhotoFoodMatch? {
        guard let first = candidates.first, first.score >= minimumScore else { return nil }
        if let second = candidates.dropFirst().first, first.score - second.score < minimumGap { return nil }
        return first
    }
}
