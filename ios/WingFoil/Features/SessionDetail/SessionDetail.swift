import Foundation
import WingFoilKit

/// Everything one detail screen needs, prepared off the main actor: the analysis plus
/// display geometry derived from the archived FIT's samples (which are deliberately not
/// kept in the database — plan §3.3).
struct SessionDetail: Sendable {

    struct Point: Sendable {
        var lat: Double
        var lon: Double
    }

    /// A run of consecutive samples with the same phase; drawn as one polyline.
    struct TrackSegment: Identifiable, Sendable {
        var id: Int
        var flying: Bool
        var points: [Point]
    }

    struct SpeedPoint: Identifiable, Sendable {
        var id: Int
        var t: Double
        var kn: Double
    }

    struct Band: Identifiable, Sendable {
        var id: Int
        var start: Double
        var end: Double
    }

    /// What happened at a maneuver or a straight-line flight end — the thing the map and
    /// the chart both mark. `filled` separates the two channels: a solid dot is a *turn*
    /// outcome, a hollow ring is a straight-line flight end that no turn explains
    /// (docs/algorithms.md "Flight-end outcome", ownership).
    struct EventMarker: Identifiable, Sendable {
        enum Tone: Sendable {
            case flew            // green: never left the foil / glided out
            case touchdown       // amber: lost it briefly
            case fell            // red: swam
            case course          // gray: bear-away / round-up, not a maneuver
        }

        var id: Int
        var t: Double
        var lat: Double
        var lon: Double
        var tone: Tone
        var filled: Bool
        var title: String
        var detail: String
    }

    /// One GP3S record with the provenance the engine already computed, so the effort can
    /// be highlighted on the map and shaded in the chart.
    struct RecordEffort: Identifiable, Sendable {
        var id: String           // the engine's window key, e.g. "best2s"
        var label: String
        var kn: Double
        var band: Band
        var points: [Point]
    }

    let row: SessionRow
    let analysis: SessionAnalysis
    let segments: [TrackSegment]
    let speed: [SpeedPoint]
    let flightBands: [Band]
    /// Turn outcomes (solid) and straight-line flight ends (hollow), in time order.
    let markers: [EventMarker]
    /// GP3S efforts with map/chart geometry, strongest set first.
    let efforts: [RecordEffort]
    /// Watch-vs-phone disagreements worth a banner (class (a) only, empty otherwise).
    let divergences: [Divergence]
    /// The rider's own wind direction from session dev field 39, when the watch wrote one.
    let windDirUserDeg: Double?
    let bounds: Bounds?
    let durationS: Double
    let maxSpeedKn: Double
    let hasHeartRate: Bool

    struct Bounds: Sendable {
        var minLat: Double
        var maxLat: Double
        var minLon: Double
        var maxLon: Double

        var centerLat: Double { (minLat + maxLat) / 2 }
        var centerLon: Double { (minLon + maxLon) / 2 }
        var latSpan: Double { max(maxLat - minLat, 0.002) * 1.3 }
        var lonSpan: Double { max(maxLon - minLon, 0.002) * 1.3 }
    }

    /// Polyline points kept per session; a 2 h ride at 1 Hz is 7 200 samples, which
    /// MapKit draws happily, but foreign 4 Hz sources are thinned.
    private static let maxTrackPoints = 6000
    /// Chart points; bucketed by max so speed peaks survive the thinning.
    private static let maxChartPoints = 700

