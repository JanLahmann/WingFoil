import Foundation

/// GP3S record-set parameters (docs/algorithms.md "Speed records").
public struct RecordsConfig: Sendable, Equatable {
    public var alphaProximityM: Double = 50
    public var alphaMaxDistanceM: Double = 500
    /// Candidate pruning (gps-wizard): windows below this path or COG spread can't be
    /// alphas — which also excludes degenerate straight-line windows.
    public var alphaPruneMinPathM: Double = 250
    public var alphaPruneMinCogSpreadDeg: Double = 90

    public init() {}
}

/// Provenance of a record: where in the session it happened.
public struct RecordWindow: Sendable, Codable, Equatable {
    public var startTs: Double
    public var durS: Double

    public init(startTs: Double, durS: Double) {
        self.startTs = startTs
        self.durS = durS
    }
}

/// GP3S speed-record set in knots. nil = not achievable in this session (segment
/// shorter than the window / not enough distance / fewer than 5 disjoint 10 s runs /
/// no closing alpha window). Matches the golden JSON `records` object (docs/testing.md);
/// the lab goldens encode "not achieved" as 0.0.
public struct GP3SRecords: Sendable, Codable, Equatable {
    public var best2sKn: Double?
    public var best10sKn: Double?
    public var best5x10sKn: Double?
    public var best100mKn: Double?
    public var best250mKn: Double?
    public var best500mKn: Double?
    public var bestNmKn: Double?
    public var bestHourKn: Double?
    public var alpha500Kn: Double?
    /// Window provenance per record, keyed by record name ("best2s", "alpha500", …).
    /// For "best5x10s" this is the top window (the lab golden stores all five).
    public var windows: [String: RecordWindow] = [:]
    /// Total Doppler-integrated session distance (m). Not part of the golden `records`
    /// object (the golden carries km in `summary`), so not encoded here.
    public var totalDistanceM: Double = 0

    enum CodingKeys: String, CodingKey {
        case best2sKn, best10sKn, best5x10sKn, best100mKn, best250mKn, best500mKn
        case bestNmKn, bestHourKn, alpha500Kn, windows
    }

    public init() {}
}

/// GP3S calculator over the cleaned Doppler channel. All windows are continuous-time:
/// cumulative distance (trapezoid-integrated Doppler) is linearly interpolated at
/// window edges, so results are identical for identical speed-vs-time profiles
/// regardless of sample rate. Windows never span hard gaps (per-segment, including
/// the 1 h search). No minimum-speed floor anywhere. Mirrors `lab/…/gp3s.py`.
public enum GP3SCalculator {

    static let nmM = 1852.0

    public static func records(for track: CleanTrack, config: RecordsConfig = RecordsConfig())
    -> GP3SRecords {
        var out = GP3SRecords()
        guard let last = track.samples.last else { return out }
        out.totalDistanceM = last.cumDistM
        let segs = segmentArrays(track)
        guard !segs.isEmpty else { return out }

        let durations: [(String, Double)] = [("best2s", 2), ("best10s", 10), ("bestHour", 3600)]
        for (name, dur) in durations {
            if let hit = bestDurationWindow(segs, durS: dur) {
                let kn = hit.mps * Units.mpsToKn
                out.windows[name] = RecordWindow(startTs: hit.startT, durS: dur)
                switch name {
                case "best2s": out.best2sKn = kn
                case "best10s": out.best10sKn = kn
                default: out.bestHourKn = kn
                }
            }
        }

        if let hit = best5x10(segs) {
            out.best5x10sKn = hit.meanMps * Units.mpsToKn
            out.windows["best5x10s"] = hit.top
        }

        let distances: [(String, Double)] = [("best100m", 100), ("best250m", 250),
                                             ("best500m", 500), ("bestNm", nmM)]
        for (name, dist) in distances {
            if let hit = bestDistanceWindow(segs, distM: dist) {
                let kn = dist / hit.durS * Units.mpsToKn
                out.windows[name] = RecordWindow(startTs: hit.startT, durS: hit.durS)
                switch name {
                case "best100m": out.best100mKn = kn
                case "best250m": out.best250mKn = kn
                case "best500m": out.best500mKn = kn
                default: out.bestNmKn = kn
                }
            }
        }

        if let hit = alpha500(segs, config: config) {
            out.alpha500Kn = hit.mps * Units.mpsToKn
            out.windows["alpha500"] = RecordWindow(startTs: hit.startT, durS: hit.durS)
        }
        return out
    }

