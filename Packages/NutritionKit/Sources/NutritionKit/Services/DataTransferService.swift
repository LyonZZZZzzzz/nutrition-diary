import Foundation

public enum BackupRestoreMode: String, Codable, Sendable {
    case merge
    case replace
}

public struct BackupRestoreSummary: Codable, Hashable, Sendable {
    public let added: Int
    public let updated: Int
    public let unchanged: Int
    public let conflicts: Int
    public let mode: BackupRestoreMode

    public init(added: Int, updated: Int, unchanged: Int, conflicts: Int, mode: BackupRestoreMode) {
        self.added = added
        self.updated = updated
        self.unchanged = unchanged
        self.conflicts = conflicts
        self.mode = mode
    }
}

public struct NutritionBackup: Codable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let entries: [DiaryEntry]
    public let energyDays: [EnergyDaySummary]
    public let balanceGoals: [BalanceGoal]
    public let conflictCopies: [ConflictCopySnapshot]
    public let savedFoods: [FoodItem]
    public let compositeFoods: [CompositeFoodDefinition]

    public init(
        schemaVersion: Int = 2,
        exportedAt: Date = .now,
        entries: [DiaryEntry],
        energyDays: [EnergyDaySummary],
        balanceGoals: [BalanceGoal],
        conflictCopies: [ConflictCopySnapshot] = [],
        savedFoods: [FoodItem] = [],
        compositeFoods: [CompositeFoodDefinition] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.entries = entries
        self.energyDays = energyDays
        self.balanceGoals = balanceGoals
        self.conflictCopies = conflictCopies
        self.savedFoods = savedFoods
        self.compositeFoods = compositeFoods
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, entries, energyDays, balanceGoals, conflictCopies, savedFoods, compositeFoods
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        entries = try values.decode([DiaryEntry].self, forKey: .entries)
        energyDays = try values.decode([EnergyDaySummary].self, forKey: .energyDays)
        balanceGoals = try values.decode([BalanceGoal].self, forKey: .balanceGoals)
        conflictCopies = try values.decodeIfPresent([ConflictCopySnapshot].self, forKey: .conflictCopies) ?? []
        savedFoods = try values.decodeIfPresent([FoodItem].self, forKey: .savedFoods) ?? []
        compositeFoods = try values.decodeIfPresent([CompositeFoodDefinition].self, forKey: .compositeFoods) ?? []
    }
}

public struct ConflictCopySnapshot: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let recordKind: String
    public let payloadJSON: String
    public let createdAt: Date

    public init(id: UUID = UUID(), recordKind: String, payloadJSON: String, createdAt: Date = .now) {
        self.id = id
        self.recordKind = recordKind
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

public enum DataTransferError: Error, LocalizedError, Sendable {
    case unsupportedBackupVersion(Int)
    case malformedData

    public var errorDescription: String? {
        switch self {
        case .unsupportedBackupVersion(let version): "不支持的备份版本：\(version)"
        case .malformedData: "备份数据格式无效"
        }
    }
}

public struct DataTransferService: Sendable {
    public init() {}

    public func makeJSONBackup(
        entries: [DiaryEntry],
        energyDays: [EnergyDaySummary],
        goals: [BalanceGoal],
        conflicts: [ConflictCopySnapshot] = [],
        savedFoods: [FoodItem] = [],
        compositeFoods: [CompositeFoodDefinition] = []
    ) throws -> Data {
        let backup = NutritionBackup(
            entries: entries,
            energyDays: energyDays,
            balanceGoals: goals,
            conflictCopies: conflicts,
            savedFoods: savedFoods,
            compositeFoods: compositeFoods
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(backup)
    }

    public func decodeJSONBackup(_ data: Data) throws -> NutritionBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: NutritionBackup
        do {
            backup = try decoder.decode(NutritionBackup.self, from: data)
        } catch {
            throw DataTransferError.malformedData
        }
        guard backup.schemaVersion == 1 || backup.schemaVersion == 2 else {
            throw DataTransferError.unsupportedBackupVersion(backup.schemaVersion)
        }
        return backup
    }

    public func makeCSV(entries: [DiaryEntry]) -> Data {
        let header = ["日期", "时间", "餐次", "食物", "份量", "热量(kcal)", "蛋白质(g)", "脂肪(g)", "碳水(g)", "膳食纤维(g)", "糖(g)", "钠(mg)", "状态", "来源"]
        var rows = [header.map(escape).joined(separator: ",")]
        let formatter = ISO8601DateFormatter()
        for entry in entries.sorted(by: { $0.occurredAt < $1.occurredAt }) {
            let values = NutrientCatalog.core.map { id in
                entry.nutrients.first { $0.nutrient == id }?.value.map { "\($0)" } ?? ""
            }
            var row = [
                entry.dayKey,
                formatter.string(from: entry.occurredAt),
                entry.mealType.title,
                entry.foodName,
                entry.quantityDescription
            ]
            row.append(contentsOf: values)
            row.append(entry.nutrients.contains(where: { $0.status == .missing }) ? "不完整" : (entry.nutrients.contains(where: { $0.status == .estimated }) ? "估算" : "完整"))
            row.append(entry.source.rawValue)
            rows.append(row.map(escape).joined(separator: ","))
        }
        let bom = Data([0xEF, 0xBB, 0xBF])
        return bom + Data(rows.joined(separator: "\n").utf8)
    }

    private func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
