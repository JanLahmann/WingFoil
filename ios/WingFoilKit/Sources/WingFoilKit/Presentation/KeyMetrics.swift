import Foundation

/// The KEY METRICS block that opens the session analysis on the phone and on the web.
///
/// `docs/app-ui-review.md` §1.1 measured the defect this closes: on a 6.9″ phone the first
/// actual result sat one and a third screens below the fold, under a map, ten legend chips
/// and three paragraphs of legend documentation. The rider finishes a session and wants
/// four things — how long was I out, how fast, how did the jibes go, how busy was it — and
/// every one of them was already in the analysis document.
///
/// Four rows, in this order, numbers big and labels small (the watch's established taste):
///
/// 1. `basics` — duration `h:mm`, distance, average speed.
/// 2. `maxSpeed` — the best 2 s record, labelled with the window it is, never "top speed".
/// 3. `tally` + `streaks` — the outcome ladder's own three counts, plus the two streaks
///    §5.1 flagged as computed-and-never-shown on either platform.
/// 4. `rates` — the 0.6.0 per-hour rates (`docs/algorithms.md` "Session rates").
///
/// Everything resolves to a display string here so both platforms format one way and so
/// the *content* is testable without a renderer — the same arrangement `ShareCardStats`
/// uses, and for the same reason: a block that prints "0.0 JPH" where it means "there is
/// no hour to divide by" is a mistake no screenshot shows.
///
/// Mirrored in `web/js/render.js` (`keyMetrics`). A difference between the two is a bug.
public struct KeyMetrics: Sendable, Equatable {

    /// One number with the label that sits under it.
    public struct Metric: Sendable, Equatable, Identifiable {
        public let key: String
        public let label: String
        public let value: String

        public var id: String { key }

        public init(key: String, label: String, value: String) {
            self.key = key
            self.label = label
            self.value = value
        }
    }

    /// The outcome tally, drawn on the ladder's own inks (green · orange · red) by the
    /// view. The counts stay numbers rather than a joined string precisely because the
    /// colour is the point — `docs/presentation.md`, "the outcome ladder is a verdict
    /// scale and nothing else may borrow it".
    public struct Tally: Sendable, Equatable {
        public let flewThrough: Int
        public let touchdown: Int
        public let fellIn: Int
        /// What the three numbers are out of — "of 50 jibes", or "of 51 turns" on a
        /// session whose wind axis never resolved and which therefore has no jibes.
        public let caption: String

        public var total: Int { flewThrough + touchdown + fellIn }

        public init(flewThrough: Int, touchdown: Int, fellIn: Int, caption: String) {
            self.flewThrough = flewThrough
            self.touchdown = touchdown
            self.fellIn = fellIn
            self.caption = caption
        }
    }

    /// Duration · distance · average speed. Always three.
    public let basics: [Metric]
    /// The best 2 s record — the session's fastest *measured* window, not a peak sample.
    public let maxSpeed: Metric
    /// nil when no turn was counted: a tally of three zeros is not a verdict.
    public let tally: Tally?
    /// "11 dry · 5 flew", nil with no counted turns.
    public let streaks: Metric?
    /// JPH (or TPH) and WPH. **Empty** when `durationS <= 0` — the engine reports the
    /// rates as null there, and "no hour to divide by" is an absence, not a 0.0.
    public let rates: [Metric]

    public init(basics: [Metric], maxSpeed: Metric, tally: Tally?, streaks: Metric?,
                rates: [Metric]) {
        self.basics = basics
        self.maxSpeed = maxSpeed
        self.tally = tally
        self.streaks = streaks
        self.rates = rates
    }

    // MARK: - Building

