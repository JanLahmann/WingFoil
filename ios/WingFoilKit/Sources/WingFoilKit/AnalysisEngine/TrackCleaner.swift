import Foundation

/// Stage 1 of the pipeline: RawTrack → CleanTrack. Row hygiene (drop rows without
/// speed — and without position when the track has any), timestamp sort/dedupe,
/// dt-aware hard-gap segmentation, Doppler spike rejection, local-meter projection,
/// positional speed, cumulative distance. Pure function of its inputs; semantics are
/// kept 1:1 with `lab/src/wingfoil_lab/filters.py` (the golden source).
public enum TrackCleaner {

    public static func clean(_ raw: RawTrack, config: FilterConfig = FilterConfig()) -> CleanTrack {
        var track = CleanTrack()
        track.config = config

        // Row hygiene: speed is mandatory (the pipeline runs on the Doppler channel);
        // position is mandatory only when the source has any. Dropped rows become
        // larger dts — and hard gaps once past the threshold.
        struct Row { var t: Double; var v: Double; var lat: Double?; var lon: Double? }
        let hasPos = raw.samples.contains { $0.lat != nil && $0.lon != nil }
        var rows: [Row] = []
        rows.reserveCapacity(raw.samples.count)
        for s in raw.samples {
            guard let v = s.speedMps else { track.droppedNaN += 1; continue }
            if hasPos, s.lat == nil || s.lon == nil { track.droppedNaN += 1; continue }
            rows.append(Row(t: s.t, v: v, lat: s.lat, lon: s.lon))
        }
        // Stable sort by t, drop duplicate timestamps (keep first).
        rows = rows.enumerated()
            .sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }
            .map(\.element)
        var deduped: [Row] = []
        deduped.reserveCapacity(rows.count)
        for r in rows {
            if let last = deduped.last, r.t == last.t { track.droppedNaN += 1; continue }
            deduped.append(r)
        }
        rows = deduped
        guard !rows.isEmpty else { return track }

        // Median dt (pre-spike timeline) and the hard-gap threshold.
        let dts = (1..<rows.count).map { rows[$0].t - rows[$0 - 1].t }
        let med = median(of: dts)
        track.medianDtS = med
        track.gapThresholdS = med > 0 ? max(config.gapMinS, config.gapFactor * med) : config.gapMinS

        // Doppler acceleration spike rejection vs the last good sample; resets across
        // gaps (self-recovering on spike runs). Rejected rows are dropped.
        var kept: [Row] = []
        kept.reserveCapacity(rows.count)
        kept.append(rows[0])
        var tg = rows[0].t
        var vg = rows[0].v
        for i in 1..<rows.count {
            let d = rows[i].t - tg
            if d > track.gapThresholdS {              // new segment: accept unconditionally
                tg = rows[i].t
                vg = rows[i].v
                kept.append(rows[i])
                continue
            }
            if d <= 0 || abs(rows[i].v - vg) / d > config.maxAccelMps2 {
                track.droppedSpike += 1
            } else {
                tg = rows[i].t
                vg = rows[i].v
                kept.append(rows[i])
            }
        }
        rows = kept

        // Local-meter projection around the centroid of the kept rows.
        var lat0 = 0.0, lon0 = 0.0
        if hasPos {
            lat0 = rows.compactMap(\.lat).reduce(0, +) / Double(rows.count)
            lon0 = rows.compactMap(\.lon).reduce(0, +) / Double(rows.count)
            track.originLat = lat0
            track.originLon = lon0
        }
        let cosLat0 = cos(lat0 * .pi / 180)

        var samples: [CleanSample] = []
        samples.reserveCapacity(rows.count)
        for (i, r) in rows.enumerated() {
            let dt = i == 0 ? 0 : r.t - rows[i - 1].t
            var c = CleanSample(t: r.t, dt: dt,
                                gapBefore: i > 0 && dt > track.gapThresholdS,
                                dopplerMps: r.v)
            if hasPos, let la = r.lat, let lo = r.lon {
                c.x = (lo - lon0) * cosLat0 * 111_320
                c.y = (la - lat0) * 110_540
            }
            samples.append(c)
        }

        // Gap-free segments.
        var segments: [Range<Int>] = []
        var segStart = 0
        for i in 1..<samples.count where samples[i].gapBefore {
            segments.append(segStart..<i)
            segStart = i
        }
        segments.append(segStart..<samples.count)
        track.segments = segments

        // Positional speed: dt-aware central difference inside segments, one-sided edges.
        if hasPos {
            for seg in segments where seg.count >= 2 {
                let lo = seg.lowerBound, hi = seg.upperBound - 1
                samples[lo].positionalMps = planarSpeed(samples[lo], samples[lo + 1])
                samples[hi].positionalMps = planarSpeed(samples[hi - 1], samples[hi])
                for i in (lo + 1)..<hi {
                    samples[i].positionalMps = planarSpeed(samples[i - 1], samples[i + 1])
                }
            }
        }

        // Cumulative Doppler-integrated distance: trapezoid inside segments, flat across gaps.
        var cum = 0.0
        for seg in segments {
            for i in seg {
                if i > seg.lowerBound {
                    cum += (samples[i].dopplerMps + samples[i - 1].dopplerMps) / 2 * samples[i].dt
                }
                samples[i].cumDistM = cum
            }
        }

        track.samples = samples
        track.spanS = samples.last!.t - samples.first!.t
        track.timerTimeS = samples.dropFirst().filter { !$0.gapBefore }.map(\.dt).reduce(0, +)
        return track
    }

    private static func planarSpeed(_ a: CleanSample, _ b: CleanSample) -> Double? {
        guard let xa = a.x, let ya = a.y, let xb = b.x, let yb = b.y, b.t > a.t else { return nil }
        return ((xb - xa) * (xb - xa) + (yb - ya) * (yb - ya)).squareRoot() / (b.t - a.t)
    }

    /// np.median semantics: mean of the two middle values for even counts.
    private static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
