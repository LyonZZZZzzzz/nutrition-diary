// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "NutritionKit",
    platforms: [.iOS(.v27), .macOS(.v15)],
    products: [
        .library(name: "NutritionKit", targets: ["NutritionKit"])
    ],
    targets: [
        .target(name: "NutritionKit", resources: [.process("Resources")], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "NutritionKitTests", dependencies: ["NutritionKit"])
    ]
)
