import Foundation
import NutritionKit

@MainActor
extension AppModel {
    func refreshOnDeviceAvailability() async {
        guard let onDevicePhotoAnalyzer else {
            photoAnalysisAvailability = .unavailable
            return
        }
        photoAnalysisAvailability = await onDevicePhotoAnalyzer.availability(language: effectiveLanguage)
    }

    func analyzePhotos(_ images: [Data], provider: PhotoRecognitionProvider, mode: PhotoRecognitionMode) async {
        guard !images.isEmpty else { return }
        isAnalyzingPhotos = true
        defer { isAnalyzingPhotos = false }
        do {
            let result: FoodPhotoAnalysisResult
            switch provider {
            case .deepSeek:
                guard let deepSeekPhotoAnalyzer else {
                    throw PhotoAnalysisError.unavailable(.unavailable)
                }
                let apiKey: String
                if let savedKey = deepSeekCredentials.load() {
                    apiKey = savedKey
                } else if usesUITestPhotoFixture {
                    apiKey = "ui-test-key"
                } else {
                    deepSeekConfigured = false
                    deepSeekStatus = .notConfigured
                    throw DeepSeekVisionError.missingAPIKey
                }
                result = try await deepSeekPhotoAnalyzer.analyze(images: images, mode: mode, apiKey: apiKey, language: effectiveLanguage)
            case .appleOnDevice:
                guard mode == .meal else {
                    throw PhotoAnalysisError.modelFailure("包装营养标签识别需要配置 DeepSeek Vision")
                }
                guard let onDevicePhotoAnalyzer else {
                    throw PhotoAnalysisError.unavailable(.unavailable)
                }
                let availability = await onDevicePhotoAnalyzer.availability(language: effectiveLanguage)
                photoAnalysisAvailability = availability
                guard availability == .available else {
                    throw PhotoAnalysisError.unavailable(availability)
                }
                result = .meal(try await onDevicePhotoAnalyzer.analyze(images: images, language: effectiveLanguage))
            }

            let filenames = try await photoFiles.save(images)
            switch result {
            case .meal(let analyzed):
                var reviewedMeal = analyzed
                var analysisPasses = 1
                var secondPassNote: String?
                let matcher = PhotoFoodMatcher(catalog: catalog, language: effectiveLanguage)
                var initialScores: [[Double]] = []
                for dish in analyzed.dishes {
                    let candidates = await matcher.candidates(for: dish, limit: 3)
                    initialScores.append(candidates.map(\.score))
                }
                let secondPassIndexes = provider == .deepSeek
                    ? PhotoRecognitionGate.secondPassDishIndexes(meal: analyzed, topCandidateScoresByDish: initialScores)
                    : []
                let croppableIndexes = secondPassIndexes.filter {
                    analyzed.dishes.indices.contains($0) && analyzed.dishes[$0].normalizedRegion?.isValid == true
                }
                let secondPassKey = deepSeekCredentials.load() ?? (usesUITestPhotoFixture ? "ui-test-key" : nil)
                if !croppableIndexes.isEmpty, let deepSeekPhotoAnalyzer, let apiKey = secondPassKey {
                    let targetDishes = croppableIndexes.map { analyzed.dishes[$0] }
                    let plateware = targetDishes.compactMap(\.plateware).first
                    let request = PhotoSecondPassRequest(
                        targetDishNames: targetDishes.map(\.name),
                        plateware: plateware
                    )
                    do {
                        let refined = try await deepSeekPhotoAnalyzer.analyzeSecondPass(
                            images: images,
                            regions: targetDishes.compactMap(\.normalizedRegion),
                            request: request,
                            apiKey: apiKey,
                            language: effectiveLanguage
                        )
                        reviewedMeal = PhotoSecondPassMerger.merge(
                            primary: analyzed,
                            secondPass: refined,
                            targetIndexes: croppableIndexes
                        )
                        analysisPasses = 2
                    } catch {
                        secondPassNote = modelLocalized(
                            "第二次近景识别失败，已保留第一次结果；请核对候选或手动搜索。",
                            "The second close-up pass failed; the first result is preserved. Review the candidates or search manually."
                        )
                    }
                }
                var items: [PhotoReviewItem] = []
                for dish in reviewedMeal.dishes {
                    let baseCandidates = await matcher.candidates(for: dish, limit: 3)
                    var adjusted: [PhotoFoodMatch] = []
                    for candidate in baseCandidates {
                        let bonus = await photoLearning.rankingBonus(query: dish.name, foodID: candidate.food.id)
                        adjusted.append(PhotoFoodMatch(
                            dish: candidate.dish,
                            food: candidate.food,
                            score: min(1, max(0, candidate.score + bonus)),
                            matchedTerm: candidate.matchedTerm
                        ))
                    }
                    adjusted.sort { $0.score > $1.score }
                    let decision = PhotoCandidateSelector.decide(from: adjusted)
                    let midpoint = NSDecimalNumber(decimal: dish.suggestedGrams).doubleValue
                    let medianRatio = await photoLearning.portionMedianRatio(query: dish.name, foodID: decision.automaticSelection?.food.id ?? adjusted.first?.food.id ?? UUID())
                    let historyMedian = medianRatio.map { $0 * midpoint }
                    let portion = PhotoPortionEstimator.suggest(
                        dish: dish,
                        plateware: dish.plateware,
                        historyMedianGrams: historyMedian
                    )
                    items.append(PhotoReviewItem(
                        dish: dish,
                        candidates: adjusted,
                        selectedFood: decision.automaticSelection?.food,
                        grams: Decimal(portion.suggestedGrams),
                        plateware: dish.plateware,
                        originalSelectedFoodID: decision.automaticSelection?.food.id,
                        portionSuggestion: portion
                    ))
                }
                photoReview = PhotoAnalysisReview(
                    analyzedMeal: reviewedMeal,
                    items: items,
                    localPhotoFilenames: filenames,
                    provider: provider,
                    analysisPasses: analysisPasses,
                    secondPassNote: secondPassNote
                )
            case .packagedLabel(let label):
                packagedLabelReview = PackagedLabelReview(
                    brand: label.brand ?? "",
                    productName: label.productName,
                    referenceUnit: label.referenceUnit,
                    nutrients: label.nutrients,
                    consumedAmount: label.referenceAmount,
                    confidence: label.confidence,
                    analysisNote: label.analysisNote,
                    localPhotoFilenames: filenames
                )
            }
        } catch DeepSeekVisionError.unauthorized {
            deleteDeepSeekAPIKey()
            errorMessage = localizedApplicationError(DeepSeekVisionError.unauthorized, language: effectiveLanguage)
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    private func modelLocalized(_ chinese: String, _ english: String) -> String {
        effectiveLanguage.isChinese ? chinese : english
    }

    func saveDeepSeekAPIKey(_ apiKey: String) async {
        do {
            try deepSeekCredentials.save(apiKey)
            deepSeekConfigured = true
            deepSeekStatus = .saved
            await testDeepSeekAPIKey(apiKey)
        } catch {
            deepSeekStatus = .saveFailed
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    func testDeepSeekAPIKey(_ apiKey: String? = nil) async {
        guard let deepSeekPhotoAnalyzer else {
            deepSeekStatus = .unavailable
            return
        }
        guard let value = apiKey ?? deepSeekCredentials.load(), !value.isEmpty else {
            deepSeekStatus = .notConfigured
            return
        }
        deepSeekStatus = .testing
        do {
            try await deepSeekPhotoAnalyzer.testAPIKey(value)
            deepSeekStatus = .connected
        } catch {
            deepSeekStatus = .failed
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    func deleteDeepSeekAPIKey() {
        do {
            try deepSeekCredentials.delete()
            deepSeekConfigured = false
            deepSeekStatus = .notConfigured
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    func commitPhotoReview(mealType: MealType? = nil) async {
        guard let review = photoReview else { return }
        let targetMeal = mealType ?? selectedMeal
        do {
            let sessionID = UUID()
            let moment = Calendar.current.date(bySettingHour: suggestedHour(for: targetMeal), minute: 0, second: 0, of: selectedDate) ?? selectedDate
            var newEntries: [DiaryEntry] = []
            for item in review.items where item.include {
                guard let food = item.selectedFood else { continue }
                let midpoint = NSDecimalNumber(decimal: item.dish.suggestedGrams).doubleValue
                await photoLearning.recordDecision(
                    query: item.dish.name,
                    selectedFoodID: food.id,
                    rejectedFoodID: item.originalSelectedFoodID == food.id ? nil : item.originalSelectedFoodID,
                    selectedGrams: NSDecimalNumber(decimal: item.grams).doubleValue,
                    modelMidpointGrams: midpoint
                )
                var computed = try calculator.compute(food: food, quantity: .edibleGrams(item.grams))
                computed = NutritionComputation(
                    food: computed.food,
                    normalizedAmount: computed.normalizedAmount,
                    normalizedUnit: computed.normalizedUnit,
                    nutrients: computed.nutrients.map {
                        NutrientMeasurement(
                            nutrient: $0.nutrient,
                            value: $0.value,
                            unit: $0.unit,
                            status: $0.status == .missing ? .missing : .estimated,
                            source: .photoEstimate
                        )
                    },
                    warnings: computed.warnings
                )
                let entry = DiaryEntry(
                    sessionID: sessionID,
                    dayKey: DayKey.make(from: moment),
                    occurredAt: moment,
                    mealType: targetMeal,
                    foodID: food.id,
                    foodName: item.dish.name,
                    foodNameZh: effectiveLanguage.isChinese ? item.dish.name : food.localizedName(for: .simplifiedChinese),
                    foodNameEn: effectiveLanguage == .english ? item.dish.name : food.localizedName(for: .english),
                    quantityDescription: describePhotoGrams(item.grams, language: effectiveLanguage),
                    quantityDescriptionZh: describePhotoGrams(item.grams, language: .simplifiedChinese),
                    quantityDescriptionEn: describePhotoGrams(item.grams, language: .english),
                    normalizedAmount: computed.normalizedAmount,
                    normalizedUnit: computed.normalizedUnit,
                    nutrients: computed.nutrients,
                    source: .photoEstimate,
                    photoConfidence: item.dish.confidence,
                    photoFilenames: review.localPhotoFilenames
                )
                try await store.save(entry)
                newEntries.append(entry)
            }
            self.photoReview = nil
            await load()
            if let first = newEntries.first {
                try await syncHealth(dayKey: first.dayKey, mealType: first.mealType)
            }
            scheduleCloudSync()
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    func commitPackagedLabelReview(mealType: MealType? = nil) async {
        guard let review = packagedLabelReview else { return }
        let targetMeal = mealType ?? selectedMeal
        do {
            let name = [review.brand, review.productName].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
            let productName = name.isEmpty ? review.productName : name
            let food = FoodItem(
                name: productName,
                nameZh: productName,
                nameEn: productName,
                category: "包装食品",
                categoryZh: "包装食品",
                categoryEn: "Packaged food",
                referenceAmount: 100,
                referenceUnit: review.referenceUnit,
                nutrients: review.nutrients,
                source: FoodSource(
                    kind: .deepSeekPhotoLabel,
                    identifier: "deepseek-label",
                    title: "DeepSeek 营养标签识别",
                    titleZh: "DeepSeek 营养标签识别",
                    titleEn: "DeepSeek nutrition label recognition",
                    retrievedAt: .now
                )
            )
            try await store.saveFood(food)
            await catalog.upsert(food)
            let quantity: FoodQuantity = review.referenceUnit == .gram
                ? .edibleGrams(review.consumedAmount)
                : .milliliters(review.consumedAmount)
            var computed = try calculator.compute(food: food, quantity: quantity)
            computed = NutritionComputation(
                food: computed.food,
                normalizedAmount: computed.normalizedAmount,
                normalizedUnit: computed.normalizedUnit,
                nutrients: computed.nutrients.map {
                    NutrientMeasurement(
                        nutrient: $0.nutrient,
                        value: $0.value,
                        unit: $0.unit,
                        status: $0.status == .missing ? .missing : .estimated,
                        source: .photoEstimate
                    )
                },
                warnings: computed.warnings
            )
            let moment = Calendar.current.date(bySettingHour: suggestedHour(for: targetMeal), minute: 0, second: 0, of: selectedDate) ?? selectedDate
            let entry = DiaryEntry(
                dayKey: DayKey.make(from: moment),
                occurredAt: moment,
                mealType: targetMeal,
                foodID: food.id,
                foodName: food.name,
                foodNameZh: food.nameZh,
                foodNameEn: food.nameEn,
                quantityDescription: describeLabelAmount(review.consumedAmount, unit: review.referenceUnit, language: effectiveLanguage),
                quantityDescriptionZh: describeLabelAmount(review.consumedAmount, unit: review.referenceUnit, language: .simplifiedChinese),
                quantityDescriptionEn: describeLabelAmount(review.consumedAmount, unit: review.referenceUnit, language: .english),
                normalizedAmount: computed.normalizedAmount,
                normalizedUnit: computed.normalizedUnit,
                nutrients: computed.nutrients,
                source: .photoEstimate,
                photoConfidence: review.confidence,
                photoFilenames: review.localPhotoFilenames
            )
            try await store.save(entry)
            packagedLabelReview = nil
            await load()
            try await syncHealth(dayKey: entry.dayKey, mealType: entry.mealType)
            scheduleCloudSync()
        } catch {
            errorMessage = localizedApplicationError(error, language: effectiveLanguage)
        }
    }

    func describePhotoGrams(_ grams: Decimal, language: AppLanguage) -> String {
        let value = Int(NSDecimalNumber(decimal: grams).doubleValue)
        return language.isChinese ? "约 \(value) 克（照片估算）" : "About \(value) g (photo estimate)"
    }

    func describeLabelAmount(_ amount: Decimal, unit: FoodReferenceUnit, language: AppLanguage) -> String {
        language.isChinese
            ? "\(amount) \(unit.localizedTitle(for: language))（营养标签识别）"
            : "\(amount) \(unit.localizedTitle(for: language)) (nutrition label recognition)"
    }
}
