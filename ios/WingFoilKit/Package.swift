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
            ],
            // The bundled example session (see ExampleSession.swift). It lives in the kit
            // rather than in the app target so `Bundle.module` reaches it from *both* the
            // shipping app and the test suite — the scrub-verification test asserts on the
            // very bytes that get installed. `.copy` rather than `.process`: a FIT is
            // opaque to Xcode's resource pipeline and must arrive byte-for-byte.
            resources: [.copy("Resources/ExampleSession.fit")]
        ),
        .testTarget(name: "WingFoilKitTests", dependencies: ["WingFoilKit"]),
    ]
)
