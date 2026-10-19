import Foundation

public actor CloudSyncCoordinator: CloudSyncServing {
    private let store: DiaryStore
    private let transport: any CloudSyncTransport
    private let deviceID: String
    private let defaults: UserDefaults
    private let confirmedAccountKey: String
    private let lastSyncKey: String
    private let stateKey: String
    private var state: CloudSyncState
    private var confirmedAccountID: String?

    public init(
        store: DiaryStore,
        transport: any CloudSyncTransport,
        deviceID: String,
        defaults: UserDefaults = .standard,
        namespace: String = "NutritionDiary.cloudSync"
    ) {
        self.store = store
        self.transport = transport
        self.deviceID = deviceID
        self.defaults = defaults
        self.confirmedAccountKey = "\(namespace).confirmedAccountID"
        self.lastSyncKey = "\(namespace).lastSuccessfulSync"
        self.stateKey = "\(namespace).lastState"
        self.confirmedAccountID = defaults.string(forKey: confirmedAccountKey)
        let timestamp = defaults.double(forKey: lastSyncKey)
        if let data = defaults.data(forKey: stateKey),
           let savedState = try? JSONDecoder().decode(CloudSyncState.self, from: data) {
            self.state = savedState
        } else {
            self.state = CloudSyncState(
                lastSuccessfulSync: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
            )
        }
    }

    public func currentState() async -> CloudSyncState {
        await updateCountsInState()
        persistState()
        return state
    }

    public func synchronize() async throws -> CloudSyncState {
        if state.requiresAccountSwitchConfirmation {
            throw CloudSyncError.accountSwitchConfirmationRequired
        }

        state.status = .syncing
        state.lastErrorMessage = nil
        await updateCountsInState()

        do {
            let account = try await transport.account()
            state.account = account
            guard account.status == .available else {
                state.status = .localOnly
                throw CloudSyncError.accountUnavailable
            }

            if let confirmedAccountID,
               let identifier = account.identifier,
               confirmedAccountID != identifier {
                state.requiresAccountSwitchConfirmation = true
                state.status = .requiresConfirmation
                state.lastErrorMessage = CloudSyncError.accountSwitchConfirmationRequired.localizedDescription
                throw CloudSyncError.accountSwitchConfirmationRequired
            }

            let remoteRecords = try await withNetworkRetry {
                try await self.transport.fetchChanges()
            }
            _ = try await store.mergeSyncRecords(remoteRecords)
            let pending = try await store.pendingSyncEnvelopes(deviceID: deviceID)
            state.pendingUploadCount = pending.count
            if !pending.isEmpty {
                try await withNetworkRetry {
                    try await self.transport.push(records: pending)
                }
                try await store.markSyncRecordsSynced(pending)
            }

            if confirmedAccountID == nil, let identifier = account.identifier {
                confirmedAccountID = identifier
                defaults.set(identifier, forKey: confirmedAccountKey)
            }

            let now = Date.now
            state.status = .idle
            state.pendingUploadCount = try await store.pendingSyncEnvelopes(deviceID: deviceID).count
            state.conflictCount = try await store.unresolvedConflictCount()
            state.lastSuccessfulSync = now
            state.lastErrorMessage = nil
            state.requiresAccountSwitchConfirmation = false
            defaults.set(now.timeIntervalSince1970, forKey: lastSyncKey)
            persistState()
            return state
        } catch {
            await updateCountsInState()
            if error is CloudSyncError {
                let syncError = error as! CloudSyncError
                switch syncError {
                case .networkUnavailable, .transportUnavailable:
                    state.status = .offline
                case .accountSwitchConfirmationRequired:
                    state.status = .requiresConfirmation
                case .accountUnavailable:
                    state.status = .localOnly
                case .rejected:
                    state.status = .failed
                }
            } else {
                state.status = .failed
            }
            state.lastErrorMessage = error.localizedDescription
            persistState()
            throw error
        }
    }

    public func confirmCurrentAccount() async throws -> CloudSyncState {
        let account = try await transport.account()
        guard account.status == .available, let identifier = account.identifier else {
            throw CloudSyncError.accountUnavailable
        }
        confirmedAccountID = identifier
        state.account = account
        state.requiresAccountSwitchConfirmation = false
        state.lastErrorMessage = nil
        defaults.set(identifier, forKey: confirmedAccountKey)
        return try await synchronize()
    }

    public func deleteCloudData() async throws {
        state.status = .syncing
        do {
            try await transport.deleteAllData()
            state.pendingUploadCount = 0
            state.lastSuccessfulSync = .now
            state.status = .idle
            state.lastErrorMessage = nil
        } catch {
            state.status = .failed
            state.lastErrorMessage = error.localizedDescription
            persistState()
            throw error
        }
    }

    private func persistState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    private func updateCountsInState() async {
        if let envelopes = try? await store.pendingSyncEnvelopes(deviceID: deviceID) {
            state.pendingUploadCount = envelopes.count
        }
        if let count = try? await store.unresolvedConflictCount() {
            state.conflictCount = count
        }
    }

    private func withNetworkRetry<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as CloudSyncError {
            switch error {
            case .networkUnavailable, .transportUnavailable:
                try await Task.sleep(for: .milliseconds(700))
                return try await operation()
            default:
                throw error
            }
        }
    }
}

public enum CloudSyncDeviceIdentity {
    private static let key = "NutritionDiary.cloudSync.deviceID"

    public static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key) { return existing }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: key)
        return value
    }
}
