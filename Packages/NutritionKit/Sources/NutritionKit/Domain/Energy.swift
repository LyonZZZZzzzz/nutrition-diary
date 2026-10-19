import Foundation

public struct HealthEnergySource: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String
    public let productType: String?
    public let isWatch: Bool
    public var activeKcal: Double?
    public var basalKcal: Double?
    public var exerciseMinutes: Double?
    public var sampleCount: Int
    public var lastSampleAt: Date?

    public init(
        id: String,
        name: String,
        bundleIdentifier: String,
        productType: String? = nil,
        isWatch: Bool,
        activeKcal: Double? = nil,
        basalKcal: Double? = nil,
        exerciseMinutes: Double? = nil,
        sampleCount: Int = 0,
        lastSampleAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.productType = productType
        self.isWatch = isWatch
        self.activeKcal = activeKcal
        self.basalKcal = basalKcal
        self.exerciseMinutes = exerciseMinutes
        self.sampleCount = sampleCount
        self.lastSampleAt = lastSampleAt
    }

    public var displayName: String {
        "\(name) · \(isWatch ? "Apple Watch" : "iPhone/其他")"
    }
}

public struct HealthEnergySelection: Codable, Hashable, Sendable {
    public let activeSource: HealthEnergySource?
    public let basalSource: HealthEnergySource?
    public let exerciseSource: HealthEnergySource?
    public let coverageNote: String?

    public init(activeSource: HealthEnergySource?, basalSource: HealthEnergySource?, exerciseSource: HealthEnergySource?, coverageNote: String?) {
        self.activeSource = activeSource
        self.basalSource = basalSource
        self.exerciseSource = exerciseSource
        self.coverageNote = coverageNote
    }
}

public struct HealthEnergySourceSelector: Sendable {
    public init() {}

    public func select(from sources: [HealthEnergySource], preferredSourceID: String?) -> HealthEnergySelection {
        if let preferredSourceID {
            guard let source = sources.first(where: { $0.id == preferredSourceID }) else {
                return HealthEnergySelection(
                    activeSource: nil,
                    basalSource: nil,
                    exerciseSource: nil,
                    coverageNote: "固定来源不可用，请重新选择"
                )
            }
            return HealthEnergySelection(
                activeSource: source.activeKcal == nil ? nil : source,
                basalSource: source.basalKcal == nil ? nil : source,
                exerciseSource: source.exerciseMinutes == nil ? nil : source,
                coverageNote: "固定使用 \(source.name)"
            )
        }

        let watches = sources.filter(\.isWatch)
        let active = bestSource(for: sources, watches: watches, metric: \.activeKcal, metricValue: { $0.activeKcal })
        let basal = bestSource(for: sources, watches: watches, metric: \.basalKcal, metricValue: { $0.basalKcal })
        let exercise = bestSource(for: sources, watches: watches, metric: \.exerciseMinutes, metricValue: { $0.exerciseMinutes })

        let chosenWatches = Set([active, basal, exercise].compactMap { source in
            source?.isWatch == true ? source?.id : nil
        })
        let coverageNote: String?
        if sources.isEmpty {
            coverageNote = "没有检测到活动能量来源"
        } else if watches.isEmpty {
            coverageNote = "未检测到 Apple Watch，使用其他健康来源"
        } else if watches.count > 1 {
            coverageNote = "检测到 \(watches.count) 个 Watch 来源，按指标选择覆盖最高者"
        } else if chosenWatches.count == 1 {
            coverageNote = "使用 \(watches[0].name)"
        } else {
            coverageNote = "部分指标缺少 Watch 数据"
        }

        return HealthEnergySelection(activeSource: active, basalSource: basal, exerciseSource: exercise, coverageNote: coverageNote)
    }

