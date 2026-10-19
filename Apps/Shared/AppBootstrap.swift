import Observation
import SwiftUI
import NutritionKit

@MainActor
@Observable
final class AppBootstrap {
    @ObservationIgnored private let factory: () throws -> AppModel
    var model: AppModel?
    var errorMessage: String?
    var isResetting = false

    init(factory: @escaping () throws -> AppModel) {
        self.factory = factory
        start()
    }

    func retry() {
        start()
    }

    func resetLocalDatabase() async {
        isResetting = true
        defer { isResetting = false }
        do {
            try NutritionStoreFactory.resetDefaultStore()
            await LocalPhotoStore().deleteAll()
            await PhotoMatchLearningStore().clearAll()
            start()
        } catch {
            errorMessage = StartupErrorDiagnostics.describe(error)
        }
    }

    private func start() {
        do {
            model = try factory()
            errorMessage = nil
        } catch {
            model = nil
            errorMessage = StartupErrorDiagnostics.describe(error)
        }
    }
}


enum StartupErrorDiagnostics {
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var lines = [
            "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)",
            "Type: \(String(reflecting: error))"
        ]
        if !nsError.userInfo.isEmpty {
            lines.append("UserInfo: \(nsError.userInfo)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("Underlying: \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)")
            if !underlying.userInfo.isEmpty {
                lines.append("Underlying UserInfo: \(underlying.userInfo)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct StartupErrorView: View {
    @Environment(AppBootstrap.self) private var bootstrap
    @AppStorage("appLanguagePreference") private var languagePreference = AppLanguagePreference.system.rawValue
    @State private var confirmsReset = false

    private var language: AppLanguage {
        AppLanguageResolver.resolve(
            preference: AppLanguagePreference(rawValue: languagePreference) ?? .system
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 52))
                        .foregroundStyle(.orange)
                    Text("启动失败")
                        .font(.largeTitle.bold())
                    Text("本地数据库无法打开。现有文件不会被自动删除。可以先重试；只有确认后才允许重建本地数据库。")
                        .foregroundStyle(.secondary)
                    Text(bootstrap.errorMessage ?? "未知错误")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    Text(language.isChinese
                         ? "数据库位置：\(NutritionStoreFactory.defaultStoreURL.path)"
                         : "Database location: \(NutritionStoreFactory.defaultStoreURL.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    VStack(spacing: 12) {
                        Button("重试") { bootstrap.retry() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        Button("重建本地数据库", role: .destructive) { confirmsReset = true }
                            .frame(maxWidth: .infinity)
                            .disabled(bootstrap.isResetting)
                        if bootstrap.isResetting { ProgressView() }
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding()
            }
            .navigationTitle("饮食营养记录")
        }
        .environment(\.locale, language.locale)
        .confirmationDialog("重建本地数据库？", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("删除本地数据库和照片并重建", role: .destructive) {
                Task { await bootstrap.resetLocalDatabase() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销。Health App 中已写入的膳食样本不会自动删除。")
        }
    }
}
