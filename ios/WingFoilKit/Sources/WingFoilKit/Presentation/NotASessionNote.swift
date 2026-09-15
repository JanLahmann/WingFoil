import Foundation

/// **What the rider is told about a recording that is not a session** — the quiet tag on the
/// library row and the one line on the session page (docs/presentation.md, "Not a session").
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

    /// The page's one line: why this recording is not counted, in a sentence.
    ///
    /// `durationS` and `distanceKm` are the row's own displayed numbers, so the line reads
    /// against the key-metrics block directly above it rather than quoting a third figure.
    public static func line(reason: SessionVerdict.Reason?,
                            durationS: Double?, distanceKm: Double?) -> String {
        switch reason {
        case .noRecording:
            return "Your watch says this afternoon happened, but its recording has not "
                + "arrived yet — so it is not counted in totals, trends or records until it "
                + "does."
        case .tooShort, .noDistance, nil:
            return "No time on the foil, \(clock(durationS)) long and \(distance(distanceKm))"
                + " covered — so this looks like a recording rather than a session. It is "
                + "kept, and left out of totals, trends and records."
        }
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
        return value < 1 ? "\(Int((value * 1000).rounded())) m"
                         : String(format: "%.1f km", value)
    }
}
