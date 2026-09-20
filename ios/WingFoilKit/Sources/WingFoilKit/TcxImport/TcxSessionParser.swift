import Foundation

/// Parses a TCX v2 (Garmin Training Center Database) track into a `RawTrack`.
///
/// Mirrors `lab/src/wingfoil_lab/tcx.py`, which is the authoritative reference; the goldens
/// `fixtures/goldens/2026-08-30-1407_nago-torbole-{speed,nospeed}.expected.json` are where
/// the two are held to the same numbers. Foundation's `XMLParser` does the reading, exactly
/// as it does for GPX, so this costs the app no dependency at all.
///
/// **A TCX is not one input class.** It carries positions and a clock like a GPX, and it
/// *may* also carry the receiver's own speed in Garmin's per-point `TPX` extension
/// (`Extensions/TPX/Speed`, m/s). Polar, Suunto and Coros all reach CleanJibe as TCX through
/// intervals.icu, and that one element decides what the analysis is allowed to claim:
///
/// * **`TPX/Speed` present ⇒ class (b)**, exactly like a native FIT. The number was measured
///   by the receiver, `SourceCapabilities.hasSpeed` is **true**, and the speed records are
///   certified.
/// * **`TPX/Speed` absent ⇒ class (c)**, exactly like a GPX. Speed is differentiated from
///   positions with `GpxSessionParser.segmentSpeed` — deliberately the same arithmetic, so
///   the two XML doors can never disagree about the same metres — `hasSpeed` stays **false**,
///   and every surface marks those speed records uncertified.
///
/// **Segments.** TCX nests `Activity > Lap > Track > Trackpoint`, and the two container
/// levels mean different things. A `<Lap>` is a *marker* — the rider pressed lap — and the
/// board kept moving through it, so a lap boundary is **not** a gap. A second `<Track>` is
/// the recorder having stopped and started again, which is what a GPX `<trkseg>` boundary
/// says, so that is the join marked `RecordSample.gapBefore`.
///
/// **Sport.** `Activity/@Sport` is not read into `capabilities.sport`: the TCX schema admits
/// only `Running`, `Biking` and `Other`, so every watersport session is `Other`, and filing
/// that as the sport would turn "this file cannot say" into a claim a watersport gate would
/// then act on.
///
/// **Time zone.** `<Time>` is ISO 8601 and usually `Z`, which states an instant and nothing
/// about the rider's clock; the longitude rung of the ladder then answers
/// (`SessionIngestor.resolveUtcOffset`). A numeric offset is the exporter naming the local
/// clock, and wins. The scanner is `GpxSessionParser.parseTime`, shared for the same reason
/// the speed arithmetic is.
///
/// Fail-soft like both parsers beside it: a `Trackpoint` with no time or no position is
/// skipped; a malformed number is dropped rather than thrown on.
public enum TcxSessionParser {

    public enum ParseError: Error {
        case unreadable(URL)
        case malformed
        case noRecords
    }

    public static func parse(url: URL) throws -> RawTrack {
        guard let data = try? Data(contentsOf: url) else { throw ParseError.unreadable(url) }
        var track = try parse(data: data)
        track.sourceURL = url
        return track
    }

    public static func parse(data: Data) throws -> RawTrack {
        let collector = Collector()
        // The same hardened door the GPX parser uses, and for the same reason: a TCX is a
        // file from a stranger, and a `<!DOCTYPE>` subset in one is refused rather than
        // expanded (see SafeXML.swift).
        let parser = SafeXML.parser(data: data, delegate: collector)
        guard parser.parse() else { throw ParseError.malformed }
        guard !collector.segments.isEmpty else { throw ParseError.noRecords }
        return build(collector)
    }

