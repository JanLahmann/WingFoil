import Foundation

/// `GET /activities/{id}/streams?key_by_type=true` — parallel arrays, one per channel, all
/// on the same index.
///
/// Every channel is optional and every one is decoded tolerantly, because Strava returns
/// only the streams an activity actually has: a watch with no optical sensor sends no
/// `heartrate`, a barometerless one sends `altitude` anyway (interpolated from the terrain
/// model), and an activity Strava is still processing can send almost nothing.
public struct StravaStreams: Sendable, Codable, Equatable {

    public struct Channel<Element: Sendable & Codable & Equatable>: Sendable, Codable, Equatable {
        public var data: [Element]

        public init(data: [Element]) { self.data = data }
    }

    /// Seconds from the start of the activity. Strava's clock is *elapsed*, so a pause
    /// shows up as a jump — which is exactly the fact a `<trkseg>` boundary records.
    public var time: Channel<Double>?
    /// `[[lat, lon], …]`.
    public var latlng: Channel<[Double]>?
    public var altitude: Channel<Double>?
    public var heartrate: Channel<Double>?
    /// Strava's smoothed speed. Decoded so the fixture matches the wire, and then not used
    /// — see `StravaImport`.
    public var velocitySmooth: Channel<Double>?

    enum CodingKeys: String, CodingKey {
        case time, latlng, altitude, heartrate
        case velocitySmooth = "velocity_smooth"
    }

    public init(time: Channel<Double>? = nil, latlng: Channel<[Double]>? = nil,
                altitude: Channel<Double>? = nil, heartrate: Channel<Double>? = nil,
                velocitySmooth: Channel<Double>? = nil) {
        self.time = time
        self.latlng = latlng
        self.altitude = altitude
        self.heartrate = heartrate
        self.velocitySmooth = velocitySmooth
    }
}

/// One fix out of a Strava recording, as a value type with no HTTP in it.
public struct StravaSample: Sendable, Equatable {
    /// Seconds from the activity's start, as Strava's `time` stream states them.
    public var t: Double
    public var lat: Double
    public var lon: Double
    public var altitudeM: Double?
    public var heartRate: Double?

    public init(t: Double, lat: Double, lon: Double, altitudeM: Double? = nil,
                heartRate: Double? = nil) {
        self.t = t
        self.lat = lat
        self.lon = lon
        self.altitudeM = altitudeM
        self.heartRate = heartRate
    }
}

/// A Strava activity's streams, turned into the same `RawTrack` every other source produces
/// (docs/decisions.md ADR-023).
///
/// **Class (c) by construction, not by special case.** What Strava hands back is positions,
/// a clock, an elevation and — if the watch had one — a heart rate. That is, channel for
/// channel, exactly what a GPX holds, so this mapper *writes a GPX* and lets
/// `GpxSessionParser` do the rest. Nothing here decides the source class, marks a record
/// uncertified or derives a speed; all three fall out of the format, in the one place they
/// are already decided for every other positions-only source. A Strava session and a GPX of
/// the same afternoon therefore analyse to the same numbers, because after this function
/// they *are* the same file.
///
/// **Why not Strava's own speed.** `velocity_smooth` is fetched and thrown away on purpose.
/// It is not a Doppler channel: Strava computes it from the positions and then smooths it,
/// so calling it measured would be a claim the data cannot support — and carrying it beside
/// the engine's own positional derivation would put two differently-filtered answers in one
/// column, which is precisely the disagreement `GpxSessionParser`'s "two speed channels
/// agree" rule exists to prevent. The engine's own derivation is the number every class-(c)
/// source is measured on, and Strava is not an exception to it.
///
/// **What is missing, and stays missing.** No Doppler, so the speed records are marked
/// **uncertified** everywhere they appear. No accelerometer, so no pump strokes, no failed
/// takeoff attempts, no accelerometer-confirmed touchdowns. No developer fields, so no
/// watch summary and no divergence check. Every one of those absences is the same sentence
/// a GPX import already carries, and the rider reads it in the same words.
public enum StravaImport {

    public enum ImportError: Error, CustomStringConvertible, Equatable {
        case noPositions
        case noClock

        public var description: String {
            switch self {
            case .noPositions:
                "Strava kept no GPS positions for that activity"
            case .noClock:
                "Strava's recording has no time stream, so it cannot be placed on a clock"
            }
        }
    }

    /// A jump this long between consecutive fixes is the recorder having stopped, and starts
    /// a new `<trkseg>`.
    ///
    /// Same number and same argument as `HealthImport.gapThresholdS`: `TrackCleaner`'s dt
    /// rule (dt > max(3 s, 2 × median dt)) already catches most pauses and this never
    /// subtracts from it — the two are ORed. What the explicit break buys is the case the
    /// dt rule cannot see: Strava thins old recordings and serves some streams at 3–5 s per
    /// point, which raises the median and with it the threshold until a real pause stops
    /// looking unusual.
    public static let gapThresholdS: Double = 10

    // MARK: - Mapping

