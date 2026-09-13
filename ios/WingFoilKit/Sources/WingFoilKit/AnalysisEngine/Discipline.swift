import Foundation

/// **Discipline presets — one engine, three rigs** (docs/algorithms.md "Disciplines").
///
/// A discipline is *not* a fork of the engine. Every stage, every clock and every verdict is
/// the one docs/algorithms.md describes; a preset only picks the numbers a few of them are
/// asked against, and switches off the one channel a windsurfer does not have.
///
/// Mirrors `lab/src/wingfoil_lab/discipline.py`, which is the authoritative copy.
///
/// **Experimental.** Windsurf analysis has never been checked against a windsurf session with
/// ground truth — the corpus has none (GitHub issue #6 gates it on 5–10 of them). Jibes and
/// tacks are the wingfoil detector, unchanged and trustworthy; the fin's two speeds are a
/// guess written down in public so it can be argued with.
public enum Discipline: String, Sendable, Codable, CaseIterable, Equatable {
    /// The published contract, unchanged. The preset is a no-op **by construction**: it is
    /// not applied at all, so a wingfoil run is byte-identical to one produced before this
    /// type existed.
    case wingfoil
    /// A foiling windsurfer flies on the same foil at the same speeds, so every threshold is
    /// the wingfoil one. What he does not do is **pump** — there is no wing to load, the
    /// accelerometer hears the rig and the chop and nothing else, and every number built on
    /// it would be noise presented as effort.
    case windsurfFoil
    /// A fin board does not fly, it **planes**, and it planes far faster than a foil flies.
    /// The same hysteresis, at speeds a fin board reaches.
    case windsurfFin

    /// Is the pump channel run at all? Wingfoil only.
    public var pumping: Bool { self == .wingfoil }

    public var isWindsurf: Bool { self != .wingfoil }

    /// **PROVISIONAL for the fin** (issue #6): 20 km/h in, 15 km/h out is a first guess at
    /// planing thresholds, not a reading off a corpus — there is no fin session in one.
    public var foilEntrySpeedKmh: Double { self == .windsurfFin ? 20.0 : 12.0 }
    public var foilExitSpeedKmh: Double { self == .windsurfFin ? 15.0 : 8.0 }

    /// The rider's word for it — the picker's row, and the chip.
    public var title: String {
        switch self {
        case .wingfoil: "Wingfoil"
        case .windsurfFoil: "Windsurf foil"
        case .windsurfFin: "Windsurf fin"
        }
    }

    /// The preset a session is analysed under.
    ///
    /// The rider's **override** wins over everything. Failing that, the `discipline`
    /// developer field decides — and *only* it. A Garmin **windsurf profile** recording is
    /// the common way a wingfoil session reaches this library (ADR-004 records FIT sport 43
    /// for wingfoiling, and every "…-windsurfen…" file in the corpus is a wingfoil
    /// afternoon), so **the sport code alone must never switch the preset**: it is not an
    /// argument to this function, which is how that is enforced. Anything unreadable is
    /// wingfoil, the default.
    public static func resolve(tag: String?, override: String? = nil) -> Discipline {
        for value in [override, tag] {
            if let stated = stated(tag: value) { return stated }
        }
        return .wingfoil
    }

