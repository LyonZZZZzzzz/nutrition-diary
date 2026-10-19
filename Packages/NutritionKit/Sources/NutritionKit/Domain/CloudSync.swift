import Foundation

public enum SyncRecordKind: String, Codable, CaseIterable, Sendable {
    case diaryEntry
    case savedFood
    case compositeFood
    case energyDay
    case balanceGoal
}

public struct SyncRecordEnvelope: Identifiable, Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let recordKind: SyncRecordKind
    public let recordID: UUID
    public let schemaVersion: Int
    public let payload: Data
    public let updatedAt: Date
    public let deletedAt: Date?
    public let deviceID: String

    public var id: UUID { recordID }
    public var recordKey: String { "\(recordKind.rawValue):\(recordID.uuidString.lowercased())" }

    public init(
        recordKind: SyncRecordKind,
        recordID: UUID,
        schemaVersion: Int = SyncRecordEnvelope.currentSchemaVersion,
        payload: Data,
        updatedAt: Date,
        deletedAt: Date? = nil,
        deviceID: String
    ) {
        self.recordKind = recordKind
        self.recordID = recordID
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.deviceID = deviceID
    }
}

public struct SyncMergeSummary: Codable, Hashable, Sendable {
    public let applied: Int
    public let keptLocal: Int
    public let unchanged: Int
    public let conflicts: Int
    public let tombstones: Int

    public init(applied: Int, keptLocal: Int, unchanged: Int, conflicts: Int, tombstones: Int) {
        self.applied = applied
        self.keptLocal = keptLocal
        self.unchanged = unchanged
        self.conflicts = conflicts
        self.tombstones = tombstones
    }
}

public enum CloudAccountStatus: String, Codable, Hashable, Sendable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case unavailable
}

public struct CloudSyncAccount: Codable, Hashable, Sendable {
    public let status: CloudAccountStatus
    public let identifier: String?
    public let displayName: String?

    public init(status: CloudAccountStatus, identifier: String? = nil, displayName: String? = nil) {
        self.status = status
        self.identifier = identifier
        self.displayName = displayName
    }
}

public enum CloudSyncStatus: String, Codable, Hashable, Sendable {
    case localOnly
    case idle
    case syncing
    case offline
    case requiresConfirmation
    case failed
}

public struct CloudSyncState: Codable, Hashable, Sendable {
    public var status: CloudSyncStatus
    public var account: CloudSyncAccount
    public var pendingUploadCount: Int
    public var conflictCount: Int
    public var lastSuccessfulSync: Date?
    public var lastErrorMessage: String?
    public var requiresAccountSwitchConfirmation: Bool

    public init(
        status: CloudSyncStatus = .localOnly,
        account: CloudSyncAccount = CloudSyncAccount(status: .couldNotDetermine),
        pendingUploadCount: Int = 0,
        conflictCount: Int = 0,
        lastSuccessfulSync: Date? = nil,
        lastErrorMessage: String? = nil,
        requiresAccountSwitchConfirmation: Bool = false
    ) {
        self.status = status
        self.account = account
        self.pendingUploadCount = pendingUploadCount
        self.conflictCount = conflictCount
        self.lastSuccessfulSync = lastSuccessfulSync
        self.lastErrorMessage = lastErrorMessage
        self.requiresAccountSwitchConfirmation = requiresAccountSwitchConfirmation
    }

    public static let localOnly = CloudSyncState()
}

public enum CloudSyncError: Error, LocalizedError, Sendable {
    case networkUnavailable
    case transportUnavailable
    case accountUnavailable
    case rejected(String)
    case accountSwitchConfirmationRequired

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable: "网络不可用，修改已保存在本机并等待重试"
        case .transportUnavailable: "iCloud 同步服务当前不可用"
        case .accountUnavailable: "未登录 iCloud 或 iCloud Drive 不可用"
        case .rejected(let message): message
        case .accountSwitchConfirmationRequired: "检测到 iCloud 账号变化，需要确认后才能继续同步"
        }
    }
}

public protocol CloudSyncServing: Sendable {
    func currentState() async -> CloudSyncState
    func synchronize() async throws -> CloudSyncState
    func confirmCurrentAccount() async throws -> CloudSyncState
    func deleteCloudData() async throws
}

public protocol CloudSyncTransport: Sendable {
    func account() async throws -> CloudSyncAccount
    func fetchChanges() async throws -> [SyncRecordEnvelope]
    func push(records: [SyncRecordEnvelope]) async throws
    func deleteAllData() async throws
}

public enum StableSyncIdentifier {
    public static func energyDay(_ dayKey: String) -> UUID { uuid("energyDay:\(dayKey)") }
    public static func balanceGoal(_ dayKey: String) -> UUID { uuid("balanceGoal:\(dayKey)") }

    public static func uuid(_ value: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in value.utf8.enumerated() {
            bytes[index % 16] = bytes[index % 16] &+ byte &+ UInt8(truncatingIfNeeded: index)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
