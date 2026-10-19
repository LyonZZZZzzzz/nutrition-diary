import Foundation
import Testing
@testable import NutritionKit

private actor FakeCloudSyncTransport: CloudSyncTransport {
    var accountValue: CloudSyncAccount
    var remoteRecords: [SyncRecordEnvelope]
    var pushedRecords: [SyncRecordEnvelope] = []
    var fetchError: CloudSyncError?
    var pushError: CloudSyncError?

    init(
        account: CloudSyncAccount = CloudSyncAccount(status: .available, identifier: "icloud-user-a"),
        remoteRecords: [SyncRecordEnvelope] = []
    ) {
        self.accountValue = account
        self.remoteRecords = remoteRecords
    }

    func account() async throws -> CloudSyncAccount { accountValue }

    func fetchChanges() async throws -> [SyncRecordEnvelope] {
        if let fetchError { throw fetchError }
        return remoteRecords
    }

    func push(records: [SyncRecordEnvelope]) async throws {
        if let pushError { throw pushError }
        pushedRecords = records
    }

    func deleteAllData() async throws {
        remoteRecords = []
        pushedRecords = []
    }

    func set(account: CloudSyncAccount) { accountValue = account }
    func set(fetchError: CloudSyncError?) { self.fetchError = fetchError }
    func set(pushError: CloudSyncError?) { self.pushError = pushError }
    func set(remoteRecords: [SyncRecordEnvelope]) { self.remoteRecords = remoteRecords }
    func pushed() -> [SyncRecordEnvelope] { pushedRecords }
}

