// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WingFoilKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "WingFoilKit", targets: ["WingFoilKit"])
    ],
    dependencies: [
        // **Pinned to a commit, not to a tag** (22 September 2026). The generated map used
        // to narrow a `FIT_UINT32` into the field's own type with the *trapping*
        // initializer, so a structurally valid FIT carrying a wider value killed the
        // process inside `FitFile.init` before a line of ours ran — found by the mutation
        // fuzz (docs/testing.md). We carried a vendored copy of 1.5.2 with that one word
        // changed; the fix is upstream now (roznet/FitFileParser#15, merged 21 September
        // 2026) and the copy is gone. The newest release, 1.5.2, predates it by three
        // years, so there is no tag to ask for: the merge commit is the pin, and it moves
        // to `.exact("…")` the day upstream cuts a release.
        .package(url: "https://github.com/roznet/FitFileParser",
                 revision: "6f50aa12b3fcb226c601b1160374f4c5f7930835"),
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
