import Foundation
import Testing
@testable import NutritionKit

struct HealthEnergySourceSelectorTests {
    private func source(_ id: String, watch: Bool, active: Double?, basal: Double?, exercise: Double?, samples: Int) -> HealthEnergySource {
        HealthEnergySource(
            id: id,
            name: id,
            bundleIdentifier: id,
            productType: watch ? "Watch7,8" : "iPhone18,3",
            isWatch: watch,
            activeKcal: active,
            basalKcal: basal,
            exerciseMinutes: exercise,
            sampleCount: samples
        )
    }

    @Test
    func prefersWatchOverPhone() {
        let phone = source("phone", watch: false, active: 100, basal: 1500, exercise: 20, samples: 50)
        let watch = source("watch", watch: true, active: 300, basal: 1600, exercise: 40, samples: 100)
        let result = HealthEnergySourceSelector().select(from: [phone, watch], preferredSourceID: nil)
        #expect(result.activeSource?.id == "watch")
        #expect(result.basalSource?.id == "watch")
        #expect(result.exerciseSource?.id == "watch")
    }

    @Test
    func selectsWatchWithHighestCoverage() {
        let oldWatch = source("old-watch", watch: true, active: 120, basal: 1500, exercise: 15, samples: 30)
        let newWatch = source("new-watch", watch: true, active: 110, basal: 1550, exercise: 20, samples: 80)
        let result = HealthEnergySourceSelector().select(from: [oldWatch, newWatch], preferredSourceID: nil)
        #expect(result.activeSource?.id == "new-watch")
    }

    @Test
    func fallsBackToPhoneWithoutWatch() {
        let phone = source("phone", watch: false, active: 90, basal: 1450, exercise: 12, samples: 40)
        let result = HealthEnergySourceSelector().select(from: [phone], preferredSourceID: nil)
        #expect(result.activeSource?.id == "phone")
        #expect(result.coverageNote?.contains("未检测到 Apple Watch") == true)
    }

    @Test
    func manualSourceDoesNotFallBackWhenMetricMissing() {
        let watch = source("watch", watch: true, active: 250, basal: 1500, exercise: nil, samples: 80)
        let phone = source("phone", watch: false, active: 100, basal: 1400, exercise: 20, samples: 60)
        let result = HealthEnergySourceSelector().select(from: [watch, phone], preferredSourceID: "watch")
        #expect(result.activeSource?.id == "watch")
        #expect(result.exerciseSource == nil)
    }

    @Test
    func noSourcesReturnsMissingValues() {
        let result = HealthEnergySourceSelector().select(from: [], preferredSourceID: nil)
        #expect(result.activeSource == nil)
        #expect(result.basalSource == nil)
        #expect(result.exerciseSource == nil)
    }

    @Test
    func exerciseTimeIsNotPartOfEnergyTotal() {
        let summary = EnergyDaySummary(dayKey: "2026-10-17", activeKcal: 300, basalKcal: 1500, exerciseMinutes: 45)
        #expect(summary.totalKcal == 1800)
        #expect(summary.exerciseMinutes == 45)
    }
}
