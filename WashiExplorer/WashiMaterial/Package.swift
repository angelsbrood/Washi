// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "WashiMaterial",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WashiMaterial", targets: ["WashiMaterial"]),
    ],
    targets: [
        .target(name: "WashiMaterial"),
    ]
)
