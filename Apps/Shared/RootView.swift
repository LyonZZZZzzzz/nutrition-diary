import SwiftUI
import NutritionKit

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case photo
    case history
    case foods
    case settings

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.today, .simplifiedChinese): "今日"
        case (.photo, .simplifiedChinese): "拍照"
        case (.history, .simplifiedChinese): "历史"
        case (.foods, .simplifiedChinese): "食物"
        case (.settings, .simplifiedChinese): "设置"
        case (.today, .english): "Today"
        case (.photo, .english): "Photo"
        case (.history, .english): "History"
        case (.foods, .english): "Foods"
        case (.settings, .english): "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max.fill"
        case .photo: "camera.fill"
        case .history: "chart.xyaxis.line"
        case .foods: "fork.knife"
        case .settings: "gearshape.fill"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSection: AppSection = .today

    var body: some View {
        Group {
            #if os(iOS)
            TabView(selection: $selectedSection) {
                ForEach(AppSection.allCases) { section in
                    NavigationStack {
                        destination(for: section)
                    }
                    .tag(section)
                    .tabItem { Label(section.title(for: model.effectiveLanguage), systemImage: section.systemImage) }
                }
            }
            #else
            NavigationSplitView {
                List(AppSection.allCases, selection: Binding(
                    get: { selectedSection },
                    set: { selectedSection = $0 ?? .today }
                )) { section in
                    Label(section.title(for: model.effectiveLanguage), systemImage: section.systemImage).tag(section)
                }
                .navigationTitle("饮食营养记录")
            } detail: {
                NavigationStack { destination(for: selectedSection) }
            }
            #endif
        }
        .tint(.accentColor)
        .environment(\.locale, model.effectiveLanguage.locale)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.handleAppBecameActive() }
        }
        .task {
            model.startHealthObservation()
            await model.load()
            await model.startCloudSync()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--open-photo-tab") {
                selectedSection = .photo
            }
            if ProcessInfo.processInfo.arguments.contains("--open-foods-tab") {
                selectedSection = .foods
            }
            if ProcessInfo.processInfo.arguments.contains("--open-settings-tab") {
                selectedSection = .settings
            }
            #if os(iOS)
            if ProcessInfo.processInfo.arguments.contains("--test-health-authorization") {
                await model.requestHealthAuthorization()
            }
            #endif
            #endif
        }
        .alert("出现错误", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .today:
            TodayView()
        case .photo:
            PhotoMealView()
        case .history:
            HistoryView()
        case .foods:
            FoodsView()
        case .settings:
            SettingsView()
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    var unit: String = ""
    var tint: Color = .accentColor
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct NutrientRow: View {
    @Environment(AppModel.self) private var model
    let definition: NutrientDefinition
    let measurement: NutrientMeasurement?

    var body: some View {
        HStack {
            Text(definition.localizedName(for: model.effectiveLanguage))
            Spacer()
            if let value = measurement?.value {
                Text("\(NSDecimalNumber(decimal: value).doubleValue, specifier: "%.\(definition.displayDigits)f") \(definition.unit.symbol)")
                    .monospacedDigit()
            } else {
                Text("缺失").foregroundStyle(.secondary)
            }
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch measurement?.status {
        case .estimated:
            Text("估算").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(.orange.opacity(0.15), in: Capsule())
        case .missing, .none:
            Text("不完整").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(.red.opacity(0.12), in: Capsule())
        case .complete:
            EmptyView()
        }
    }
}
