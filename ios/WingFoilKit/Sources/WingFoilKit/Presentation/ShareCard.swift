import Foundation

/// Everything printed on a shareable session card, resolved once so the SwiftUI view that
/// renders it is pure layout — and so the *content* can be tested without a renderer.
///
/// Every stat is a display string, including the em-dash placeholders: a card is an image,
/// so "—" has to be decided here rather than by an optional binding at draw time.
///
/// **The stats are `KeyMetrics`, re-laid-out.** They are not a second vocabulary. The card
/// used to build its own four cells out of the index row — foil %, flight count, longest
/// flight, best 2 s — which meant the picture a rider posted and the block at the top of
/// the same session in the app named different numbers with different words. A reader who
/// has both in front of them must never have to work out which one is lying. So `make`
/// takes the *rendered* `KeyMetrics` block and turns each of its entries into a `Stat`,
/// verbatim: same keys, same order, same labels, same strings. A change to the block flows
/// into the card with no edit here, and the two cannot disagree because there is only one
/// of them.
///
/// The preset then chooses how much of that block the card shows (`Preset`). It can only
/// ever *drop* entries — nothing on the card is computed here that is not in the block.
public struct ShareCardStats: Sendable, Equatable {

    /// One headline number with its label, in the order the card lays them out.
    public struct Stat: Sendable, Equatable, Identifiable {
        public let key: String
        public let label: String
        public let value: String
        /// Shown under the value when there is something worth saying.
        public let caption: String?
        /// Set only on the outcome-tally cell, whose three counts are drawn on the verdict
        /// ladder's own inks. `value` already spells the same three numbers out, so a
        /// renderer that ignores this still prints the truth — it just prints it in one
        /// colour (docs/presentation.md, "the outcome ladder is a verdict scale").
        public let tally: KeyMetrics.Tally?

        public var id: String { key }

        public init(key: String, label: String, value: String, caption: String? = nil,
                    tally: KeyMetrics.Tally? = nil) {
            self.key = key
            self.label = label
            self.value = value
            self.caption = caption
            self.tally = tally
        }

        /// A key-metrics entry, unchanged. The card adds nothing and rewords nothing.
        public init(_ metric: KeyMetrics.Metric) {
            self.init(key: metric.key, label: metric.label, value: metric.value)
        }

        /// The outcome tally as one cell: the three counts as a value, and the block's own
        /// caption ("of 50 jibes") underneath, so the numbers can never be mistaken for a
        /// tally of some other set of turns.
        public init(_ tally: KeyMetrics.Tally) {
            self.init(key: Key.tally, label: "flew · touchdown · fell",
                      value: "\(tally.flewThrough) · \(tally.touchdown) · \(tally.fellIn)",
                      caption: tally.caption, tally: tally)
        }
    }

    /// The stat keys the card knows by name. They are `KeyMetrics.Metric.key` values —
    /// only the tally needs one of its own, because a `Tally` is not a `Metric`.
    public enum Key {
        public static let duration = "duration"
        public static let distance = "distance"
        public static let avgSpeed = "avgSpeed"
        public static let maxSpeed = "max2s"
        public static let tally = "tally"
        public static let streaks = "streaks"
        /// **The closing card's ninth cell, and nowhere else.** Not a `KeyMetrics` key: the
        /// block does not carry the longest flight, and the exported card is a strict mirror
        /// of the block — see `outro`.
        public static let longestFlight = "longestFlight"
    }

