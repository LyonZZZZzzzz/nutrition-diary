import CryptoKit
import Foundation

public struct LocalPhotoLearningSummary: Hashable, Sendable {
    public let learnedMappings: Int
    public let portionHistories: Int

    public init(learnedMappings: Int, portionHistories: Int) {
        self.learnedMappings = learnedMappings
        self.portionHistories = portionHistories
    }
}

public actor PhotoMatchLearningStore {
    private struct FoodLearning: Codable, Sendable {
        var confirmed: Int = 0
        var rejected: Int = 0
        var portionRatios: [Double] = []
        var updatedAt: Date = .now
    }

    private struct State: Codable, Sendable {
        var records: [String: [String: FoodLearning]] = [:]
    }

    private let fileURL: URL?
    private var state: State

    public init(fileURL: URL? = PhotoMatchLearningStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
        }
    }

    public func rankingBonus(query: String, foodID: UUID) -> Double {
        guard let learning = state.records[Self.hash(query)]?[foodID.uuidString.lowercased()] else { return 0 }
        let positive = learning.confirmed >= 2 ? min(0.15, Double(learning.confirmed) * 0.075) : 0
        let negative = learning.rejected >= 2 ? max(-0.10, -Double(learning.rejected) * 0.04) : 0
        return min(0.15, max(-0.10, positive + negative))
    }

    public func portionMedianRatio(query: String, foodID: UUID) -> Double? {
        guard let values = state.records[Self.hash(query)]?[foodID.uuidString.lowercased()]?.portionRatios,
              values.count >= 3 else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    public func recordDecision(
        query: String,
        selectedFoodID: UUID,
        rejectedFoodID: UUID?,
        selectedGrams: Double,
        modelMidpointGrams: Double
    ) {
        let queryHash = Self.hash(query)
        var records = state.records[queryHash] ?? [:]
        let selectedKey = selectedFoodID.uuidString.lowercased()
        var selected = records[selectedKey] ?? FoodLearning()
        selected.confirmed += 1
        selected.updatedAt = .now
        if selectedGrams > 0, modelMidpointGrams > 0, selectedGrams.isFinite, modelMidpointGrams.isFinite {
            let ratio = min(4, max(0.25, selectedGrams / modelMidpointGrams))
            selected.portionRatios.append(ratio)
            selected.portionRatios = Array(selected.portionRatios.suffix(20))
        }
        records[selectedKey] = selected

        if let rejectedFoodID, rejectedFoodID != selectedFoodID {
            let rejectedKey = rejectedFoodID.uuidString.lowercased()
            var rejected = records[rejectedKey] ?? FoodLearning()
            rejected.rejected += 1
            rejected.updatedAt = .now
            records[rejectedKey] = rejected
        }
        state.records[queryHash] = records
        persist()
    }

    public func summary() -> LocalPhotoLearningSummary {
        LocalPhotoLearningSummary(
            learnedMappings: state.records.values.reduce(0) { $0 + $1.count },
            portionHistories: state.records.values.flatMap(\.values).filter { $0.portionRatios.count >= 3 }.count
        )
    }

    public func clearAll() {
        state = State()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL() -> URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent("NutritionDiary", isDirectory: true)
            .appendingPathComponent("photo-match-learning.json")
    }

    private static func hash(_ query: String) -> String {
        let normalized = FoodTextScorer.normalize(query)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
