import Foundation

/// Turns a `.cjr` direct stream (docs/transfer-format.md) into a `RawTrack`.
///
/// The fifth door, and deliberately a door rather than a special case: `TrackParser` sniffs
/// the magic, this produces the same `RawTrack` + `SourceCapabilities` everything downstream
/// already reads, and nothing past this file knows that a session arrived over Bluetooth
/// instead of through an account (docs/plan.md §3.3 — the pipeline degrades on capabilities,
/// not on formats).
///
/// **Source class.** The stream carries the receiver's own Doppler channel, the positions and
/// the four record developer fields of docs/fit-schema.md, so `SourceCapabilities.sourceClass`
/// answers `"a"` — the same letter the FIT of the same afternoon gets, because it is the same
/// watch app writing the same four fields. No letter is invented here (pattern L). What it
/// does *not* carry is the wrist stream, which is dev3's (`hasAccel` false) — and that is
/// already the ordinary shape of a class-(a) recording, because `accelLogging` is off by
/// default on the watch.
public enum DirectStreamParser {

    public enum ParseError: Error, CustomStringConvertible {
        case noRecords

        public var description: String {
            switch self {
            case .noRecords: "the direct stream contains no position fixes"
            }
        }
    }

    public static func parse(data: Data) throws -> RawTrack {
        let (header, records) = try DirectStreamDecoder.decode(data)
        return try build(header: header, records: records)
    }

    public static func parse(url: URL) throws -> RawTrack {
        guard let data = try? Data(contentsOf: url) else {
            throw FitSessionParser.ParseError.unreadable(url)
        }
        var track = try parse(data: data)
        track.sourceURL = url
        return track
    }

    // MARK: - Assembly

    static func build(header: DirectStreamHeader, records: [DirectRecord]) throws -> RawTrack {
        guard let first = records.first else { throw ParseError.noRecords }

        var track = RawTrack()
        // The header's start is the card's `KEY_START`, which is half of the ±60 s dedupe
        // key (ADR-013) — so the direct session and the card claim the same afternoon by
        // construction. `min` is the belt to that brace: a header whose start somehow sits
        // after its own first fix would otherwise give every sample a negative `t`.
        let base = min(header.startEpochS, first.t)
        track.startDate = Date(timeIntervalSince1970: Double(base))

        var samples: [RecordSample] = []
        samples.reserveCapacity(records.count)
        var distance: Double = 0
        var previous: (lat: Double, lon: Double)?

        for record in records {
            var s = RecordSample(t: Double(record.t - base),
                                 timestamp: Date(timeIntervalSince1970: Double(record.t)))
            s.lat = record.lat
            s.lon = record.lon
            s.speedMps = Double(record.speedCms) / 100
            s.altitudeM = record.altitudeM.map(Double.init)
            // 0 is the wire's "no reading" and must never reach the engine as a heart rate:
            // a 0 bpm sample in an HR cost curve is a real number to the arithmetic and a
            // nonsense one to the rider.
            s.heartRate = record.heartRate > 0 ? Double(record.heartRate) : nil
            s.foilState = record.foilState
            s.pumpCadence = record.pumpCadence
            s.turnMarker = record.turnMarker
            s.tick = record.tick
            // The watch sends no odometer, so the column is filled here with the same
            // great-circle arithmetic the engine would use. Accumulated rather than left
            // nil because a FIT from the same afternoon carries one, and a direct session
            // that silently lacked the column would read as a different kind of recording.
            if let previous {
                distance += Self.haversineM(previous.lat, previous.lon, record.lat, record.lon)
            }
            s.distanceM = distance
            previous = (record.lat, record.lon)
            samples.append(s)
        }
        track.samples = samples

        // The wind axis the rider entered, in the field the FIT parser puts `wind_dir_user`
        // in — so `WindEstimator` and the turn namer read one channel whichever door the
        // session came through. The watch's own estimate (`wind_dir_auto`) is not on the
        // wire: it is a session field, and the stream carries records.
        track.watchSummary.windDirUserDeg = header.windDirDeg >= 0 && header.windDirDeg <= 359
            ? Double(header.windDirDeg) : nil
        track.watchSummary.discipline = Self.discipline(header.discipline)
        track.watchSummary.appVersion = header.appVersion

        var caps = SourceCapabilities()
        // Every claim below is checked against what actually arrived rather than against
        // what the format promises.
        caps.hasPosition = true
        caps.hasSpeed = samples.contains { ($0.speedMps ?? 0) > 0 }
        caps.hasHR = samples.contains { $0.heartRate != nil }
        // The four record developer fields are columns of `rec.v1`, written by the same
        // detectors that write them into the FIT. They are there in every record of every
        // stream this app will ever decode.
        caps.hasDevFields = true
        // The wrist magnitudes are stream 1, which is dev3's (docs/transfer-format.md §6).
        caps.hasAccel = false
        // No lap messages on the wire. The FIT's laps are hints the phone re-derives anyway
        // (docs/fit-schema.md, "watch lap boundaries are hints"), and `hasWatchLaps` is
        // `laps.count > 1` there — so no laps means the flag is false and the engine
        // segments the flights itself, exactly as it does for a one-lap FIT.
        caps.hasWatchLaps = false
        // One fix a second, which is what the watch records and what the format prices at
        // 9 bytes a second. Stated rather than measured: a pause in the middle of a session
        // is a pause, not a lower rate.
        caps.sampleRateHz = 1
        caps.discipline = Self.discipline(header.discipline)
        caps.sport = caps.discipline
        track.capabilities = caps

        // Rung 1 of the offset ladder is not available: the stream carries UTC seconds and
        // no local clock. `SessionIngestor.resolveUtcOffset` therefore falls through to the
        // longitude rung, and the row records that it was a guess.
        return track
    }

    /// The discipline tag for a wire code. `0` is wingfoil, the only value 0.9.x writes;
    /// anything else is a watch newer than this build and says nothing rather than guessing.
    static func discipline(_ code: Int) -> String? {
        code == 0 ? Discipline.wingfoil.rawValue : nil
    }

    /// Great-circle metres between two fixes. The same spherical earth the engine's own
    /// projection uses, so the column and the analysis cannot disagree by a model.
    static func haversineM(_ lat1: Double, _ lon1: Double,
                           _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}
