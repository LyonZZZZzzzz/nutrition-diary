import Foundation

/// The languages the app can render. The raw values are valid Locale identifiers.
public enum AppLanguage: String, Codable, CaseIterable, Hashable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public var locale: Locale { Locale(identifier: rawValue) }
    public var isChinese: Bool { self == .simplifiedChinese }

    public var displayName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
}

/// User preference, including the default system-following mode.
public enum AppLanguagePreference: String, Codable, CaseIterable, Hashable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
}

public enum AppLanguageResolver {
    /// Chinese system locales resolve to Simplified Chinese; every other locale
    /// falls back to English. An explicit app preference always wins.
    public static func resolve(
        preference: AppLanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        switch preference {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        case .system:
            guard let first = preferredLanguages.first?.lowercased() else { return .english }
            return first.hasPrefix("zh") ? .simplifiedChinese : .english
        }
    }
}

public extension FoodReferenceUnit {
    func localizedTitle(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.gram, .simplifiedChinese): "克"
        case (.milliliter, .simplifiedChinese): "毫升"
        case (.gram, .english): "g"
        case (.milliliter, .english): "ml"
        }
    }
}

public extension FoodSource {
    func localizedTitle(for language: AppLanguage) -> String {
        if language.isChinese, let titleZh, !titleZh.isEmpty { return titleZh }
        if !language.isChinese, let titleEn, !titleEn.isEmpty { return titleEn }
        if language.isChinese, let titleZh, !titleZh.isEmpty { return titleZh }
        switch kind {
        case .bundled:
            return language.isChinese ? "公开授权食物目录" : "Licensed food catalog"
        case .custom:
            return language.isChinese ? "自定义食物" : "Custom food"
        case .openFoodFacts:
            return "Open Food Facts"
        case .deepSeekPhotoLabel:
            return language.isChinese ? "DeepSeek 营养标签识别" : "DeepSeek nutrition label"
        case .imported:
            return language.isChinese ? "导入食物目录" : "Imported food catalog"
        }
    }
}

public extension ServingPortion {
    func localizedLabel(for language: AppLanguage) -> String {
        if language.isChinese, let labelZh, !labelZh.isEmpty { return labelZh }
        if !language.isChinese, let labelEn, !labelEn.isEmpty { return labelEn }
        return label
    }
}

public extension FoodItem {
    func localizedName(for language: AppLanguage) -> String {
        if language.isChinese, let nameZh, !nameZh.isEmpty { return nameZh }
        if !language.isChinese, let nameEn, !nameEn.isEmpty { return nameEn }
        if language.isChinese, let nameEn, !nameEn.isEmpty, nameZh == nil { return nameEn }
        return name
    }

    func localizedCategory(for language: AppLanguage) -> String {
        if language.isChinese, let categoryZh, !categoryZh.isEmpty { return categoryZh }
        if !language.isChinese, let categoryEn, !categoryEn.isEmpty { return categoryEn }
        return category
    }

    func hasLocalizedName(for language: AppLanguage) -> Bool {
        switch language {
        case .simplifiedChinese: nameZh?.isEmpty == false
        case .english: nameEn?.isEmpty == false
        }
    }

    var searchableNames: [String] {
        [name, nameZh, nameEn].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        } + aliases + (pinyin ?? [])
    }
}

public extension MealType {
    func localizedTitle(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.breakfast, .simplifiedChinese): "早餐"
        case (.lunch, .simplifiedChinese): "午餐"
        case (.dinner, .simplifiedChinese): "晚餐"
        case (.snack, .simplifiedChinese): "加餐"
        case (.breakfast, .english): "Breakfast"
        case (.lunch, .english): "Lunch"
        case (.dinner, .english): "Dinner"
        case (.snack, .english): "Snack"
        }
    }
}

public extension NutrientGroup {
    func localizedTitle(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.macronutrient, .simplifiedChinese): "宏量营养"
        case (.fatDetail, .simplifiedChinese): "脂肪酸与胆固醇"
        case (.mineral, .simplifiedChinese): "矿物质"
        case (.vitamin, .simplifiedChinese): "维生素"
        case (.other, .simplifiedChinese): "其他"
        case (.macronutrient, .english): "Macronutrients"
        case (.fatDetail, .english): "Fats & cholesterol"
        case (.mineral, .english): "Minerals"
        case (.vitamin, .english): "Vitamins"
        case (.other, .english): "Other"
        }
    }
}

