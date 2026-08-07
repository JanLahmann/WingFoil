import Foundation

/// Sample-hygiene parameters (docs/algorithms.md "Speed sample hygiene"). The gap rule
/// is dt-aware: gap iff dt > max(`gapMinS`, `gapFactor` × median dt) — hard segment
/// break, never interpolated across (dt-weighted windows subsume the 1 Hz
/// `gapInterpolateMax` linear-interpolation rule). Mirrors `lab/…/filters.py`.
public struct FilterConfig: Sendable, Equatable {
    /// GP3S standard HDOP gate — applied only when the channel exists (native Garmin
    /// FITs have neither hdop nor satellites; carried for config echo / future sources).
    public var maxHdop: Double = 5.0
    public var minSatellites: Int = 5
    /// Doppler acceleration spike gate: samples with |dv/dt| above this (vs the last
    /// good sample) are dropped.
    public var maxAccelMps2: Double = 4.0
    public var gapMinS: Double = 3.0
    public var gapFactor: Double = 2.0

    public init() {}
}

/// One cleaned sample. `t` is seconds from session start (same base as `RecordSample.t`).
/// Unusable raw records (missing speed/position, duplicate timestamps, Doppler spikes)
/// are dropped before this stage's timeline is built, so every kept sample has a
/// Doppler value; drops surface as larger `dt`s (and, past the threshold, gaps).
public struct CleanSample: Sendable, Equatable {
    public var t: Double
    /// Seconds since the previous kept sample (0 for the first sample of the track).
    public var dt: Double
    /// True when the step *into* this sample exceeded the gap threshold: hard segment break.
    public var gapBefore: Bool
    /// Local-meter projection (equirectangular around the track centroid:
    /// x = Δlon·cos(lat0)·111320, y = Δlat·110540); nil for position-less tracks.
    public var x: Double?
    public var y: Double?
    /// Device Doppler channel (m/s) — the speed base for detection and all records.
    public var dopplerMps: Double
    /// Positional speed from the local-meter track (dt-aware central difference inside
    /// a segment, one-sided at its edges); nil without GPS.
    public var positionalMps: Double?
    /// Cumulative Doppler-integrated distance (m): trapezoid inside segments, zero
    /// increment across gaps. The distance base for all GP3S windows.
    public var cumDistM: Double

    public init(t: Double, dt: Double, gapBefore: Bool, x: Double? = nil, y: Double? = nil,
                dopplerMps: Double = 0, positionalMps: Double? = nil, cumDistM: Double = 0) {
        self.t = t
        self.dt = dt
        self.gapBefore = gapBefore
        self.x = x
        self.y = y
        self.dopplerMps = dopplerMps
        self.positionalMps = positionalMps
        self.cumDistM = cumDistM
    }
}

/// Cleaned, projected, gap-segmented track: the input to segmentation and records.
public struct CleanTrack: Sendable {
    public var samples: [CleanSample] = []
    /// Maximal gap-free runs of `samples` indices, in time order. No analysis window
    /// ever spans two segments.
    public var segments: [Range<Int>] = []
    public var medianDtS: Double = 0
    /// The hard-gap threshold actually used: max(gapMinS, gapFactor × median dt).
    public var gapThresholdS: Double = 0
    /// Wall-clock span first→last kept sample (s).
    public var spanS: Double = 0
    /// Total non-gap time (s) — the foil-percentage denominator ("timer time").
    public var timerTimeS: Double = 0
    /// Projection origin (deg) — the centroid used for the local-meter frame.
    public var originLat: Double?
    public var originLon: Double?
    /// Rows dropped by quality gates / missing channels / spike rejection.
    public var droppedGate = 0
    public var droppedNaN = 0
    public var droppedSpike = 0
    public var config = FilterConfig()

    public init() {}

    /// Cumulative distance at an arbitrary time, linearly interpolated between samples
    /// (flat across gaps — distance never accrues where there is no data).
    public func cumDist(at t: Double) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if t <= first.t { return first.cumDistM }
        if t >= last.t { return last.cumDistM }
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        guard b.t > a.t else { return a.cumDistM }
        let f = (t - a.t) / (b.t - a.t)
        return a.cumDistM + f * (b.cumDistM - a.cumDistM)
    }
}
