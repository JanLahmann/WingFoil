import Foundation

/// Parses a GPX 1.1 track into a `RawTrack` — docs/plan.md's **input class (c)**.
///
/// Mirrors `lab/src/wingfoil_lab/gpx.py`, which is the authoritative reference; the golden
/// `fixtures/goldens/2026-08-30-1407_nago-torbole.expected.json` is where the two are held
/// to the same numbers. Foundation's `XMLParser` does the reading, so this costs the app no
/// dependency at all.
///
/// Three absences define the source class, and each is recorded as a fact rather than
/// papered over:
///
/// * **No Doppler.** No GPX carries a speed channel. Speed here is *differentiated from
///   positions*, which is systematically noisier and can read high on a bad fix, so
///   `SourceCapabilities.hasSpeed` stays **false** even though every `RecordSample` has a
///   `speedMps`. That is not a contradiction: the field says the analysis has a number to
///   work with, the capability says the file could not prove it was measured. `hasSpeed`
///   is what drives `sourceClass` → `"c"`, and class (c) is what `LibraryQueries
///   .certified`, `ShareCard` and `SessionDisplay.sourceClassNote` read to mark these
///   speed records **uncertified**.
/// * **No accelerometer.** So no pump strokes, no failed takeoff attempts, no
///   accelerometer-confirmed touchdowns — `PumpTrack` and `TakeoffAnalyzer` already
///   degrade on a track with an empty `accel`, and nothing new is needed here.
/// * **No developer fields.** Nothing of ours ever reached a GPX, so there is no watch
///   summary to diverge from and no discipline tag to read.
///
/// **Speed derivation.** Positions are projected with the same local-meter projection
/// `TrackCleaner` uses (equirectangular about the mean latitude) and central-differenced
/// inside each contiguous run — deliberately the arithmetic that produces
/// `CleanSample.positionalMps`, so a GPX session's two speed channels agree rather than
/// disagreeing about the same metres.
///
/// **Segments.** A `<trkseg>` boundary is the recorder saying it stopped: the two sides are
/// not one motion, and a speed differentiated across the join would be a fiction. Each
/// segment is differentiated on its own and the join is marked `RecordSample.gapBefore`,
/// which `TrackCleaner` ORs into its dt-aware gap rule — so the break survives even when
/// the clock is continuous across it, the one case the dt rule alone cannot see.
///
/// **Time zone.** GPX timestamps are usually `Z`, which states an *instant* and nothing at
/// all about the rider's clock, so it yields no offset and the longitude rung of the 0.8.2
/// ladder takes over (`SessionIngestor.resolveUtcOffsetS`). A timestamp written with a
/// numeric offset (`+02:00`) *is* the exporter naming the local clock, and wins.
///
/// Fail-soft like the FIT parser: a `trkpt` with no time cannot be placed on the timeline
/// and is skipped; a malformed number is dropped rather than thrown on.
public enum GpxSessionParser {

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
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = true      // local names only: GPX 1.0/1.1, any prefix
        guard parser.parse() else { throw ParseError.malformed }
        guard !collector.segments.isEmpty else { throw ParseError.noRecords }
        return build(collector)
    }

    /// Cheap content sniff: does this blob look like GPX rather than FIT?
    ///
    /// Byte-level rather than extension-level, because the callers that matter — a dropped
    /// file, an archived original, a ZIP member — all have bytes and only sometimes have a
    /// trustworthy name. Mirrors `gpx.is_gpx` in the lab.
    public static func isGpx(_ data: Data) -> Bool {
        let head = data.prefix(512).drop { $0 == 0xEF || $0 == 0xBB || $0 == 0xBF
            || $0 == 0x20 || $0 == 0x09 || $0 == 0x0D || $0 == 0x0A }
        guard head.first == UInt8(ascii: "<") else { return false }
        let window = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        return window.contains("<gpx")
    }

    // MARK: - Assembly

    private static func build(_ c: Collector) -> RawTrack {
        var track = RawTrack()
        let points = c.segments.flatMap { $0 }
        guard let first = points.first else { return track }

        track.startDate = first.time
        var caps = SourceCapabilities()
        // hasSpeed stays false: the speeds below are *derived*, and the capability is the
        // file's claim, not the analysis's. This is what makes the session class (c).
        caps.hasSpeed = false
        caps.hasPosition = true
        caps.hasHR = points.contains { $0.hr != nil }

        // The projection every derived speed is measured in — the centroid of the whole
        // track, exactly as `TrackCleaner` picks its origin.
        let lat0 = points.map(\.lat).reduce(0, +) / Double(points.count)
        let lon0 = points.map(\.lon).reduce(0, +) / Double(points.count)
        let cosLat0 = cos(lat0 * .pi / 180)

        var samples: [RecordSample] = []
        samples.reserveCapacity(points.count)
        for (index, segment) in c.segments.enumerated() {
            let xs = segment.map { ($0.lon - lon0) * cosLat0 * 111_320 }
            let ys = segment.map { ($0.lat - lat0) * 110_540 }
            let ts = segment.map { $0.time.timeIntervalSince(first.time) }
            let speeds = segmentSpeed(t: ts, x: xs, y: ys)
            for (i, point) in segment.enumerated() {
                var s = RecordSample(t: ts[i], timestamp: point.time)
                s.lat = point.lat
                s.lon = point.lon
                s.altitudeM = point.ele
                s.heartRate = point.hr
                s.speedMps = speeds[i]
                s.gapBefore = index > 0 && i == 0     // the join: two recordings, not one motion
                samples.append(s)
            }
        }
        track.samples = samples

        if samples.count > 1 {
            let dts = (1..<samples.count).map { samples[$0].t - samples[$0 - 1].t }
            let med = median(dts)
            caps.sampleRateHz = med > 0 ? (1 / med * 1000).rounded() / 1000 : 0
        }
        track.capabilities = caps
        track.startUtcOffsetS = c.statedOffsets.first
        return track
    }

    /// Central difference inside one contiguous run, one-sided at its two ends.
    ///
    /// The arithmetic of `TrackCleaner.planarSpeed`, on purpose: this channel *becomes*
    /// `dopplerMps`, and a GPX whose two speed channels disagreed would have the maneuver
    /// detector and the record windows reading different sessions. A repeated instant
    /// divides by zero, so a non-finite result becomes nil and the row is dropped by the
    /// cleaner exactly as a missing speed is.
    private static func segmentSpeed(t: [Double], x: [Double], y: [Double]) -> [Double?] {
        let n = t.count
        guard n >= 2 else { return Array(repeating: nil, count: n) }
        var out = [Double?](repeating: nil, count: n)
        func step(_ a: Int, _ b: Int) -> Double? {
            let span = t[b] - t[a]
            guard span > 0 else { return nil }
            let v = hypot(x[b] - x[a], y[b] - y[a]) / span
            return v.isFinite ? v : nil
        }
        out[0] = step(0, 1)
        out[n - 1] = step(n - 2, n - 1)
        if n >= 3 {
            for i in 1..<(n - 1) { out[i] = step(i - 1, i + 1) }
        }
        return out
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
    }

    /// The `XMLParser` delegate. GPX is small and shallow, so a flat state machine over the
    /// four elements that matter beats any general-purpose tree.
    private final class Collector: NSObject, XMLParserDelegate {
        /// Only the **first** `<trk>` is kept: several tracks in one file are several
        /// activities, not several segments of one.
        var trackCount = 0
        var segments: [[Point]] = []
        /// Every UTC offset a timestamp *stated* (a `Z` states none). The first wins:
        /// the clock a session is read on is the one it started on.
        var statedOffsets: [Int] = []

        private var current: [Point] = []
        private var lat: Double?
        private var lon: Double?
        private var time: Date?
        private var ele: Double?
        private var hr: Double?
        private var inPoint = false
        private var text = ""
        private var seen = Set<Date>()

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String]) {
            text = ""
            switch name.lowercased() {
            case "trk":
                trackCount += 1
            case "trkseg":
                guard trackCount == 1 else { return }
                current = []
            case "trkpt":
                guard trackCount == 1 else { return }
                inPoint = true
                lat = Double(attributes["lat"] ?? "")
                lon = Double(attributes["lon"] ?? "")
                time = nil
                ele = nil
                hr = nil
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
            guard trackCount == 1 else { return }
            switch name.lowercased() {
            case "ele" where inPoint:
                ele = Double(trimmed)
            case "hr", "heartrate":
                if inPoint, let v = Double(trimmed) { hr = v }
            case "time" where inPoint:
                if let (date, stated) = GpxSessionParser.parseTime(trimmed) {
                    time = date
                    if let stated { statedOffsets.append(stated) }
                }
            case "trkpt":
                inPoint = false
                // No clock, no timeline: every phase of the analysis is a function of time,
                // so a point that cannot say when it happened is not a degraded sample —
                // it is not a sample. (A waypoint-only GPX is exactly this, whole.)
                guard let lat, let lon, let time, !seen.contains(time) else { return }
                seen.insert(time)
                current.append(Point(lat: lat, lon: lon, time: time, ele: ele, hr: hr))
            case "trkseg":
                if !current.isEmpty { segments.append(current.sorted { $0.time < $1.time }) }
                current = []
            default:
                break
            }
        }
    }

    /// `<time>` → (instant, the local UTC offset the file *stated*, or nil).
    ///
    /// `Z` is an instant; `+00:00` spelled out is a clock that happens to be UTC. The
    /// difference is what the exporter was willing to say, and the ladder honours it.
    /// A timestamp with no zone designator is UTC by the GPX schema, and states no clock.
    ///
    /// Hand-scanned rather than handed to a `DateFormatter`: the formatters are reference
    /// types and cannot be shared across a concurrency domain, a fresh one per point would
    /// cost more than the parse, and ISO 8601's calendar arithmetic is exactly specified.
    /// Anything that does not match the shape returns nil, and the point is skipped.
    static func parseTime(_ raw: String) -> (Date, Int?)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 19 else { return nil }
        let chars = Array(text)
        guard chars[4] == "-", chars[7] == "-", chars[10] == "T" || chars[10] == " ",
              chars[13] == ":", chars[16] == ":",
              let year = Int(String(chars[0..<4])),
              let month = Int(String(chars[5..<7])),
              let day = Int(String(chars[8..<10])),
              let hour = Int(String(chars[11..<13])),
              let minute = Int(String(chars[14..<16])),
              let second = Double(String(chars[17..<19]))
        else { return nil }

        var stated: Int?
        var offset = 0
        let zone = chars[19...]
        if let last = zone.last, last == "Z" || last == "z" {
            offset = 0                                  // an instant, and no claim of a clock
        } else if let signIndex = zone.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            let body = String(zone[zone.index(after: signIndex)...])
                .replacingOccurrences(of: ":", with: "")
            guard body.count == 4, let hh = Int(body.prefix(2)), let mm = Int(body.suffix(2))
            else { return nil }
            offset = (zone[signIndex] == "-" ? -1 : 1) * (hh * 3600 + mm * 60)
            stated = offset
        }
        // Fractional seconds, when the exporter wrote any. Never a zone designator: the
        // scan above already consumed whatever followed the whole seconds.
        if zone.first == ".", let dot = text.range(of: ".") {
            let digits = text[dot.upperBound...].prefix { $0.isNumber }
            if let frac = Double("0.\(digits)") { return (date(year, month, day, hour, minute,
                                                              second + frac, offset), stated) }
        }
        return (date(year, month, day, hour, minute, second, offset), stated)
    }

    /// Civil date + time of day − UTC offset → an instant.
    ///
    /// `daysFromCivil` is the standard proleptic-Gregorian day count (Howard Hinnant's),
    /// which is what makes this independent of any calendar object, any locale and any
    /// device setting — the three things a session's clock must never depend on.
    private static func date(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int,
                             _ ss: Double, _ offsetS: Int) -> Date {
        let days = daysFromCivil(y, m, d)
        let seconds = Double(days * 86_400 + hh * 3600 + mm * 60 - offsetS) + ss
        return Date(timeIntervalSince1970: seconds)
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date.
    private static func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let y = y - (m <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                   // [0, 399]
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1  // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy           // [0, 146096]
        return era * 146_097 + doe - 719_468
    }
}
