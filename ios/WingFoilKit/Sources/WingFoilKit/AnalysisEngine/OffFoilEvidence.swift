import Foundation

/// Shared off-foil evidence: the channels every outcome verdict is read from.
///
/// Turn outcomes (`TurnDetector`) and flight-end outcomes (`FlightEndClassifier`) ask the
/// *same three questions* of the same track — did the foil stop carrying (speed), did the
/// wrist go under (barometer), did the rider have to pump it back up (accelerometer) — so
/// the masks, the stop measure and the recovery search live here and both callers read one
/// ladder. Only the maneuver-specific parts stay with the caller: which window is judged,
/// which entry speed the recovery is measured against, and what the verdict is called.
///
/// Contract: docs/algorithms.md "Turn outcome" steps 0–4. Mirrors
/// `lab/src/wingfoil_lab/evidence.py` (the authoritative reference).
public struct OffFoilEvidence: Sendable {
    /// Sample times (whole track, gaps included).
    public var t: [Double]
    /// A recording gap precedes this sample.
    public var gap: [Bool]
    /// Device Doppler (flight state, recovery test).
    public var doppler: [Double]
    /// min(Doppler, positional): the sharp "is the foil still carrying" test.
    public var speed: [Double]
    /// Barometer says the wrist is under water.
    public var submerged: [Bool]
    /// In a flight, above exit speed, not submerged.
    public var flying: [Bool]

    public var count: Int { t.count }
}

/// One spell the barometer says the wrist spent under water (engine 0.16.0).
///
/// **Presentation evidence, never a verdict.** The `submerged` flags on turns and flight
/// ends are the outcome ladder's input and are computed exactly as they always were; this is
/// the same mask read a second way — as events with a time, a length and a depth, so a map
/// can put one mark on each of them instead of one mark on the maneuver that owned one.
/// Mirrors `lab/src/wingfoil_lab/evidence.py`'s `Submersion`.
public struct Submersion: Sendable, Equatable {
    /// First submerged sample of the run.
    public var startT: Double
    /// Last submerged sample of the run.
    public var endT: Double
    /// Gap-aware elapsed time between the two.
    public var durationS: Double
    /// The deepest sample of the run below `Evidence.submergedReference`.
    public var dropM: Double
    /// The counted turn whose outcome window this run overlaps, else nil.
    public var turnIndex: Int?
    /// Failing that, the drawn flight end whose window it overlaps, else nil — and a run
    /// with neither happened while the rider was already off the foil.
    public var flightEndIndex: Int?

    public init(startT: Double, endT: Double, durationS: Double, dropM: Double,
                turnIndex: Int? = nil, flightEndIndex: Int? = nil) {
        self.startT = startT
        self.endT = endT
        self.durationS = durationS
        self.dropM = dropM
        self.turnIndex = turnIndex
        self.flightEndIndex = flightEndIndex
    }
}

/// Builders and the shared window/stop primitives.
public enum Evidence {

    static let kmhToMps = 1.0 / 3.6

    /// Evidence arrays for a whole cleaned track, or nil when it is empty.
    ///
    /// Built over the whole track rather than per segment: a fall that starts before a
    /// recording gap is still followed into the samples after it (the *window* search stops
    /// at the gap, but the arrays must span it).
    public static func build(_ track: CleanTrack, flights: FlightSegmentation,
                             exitSpeedKmh: Double, baroDropM: Double) -> OffFoilEvidence? {
        guard !track.samples.isEmpty else { return nil }
        let t = track.samples.map(\.t)
        let gap = track.samples.map(\.gapBefore)
        let dop = track.samples.map(\.dopplerMps)
        let speed = track.samples.map { min($0.dopplerMps, $0.hybridMps) }
        let submerged = submergedMask(track.samples.map(\.altM), dropM: baroDropM)
        let flying = flyingMask(t: t, speed: speed, submerged: submerged, flights: flights,
                                exitMps: exitSpeedKmh * kmhToMps)
        return OffFoilEvidence(t: t, gap: gap, doppler: dop, speed: speed,
                               submerged: submerged, flying: flying)
    }

    /// Per sample: inside a flight, above the foil exit speed, and not underwater.
    ///
    /// Flight segmentation alone is too coarse: its exit needs `exitHold` (3 s) of sub-exit
    /// speed, so a 1–2 s touchdown never breaks the flight. The instantaneous speed test
    /// makes those visible while the flight mask still catches the long losses.
    static func flyingMask(t: [Double], speed: [Double], submerged: [Bool],
                           flights: FlightSegmentation, exitMps: Double) -> [Bool] {
        var m = [Bool](repeating: false, count: t.count)
        for f in flights.flights {
            for i in t.indices where t[i] >= f.startT && t[i] <= f.endT { m[i] = true }
        }
        for i in t.indices { m[i] = m[i] && speed[i] > exitMps && !submerged[i] }
        return m
    }

    /// The altitude the submersion test is measured *against*: the session median of the
    /// finite samples, or nil when there is no altitude channel at all.
    ///
    /// Spelled once because two things read it — the mask below, and `dropM` on a submersion
    /// episode, which is how far under this same line the deepest sample of the run got.
    /// Mirrors the lab's `submerged_reference`.
    static func submergedReference(_ alt: [Double?]) -> Double? {
        let finite = alt.compactMap { $0.flatMap { $0.isFinite ? $0 : nil } }
        guard !finite.isEmpty else { return nil }
        return median(finite)
    }

    /// Per sample: the barometer reads `dropM` below the session median ⇒ wrist wet.
    /// A source without an altitude channel yields all-false, so it simply loses this
    /// evidence instead of failing.
    static func submergedMask(_ alt: [Double?], dropM: Double) -> [Bool] {
        guard let reference = submergedReference(alt) else {
            return [Bool](repeating: false, count: alt.count)
        }
        let threshold = reference - dropM
        return alt.map { value in
            guard let v = value, v.isFinite else { return false }
            return v < threshold
        }
    }

