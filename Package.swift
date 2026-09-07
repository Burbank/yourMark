// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YourMark",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "YourMark", targets: ["YourMark"])
    ],
    targets: [
        .executableTarget(
            name: "YourMark",
            path: "Sources/YourMark"
        )
    ]
)