@Suite(.serialized)
struct CloudSyncTests {
    private func entry(
        id: UUID = UUID(),
        name: String,
        updatedAt: Date,
        mealType: MealType = .lunch,
        deletedAt: Date? = nil
    ) -> DiaryEntry {
        DiaryEntry(
            id: id,
            dayKey: "2026-10-17",
            occurredAt: updatedAt,
            mealType: mealType,
            foodID: UUID(),
            foodName: name,
            foodNameZh: name,
            foodNameEn: name,
            quantityDescription: "100 克",
            quantityDescriptionZh: "100 克",
            quantityDescriptionEn: "100 g",
            normalizedAmount: 100,
            normalizedUnit: .gram,
            nutrients: [
                NutrientMeasurement(
                    nutrient: NutrientCatalog.energy,
                    value: 200,
                    unit: .kilocalorie,
                    status: .complete,
                    source: .manual
                )
            ],
            source: .manual,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    private func envelope(for entry: DiaryEntry, deviceID: String = "remote-device") throws -> SyncRecordEnvelope {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return SyncRecordEnvelope(
            recordKind: .diaryEntry,
            recordID: entry.id,
            payload: try encoder.encode(entry),
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt,
            deviceID: deviceID
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "CloudSyncTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    @Test
    func firstSyncPushesLocalRecordsAndMarksThemSynced() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        try await store.save(entry(name: "本地午餐", updatedAt: Date(timeIntervalSince1970: 200)))
        let transport = FakeCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(
            store: store,
            transport: transport,
            deviceID: "iphone-17",
            defaults: try makeDefaults()
        )

        let state = try await coordinator.synchronize()
        #expect(state.status == .idle)
        #expect(state.pendingUploadCount == 0)
        let pushed = await transport.pushed()
        #expect(pushed.count == 1)
        #expect(pushed.first?.recordKind == .diaryEntry)
        #expect(pushed.first?.recordKey.hasPrefix("diaryEntry:") == true)
    }

    @Test
    func newerRemoteRecordWinsAndOlderLocalValueBecomesConflict() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        let id = UUID()
        let local = entry(id: id, name: "本机较旧", updatedAt: Date(timeIntervalSince1970: 100))
        try await store.save(local)
        let remoteEntry = entry(id: id, name: "云端较新", updatedAt: Date(timeIntervalSince1970: 300))
        let transport = FakeCloudSyncTransport(remoteRecords: [try envelope(for: remoteEntry)])
        let coordinator = CloudSyncCoordinator(
            store: store,
            transport: transport,
            deviceID: "iphone-17",
            defaults: try makeDefaults()
        )

        let state = try await coordinator.synchronize()
        let entries = try await store.allEntries()
        let conflicts = try await store.unresolvedConflicts()
        #expect(entries.first?.foodName == "云端较新")
        #expect(conflicts.count == 1)
        #expect(state.conflictCount == 1)
    }

    @Test
    func tombstoneRemovesRecordFromStatisticsAndIsIdempotent() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        let id = UUID()
        let local = entry(id: id, name: "待删除", updatedAt: Date(timeIntervalSince1970: 100))
        try await store.save(local)
        let tombstone = entry(
            id: id,
            name: "待删除",
            updatedAt: Date(timeIntervalSince1970: 200),
            deletedAt: Date(timeIntervalSince1970: 200)
        )
        let transport = FakeCloudSyncTransport(remoteRecords: [try envelope(for: tombstone)])
        let coordinator = CloudSyncCoordinator(
            store: store,
            transport: transport,
            deviceID: "mac",
            defaults: try makeDefaults()
        )

        _ = try await coordinator.synchronize()
        #expect(try await store.allEntries().isEmpty)
        let conflictCount = try await store.unresolvedConflicts().count
        _ = try await coordinator.synchronize()
        #expect(try await store.allEntries().isEmpty)
        #expect(try await store.unresolvedConflicts().count == conflictCount)
        #expect(try await store.pendingSyncEnvelopes(deviceID: "mac").isEmpty)
    }

    @Test
    func movedEntryMergesBySameIDWithoutCreatingDuplicate() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        let id = UUID()
        let breakfast = entry(
            id: id,
            name: "鸡蛋",
            updatedAt: Date(timeIntervalSince1970: 100),
            mealType: .breakfast
        )
        try await store.save(breakfast)
        let dinner = breakfast.moved(
            to: .dinner,
            occurredAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let summary = try await store.mergeSyncRecords([try envelope(for: dinner)])
        let entries = try await store.allEntries()

        #expect(summary.applied == 1)
        #expect(entries.count == 1)
        #expect(entries.first?.id == id)
        #expect(entries.first?.mealType == .dinner)
    }

    @Test
    func networkFailureLeavesPendingUploadAndOfflineState() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        try await store.save(entry(name: "离线晚餐", updatedAt: .now))
        let transport = FakeCloudSyncTransport()
        await transport.set(fetchError: .networkUnavailable)
        let coordinator = CloudSyncCoordinator(
            store: store,
            transport: transport,
            deviceID: "iphone-17",
            defaults: try makeDefaults()
        )

        await #expect(throws: CloudSyncError.self) {
            _ = try await coordinator.synchronize()
        }
        let state = await coordinator.currentState()
        #expect(state.status == .offline)
        #expect(state.pendingUploadCount == 1)

        await transport.set(fetchError: nil)
        let recovered = try await coordinator.synchronize()
        #expect(recovered.status == .idle)
        #expect(recovered.pendingUploadCount == 0)
    }

    @Test
    func accountSwitchRequiresExplicitConfirmationBeforeUploading() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        try await store.save(entry(name: "账号数据", updatedAt: .now))
        let transport = FakeCloudSyncTransport(
            account: CloudSyncAccount(status: .available, identifier: "account-a")
        )
        let coordinator = CloudSyncCoordinator(
            store: store,
            transport: transport,
            deviceID: "iphone-17",
            defaults: try makeDefaults()
        )
        _ = try await coordinator.synchronize()

        try await store.save(entry(name: "切换后新增", updatedAt: .now.addingTimeInterval(10)))
        await transport.set(account: CloudSyncAccount(status: .available, identifier: "account-b"))
        await #expect(throws: CloudSyncError.self) {
            _ = try await coordinator.synchronize()
        }
        let blocked = await coordinator.currentState()
        #expect(blocked.requiresAccountSwitchConfirmation)
        #expect(blocked.status == .requiresConfirmation)

        let confirmed = try await coordinator.confirmCurrentAccount()
        #expect(confirmed.status == .idle)
        #expect(!confirmed.requiresAccountSwitchConfirmation)
    }
}
