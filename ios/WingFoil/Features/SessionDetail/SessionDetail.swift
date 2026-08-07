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

    let row: SessionRow
    let analysis: SessionAnalysis
    let segments: [TrackSegment]
    let speed: [SpeedPoint]
    let flightBands: [Band]
    /// Provenance of the best 2 s run, drawn over the chart.
    let bestWindow: Band?
    let bounds: Bounds?
    let durationS: Double
    let maxSpeedKn: Double
    let hasHeartRate: Bool

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
        bestWindow = analysis.records.windows["best2s"].map {
            Band(id: -1, start: $0.startTs, end: $0.startTs + $0.durS)
        }

        segments = Self.buildSegments(track.samples, flights: flights)
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

    private static func buildSegments(_ samples: [RecordSample],
                                      flights: [FlightRecord]) -> [TrackSegment] {
        let positioned = samples.filter { $0.lat != nil && $0.lon != nil }
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