    /// Two runs closer together than this are one submersion (docs/algorithms.md
    /// "Submersion episodes"): a dunk and the wave that follows it are one event to the
    /// rider, and a slew-limited altimeter can cross the threshold twice on the way back up.
    public static let submersionMergeS = 2.0

    /// The mask's contiguous true-runs, per gap-free segment, with near ones merged —
    /// unattributed. Mirrors the lab's `submersion_runs`.
    ///
    /// A recording gap always breaks a run: the samples either side of it are not evidence
    /// about one another, which is the rule every other window in this type obeys.
    static func submersionRuns(t: [Double], gap: [Bool], submerged: [Bool], alt: [Double?],
                               mergeS: Double = submersionMergeS) -> [Submersion] {
        guard let reference = submergedReference(alt) else { return [] }
        var spans: [(Int, Int)] = []
        var i = 0
        while i < t.count {
            guard submerged[i] else { i += 1; continue }
            var b = i
            while b + 1 < t.count, submerged[b + 1], !gap[b + 1] { b += 1 }
            if let last = spans.last {
                let near = t[i] - t[last.1] < mergeS
                let broken = ((last.1 + 1)...i).contains { gap[$0] }
                if near && !broken {
                    spans[spans.count - 1] = (last.0, b)
                    i = b + 1
                    continue
                }
            }
            spans.append((i, b))
            i = b + 1
        }
        return spans.map { a, b in
            let deepest = (a...b).compactMap { alt[$0].flatMap { $0.isFinite ? $0 : nil } }
                .min() ?? reference
            return Submersion(startT: t[a], endT: t[b],
                              durationS: elapsed(t: t, gap: gap, a: a, b: b),
                              dropM: reference - deepest)
        }
    }

    /// Name what each episode happened *during*, in place. Mirrors the lab's
    /// `attribute_submersions`.
    ///
    /// Order matters and is the map's: a counted turn's outcome window first, because that
    /// is the maneuver a rider remembers going under in; then a drawn flight end's window,
    /// which is the straight-line swim; and otherwise nothing at all — the rider was already
    /// off the foil, which is a real answer and not a missing one. First match wins.
    static func attribute(_ subs: inout [Submersion],
                          turnWindows: [(index: Int, start: Double, end: Double)],
                          endWindows: [(index: Int, start: Double, end: Double)]) {
        for i in subs.indices {
            if let hit = turnWindows.first(where: {
                subs[i].startT <= $0.end && subs[i].endT >= $0.start
            }) {
                subs[i].turnIndex = hit.index
                continue
            }
            if let hit = endWindows.first(where: {
                subs[i].startT <= $0.end && subs[i].endT >= $0.start
            }) {
                subs[i].flightEndIndex = hit.index
            }
        }
    }

    /// Last sample index an outcome is judged over: recovery, a gap, or the `capT` cap.
    ///
    /// *Recovery* is the rider back to cruising — Doppler at or above `thrMps`, held for
    /// `holdS` with the same both-ends-qualify convention flight entry uses. Searched only
    /// past `afterT`, so the speed the window opened at cannot close it immediately.
    /// A **recording gap ends the window** even before recovery: flights hard-break at gaps,
    /// so following the search across would manufacture a loss out of missing data.
    static func recoveryEnd(t: [Double], gap: [Bool], doppler: [Double], lo: Int,
                            capT: Double, afterT: Double, thrMps: Double, holdS: Double) -> Int {
        var hi = lo
        var last = -1
        var held = 0.0
        var i = lo
        while i < t.count {
            if t[i] > capT || (i > lo && gap[i]) { break }
            hi = i
            defer { i += 1 }
            if t[i] <= afterT { continue }
            if doppler[i] < thrMps {
                held = 0
                last = -1
                continue
            }
            held = last == i - 1 ? held + (t[i] - t[last]) : 0
            last = i
            if held >= holdS { break }
        }
        return hi
    }

    /// From the first non-flying sample `a`, (last non-flying index, first flying index).
    /// The run is followed past the judging window until foiling resumes, capped at `capT`
    /// so an event just before a break does not absorb it.
    static func offFoilRun(t: [Double], flying: [Bool], a: Int, capT: Double) -> (Int, Int) {
        var b = a
        while b + 1 < t.count, !flying[b + 1], t[b + 1] <= capT { b += 1 }
        return (b, min(b + 1, t.count - 1))
    }

    /// Recorded time from sample `a` to `b`, skipping intervals that span a gap.
    static func elapsed(t: [Double], gap: [Bool], a: Int, b: Int) -> Double {
        guard b > a else { return 0 }
        var sum = 0.0
        for i in (a + 1)...b where !gap[i] { sum += t[i] - t[i - 1] }
        return sum
    }

    /// Longest contiguous spell below `floor` in [a, b], in recorded seconds.
    /// An interval counts only when *both* of its end samples are below the floor and no gap
    /// separates them — the same "hold" convention flight segmentation uses.
    static func longestStop(t: [Double], gap: [Bool], v: [Double], a: Int, b: Int,
                            floor: Double) -> Double {
        guard b > a, a >= 0, b < t.count else { return 0 }
        var best = 0.0
        var run = 0.0
        for i in (a + 1)...b {
            let keep = v[i] < floor && v[i - 1] < floor && !gap[i]
            run = keep ? run + (t[i] - t[i - 1]) : 0
            best = max(best, run)
        }
        return best
    }

    /// np.median semantics: mean of the two middle values for even counts.
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}
