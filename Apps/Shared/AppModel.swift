import Foundation
import Observation
import NutritionKit

enum DeepSeekStatus {
    case notConfigured
    case saved
    case saveFailed
    case unavailable
    case testing
    case connected
    case failed

    func text(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.notConfigured, .simplifiedChinese): "未配置"
        case (.saved, .simplifiedChinese): "API Key 已保存"
        case (.saveFailed, .simplifiedChinese): "保存失败"
        case (.unavailable, .simplifiedChinese): "当前平台不可用"
        case (.testing, .simplifiedChinese): "正在测试…"
        case (.connected, .simplifiedChinese): "连接成功"
        case (.failed, .simplifiedChinese): "测试失败"
        case (.notConfigured, .english): "Not configured"
        case (.saved, .english): "API key saved"
        case (.saveFailed, .english): "Save failed"
        case (.unavailable, .english): "Unavailable on this platform"
        case (.testing, .english): "Testing…"
        case (.connected, .english): "Connected"
        case (.failed, .english): "Test failed"
        }
    }
}

enum HealthStatus {
    case notConnected
    case authorizationRequested
    case noData
    case connected(Int)
    case notAuthorized
    case readFailed

    func text(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.notConnected, .simplifiedChinese): "尚未连接健康数据"
        case (.authorizationRequested, .simplifiedChinese): "健康权限已请求，正在读取"
        case (.noData, .simplifiedChinese): "已授权，但暂无健康数据"
        case (.connected(let count), .simplifiedChinese): "已连接，检测到 \(count) 个来源"
        case (.notAuthorized, .simplifiedChinese): "尚未授权健康数据，请在设置中连接健康"
        case (.readFailed, .simplifiedChinese): "读取健康能量失败"
        case (.notConnected, .english): "Health data not connected"
        case (.authorizationRequested, .english): "Health permission requested; loading"
        case (.noData, .english): "Authorized, but no health data is available"
        case (.connected(let count), .english): "Connected; \(count) source\(count == 1 ? "" : "s") detected"
        case (.notAuthorized, .english): "Health access has not been authorized"
        case (.readFailed, .english): "Failed to read health energy"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let store: DiaryStore
    let calculator = NutritionCalculator()
    let energyCalculator = EnergyBalanceCalculator()
    private let dataTransfer = DataTransferService()
    private let mediaBackup = MediaBackupService()
    let energyReader: (any EnergyReading)?
    let healthObserver: (any HealthEnergyObserving)?
    let healthWriter: (any DietaryHealthWriting)?
    let onDevicePhotoAnalyzer: (any MealPhotoAnalyzing)?
    let deepSeekPhotoAnalyzer: (any DeepSeekPhotoAnalyzing)?
    let deepSeekCredentials = DeepSeekCredentialStore()
    let photoLearning = PhotoMatchLearningStore()
    let photoFiles = LocalPhotoStore()
    let usesUITestPhotoFixture: Bool
    let cloudSync: (any CloudSyncServing)?
    private var hasLoadedSavedFoods = false
    private var hasLoadedComposites = false
    var hasStartedHealthObservation = false
    var healthRefreshTask: Task<Void, Never>?
    var cloudSyncTask: Task<Void, Never>?
    static let preferredHealthSourceKey = "preferredHealthSourceID"
    static let languagePreferenceKey = "appLanguagePreference"

    let catalog: any FoodSearching

    var selectedDate: Date = .now
    var entries: [DiaryEntry] = []
    var nutritionSummary: DailyNutritionSummary?
    var energySummary: EnergyDaySummary?
    var balanceGoal: BalanceGoal?
    var energyBalance: EnergyBalance?
    var selectedMeal: MealType = .breakfast
    private(set) var movingEntryIDs: Set<UUID> = []
    var errorMessage: String?
    var isLoading = false
    var isAnalyzingPhotos = false
    var photoAnalysisAvailability: PhotoAnalysisAvailability
    var photoReview: PhotoAnalysisReview?
    var packagedLabelReview: PackagedLabelReview?
    var deepSeekConfigured = false
    var deepSeekStatus: DeepSeekStatus = .notConfigured
    var allowEstimatedHealthWrites = false
    var healthAuthorizationRequested = false
    var healthStatus: HealthStatus = .notConnected
    var languagePreference: AppLanguagePreference
    private(set) var effectiveLanguage: AppLanguage
    var compositeFoods: [CompositeFoodDefinition] = []
    var healthSources: [HealthEnergySource] = []
    var preferredHealthSourceID: String?
    var healthLastUpdatedAt: Date?
    var cloudSyncState: CloudSyncState = .localOnly

