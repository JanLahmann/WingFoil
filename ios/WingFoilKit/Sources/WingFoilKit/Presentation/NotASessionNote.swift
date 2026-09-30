import Foundation

/// **What the rider is told about a recording that is not a session** — the quiet tag on the
/// library row and the one line on the session page (docs/presentation/not-a-session-spots.md, "Not a session").
///
/// The engine decides (`SessionVerdict`); this decides the words, once, so the row and the
/// page cannot drift apart. Three rules the wording keeps:
///
/// * **It never says "deleted", "ignored" or "invalid".** Nothing is deleted and nothing is
///   hidden: the row is in the list, the page opens, the map draws. What changed is that the
///   recording is not counted, and the sentence says exactly that.
/// * **It says what it looked at.** "No riding detected" on its own invites "detected how?",
///   and a rider whose real session was mis-read has to be able to see the evidence and
///   disagree with it — so the page's line names the two numbers that decided.
/// * **No engine vocabulary.** Not "isSession", not "foilTimeS", not "success" or "carried".
public enum NotASessionNote {

    /// The tag on the library row. Four words, no punctuation, no verdict about the rider:
    /// the recording is what was not a session, and "detected" is what leaves room for the
    /// engine to have been wrong.
    public static let tag = "No riding detected"

    /// The row's tag for a land sport (engine 0.26.0): a run or a ride *was* riding of a
    /// kind, so "No riding detected" would be wrong about it. Three words that say what the
    /// recording is not, without a verdict on the rider.
    public static let landTag = "Not a watersport"

    /// The five snow sports among ``SessionVerdict/landSports`` (30 Sep 2026, ADR-036
    /// amendment, Jan: "CleanJibe reads foiling on water. A snow-wing day has no foil to
    /// read."). They keep ``landTag`` — a snow-wing afternoon is still not a watersport —
    /// but the page's line names the reason a rider actually asked: not "wrong sport", but
    /// "no foil at all". Skate sports (inline and ice skating) and every other land sport
    /// keep the generic line below.
    public static let snowSports: Set<String> = [
        "cross_country_skiing", "alpine_skiing", "snowboarding", "snowshoeing",
        "snowmobiling",
    ]

    /// Is `sport` (a FIT profile name, any case) one of ``snowSports``?
    public static func isSnowSport(_ sport: String?) -> Bool {
        guard let sport else { return false }
        return snowSports.contains(sport.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// The tag a row wears for its reason — the one call the row and the document share.
    public static func tag(for reason: SessionVerdict.Reason?) -> String {
        reason == .landSport ? landTag : tag
    }

    /// The page's one line: why this recording is not counted, in a sentence.
    ///
    /// `durationS` and `distanceKm` are the row's own displayed numbers, so the line reads
    /// against the key-metrics block directly above it rather than quoting a third figure.
    ///
    /// `sport` is the land sport that decided (`summary.landSport`, a FIT profile name), read
    /// only for ``SessionVerdict/Reason/landSport``.
    public static func line(reason: SessionVerdict.Reason?,
                            durationS: Double?, distanceKm: Double?,
                            sport: String? = nil) -> String {
        switch reason {
        case .landSport:
            if isSnowSport(sport) {
                // Jan, 30 Sep 2026: the shorter line, without the sport's name.
                return "CleanJibe reads foiling on water, and snow has no foil to read. "
                    + "It is kept, and left out of totals, trends and records."
            }
            return "This was recorded as " + sportWord(sport)
                + ", so it is not a session on the water. It is kept, and left out of "
                + "totals, trends and records."
        case .noRecording:
            return "Your watch says this afternoon happened, but its recording has not "
                + "arrived yet. It is not counted in totals, trends or records until it "
                + "does."
        case .tooShort, .noDistance, nil:
            return "No time on the foil, " + clock(durationS) + " long and "
                + distance(distanceKm)
                + " covered. This looks like a recording rather than a session. It is "
                + "kept, and left out of totals, trends and records."
        }
    }

    /// The FIT profile's sport name as a rider reads it: `e_biking` → "e-biking". A file
    /// that somehow reaches here without one is "another sport", never an empty space.
    static func sportWord(_ sport: String?) -> String {
        guard let sport, !sport.isEmpty else { return "another sport" }
        return sport.lowercased().replacingOccurrences(of: "_", with: "-")
    }

    /// `m:ss` under an hour, `h:mm:ss` over it — the session clock's own shape.
    static func clock(_ seconds: Double?) -> String {
        let total = Int((seconds ?? 0).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Metres under a kilometre, because "0.0 km" is what put this row on the screen and
    /// saying it back is no answer at all.
    static func distance(_ km: Double?) -> String {
        let value = km ?? 0
        return value < 1 ? String(Int((value * 1000).rounded())) + " m"
                         : String(format: "%.1f km", value)
    }
}
