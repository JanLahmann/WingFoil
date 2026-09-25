import Foundation
import Testing
@testable import WingFoil

/// **Done sits top right, everywhere.** (fb/done-right)
///
/// A sheet's "Done" is the same gesture on every screen — dismiss, keep what changed — and
/// Jan's own words were "sometimes top left, sometimes top right, top right is good". SwiftUI
/// renders `.confirmationAction` and `.topBarTrailing` on the right, `.cancellationAction` and
/// `.topBarLeading` on the left; a `Button("Done")` that ends up under either of the leading
/// placements has drifted back to the left, and this scan is what would catch it. A source
/// scan and not a snapshot test, the same trade `HelpButtonTests` makes: it cannot see where
/// the button renders, only what it is declared under, which is enough to catch the drift
/// that started this pass.
@Suite struct ToolbarPlacementTests {

    private let leadingPlacements = ["cancellationAction", "topBarLeading"]

    /// The nearest `ToolbarItem(placement: ...)` above a given line, within the same
    /// `.toolbar { }` block — close enough for the shape every call site here actually uses,
    /// which is one placement immediately followed by one button.
    private func placement(above index: Int, in lines: [Substring]) -> String? {
        var i = index
        while i >= 0 {
            if let range = lines[i].range(of: "ToolbarItem(placement: .") {
                let after = lines[i][range.upperBound...]
                return String(after.prefix(while: { $0.isLetter }))
            }
            i -= 1
        }
        return nil
    }

    @Test func everyDoneButtonIsUnderATrailingPlacement() throws {
        try #require(AppSources.directory != nil,
                     "the checkout this bundle was built from is not readable")
        var checked = 0
        for file in AppSources.swiftFiles() {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                guard line.contains("Button(\"Done\"") else { continue }
                checked += 1
                let found = placement(above: index, in: lines)
                #expect(found != nil,
                        "Done button with no ToolbarItem placement above it, in \(file.url.lastPathComponent):\(index + 1)")
                if let found {
                    #expect(!leadingPlacements.contains(found),
                            "Done under .\(found) renders top left, in \(file.url.lastPathComponent):\(index + 1)")
                }
            }
        }
        // The scan is worth nothing if it silently matched nothing.
        #expect(checked >= 15)
    }
}