    init(
        store: DiaryStore,
        energyReader: (any EnergyReading)? = nil,
        healthObserver: (any HealthEnergyObserving)? = nil,
        healthWriter: (any DietaryHealthWriting)? = nil,
        onDevicePhotoAnalyzer: (any MealPhotoAnalyzing)? = nil,
        deepSeekPhotoAnalyzer: (any DeepSeekPhotoAnalyzing)? = nil,
        catalog: (any FoodSearching)? = nil,
        cloudSync: (any CloudSyncServing)? = nil,
        usesUITestPhotoFixture: Bool = false
    ) {
        self.store = store
        self.energyReader = energyReader
        self.healthObserver = healthObserver
        self.healthWriter = healthWriter
        self.onDevicePhotoAnalyzer = onDevicePhotoAnalyzer
        self.deepSeekPhotoAnalyzer = deepSeekPhotoAnalyzer
        self.cloudSync = cloudSync
        self.usesUITestPhotoFixture = usesUITestPhotoFixture
        self.catalog = catalog ?? FoodCatalog()
        self.photoAnalysisAvailability = .unavailable
        let preference = UserDefaults.standard.string(forKey: Self.languagePreferenceKey)
            .flatMap(AppLanguagePreference.init(rawValue:)) ?? .system
        self.languagePreference = preference
        self.effectiveLanguage = AppLanguageResolver.resolve(preference: preference)
        self.deepSeekConfigured = DeepSeekCredentialStore().load() != nil
        self.deepSeekStatus = deepSeekConfigured ? .saved : .notConfigured
        self.preferredHealthSourceID = UserDefaults.standard.string(forKey: Self.preferredHealthSourceKey)
    }

    var dayKey: String {
        DayKey.make(from: selectedDate)
    }

    var deepSeekStatusText: String { deepSeekStatus.text(for: effectiveLanguage) }
    var healthStatusText: String { healthStatus.text(for: effectiveLanguage) }
    var syncStatusText: String {
        guard cloudSync != nil else { return localized("仅本机保存", "Local only") }
        switch cloudSyncState.status {
        case .localOnly: return localized("仅本机保存", "Local only")
        case .idle: return localized("已同步", "Synced")
        case .syncing: return localized("正在同步…", "Syncing…")
        case .offline: return localized("离线，等待重试", "Offline; waiting to retry")
        case .requiresConfirmation: return localized("需要确认 iCloud 账号", "iCloud account confirmation required")
        case .failed: return localized("同步失败", "Sync failed")
        }
    }

    var cloudAccountText: String {
        switch cloudSyncState.account.status {
        case .available: return localized("iCloud 已登录", "Signed in to iCloud")
        case .noAccount: return localized("未登录 iCloud", "Not signed in to iCloud")
        case .restricted: return localized("iCloud 受限", "iCloud restricted")
        case .couldNotDetermine: return localized("无法确定 iCloud 状态", "iCloud status unknown")
        case .unavailable: return localized("CloudKit 不可用", "CloudKit unavailable")
        }
    }

    func setLanguagePreference(_ preference: AppLanguagePreference) {
        languagePreference = preference
        effectiveLanguage = AppLanguageResolver.resolve(preference: preference)
        UserDefaults.standard.set(preference.rawValue, forKey: Self.languagePreferenceKey)
        Task { await refreshOnDeviceAvailability() }
    }

    func localized(_ chinese: String, _ english: String) -> String {
        effectiveLanguage.isChinese ? chinese : english
    }

    var calories: Double? { nutritionSummary?.totals.energyKcal }
    var calorieText: String { calories.map { "\(Int($0.rounded()))" } ?? "—" }
    var hasMissingCoreNutrients: Bool {
        NutrientCatalog.core.contains { nutritionSummary?.totals[$0]?.status == .missing }
    }
    var totalBurnText: String { energyBalance?.totalBurnKcal.map { "\(Int($0.rounded()))" } ?? "—" }
    var totalBalanceText: String { energyBalance?.totalBalanceKcal.map { String(format: "%+.0f", $0) } ?? "—" }
    var activeBalanceText: String { energyBalance?.activeBalanceKcal.map { String(format: "%+.0f", $0) } ?? "—" }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if !hasLoadedSavedFoods {
                for food in try await store.allFoods() {
                    await catalog.upsert(food)
                }
                hasLoadedSavedFoods = true
            }
            if !hasLoadedComposites {
                compositeFoods = try await store.allComposites()
                let compositeCalculator = CompositeNutritionCalculator()
                for composite in compositeFoods {
                    if let food = try? compositeCalculator.foodItem(from: composite) {
                        await catalog.upsert(food)
                    }
                }
                hasLoadedComposites = true
            }
            await refreshOnDeviceAvailability()
            entries = try await store.entries(dayKey: dayKey)
            nutritionSummary = calculator.summarize(
                entries: entries,
                expectedNutrients: NutrientCatalog.definitions.map(\.id)
            )
            balanceGoal = try await store.balanceGoal(effectiveOn: dayKey)
            await refreshHealthData()
            await refreshCloudState()
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    func refresh() async {
        await load()
    }

