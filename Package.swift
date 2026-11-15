// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoodFitCore",
    platforms: [.macOS(.v12), .iOS(.v17)],
    products: [.library(name: "FoodFitCore", targets: ["FoodFitCore"])],
    targets: [
        .target(name: "FoodFitCore", path: "Core"),
        .testTarget(name: "FoodFitCoreTests", dependencies: ["FoodFitCore"], path: "Tests")
    ]
)
