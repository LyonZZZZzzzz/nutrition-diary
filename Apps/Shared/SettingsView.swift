import SwiftUI
import UniformTypeIdentifiers
import NutritionKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showExporter = false
    @State private var exportDocument: ExportDocument?
    @State private var exportType: UTType = .json
    @State private var exportName = "NutritionBackup.json"
    @State private var balanceGoal = 0.0
    @State private var includeEstimated = false
    @State private var showDeepSeekSettings = false
    @State private var showCSVImporter = false
    @State private var importPreview: CatalogImportPreview?
    @State private var importPreviewPresented = false
    @State private var showRestoreImporter = false
    @State private var showMediaImporter = false
    @State private var pendingBackupImport: PendingBackupImport?
    @State private var showDeleteLocalConfirmation = false
    @State private var showDeleteCloudConfirmation = false
    @State private var restoreSummary: BackupRestoreSummary?
    private let appVersion = AppVersion.current

    private func sourceSummary(_ source: HealthEnergySource) -> String {
        let missing = model.localized("缺失", "Missing")
        let active = source.activeKcal.map { "\(Int($0.rounded())) kcal" } ?? missing
        let basal = source.basalKcal.map { "\(Int($0.rounded())) kcal" } ?? missing
        let exercise = source.exerciseMinutes.map {
            model.effectiveLanguage.isChinese ? "\(Int($0.rounded())) 分钟" : "\(Int($0.rounded())) min"
        } ?? missing
        return model.effectiveLanguage.isChinese
            ? "活动 \(active) · 静息 \(basal) · 锻炼 \(exercise)"
            : "Active \(active) · Resting \(basal) · Exercise \(exercise)"
    }

    var body: some View {
        Form {
            Section {
                Picker("语言", selection: Binding(
                    get: { model.languagePreference },
                    set: { model.setLanguagePreference($0) }
                )) {
                    Text(model.localized("跟随系统", "Follow System")).tag(AppLanguagePreference.system)
                    Text("简体中文").tag(AppLanguagePreference.simplifiedChinese)
                    Text("English").tag(AppLanguagePreference.english)
                }
                Text(model.localized("应用内语言切换会立即生效；系统权限弹窗和主屏幕名称跟随设备语言。", "The in-app language changes immediately. System permission prompts and the Home Screen name follow the device language."))
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text(model.localized("语言 / Language", "Language"))
            }

            Section("健康与 Apple Watch") {
                #if os(iOS)
                Button("授权读取活动/静息能量并写入膳食营养") {
                    Task { await model.requestHealthAuthorization() }
                }
                LabeledContent("健康状态", value: model.healthStatusText)
                if let updated = model.healthLastUpdatedAt {
                    LabeledContent(
                        "最后更新",
                        value: updated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(model.effectiveLanguage.locale))
                    )
                }
                Picker("能量来源", selection: Binding(
                    get: { model.preferredHealthSourceID ?? "auto" },
                    set: { value in Task { await model.setPreferredHealthSource(value == "auto" ? nil : value) } }
                )) {
                    Text("自动（Apple Watch 优先）").tag("auto")
                    ForEach(model.healthSources) { source in
                        Text(source.localizedDisplayName(for: model.effectiveLanguage)).tag(source.id)
                    }
                }
                if !model.healthSources.isEmpty {
                    ForEach(model.healthSources) { source in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.localizedDisplayName(for: model.effectiveLanguage)).font(.subheadline.bold())
                            Text(sourceSummary(source))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button("立即刷新") { Task { await model.refreshHealthData() } }
                    Link("管理健康权限", destination: URL(string: "x-apple-health://")!)
                }
                Text("活动、静息和锻炼时间按来源分别选择，不会把多个设备相加。App 仅在前台、回到前台或 HealthKit 数据变化时刷新。")
                    .font(.footnote).foregroundStyle(.secondary)
                #else
                Label("HealthKit 写入仅在 iPhone 上进行", systemImage: "iphone")
                Text("Mac 查看 iPhone 通过 CloudKit 同步的每日活动、静息和总消耗汇总。当前构建尚未配置真实 CloudKit 容器时，数据仅保存在本机。")
                    .font(.footnote).foregroundStyle(.secondary)
                #endif
                Toggle("允许把照片估算值写入 Health", isOn: $includeEstimated)
                    .onChange(of: includeEstimated) { _, value in model.allowEstimatedHealthWrites = value }
            }

            #if os(iOS)
            Section("DeepSeek 照片识别") {
                LabeledContent("模型", value: "deepseek-flash Vision")
                LabeledContent("状态", value: model.deepSeekStatusText)
                Button(model.deepSeekConfigured ? model.localized("管理 DeepSeek API Key", "Manage DeepSeek API Key") : model.localized("配置 DeepSeek API Key", "Configure DeepSeek API Key")) {
                    showDeepSeekSettings = true
                }
                Button("测试已保存 Key") {
                    Task { await model.testDeepSeekAPIKey() }
                }
                .disabled(!model.deepSeekConfigured)
                Text("DeepSeek 只用于识别菜品、份量和营养标签文字。每次分析前都会确认照片上传，API 费用由你的账户承担。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            #endif

            Section("热量平衡目标") {
                Text("目标为正值表示每日盈余，负值表示每日缺口。App 不提供医学建议。")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Slider(value: $balanceGoal, in: -1000...1000, step: 50)
                    Text("\(Int(balanceGoal)) kcal").monospacedDigit()
                }
                Button("保存目标") {
                    Task { await model.setBalanceGoal(balanceGoal) }
                }
            }

            Section("食物目录") {
                NavigationLink("食物数据来源与许可证") { FoodDataSourceView() }
                Button("导入 CSV 食物数据") { showCSVImporter = true }
                Text("CSV 支持稳定营养代码，例如 energy_kcal、protein_g、calcium_mg。导入前会显示未知列、重复项和单位错误。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("备份与恢复") {
                Button("导出完整 JSON 备份") {
                    Task {
                        if let data = await model.makeJSONBackup() {
                            exportDocument = ExportDocument(data: data)
                            exportType = .json
                            exportName = "NutritionBackup-\(model.dayKey).json"
                            showExporter = true
                        }
                    }
                }
                Button("导出含照片媒体备份 ZIP") {
                    Task {
                        do {
                            let data = try await model.makeMediaBackup()
                            exportDocument = ExportDocument(data: data)
                            exportType = .zip
                            exportName = "NutritionMediaBackup-\(model.dayKey).zip"
                            showExporter = true
                        } catch {
                            model.errorMessage = localizedApplicationError(error, language: model.effectiveLanguage)
                        }
                    }
                }
                Button("恢复 JSON 备份") { showRestoreImporter = true }
                Button("恢复媒体备份 ZIP") { showMediaImporter = true }
                Button("导出每日记录 CSV") {
                    Task {
                        if let data = await model.makeCSV() {
                            exportDocument = ExportDocument(data: data)
                            exportType = .commaSeparatedText
                            exportName = "NutritionEntries-\(model.dayKey).csv"
                            showExporter = true
                        }
                    }
                }
                Text("JSON 不包含本地餐食原图；媒体备份 ZIP 同时包含 JSON 和本地照片。DeepSeek Key、HealthKit 原始数据和 iCloud 凭据不会进入备份。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("数据删除") {
                Button("删除本机数据", role: .destructive) { showDeleteLocalConfirmation = true }
                Button("删除本机与 iCloud 数据", role: .destructive) { showDeleteCloudConfirmation = true }
                Text("本机删除会移除当前设备的饮食记录、自定义食物、目标、汇总、同步元数据、冲突副本和本地照片。删除 iCloud 数据会同时删除当前私有 CloudKit Zone；Health App 中已写入的膳食样本不会自动删除。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section(model.localized("数据与来源", "Data & sources")) {
                Label("Apple 本机照片识别不上传照片", systemImage: "lock.shield")
                #if os(iOS)
                Label("DeepSeek 仅在每次确认后接收所选照片", systemImage: "cloud")
                #endif
                Label("USDA FoodData Central 公共领域种子数据", systemImage: "book.closed")
                Label("Open Food Facts 依 ODbL 归属使用", systemImage: "barcode")
                Link("支持与问题反馈", destination: URL(string: "https://lyonzhu.github.io/nutrition-diary-legal/support.html")!)
            }

            Section("iCloud 同步") {
                LabeledContent("状态", value: model.syncStatusText)
                LabeledContent("iCloud 账号", value: model.cloudAccountText)
                LabeledContent("待上传", value: "\(model.cloudSyncState.pendingUploadCount)")
                LabeledContent("未解决冲突", value: "\(model.cloudSyncState.conflictCount)")
                if let lastSync = model.cloudSyncState.lastSuccessfulSync {
                    LabeledContent(
                        "最后成功同步",
                        value: lastSync.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(model.effectiveLanguage.locale))
                    )
                }
                if let error = model.cloudSyncState.lastErrorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                if model.cloudSyncState.requiresAccountSwitchConfirmation {
                    Button("确认使用当前 iCloud 账号") {
                        Task { await model.confirmCloudAccount() }
                    }
                    Text("iCloud 账号已变化。确认前不会上传上一账号的数据，也不会自动合并到新账号。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("立即同步") {
                    Task { await model.synchronizeCloud(showErrors: true) }
                }
                Text("使用 CKSyncEngine 和私有自定义 Zone 同步日记、自定义食物、复合食物、每日能量汇总与目标。照片、DeepSeek Key、健康和语言偏好不进入 CloudKit。离线修改保留在本机并等待下一次同步。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: appVersion.version == "未知" ? model.localized("未知", "Unknown") : appVersion.version)
                LabeledContent("构建", value: appVersion.build == "未知" ? model.localized("未知", "Unknown") : appVersion.build)
                HStack {
                    Text("完整版本")
                    Spacer()
                    Text(appVersion.displayText(for: model.effectiveLanguage))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("设置")
        .onAppear {
            balanceGoal = model.balanceGoal?.targetBalanceKcal ?? 0
            includeEstimated = model.allowEstimatedHealthWrites
        }
        .sheet(isPresented: $showDeepSeekSettings) {
            DeepSeekKeyEditorView()
        }
        .sheet(isPresented: $importPreviewPresented, onDismiss: { importPreview = nil }) {
            if let importPreview {
                CatalogImportPreviewView(preview: importPreview)
            }
        }
        .fileImporter(isPresented: $showRestoreImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            loadImportedBackup(result, kind: .json)
        }
        .fileImporter(isPresented: $showMediaImporter, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            loadImportedBackup(result, kind: .media)
        }
        .fileImporter(isPresented: $showCSVImporter, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: false) { result in
            do {
                let url = try result.get().first
                guard let url else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                importPreview = try CSVFoodCatalogImporter().previewCSV(data)
                importPreviewPresented = true
            } catch {
                model.errorMessage = localizedApplicationError(error, language: model.effectiveLanguage)
            }
        }
        .confirmationDialog(
            "恢复备份",
            isPresented: Binding(
                get: { pendingBackupImport != nil },
                set: { if !$0 { pendingBackupImport = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingBackupImport
        ) { pending in
            Button("合并恢复") { restore(pending, mode: .merge) }
            Button("完整替换本机数据", role: .destructive) { restore(pending, mode: .replace) }
            Button("取消", role: .cancel) { pendingBackupImport = nil }
        } message: { _ in
            Text("合并恢复会保留较新的本机记录并将冲突写入冲突副本；完整替换会先删除当前设备上的饮食数据。")
        }
        .confirmationDialog("删除本机数据？", isPresented: $showDeleteLocalConfirmation, titleVisibility: .visible) {
            Button("删除本机数据", role: .destructive) {
                Task {
                    do { try await model.deleteAllLocalData() }
                    catch { model.errorMessage = localizedApplicationError(error, language: model.effectiveLanguage) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销。Health App 中已写入的膳食样本不会自动删除。")
        }
        .confirmationDialog("删除本机与 iCloud 数据？", isPresented: $showDeleteCloudConfirmation, titleVisibility: .visible) {
            Button("删除本机与 iCloud 数据", role: .destructive) {
                Task {
                    do { try await model.deleteAllLocalAndCloudData() }
                    catch { model.errorMessage = localizedApplicationError(error, language: model.effectiveLanguage) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除当前 iCloud 私有 Zone 中的所有同步记录，并清除本机数据与照片。Health App 中已写入的膳食样本仍需在 Health 内单独删除。")
        }
        .alert("恢复完成", isPresented: Binding(
            get: { restoreSummary != nil },
            set: { if !$0 { restoreSummary = nil } }
        )) {
            Button("好", role: .cancel) { restoreSummary = nil }
        } message: {
            if let summary = restoreSummary {
                Text(model.localized(
                    "新增 \(summary.added) 项，更新 \(summary.updated) 项，未变 \(summary.unchanged) 项，冲突 \(summary.conflicts) 项。",
                    "Added \(summary.added), updated \(summary.updated), unchanged \(summary.unchanged), conflicts \(summary.conflicts)."
                ))
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: exportType,
            defaultFilename: exportName
        ) { _ in }
    }

    private func loadImportedBackup(_ result: Result<[URL], Error>, kind: BackupImportKind) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            pendingBackupImport = PendingBackupImport(kind: kind, data: try Data(contentsOf: url))
        } catch {
            model.errorMessage = localizedApplicationError(error, language: model.effectiveLanguage)
        }
    }

    private func restore(_ pending: PendingBackupImport, mode: BackupRestoreMode) {
        pendingBackupImport = nil
        Task {
            do {
                switch pending.kind {
                case .json:
                    restoreSummary = try await model.restoreJSONBackup(pending.data, mode: mode)
                case .media:
                    restoreSummary = try await model.restoreMediaBackup(pending.data, mode: mode)
                }
            } catch {
                model.errorMessage = localizedApplicationError(error, language: model.effectiveLanguage)
            }
        }
    }
}

private enum BackupImportKind: Sendable {
    case json
    case media
}

private struct PendingBackupImport: Identifiable, Sendable {
    let id = UUID()
    let kind: BackupImportKind
    let data: Data
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .zip] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
