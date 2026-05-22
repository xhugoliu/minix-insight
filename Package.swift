// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MinixInsight",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MinixInsight", targets: ["MinixInsight"]),
        .library(name: "MinixInsightCore", targets: ["MinixInsightCore"]),
    ],
    targets: [
        .target(
            name: "MinixInsightCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "MinixInsight",
            dependencies: ["MinixInsightCore"]
        ),
        .testTarget(
            name: "MinixInsightTests",
            dependencies: ["MinixInsightCore"]
        ),
    ]
)
