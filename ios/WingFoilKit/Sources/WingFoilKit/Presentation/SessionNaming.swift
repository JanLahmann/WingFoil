import Foundation

/// What a session is *called*, and what the rider wants said about it — the two rules that
/// decide, and the only place either of them is decided.
///
/// **Why the title is one function and not an `??`.** A session has two candidate names: the
/// one the rider typed (`SessionRow.customTitle`) and the one the app derived from the
/// recording's filename (`SessionDisplay.title`). The preference between them is trivial —
/// and it is applied on eleven surfaces, from the library row to the name the shared FIT
/// arrives under in somebody's chat. Eleven copies of a trivial rule is eleven places for a
/// rename to *not* take, which is the failure a rider notices: he named the session, and the
/// video still says "Nago Torbole Windsurfen". So the rule is here, `SessionDisplay.title`
/// applies it once, and every surface that already asked that function gets the rename for
/// free.
///
/// **Why blank means "no".** A rider who selects the title, deletes it and leaves has not
/// asked for a session called "". He has asked for the name back. Trimming to nil is what
/// makes "cleared" and "never set" the same state — and it is what stops a whitespace-only
/// title from reaching a 75 px headline as an empty card.
///
/// **Why the note is capped here rather than in the view.** A caption is drawn into a PNG.
/// There is no re-render, no scroll and no "…" that a reader can expand, so the length at
/// which it stops being legible is a *content* decision and belongs beside the content. The
/// text field enforces the same number, but the store is what guarantees it: a value that
/// arrived some other way (a future importer, a restored backup) must not be able to put a
/// paragraph on a card.
public enum SessionNaming {

    /// The most characters a share caption may carry.
    ///
    /// Eighty is about one line of a chat message, and about what the card's header can set
    /// on one line at a size a phone-sized thumbnail still resolves. It is the same budget on
    /// every shape, because a rider composing a caption is not choosing an aspect yet — and a
    /// caption that fitted the portrait card and overflowed the wide one would be a trap.
    public static let noteLimit = 80

    /// The most characters a custom title may carry.
    ///
    /// Longer than the caption because a title is the biggest type on the card and shrinks to
    /// fit; shorter than a sentence because at some point it stops being a name. Nothing
    /// downstream truncates, so this is the only place the number exists.
    public static let titleLimit = 60

    /// **The** session title: the rider's, when there is one, and the derived one otherwise.
    ///
    /// `derived` is the caller's fallback and is used verbatim — the kit has no business
    /// deriving a readable name out of a filename, which is presentation that depends on how
    /// the app happens to have stored the recording. The one rule it *does* own about a
    /// derived name is `sportCorrected(_:)`, which the caller applies while deriving.
    public static func title(custom: String?, derived: String) -> String {
        customTitle(custom) ?? derived
    }

    /// What the composer's title field **opens containing** — the session's current name, as
    /// editable text.
    ///
    /// It is `title(custom:derived:)`, and the point of giving it a name of its own is that it
    /// must stay that way. The field used to open *empty*, with the derived name greyed out
    /// behind it as a placeholder, which looks like a prefill and is not one: a placeholder
    /// vanishes on the first keystroke, so a rider who wanted "Nago Torbole Wingfoil — first
    /// 20 kn" had to type all six words, and every rename started from nothing.
    ///
    /// Prefilling with anything *else* would be worse than the placeholder. The custom title
    /// alone would open blank on every session nobody has renamed — which is nearly all of
    /// them — and a name the card is not currently showing would invite the rider to edit a
    /// string that was never on his card.
    ///
    /// The caller seeds its *committed* value with this too, so opening the sheet and closing
    /// it is not a rename: only a keystroke can be one.
    public static func titleDraft(custom: String?, derived: String) -> String {
        title(custom: custom, derived: derived)
    }

    /// The sport this app is about. One word, one spelling, one place.
    public static let sport = "Wingfoil"

    /// The words a Garmin watch puts there instead, lower-cased for the comparison.
    ///
    /// Garmin has no wingfoil profile, so a session is recorded under the windsurf one
    /// (docs/fit-schema.md: sport 43 alone does not mean wingfoil) and the watch names the
    /// activity after it — in the watch's own locale, which is why the German word is on this
    /// list beside the two English ones.
    private static let garminSportWords: Set<String> = [
        "windsurfen", "windsurfing", "windsurf",
    ]

