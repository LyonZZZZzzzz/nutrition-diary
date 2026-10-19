import Foundation
import Testing
@testable import NutritionKit

struct BackupRestoreTests {
    private func entry(id: UUID = UUID(), foodName: String, updatedAt: Date, energy: Double) -> DiaryEntry {
        DiaryEntry(
            id: id,
            dayKey: "2026-10-17",
            occurredAt: updatedAt,
            mealType: .lunch,
            foodID: UUID(),
            foodName: foodName,
            foodNameZh: foodName,
            foodNameEn: foodName,
            quantityDescription: "100 克",
            quantityDescriptionZh: "100 克",
            quantityDescriptionEn: "100 g",
            normalizedAmount: 100,
            normalizedUnit: .gram,
            nutrients: [
                NutrientMeasurement(nutrient: NutrientCatalog.energy, value: Decimal(energy), unit: .kilocalorie, status: .complete, source: .manual)
            ],
            source: .manual,
            updatedAt: updatedAt
        )
    }

    @Test
    func mediaBackupRoundTripsJSONAndPhotos() throws {
        let service = MediaBackupService()
        let json = Data("{\"schemaVersion\":2}".utf8)
        let photos = ["meal-1.img": Data([0x01, 0x02, 0x03]), "meal-2.img": Data([0xAA, 0xBB])]
        let archive = try service.make(backupJSON: json, photos: photos)
        let restored = try service.read(archive)
        #expect(restored.backupJSON == json)
        #expect(restored.photos == photos)
    }

    @Test
    func jsonBackupIncludesCustomFoodsAndComposites() throws {
        let food = FoodItem(name: "自定义食物", aliases: ["测试"], category: "其他", nutrients: [])
        let composite = CompositeFoodDefinition(name: "自制饮品", mode: .direct, directNutrients: [
            NutrientMeasurement(nutrient: NutrientCatalog.energy, value: 100, unit: .kilocalorie, status: .estimated, source: .manual)
        ])
        let service = DataTransferService()
        let data = try service.makeJSONBackup(entries: [], energyDays: [], goals: [], savedFoods: [food], compositeFoods: [composite])
        let decoded = try service.decodeJSONBackup(data)
        #expect(decoded.schemaVersion == 2)
        #expect(decoded.savedFoods == [food])
        #expect(decoded.compositeFoods.count == 1)
        #expect(decoded.compositeFoods.first?.id == composite.id)
        #expect(decoded.compositeFoods.first?.name == composite.name)
        #expect(decoded.compositeFoods.first?.directNutrients == composite.directNutrients)
    }

    @Test
    func mergeRestoreAddsNewerAndPreservesLocalNewerEntries() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        let sharedID = UUID()
        let local = entry(id: sharedID, foodName: "本地较新", updatedAt: Date(timeIntervalSince1970: 200), energy: 200)
        try await store.save(local)
        let olderRemote = entry(id: sharedID, foodName: "备份较旧", updatedAt: Date(timeIntervalSince1970: 100), energy: 100)
        let newID = UUID()
        let added = entry(id: newID, foodName: "备份新增", updatedAt: Date(timeIntervalSince1970: 300), energy: 300)
        let backup = NutritionBackup(entries: [olderRemote, added], energyDays: [], balanceGoals: [])
        let summary = try await store.restore(backup, mode: .merge)
        let entries = try await store.allEntries()
        #expect(summary.added == 1)
        #expect(summary.conflicts == 1)
        #expect(entries.contains { $0.id == local.id && $0.foodName == "本地较新" })
        #expect(entries.contains { $0.id == newID })
    }

    @Test
    func replaceRestoreClearsExistingLocalEntries() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        try await store.save(entry(foodName: "旧数据", updatedAt: Date(timeIntervalSince1970: 100), energy: 100))
        let replacement = entry(foodName: "替换数据", updatedAt: Date(timeIntervalSince1970: 200), energy: 250)
        let summary = try await store.restore(
            NutritionBackup(entries: [replacement], energyDays: [], balanceGoals: []),
            mode: .replace
        )
        let entries = try await store.allEntries()
        #expect(summary.mode == .replace)
        #expect(entries.count == 1)
        #expect(entries.first?.foodName == "替换数据")
    }

    @Test
    func deleteAllLocalDataRemovesEveryRecord() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        try await store.save(entry(foodName: "待删除", updatedAt: .now, energy: 100))
        try await store.saveBalanceGoal(BalanceGoal(effectiveDayKey: "2026-10-17", targetBalanceKcal: 0))
        try await store.deleteAllLocalData()
        #expect(try await store.allEntries().isEmpty)
        #expect(try await store.balanceGoal(effectiveOn: "2026-10-17") == nil)
    }
}
