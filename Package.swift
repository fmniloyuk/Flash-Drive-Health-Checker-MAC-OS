// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlashScope",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FlashScopeCore", targets: ["FlashScopeCore"])
    ],
    targets: [
        .target(
            name: "FlashScopeCore",
            path: "Sources/FlashScopeCore"
        ),
        .testTarget(
            name: "FlashScopeCoreTests",
            dependencies: ["FlashScopeCore"],
            path: "Tests/FlashScopeCoreTests"
        )
    ]
)
