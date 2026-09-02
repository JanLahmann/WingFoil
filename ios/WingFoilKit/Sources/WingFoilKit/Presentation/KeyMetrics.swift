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
/// 1. `basics` — duration (`10:45 min` / `1:57 h`), distance, average speed.
/// 2. `maxSpeed` — the best 2 s record, labelled with the window it is, never "top speed".
/// 3. `tally` + `streaks` — the outcome ladder's own three counts, plus the two streaks
///    §5.1 flagged as computed-and-never-shown on either platform. The tally's caption
///    carries the **clean jibe** count as well as the total, so the one number a rider
///    quotes about his turns is in the block rather than three screens down.
/// 4. `rates` — the per-hour rates (`docs/algorithms.md` "Session rates"); CPH counts the
///    **clean** jibes since 0.10.0, and its label says so.
///
/// Everything resolves to a display string here so both platforms format one way and so
/// the *content* is testable without a renderer — the same arrangement `ShareCardStats`
/// uses, and for the same reason: a block that prints "0.0 CPH" where it means "there is
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
        /// What the three numbers are out of, and how many of them were **clean** —
        /// "of 50 jibes · 12 clean", or "of 51 turns · 12 clean" on a session whose wind
        /// axis never resolved and which therefore has no jibes.
        ///
        /// A *clean jibe* is a counted jibe flown all the way through with the speed
        /// carried — the engine's `success` flag (`docs/algorithms.md`, `turnSuccessPct`).
        /// It is a stricter verdict than the ladder's green and deliberately a different
        /// number: the three counts say how each turn ended, the clean count says how many
        /// of them the rider actually got right.
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
    /// "5 flew · 11 dry", nil with no counted turns. Flying leads: it is the harder of
    /// the two runs and the one the rider is chasing, and `longestFlewStreak` is always
    /// the smaller number, so the pair reads strict-then-lenient in both halves.
    public let streaks: Metric?
    /// CPH (or TPH) and WPH. **Empty** when `durationS <= 0` — the engine reports the
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
                       value: duration(summary.durationS)),
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
                         value: "\(t.longestFlewStreak) flew · \(t.longestDryStreak) dry")
                : nil,
            rates: rates(summary))
    }

    /// The jibe ladder when the session named jibes, the whole counted-turn ladder when it
    /// could not.
    ///
    /// Jibes are what the rider asked for and what CPH counts one row below, so the two
    /// have to be about the same turns. But a session with no usable wind axis has no
    /// jibes at all (`unclassified`), and an empty tally on a screen full of turns would
    /// read as "nothing happened" — so it falls back to every counted turn, exactly the
    /// way the rate row falls back from CPH to TPH, and on the very same test. The caption
    /// says which, so the three numbers can never be mistaken for the other set.
    ///
    /// The caption also carries the **clean** count — the jibes he flew all the way
    /// through carrying his speed (`turnSuccessPct`). It rides in the caption rather than
    /// in a cell of its own because it is about the same set of turns the three counts are
    /// about, and because a fifth cell on row 3 is a cell the streaks pair would lose.
    static func tally(_ t: TurnSummary) -> Tally? {
        if t.jibes > 0 {
            let o = t.jibeOutcomes
            return Tally(flewThrough: o.flewThrough, touchdown: o.touchdown,
                         fellIn: o.fellIn,
                         caption: "of \(t.jibes) jibes · \(t.jibesSuccessful) clean")
        }
        guard t.turnsCounted > 0 else { return nil }
        let o = t.outcomes
        return Tally(flewThrough: o.flewThrough, touchdown: o.touchdown, fellIn: o.fellIn,
                     caption: "of \(t.turnsCounted) turns · \(t.turnsSuccessful) clean")
    }

    /// CPH · WPH, one decimal.
    ///
    /// CPH is **clean** jibes per hour (engine 0.10.0), and the label says so: the jibes he
    /// flew all the way through carrying his speed, which is the verdict the rider is
    /// actually chasing and the one the tally's caption counts a row up. It replaced JPH
    /// here in 0.10.0 — the dry rate forgives every touchdown, and a headline that forgives
    /// is a headline that stops moving. JPH is still measured and still shown, in the turn
    /// analytics where the ladder it belongs to lives.
    ///
    /// It degrades to TPH rather than to 0.0 — and on the **tally's** test, not on its own
    /// value: a session whose wind axis never resolved has turns and no jibes at all, and
    /// naming a jibe rate over it would be naming a set that does not exist. A session that
    /// *did* jibe and rode none of them keeps CPH at `0.0`, because that is a measured
    /// verdict and TPH would hide it. WPH needs no fallback — a fell-in flight end is a
    /// fall whatever the wind was doing.
    static func rates(_ s: SessionSummary) -> [Metric] {
        guard let wet = s.wetPerHour else { return [] }
        var out: [Metric] = []
        if s.turns.jibes > 0 || (s.turnsPerHour ?? 0) <= 0 {
            out.append(Metric(key: "cph", label: "CPH · clean jibes per hour",
                              value: rate(s.cleanJibesPerHour ?? 0)))
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

    /// How long the session was: `1:57 h` past an hour, `10:45 min` under one.
    ///
    /// **Why the short form exists.** This was `h:mm` at every length, so a ten minute
    /// forty-five second session printed **`0:11`** — the two most interesting digits
    /// rounded away, and a leading zero where the number should be. That is survivable on
    /// a page the rider can scroll past; it is not survivable on the share card, which is
    /// a PNG in somebody else's chat thread with no re-render and nothing beside it to
    /// check against. A short session is exactly the kind a rider shares ("first
    /// flight!"), and `0:11` is the one string that makes it look like nothing happened.
    ///
    /// **Why the unit rides inside the value.** Every other cell in this block carries its
    /// own unit in the big type — `2.6 km`, `13.47 kn` — so a duration doing the same is
    /// the block's own habit rather than a special case. It also settles the ambiguity the
    /// bare digits create: `10:45` under the word "duration" reads as ten and three
    /// quarter *hours* just as easily as it reads as ten and three quarter minutes, and at
    /// cell size, on a card, with no second number to calibrate against, there is nothing
    /// to resolve it. `10:45 min` cannot be misread, and needs no caption to say so —
    /// which matters, because the card's caption slot is a layout affordance the tally
    /// already owns.
    ///
    /// Both forms keep `m:ss`/`h:mm` colon arithmetic rather than "10 m 45 s": the colon
    /// is what a clock looks like, it stays narrow at 75 px type, and it is the shape the
    /// flight table and the replay caption already print (`FlightPairing.clock`).
    ///
    /// Rounded to the nearest minute above the hour and to the nearest second below it —
    /// never truncated, in both cases for the same reason: `0:00` over a recording that
    /// exists reads as a failure to measure. Twin of `hm` in web/js/cardstats.js.
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            let minutes = Int((Double(total) / 60).rounded())
            return String(format: "%d:%02d h", minutes / 60, minutes % 60)
        }
        return String(format: "%d:%02d min", total / 60, total % 60)
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
