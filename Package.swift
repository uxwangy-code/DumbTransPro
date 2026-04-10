// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DumbTransPro",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "DumbTransProCore"
        ),
        .executableTarget(
            name: "DumbTransPro",
            dependencies: ["DumbTransProCore"]
        ),
        .testTarget(
            name: "DumbTransProCoreTests",
            dependencies: ["DumbTransProCore"]
        ),
    ]
)
