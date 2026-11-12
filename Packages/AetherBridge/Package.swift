// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AetherBridge",
    platforms: [
        .tvOS(.v18),
    ],
    products: [
        .library(
            name: "AetherBridge",
            targets: ["AetherBridge"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/superuser404notfound/AetherEngine.git",
            exact: "7.65.0",
            traits: [
                "TrueHDObjectAudio",
                "DTSXObjectAudio",
                "DualLayerDolbyVision",
                "DolbyVisionFelCurves",
                "DolbyVisionStillReshaping",
            ]
        ),
    ],
    targets: [
        .target(
            name: "AetherBridge",
            dependencies: [
                .product(name: "AetherEngine", package: "AetherEngine"),
            ]
        ),
    ]
)