    // MARK: - Per-segment arrays

    /// Per gap-free segment (≥ 2 samples): times, per-segment cumulative distance,
    /// local meters (NaN without GPS) and unwrapped per-interval COG.
    struct SegArrays {
        var t: [Double]
        var c: [Double]
        var x: [Double]
        var y: [Double]
        /// Unwrapped interval bearings (deg, count − 1); near-zero displacements
        /// (< 0.5 m) inherit the last bearing.
        var u: [Double]
        var hasXY: Bool
    }

    static func segmentArrays(_ track: CleanTrack) -> [SegArrays] {
        var segs: [SegArrays] = []
        for seg in track.segments where seg.count >= 2 {
            let base = track.samples[seg.lowerBound].cumDistM
            var t = [Double](); var c = [Double]()
            var x = [Double](); var y = [Double]()
            t.reserveCapacity(seg.count)
            for i in seg {
                let s = track.samples[i]
                t.append(s.t)
                c.append(s.cumDistM - base)
                x.append(s.x ?? .nan)
                y.append(s.y ?? .nan)
            }
            let hasXY = x.contains { !$0.isNaN }
            segs.append(SegArrays(t: t, c: c, x: x, y: y,
                                  u: unwrappedBearings(x: x, y: y), hasXY: hasXY))
        }
        return segs
    }

    /// Per-interval COG (deg, np.unwrap semantics). Displacements < 0.5 m give no
    /// bearing and inherit the last one (forward- then backward-fill, then 0).
    static func unwrappedBearings(x: [Double], y: [Double]) -> [Double] {
        let n = x.count
        guard n >= 2 else { return [] }
        var bear = [Double](repeating: .nan, count: n - 1)
        for k in 0..<(n - 1) {
            let dx = x[k + 1] - x[k]
            let dy = y[k + 1] - y[k]
            let disp = (dx * dx + dy * dy).squareRoot()
            if disp >= 0.5 {                          // NaN disp fails the test too
                bear[k] = atan2(dx, dy) * 180 / .pi
            }
        }
        var lastSeen = Double.nan
        for k in bear.indices {
            if bear[k].isNaN { bear[k] = lastSeen } else { lastSeen = bear[k] }
        }
        var nextSeen = Double.nan
        for k in bear.indices.reversed() {
            if bear[k].isNaN { bear[k] = nextSeen } else { nextSeen = bear[k] }
        }
        for k in bear.indices where bear[k].isNaN { bear[k] = 0 }

        var u = bear
        for k in 1..<u.count {
            let dd = bear[k] - bear[k - 1]
            var m = (dd + 180).truncatingRemainder(dividingBy: 360)
            if m < 0 { m += 360 }
            m -= 180                                   // [-180, 180)
            if m == -180 && dd > 0 { m = 180 }         // np.unwrap keeps +180 for +180
            u[k] = u[k - 1] + m
        }
        return u
    }