    init(row: SessionRow, analysis: SessionAnalysis, track: RawTrack) {
        self.row = row
        self.analysis = analysis

        let flights = analysis.flights.sorted { $0.startTs < $1.startTs }
        flightBands = flights.enumerated().map { Band(id: $0.offset, start: $0.element.startTs,
                                                      end: $0.element.endTs) }
        durationS = (track.samples.last?.t ?? 0) - (track.samples.first?.t ?? 0)
        hasHeartRate = track.capabilities.hasHR
        windDirUserDeg = track.watchSummary.windDirUserDeg
        divergences = DivergenceCheck.compare(watch: track.watchSummary, phone: analysis)

        let positioned = track.samples.filter { $0.lat != nil && $0.lon != nil }
        segments = Self.buildSegments(positioned, flights: flights)
        markers = Self.buildMarkers(analysis, positioned: positioned)
        efforts = Self.buildEfforts(analysis, positioned: positioned)

        var bounds: Bounds?
        for segment in segments {
            for point in segment.points {
                if var current = bounds {
                    current.minLat = min(current.minLat, point.lat)
                    current.maxLat = max(current.maxLat, point.lat)
                    current.minLon = min(current.minLon, point.lon)
                    current.maxLon = max(current.maxLon, point.lon)
                    bounds = current
                } else {
                    bounds = Bounds(minLat: point.lat, maxLat: point.lat,
                                    minLon: point.lon, maxLon: point.lon)
                }
            }
        }
        self.bounds = bounds

        speed = Self.buildSpeedSeries(track.samples)
        maxSpeedKn = speed.map(\.kn).max() ?? 0
    }

    // MARK: - Geometry

