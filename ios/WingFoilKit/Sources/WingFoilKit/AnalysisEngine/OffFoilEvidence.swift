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
/// Contract: docs/algorithms/pumping.md "Turn outcome" steps 0–4. Mirrors
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
    /// The local altitude baseline `submerged` was read against, per sample.
    public var baseline: [Double]
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
    /// The deepest sample of the run below the baseline the run started on.
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
        let (submerged, baseline) = submergedTrace(track.samples.map(\.altM), t: t, gap: gap,
                                                   dropM: baroDropM)
        let flying = flyingMask(t: t, speed: speed, submerged: submerged, flights: flights,
                                exitMps: exitSpeedKmh * kmhToMps)
        return OffFoilEvidence(t: t, gap: gap, doppler: dop, speed: speed,
                               submerged: submerged, baseline: baseline, flying: flying)
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

    // MARK: - The submersion mask

    /// The baseline's time constant, seconds. The watch's live test walks its pressure
    /// baseline by `BARO_EMA` = 0.02 of the residual per 1 Hz sample; spelled as a time
    /// constant instead, the same walk is exact at any sample rate, which a bare coefficient
    /// is not (a 4 Hz source would adapt four times as fast for no physical reason).
    /// **A constant, not a parameter:** it is the altimeter's own slew behaviour, not a
    /// judgement about riding. Mirrors the lab's `BARO_TAU_S`.
    static let baroTauS = 50.0

    /// How long a level has to hold before the baseline accepts it, seconds. A dunk is a
    /// spike — 30 cm of water for a few seconds — and a re-anchored altimeter is a *level*:
    /// a tester's fenix 5X Plus (20 Sep 2026) stepped its whole reference by up to 190 m
    /// between stretches and then sat there for minutes. Twenty seconds is long enough that
    /// no fall can buy it (the longest corpus episode lasts 9 s) and short enough that the
    /// stretch after a re-anchor is read as riding. **A constant, not a parameter.**
    /// Mirrors the lab's `BARO_SETTLE_S`.
    static let baroSettleS = 20.0

    /// How still that level has to be, metres. Within ±5 m of each other for `baroSettleS`
    /// is flat next to a `turnBaroDrop` of 25 m and next to the 250 m a wrist under water
    /// reads, so the release cannot be triggered by a dunk that is merely slow to come back.
    /// **A constant, not a parameter.** Mirrors the lab's `BARO_SETTLE_M`.
    static let baroSettleM = 5.0

    /// Has the level held within `baroSettleM` for `baroSettleS` of unbroken samples?
    ///
    /// Walks back from `i` while the window is not yet `baroSettleS` long, and refuses on the
    /// first gap, the first non-finite sample and the first sample more than `baroSettleM`
    /// from `x`. False when the track does not reach back that far — a settle has to be
    /// *observed*, and the opening seconds of a recording have observed nothing.
    /// Mirrors the lab's `_settled`.
    private static func settled(_ alt: [Double?], t: [Double], gap: [Bool], i: Int,
                                x: Double) -> Bool {
        var j = i
        while j > 0, t[i] - t[j] < baroSettleS {
            guard !gap[j], let previous = alt[j - 1], previous.isFinite,
                  abs(previous - x) <= baroSettleM else { return false }
            j -= 1
        }
        return t[i] - t[j] >= baroSettleS - 1e-9
    }

    /// (mask, baseline): the wrist-under test and the line each sample was judged against.
    ///
    /// Causal and local (engine 0.22.0, docs/algorithms/pumping.md "Turn outcome" step 2). A sample
    /// is wet when it sits `dropM` below the baseline **in force at that moment**, not below
    /// the session's median: a watch that re-anchors its altitude after a swim otherwise
    /// turns every later stretch into a swim of its own.
    ///
    /// The baseline starts at the first finite sample, restarts at every sample a recording
    /// gap precedes, and otherwise walks towards a dry sample with time constant `baroTauS`.
    /// While a sample reads wet the baseline **holds** — a swim must not be able to
    /// re-baseline itself dry — except for the **settle release**: a level that has held for
    /// `baroSettleS` within `baroSettleM` is accepted as the new baseline and the sample is
    /// dry. A dunk is a spike; a level is not a dunk.
    ///
    /// A source without an altitude channel yields all-false, so it simply loses this
    /// evidence instead of failing. Mirrors the lab's `submerged_trace`.
    static func submergedTrace(_ alt: [Double?], t: [Double], gap: [Bool],
                               dropM: Double) -> (mask: [Bool], baseline: [Double]) {
        var mask = [Bool](repeating: false, count: alt.count)
        var baseline = [Double](repeating: .nan, count: alt.count)
        var base: Double?
        var lastT = 0.0
        for i in alt.indices {
            guard let x = alt[i], x.isFinite else {
                baseline[i] = base ?? .nan
                continue
            }
            guard let current = base, !gap[i] else {
                base = x
                lastT = t[i]
                baseline[i] = x
                continue
            }
            let dt = t[i] - lastT
            lastT = t[i]
            if x >= current - dropM {
                base = current + (1 - exp(-dt / baroTauS)) * (x - current)
            } else if settled(alt, t: t, gap: gap, i: i, x: x) {
                base = x                    // the settle release: a level is not a dunk
            } else {
                mask[i] = true              // wet: the baseline holds under a spike
            }
            baseline[i] = base ?? .nan
        }
        return (mask, baseline)
    }

    /// Per sample: the barometer reads `dropM` below the local baseline ⇒ wrist wet.
    /// The mask half of `submergedTrace`, for the callers that do not need the baseline.
    static func submergedMask(_ alt: [Double?], t: [Double], gap: [Bool],
                              dropM: Double) -> [Bool] {
        submergedTrace(alt, t: t, gap: gap, dropM: dropM).mask
    }

    /// Two runs closer together than this are one submersion (docs/algorithms/pumping.md
    /// "Submersion episodes"): a dunk and the wave that follows it are one event to the
    /// rider, and a slew-limited altimeter can cross the threshold twice on the way back up.
    public static let submersionMergeS = 2.0

    /// The mask's contiguous true-runs, per gap-free segment, with near ones merged —
    /// unattributed. Mirrors the lab's `submersion_runs`.
    ///
    /// A recording gap always breaks a run: the samples either side of it are not evidence
    /// about one another, which is the rule every other window in this type obeys.
    ///
    /// `baseline` is `submergedTrace`'s second return, and a run's depth is read against the
    /// line **in force at its first wet sample** — the same line the mask crossed to open
    /// the run, so the two cannot drift and `dropM` is always at least `turnBaroDrop`.
    static func submersionRuns(t: [Double], gap: [Bool], submerged: [Bool], alt: [Double?],
                               baseline: [Double],
                               mergeS: Double = submersionMergeS) -> [Submersion] {
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
                .min() ?? baseline[a]
            return Submersion(startT: t[a], endT: t[b],
                              durationS: elapsed(t: t, gap: gap, a: a, b: b),
                              dropM: baseline[a] - deepest)
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

    /// (last sample index of an outcome tail, *did the rider never recover*).
    ///
    /// **A fall the turn caused is the turn's fall** (engine 0.24.0, ADR-032).
    /// `recoveryEnd` above answers "how long is this event on the hook" and closes the tail
    /// at the first recovery, the first gap, or a cap. Until 0.24.0 that cap was
    /// `lookaheadS` (12 s) for everyone, and a rider who *never recovers* — the learner who
    /// mushes slowly out of a jibe and coasts to a stop — had his stop begin just past it,
    /// so the maneuver read `touchdown` and the stop was booked a second time by the other
    /// channel. The tail now follows a rider who is **still not flying again** for up to
    /// `notRecoveredS` (30 s).
    ///
    /// Recovery is unchanged and still closes the tail wherever it happens, so this only
    /// ever lengthens a tail that had nothing to close it. A recording gap still ends the
    /// measurement exactly as before: a gap inside the first `lookaheadS` closes the tail
    /// there *and* reports `false` — the samples the far side of a hole are not evidence
    /// that the rider failed to recover, they are no evidence at all.
    ///
    /// The second return is the **not-recovered condition**, defined once here and read by
    /// both `TurnDetector` and `FlightEndClassifier`: the tail ran past `lookaheadS`
    /// without recovery and without a gap. Equivalently: *no recovery at any point between
    /// the event and the stop.* Mirrors `outcome_tail` in `lab/src/wingfoil_lab/evidence.py`.
    static func outcomeTail(t: [Double], gap: [Bool], doppler: [Double], lo: Int,
                            fromT: Double, afterT: Double, thrMps: Double, holdS: Double,
                            lookaheadS: Double, notRecoveredS: Double) -> (Int, Bool) {
        let hi = recoveryEnd(t: t, gap: gap, doppler: doppler, lo: lo,
                             capT: fromT + max(lookaheadS, notRecoveredS),
                             afterT: afterT, thrMps: thrMps, holdS: holdS)
        return (hi, t[hi] > fromT + lookaheadS)
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