    /// Piecewise-linear interpolation of (t, c) at time q, clamped at the ends.
    private static func interp(_ q: Double, _ t: [Double], _ c: [Double]) -> Double {
        if q <= t[0] { return c[0] }
        if q >= t[t.count - 1] { return c[c.count - 1] }
        var lo = 0, hi = t.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if t[mid] <= q { lo = mid } else { hi = mid }
        }
        guard t[hi] > t[lo] else { return c[lo] }
        return c[lo] + (q - t[lo]) / (t[hi] - t[lo]) * (c[hi] - c[lo])
    }

    // MARK: - Duration windows (2 s / 10 s / 1 h)

    /// Max average Doppler speed over any window of `durS` seconds → (mps, startT).
    /// Candidate starts: every sample time (forward search) and every sample time
    /// minus `durS` (backward search — the classic 1 h bug guard), plus
    /// exclusion-zone edges; cumulative distance interpolated at the window edges.
    static func bestDurationWindow(_ segs: [SegArrays], durS: Double,
                                   exclude: [(Double, Double)] = [])
    -> (mps: Double, startT: Double)? {
        var bestV = -Double.infinity
        var bestS: Double?
        for s in segs {
            let t = s.t, c = s.c
            guard t[t.count - 1] - t[0] + 1e-9 >= durS else { continue }
            var cand = t
            cand.append(contentsOf: t.lazy.map { $0 - durS })
            for (a, b) in exclude {
                cand.append(b)
                cand.append(a - durS)
            }
            cand.sort()
            let lo = t[0], hi = t[t.count - 1] - durS
            var prev = Double.nan
            for start in cand {
                if start == prev { continue }          // np.unique
                prev = start
                guard start >= lo - 1e-9, start <= hi + 1e-9 else { continue }
                if exclude.contains(where: { start + durS > $0.0 + 1e-9 && start < $0.1 - 1e-9 }) {
                    continue                           // overlaps an excluded zone
                }
                let avg = (interp(start + durS, t, c) - interp(start, t, c)) / durS
                if avg > bestV {
                    bestV = avg
                    bestS = start
                }
            }
        }
        guard let start = bestS else { return nil }
        return (bestV, start)
    }

    // MARK: - 5 × 10 s

    /// Greedy best 5 non-overlapping 10 s windows (each iteration re-searches with the
    /// chosen zones excluded, adding zone-edge candidates). nil when fewer than 5
    /// disjoint windows exist — GP3S needs all five (the lab keeps a partial mean;
    /// observable only on tracks with < 50 s of usable data).
    static func best5x10(_ segs: [SegArrays]) -> (meanMps: Double, top: RecordWindow)? {
        let durS = 10.0
        var chosen: [(Double, Double)] = []
        var vals: [Double] = []
        var top: RecordWindow?
        for _ in 0..<5 {
            guard let hit = bestDurationWindow(segs, durS: durS, exclude: chosen) else { break }
            if top == nil { top = RecordWindow(startTs: hit.startT, durS: durS) }
            vals.append(hit.mps)
            chosen.append((hit.startT, hit.startT + durS))
        }
        guard vals.count == 5, let topWindow = top else { return nil }
        return (vals.reduce(0, +) / 5, topWindow)
    }

    // MARK: - Distance windows (100 / 250 / 500 / 1852 m)

    /// Min time over any contiguous window covering `distM` meters → (startT, durS).
    /// Two passes per segment over cumulative distance with edge interpolation:
    /// forward from every sample and backward from every sample (plateau-exact:
    /// backward starts at the latest time the target distance was reached).
    static func bestDistanceWindow(_ segs: [SegArrays], distM: Double)
    -> (startT: Double, durS: Double)? {
        var bestEl = Double.infinity
        var bestStart: Double?
        for s in segs {
            let t = s.t, c = s.c
            let n = c.count
            guard c[n - 1] >= distM else { continue }

            // Forward: window starts on sample i, end edge interpolated.
            var j = 0
            for i in 0..<n {
                let target = c[i] + distM
                if target > c[n - 1] { break }
                while c[j] < target { j += 1 }         // j ≥ 1: c[0] < target always
                let denom = max(c[j] - c[j - 1], 1e-12)
                let tEnd = t[j - 1] + (target - c[j - 1]) / denom * (t[j] - t[j - 1])
                let el = tEnd - t[i]
                if el < bestEl {
                    bestEl = el
                    bestStart = t[i]
                }
            }
            // Backward: window ends on sample j, start edge interpolated (latest t1).
            var ii = 0
            for j2 in 0..<n {
                let target = c[j2] - distM
                guard target >= c[0] - 1e-12 else { continue }
                while ii + 1 < n && c[ii + 1] <= target { ii += 1 }
                let t1: Double
                if c[ii] >= target - 1e-12 {
                    t1 = t[ii]
                } else {
                    let nxt = min(ii + 1, n - 1)
                    let denom = max(c[nxt] - c[ii], 1e-12)
                    t1 = t[ii] + (target - c[ii]) / denom * (t[nxt] - t[ii])
                }
                let el = t[j2] - t1
                if el < bestEl {
                    bestEl = el
                    bestStart = t1
                }
            }
        }
        guard let start = bestStart, bestEl > 0, bestEl.isFinite else { return nil }
        return (start, bestEl)
    }

    // MARK: - Alpha 500

    /// Alpha 500: best path/time over a contiguous window with path ≤ 500 m and
    /// endpoints ≤ 50 m apart (Pythagoras on local meters), pruned to ≥ 250 m path
    /// and ≥ 90° COG spread. Window ends at sample edges plus one interpolated end
    /// capping the path at exactly 500 m; starts at sample edges.
    static func alpha500(_ segs: [SegArrays], config: RecordsConfig)
    -> (mps: Double, startT: Double, durS: Double)? {
        var bestV = -Double.infinity
        var bestStart: Double?
        var bestEl = 0.0
        for s in segs {
            let t = s.t, c = s.c, x = s.x, y = s.y, u = s.u
            let n = t.count
            guard n >= 3, s.hasXY else { continue }
            var jend = 0
            for i in 0..<(n - 1) {
                let lim = c[i] + config.alphaMaxDistanceM
                if jend < i { jend = i }
                while jend + 1 < n && c[jend + 1] <= lim { jend += 1 }
                guard jend > i else { continue }
                var uMin = Double.infinity
                var uMax = -Double.infinity
                for j in (i + 1)...jend {
                    let ub = u[j - 1]                  // interval j-1 enters the window
                    uMin = min(uMin, ub)
                    uMax = max(uMax, ub)
                    let path = c[j] - c[i]
                    let dtv = t[j] - t[i]
                    guard path >= config.alphaPruneMinPathM,
                          uMax - uMin >= config.alphaPruneMinCogSpreadDeg,
                          dtv > 0 else { continue }
                    let dx = x[j] - x[i], dy = y[j] - y[i]
                    guard (dx * dx + dy * dy).squareRoot() <= config.alphaProximityM else {
                        continue                       // NaN-safe: NaN proximity fails
                    }
                    let sp = path / dtv
                    if sp > bestV {
                        bestV = sp
                        bestStart = t[i]
                        bestEl = dtv
                    }
                }
                // Interpolated end capping the path at exactly the 500 m limit.
                if jend < n - 1, c[jend + 1] - c[i] > config.alphaMaxDistanceM,
                   c[jend + 1] > c[jend] {
                    let frac = (lim - c[jend]) / (c[jend + 1] - c[jend])
                    let ts = t[jend] + frac * (t[jend + 1] - t[jend])
                    let xs = x[jend] + frac * (x[jend + 1] - x[jend])
                    let ys = y[jend] + frac * (y[jend + 1] - y[jend])
                    let sMin = min(uMin, u[jend])      // spread includes the partial
                    let sMax = max(uMax, u[jend])      // interval's full bearing
                    let el = ts - t[i]
                    let dx = xs - x[i], dy = ys - y[i]
                    if el > 0, sMax - sMin >= config.alphaPruneMinCogSpreadDeg,
                       (dx * dx + dy * dy).squareRoot() <= config.alphaProximityM {
                        let sp2 = config.alphaMaxDistanceM / el
                        if sp2 > bestV {
                            bestV = sp2
                            bestStart = t[i]
                            bestEl = el
                        }
                    }
                }
            }
        }
        guard let start = bestStart else { return nil }
        return (bestV, start, bestEl)
    }
}
