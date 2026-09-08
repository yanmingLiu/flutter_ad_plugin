// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_ad_plugin",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-ad-plugin", targets: ["flutter_ad_plugin"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_ad_plugin",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
