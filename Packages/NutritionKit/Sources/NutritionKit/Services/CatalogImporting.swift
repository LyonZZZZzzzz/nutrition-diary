import Foundation

public struct CatalogImportIssue: Codable, Hashable, Sendable {
    public let row: Int
    public let message: String

    public init(row: Int, message: String) {
        self.row = row
        self.message = message
    }
}

public struct CatalogImportPreview: Codable, Sendable {
    public let foods: [FoodItem]
    public let issues: [CatalogImportIssue]
    public let unknownColumns: [String]
    public let duplicateNames: [String]

    public init(foods: [FoodItem], issues: [CatalogImportIssue], unknownColumns: [String], duplicateNames: [String]) {
        self.foods = foods
        self.issues = issues
        self.unknownColumns = unknownColumns
        self.duplicateNames = duplicateNames
    }

    public var canCommit: Bool { !foods.isEmpty && issues.isEmpty && duplicateNames.isEmpty }
}

public protocol CatalogImporting: Sendable {
    func previewCSV(_ data: Data) throws -> CatalogImportPreview
}

public struct CSVFoodCatalogImporter: CatalogImporting {
    public init() {}

    public func previewCSV(_ data: Data) throws -> CatalogImportPreview {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CatalogImportError.invalidEncoding
        }
        let rows = parseCSV(text)
        guard let header = rows.first, !header.isEmpty else {
            throw CatalogImportError.emptyFile
        }
        let normalized = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let knownNutrients = Dictionary(uniqueKeysWithValues: NutrientCatalog.definitions.map { ($0.id.rawValue, $0) })
        let fixedColumns = Set(["name", "aliases", "category", "referenceAmount", "referenceUnit", "edibleRatio", "density", "sourceTitle", "license", "barcode"])
        let unknown = normalized.filter { !fixedColumns.contains($0) && knownNutrients[$0] == nil }
        var foods: [FoodItem] = []
        var issues: [CatalogImportIssue] = []
        var seenNames: [String: Int] = [:]
        var duplicates = Set<String>()

        for (offset, row) in rows.dropFirst().enumerated() {
            let rowNumber = offset + 2
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            let values = Dictionary(uniqueKeysWithValues: zip(normalized, row + Array(repeating: "", count: max(0, normalized.count - row.count))))
            let name = values["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else {
                issues.append(.init(row: rowNumber, message: "缺少 name"))
                continue
            }
            if let first = seenNames[name] {
                duplicates.insert(name)
                issues.append(.init(row: rowNumber, message: "与第 \(first) 行名称重复：\(name)"))
                continue
            }
            seenNames[name] = rowNumber

            guard let referenceAmount = Decimal(string: values["referenceAmount"] ?? "100"), referenceAmount > 0 else {
                issues.append(.init(row: rowNumber, message: "referenceAmount 必须大于零"))
                continue
            }
            let unitValue = values["referenceUnit"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "g"
            guard let unit = FoodReferenceUnit(rawValue: unitValue) else {
                issues.append(.init(row: rowNumber, message: "referenceUnit 只能是 g 或 ml"))
                continue
            }

            var nutrients: [NutrientMeasurement] = []
            for definition in NutrientCatalog.definitions {
                let raw = values[definition.id.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if raw.isEmpty {
                    nutrients.append(.missing(definition.id, unit: definition.unit, source: .importedCatalog))
                } else if let value = Decimal(string: raw), value >= 0 {
                    nutrients.append(.init(nutrient: definition.id, value: value, unit: definition.unit, status: .complete, source: .importedCatalog))
                } else {
                    issues.append(.init(row: rowNumber, message: "\(definition.id.rawValue) 不是有效非负数"))
                }
            }

            let aliases = (values["aliases"] ?? "").split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let sourceTitle = values["sourceTitle"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "CSV 导入"
            let license = values["license"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            foods.append(FoodItem(
                name: name,
                aliases: aliases,
                category: values["category"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "导入食物",
                referenceAmount: referenceAmount,
                referenceUnit: unit,
                edibleRatio: Decimal(string: values["edibleRatio"] ?? "1") ?? 1,
                densityGramsPerMilliliter: Decimal(string: values["density"] ?? ""),
                nutrients: nutrients,
                source: FoodSource(kind: .imported, title: sourceTitle, license: license?.isEmpty == false ? license : nil, retrievedAt: .now),
                barcode: values["barcode"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return CatalogImportPreview(foods: foods, issues: issues, unknownColumns: unknown, duplicateNames: duplicates.sorted())
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "\"" {
                let next = text.index(after: index)
                if inQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if char == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if (char == "\n" || char == "\r"), !inQuotes {
                if char == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" { index = next }
                }
                row.append(field)
                field = ""
                rows.append(row)
                row = []
            } else {
                field.append(char)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

public enum CatalogImportError: Error, LocalizedError, Sendable {
    case invalidEncoding
    case emptyFile

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding: "CSV 文件不是 UTF-8 编码"
        case .emptyFile: "CSV 文件为空"
        }
    }
}
