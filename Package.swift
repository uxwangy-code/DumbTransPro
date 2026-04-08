// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoodGoodStudy",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "GoodGoodStudyCore"
        ),
        .executableTarget(
            name: "GoodGoodStudy",
            dependencies: ["GoodGoodStudyCore"]
        ),
        .testTarget(
            name: "GoodGoodStudyCoreTests",
            dependencies: ["GoodGoodStudyCore"]
        ),
    ]
)
