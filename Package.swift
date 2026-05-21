// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PromptPaster",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PromptPaster",
            targets: ["PromptPaster"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PromptPaster"
        )
    ]
)
