// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsagePro",
    platforms: [
        .macOS(.v13)
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
                .process("Resources")
            ]
        )
    ]
)