public extension NutrientDefinition {
    func localizedName(for language: AppLanguage) -> String {
        guard language == .english else { return name }
        switch id.rawValue {
        case "energy_kcal": return "Calories"
        case "protein_g": return "Protein"
        case "fat_g": return "Fat"
        case "carbohydrate_g": return "Carbohydrates"
        case "fiber_g": return "Dietary fiber"
        case "sugar_g": return "Sugar"
        case "sodium_mg": return "Sodium"
        case "saturated_fat_g": return "Saturated fat"
        case "monounsaturated_fat_g": return "Monounsaturated fat"
        case "polyunsaturated_fat_g": return "Polyunsaturated fat"
        case "trans_fat_g": return "Trans fat"
        case "cholesterol_mg": return "Cholesterol"
        case "potassium_mg": return "Potassium"
        case "calcium_mg": return "Calcium"
        case "iron_mg": return "Iron"
        case "magnesium_mg": return "Magnesium"
        case "phosphorus_mg": return "Phosphorus"
        case "zinc_mg": return "Zinc"
        case "selenium_ug": return "Selenium"
        case "vitamin_a_ug": return "Vitamin A"
        case "vitamin_c_mg": return "Vitamin C"
        case "vitamin_d_ug": return "Vitamin D"
        case "vitamin_e_mg": return "Vitamin E"
        case "vitamin_k_ug": return "Vitamin K"
        case "thiamin_mg": return "Vitamin B1"
        case "riboflavin_mg": return "Vitamin B2"
        case "niacin_mg": return "Niacin"
        case "vitamin_b6_mg": return "Vitamin B6"
        case "folate_ug": return "Folate"
        case "vitamin_b12_ug": return "Vitamin B12"
        case "caffeine_mg": return "Caffeine"
        default: return name
        }
    }
}

public extension MeasurementSource {
    func localizedTitle(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.bundledCatalog, .simplifiedChinese): "公开目录"
        case (.userFood, .simplifiedChinese): "自定义食物"
        case (.recipe, .simplifiedChinese): "配方计算"
        case (.photoEstimate, .simplifiedChinese): "照片估算"
        case (.importedCatalog, .simplifiedChinese): "导入目录"
        case (.manual, .simplifiedChinese): "手动录入"
        case (.bundledCatalog, .english): "Bundled catalog"
        case (.userFood, .english): "Custom food"
        case (.recipe, .english): "Recipe calculation"
        case (.photoEstimate, .english): "Photo estimate"
        case (.importedCatalog, .english): "Imported catalog"
        case (.manual, .english): "Manual entry"
        }
    }
}

public extension CompositeNutritionMode {
    func localizedTitle(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.direct, .simplifiedChinese): "直接营养数据"
        case (.recipe, .simplifiedChinese): "按配料配方"
        case (.direct, .english): "Direct nutrition data"
        case (.recipe, .english): "Recipe calculation"
        }
    }
}

public extension PhotoRecognitionMode {
    func localizedTitle(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.meal, .simplifiedChinese): "混合餐"
        case (.packagedLabel, .simplifiedChinese): "包装营养标签"
        case (.meal, .english): "Mixed meal"
        case (.packagedLabel, .english): "Packaged nutrition label"
        }
    }
}

public extension PhotoRecognitionProvider {
    func localizedTitle(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.appleOnDevice, .simplifiedChinese): "Apple 本机识别"
        case (.deepSeek, .simplifiedChinese): "DeepSeek 云端识别"
        case (.appleOnDevice, .english): "Apple on-device recognition"
        case (.deepSeek, .english): "DeepSeek cloud recognition"
        }
    }
}

public extension PhotoAnalysisAvailability {
    func localizedDescription(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.available, .simplifiedChinese): "可用"
        case (.deviceNotEligible, .simplifiedChinese): "当前设备不支持 Apple Intelligence。"
        case (.appleIntelligenceDisabled, .simplifiedChinese): "Apple Intelligence 尚未开启。"
        case (.modelNotReady, .simplifiedChinese): "Apple 端侧模型尚未准备完成。"
        case (.localeUnsupported, .simplifiedChinese): "当前语言暂不受端侧模型支持。"
        case (.unavailable, .simplifiedChinese): "Apple 端侧照片识别不可用。"
        case (.available, .english): "Available"
        case (.deviceNotEligible, .english): "This device does not support Apple Intelligence."
        case (.appleIntelligenceDisabled, .english): "Apple Intelligence is turned off."
        case (.modelNotReady, .english): "The on-device model is not ready yet."
        case (.localeUnsupported, .english): "The on-device model does not support the selected language."
        case (.unavailable, .english): "Apple on-device photo recognition is unavailable."
        }
    }
}

public extension DiaryEntry {
    func localizedFoodName(for language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return foodNameZh?.nilIfBlank ?? foodName
        case .english:
            return foodNameEn?.nilIfBlank ?? foodName
        }
    }

    func localizedQuantityDescription(for language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return quantityDescriptionZh?.nilIfBlank ?? quantityDescription
        case .english:
            return quantityDescriptionEn?.nilIfBlank ?? quantityDescription
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}

public extension HealthEnergySource {
    func localizedDisplayName(for language: AppLanguage) -> String {
        let type = language.isChinese ? (isWatch ? "Apple Watch" : "iPhone/其他") : (isWatch ? "Apple Watch" : "iPhone/Other")
        return "\(name) · \(type)"
    }
}