    private func bestSource(
        for sources: [HealthEnergySource],
        watches: [HealthEnergySource],
        metric: KeyPath<HealthEnergySource, Double?>,
        metricValue: (HealthEnergySource) -> Double?
    ) -> HealthEnergySource? {
        let watchCandidates = watches.filter { metricValue($0) != nil }
        if !watchCandidates.isEmpty {
            return watchCandidates.max { lhs, rhs in
                if lhs.sampleCount == rhs.sampleCount { return metricValue(lhs) ?? 0 < metricValue(rhs) ?? 0 }
                return lhs.sampleCount < rhs.sampleCount
            }
        }
        return sources
            .filter { !$0.isWatch && metricValue($0) != nil }
            .max { lhs, rhs in
                if lhs.sampleCount == rhs.sampleCount { return metricValue(lhs) ?? 0 < metricValue(rhs) ?? 0 }
                return lhs.sampleCount < rhs.sampleCount
            }
    }
}

public struct EnergyDaySummary: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let dayKey: String
    public let activeKcal: Double?
    public let basalKcal: Double?
    public let exerciseMinutes: Double?
    public let activeSource: String?
    public let basalSource: String?
    public let exerciseSource: String?
    public let activeSourceID: String?
    public let basalSourceID: String?
    public let exerciseSourceID: String?
    public let fetchedAt: Date
    public let coverageNote: String?

    public init(
        id: UUID = UUID(),
        dayKey: String,
        activeKcal: Double?,
        basalKcal: Double?,
        exerciseMinutes: Double? = nil,
        activeSource: String? = nil,
        basalSource: String? = nil,
        exerciseSource: String? = nil,
        activeSourceID: String? = nil,
        basalSourceID: String? = nil,
        exerciseSourceID: String? = nil,
        fetchedAt: Date = .now,
        coverageNote: String? = nil
    ) {
        self.id = id
        self.dayKey = dayKey
        self.activeKcal = activeKcal
        self.basalKcal = basalKcal
        self.exerciseMinutes = exerciseMinutes
        self.activeSource = activeSource
        self.basalSource = basalSource
        self.exerciseSource = exerciseSource
        self.activeSourceID = activeSourceID
        self.basalSourceID = basalSourceID
        self.exerciseSourceID = exerciseSourceID
        self.fetchedAt = fetchedAt
        self.coverageNote = coverageNote
    }

    public var totalKcal: Double? {
        guard let activeKcal, let basalKcal else { return nil }
        return activeKcal + basalKcal
    }
}

public struct BalanceGoal: Codable, Hashable, Sendable {
    public let effectiveDayKey: String
    public let targetBalanceKcal: Double

    public init(effectiveDayKey: String, targetBalanceKcal: Double) {
        self.effectiveDayKey = effectiveDayKey
        self.targetBalanceKcal = targetBalanceKcal
    }
}

public struct EnergyBalance: Codable, Hashable, Sendable {
    public let intakeKcal: Double?
    public let activeKcal: Double?
    public let basalKcal: Double?
    public let totalBurnKcal: Double?
    public let activeBalanceKcal: Double?
    public let totalBalanceKcal: Double?
    public let suggestedIntakeKcal: Double?
    public let activeSource: String?
    public let basalSource: String?
    public let isComplete: Bool

    public init(
        intakeKcal: Double?,
        activeKcal: Double?,
        basalKcal: Double?,
        totalBurnKcal: Double?,
        activeBalanceKcal: Double?,
        totalBalanceKcal: Double?,
        suggestedIntakeKcal: Double?,
        activeSource: String? = nil,
        basalSource: String? = nil,
        isComplete: Bool
    ) {
        self.intakeKcal = intakeKcal
        self.activeKcal = activeKcal
        self.basalKcal = basalKcal
        self.totalBurnKcal = totalBurnKcal
        self.activeBalanceKcal = activeBalanceKcal
        self.totalBalanceKcal = totalBalanceKcal
        self.suggestedIntakeKcal = suggestedIntakeKcal
        self.activeSource = activeSource
        self.basalSource = basalSource
        self.isComplete = isComplete
    }
}

public struct HealthEnergyReadResult: Sendable {
    public let summary: EnergyDaySummary
    public let sources: [HealthEnergySource]

    public init(summary: EnergyDaySummary, sources: [HealthEnergySource]) {
        self.summary = summary
        self.sources = sources
    }
}
