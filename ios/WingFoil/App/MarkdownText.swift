import SwiftUI

extension Text {

    /// Rider copy with emphasis in it — `**bold**`, `*italic*` — drawn as emphasis rather
    /// than as a pair of asterisks.
    ///
    /// **Why this exists.** `Text("… **ten riders** …")` parses markdown only when the
    /// argument is a `LocalizedStringKey`, which is to say only when it is a literal. Every
    /// long footer in this app is assembled at run time — a `+` chain of source lines, an
    /// interpolation, a paragraph handed over by `WingFoilKit.HelpCatalog` — so it arrives
    /// as a `String`, takes the `Text(_: String)` overload, and renders the asterisks
    /// literally. Which is worse than no emphasis at all: it reads as an unfinished screen.
    /// Found in the release walkthrough of 14 September 2026, in eleven places at once.
    ///
    /// `AttributedString(markdown:)` is the parser that takes a run-time string, and
    /// `.inlineOnlyPreservingWhitespace` is the interpretation to ask it for: the default
    /// one throws the blank lines away and returns these three-paragraph footers as a
    /// single run-on line. Inline-only also means no accidental block markdown — a footer
    /// that happens to start with "1. " stays a sentence rather than becoming a list.
    ///
    /// A string the parser refuses falls back to itself, verbatim: a stray bracket costs
    /// the emphasis and never the sentence. `verbatim` because this text has already been
    /// composed, and handing an assembled string to the localisation table would be asking
    /// for a key that cannot exist.
    init(markdown string: String) {
        if let parsed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            self.init(parsed)
        } else {
            self.init(verbatim: string)
        }
    }
}
