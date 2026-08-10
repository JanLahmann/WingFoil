import Foundation

/// Flight-detection parameters (docs/algorithms.md "Flight (foil) detection").
public struct FlightConfig: Sendable, Equatable {
    public var foilEntrySpeedKmh: Double = 12.0
    public var entryHoldS: Double = 2.0
    public var foilExitSpeedKmh: Double = 8.0
    public var exitHoldS: Double = 3.0
    public var minFlightDurationS: Double = 5.0
    /// v2, phone-only touchdown merging; 0 = off.
    public var touchdownMergeGapS: Double = 0.0

    public init() {}

    var entryMps: Double { foilEntrySpeedKmh / Units.mpsToKmh }
    var exitMps: Double { foilExitSpeedKmh / Units.mpsToKmh }
}

/// One detected flight. Times are seconds from session start (sample-aligned):
/// `startT` = first qualifying (≥ entry) sample — backdated; `endT` = first sub-exit
/// sample — backdated (segment-final sample if the flight was cut by a gap/data end).
public struct Flight: Sendable, Equatable {
    public var startT: Double
    public var endT: Double
    /// Trapezoid integral of Doppler speed over the flight (m).
    public var distM: Double
    public var maxKn: Double

    public var durationS: Double { endT - startT }

    public init(startT: Double, endT: Double, distM: Double, maxKn: Double) {
        self.startT = startT
        self.endT = endT
        self.distM = distM
        self.maxKn = maxKn
    }
}

public struct FlightSegmentation: Sendable, Equatable {
    public var flights: [Flight] = []
    /// Sum of kept flight durations (flights < minFlightDuration don't count).
    public var foilTimeS: Double = 0
    /// Percentage of timer time (total non-gap time) spent on foil.
    public var foilPct: Double = 0
    public var longest: Flight?

    public init() {}
}

/// Hysteresis state machine over the cleaned Doppler channel. Time-based holds: a
/// hold accumulates real dt between qualifying samples, so 1 Hz and 0.5 Hz tracks of
/// the same speed profile segment identically. Gaps hard-break flights (a flight
/// never spans a gap; state resets per segment). Mirrors `lab/…/flight.py`.
public enum FlightSegmenter {

    public static func segment(_ track: CleanTrack, config: FlightConfig = FlightConfig())
    -> FlightSegmentation {
        var result = FlightSegmentation()
        guard !track.samples.isEmpty else { return result }
        let entry = config.entryMps
        let exit = config.exitMps

        var flights: [Flight] = []
        for seg in track.segments {
            for (s, e) in flightSpans(track.samples, seg, entry: entry, exit: exit,
                                      entryHold: config.entryHoldS, exitHold: config.exitHoldS) {
                let startT = track.samples[s].t
                let endT = track.samples[e].t
                guard endT - startT >= config.minFlightDurationS else { continue }
                let dist = track.samples[e].cumDistM - track.samples[s].cumDistM
                var maxV = 0.0
                for i in s...e { maxV = max(maxV, track.samples[i].dopplerMps) }
                flights.append(Flight(startT: startT, endT: endT, distM: dist,
                                      maxKn: maxV * Units.mpsToKn))
            }
        }

        result.flights = flights
        result.foilTimeS = flights.map(\.durationS).reduce(0, +)
        result.foilPct = track.timerTimeS > 0 ? 100 * result.foilTimeS / track.timerTimeS : 0
        result.longest = flights.max { $0.durationS < $1.durationS }
        return result
    }

    /// Hysteresis over one gap-free segment; returns (startIndex, endIndex) pairs
    /// (absolute indices into `samples`).
    private static func flightSpans(_ samples: [CleanSample], _ seg: Range<Int>,
                                    entry: Double, exit: Double,
                                    entryHold: Double, exitHold: Double) -> [(Int, Int)] {
        var spans: [(Int, Int)] = []
        var on = false
        var startIdx = -1
        var run = -1          // entry-run first index, -1 = inactive
        var acc = 0.0
        var xrun = -1         // exit-run first index
        var xacc = 0.0
        for i in seg {
            let v = samples[i].dopplerMps
            if !on {
                if v >= entry {
                    if run < 0 {
                        run = i
                        acc = 0
                    } else {
                        acc += samples[i].t - samples[i - 1].t
                    }
                    if acc >= entryHold {
                        on = true
                        startIdx = run
                        xrun = -1
                        xacc = 0
                    }
                } else {
                    run = -1
                }
            } else {
                if v <= exit {
                    if xrun < 0 {
                        xrun = i
                        xacc = 0
                    } else {
                        xacc += samples[i].t - samples[i - 1].t
                    }
                    if xacc >= exitHold {
                        on = false
                        spans.append((startIdx, xrun))
                        run = -1
                    }
                } else {
                    xrun = -1
                }
            }
        }
        if on {
            spans.append((startIdx, seg.upperBound - 1))   // cut by gap / data end
        }
        return spans
    }
}