    func searchFoods(query: String, limit: Int = 30) async -> [FoodItem] {
        await catalog.search(query: query, limit: limit, language: effectiveLanguage)
    }

    func searchFoodResults(query: String, limit: Int = 30) async -> [FoodSearchResult] {
        await catalog.searchResults(query: query, limit: limit, language: effectiveLanguage)
    }

    func previewNutrition(food: FoodItem, quantity: FoodQuantity) throws -> NutritionComputation {
        try calculator.compute(food: food, quantity: quantity)
    }

    @discardableResult
    func add(food: FoodItem, quantity: FoodQuantity, mealType: MealType? = nil) async throws -> DiaryEntry {
        let computed = try calculator.compute(food: food, quantity: quantity)
        let occurredAt = selectedDate
        let targetMeal = mealType ?? selectedMeal
        let moment = Calendar.current.date(bySettingHour: suggestedHour(for: targetMeal), minute: 0, second: 0, of: occurredAt) ?? occurredAt
        let entry = DiaryEntry(
            dayKey: DayKey.make(from: moment),
            occurredAt: moment,
            mealType: targetMeal,
            foodID: food.id,
            foodName: food.name,
            foodNameZh: food.nameZh ?? (effectiveLanguage.isChinese ? food.name : nil),
            foodNameEn: food.nameEn ?? (!effectiveLanguage.isChinese ? food.name : nil),
            quantityDescription: describe(quantity, food: food, language: effectiveLanguage),
            quantityDescriptionZh: describe(quantity, food: food, language: .simplifiedChinese),
            quantityDescriptionEn: describe(quantity, food: food, language: .english),
            normalizedAmount: computed.normalizedAmount,
            normalizedUnit: computed.normalizedUnit,
            nutrients: computed.nutrients,
            source: food.source.kind == .custom ? .userFood : .bundledCatalog
        )
        try await store.save(entry)
        await load()
        try? await syncHealth(dayKey: entry.dayKey, mealType: entry.mealType)
        scheduleCloudSync()
        return entry
    }

    func isMovingEntry(_ entryID: UUID) -> Bool {
        movingEntryIDs.contains(entryID)
    }

    @discardableResult
    func move(entry: DiaryEntry, to targetMeal: MealType) async throws -> DiaryEntry {
        guard entry.mealType != targetMeal, !movingEntryIDs.contains(entry.id) else {
            return entry
        }
        movingEntryIDs.insert(entry.id)
        defer { movingEntryIDs.remove(entry.id) }

        guard let current = try await store.entries(dayKey: entry.dayKey)
            .first(where: { $0.id == entry.id }) else {
            return entry
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: current.timeZoneIdentifier) ?? .current
        let targetTime = calendar.date(
            bySettingHour: suggestedHour(for: targetMeal),
            minute: 0,
            second: 0,
            of: current.occurredAt
        ) ?? current.occurredAt
        let moved = current.moved(to: targetMeal, occurredAt: targetTime)

        try await store.save(moved)
        await load()
        try? await syncHealth(dayKey: current.dayKey, mealType: current.mealType)
        try? await syncHealth(dayKey: moved.dayKey, mealType: moved.mealType)
        scheduleCloudSync()
        return moved
    }