    /// The streams as usable fixes: sorted, de-duplicated on the clock, and stripped of
    /// anything that cannot be placed on a map or a timeline.
    ///
    /// The three refusals are `GpxSessionParser`'s and `HealthImport`'s, for the same
    /// reasons: a fix with no position is not a degraded sample but not a sample at all, a
    /// point with no time cannot be placed on the timeline every phase of the analysis is a
    /// function of, and two fixes at one instant divide by zero in every speed the engine
    /// derives.
    public static func samples(_ streams: StravaStreams) throws -> [StravaSample] {
        guard let clock = streams.time?.data, !clock.isEmpty else { throw ImportError.noClock }
        guard let points = streams.latlng?.data, !points.isEmpty else {
            throw ImportError.noPositions
        }
        let altitude = streams.altitude?.data
        let heart = streams.heartrate?.data
        let count = min(clock.count, points.count)

        var out: [StravaSample] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            let point = points[index]
            guard point.count >= 2 else { continue }
            let lat = point[0], lon = point[1]
            let t = clock[index]
            guard t.isFinite, lat.isFinite, lon.isFinite,
                  abs(lat) <= 90, abs(lon) <= 180,
                  !(lat == 0 && lon == 0) else { continue }
            out.append(StravaSample(t: t, lat: lat, lon: lon,
                                    altitudeM: reading(altitude, index),
                                    heartRate: heart.flatMap { series -> Double? in
                                        guard index < series.count else { return nil }
                                        let bpm = series[index]
                                        return bpm.isFinite && bpm > 0 ? bpm : nil
                                    }))
        }