    /// Cheap content sniff: does this blob look like TCX rather than GPX or FIT?
    ///
    /// Byte-level rather than extension-level, for the reason `GpxSessionParser.isGpx` is:
    /// the callers that matter — a dropped file, an intervals.icu original, a ZIP member —
    /// all have bytes and only sometimes have a trustworthy name. Mirrors `tcx.is_tcx`.
    public static func isTcx(_ data: Data) -> Bool {
        let head = data.prefix(512).drop { $0 == 0xEF || $0 == 0xBB || $0 == 0xBF
            || $0 == 0x20 || $0 == 0x09 || $0 == 0x0D || $0 == 0x0A }
        guard head.first == UInt8(ascii: "<") else { return false }
        let window = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        return window.contains("<trainingcenterdatabase")
    }

    // MARK: - Assembly

    private static func build(_ c: Collector) -> RawTrack {
        var track = RawTrack()
        let points = c.segments.flatMap { $0 }
        guard let first = points.first else { return track }

        track.startDate = first.time
        var caps = SourceCapabilities()
        // THE rule of this parser: the capability is a question about the *file*. A stated
        // `TPX/Speed` anywhere is a measured channel and makes the session class (b);
        // without one the speeds below are differentiated from positions exactly as a GPX's
        // are, and the session is class (c) with its records marked uncertified.
        caps.hasSpeed = points.contains { $0.speed != nil }
        caps.hasPosition = true
        caps.hasHR = points.contains { $0.hr != nil }
        caps.hasWatchLaps = c.laps.count > 1

        // The projection every derived speed is measured in — the centroid of the whole
        // track, exactly as `GpxSessionParser` and `TrackCleaner` pick their origin.
        let lat0 = points.map(\.lat).reduce(0, +) / Double(points.count)
        let lon0 = points.map(\.lon).reduce(0, +) / Double(points.count)
        let cosLat0 = cos(lat0 * .pi / 180)

        var samples: [RecordSample] = []
        samples.reserveCapacity(points.count)
        for (index, segment) in c.segments.enumerated() {
            let ts = segment.map { $0.time.timeIntervalSince(first.time) }
            var derived: [Double?] = Array(repeating: nil, count: segment.count)
            if !caps.hasSpeed {
                let xs = segment.map { ($0.lon - lon0) * cosLat0 * 111_320 }
                let ys = segment.map { ($0.lat - lat0) * 110_540 }
                derived = GpxSessionParser.segmentSpeed(t: ts, x: xs, y: ys)
            }
            for (i, point) in segment.enumerated() {
                var s = RecordSample(t: ts[i], timestamp: point.time)
                s.lat = point.lat
                s.lon = point.lon
                s.altitudeM = point.ele
                s.heartRate = point.hr
                // A stated speed is carried through untouched; a file that states none has
                // its positions differentiated. Never both, and never a blend of the two.
                s.speedMps = caps.hasSpeed ? point.speed : derived[i]
                s.gapBefore = index > 0 && i == 0   // a second <Track>: two recordings
                samples.append(s)
            }
        }
        track.samples = samples
        track.laps = c.laps

        if samples.count > 1 {
            let dts = (1..<samples.count).map { samples[$0].t - samples[$0 - 1].t }
            let med = median(dts)
            caps.sampleRateHz = med > 0 ? (1 / med * 1000).rounded() / 1000 : 0
        }
        track.capabilities = caps
        track.startUtcOffsetS = c.statedOffsets.first
        track.startUtcOffsetSource = track.startUtcOffsetS == nil ? nil : .activity
        return track
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    // MARK: - Reading

    fileprivate struct Point {
        var lat: Double
        var lon: Double
        var time: Date
        var ele: Double?
        var hr: Double?
        /// `Extensions/TPX/Speed` in m/s, when the file stated one.
        var speed: Double?
    }

    /// The `XMLParser` delegate. TCX is deeper than GPX but just as regular, so the same
    /// flat state machine works — with one extra piece of bookkeeping, because `<Value>`
    /// means "heart rate" only inside `<HeartRateBpm>` and TCX reuses the tag elsewhere.
    private final class Collector: SafeXMLCollector {
        /// Only the **first** `<Activity>` is kept: several activities in one file are
        /// several sessions, not several segments of one.
        var activityCount = 0
        var segments: [[Point]] = []
        var laps: [LapInfo] = []
        /// Every UTC offset a `<Time>` *stated* (a `Z` states none). The first wins: the
        /// clock a session is read on is the one it started on.
        var statedOffsets: [Int] = []

        private var current: [Point] = []
        private var lat: Double?
        private var lon: Double?
        private var time: Date?
        private var ele: Double?
        private var hr: Double?
        private var speed: Double?
        private var inPoint = false
        private var inHeartRate = false
        private var lapStart: Date?
        private var lapTotalS: Double?
        private var lapDistanceM: Double?
        private var text = ""
        private var seen = Set<Date>()

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String]) {
            text = ""
            switch name.lowercased() {
            case "activity":
                activityCount += 1
            case "lap":
                guard activityCount == 1 else { return }
                lapStart = attributes["StartTime"].flatMap {
                    GpxSessionParser.parseTime($0)?.0
                }
                lapTotalS = nil
                lapDistanceM = nil
            case "track":
                guard activityCount == 1 else { return }
                current = []
                // Per-`<Track>`, as the lab dedupes per-track: two points on the same second
                // inside one recording are one point written twice, but the same instant
                // either side of a stop is two recordings that happen to abut.
                seen = []
            case "trackpoint":
                guard activityCount == 1 else { return }
                inPoint = true
                lat = nil
                lon = nil
                time = nil
                ele = nil
                hr = nil
                speed = nil
            case "heartratebpm":
                inHeartRate = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            guard activityCount == 1 else {
                if name.lowercased() == "heartratebpm" { inHeartRate = false }
                return
            }
            switch name.lowercased() {
            case "latitudedegrees" where inPoint:
                lat = Double(trimmed)
            case "longitudedegrees" where inPoint:
                lon = Double(trimmed)
            case "altitudemeters" where inPoint:
                ele = Double(trimmed)
            case "value":
                // `<Value>` is heart rate only inside `<HeartRateBpm>`; TCX uses the same
                // tag for a lap's average and maximum, which are not per-sample facts.
                if inPoint, inHeartRate, let v = Double(trimmed) { hr = v }
            case "heartratebpm":
                inHeartRate = false
            case "speed" where inPoint:
                // The one element that decides the source class. A negative number is not a
                // measurement of anything, so it leaves the file having stated nothing.
                if let v = Double(trimmed), v >= 0 { speed = v }
            case "time" where inPoint:
                if let (date, stated) = GpxSessionParser.parseTime(trimmed) {
                    time = date
                    if let stated { statedOffsets.append(stated) }
                }
            case "totaltimeseconds":
                lapTotalS = Double(trimmed)
            case "distancemeters" where !inPoint:
                lapDistanceM = Double(trimmed)
            case "trackpoint":
                inPoint = false
                // No clock, no timeline; no position, no track. A TCX written by a treadmill
                // is the second case, whole.
                guard let lat, let lon, let time, !seen.contains(time) else { return }
                seen.insert(time)
                current.append(Point(lat: lat, lon: lon, time: time, ele: ele, hr: hr,
                                     speed: speed))
            case "track":
                if !current.isEmpty { segments.append(current.sorted { $0.time < $1.time }) }
                current = []
            case "lap":
                // Carried for its count (`hasWatchLaps`) and for what the file states about
                // it; nothing here is derived, because a computed lap would be a number the
                // recording never contained.
                var lap = LapInfo(startT: 0)
                lap.totalTimeS = lapTotalS
                lap.distanceM = lapDistanceM
                if let lapStart, let first = segments.first?.first?.time {
                    lap.startT = lapStart.timeIntervalSince(first)
                }
                laps.append(lap)
                lapStart = nil
            default:
                break
            }
        }
    }
}
