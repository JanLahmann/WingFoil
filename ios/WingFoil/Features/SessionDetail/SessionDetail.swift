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

    /// One takeoff run he pumped through: the stretch of track between the first stroke
    /// (or the start of the speed rise) and the moment the board came up.
    ///
    /// It is the pumping that *worked*, and only that: a span is drawn from a takeoff run,
    /// so a failed attempt gets a takeoff-layer marker (`TakeoffMark.Kind.failed`) rather
    /// than a stretch of tinted track. In-flight pumping stays a summary total — it is a
    /// different act from trying to get up, and tinting it would read as one.
    struct PumpSpan: Identifiable, Sendable {
        var id: Int
        var band: Band
        /// nil on a source with no accelerometer; such a run is not drawn at all.
        var strokes: Int?
        var points: [Point]
    }

    /// A takeoff *attempt*, at the instant it began or failed.
    ///
    /// Two things share this layer because to the rider they are one act: pumping to get
    /// up. `Kind` is what separates them, and it is exactly the split the data supports —
    /// a flight started, or a pumping episode the engine classified `failed`.
    struct TakeoffMark: Identifiable, Sendable {
        enum Kind: Sendable {
            case pumped          // a flight, worked for
            case free            // a flight, under `freeTakeoff` strokes: the wind did it
            case failed          // a real burst that produced no flight
        }

        var id: Int
        var t: Double
        var lat: Double
        var lon: Double
        var kind: Kind
        var title: String
        var detail: String

        var isFailed: Bool { kind == .failed }
    }

    /// A moment the barometer says the wrist went under water — the turns and flight ends
    /// the engine flagged `submerged`. Not every swim produces one (the sensor has to see
    /// the pressure step), so this layer is evidence, not a census.
    struct SplashMark: Identifiable, Sendable {
        var id: Int
        var t: Double
        var lat: Double
        var lon: Double
        var title: String
        var detail: String
    }

    /// Where one counted turn happened. `id` is its index in `analysis.turns`, which is
    /// also `TurnListItem.id` — so a row in the turns page and a dot on its map are the
    /// same turn by construction rather than by a lookup that could drift.
    struct TurnPin: Identifiable, Sendable {
        var id: Int
        var t: Double
        var lat: Double
        var lon: Double
        var outcome: TurnOutcomeKind
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

    /// One instant of the session as the replay scrubber reads it: everything the live
    /// readout shows, on the *sample* clock rather than the chart's bucketed one.
    ///
    /// The chart series is bucketed by max (peaks must survive thinning), which makes it
    /// the wrong thing to scrub: its `kn` is a bucket maximum and it carries no position.
    /// This is the parallel, evenly-thinned series the playhead actually rides on.
    struct TimelinePoint: Sendable, Equatable {
        var t: Double
        var lat: Double?
        var lon: Double?
        var kn: Double
        var hr: Double?
        var flying: Bool
    }

    let row: SessionRow
    let analysis: SessionAnalysis
    let segments: [TrackSegment]
    let speed: [SpeedPoint]
    /// Scrubbable timeline, ascending in `t`.
    let timeline: [TimelinePoint]
    let flightBands: [Band]
    /// Turn outcomes (solid) and straight-line flight ends (hollow), in time order.
    let markers: [EventMarker]
    /// The pumped takeoff runs, in time order.
    let pumpSpans: [PumpSpan]
    /// One per takeoff the analysis carries.
    let takeoffMarks: [TakeoffMark]
    /// Submersion evidence on turns and straight-line flight ends.
    let splashMarks: [SplashMark]
    /// Positions of the counted turns, keyed by their index in `analysis.turns`.
    let turnPins: [TurnPin]
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
    /// Scrubber resolution. A 2 h ride at 1 Hz is 7 200 samples; 1 500 keeps the playhead
    /// smooth under a finger (≈5 s per step on the longest sessions) without holding the
    /// whole record stream alive for a screen that only reads one instant at a time.
    private static let maxTimelinePoints = 1500

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
        pumpSpans = Self.buildPumpSpans(analysis, positioned: positioned)
        takeoffMarks = Self.buildTakeoffMarks(analysis, positioned: positioned)
        splashMarks = Self.buildSplashMarks(analysis, positioned: positioned)
        turnPins = Self.buildTurnPins(analysis, positioned: positioned)
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
        timeline = Self.buildTimeline(track.samples, flights: flights)
    }

    // MARK: - Replay

    /// Scrubbable span. Empty when the recording has no usable timeline at all.
    var timeRange: ClosedRange<Double>? {
        guard let first = timeline.first, let last = timeline.last, last.t > first.t else {
            return nil
        }
        return first.t...last.t
    }

    /// The instant nearest `t` — what the readout, the chart playhead and the map dot all
    /// resolve through, so the three can never point at different moments.
    func moment(at t: Double) -> TimelinePoint? {
        guard !timeline.isEmpty else { return nil }
        var lo = 0, hi = timeline.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if timeline[mid].t <= t { lo = mid } else { hi = mid }
        }
        return abs(timeline[lo].t - t) <= abs(timeline[hi].t - t) ? timeline[lo] : timeline[hi]
    }

    /// The time of the track point nearest a tapped coordinate, or nil when the tap landed
    /// nowhere near the track. `toleranceM` keeps a tap on open water from yanking the
    /// playhead to some unrelated corner of the session.
    func time(nearLat lat: Double, lon: Double, toleranceM: Double) -> Double? {
        // Equirectangular metres around the tap: over a session-sized box this is exact
        // enough to rank distances, and it avoids a CoreLocation call per sample.
        let cosLat = cos(lat * .pi / 180)
        var bestT: Double?
        var bestDistanceSq = Double.infinity
        for point in timeline {
            guard let pLat = point.lat, let pLon = point.lon else { continue }
            let dx = (pLon - lon) * cosLat * 111_320
            let dy = (pLat - lat) * 110_540
            let distanceSq = dx * dx + dy * dy
            if distanceSq < bestDistanceSq {
                bestDistanceSq = distanceSq
                bestT = point.t
            }
        }
        return bestDistanceSq <= toleranceM * toleranceM ? bestT : nil
    }

    /// Evenly thinned — *not* bucketed by max. The scrubber shows the speed at an instant,
    /// so it must report what the recording says at that instant rather than the local
    /// peak, which would read high everywhere and make a steady reach look gusty.
    private static func buildTimeline(_ samples: [RecordSample],
                                      flights: [FlightRecord]) -> [TimelinePoint] {
        guard !samples.isEmpty else { return [] }
        let isFlying = flyingLookup(flights)
        let stride = max(1, (samples.count + maxTimelinePoints - 1) / maxTimelinePoints)
        var out: [TimelinePoint] = []
        out.reserveCapacity(samples.count / stride + 1)
        for (index, sample) in samples.enumerated()
        where index % stride == 0 || index == samples.count - 1 {
            out.append(TimelinePoint(t: sample.t, lat: sample.lat, lon: sample.lon,
                                     kn: (sample.speedMps ?? 0) * Units.mpsToKn,
                                     hr: sample.heartRate,
                                     flying: isFlying(sample.t)))
        }
        return out
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
        for end in PresentationRules.drawnFlightEnds(analysis) {
            var detail = "straight-line"
            if end.stoppedS > 0 { detail += String(format: " · stopped %.0f s", end.stoppedS) }
            if end.submerged { detail += " · wrist under" }
            add(t: end.ts, tone: outcomeTone(end.outcome), filled: false,
                title: endTitle(end.outcome), detail: detail)
        }
        return out.sorted { $0.t < $1.t }
    }

    /// Through the shared rule (`PresentationRules`), not a second copy of the ladder:
    /// the chip a mark answers to and the colour it is drawn in must be the same decision.
    private static func outcomeTone(_ outcome: String) -> EventMarker.Tone {
        switch PresentationRules.layer(forOutcome: outcome) {
        case .fellIn: return .fell
        case .touchdown: return .touchdown
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

    /// The takeoff runs he pumped through, as spans of track.
    ///
    /// A truncated run is skipped: the recording does not reach back over it, so there is
    /// no stretch of water to tint — drawing one would invent the approach. So is a run
    /// with no strokes (the wind did it) and one from a source with no accelerometer,
    /// where "pumping" is not a thing this file can know about at all.
    private static func buildPumpSpans(_ analysis: SessionAnalysis,
                                       positioned: [RecordSample]) -> [PumpSpan] {
        var out: [PumpSpan] = []
        for takeoff in analysis.takeoffs {
            guard !takeoff.truncated, let strokes = takeoff.pumps, strokes > 0,
                  takeoff.startTs > takeoff.runStartTs else { continue }
            let points = self.points(positioned, from: takeoff.runStartTs, to: takeoff.startTs)
            guard points.count >= 2 else { continue }
            out.append(PumpSpan(id: out.count,
                                band: Band(id: out.count, start: takeoff.runStartTs,
                                           end: takeoff.startTs),
                                strokes: strokes, points: points))
        }
        return out
    }

    /// Both halves of the takeoff layer: the attempts that flew and the attempts that did
    /// not.
    ///
    /// Every entry in `analysis.takeoffs` succeeded — the engine only emits one for a
    /// flight that happened — so the failures come from the other block. Engine 0.3.0
    /// serializes `pumpEpisodes`, and an episode the classifier called `failed` is exactly
    /// "he pumped a real burst and did not get up": a timestamp, and therefore a position.
    ///
    /// The other three outcomes are deliberately *not* marked. `success` is the same event
    /// as the takeoff already drawn beside it and would double-mark it; `recovery` is
    /// pumping the foil back after a jibe touchdown, which the turn markers already score;
    /// `in_flight` is pumping to hold a glide, not an attempt at anything; and `unknown`
    /// means the recording stopped before it could be judged — marking it would state as
    /// fact the one thing the data cannot say.
    private static func buildTakeoffMarks(_ analysis: SessionAnalysis,
                                          positioned: [RecordSample]) -> [TakeoffMark] {
        var out: [TakeoffMark] = []
        func add(t: Double, kind: TakeoffMark.Kind, title: String, detail: String) {
            guard let sample = nearest(positioned, t: t),
                  let lat = sample.lat, let lon = sample.lon else { return }
            out.append(TakeoffMark(id: out.count, t: t, lat: lat, lon: lon, kind: kind,
                                   title: title, detail: detail))
        }

        for takeoff in analysis.takeoffs {
            var detail = String(format: "up at %.1f kn", takeoff.entryKn)
            if let pumps = takeoff.pumps {
                detail += " · \(pumps) stroke\(pumps == 1 ? "" : "s")"
            }
            if !takeoff.truncated {
                detail += String(format: " · %.0f s run", takeoff.timeToFoilS)
            }
            add(t: takeoff.startTs, kind: takeoff.free ? .free : .pumped,
                title: takeoff.free ? "Free takeoff" : "Takeoff", detail: detail)
        }
        // The episode's *first* stroke, not its last: the marker should sit where he
        // started trying, which is where the pumping run he can recognise begins.
        for episode in PresentationRules.failedAttempts(analysis) {
            var detail = "\(episode.strokes) stroke\(episode.strokes == 1 ? "" : "s")"
            let duration = episode.endTs - episode.startTs
            if duration >= 1 { detail += String(format: " · %.0f s", duration) }
            if episode.bursts > 1 { detail += " · \(episode.bursts) bursts" }
            add(t: episode.startTs, kind: .failed, title: "Failed attempt", detail: detail)
        }

        // Time order, so the chart's marks and the map's read the session the same way —
        // `id` is only an identity for `ForEach`, so it is reassigned after the sort.
        return out.sorted { $0.t < $1.t }.enumerated().map { index, mark in
            var mark = mark
            mark.id = index
            return mark
        }
    }

    /// Where the wrist went under. Both channels of the engine's `submerged` evidence: a
    /// turn that ended in the water, and a straight-line flight end no turn explains. The
    /// same ownership rule the outcome markers use keeps one swim from being marked twice.
    private static func buildSplashMarks(_ analysis: SessionAnalysis,
                                         positioned: [RecordSample]) -> [SplashMark] {
        var out: [SplashMark] = []
        func add(t: Double, title: String, detail: String) {
            guard let sample = nearest(positioned, t: t),
                  let lat = sample.lat, let lon = sample.lon else { return }
            out.append(SplashMark(id: out.count, t: t, lat: lat, lon: lon,
                                  title: title, detail: detail))
        }
        for turn in PresentationRules.splashTurns(analysis) {
            add(t: turn.ts, title: "\(TurnAnalytics.typeLabel(turn.type)) · wrist under",
                detail: String(format: "%.1f → %.1f kn", turn.entryKn, turn.minKn))
        }
        for end in PresentationRules.splashEnds(analysis) {
            add(t: end.ts, title: "Wrist under",
                detail: end.stoppedS > 0
                    ? String(format: "straight-line · stopped %.0f s", end.stoppedS)
                    : "straight-line")
        }
        return out.sorted { $0.t < $1.t }
    }

    /// Positions for the counted turns, so the turns page can mark exactly the ones its
    /// filters kept.
    private static func buildTurnPins(_ analysis: SessionAnalysis,
                                      positioned: [RecordSample]) -> [TurnPin] {
        analysis.turns.enumerated().compactMap { index, turn in
            guard turn.counted, let sample = nearest(positioned, t: turn.ts),
                  let lat = sample.lat, let lon = sample.lon else { return nil }
            return TurnPin(id: index, t: turn.ts, lat: lat, lon: lon,
                           outcome: TurnOutcomeKind(turn.outcome))
        }
    }

    /// GP3S efforts, using the window provenance the engine already carries.
    ///
    /// Every record in `RecordWindowSelection.catalogue` gets one, not just the 2 s peak:
    /// the record cards are a picker, and a card whose effort was never built could not be
    /// tapped. A record the session did not produce is simply absent here, which is what
    /// makes its card inert.
    private static func buildEfforts(_ analysis: SessionAnalysis,
                                     positioned: [RecordSample]) -> [RecordEffort] {
        var out: [RecordEffort] = []
        for kind in RecordWindowSelection.catalogue {
            guard let kn = kind.value(in: analysis.records), kn > 0,
                  let window = analysis.records.windows[kind.rawValue] else { continue }
            let start = window.startTs
            let end = window.startTs + window.durS
            out.append(RecordEffort(id: kind.rawValue, label: effortLabel(kind), kn: kn,
                                    band: Band(id: out.count, start: start, end: end),
                                    points: points(positioned, from: start, to: end)))
        }
        return out
    }

    /// "Best 10 s" — the record's own name with the word the legend chip needs in front of
    /// it. The two composites already read as names and take no prefix.
    static func effortLabel(_ kind: RecordKind) -> String {
        switch kind {
        case .best5x10s, .alpha500: return kind.label
        default: return "Best \(kind.label)"
        }
    }

    /// The positioned track between two session-clock times.
    private static func points(_ positioned: [RecordSample], from start: Double,
                               to end: Double) -> [Point] {
        positioned
            .filter { $0.t >= start && $0.t <= end }
            .compactMap { s -> Point? in
                guard let lat = s.lat, let lon = s.lon else { return nil }
                return Point(lat: lat, lon: lon)
            }
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
