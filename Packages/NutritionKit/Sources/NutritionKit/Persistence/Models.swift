import Foundation
import SwiftData

@Model
public final class DiaryEntryRecord {
    public var id: UUID = UUID()
    public var sessionID: UUID = UUID()
    public var dayKey: String = ""
    public var occurredAt: Date = Date()
    public var payload: Data = Data()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date?

    public init(id: UUID, sessionID: UUID, dayKey: String, occurredAt: Date, payload: Data, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.dayKey = dayKey
        self.occurredAt = occurredAt
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
public final class EnergyDayRecord {
    public var id: UUID = UUID()
    public var dayKey: String = ""
    public var payload: Data = Data()
    public var fetchedAt: Date = Date()
    public var deletedAt: Date?

    public init(id: UUID, dayKey: String, payload: Data, fetchedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.dayKey = dayKey
        self.payload = payload
        self.fetchedAt = fetchedAt
        self.deletedAt = deletedAt
    }
}

@Model
public final class GoalRecord {
    public var id: UUID = UUID()
    public var effectiveDayKey: String = ""
    public var targetBalanceKcal: Double = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date?

    public init(id: UUID = UUID(), effectiveDayKey: String, targetBalanceKcal: Double, createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id
        self.effectiveDayKey = effectiveDayKey
        self.targetBalanceKcal = targetBalanceKcal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
public final class SavedFoodRecord {
    public var id: UUID = UUID()
    public var payload: Data = Data()
    public var updatedAt: Date = Date()
    public var deletedAt: Date?

    public init(id: UUID, payload: Data, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.payload = payload
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
public final class SavedCompositeFoodRecord {
    public var id: UUID = UUID()
    public var payload: Data = Data()
    public var updatedAt: Date = Date()
    public var deletedAt: Date?

    public init(id: UUID, payload: Data, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.payload = payload
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
public final class ConflictCopyRecord {
    public var id: UUID = UUID()
    public var recordKind: String = ""
    public var payloadJSON: String = ""
    public var createdAt: Date = Date()
    public var resolvedAt: Date?

    public init(id: UUID = UUID(), recordKind: String, payloadJSON: String, createdAt: Date = .now, resolvedAt: Date? = nil) {
        self.id = id
        self.recordKind = recordKind
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

@Model
public final class SyncMetadataRecord {
    @Attribute(.unique) public var recordKey: String = ""
    public var lastSyncedPayload: Data = Data()
    public var lastSyncedUpdatedAt: Date = Date()
    public var lastSyncedDeletedAt: Date?
    public var syncedAt: Date = Date()

    public init(recordKey: String, lastSyncedPayload: Data, lastSyncedUpdatedAt: Date, lastSyncedDeletedAt: Date? = nil, syncedAt: Date = .now) {
        self.recordKey = recordKey
        self.lastSyncedPayload = lastSyncedPayload
        self.lastSyncedUpdatedAt = lastSyncedUpdatedAt
        self.lastSyncedDeletedAt = lastSyncedDeletedAt
        self.syncedAt = syncedAt
    }
}

public enum NutritionStoreFactory {
    public static let schema = Schema([
        DiaryEntryRecord.self,
        EnergyDayRecord.self,
        SavedFoodRecord.self,
        SavedCompositeFoodRecord.self,
        GoalRecord.self,
        ConflictCopyRecord.self,
        SyncMetadataRecord.self
    ])

    public static var defaultStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NutritionDiary.store", isDirectory: false)
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            let configuration = ModelConfiguration(
                "NutritionDiary",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        let url = defaultStoreURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // CloudKit synchronization is implemented by CKSyncEngine. SwiftData's
        // automatic CloudKit integration must stay disabled because it does not
        // support the unique constraint on SyncMetadataRecord.recordKey.
        let configuration = ModelConfiguration(
            "NutritionDiary",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Removes only the SwiftData store. Callers must separately confirm the reset and delete photos.
    public static func resetDefaultStore() throws {
        let fileManager = FileManager.default
        let url = defaultStoreURL
        for candidate in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }
}