    func delete(entry: DiaryEntry, deletePhotos: Bool = false) async {
        do {
            try await store.delete(id: entry.id)
            if deletePhotos, !entry.photoFilenames.isEmpty {
                await photoFiles.delete(entry.photoFilenames)
            }
            await load()
            try await syncHealth(dayKey: entry.dayKey, mealType: entry.mealType)
            scheduleCloudSync()
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    func setBalanceGoal(_ target: Double) async {
        do {
            let goal = BalanceGoal(effectiveDayKey: dayKey, targetBalanceKcal: target)
            try await store.saveBalanceGoal(goal)
            balanceGoal = goal
            recalculateBalance()
            scheduleCloudSync()
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    func importFoods(_ foods: [FoodItem]) async throws {
        for food in foods {
            try await store.saveFood(food)
            await catalog.upsert(food)
        }
        scheduleCloudSync()
    }

    func saveComposite(_ composite: CompositeFoodDefinition) async throws {
        try await store.saveComposite(composite)
        let food = try CompositeNutritionCalculator().foodItem(from: composite)
        await catalog.upsert(food)
        if !compositeFoods.contains(where: { $0.id == composite.id }) {
            compositeFoods.append(composite)
        } else if let index = compositeFoods.firstIndex(where: { $0.id == composite.id }) {
            compositeFoods[index] = composite
        }
        scheduleCloudSync()
    }

    func makeJSONBackup() async -> Data? {
        do {
            return try await makeJSONBackupThrowing()
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
            return nil
        }
    }

    private func makeJSONBackupThrowing() async throws -> Data {
        let allEntries = try await store.allEntries()
        let energyDays = try await store.allEnergy()
        let goal = try await store.balanceGoal(effectiveOn: dayKey)
        let conflicts = try await store.unresolvedConflicts()
        let savedFoods = try await store.allFoods()
        let compositeFoods = try await store.allComposites()
        return try dataTransfer.makeJSONBackup(
            entries: allEntries,
            energyDays: energyDays,
            goals: goal.map { [$0] } ?? [],
            conflicts: conflicts,
            savedFoods: savedFoods,
            compositeFoods: compositeFoods
        )
    }

    func restoreJSONBackup(_ data: Data, mode: BackupRestoreMode) async throws -> BackupRestoreSummary {
        let backup = try dataTransfer.decodeJSONBackup(data)
        let summary = try await store.restore(backup, mode: mode)
        await load()
        scheduleCloudSync()
        return summary
    }

    func makeMediaBackup() async throws -> Data {
        let json = try await makeJSONBackupThrowing()
        let photos = await photoFiles.allData()
        return try mediaBackup.make(backupJSON: json, photos: photos)
    }

    func restoreMediaBackup(_ data: Data, mode: BackupRestoreMode) async throws -> BackupRestoreSummary {
        let contents = try mediaBackup.read(data)
        let backup = try dataTransfer.decodeJSONBackup(contents.backupJSON)
        let summary = try await store.restore(backup, mode: mode)
        try await photoFiles.restore(contents.photos, replaceExisting: mode == .replace)
        await load()
        return summary
    }

    func deleteAllLocalData() async throws {
        try await store.deleteAllLocalData()
        await photoFiles.deleteAll()
        await photoLearning.clearAll()
        entries = []
        nutritionSummary = nil
        energySummary = nil
        balanceGoal = nil
        energyBalance = nil
        compositeFoods = []
        healthSources = []
        await load()
    }

    func makeCSV() async -> Data? {
        do {
            let allEntries = try await store.allEntries()
            return dataTransfer.makeCSV(entries: allEntries)
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
            return nil
        }
    }

    func suggestedHour(for meal: MealType) -> Int {
        switch meal {
        case .breakfast: 8
        case .lunch: 12
        case .dinner: 18
        case .snack: 15
        }
    }

    private func describe(_ quantity: FoodQuantity, food: FoodItem, language: AppLanguage) -> String {
        switch (quantity, language) {
        case (.edibleGrams(let grams), .simplifiedChinese): "\(grams) 克可食部"
        case (.purchasedGrams(let grams), .simplifiedChinese): "\(grams) 克购买重量"
        case (.milliliters(let milliliters), .simplifiedChinese): "\(milliliters) 毫升"
        case (.portion(let id, let count), .simplifiedChinese):
            if let portion = food.portion(id: id) { "\(count) × \(portion.localizedLabel(for: language))" } else { "\(count) 份" }
        case (.edibleGrams(let grams), .english): "\(grams) g edible portion"
        case (.purchasedGrams(let grams), .english): "\(grams) g purchased weight"
        case (.milliliters(let milliliters), .english): "\(milliliters) ml"
        case (.portion(let id, let count), .english):
            if let portion = food.portion(id: id) { "\(count) × \(portion.localizedLabel(for: language))" } else { "\(count) serving(s)" }
        }
    }

}
