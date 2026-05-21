// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DumbTransPro",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2"),
    ],
    targets: [
        .target(
            name: "DumbTransProCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ]
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
