import SwiftUI

/// The five brand colours the watch actually paints with.
///
/// **A deliberate second copy, not an oversight.** The phone's palette lives in
/// `ios/WingFoil/App/Brand.swift`, and sharing that one file with this target is what a
/// reader would expect — it is what `WingFoilWidgets` does with `WidgetSnapshot.swift`. It
/// does not work here for a mechanical reason: `Brand.swift` sits inside the WingFoil
/// target's own source tree, so XcodeGen emits a single group-relative file reference and
/// files it in two groups at different depths, and the second path resolves to
/// `WingFoil/App/WingFoil/App/Brand.swift`. The build fails on a missing input. The shared
/// `WatchSessionContainer.swift` has no such problem because no target claims its directory.
///
/// So these values are duplicated, and the duplication is bounded and checkable: the same
/// five numbers appear in `ios/WingFoil/App/Brand.swift`, in
/// `Assets.xcassets/AccentColor.colorset` and `LaunchBackground.colorset`, and upstream of
/// all of them in `design/tokens.json`. If they ever have to change, that file is where it
/// starts.
///
/// The type is named `Brand` on purpose — same name, different module, so the view code here
/// reads exactly like the view code on the phone.
enum Brand {
    /// Deep navy — the ground every watch screen is painted on. Chosen over black because
    /// the OLED is read in direct Garda sun through polarised lenses, where a coloured dark
    /// ground separates from the bezel and pure black does not.
    static let navy = Color(red: 0.039, green: 0.118, blue: 0.188)
    /// The accent green: START, the "GPS ready" dot, the unit beside the speed.
    static let green = Color(red: 0.180, green: 0.902, blue: 0.659)
    static let cyan = Color(red: 0.208, green: 0.769, blue: 0.941)
    static let lime = Color(red: 0.725, green: 1.000, blue: 0.400)
    /// Near-white, warm enough not to glare against the navy. Every number on the wrist.
    static let paper = Color(red: 0.957, green: 0.980, blue: 1.000)
}
