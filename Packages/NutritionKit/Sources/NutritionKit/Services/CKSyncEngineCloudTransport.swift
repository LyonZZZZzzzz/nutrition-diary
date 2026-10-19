import CloudKit
import Foundation

/// CloudKit transport backed by CKSyncEngine. The engine owns its change token and
/// pending queue; the payload contract remains in NutritionKit so it can be tested
/// without contacting CloudKit.
public actor CKSyncEngineCloudTransport: CloudSyncTransport, CKSyncEngineDelegate {
    private let containerIdentifier: String
    private let zoneName: String
    private let stateFileURL: URL
    private let recordType = "NutritionSyncRecord"
    private let zoneID: CKRecordZone.ID
    private var engine: CKSyncEngine?
    private var pendingRecords: [CKRecord.ID: CKRecord] = [:]
    private var fetchedRecords: [SyncRecordEnvelope] = []
    private var accountChangeSeen = false

    public init(
        containerIdentifier: String = "iCloud.com.lyonzhu.NutritionDiary",
        zoneName: String = "NutritionDiary",
        stateFileURL: URL? = nil
    ) {
        self.containerIdentifier = containerIdentifier
        self.zoneName = zoneName
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.stateFileURL = stateFileURL ?? base.appendingPathComponent("CloudSyncState.plist")
        self.zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    public func account() async throws -> CloudSyncAccount {
        let container = CKContainer(identifier: containerIdentifier)
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                let identity = try? await container.userRecordID()
                return CloudSyncAccount(status: .available, identifier: identity?.recordName)
            case .noAccount:
                return CloudSyncAccount(status: .noAccount)
            case .restricted:
                return CloudSyncAccount(status: .restricted)
            case .couldNotDetermine, .temporarilyUnavailable:
                return CloudSyncAccount(status: .couldNotDetermine)
            @unknown default:
                return CloudSyncAccount(status: .couldNotDetermine)
            }
        } catch {
            throw CloudSyncError.transportUnavailable
        }
    }

    public func fetchChanges() async throws -> [SyncRecordEnvelope] {
        do {
            let engine = try await ensureEngine()
            fetchedRecords.removeAll(keepingCapacity: true)
            try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
            return fetchedRecords
        } catch let error as CloudSyncError {
            throw error
        } catch {
            throw mapCloudKitError(error)
        }
    }

    public func push(records: [SyncRecordEnvelope]) async throws {
        guard !records.isEmpty else { return }
        do {
            let engine = try await ensureEngine()
            let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
            let envelopesByID = Dictionary(uniqueKeysWithValues: records.map { envelope in
                (CKRecord.ID(recordName: envelope.recordKey, zoneID: zoneID), envelope)
            })
            let ids = Array(envelopesByID.keys)
            let existingResults = try await database.records(for: ids)
            for id in ids {
                guard let envelope = envelopesByID[id] else { continue }
                let record: CKRecord
                if let result = existingResults[id] {
                    switch result {
                    case .success(let existing):
                        record = existing
                    case .failure(let error):
                        if let ckError = error as? CKError, ckError.code == .unknownItem {
                            record = CKRecord(recordType: recordType, recordID: id)
                        } else {
                            throw error
                        }
                    }
                } else {
                    record = CKRecord(recordType: recordType, recordID: id)
                }
                apply(envelope, to: record)
                pendingRecords[id] = record
            }
            engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord($0) })
            try await engine.sendChanges(.init(scope: .recordIDs(ids)))
        } catch let error as CloudSyncError {
            throw error
        } catch {
            throw mapCloudKitError(error)
        }
    }

    public func deleteAllData() async throws {
        do {
            let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
            _ = try await database.deleteRecordZone(withID: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            return
        } catch {
            throw mapCloudKitError(error)
        }
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            persist(update.stateSerialization)
        case .accountChange:
            accountChangeSeen = true
        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                if let envelope = decode(modification.record),
                   !fetchedRecords.contains(where: { $0.recordKey == envelope.recordKey }) {
                    fetchedRecords.append(envelope)
                }
            }
        case .sentRecordZoneChanges(let changes):
            for record in changes.savedRecords {
                pendingRecords[record.recordID] = nil
            }
        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let records = pending.compactMap { change -> CKRecord? in
            guard case .saveRecord(let id) = change else { return nil }
            return pendingRecords[id]
        }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records, atomicByZone: false)
    }

    public func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        .init(scope: .zoneIDs([zoneID]))
    }

    private func ensureEngine() async throws -> CKSyncEngine {
        if let engine { return engine }
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        do {
            _ = try await database.save(CKRecordZone(zoneName: zoneName))
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // A rejected zone save usually means the zone already exists, but
            // serverRejectedRequest can also represent a container/schema issue.
            // Verify the zone explicitly before treating the save as successful.
            do {
                _ = try await database.recordZone(for: zoneID)
            } catch {
                throw mapCloudKitError(error)
            }
        } catch {
            throw mapCloudKitError(error)
        }

        let serialization = loadSerialization()
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: serialization,
            delegate: self
        )
        configuration.automaticallySync = false
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        return engine
    }

    private func apply(_ envelope: SyncRecordEnvelope, to record: CKRecord) {
        record["recordKind"] = envelope.recordKind.rawValue as CKRecordValue
        // `recordID` is reserved by CKRecord and cannot be used as a custom key.
        record["businessRecordID"] = envelope.recordID.uuidString as CKRecordValue
        record["schemaVersion"] = NSNumber(value: envelope.schemaVersion)
        record["payload"] = envelope.payload as NSData
        record["updatedAt"] = envelope.updatedAt as NSDate
        record["deviceID"] = envelope.deviceID as CKRecordValue
        if let deletedAt = envelope.deletedAt {
            record["deletedAt"] = deletedAt as NSDate
        }
    }

    private func decode(_ record: CKRecord) -> SyncRecordEnvelope? {
        guard let kindValue = record["recordKind"] as? String,
              let kind = SyncRecordKind(rawValue: kindValue),
              let idValue = (record["businessRecordID"] ?? record["recordID"]) as? String,
              let id = UUID(uuidString: idValue),
              let payload = record["payload"] as? Data,
              let updatedAt = record["updatedAt"] as? Date,
              let deviceID = record["deviceID"] as? String else {
            return nil
        }
        let schemaVersion = record["schemaVersion"] as? Int ?? SyncRecordEnvelope.currentSchemaVersion
        let deletedAt = record["deletedAt"] as? Date
        return SyncRecordEnvelope(
            recordKind: kind,
            recordID: id,
            schemaVersion: schemaVersion,
            payload: payload,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            deviceID: deviceID
        )
    }

    private func persist(_ serialization: CKSyncEngine.State.Serialization) {
        do {
            let data = try PropertyListEncoder().encode(serialization)
            try FileManager.default.createDirectory(at: stateFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: stateFileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            // A failed state persistence must not corrupt local records. The next
            // engine launch will recover with a full fetch.
        }
    }

    private func loadSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateFileURL) else { return nil }
        return try? PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func mapCloudKitError(_ error: Error) -> CloudSyncError {
        guard let error = error as? CKError else {
            return .transportUnavailable
        }
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return .networkUnavailable
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .accountUnavailable
        case .partialFailure:
            let partial = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Any]
            let details = partial?.values.map { String(describing: $0) }.sorted().joined(separator: " | ")
            return .rejected(details?.isEmpty == false ? details! : error.localizedDescription)
        default:
            return .rejected("CloudKit \(error.code.rawValue): \(error.localizedDescription). UserInfo: \(error.userInfo)")
        }
    }
}
