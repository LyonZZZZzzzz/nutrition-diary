import SwiftUI
import NutritionKit

@main
struct NutritionDiaryIOSApp: App {
    @State private var bootstrap: AppBootstrap

    init() {
        #if DEBUG
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing-in-memory-store")
        #else
        let isUITesting = false
        #endif
        _bootstrap = State(initialValue: AppBootstrap {
            #if DEBUG
            if isUITesting, ProcessInfo.processInfo.arguments.contains("--ui-testing-startup-failure") {
                throw NSError(domain: "NutritionDiaryUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthetic database startup failure"])
            }
            #endif
            let container = try NutritionStoreFactory.makeContainer(inMemory: isUITesting)
            let store = DiaryStore(modelContainer: container)
            let catalog: any FoodSearching = SQLiteFoodCatalog.bundled() ?? FoodCatalog()
            let health: HealthManager? = isUITesting ? nil : HealthManager()
            let onDeviceAnalyzer: FoundationModelsMealAnalyzer? = isUITesting ? nil : FoundationModelsMealAnalyzer()
            let usesPhotoFixture = ProcessInfo.processInfo.arguments.contains("--ui-testing-photo-fixture")
            let usesLowConfidenceFixture = ProcessInfo.processInfo.arguments.contains("--ui-testing-photo-low-confidence")
            let deepSeekAnalyzer: (any DeepSeekPhotoAnalyzing)? = usesPhotoFixture
                ? UITestDeepSeekPhotoAnalyzer(forcesLowConfidence: usesLowConfidenceFixture)
                : (isUITesting ? nil : DeepSeekPhotoAnalyzer())
            let cloudSync: CloudSyncCoordinator?
            #if DEVICE_TEST
            // DeviceTest intentionally has HealthKit-only entitlements. Creating
            // CKContainer without an iCloud entitlement traps inside CloudKit
            // during startup, so this configuration must stay local-only.
            cloudSync = nil
            #else
            cloudSync = isUITesting
                ? nil
                : CloudSyncCoordinator(
                    store: store,
                    transport: CKSyncEngineCloudTransport(),
                    deviceID: CloudSyncDeviceIdentity.current()
                )
            #endif
            let model = AppModel(
                store: store,
                energyReader: health,
                healthObserver: health,
                healthWriter: health,
                onDevicePhotoAnalyzer: onDeviceAnalyzer,
                deepSeekPhotoAnalyzer: deepSeekAnalyzer,
                catalog: catalog,
                cloudSync: cloudSync,
                usesUITestPhotoFixture: usesPhotoFixture
            )
            if usesPhotoFixture {
                model.deepSeekConfigured = true
                model.deepSeekStatus = .saved
            }
            return model
        })
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model = bootstrap.model {
                    RootView().environment(model)
                } else {
                    StartupErrorView().environment(bootstrap)
                }
            }
        }
    }
}
