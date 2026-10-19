import Foundation
import NutritionKit

@MainActor
extension AppModel {
    func startCloudSync() async {
        await refreshCloudState()
        guard let cloudSync else { return }
        do {
            cloudSyncState = try await cloudSync.synchronize()
            await loadCloudBackedData()
        } catch {
            // Initial sync failures are represented by the state card; they must
            // never prevent the local diary from opening or being edited.
            await refreshCloudState()
        }
    }

    func refreshCloudState() async {
        guard let cloudSync else {
            cloudSyncState = .localOnly
            return
        }
        cloudSyncState = await cloudSync.currentState()
    }

    func synchronizeCloud(showErrors: Bool = false) async {
        guard let cloudSync else { return }
        do {
            cloudSyncState = try await cloudSync.synchronize()
            await loadCloudBackedData()
        } catch {
            await refreshCloudState()
            if showErrors {
                errorMessage = localizedApplicationError(error, language: effectiveLanguage)
            }
        }
    }

    func confirmCloudAccount() async {
        guard let cloudSync else { return }
        do {
            cloudSyncState = try await cloudSync.confirmCurrentAccount()
            await loadCloudBackedData()
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
            await refreshCloudState()
        }
    }

    func deleteCloudData() async throws {
        guard let cloudSync else { return }
        try await cloudSync.deleteCloudData()
        cloudSyncState = await cloudSync.currentState()
    }

    func deleteAllLocalAndCloudData() async throws {
        try await deleteCloudData()
        try await deleteAllLocalData()
    }

    private func loadCloudBackedData() async {
        entries = (try? await store.entries(dayKey: dayKey)) ?? entries
        nutritionSummary = calculator.summarize(
            entries: entries,
            expectedNutrients: NutrientCatalog.definitions.map(\.id)
        )
        compositeFoods = (try? await store.allComposites()) ?? compositeFoods
        balanceGoal = (try? await store.balanceGoal(effectiveOn: dayKey)) ?? balanceGoal
        await refreshCloudState()
    }

    func scheduleCloudSync() {
        guard cloudSync != nil else { return }
        cloudSyncTask?.cancel()
        cloudSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.synchronizeCloud()
        }
    }

}