public extension HealthEnergySelection {
    func localizedCoverageNote(for language: AppLanguage) -> String? {
        coverageNote.map { localizedHealthCoverageNote($0, language: language) }
    }
}

public extension EnergyDaySummary {
    func localizedCoverageNote(for language: AppLanguage) -> String? {
        guard let coverageNote, !coverageNote.isEmpty else { return nil }
        if !language.isChinese {
            return coverageNote
                .split(separator: "；")
                .map { localizedHealthCoverageNote(String($0), language: language) }
                .joined(separator: "; ")
        }
        return coverageNote
    }
}

private func localizedHealthCoverageNote(_ note: String, language: AppLanguage) -> String {
    guard language == .english else { return note }
    switch note {
    case "固定来源不可用，请重新选择": return "The selected source is unavailable; choose another source"
    case "没有检测到活动能量来源": return "No activity-energy sources were detected"
    case "未检测到 Apple Watch，使用其他健康来源": return "No Apple Watch data was detected; another health source is being used"
    case "部分指标缺少 Watch 数据": return "Some metrics are missing Apple Watch data"
    case "部分健康指标缺失": return "Some health metrics are missing"
    default:
        break
    }
    if note.hasPrefix("固定使用 ") { return "Fixed to \(note.dropFirst("固定使用 ".count))" }
    if note.hasPrefix("使用 ") { return "Using \(note.dropFirst("使用 ".count))" }
    if note.hasSuffix(" 个 Watch 来源，按指标选择覆盖最高者") {
        let count = note.replacingOccurrences(of: " 个 Watch 来源，按指标选择覆盖最高者", with: "")
        return "\(count) Apple Watch sources detected; the highest-coverage source is selected per metric"
    }
    return note
}

public func localizedErrorDescription(_ error: Error, language: AppLanguage) -> String {
    guard language == .english else { return error.localizedDescription }
    if let error = error as? CloudSyncError {
        switch error {
        case .networkUnavailable: return "Network unavailable; changes are saved locally and will retry"
        case .transportUnavailable: return "iCloud sync is currently unavailable"
        case .accountUnavailable: return "Sign in to iCloud and enable iCloud Drive to sync"
        case .rejected(let message): return message
        case .accountSwitchConfirmationRequired: return "Your iCloud account changed; confirmation is required before syncing"
        }
    }
    if let error = error as? DeepSeekVisionError {
        switch error {
        case .missingAPIKey: return "DeepSeek API key is not configured"
        case .unauthorized: return "The DeepSeek API key is invalid; configure it again in Settings"
        case .insufficientBalance: return "The DeepSeek account has insufficient balance"
        case .rateLimited(let retryAfter):
            return retryAfter.map { "DeepSeek is rate limiting requests; wait about \(Int($0.rounded())) seconds" }
                ?? "DeepSeek is rate limiting requests; try again later"
        case .payloadTooLarge: return "The photos are too large; use fewer photos or retake them"
        case .invalidResponse: return "DeepSeek returned an unrecognized response"
        case .invalidLabel(let message): return message
        case .network(let message): return "DeepSeek network error: \(message)"
        case .server(let statusCode, let requestID):
            return requestID.map { "DeepSeek service error \(statusCode), request \($0)" } ?? "DeepSeek service error \(statusCode)"
        case .invalidJSON(let message): return "Could not parse the DeepSeek result: \(message)"
        }
    }
    if let error = error as? PhotoAnalysisError {
        switch error {
        case .unavailable(let reason): return reason.localizedDescription(for: language)
        case .invalidImage: return "The photo format is invalid"
        case .imageQuality(let issue): return issue.localizedDescription(for: language)
        case .modelFailure(let message): return message
        }
    }
    if let error = error as? CompositeFoodError {
        switch error {
        case .missingDirectNutrition: return "Direct-nutrition mode requires at least one nutrient value"
        case .missingIngredients: return "Recipe mode requires at least one ingredient"
        case .invalidYield: return "Finished weight and servings must be greater than zero"
        case .missingDensity(let food): return "\(food) has no density, so its weight cannot be calculated"
        }
    }
    if let error = error as? NutritionCalculationError {
        switch error {
        case .invalidAmount: return "The portion must be greater than zero"
        case .missingDensity: return "This food has no density for gram-to-milliliter conversion"
        case .unknownPortion: return "The selected portion could not be found"
        case .incompatibleUnit: return "The food reference unit is incompatible with the entry unit"
        }
    }
    if let error = error as? CatalogImportError {
        switch error {
        case .invalidEncoding: return "The CSV file is not UTF-8 encoded"
        case .emptyFile: return "The CSV file is empty"
        }
    }
    if let error = error as? DataTransferError {
        switch error {
        case .unsupportedBackupVersion(let version): return "Unsupported backup version: \(version)"
        case .malformedData: return "The backup data is invalid"
        }
    }
    return error.localizedDescription
}
