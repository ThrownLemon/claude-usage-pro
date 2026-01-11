// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsagePro",
    platforms: [
        .macOS(.v14)  // Updated for @Observable support
    ],
    products: [
        .executable(name: "ClaudeUsagePro", targets: ["ClaudeUsagePro"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ClaudeUsagePro",
            dependencies: [],
            path: "Sources/ClaudeUsagePro",
            resources: [
                .process("Assets.xcassets")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ClaudeUsageProTests",
            dependencies: ["ClaudeUsagePro"],
            path: "Tests/ClaudeUsageProTests"
        ),
    ]
)