    public static func make(summary: SessionSummary, records: GP3SRecords) -> KeyMetrics {
        let t = summary.turns
        return KeyMetrics(
            basics: [
                Metric(key: "duration", label: "duration",
                       value: hoursMinutes(summary.durationS)),
                Metric(key: "distance", label: "distance", value: km(summary.distanceKm)),
                Metric(key: "avgSpeed", label: "avg speed",
                       value: knots(knFromKmh(summary.avgSpeedKmh))),
            ],
            // Labelled with the window it actually is. The record set's own contract
            // (docs/presentation.md, "Record windows") is that a chip names the window it
            // is highlighting; "max speed" over a 2 s peak would be the same overclaim.
            maxSpeed: Metric(key: "max2s", label: "max 2 s", value: knots(records.best2sKn)),
            tally: tally(t),
            streaks: t.turnsCounted > 0
                ? Metric(key: "streaks", label: "best streaks",
                         value: "\(t.longestDryStreak) dry · \(t.longestFlewStreak) flew")
                : nil,
            rates: rates(summary))
    }

    /// The jibe ladder when the session named jibes, the whole counted-turn ladder when it
    /// could not.
    ///
    /// Jibes are what the rider asked for and what JPH counts one row below, so the two
    /// have to be about the same turns. But a session with no usable wind axis has no
    /// jibes at all (`unclassified`), and an empty tally on a screen full of turns would
    /// read as "nothing happened" — so it falls back to every counted turn, exactly the
    /// way the rate row falls back from JPH to TPH. The caption says which, so the three
    /// numbers can never be mistaken for the other set.
    static func tally(_ t: TurnSummary) -> Tally? {
        if t.jibes > 0 {
            let o = t.jibeOutcomes
            return Tally(flewThrough: o.flewThrough, touchdown: o.touchdown,
                         fellIn: o.fellIn, caption: "of \(t.jibes) jibes")
        }
        guard t.turnsCounted > 0 else { return nil }
        let o = t.outcomes
        return Tally(flewThrough: o.flewThrough, touchdown: o.touchdown, fellIn: o.fellIn,
                     caption: "of \(t.turnsCounted) turns")
    }

    /// JPH · WPH, one decimal.
    ///
    /// JPH degrades to TPH rather than to 0.0: a session whose wind axis never resolved
    /// has turns and no jibes, and "0.0 jibes per hour" would be a verdict on a rider who
    /// jibed all afternoon. WPH needs no such fallback — a fell-in flight end is a fall
    /// whatever the wind was doing.
    static func rates(_ s: SessionSummary) -> [Metric] {
        guard let wet = s.wetPerHour else { return [] }
        var out: [Metric] = []
        if let jibes = s.jibesPerHour, jibes > 0 || (s.turnsPerHour ?? 0) <= 0 {
            out.append(Metric(key: "jph", label: "JPH · jibes per hour",
                              value: rate(jibes)))
        } else if let turns = s.turnsPerHour {
            out.append(Metric(key: "tph", label: "TPH · turns per hour",
                              value: rate(turns)))
        }
        out.append(Metric(key: "wph", label: "WPH · swims per hour", value: rate(wet)))
        return out
    }

    // MARK: - Formatting
    //
    // Local and POSIX-stable, like `ShareCardStats`: the same strings have to come out of
    // the Swift and the JavaScript halves of this block, and a locale's decimal comma
    // would silently split them.

    static func rate(_ value: Double) -> String { String(format: "%.1f", value) }

    /// `1:57` — hours and minutes, which is how long a session is talked about. Seconds
    /// belong to a flight timer, not to an afternoon.
    ///
    /// Rounded to the nearest minute rather than truncated: a 59 s clip is a minute on the
    /// water, and `0:00` over a recording that exists reads as a failure to measure.
    static func hoursMinutes(_ seconds: Double) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func km(_ value: Double) -> String { String(format: "%.1f km", value) }

    static func knots(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f kn", value)
    }

    /// The rider's unit is knots everywhere in both apps (records, chart axis, callouts),
    /// so the one summary number the engine reports in km/h is converted rather than
    /// printed beside a column of knots.
    static func knFromKmh(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return value / 1.852
    }
}
