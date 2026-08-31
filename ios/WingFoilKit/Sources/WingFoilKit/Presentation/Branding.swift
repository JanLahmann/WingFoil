import Foundation

/// The app's name and its address on the web, in exactly one place.
///
/// Three surfaces print it — the share card's footer, the invitation that travels with a
/// shared FIT, and anything later that has to say where the recording can be opened — and
/// the address has already moved once: it was the `janlahmann.github.io/WingFoil` Pages URL
/// until `cleanjibe.org` was registered. A string literal repeated across the app would
/// mean a card and an invitation that disagree about where the app lives, on a card that is
/// already out in the world as a PNG.
///
/// Kept in the kit rather than in `Brand` (the app's colour palette) because it is content,
/// not styling, and because `ShareCardStats` — which is testable and has no SwiftUI — is one
/// of the things that has to name it.
public enum Branding {

    /// The app, as it is written everywhere: one word, capital F.
    public static let appName = "WingFoil"

    /// The site, without a scheme. A card is *read*, not clicked, and "https://" on an
    /// exported image is four characters of noise in a footer that has to stay small.
    public static let site = "cleanjibe.org"

    /// The same address as something that can actually be opened — for the FIT invitation,
    /// where the receiver is expected to tap it.
    public static let siteURL = "https://" + site

    /// "WingFoil · cleanjibe.org" — the card's footer credit, so the name
    /// and the address can never drift apart into two separate edits.
    public static let credit = appName + " · " + site
}