    /// The preset a tag **states**, or nil where it states nothing.
    ///
    /// The difference between this and `resolve` is the whole of the import question: a
    /// recording that carries the `discipline` developer field has *said* what it is and is
    /// never asked about again, and one that does not has said nothing — not "wingfoil". Only
    /// the CleanJibe watch app writes the field, so "nothing" is what a Garmin native profile,
    /// an Apple Health workout, an intervals.icu download, a Strava activity and a GPX all
    /// say, however confidently their sport code reads.
    public static func stated(tag: String?) -> Discipline? {
        guard let key = tag?.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: ""), !key.isEmpty else { return nil }
        switch key {
        case "windsurffin", "windsurfingfin", "fin": return .windsurfFin
        case "windsurf", "windsurfing", "windsurffoil", "windsurfingfoil", "windfoil":
            return .windsurfFoil
        case "wingfoil", "wing", "wingfoiling": return .wingfoil
        // A tag this version has never heard of (`kitefoil`) states nothing *about this
        // question*, so it falls through to the rider's default rather than to wingfoil: he
        // is the one who knows which rig he was on.
        default: return nil
        }
    }

    /// **The preset a freshly imported session is read under**, before anybody has confirmed
    /// anything (docs/presentation.md, "Confirming the discipline on import").
    ///
    /// The recording's own field if it has one — authoritative, and the review step never
    /// asks about it. Otherwise the rider's declared default (Settings → "I mostly ride"),
    /// because the *only* other evidence in the file is the sport code and the sport code is
    /// systematically wrong about this question: ADR-004 records FIT sport 43 (windsurfing)
    /// for wingfoiling, so a corpus of wingfoil afternoons would flip itself to windsurf the
    /// moment a sport code were allowed to decide. It is shown to the rider as a *hint* on the
    /// review row and never consulted here — it is not an argument to this function, which is
    /// how that is enforced rather than promised.
    public static func imported(tag: String?, riderDefault: Discipline = .wingfoil)
    -> Discipline {
        stated(tag: tag) ?? riderDefault
    }

    /// Whether an imported session's preset was a **guess** — the recording said nothing and
    /// the rider's default answered for it. What the review step lists, and what the `?`
    /// beside the library badge means.
    public static func isGuess(tag: String?) -> Bool { stated(tag: tag) == nil }

    /// The four configs that carry the two speeds, and the pump rung's switch.
    public struct Configs: Sendable, Equatable {
        public var flight: FlightConfig
        public var turn: TurnConfig
        public var flightEnd: FlightEndConfig
        public var takeoff: TakeoffConfig

        public init(flight: FlightConfig = FlightConfig(), turn: TurnConfig = TurnConfig(),
                    flightEnd: FlightEndConfig = FlightEndConfig(),
                    takeoff: TakeoffConfig = TakeoffConfig()) {
            self.flight = flight
            self.turn = turn
            self.flightEnd = flightEnd
            self.takeoff = takeoff
        }
    }

    /// The preset, over a set of configs. **Identity for `wingfoil`** — not merely equal to
    /// it, not applied, so a caller's own thresholds (a tuning slider) survive untouched.
    ///
    /// The two speeds live in *four* configs and have to move together: the flight hysteresis
    /// segments the runs, the turn ladder and the flight-end ladder read "off the foil" from
    /// the exit speed, and the takeoff analyser shares the one off-foil evidence object built
    /// from it. Moving one alone would leave the scorer judging against a speed no run was
    /// segmented on — and would silently split the shared evidence in `analyze`.
    public func apply(to base: Configs) -> Configs {
        guard isWindsurf else { return base }
        var out = base
        out.flight.foilEntrySpeedKmh = foilEntrySpeedKmh
        out.flight.foilExitSpeedKmh = foilExitSpeedKmh
        out.turn.foilEntrySpeedKmh = foilEntrySpeedKmh
        out.turn.foilExitSpeedKmh = foilExitSpeedKmh
        // Refused, not merely unreachable: with no pump channel there is no burst to
        // corroborate, and a switch left on would claim otherwise.
        out.turn.pumpedOutIsTouchdown = false
        out.flightEnd.foilEntrySpeedKmh = foilEntrySpeedKmh
        out.flightEnd.foilExitSpeedKmh = foilExitSpeedKmh
        out.takeoff.foilExitSpeedKmh = foilExitSpeedKmh
        return out
    }
}

// MARK: - The stamp in `engineVersion`

/// How a run under a non-default preset marks itself: `"0.18.0+disc.windsurfFin"`.
///
/// Same trick, and for the same reason, as `TuningStamp` — `SessionAnalysis.engineVersion` is
/// *already* the staleness key (`SessionIngestor.reanalyzeStale()` sweeps on it,
/// `SessionArchive.analysis(for:)` refuses a cached document that does not match,
/// `SessionStore.detail(for:)` reloads when the two disagree), so changing a session's
/// discipline re-derives it lazily through the one mechanism that already exists, and a
/// number on the screen can always be traced back to the preset that produced it.
///
/// It composes **inside** the tuning stamp — `0.18.0+disc.windsurfFin+tuned.2.a1b2c3d4` — so
/// `TuningStamp.parse` keeps working unchanged on the tail it owns.
public enum DisciplineStamp: Sendable {

    static let marker = "+disc."

    /// The base version a run under this preset should be stamped with; the plain engine
    /// version for wingfoil, so a library that has never touched the feature is
    /// byte-identical to one built before it existed.
    public static func key(base: String = AnalysisEngine.version,
                           discipline: Discipline) -> String {
        discipline.isWindsurf ? "\(base)\(marker)\(discipline.rawValue)" : base
    }

    /// The preset a stamped version was produced under, or `.wingfoil` for an unstamped one.
    public static func discipline(_ engineVersion: String) -> Discipline {
        let base = TuningStamp.baseVersion(engineVersion)
        guard let range = base.range(of: marker) else { return .wingfoil }
        return Discipline(rawValue: String(base[range.upperBound...])) ?? .wingfoil
    }

    /// The published engine version behind a stamped one — neither marker.
    public static func baseVersion(_ engineVersion: String) -> String {
        let base = TuningStamp.baseVersion(engineVersion)
        guard let range = base.range(of: marker) else { return base }
        return String(base[base.startIndex..<range.lowerBound])
    }
}
