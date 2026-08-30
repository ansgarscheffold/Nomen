// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nomen",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "NomenCore", targets: ["NomenCore"]),
        .executable(name: "Nomen", targets: ["Nomen"]),
        .executable(name: "NomenCoreChecks", targets: ["NomenCoreChecks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/mattt/llama.swift", exact: "2.8763.0"),
    ],
    targets: [
        .target(
            name: "NomenCore",
            path: "Sources/NomenCore"
        ),
        .executableTarget(
            name: "Nomen",
            dependencies: [
                "NomenCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "LlamaSwift", package: "llama.swift"),
            ],
            path: "Sources/Nomen"
        ),
        .executableTarget(
            name: "NomenCoreChecks",
            dependencies: ["NomenCore"],
            path: "Tests/NomenCoreChecks"
        ),
    ]
)