    /// How much of the key-metrics block the card carries.
    ///
    /// Two presets rather than a checklist of eight: the rider is choosing between "a clean
    /// picture with the headline on it" and "the session, fully reported", and every finer
    /// distinction than that is a decision taken at the moment they least want to take one.
    ///
    /// `complete` is the default and shows the block entire — the new rates and streaks are
    /// the point of asking for them, and a card that hid them by default would be a feature
    /// nobody found. `lean` is a strict *subset*: it can only remove entries, never
    /// substitute or reword them, which is what keeps both presets honest against the app.
    public enum Preset: String, CaseIterable, Sendable, Identifiable, Codable {
        /// Duration, distance, the best 2 s window, and the jibe tally.
        case lean
        /// The whole key-metrics block, in its own order.
        case complete

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .lean: "Lean"
            case .complete: "Complete"
            }
        }

        /// One line under the picker, so the choice is legible before it is made.
        public var summary: String {
            switch self {
            case .lean: "Duration, distance, max 2 s and the jibe tally."
            case .complete: "Everything the app's key-metrics block shows."
            }
        }

        /// What `lean` keeps — the four a rider quotes walking off the water. Held as keys
        /// rather than as a rebuilt list so the preset cannot invent an entry: anything not
        /// produced by `KeyMetrics` is simply never there to be kept.
        public static let leanKeys: Set<String> = [
            Key.duration, Key.distance, Key.maxSpeed, Key.tally,
        ]

        func keeps(_ key: String) -> Bool {
            self == .complete || Self.leanKeys.contains(key)
        }

        public func filter(_ stats: [Stat]) -> [Stat] {
            stats.filter { keeps($0.key) }
        }
    }

    /// Aspect of the exported image.
    public enum Shape: String, CaseIterable, Sendable, Identifiable {
        /// 1080 × 1350 — the tall format feeds and stories prefer.
        case portrait
        /// 1080 × 1080.
        case square
        /// 1920 × 1080 — the wide format a chat preview, a forum post or a desktop
        /// screen shows in full instead of cropping to a letterbox.
        case landscape

        public var id: String { rawValue }

        public var size: (width: Double, height: Double) {
            switch self {
            case .portrait: (1080, 1350)
            case .square: (1080, 1080)
            case .landscape: (1920, 1080)
            }
        }

        public var label: String {
            switch self {
            case .portrait: "Portrait"
            case .square: "Square"
            case .landscape: "Landscape"
            }
        }

        /// True when the card is wider than it is tall, and the track therefore belongs
        /// *beside* the stats rather than above them. The renderer asks the shape rather
        /// than testing for a case, so a fourth aspect lands in the right layout for free.
        public var isWide: Bool { size.width > size.height }
    }

    public let title: String
    public let dateLine: String
    public let stats: [Stat]
    /// The preset the stats were filtered through — carried so the renderer can size its
    /// grid to the count without counting cases.
    public let preset: Preset
    /// Set when the session's records cannot be certified, so the card cannot be read as
    /// a speed claim it has no right to make.
    public let disclaimer: String?

    public init(title: String, dateLine: String, stats: [Stat],
                preset: Preset = .complete, disclaimer: String?) {
        self.title = title
        self.dateLine = dateLine
        self.stats = stats
        self.preset = preset
        self.disclaimer = disclaimer
    }

    // MARK: - Building

    /// Builds the card content from the stored summary row and the session's key-metrics
    /// block.
    ///
    /// `title` is the caller's (the app derives a readable name from the spot or the
    /// original filename, which is presentation the kit has no business owning).
    ///
    /// `metrics` is nil only in the second before the analysis finishes loading behind the
    /// share sheet. The card then falls back to the three facts the *index row* carries
    /// that cannot possibly disagree with the block — duration, distance, best 2 s, each
    /// formatted by `KeyMetrics`' own formatters. Everything else is omitted rather than
    /// approximated: the row has no jibe-outcome split and no streaks, and a tally
    /// reconstructed from the whole-turn columns would print different numbers than the
    /// same session's block one screen away.
    public static func make(row: SessionRow, title: String, metrics: KeyMetrics? = nil,
                            preset: Preset = .complete,
                            timeZone: TimeZone = .current) -> ShareCardStats {
        ShareCardStats(
            title: title,
            dateLine: dateLine(row.startDate, timeZone: timeZone),
            stats: metrics.map { stats(from: $0, preset: preset) }
                ?? preset.filter(rowOnlyStats(row)),
            preset: preset,
            disclaimer: row.sourceClass == "c"
                ? "Speeds from a degraded source — uncertified" : nil)
    }

    /// The **closing card of a clip**: the complete block, plus the longest flight.
    ///
    /// **Why the clip's card gets a cell the exported card does not.** The outro used to print
    /// the grid and then, underneath it, two or three highlight lines lifted out of the
    /// commentary — "Top speed — 13.47 kn over 2 s", "New streak — 8 dry jibes". Two of the
    /// three were the grid again in a sentence: the max-2 s cell and the streaks cell say
    /// exactly those numbers, four centimetres higher up. The one highlight the grid did *not*
    /// carry was the longest flight, and a number is better in a cell than in a caption
    /// repeating cells around it. So the lines are gone and the number they were really about
    /// is a cell — which also makes the grid a clean 3 × 3.
    ///
    /// **Only here.** `make` is unchanged and stays a strict mirror of `KeyMetrics`: the app's
    /// key-metrics block and the PNG a rider exports must remain the same list, or the two
    /// start disagreeing about what a session is.
    ///
    /// The flight is formatted with `FlightPairing.clock` — the same "6:32" the replay's own
    /// caption said and the flight table prints, so the closing frame and the page behind it
    /// spell one number one way.
    public static func outro(row: SessionRow, title: String, metrics: KeyMetrics? = nil,
                             longestFlightS: Double? = nil,
                             timeZone: TimeZone = .current) -> ShareCardStats {
        let base = make(row: row, title: title, metrics: metrics, preset: .complete,
                        timeZone: timeZone)
        guard let flight = longestFlightStat(longestFlightS) else { return base }
        return ShareCardStats(title: base.title, dateLine: base.dateLine,
                              stats: base.stats + [flight], preset: base.preset,
                              disclaimer: base.disclaimer)
    }

    /// The longest flight as a cell, or nil when there was not one.
    ///
    /// Absent rather than "0:00": a session where nothing ever flew has an *unknown* longest
    /// flight, not a zero-second one, and a closing card that printed 0:00 would be delivering
    /// a verdict the analysis never reached. The grid is then eight cells, which is what it
    /// was before.
    public static func longestFlightStat(_ seconds: Double?) -> Stat? {
        guard let seconds, seconds > 0 else { return nil }
        return Stat(key: Key.longestFlight, label: "longest flight",
                    value: FlightPairing.clock(seconds))
    }

    /// The key-metrics block flattened into cells, in the block's own reading order:
    /// duration · distance · avg speed, the max 2 s window, the tally and the streaks, then
    /// the per-hour rates. Absent entries stay absent — a session with no wind axis has no
    /// jibe rate, and `KeyMetrics.rates` is empty rather than 0.0, so the card simply has
    /// two fewer cells (the same rule, because it is the same list).
    public static func stats(from metrics: KeyMetrics, preset: Preset) -> [Stat] {
        var out = metrics.basics.map(Stat.init)
        out.append(Stat(metrics.maxSpeed))
        if let tally = metrics.tally { out.append(Stat(tally)) }
        if let streaks = metrics.streaks { out.append(Stat(streaks)) }
        out.append(contentsOf: metrics.rates.map(Stat.init))
        return preset.filter(out)
    }

    /// The loading-state fallback — see `make`. Deliberately three cells and no tally.
    static func rowOnlyStats(_ row: SessionRow) -> [Stat] {
        [
            Stat(key: Key.duration, label: "duration",
                 value: KeyMetrics.hoursMinutes(row.durationS)),
            Stat(key: Key.distance, label: "distance",
                 value: row.distanceKm.map(KeyMetrics.km) ?? "—"),
            Stat(key: Key.maxSpeed, label: "max 2 s",
                 value: KeyMetrics.knots(row.best2sKn)),
        ]
    }

    static func dateLine(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
}

/// The one stored copy of the rider's preset choice — per user, not per session, so the
/// next card comes out the way the last one did.
///
/// Same shape as `MapLayerVisibilityStore`, and for the same reason: a preference the
/// composer reads and writes belongs behind a testable pair of functions rather than in a
/// `@AppStorage` scattered through a view. An unreadable or unknown stored value falls back
/// to `complete` — the default is "show the rider everything they asked for", and a preset
/// added in a later version must not silently strand an older app on a blank card.
public enum ShareCardPresetStore {

    public static let defaultsKey = "shareCardPreset.v1"

    public static func load(from defaults: UserDefaults) -> ShareCardStats.Preset {
        defaults.string(forKey: defaultsKey)
            .flatMap(ShareCardStats.Preset.init(rawValue:)) ?? .complete
    }

    public static func save(_ preset: ShareCardStats.Preset, to defaults: UserDefaults) {
        defaults.set(preset.rawValue, forKey: defaultsKey)
    }
}