        var seen = Set<Double>()
        let usable = out.sorted { $0.t < $1.t }.filter { seen.insert($0.t).inserted }
        guard !usable.isEmpty else { throw ImportError.noPositions }
        return usable
    }

    /// The bytes that get archived and re-analysed on an engine bump: a GPX 1.1 document.
    ///
    /// `utcOffsetS` is what *Strava* said the rider's clock was, and it is written into
    /// every timestamp as a numeric offset (`+02:00`) rather than as `Z`. That is not
    /// decoration: `GpxSessionParser` reads a stated offset as the exporter naming the local
    /// clock and hands it to the session as rung 1 of the offset ladder, where a `Z` would
    /// state an instant and nothing at all, leaving the longitude guess to answer. Strava
    /// knows the answer exactly, so it is written down exactly. nil falls back to `Z`, and
    /// to the guess, honestly.
    public static func gpx(activity: StravaActivity, samples: [StravaSample],
                           producer: String) throws -> Data {
        guard let start = activity.startDate else { throw ImportError.noClock }
        guard !samples.isEmpty else { throw ImportError.noPositions }
        let offsetS = activity.resolvedUtcOffsetS
        let stamp = TimestampWriter(offsetS: offsetS)

        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="\(escape(producer))"\
             xmlns="http://www.topografix.com/GPX/1/1"\
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
            <metadata><time>\(TimestampWriter(offsetS: 0).utc(start))</time></metadata>
            <trk><name>\(escape(activity.name ?? "Strava activity \(activity.id)"))</name>

            """
        if let sport = activity.sportType {
            xml += "<type>\(escape(sport))</type>\n"
        }

        var previous: Double?
        var open = false
        for sample in samples {
            let broke = previous.map { sample.t - $0 > gapThresholdS } ?? false
            if !open || broke {
                if open { xml += "</trkseg>\n" }
                xml += "<trkseg>\n"
                open = true
            }
            previous = sample.t
            xml += "<trkpt lat=\"\(coordinate(sample.lat))\" lon=\"\(coordinate(sample.lon))\">"
            if let altitude = sample.altitudeM, altitude.isFinite {
                xml += "<ele>\(number(altitude, places: 1))</ele>"
            }
            xml += "<time>\(stamp.local(start.addingTimeInterval(sample.t)))</time>"
            if let bpm = sample.heartRate {
                xml += "<extensions><gpxtpx:TrackPointExtension>"
                    + "<gpxtpx:hr>\(Int(bpm.rounded()))</gpxtpx:hr>"
                    + "</gpxtpx:TrackPointExtension></extensions>"
            }
            xml += "</trkpt>\n"
        }
        if open { xml += "</trkseg>\n" }
        xml += "</trk>\n</gpx>\n"
        return Data(xml.utf8)
    }

    /// Streams straight to archivable bytes — what the sync actually calls.
    public static func gpx(activity: StravaActivity, streams: StravaStreams,
                           producer: String) throws -> Data {
        try gpx(activity: activity, samples: samples(streams), producer: producer)
    }

    /// The mapper's own answer to "what session is this" — the pair the library dedupes on
    /// (docs/plan.md §3.3: start within ±60 s **and** duration within ±60 s).
    ///
    /// Taken from the *streams* rather than from Strava's `elapsed_time`, because that is
    /// what the ingested track's span will be: the same arithmetic the ingestor does, done
    /// before the download so the Import screen can mark a row "in your library" instead of
    /// spending a request to find out.
    public static func dedupeKey(activity: StravaActivity,
                                 samples: [StravaSample]) -> (start: Date, durationS: Double)? {
        guard let start = activity.startDate, let first = samples.first,
              let last = samples.last else { return nil }
        return (start.addingTimeInterval(first.t), last.t - first.t)
    }

    /// `<id>_<name-slug>_strava.gpx` — the same shape `IcuSyncService.filename` produces,
    /// so the library shows the activity's name rather than a bare Strava id.
    /// The slug keeps the activity's **own capitalisation** (`SessionNaming.activityNameSlug`):
    /// the filename is where a Strava name survives, and the title is derived back out of it.
    public static func filename(for activity: StravaActivity) -> String {
        "\(activity.id)_\(SessionNaming.activityNameSlug(activity.name))_strava.gpx"
    }

    /// The activity id back out of a stored row's `originalFilename`, or nil when that row
    /// did not come from Strava.
    ///
    /// **Why this is read back rather than stored in a column.** Strava's brand guidelines
    /// require an app that shows Strava data to link back to the activity on Strava, which
    /// needs the id on a session page (`StravaActivityLink`). The id was never lost: it is
    /// the first field of the name `filename(for:)` writes, and that name is kept verbatim on
    /// the row. A migration to add a `stravaActivityId` column would add a schema version,
    /// a backfill (which would read *this same filename* to fill it), and a nullable field
    /// every future reader has to reason about — to store a fact the row already carries.
    ///
    /// The `_strava.gpx` suffix is what makes it safe: it is written by exactly one function
    /// and no other door produces it, so a filename that ends in it came from this import and
    /// a filename that does not is not guessed at. A leading field that is not all digits is
    /// rejected for the same reason — a rider who renamed a file into that shape by hand gets
    /// no link rather than a link to somebody else's ride.
    public static func activityId(originalFilename: String?) -> String? {
        guard let name = originalFilename, name.hasSuffix("_strava.gpx"),
              let id = name.split(separator: "_").first, !id.isEmpty,
              id.allSatisfy(\.isNumber)
        else { return nil }
        return String(id)
    }

    // MARK: - Internals

    static func reading(_ series: [Double]?, _ index: Int) -> Double? {
        guard let series, index < series.count else { return nil }
        let value = series[index]
        return value.isFinite ? value : nil
    }

    /// Seven decimals — about a centimetre, and the precision every GPS exporter writes.
    static func coordinate(_ value: Double) -> String { number(value, places: 7) }

    /// Locale-independent by construction: `String(format:)` would follow the device's
    /// decimal separator, and a GPX with commas in its latitudes is not a GPX.
    static func number(_ value: Double, places: Int) -> String {
        let scale = pow(10.0, Double(places))
        let rounded = (value * scale).rounded() / scale
        var text = String(rounded)
        // `String(Double)` gives exponent form for very small magnitudes; a coordinate is
        // never one, but an altitude read as 1e-05 would be, and `<ele>1e-05</ele>` parses
        // as nothing.
        if text.contains("e") || text.contains("E") { text = "0" }
        return text
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// ISO 8601 with a *stated* numeric offset, built by hand.
    ///
    /// Hand-built rather than handed to a `DateFormatter` for the reason
    /// `GpxSessionParser.parseTime` gives for reading them the same way: the formatters are
    /// reference types that cannot cross a concurrency domain, one per point would cost more
    /// than the whole mapping, and the calendar arithmetic here is exactly specified.
    struct TimestampWriter {
        let offsetS: Int?

        func local(_ date: Date) -> String {
            guard let offsetS else { return utc(date) }
            let sign = offsetS < 0 ? "-" : "+"
            let magnitude = abs(offsetS)
            let suffix = String(format: "%@%02d:%02d", sign, magnitude / 3600,
                                (magnitude % 3600) / 60)
            return civil(date.timeIntervalSince1970 + Double(offsetS)) + suffix
        }

        func utc(_ date: Date) -> String {
            civil(date.timeIntervalSince1970) + "Z"
        }

        /// `yyyy-MM-ddTHH:mm:ss` for an epoch already shifted onto the wanted clock.
        private func civil(_ epoch: Double) -> String {
            let whole = Int(epoch.rounded(.down))
            var days = whole / 86_400
            var rest = whole % 86_400
            if rest < 0 { rest += 86_400; days -= 1 }
            let (y, m, d) = civilFromDays(days)
            return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", y, m, d,
                          rest / 3600, (rest % 3600) / 60, rest % 60)
        }

        /// The inverse of `GpxSessionParser.daysFromCivil` — Howard Hinnant's
        /// `civil_from_days`, which is what makes this independent of any calendar object,
        /// locale or device setting.
        private func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
            let z = z0 + 719_468
            let era = (z >= 0 ? z : z - 146_096) / 146_097
            let doe = z - era * 146_097                                   // [0, 146096]
            let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
            let y = yoe + era * 400
            let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)             // [0, 365]
            let mp = (5 * doy + 2) / 153                                  // [0, 11]
            let d = doy - (153 * mp + 2) / 5 + 1                          // [1, 31]
            let m = mp + (mp < 10 ? 3 : -9)                               // [1, 12]
            return (y + (m <= 2 ? 1 : 0), m, d)
        }
    }
}
