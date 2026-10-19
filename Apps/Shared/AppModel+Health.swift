import Foundation
import NutritionKit

@MainActor
extension AppModel {
    func requestHealthAuthorization() async {
        guard let energyReader else { return }
        do {
            try await energyReader.requestAuthorization()
            healthAuthorizationRequested = true
            healthStatus = .authorizationRequested
            await refreshHealthData()
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    func startHealthObservation() {
        guard !hasStartedHealthObservation, let healthObserver else { return }
        hasStartedHealthObservation = true
        healthObserver.startObserving { [weak self] in
            await self?.scheduleHealthRefresh()
        }
    }

    func handleAppBecameActive() async {
        await refreshHealthData()
    }

    func refreshHealthData() async {
        guard let energyReader else {
            if let stored = try? await store.energy(dayKey: dayKey) {
                energySummary = stored
                healthLastUpdatedAt = stored.fetchedAt
            }
            recalculateBalance()
            return
        }
        do {
            let result = try await energyReader.readDailyEnergy(
                for: selectedDate,
                timeZone: .current,
                preferredSourceID: preferredHealthSourceID
            )
            try await store.saveEnergy(result.summary)
            energySummary = result.summary
            healthSources = result.sources
            healthLastUpdatedAt = result.summary.fetchedAt
            healthStatus = result.sources.isEmpty ? .noData : .connected(result.sources.count)
        } catch HealthReadError.authorizationRequired {
            energySummary = try? await store.energy(dayKey: dayKey)
            healthSources = []
            healthStatus = .notAuthorized
        } catch {
            energySummary = try? await store.energy(dayKey: dayKey)
            healthStatus = .readFailed
            let detail = localizedApplicationError(error, language: effectiveLanguage)
            errorMessage = localized("读取健康能量失败：\(detail)", "Failed to read health energy: \(detail)")
        }
        recalculateBalance()
    }

    func setPreferredHealthSource(_ sourceID: String?) async {
        preferredHealthSourceID = sourceID
        if let sourceID {
            UserDefaults.standard.set(sourceID, forKey: Self.preferredHealthSourceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.preferredHealthSourceKey)
        }
        await refreshHealthData()
    }

    private func scheduleHealthRefresh() {
        healthRefreshTask?.cancel()
        healthRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.refreshHealthData()
        }
    }

    func syncHealth(dayKey: String, mealType: MealType) async throws {
        guard let healthWriter else { return }
        let mealEntries = try await store.entries(dayKey: dayKey).filter { $0.mealType == mealType }
        try await healthWriter.syncMeal(dayKey: dayKey, mealType: mealType, entries: mealEntries, allowEstimated: allowEstimatedHealthWrites)
    }

    func recalculateBalance() {
        let goalValue = balanceGoal?.targetBalanceKcal
        energyBalance = energyCalculator.calculate(
            intakeKcal: calories,
            activeKcal: energySummary?.activeKcal,
            basalKcal: energySummary?.basalKcal,
            balanceGoalKcal: goalValue
        )
    }

}
