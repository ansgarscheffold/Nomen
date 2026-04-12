// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nomen",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Nomen", targets: ["Nomen"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/mattt/llama.swift", exact: "2.8763.0"),
    ],
    targets: [
        .executableTarget(
            name: "Nomen",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "LlamaSwift", package: "llama.swift"),
            ],
            path: "Sources/Nomen"
        ),
    ]
)
