// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WingFoilKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "WingFoilKit", targets: ["WingFoilKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/roznet/FitFileParser", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "WingFoilKit",
            dependencies: [
                "FitFileParser",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .testTarget(name: "WingFoilKitTests", dependencies: ["WingFoilKit"]),
    ]
)
