import Foundation
import SwiftData

@ModelActor
public actor DiaryStore {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public func restore(_ backup: NutritionBackup, mode: BackupRestoreMode) throws -> BackupRestoreSummary {
        if mode == .replace {
            try deleteAllLocalData()
            for entry in backup.entries { try save(entry) }
            for energy in backup.energyDays { try saveEnergy(energy) }
            for goal in backup.balanceGoals { try saveBalanceGoal(goal) }
            for food in backup.savedFoods { try saveFood(food) }
            for composite in backup.compositeFoods { try saveComposite(composite) }
            for conflict in backup.conflictCopies {
                modelContext.insert(ConflictCopyRecord(
                    id: conflict.id,
                    recordKind: conflict.recordKind,
                    payloadJSON: conflict.payloadJSON,
                    createdAt: conflict.createdAt
                ))
            }
            try modelContext.save()
            let total = backup.entries.count + backup.energyDays.count + backup.balanceGoals.count
                + backup.savedFoods.count + backup.compositeFoods.count + backup.conflictCopies.count
            return BackupRestoreSummary(added: total, updated: 0, unchanged: 0, conflicts: 0, mode: .replace)
        }

        var added = 0
        var updated = 0
        var unchanged = 0
        var conflicts = 0

        let localEntries = Dictionary(uniqueKeysWithValues: try allEntries().map { ($0.id, $0) })
        for entry in backup.entries {
            guard let local = localEntries[entry.id] else {
                try save(entry)
                added += 1
                continue
            }
            if local == entry {
                unchanged += 1
            } else if entry.updatedAt > local.updatedAt {
                try save(entry)
                updated += 1
            } else {
                try saveConflict(kind: "diaryEntry", payloadJSON: try jsonString(entry))
                conflicts += 1
            }
        }

        let localEnergy = Dictionary(uniqueKeysWithValues: try allEnergy().map { ($0.dayKey, $0) })
        for energy in backup.energyDays {
            guard let local = localEnergy[energy.dayKey] else {
                try saveEnergy(energy)
                added += 1
                continue
            }
            if local == energy {
                unchanged += 1
            } else if energy.fetchedAt > local.fetchedAt {
                try saveEnergy(energy)
                updated += 1
            } else {
                try saveConflict(kind: "energyDay", payloadJSON: try jsonString(energy))
                conflicts += 1
            }
        }

        let goalRecords = try modelContext.fetch(FetchDescriptor<GoalRecord>())
        let localGoals = Dictionary(uniqueKeysWithValues: goalRecords.map {
            ($0.effectiveDayKey, BalanceGoal(effectiveDayKey: $0.effectiveDayKey, targetBalanceKcal: $0.targetBalanceKcal))
        })
        for goal in backup.balanceGoals {
            guard let local = localGoals[goal.effectiveDayKey] else {
                try saveBalanceGoal(goal)
                added += 1
                continue
            }
            if local == goal {
                unchanged += 1
            } else {
                try saveConflict(kind: "balanceGoal", payloadJSON: try jsonString(goal))
                conflicts += 1
            }
        }

        let localFoods = Dictionary(uniqueKeysWithValues: try allFoods().map { ($0.id, $0) })
        for food in backup.savedFoods {
            if let local = localFoods[food.id] {
                if local == food { unchanged += 1 }
                else { try saveConflict(kind: "savedFood", payloadJSON: try jsonString(food)); conflicts += 1 }
            } else {
                try saveFood(food)
                added += 1
            }
        }

        let localComposites = Dictionary(uniqueKeysWithValues: try allComposites().map { ($0.id, $0) })
        for composite in backup.compositeFoods {
            if let local = localComposites[composite.id] {
                if local == composite { unchanged += 1 }
                else { try saveConflict(kind: "compositeFood", payloadJSON: try jsonString(composite)); conflicts += 1 }
            } else {
                try saveComposite(composite)
                added += 1
            }
        }

        let existingConflictPayloads = Set(try unresolvedConflicts().map { "\($0.recordKind)|\($0.payloadJSON)" })
        for conflict in backup.conflictCopies where !existingConflictPayloads.contains("\(conflict.recordKind)|\(conflict.payloadJSON)") {
            modelContext.insert(ConflictCopyRecord(
                id: conflict.id,
                recordKind: conflict.recordKind,
                payloadJSON: conflict.payloadJSON,
                createdAt: conflict.createdAt
            ))
            added += 1
        }
        try modelContext.save()

        return BackupRestoreSummary(added: added, updated: updated, unchanged: unchanged, conflicts: conflicts, mode: .merge)
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public func deleteAllLocalData() throws {
        for item in try modelContext.fetch(FetchDescriptor<DiaryEntryRecord>()) { modelContext.delete(item) }
        for item in try modelContext.fetch(FetchDescriptor<EnergyDayRecord>()) { modelContext.delete(item) }
        for item in try modelContext.fetch(FetchDescriptor<SavedFoodRecord>()) { modelContext.delete(item) }
        for item in try modelContext.fetch(FetchDescriptor<SavedCompositeFoodRecord>()) { modelContext.delete(item) }
        for item in try modelContext.fetch(FetchDescriptor<GoalRecord>()) { modelContext.delete(item) }
        for item in try modelContext.fetch(FetchDescriptor<ConflictCopyRecord>()) { modelContext.delete(item) }
        for item in try modelContext.fetch(FetchDescriptor<SyncMetadataRecord>()) { modelContext.delete(item) }
        try modelContext.save()
    }

    public func save(_ entry: DiaryEntry) throws {
        let descriptor = FetchDescriptor<DiaryEntryRecord>()
        let records = try modelContext.fetch(descriptor)
        let data = try encoder.encode(entry)
        if let record = records.first(where: { $0.id == entry.id }) {
            record.sessionID = entry.sessionID
            record.dayKey = entry.dayKey
            record.occurredAt = entry.occurredAt
            record.payload = data
            record.updatedAt = entry.updatedAt
            record.deletedAt = entry.deletedAt
        } else {
            modelContext.insert(DiaryEntryRecord(
                id: entry.id,
                sessionID: entry.sessionID,
                dayKey: entry.dayKey,
                occurredAt: entry.occurredAt,
                payload: data,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                deletedAt: entry.deletedAt
            ))
        }
        try modelContext.save()
    }

    public func delete(id: UUID, at date: Date = .now) throws {
        let descriptor = FetchDescriptor<DiaryEntryRecord>()
        let records = try modelContext.fetch(descriptor)
        guard let record = records.first(where: { $0.id == id }) else { return }
        record.deletedAt = date
        record.updatedAt = date
        if var entry = try? decoder.decode(DiaryEntry.self, from: record.payload) {
            entry = DiaryEntry(
                id: entry.id,
                sessionID: entry.sessionID,
                dayKey: entry.dayKey,
                occurredAt: entry.occurredAt,
                timeZoneIdentifier: entry.timeZoneIdentifier,
                mealType: entry.mealType,
                foodID: entry.foodID,
                foodName: entry.foodName,
                foodNameZh: entry.foodNameZh,
                foodNameEn: entry.foodNameEn,
                quantityDescription: entry.quantityDescription,
                quantityDescriptionZh: entry.quantityDescriptionZh,
                quantityDescriptionEn: entry.quantityDescriptionEn,
                normalizedAmount: entry.normalizedAmount,
                normalizedUnit: entry.normalizedUnit,
                nutrients: entry.nutrients,
                source: entry.source,
                photoConfidence: entry.photoConfidence,
                photoFilenames: entry.photoFilenames,
                createdAt: entry.createdAt,
                updatedAt: date,
                deletedAt: date
            )
            record.payload = try encoder.encode(entry)
        }
        try modelContext.save()
    }

    public func entries(dayKey: String) throws -> [DiaryEntry] {
        let descriptor = FetchDescriptor<DiaryEntryRecord>(sortBy: [SortDescriptor(\.occurredAt)])
        return try modelContext.fetch(descriptor)
            .filter { $0.dayKey == dayKey && $0.deletedAt == nil }
            .compactMap { try? decoder.decode(DiaryEntry.self, from: $0.payload) }
    }

    public func allEntries() throws -> [DiaryEntry] {
        let descriptor = FetchDescriptor<DiaryEntryRecord>(sortBy: [SortDescriptor(\.occurredAt)])
        return try modelContext.fetch(descriptor)
            .filter { $0.deletedAt == nil }
            .compactMap { try? decoder.decode(DiaryEntry.self, from: $0.payload) }
    }

    public func saveFood(_ food: FoodItem) throws {
        let data = try encoder.encode(food)
        let descriptor = FetchDescriptor<SavedFoodRecord>()
        let records = try modelContext.fetch(descriptor)
        let now = Date.now
        if let record = records.first(where: { $0.id == food.id }) {
            record.payload = data
            record.updatedAt = now
            record.deletedAt = nil
        } else {
            modelContext.insert(SavedFoodRecord(id: food.id, payload: data, updatedAt: now))
        }
        try modelContext.save()
    }

    public func saveComposite(_ composite: CompositeFoodDefinition) throws {
        let data = try encoder.encode(composite)
        let descriptor = FetchDescriptor<SavedCompositeFoodRecord>()
        let records = try modelContext.fetch(descriptor)
        if let record = records.first(where: { $0.id == composite.id }) {
            record.payload = data
            record.updatedAt = composite.updatedAt
            record.deletedAt = nil
        } else {
            modelContext.insert(SavedCompositeFoodRecord(id: composite.id, payload: data, updatedAt: composite.updatedAt))
        }
        try modelContext.save()
    }

    public func allComposites() throws -> [CompositeFoodDefinition] {
        let descriptor = FetchDescriptor<SavedCompositeFoodRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try modelContext.fetch(descriptor)
            .filter { $0.deletedAt == nil }
            .compactMap { try? decoder.decode(CompositeFoodDefinition.self, from: $0.payload) }
    }

    public func allFoods() throws -> [FoodItem] {
        let descriptor = FetchDescriptor<SavedFoodRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try modelContext.fetch(descriptor)
            .filter { $0.deletedAt == nil }
            .compactMap { try? decoder.decode(FoodItem.self, from: $0.payload) }
    }

    public func saveEnergy(_ summary: EnergyDaySummary) throws {
        let data = try encoder.encode(summary)
        let descriptor = FetchDescriptor<EnergyDayRecord>()
        let records = try modelContext.fetch(descriptor)
        if let record = records.first(where: { $0.dayKey == summary.dayKey }) {
            record.payload = data
            record.fetchedAt = summary.fetchedAt
            record.deletedAt = nil
        } else {
            modelContext.insert(EnergyDayRecord(id: summary.id, dayKey: summary.dayKey, payload: data, fetchedAt: summary.fetchedAt))
        }
        try modelContext.save()
    }

    public func energy(dayKey: String) throws -> EnergyDaySummary? {
        let descriptor = FetchDescriptor<EnergyDayRecord>()
        guard let record = try modelContext.fetch(descriptor).first(where: { $0.dayKey == dayKey && $0.deletedAt == nil }) else { return nil }
        return try decoder.decode(EnergyDaySummary.self, from: record.payload)
    }

    public func allEnergy() throws -> [EnergyDaySummary] {
        let descriptor = FetchDescriptor<EnergyDayRecord>(sortBy: [SortDescriptor(\.dayKey)])
        return try modelContext.fetch(descriptor)
            .filter { $0.deletedAt == nil }
            .compactMap { try? decoder.decode(EnergyDaySummary.self, from: $0.payload) }
    }

    public func saveBalanceGoal(_ goal: BalanceGoal) throws {
        let descriptor = FetchDescriptor<GoalRecord>()
        let records = try modelContext.fetch(descriptor)
        let now = Date.now
        if let record = records.first(where: { $0.effectiveDayKey == goal.effectiveDayKey }) {
            record.targetBalanceKcal = goal.targetBalanceKcal
            record.updatedAt = now
            record.deletedAt = nil
        } else {
            modelContext.insert(GoalRecord(effectiveDayKey: goal.effectiveDayKey, targetBalanceKcal: goal.targetBalanceKcal, updatedAt: now))
        }
        try modelContext.save()
    }

    public func balanceGoal(effectiveOn dayKey: String) throws -> BalanceGoal? {
        let descriptor = FetchDescriptor<GoalRecord>(sortBy: [SortDescriptor(\.effectiveDayKey, order: .reverse)])
        guard let record = try modelContext.fetch(descriptor).first(where: { $0.effectiveDayKey <= dayKey && $0.deletedAt == nil }) else { return nil }
        return BalanceGoal(effectiveDayKey: record.effectiveDayKey, targetBalanceKcal: record.targetBalanceKcal)
    }

    public func saveConflict(kind: String, payloadJSON: String) throws {
        modelContext.insert(ConflictCopyRecord(recordKind: kind, payloadJSON: payloadJSON))
        try modelContext.save()
    }

    public func unresolvedConflicts() throws -> [ConflictCopySnapshot] {
        let descriptor = FetchDescriptor<ConflictCopyRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try modelContext.fetch(descriptor)
            .filter { $0.resolvedAt == nil }
            .map { ConflictCopySnapshot(id: $0.id, recordKind: $0.recordKind, payloadJSON: $0.payloadJSON, createdAt: $0.createdAt) }
    }

    // MARK: - Cloud sync snapshots and merge

    public func syncEnvelopes(deviceID: String) throws -> [SyncRecordEnvelope] {
        var result: [SyncRecordEnvelope] = []

        for record in try modelContext.fetch(FetchDescriptor<DiaryEntryRecord>()) {
            result.append(SyncRecordEnvelope(
                recordKind: .diaryEntry,
                recordID: record.id,
                payload: record.payload,
                updatedAt: record.updatedAt,
                deletedAt: record.deletedAt,
                deviceID: deviceID
            ))
        }

        for record in try modelContext.fetch(FetchDescriptor<SavedFoodRecord>()) {
            result.append(SyncRecordEnvelope(
                recordKind: .savedFood,
                recordID: record.id,
                payload: record.payload,
                updatedAt: record.updatedAt,
                deletedAt: record.deletedAt,
                deviceID: deviceID
            ))
        }

        for record in try modelContext.fetch(FetchDescriptor<SavedCompositeFoodRecord>()) {
            result.append(SyncRecordEnvelope(
                recordKind: .compositeFood,
                recordID: record.id,
                payload: record.payload,
                updatedAt: record.updatedAt,
                deletedAt: record.deletedAt,
                deviceID: deviceID
            ))
        }

        for record in try modelContext.fetch(FetchDescriptor<EnergyDayRecord>()) {
            result.append(SyncRecordEnvelope(
                recordKind: .energyDay,
                recordID: StableSyncIdentifier.energyDay(record.dayKey),
                payload: record.payload,
                updatedAt: record.fetchedAt,
                deletedAt: record.deletedAt,
                deviceID: deviceID
            ))
        }

        for record in try modelContext.fetch(FetchDescriptor<GoalRecord>()) {
            let goal = BalanceGoal(effectiveDayKey: record.effectiveDayKey, targetBalanceKcal: record.targetBalanceKcal)
            result.append(SyncRecordEnvelope(
                recordKind: .balanceGoal,
                recordID: StableSyncIdentifier.balanceGoal(record.effectiveDayKey),
                payload: try encoder.encode(goal),
                updatedAt: record.updatedAt,
                deletedAt: record.deletedAt,
                deviceID: deviceID
            ))
        }

        return result.sorted { $0.recordKey < $1.recordKey }
    }

    public func pendingSyncEnvelopes(deviceID: String) throws -> [SyncRecordEnvelope] {
        let metadata = try metadataByKey()
        return try syncEnvelopes(deviceID: deviceID).filter { envelope in
            guard let meta = metadata[envelope.recordKey] else { return true }
            return meta.lastSyncedPayload != envelope.payload
                || meta.lastSyncedUpdatedAt != envelope.updatedAt
                || meta.lastSyncedDeletedAt != envelope.deletedAt
        }
    }

    public func markSyncRecordsSynced(_ envelopes: [SyncRecordEnvelope]) throws {
        let existing = try modelContext.fetch(FetchDescriptor<SyncMetadataRecord>())
        var byKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.recordKey, $0) })
        for envelope in envelopes {
            if let record = byKey[envelope.recordKey] {
                record.lastSyncedPayload = envelope.payload
                record.lastSyncedUpdatedAt = envelope.updatedAt
                record.lastSyncedDeletedAt = envelope.deletedAt
                record.syncedAt = .now
            } else {
                let record = SyncMetadataRecord(
                    recordKey: envelope.recordKey,
                    lastSyncedPayload: envelope.payload,
                    lastSyncedUpdatedAt: envelope.updatedAt,
                    lastSyncedDeletedAt: envelope.deletedAt
                )
                modelContext.insert(record)
                byKey[envelope.recordKey] = record
            }
        }
        try modelContext.save()
    }

    public func mergeSyncRecords(_ remote: [SyncRecordEnvelope]) throws -> SyncMergeSummary {
        var applied = 0
        var keptLocal = 0
        var unchanged = 0
        var conflicts = 0
        var tombstones = 0
        let metadata = try metadataByKey()

        for envelope in remote {
            let local = try syncEnvelopes(deviceID: envelope.deviceID).first { $0.recordKey == envelope.recordKey }
            guard let local else {
                try applySyncEnvelope(envelope)
                try markSyncRecordsSynced([envelope])
                if envelope.deletedAt != nil { tombstones += 1 } else { applied += 1 }
                continue
            }

            if local.payload == envelope.payload
                && local.updatedAt == envelope.updatedAt
                && local.deletedAt == envelope.deletedAt {
                unchanged += 1
                continue
            }

            let base = metadata[envelope.recordKey]
            let localChanged = base.map {
                $0.lastSyncedPayload != local.payload
                    || $0.lastSyncedUpdatedAt != local.updatedAt
                    || $0.lastSyncedDeletedAt != local.deletedAt
            } ?? true
            let remoteChanged = base.map {
                $0.lastSyncedPayload != envelope.payload
                    || $0.lastSyncedUpdatedAt != envelope.updatedAt
                    || $0.lastSyncedDeletedAt != envelope.deletedAt
            } ?? true

            if !localChanged {
                try applySyncEnvelope(envelope)
                try markSyncRecordsSynced([envelope])
                if envelope.deletedAt != nil { tombstones += 1 } else { applied += 1 }
            } else if !remoteChanged || local.updatedAt > envelope.updatedAt {
                if remoteChanged && envelope.deletedAt == nil {
                    try saveConflictIfNeeded(kind: envelope.recordKind.rawValue, payloadJSON: try jsonString(envelope))
                    conflicts += 1
                }
                // Keep the local value, but remember the last server state so it will be uploaded.
                try markSyncRecordsSynced([envelope])
                keptLocal += 1
            } else if envelope.updatedAt > local.updatedAt {
                if local.deletedAt == nil {
                    try saveConflictIfNeeded(kind: envelope.recordKind.rawValue, payloadJSON: try jsonString(local))
                    conflicts += 1
                }
                try applySyncEnvelope(envelope)
                try markSyncRecordsSynced([envelope])
                if envelope.deletedAt != nil { tombstones += 1 } else { applied += 1 }
            } else {
                try saveConflictIfNeeded(kind: envelope.recordKind.rawValue, payloadJSON: try jsonString(envelope))
                conflicts += 1
                try markSyncRecordsSynced([envelope])
                keptLocal += 1
            }
        }

        return SyncMergeSummary(applied: applied, keptLocal: keptLocal, unchanged: unchanged, conflicts: conflicts, tombstones: tombstones)
    }

    public func unresolvedConflictCount() throws -> Int {
        try modelContext.fetch(FetchDescriptor<ConflictCopyRecord>()).filter { $0.resolvedAt == nil }.count
    }

    private func metadataByKey() throws -> [String: SyncMetadataRecord] {
        Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<SyncMetadataRecord>()).map { ($0.recordKey, $0) })
    }

    private func applySyncEnvelope(_ envelope: SyncRecordEnvelope) throws {
        switch envelope.recordKind {
        case .diaryEntry:
            if envelope.deletedAt != nil {
                if let record = try modelContext.fetch(FetchDescriptor<DiaryEntryRecord>()).first(where: { $0.id == envelope.recordID }) {
                    record.deletedAt = envelope.deletedAt
                    record.updatedAt = envelope.updatedAt
                    record.payload = envelope.payload
                }
            } else {
                let entry = try decoder.decode(DiaryEntry.self, from: envelope.payload)
                try save(DiaryEntry(
                    id: entry.id,
                    sessionID: entry.sessionID,
                    dayKey: entry.dayKey,
                    occurredAt: entry.occurredAt,
                    timeZoneIdentifier: entry.timeZoneIdentifier,
                    mealType: entry.mealType,
                    foodID: entry.foodID,
                    foodName: entry.foodName,
                    foodNameZh: entry.foodNameZh,
                    foodNameEn: entry.foodNameEn,
                    quantityDescription: entry.quantityDescription,
                    quantityDescriptionZh: entry.quantityDescriptionZh,
                    quantityDescriptionEn: entry.quantityDescriptionEn,
                    normalizedAmount: entry.normalizedAmount,
                    normalizedUnit: entry.normalizedUnit,
                    nutrients: entry.nutrients,
                    source: entry.source,
                    photoConfidence: entry.photoConfidence,
                    photoFilenames: entry.photoFilenames,
                    createdAt: entry.createdAt,
                    updatedAt: envelope.updatedAt,
                    deletedAt: nil
                ))
            }
        case .savedFood:
            let records = try modelContext.fetch(FetchDescriptor<SavedFoodRecord>())
            if let record = records.first(where: { $0.id == envelope.recordID }) {
                record.deletedAt = envelope.deletedAt
                record.updatedAt = envelope.updatedAt
                record.payload = envelope.payload
            } else if envelope.deletedAt == nil {
                modelContext.insert(SavedFoodRecord(id: envelope.recordID, payload: envelope.payload, updatedAt: envelope.updatedAt))
            }
        case .compositeFood:
            let records = try modelContext.fetch(FetchDescriptor<SavedCompositeFoodRecord>())
            if let record = records.first(where: { $0.id == envelope.recordID }) {
                record.deletedAt = envelope.deletedAt
                record.updatedAt = envelope.updatedAt
                record.payload = envelope.payload
            } else if envelope.deletedAt == nil {
                modelContext.insert(SavedCompositeFoodRecord(id: envelope.recordID, payload: envelope.payload, updatedAt: envelope.updatedAt))
            }
        case .energyDay:
            let summary = try decoder.decode(EnergyDaySummary.self, from: envelope.payload)
            let records = try modelContext.fetch(FetchDescriptor<EnergyDayRecord>())
            if let record = records.first(where: { $0.dayKey == summary.dayKey }) {
                record.deletedAt = envelope.deletedAt
                record.fetchedAt = envelope.updatedAt
                record.payload = envelope.payload
            } else if envelope.deletedAt == nil {
                modelContext.insert(EnergyDayRecord(id: summary.id, dayKey: summary.dayKey, payload: envelope.payload, fetchedAt: envelope.updatedAt))
            }
        case .balanceGoal:
            let goal = try decoder.decode(BalanceGoal.self, from: envelope.payload)
            let records = try modelContext.fetch(FetchDescriptor<GoalRecord>())
            if let record = records.first(where: { $0.effectiveDayKey == goal.effectiveDayKey }) {
                record.deletedAt = envelope.deletedAt
                record.updatedAt = envelope.updatedAt
                record.targetBalanceKcal = goal.targetBalanceKcal
            } else if envelope.deletedAt == nil {
                modelContext.insert(GoalRecord(
                    id: envelope.recordID,
                    effectiveDayKey: goal.effectiveDayKey,
                    targetBalanceKcal: goal.targetBalanceKcal,
                    updatedAt: envelope.updatedAt
                ))
            }
        }
        try modelContext.save()
    }

    private func saveConflictIfNeeded(kind: String, payloadJSON: String) throws {
        let existing = try modelContext.fetch(FetchDescriptor<ConflictCopyRecord>())
        guard !existing.contains(where: { $0.recordKind == kind && $0.payloadJSON == payloadJSON && $0.resolvedAt == nil }) else { return }
        modelContext.insert(ConflictCopyRecord(recordKind: kind, payloadJSON: payloadJSON))
        try modelContext.save()
    }

}