    /// A **derived** name with Garmin's sport word swapped for this app's.
    ///
    /// "Nago-Torbole Windsurfen" is what a session synced back from the watch is called: the
    /// activity name is the spot plus the *profile it was recorded under*, and that word then
    /// travels — into the filename the sync writes, into the derived title every surface
    /// shows, and onto the share card's headline, where a rider publishes a picture of a
    /// wingfoil session captioned with somebody else's sport.
    ///
    /// **Display only, and deliberately so.** The recording keeps its name, the archive keeps
    /// its filename and the FIT keeps its sport code: all three are records of what the watch
    /// actually did, and rewriting them would be a lie about provenance. What changes is the
    /// derived title, which was only ever a guess made out of a filename.
    ///
    /// **A typed title is never touched.** `title(custom:derived:)` prefers the rider's own
    /// name whole, and this is applied to the derived branch only — a rider who wants to call
    /// an afternoon "Windsurfen" has named his afternoon.
    ///
    /// The word has to stand alone: "Windsurfen" becomes "Wingfoil", "Windsurfschule" stays
    /// itself. The boundary is the space the derivation already split on, and the swap keeps
    /// the case of the position it lands in — a capitalised word stays capitalised, a
    /// lower-case one stays lower-case — because the derivation capitalises and other callers
    /// may not.
    public static func sportCorrected(_ derived: String) -> String {
        derived.split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard garminSportWords.contains(word.lowercased()) else { return String(word) }
                return word.first?.isUppercase == true ? sport : sport.lowercased()
            }
            .joined(separator: " ")
    }

    /// **An external activity name, as the middle part of an archived filename.**
    /// `"Wingfoil am Nachmittag"` → `"Wingfoil-am-Nachmittag"`.
    ///
    /// Non-alphanumerics collapse to a single `-`, the result is capped at 40 characters and
    /// never ends in a dash. **Case is kept.** The filename is the only place the source's
    /// own name survives — no importer writes `customTitle`, which belongs to the rider —
    /// and `derivedTitle(fromFilename:)` reads it straight back out, so lower-casing here
    /// destroyed the one thing that told the title rule whose capitalisation it was looking
    /// at. That is how Strava's "Wingfoil am Nachmittag" reached the library as "Wingfoil Am
    /// Nachmittag".
    public static func activityNameSlug(_ name: String?) -> String {
        var slug = ""
        var lastWasDash = true
        for character in name ?? "" where true {
            if character.isLetter || character.isNumber {
                slug.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        slug = String(slug.prefix(40))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "session" : slug
    }

    /// **The name a session gets from the filename its recording arrived under.**
    /// `"2026-08-03-1440_nago-torbole-windsurfen_native.fit"` → `"Nago Torbole Wingfoil"`;
    /// `"14123456789_Wingfoil-am-Nachmittag_strava.gpx"` → `"Wingfoil am Nachmittag"`.
    ///
    /// A guess made out of a filename, and never a statement — `title(custom:derived:)`
    /// prefers anything the rider typed.
    ///
    /// **It title-cases only a name the app itself built.** The importers write the source's
    /// own activity name into the middle `_`-part, and an imported name is somebody else's
    /// text: Strava's "Wingfoil am Nachmittag" and "Hallbergmoos Surfen" came back out of
    /// this function as "Wingfoil Am Nachmittag" and "Hallbergmoos Surfen" with a capital on
    /// every word, which is a rewrite of a name a person chose. So the rule is: **if the stem
    /// carries any capital at all, its capitalisation is the source's and is left alone.** A
    /// stem that is entirely lower-case carries no information to preserve — that is the
    /// watch's `nago-torbole-windsurfen` and the app's own slug of a bare spot name — and is
    /// the one case that gets a capital per word.
    ///
    /// Four-digit-or-longer all-number words are dropped, because the importers prefix the
    /// stem with a date or an activity id and neither is part of anybody's name.
    ///
    /// The last step is the guess's one correction, `sportCorrected(_:)`.
    public static func derivedTitle(fromFilename file: String?) -> String {
        guard let file else { return "Session" }
        var stem = (file as NSString).deletingPathExtension
        let parts = stem.split(separator: "_")
        if parts.count >= 2 { stem = String(parts[1]) }
        let words = stem.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .filter { !($0.allSatisfy(\.isNumber) && $0.count >= 4) }
        guard !words.isEmpty else { return "Session" }
        let sourceCased = words.contains { $0.contains(where: \.isUppercase) }
        let title = words
            .map { sourceCased ? String($0) : String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
        return sportCorrected(title)
    }

    /// **What the Recording card calls the sport a session was recorded under.**
    ///
    /// The value is whatever the source said — a FIT sport name or number, a HealthKit type
    /// string, or Strava's `sport_type` — and a source that said nothing at all reads as
    /// `nil`, which is "Unknown". The five hard-coded rows are the ones whose raw spelling is
    /// not a word a rider would recognise; everything else is **unbent**: underscores become
    /// spaces, a run-together `CamelCase` name is split at its capitals, and the source's own
    /// capitalisation is otherwise kept. `.capitalized` used to be applied here and turned
    /// HealthKit's `surfingSports` into `Surfingsports`.
    ///
    /// This is not the discipline and must never be read as one: ADR-004 records FIT sport 43
    /// (windsurfing) for a wingfoil afternoon. It is a line of provenance on the Recording
    /// card, and `Discipline.resolve` does not take it as an argument.
    public static func sportLabel(_ sport: String?) -> String {
        let raw = (sport ?? "").trimmingCharacters(in: .whitespaces)
        switch raw.lowercased() {
        case "windsurfing", "windsurf", "43": return "Windsurf"
        case "kitesurfing", "kitesurf", "44": return "Kitesurf"
        case "sailing", "sail", "32": return "Sailing"
        case "stand_up_paddleboarding", "standuppaddling", "sup": return "SUP"
        case "walking", "walk", "11": return "CIQ app"
        case "": return "Unknown"
        default: return splitWords(raw)
        }
    }

    /// `"surfingSports"` → `"surfing Sports"`, `"stand_up"` → `"stand up"`, `"Windsurf"` →
    /// `"Windsurf"`. Separators only — no letter's case is changed.
    static func splitWords(_ raw: String) -> String {
        var out = ""
        var previous: Character?
        for character in raw.replacingOccurrences(of: "_", with: " ") {
            if character.isUppercase, let previous, previous != " ", !previous.isUppercase {
                out.append(" ")
            }
            out.append(character)
            previous = character
        }
        return out
    }

    /// A typed title as it should be stored: trimmed, capped, and nil rather than blank.
    ///
    /// Interior whitespace is left exactly as typed. A rider who writes "First  20 kn" has
    /// written that, and a normalizer that quietly rewrote his name would be a worse bug than
    /// two spaces.
    public static func customTitle(_ raw: String?) -> String? {
        clean(raw, limit: titleLimit, singleLine: false)
    }

    /// A typed caption as it should be stored: one line, trimmed, capped at `noteLimit`, and
    /// nil rather than blank.
    ///
    /// **Single line, enforced not requested.** The caption is drawn with one `fillText` on
    /// the web and one `Text` on the phone; a newline that survived to either would be drawn
    /// as a space by one and as a box by the other. Paste is the only way one can arrive —
    /// nobody types a return into a one-line field — so it is folded to a space here rather
    /// than rejected, because a rider who pasted two lines meant both of them.
    public static func note(_ raw: String?) -> String? {
        clean(raw, limit: noteLimit, singleLine: true)
    }

    /// Trim, optionally flatten, cap, trim again — in that order, and the second trim is the
    /// point: a cap that lands mid-space would otherwise store a caption with a trailing one,
    /// which draws as a gap before nothing.
    private static func clean(_ raw: String?, limit: Int, singleLine: Bool) -> String? {
        guard var text = raw else { return nil }
        if singleLine {
            text = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > limit {
            text = String(text.prefix(limit))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }
}
