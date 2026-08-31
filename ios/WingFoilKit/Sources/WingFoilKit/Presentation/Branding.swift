import Foundation

/// The app's name and its address on the web, in exactly one place.
///
/// Three surfaces print it — the share card's footer, the invitation that travels with a
/// shared FIT, and anything later that has to say where the recording can be opened — and
/// both halves have already moved once: the address was the `janlahmann.github.io/WingFoil`
/// Pages URL until `cleanjibe.org` was registered, and the name was **WingFoil** until the
/// domain made the brand. A string literal repeated across the app would mean a card and an
/// invitation that disagree about what the app is called, on a card that is already out in
/// the world as a PNG.
///
/// **The name here is the brand, not the sport.** `appName` is "CleanJibe"; the word
/// *wingfoil* survives all over the copy as the thing a rider does, lowercase, and in the
/// Xcode target, the module and the bundle ids, which are identifiers and not read by
/// anyone. The Garmin watch app is still called WingFoil, and screens that mean *that* app
/// say so on purpose.
///
/// Kept in the kit rather than in `Brand` (the app's colour palette) because it is content,
/// not styling, and because `ShareCardStats` — which is testable and has no SwiftUI — is one
/// of the things that has to name it.
public enum Branding {

    /// The app, as it is written everywhere: one word, capital C, capital J.
    public static let appName = "CleanJibe"

    /// The site, without a scheme. A card is *read*, not clicked, and "https://" on an
    /// exported image is four characters of noise in a footer that has to stay small.
    public static let site = "cleanjibe.org"

    /// The same address as something that can actually be opened — for the FIT invitation,
    /// where the receiver is expected to tap it, and for the card footer's QR code.
    public static let siteURL = "https://" + site

    /// "CleanJibe · cleanjibe.org" — the credit *inside* the app, where the reader is
    /// already a user and an invitation would be absurd: the welcome screen's bottom rule,
    /// and the one-line attribution on a shared clip or card.
    public static let credit = appName + " · " + site

    /// "analyze your wingfoil sessions free — cleanjibe.org" — the line on everything that
    /// leaves the phone, and the one string the web share card and this one must agree on
    /// character for character (`docs/presentation.md`, the card contract).
    ///
    /// Lowercase throughout, including the first word: it sits under the wordmark as its
    /// subtitle rather than beside it as a sentence. "wingfoil" here is the sport, which is
    /// why it is not the brand's capitalisation.
    public static let callToAction = "analyze your wingfoil sessions free — " + site
}
