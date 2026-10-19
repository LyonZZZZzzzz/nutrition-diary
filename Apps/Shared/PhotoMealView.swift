import SwiftUI
import NutritionKit

#if os(iOS)
import PhotosUI
#endif

struct PhotoMealView: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @State private var selectedItems: [PhotosPickerItem] = []
    #endif
    @State private var photoData: [Data] = []
    @State private var selectedMode: PhotoRecognitionMode = .meal
    @State private var showCloudConsent = false
    @State private var showMealReview = false
    @State private var showPackagedReview = false
    @State private var showKeyEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                introCard
                modePicker
                captureCard
                if !photoData.isEmpty {
                    photoGrid
                    analysisButtons
                }
                if selectedMode == .meal && model.photoAnalysisAvailability != .available {
                    localUnavailableCard
                }
                privacyCard
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color.platformGroupedBackground)
        .navigationTitle("拍照记录")
        .alert("发送照片到 DeepSeek？", isPresented: $showCloudConsent) {
            Button("取消", role: .cancel) {}
            Button("继续识别") {
                Task {
                    await model.analyzePhotos(photoData, provider: .deepSeek, mode: selectedMode)
                    // Let the consent alert finish dismissing before presenting the review sheet.
                    try? await Task.sleep(for: .milliseconds(350))
                    showResultIfAvailable()
                }
            }
        } message: {
            Text("最多 3 张照片将发送至 DeepSeek（deepseek-flash）。API 费用由你的账户承担；原图仍只保存在本机。")
        }
        .sheet(isPresented: $showMealReview, onDismiss: { model.photoReview = nil }) {
            PhotoReviewView()
        }
        .sheet(isPresented: $showPackagedReview, onDismiss: { model.packagedLabelReview = nil }) {
            PackagedLabelReviewView()
        }
        .sheet(isPresented: $showKeyEditor) {
            DeepSeekKeyEditorView()
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("最多三张照片", systemImage: "camera.viewfinder")
                .font(.title3.bold())
            Text("先拍一张全景，再补充近景。识别只提供菜品、份量或标签信息，必须由你确认后才计入营养。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var modePicker: some View {
        Picker("识别类型", selection: $selectedMode) {
            ForEach(PhotoRecognitionMode.allCases, id: \.self) { mode in
                Text(mode.localizedTitle(for: model.effectiveLanguage)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var captureCard: some View {
        VStack(spacing: 14) {
            #if os(iOS)
            HStack(spacing: 12) {
                CameraCaptureButton { data in
                    appendPhoto(data)
                } label: {
                    Label("拍摄照片", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)
                PhotosPicker(selection: $selectedItems, maxSelectionCount: 3, matching: .images) {
                    Label("从照片库选择", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }
            .onChange(of: selectedItems) { _, items in
                Task { await loadPickerItems(items) }
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-photo-fixture") ||
                ProcessInfo.processInfo.arguments.contains("--ui-testing-photo-low-confidence") {
                Button(model.localized("加载测试餐照片", "Load test meal photo")) {
                    appendPhoto(Self.uiTestPhotoData)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("photo.loadFixture")
            }
            #endif
            #else
            ContentUnavailableView("照片识别仅在 iPhone 上可用", systemImage: "iphone", description: Text("Mac 可查看同步后的营养条目和热量平衡。"))
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var analysisButtons: some View {
        VStack(spacing: 12) {
            if model.deepSeekConfigured {
                Button {
                    showCloudConsent = true
                } label: {
                    HStack {
                        if model.isAnalyzingPhotos { ProgressView() }
                        Label(model.isAnalyzingPhotos ? model.localized("正在请求 DeepSeek…", "Requesting DeepSeek…") : model.localized("使用 DeepSeek 识别", "Recognize with DeepSeek"), systemImage: "cloud.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isAnalyzingPhotos)
                .accessibilityIdentifier("photo.deepSeekAnalyze")
            } else {
                Button {
                    showKeyEditor = true
                } label: {
                    Label("配置 DeepSeek API Key", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if selectedMode == .meal && model.photoAnalysisAvailability == .available {
                Button {
                    Task {
                        await model.analyzePhotos(photoData, provider: .appleOnDevice, mode: .meal)
                        showResultIfAvailable()
                    }
                } label: {
                    Label("使用 Apple 本机识别", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isAnalyzingPhotos)
            }
        }
    }

    private var photoGrid: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(photoData.enumerated()), id: \.offset) { index, data in
                    ZStack(alignment: .topTrailing) {
                        PlatformMealImage(data: data)
                            .scaledToFill()
                            .frame(width: 180, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Button {
                            photoData.remove(at: index)
                            clearPickerSelection()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .padding(8)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var localUnavailableCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Apple 本机识别不可用", systemImage: "info.circle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text(availabilityMessage)
                .font(.footnote).foregroundStyle(.secondary)
            Text("可改用 DeepSeek 云端识别，照片只会在你每次确认后上传。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("照片默认保存在本机", systemImage: "lock.shield.fill")
                .font(.footnote.bold())
            Text("Apple 本机识别不上传照片。DeepSeek 识别仅在每次确认后发送照片，App 不保留云端副本。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var availabilityMessage: String {
        model.photoAnalysisAvailability.localizedDescription(for: model.effectiveLanguage)
    }

    private func showResultIfAvailable() {
        showMealReview = model.photoReview != nil
        showPackagedReview = model.packagedLabelReview != nil
    }

    private func appendPhoto(_ data: Data) {
        guard photoData.count < 3 else { return }
        photoData.append(data)
    }

    private func clearPickerSelection() {
        #if os(iOS)
        selectedItems = []
        #endif
    }

    #if os(iOS)
    private func loadPickerItems(_ items: [PhotosPickerItem]) async {
        photoData = []
        for item in items.prefix(3) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                photoData.append(data)
            }
        }
    }
    #endif

    private static let uiTestPhotoData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=") ?? Data([0x89, 0x50, 0x4E, 0x47])
}

struct PhotoReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mealType: MealType = .lunch

    var body: some View {
        NavigationStack {
            List {
                Section("整体分析") {
                    if let provider = model.photoReview?.provider {
                        LabeledContent("识别来源", value: provider.localizedTitle(for: model.effectiveLanguage))
                    }
                    LabeledContent("识别轮次", value: model.localized("\(model.photoReview?.analysisPasses ?? 1) 次", "\(model.photoReview?.analysisPasses ?? 1) pass(es)"))
                        .accessibilityIdentifier("photo.review.passes")
                    Text(model.photoReview?.analyzedMeal.analysisNote ?? "")
                        .font(.footnote)
                    if let note = model.photoReview?.secondPassNote {
                        Text(note).font(.footnote).foregroundStyle(.orange)
                    }
                    LabeledContent("整体置信度", value: "\(Int((model.photoReview?.analyzedMeal.overallConfidence ?? 0) * 100))%")
                }
                ForEach(Array((model.photoReview?.items ?? []).indices), id: \.self) { index in
                    Section(model.localized("识别菜品 \(index + 1)", "Recognized dish \(index + 1)")) {
                        reviewItem(index: index)
                    }
                }
                Section("保存到") {
                    Picker("餐次", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in Text(meal.localizedTitle(for: model.effectiveLanguage)).tag(meal) }
                    }
                }
                Section {
                    Text("照片结果属于估算，需确认后才计入。识别不到的食物可返回普通搜索录入。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("确认识别结果")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("计入记录") {
                        Task {
                            await model.commitPhotoReview(mealType: mealType)
                            dismiss()
                        }
                    }
                    .disabled(!(model.photoReview?.items.contains { $0.include && $0.selectedFood != nil } ?? false))
                    .accessibilityIdentifier("photo.review.confirm")
                }
            }
        }
        .onAppear { mealType = model.selectedMeal }
    }

    @ViewBuilder
    private func reviewItem(index: Int) -> some View {
        if let binding = bindingForItem(index: index) {
            Toggle("计入此菜品", isOn: Binding(
                get: { binding.wrappedValue.include },
                set: { binding.wrappedValue.include = $0 }
            ))
            LabeledContent("识别名称", value: binding.wrappedValue.dish.name)
                .accessibilityIdentifier("photo.review.dish.\(index)")
            if !binding.wrappedValue.dish.visibleIngredients.isEmpty {
                Text(model.localized("可见食材：\(binding.wrappedValue.dish.visibleIngredients.joined(separator: "、"))", "Visible ingredients: \(binding.wrappedValue.dish.visibleIngredients.joined(separator: ", "))"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let oil = binding.wrappedValue.dish.hiddenOilLevel, !oil.isEmpty {
                Text(model.localized("油汁判断：\(oil)", "Hidden oil: \(oil)")).font(.caption).foregroundStyle(.secondary)
            }
            Picker(model.localized("餐具规格", "Plateware"), selection: platewareBinding(index: index)) {
                Text(model.localized("未选择（扩大范围）", "Not selected (wider range)")).tag(nil as PlatewareSpec?)
                ForEach(PlatewareSpec.allCases) { spec in
                    Text(spec.localizedTitle(for: model.effectiveLanguage)).tag(Optional(spec))
                }
            }
            Menu {
                ForEach(binding.wrappedValue.candidates) { match in
                    Button("\(match.food.localizedName(for: model.effectiveLanguage)) · \(match.matchedTerm) · \(Int(match.score * 100))%") {
                        binding.wrappedValue.selectedFood = match.food
                    }
                }
            } label: {
                LabeledContent("匹配食物", value: binding.wrappedValue.selectedFood?.localizedName(for: model.effectiveLanguage) ?? model.localized("未自动匹配，请手动选择", "No automatic match; select manually"))
            }
            .accessibilityIdentifier("photo.review.match.\(index)")
            if let first = binding.wrappedValue.candidates.first {
                Text(model.localized("最佳匹配依据：\(first.matchedTerm) · 匹配度 \(Int(first.score * 100))%", "Best match: \(first.matchedTerm) · \(Int(first.score * 100))%"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if binding.wrappedValue.originalSelectedFoodID == nil {
                Text(model.localized(
                    "候选未达到自动选中门槛，只展示前三个结果，请人工核对。",
                    "Candidates did not meet the automatic-selection threshold. Only the top three are shown; review manually."
                ))
                    .font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("photo.review.manualCandidate.\(index)")
            }
            HStack {
                Text("份量")
                Slider(value: gramsBinding(index: index), in: 10...600, step: 5)
                Text("\(Int(binding.wrappedValue.grams.doubleValue)) g").monospacedDigit()
            }
            Text(model.localized("建议范围：\(Int(binding.wrappedValue.dish.portionMinGrams.doubleValue))–\(Int(binding.wrappedValue.dish.portionMaxGrams.doubleValue)) g", "Suggested range: \(Int(binding.wrappedValue.dish.portionMinGrams.doubleValue))–\(Int(binding.wrappedValue.dish.portionMaxGrams.doubleValue)) g"))
                .font(.caption).foregroundStyle(.secondary)
            if let suggestion = binding.wrappedValue.portionSuggestion {
                Text(model.localized(
                    "综合餐具建议：\(Int(suggestion.minimumGrams))–\(Int(suggestion.maximumGrams)) g · 建议 \(Int(suggestion.suggestedGrams)) g · 份量置信度 \(Int(suggestion.confidence * 100))%\(suggestion.usedHistory ? " · 已参考本机历史" : "")",
                    "Combined suggestion: \(Int(suggestion.minimumGrams))–\(Int(suggestion.maximumGrams)) g · suggested \(Int(suggestion.suggestedGrams)) g · \(Int(suggestion.confidence * 100))% portion confidence\(suggestion.usedHistory ? " · local history used" : "")"
                ))
                .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("置信度", value: "\(Int(binding.wrappedValue.dish.confidence * 100))%")
            if !binding.wrappedValue.dish.uncertaintyNotes.isEmpty {
                Text(binding.wrappedValue.dish.uncertaintyNotes.joined(separator: model.effectiveLanguage.isChinese ? "；" : "; "))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func bindingForItem(index: Int) -> Binding<PhotoReviewItem>? {
        guard model.photoReview != nil else { return nil }
        return Binding(
            get: {
                guard let review = model.photoReview, review.items.indices.contains(index) else {
                    return PhotoReviewItem(dish: AnalyzedDish(name: "", visibleIngredients: [], portionMinGrams: 0, portionMaxGrams: 0, confidence: 0), candidates: [], selectedFood: nil, grams: 0)
                }
                return review.items[index]
            },
            set: { newValue in
                guard model.photoReview != nil, model.photoReview!.items.indices.contains(index) else { return }
                model.photoReview!.items[index] = newValue
            }
        )
    }

    private func gramsBinding(index: Int) -> Binding<Double> {
        Binding(
            get: { bindingForItem(index: index)?.wrappedValue.grams.doubleValue ?? 0 },
            set: { newValue in
                guard var item = bindingForItem(index: index)?.wrappedValue else { return }
                item.grams = Decimal(newValue)
                bindingForItem(index: index)?.wrappedValue = item
            }
        )
    }

    private func platewareBinding(index: Int) -> Binding<PlatewareSpec?> {
        Binding(
            get: { bindingForItem(index: index)?.wrappedValue.plateware },
            set: { spec in
                guard var item = bindingForItem(index: index)?.wrappedValue else { return }
                item.plateware = spec
                let suggestion = PhotoPortionEstimator.suggest(dish: item.dish, plateware: spec)
                item.portionSuggestion = suggestion
                item.grams = Decimal(suggestion.suggestedGrams)
                bindingForItem(index: index)?.wrappedValue = item
            }
        )
    }
}

struct PackagedLabelReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mealType: MealType = .snack

    var body: some View {
        NavigationStack {
            Form {
                if let review = model.packagedLabelReview {
                    Section("产品") {
                        TextField("品牌", text: stringBinding(\.brand))
                        TextField("产品名", text: stringBinding(\.productName))
                        LabeledContent("识别置信度", value: "\(Int(review.confidence * 100))%")
                        Text(review.analysisNote).font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("营养基准") {
                        Picker("每 100", selection: Binding(
                            get: { review.referenceUnit },
                            set: { model.packagedLabelReview?.referenceUnit = $0 }
                        )) {
                            Text(model.localized("克", "g")).tag(FoodReferenceUnit.gram)
                            Text(model.localized("毫升", "ml")).tag(FoodReferenceUnit.milliliter)
                        }
                        HStack {
                            Text("本次摄入")
                            TextField("100", text: consumedAmountBinding)
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                            Text(review.referenceUnit.localizedTitle(for: model.effectiveLanguage))
                        }
                    }
                    Section(model.localized("每 100 \(review.referenceUnit.localizedTitle(for: model.effectiveLanguage))", "Per 100 \(review.referenceUnit.localizedTitle(for: model.effectiveLanguage))")) {
                        ForEach(NutrientCatalog.definitions) { definition in
                            HStack {
                                Text(definition.localizedName(for: model.effectiveLanguage))
                                Spacer()
                                TextField("缺失", text: nutrientBinding(definition.id))
                                    #if os(iOS)
                                        .keyboardType(.decimalPad)
                                    #endif
                                    .multilineTextAlignment(.trailing)
                                Text(definition.unit.symbol).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("保存到") {
                        Picker("餐次", selection: $mealType) {
                            ForEach(MealType.allCases) { meal in Text(meal.localizedTitle(for: model.effectiveLanguage)).tag(meal) }
                        }
                    }
                    Section {
                        Text("营养数值来自照片中的营养标签，保持“估算”状态；请核对后保存。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("确认营养标签")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并记录") {
                        Task {
                            await model.commitPackagedLabelReview(mealType: mealType)
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { mealType = model.selectedMeal }
    }

    private func stringBinding(_ keyPath: WritableKeyPath<PackagedLabelReview, String>) -> Binding<String> {
        Binding(
            get: { model.packagedLabelReview?[keyPath: keyPath] ?? "" },
            set: { model.packagedLabelReview?[keyPath: keyPath] = $0 }
        )
    }

    private var consumedAmountBinding: Binding<String> {
        Binding(
            get: {
                guard let amount = model.packagedLabelReview?.consumedAmount else { return "" }
                return "\(amount)"
            },
            set: { model.packagedLabelReview?.consumedAmount = Decimal(string: $0) ?? 0 }
        )
    }

    private func nutrientBinding(_ nutrient: NutrientID) -> Binding<String> {
        Binding(
            get: {
                guard let value = model.packagedLabelReview?.value(for: nutrient) else { return "" }
                return String(format: "%.2f", value)
            },
            set: { model.packagedLabelReview?.setValue(Double($0), for: nutrient) }
        )
    }
}

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
