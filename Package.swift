// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YourMark",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "YourMark", targets: ["YourMark"]),
        .executable(name: "yourmark", targets: ["yourmark"]),
        .library(name: "YourMarkCore", targets: ["YourMarkCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        // Core library (non-UI conversion logic)
        .target(
            name: "YourMarkCore",
            path: "Sources/YourMarkCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        
        // GUI app
        .executableTarget(
            name: "YourMark",
            dependencies: ["YourMarkCore"],
            path: "Sources/YourMark",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        
        // CLI executable
        .executableTarget(
            name: "yourmark",
            dependencies: [
                "YourMarkCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/YourMarkCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        
        // Tests
        .testTarget(
            name: "YourMarkCoreTests",
            dependencies: ["YourMarkCore"],
            path: "Sources/YourMarkCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        
        .testTarget(
            name: "YourMarkCLITests",
            dependencies: ["yourmark", "YourMarkCore"],
            path: "Sources/YourMarkCLITests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