    private static func flyingLookup(_ flights: [FlightRecord]) -> (Double) -> Bool {
        { t in
            var lo = 0, hi = flights.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                if t < flights[mid].startTs { hi = mid - 1 }
                else if t > flights[mid].endTs { lo = mid + 1 }
                else { return true }
            }
            return false
        }
    }

    private static func buildSegments(_ positioned: [RecordSample],
                                      flights: [FlightRecord]) -> [TrackSegment] {
        guard !positioned.isEmpty else { return [] }
        let stride = max(1, positioned.count / maxTrackPoints)
        let isFlying = flyingLookup(flights)

        var segments: [TrackSegment] = []
        var current: [Point] = []
        var currentFlying = isFlying(positioned[0].t)
        var nextID = 0

        func flush() {
            guard current.count >= 2 else {
                current.removeAll()
                return
            }
            segments.append(TrackSegment(id: nextID, flying: currentFlying, points: current))
            nextID += 1
            current.removeAll()
        }

        for (index, sample) in positioned.enumerated() {
            let flying = isFlying(sample.t)
            let keep = index % stride == 0 || index == positioned.count - 1
                || flying != currentFlying
            guard keep else { continue }
            let point = Point(lat: sample.lat!, lon: sample.lon!)
            if flying != currentFlying {
                current.append(point)          // shared vertex: no visual gap at the phase change
                flush()
                currentFlying = flying
            }
            current.append(point)
        }
        flush()
        return segments
    }

    /// Turn outcomes plus the straight-line flight ends no turn already explains.
    ///
    /// The two channels genuinely see different events (a 2 s turn touchdown never breaks a
    /// flight), so both are drawn — but a flight end flagged `ownedByTurn` is already
    /// counted at its turn and would double-mark the same swim, so it is dropped. `unknown`
    /// ends are dropped too: the recording stopped, nothing happened there.
    private static func buildMarkers(_ analysis: SessionAnalysis,
                                     positioned: [RecordSample]) -> [EventMarker] {
        guard !positioned.isEmpty else { return [] }
        var out: [EventMarker] = []
        var nextID = 0

        func add(t: Double, tone: EventMarker.Tone, filled: Bool, title: String, detail: String) {
            guard let sample = nearest(positioned, t: t),
                  let lat = sample.lat, let lon = sample.lon else { return }
            out.append(EventMarker(id: nextID, t: t, lat: lat, lon: lon, tone: tone,
                                   filled: filled, title: title, detail: detail))
            nextID += 1
        }

        for turn in analysis.turns {
            let tone: EventMarker.Tone = turn.counted ? outcomeTone(turn.outcome) : .course
            var detail = String(format: "%.1f → %.1f kn", turn.entryKn, turn.minKn)
            if turn.stoppedS > 0 { detail += String(format: " · stopped %.0f s", turn.stoppedS) }
            if turn.submerged { detail += " · wrist under" }
            if turn.pumped { detail += " · pumped out" }
            add(t: turn.ts, tone: tone, filled: true,
                title: turnTitle(turn), detail: detail)
        }
        for end in analysis.flightEnds where end.ownedByTurn == nil && !end.truncated {
            var detail = "straight-line"
            if end.stoppedS > 0 { detail += String(format: " · stopped %.0f s", end.stoppedS) }
            if end.submerged { detail += " · wrist under" }
            add(t: end.ts, tone: outcomeTone(end.outcome), filled: false,
                title: endTitle(end.outcome), detail: detail)
        }
        return out.sorted { $0.t < $1.t }
    }

    private static func outcomeTone(_ outcome: String) -> EventMarker.Tone {
        switch outcome {
        case "fell_in": return .fell
        case "touchdown": return .touchdown
        default: return .flew            // flew_through | glide_out
        }
    }

    private static func turnTitle(_ turn: TurnRecord) -> String {
        let kind: String
        switch turn.type {
        case "jibe": kind = "Jibe"
        case "tack": kind = "Tack"
        case "bear_away": kind = "Bear-away"
        case "round_up": kind = "Round-up"
        default: kind = "Turn"
        }
        guard turn.counted else { return kind }
        let outcome: String
        switch turn.outcome {
        case "fell_in": outcome = "fell in"
        case "touchdown": outcome = turn.borderline ? "touchdown (borderline)" : "touchdown"
        default: outcome = "flew through"
        }
        return "\(kind) · \(outcome)"
    }

    private static func endTitle(_ outcome: String) -> String {
        switch outcome {
        case "fell_in": return "Fell in"
        case "touchdown": return "Touchdown"
        default: return "Glided out"
        }
    }

    /// GP3S efforts, using the window provenance the engine already carries.
    private static func buildEfforts(_ analysis: SessionAnalysis,
                                     positioned: [RecordSample]) -> [RecordEffort] {
        let catalogue: [(String, String, Double?)] = [
            ("best2s", "Best 2 s", analysis.records.best2sKn),
            ("best10s", "Best 10 s", analysis.records.best10sKn),
            ("best5x10s", "5 × 10 s", analysis.records.best5x10sKn),
            ("best500m", "Best 500 m", analysis.records.best500mKn),
            ("bestNm", "Best 1 NM", analysis.records.bestNmKn),
            ("alpha500", "Alpha 500", analysis.records.alpha500Kn),
        ]
        var out: [RecordEffort] = []
        for (key, label, kn) in catalogue {
            guard let kn, kn > 0, let window = analysis.records.windows[key] else { continue }
            let start = window.startTs
            let end = window.startTs + window.durS
            let points = positioned
                .filter { $0.t >= start && $0.t <= end }
                .compactMap { s -> Point? in
                    guard let lat = s.lat, let lon = s.lon else { return nil }
                    return Point(lat: lat, lon: lon)
                }
            out.append(RecordEffort(id: key, label: label, kn: kn,
                                    band: Band(id: out.count, start: start, end: end),
                                    points: points))
        }
        return out
    }

    /// The positioned sample closest in time to `t` (binary search over a sorted array).
    private static func nearest(_ samples: [RecordSample], t: Double) -> RecordSample? {
        guard !samples.isEmpty else { return nil }
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        return abs(samples[lo].t - t) <= abs(samples[hi].t - t) ? samples[lo] : samples[hi]
    }

    private static func buildSpeedSeries(_ samples: [RecordSample]) -> [SpeedPoint] {
        let usable = samples.filter { $0.speedMps != nil }
        guard let first = usable.first, let last = usable.last, last.t > first.t else { return [] }
        let span = last.t - first.t
        let buckets = min(maxChartPoints, max(1, usable.count))
        let width = span / Double(buckets)
        guard width > 0 else { return [] }

        var peaks = [Double](repeating: -1, count: buckets)
        for sample in usable {
            let index = min(buckets - 1, Int((sample.t - first.t) / width))
            peaks[index] = max(peaks[index], (sample.speedMps ?? 0) * Units.mpsToKn)
        }
        var out: [SpeedPoint] = []
        out.reserveCapacity(buckets)
        for (index, value) in peaks.enumerated() where value >= 0 {
            out.append(SpeedPoint(id: index, t: first.t + (Double(index) + 0.5) * width, kn: value))
        }
        return out
    }
}
