// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DropLedge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DropLedgeApp", targets: ["DropLedgeApp"]),
        .library(name: "LedgeCore", targets: ["LedgeCore"]),
        .library(name: "StorageCoordinator", targets: ["StorageCoordinator"]),
        .library(name: "VisionEngine", targets: ["VisionEngine"]),
        .library(name: "ConversionEngine", targets: ["ConversionEngine"]),
        .library(name: "CodeAnalysis", targets: ["CodeAnalysis"]),
        .library(name: "LedgeUI", targets: ["LedgeUI"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StorageCoordinator",
            dependencies: [],
            path: "Sources/StorageCoordinator"
        ),
        .target(
            name: "VisionEngine",
            dependencies: [],
            path: "Sources/VisionEngine"
        ),
        .target(
            name: "ConversionEngine",
            dependencies: [],
            path: "Sources/ConversionEngine"
        ),
        .target(
            name: "CodeAnalysis",
            dependencies: [],
            path: "Sources/CodeAnalysis"
        ),
        .target(
            name: "LedgeCore",
            dependencies: [
                "StorageCoordinator",
                "VisionEngine",
                "ConversionEngine",
                "CodeAnalysis"
            ],
            path: "Sources/LedgeCore"
        ),
        .target(
            name: "LedgeUI",
            dependencies: [
                "LedgeCore",
                "CodeAnalysis"
            ],
            path: "Sources/LedgeUI"
        ),
        .executableTarget(
            name: "DropLedgeApp",
            dependencies: [
                "LedgeCore",
                "LedgeUI"
            ],
            path: "Sources/DropLedgeApp"
        ),
        // Tests
        .testTarget(
            name: "StorageCoordinatorTests",
            dependencies: ["StorageCoordinator"],
            path: "Tests/StorageCoordinatorTests"
        ),
        .testTarget(
            name: "CodeAnalysisTests",
            dependencies: ["CodeAnalysis"],
            path: "Tests/CodeAnalysisTests"
        ),
        .testTarget(
            name: "VisionEngineTests",
            dependencies: ["VisionEngine"],
            path: "Tests/VisionEngineTests"
        ),
        .testTarget(
            name: "LedgeUITests",
            dependencies: ["LedgeUI", "LedgeCore"],
            path: "Tests/LedgeUITests"
        ),
        .testTarget(
            name: "LedgeCoreTests",
            dependencies: ["LedgeCore"],
            path: "Tests/LedgeCoreTests"
        ),
        .testTarget(
            name: "ConversionEngineTests",
            dependencies: ["ConversionEngine"],
            path: "Tests/ConversionEngineTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
