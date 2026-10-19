import Foundation
import HealthKit
import NutritionKit

enum HealthManagerError: Error, LocalizedError {
    case unavailable
    case missingType

    var errorDescription: String? {
        switch self {
        case .unavailable: "当前设备无法访问 HealthKit"
        case .missingType: "缺少对应的 HealthKit 数据类型"
        }
    }
}

@MainActor
final class HealthManager: EnergyReading, HealthEnergyObserving, DietaryHealthWriting {
    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []

    private var writeTypes: [NutrientID: HKQuantityType] {
        var result: [NutrientID: HKQuantityType] = [:]
        for definition in NutrientCatalog.definitions {
            guard let rawIdentifier = definition.healthKitIdentifier else { continue }
            let identifier = HKQuantityTypeIdentifier(rawValue: rawIdentifier)
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                result[definition.id] = type
            }
        }
        return result
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthManagerError.unavailable }
        let readTypes = Set<HKObjectType>([
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        ].compactMap { $0 })
        let shareTypes = Set(writeTypes.values)
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func readDailyEnergy(for date: Date, timeZone: TimeZone, preferredSourceID: String?) async throws -> HealthEnergyReadResult {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthManagerError.unavailable }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)

        do {
            async let activeSamples = samples(identifier: .activeEnergyBurned, start: start, end: end)
            async let basalSamples = samples(identifier: .basalEnergyBurned, start: start, end: end)
            async let exerciseSamples = samples(identifier: .appleExerciseTime, start: start, end: end)
            let (active, basal, exercise) = try await (activeSamples, basalSamples, exerciseSamples)

            var registry: [String: HealthEnergySource] = [:]
            aggregate(active, unit: .kilocalorie(), into: &registry) { source, value in
                source.activeKcal = (source.activeKcal ?? 0) + value
            }
            aggregate(basal, unit: .kilocalorie(), into: &registry) { source, value in
                source.basalKcal = (source.basalKcal ?? 0) + value
            }
            aggregate(exercise, unit: .minute(), into: &registry) { source, value in
                source.exerciseMinutes = (source.exerciseMinutes ?? 0) + value
            }

            let sources = registry.values.sorted {
                if $0.isWatch != $1.isWatch { return $0.isWatch && !$1.isWatch }
                if $0.sampleCount != $1.sampleCount { return $0.sampleCount > $1.sampleCount }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            let selection = HealthEnergySourceSelector().select(from: sources, preferredSourceID: preferredSourceID)
            var notes: [String] = []
            if let note = selection.coverageNote { notes.append(note) }
            if selection.activeSource == nil || selection.basalSource == nil || selection.exerciseSource == nil {
                notes.append("部分健康指标缺失")
            }

            let summary = EnergyDaySummary(
                dayKey: DayKey.make(from: date, timeZone: timeZone),
                activeKcal: selection.activeSource?.activeKcal,
                basalKcal: selection.basalSource?.basalKcal,
                exerciseMinutes: selection.exerciseSource?.exerciseMinutes,
                activeSource: selection.activeSource?.name,
                basalSource: selection.basalSource?.name,
                exerciseSource: selection.exerciseSource?.name,
                activeSourceID: selection.activeSource?.id,
                basalSourceID: selection.basalSource?.id,
                exerciseSourceID: selection.exerciseSource?.id,
                fetchedAt: .now,
                coverageNote: notes.isEmpty ? nil : notes.joined(separator: "；")
            )
            return HealthEnergyReadResult(summary: summary, sources: sources)
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined || error.code == .errorAuthorizationDenied {
            throw HealthReadError.authorizationRequired
        }
    }

    func startObserving(onChange: @escaping @Sendable () async -> Void) {
        guard observerQueries.isEmpty else { return }
        let identifiers: [HKQuantityTypeIdentifier] = [.activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime]
        for identifier in identifiers {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                completion()
                guard error == nil else { return }
                Task { await onChange() }
            }
            store.execute(query)
            observerQueries.append(query)
        }
    }

    func stopObserving() {
        for query in observerQueries {
            store.stop(query)
        }
        observerQueries.removeAll()
    }

    func syncMeal(dayKey: String, mealType: MealType, entries: [DiaryEntry], allowEstimated: Bool) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthManagerError.unavailable }
        for (nutrient, type) in writeTypes {
            let identifier = syncIdentifier(dayKey: dayKey, mealType: mealType, nutrient: nutrient)
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, operatorType: .equalTo, value: identifier)
            try await store.deleteObjects(of: type, predicate: predicate)
        }
        guard !entries.isEmpty else { return }

        let timestamp = entries.map(\.occurredAt).min() ?? .now
        let version = Int(Date().timeIntervalSince1970 * 1000)
        var samples: [HKQuantitySample] = []
        for (nutrient, type) in writeTypes {
            let measurements = entries.compactMap { entry in entry.nutrients.first { $0.nutrient == nutrient } }
            guard measurements.count == entries.count else { continue }
            let eligible = measurements.allSatisfy { measurement in
                measurement.status == .complete || (allowEstimated && measurement.status == .estimated)
            }
            guard eligible, let value = measurements.compactMap(\.value).reduce(nil, { partial, next in
                (partial ?? 0) + next
            }) else { continue }
            let quantity = HKQuantity(unit: unit(for: nutrient), doubleValue: NSDecimalNumber(decimal: value).doubleValue)
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: syncIdentifier(dayKey: dayKey, mealType: mealType, nutrient: nutrient),
                HKMetadataKeySyncVersion: version,
                HKMetadataKeyTimeZone: entries.first?.timeZoneIdentifier ?? TimeZone.current.identifier
            ]
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: timestamp, end: timestamp, metadata: metadata))
        }
        if !samples.isEmpty {
            try await store.save(samples)
        }
    }

    private func samples(identifier: HKQuantityTypeIdentifier, start: Date, end: Date) async throws -> [HKQuantitySample] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthManagerError.missingType
        }
        let predicate = HKSamplePredicate.quantitySample(
            type: type,
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        )
        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(predicates: [predicate], sortDescriptors: [], limit: nil)
        return try await descriptor.result(for: store)
    }

    private func aggregate(
        _ samples: [HKQuantitySample],
        unit: HKUnit,
        into registry: inout [String: HealthEnergySource],
        update: (inout HealthEnergySource, Double) -> Void
    ) {
        for sample in samples {
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite else { continue }
            let source = sample.sourceRevision.source
            let name = source.name
            let bundleIdentifier = source.bundleIdentifier
            let productType = sample.sourceRevision.productType
            let id = "\(bundleIdentifier)::\(name)"
            let isWatch = productType?.hasPrefix("Watch") == true
                || name.localizedCaseInsensitiveContains("watch")
                || name.contains("手表")
            var entry = registry[id] ?? HealthEnergySource(
                id: id,
                name: name,
                bundleIdentifier: bundleIdentifier,
                productType: productType,
                isWatch: isWatch
            )
            update(&entry, value)
            entry.sampleCount += 1
            if entry.lastSampleAt == nil || sample.endDate > entry.lastSampleAt! {
                entry.lastSampleAt = sample.endDate
            }
            registry[id] = entry
        }
    }

    private func unit(for nutrient: NutrientID) -> HKUnit {
        switch NutrientCatalog.definition(for: nutrient)?.unit {
        case .kilocalorie: return .kilocalorie()
        case .milligram: return .gramUnit(with: .milli)
        case .microgram: return .gramUnit(with: .micro)
        case .gram, .none: return .gram()
        }
    }

    private func syncIdentifier(dayKey: String, mealType: MealType, nutrient: NutrientID) -> String {
        "nutritiondiary.meal.\(dayKey).\(mealType.rawValue).\(nutrient.rawValue)"
    }
}
