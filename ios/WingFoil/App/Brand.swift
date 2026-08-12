import SwiftUI

/// The brand palette (brand/icon-square.svg), in one place so the share card, the launch
/// screen and the celebration all use the same greens.
///
/// These are *brand* colours, not semantic ones: everything that has to read against a
/// system background keeps using `Color.accentColor` and the system materials, which adapt
/// to light and dark. `Brand` is for surfaces the app paints itself — the exported card and
/// the confetti — where there is no system background to adapt to.
enum Brand {
    /// Deep navy — the card background and the launch screen.
    static let navy = Color(red: 0.039, green: 0.118, blue: 0.188)
    /// The accent green (also `AccentColor` in the asset catalogue).
    static let green = Color(red: 0.180, green: 0.902, blue: 0.659)
    static let cyan = Color(red: 0.208, green: 0.769, blue: 0.941)
    static let lime = Color(red: 0.725, green: 1.000, blue: 0.400)
    /// Near-white, warm enough not to glare against the navy.
    static let paper = Color(red: 0.957, green: 0.980, blue: 1.000)

    /// The card's default background when the rider has not picked a photo.
    static let cardGradient = LinearGradient(
        colors: [Color(red: 0.047, green: 0.157, blue: 0.243), navy,
                 Color(red: 0.024, green: 0.086, blue: 0.141)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Confetti colours — the palette plus the outcome green/amber, so a burst reads as
    /// "WingFoil" rather than as generic party stock.
    static let celebration: [Color] = [green, cyan, lime, .orange, paper]
}
