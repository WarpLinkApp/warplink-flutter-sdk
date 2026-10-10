// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "warplink_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "warplink-flutter", targets: ["warplink_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/WarpLinkApp/warplink-ios-sdk.git", from: "1.1.1")
    ],
    targets: [
        .target(
            name: "warplink_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "WarpLink", package: "warplink-ios-sdk")
            ]
        )
    ]
)
