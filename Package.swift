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
            dependencies: ["GoodGoodStudyCore"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ]
)
