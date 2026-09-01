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

    /// Per sample: the barometer reads `dropM` below the session median ⇒ wrist wet.
    /// A source without an altitude channel yields all-false, so it simply loses this
    /// evidence instead of failing.
    static func submergedMask(_ alt: [Double?], dropM: Double) -> [Bool] {
        let finite = alt.compactMap { $0.flatMap { $0.isFinite ? $0 : nil } }
        guard !finite.isEmpty else { return [Bool](repeating: false, count: alt.count) }
        let threshold = median(finite) - dropM
        return alt.map { value in
            guard let v = value, v.isFinite else { return false }
            return v < threshold
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

    /// Distance covered from sample `a` to `b` on speed channel `v`, in metres.
    ///
    /// Trapezoid-integrated over recorded intervals only — the twin of `elapsed`, which
    /// integrates the same intervals against 1 — so a recording gap contributes no distance
    /// for the same reason it contributes no time: nothing was measured across it.
    ///
    /// The *channel* is the caller's choice and it matters. For anything measured while the
    /// rider is off the foil the honest one is `speed` (= min(Doppler, positional)), not
    /// `doppler`: both over-read a rider who is not being carried — wrist Doppler picks up
    /// swim strokes, positional picks up GPS jitter — so the lower of the two is a distance
    /// he certainly covered. Mirrors `travelled` in `lab/src/wingfoil_lab/evidence.py`.
    static func travelled(t: [Double], gap: [Bool], v: [Double], a: Int, b: Int) -> Double {
        guard b > a, a >= 0, b < t.count else { return 0 }
        var sum = 0.0
        for i in (a + 1)...b where !gap[i] { sum += (t[i] - t[i - 1]) * (v[i] + v[i - 1]) / 2 }
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
