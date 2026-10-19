import SwiftUI
import NutritionKit

@main
struct NutritionDiaryMacApp: App {
    @State private var bootstrap: AppBootstrap

    init() {
        _bootstrap = State(initialValue: AppBootstrap {
            let container = try NutritionStoreFactory.makeContainer()
            let store = DiaryStore(modelContainer: container)
            let catalog: any FoodSearching = SQLiteFoodCatalog.bundled() ?? FoodCatalog()
            let cloudSync = CloudSyncCoordinator(
                store: store,
                transport: CKSyncEngineCloudTransport(),
                deviceID: CloudSyncDeviceIdentity.current()
            )
            return AppModel(store: store, catalog: catalog, cloudSync: cloudSync)
        })
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model = bootstrap.model {
                    RootView()
                        .environment(model)
                        .frame(minWidth: 960, minHeight: 680)
                } else {
                    StartupErrorView()
                        .environment(bootstrap)
                        .frame(minWidth: 700, minHeight: 560)
                }
            }
        }
        .defaultSize(width: 1180, height: 800)
    }
}
