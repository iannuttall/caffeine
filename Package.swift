// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Caffeine",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CaffeineCore", targets: ["CaffeineCore"]),
        .executable(name: "caffeinecli", targets: ["caffeinecli"]),
        .executable(name: "Caffeine", targets: ["Caffeine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
    ],
    targets: [
        .target(
            name: "CaffeineCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]),
        .executableTarget(
            name: "caffeinecli",
            dependencies: ["CaffeineCore"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]),
        .executableTarget(
            name: "Caffeine",
            dependencies: [
                "CaffeineCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .define("ENABLE_SPARKLE"),
            ]),
        .testTarget(
            name: "CaffeineCoreTests",
            dependencies: ["CaffeineCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
    ])
