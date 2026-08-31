import Foundation
import FitFileParser

/// Parses a FIT activity file into a `RawTrack`. Fail-soft: missing channels reduce
/// `SourceCapabilities`, they never throw. Developer-field names per docs/fit-schema.md.
public enum FitSessionParser {

    public enum ParseError: Error {
        case unreadable(URL)
        case noRecords
    }

    /// FIT global message numbers we look at by number rather than by FitFileParser's enum.
    private enum Mesg {
        static let record: UInt16 = 20
        static let lap: UInt16 = 19
        static let session: UInt16 = 18
        /// Read for one field only: `local_timestamp`. See `utcOffsetS`.
        static let activity: UInt16 = 34
        static let accelerometerData: UInt16 = 165
        static let threeDSensorCalibration: UInt16 = 167
    }

    /// Record-level developer fields whose presence marks source class (a). Mirrors
    /// `DEV_RECORD_FIELDS` in lab/src/wingfoil_lab/parse.py — Python is the reference for
    /// classification.
    private static let devRecordFields: Set<String> =
        ["foil_state", "flight_index", "pump_cadence", "turn_marker", "tick"]

    public static func parse(url: URL) throws -> RawTrack {
        guard let data = try? Data(contentsOf: url) else { throw ParseError.unreadable(url) }
        var track = try parse(data: data)
        track.sourceURL = url
        return track
    }

    public static func parse(data: Data) throws -> RawTrack {
        // FitFileParser's C decoder overflows its 254-byte message buffer on any definition
        // larger than that (our CIQ files log 356-byte `accelerometer_data`), which silently
        // corrupts the record stream and can segfault — see FitStreamSanitizer.
        let sanitized = FitStreamSanitizer.sanitize(data)
        let fit = FitFile(data: sanitized.data, parsingType: .generic)
        // …and it cannot decode developer fields at all in this mode, so we read those
        // straight from the (sanitized, hence index-aligned) bytes — see
        // FitDeveloperFieldReader.
        let dev = FitDeveloperFieldReader.read(sanitized.data)
        var track = RawTrack()

        let records = fit.messages(forMessageType: .record)
        guard !records.isEmpty else { throw ParseError.noRecords }

        let devRecords = alignedDevFields(dev, Mesg.record, count: records.count)
        var start: Date?
        for (index, message) in records.enumerated() {
            guard let ts = message.interpretedField(key: "timestamp")?.time else { continue }
            if start == nil { start = ts }
            var sample = RecordSample(t: ts.timeIntervalSince(start!), timestamp: ts)

            if let coord = message.interpretedField(key: "position")?.coordinate {
                sample.lat = coord.latitude
                sample.lon = coord.longitude
            }
            let speed = message.interpretedField(key: "enhanced_speed")?.valueUnit?.value
                ?? message.interpretedField(key: "speed")?.valueUnit?.value
            sample.speedMps = speed
            sample.heartRate = message.interpretedField(key: "heart_rate")?.valueUnit?.value
            sample.distanceM = message.interpretedField(key: "distance")?.valueUnit?.value
            sample.altitudeM = message.interpretedField(key: "enhanced_altitude")?.valueUnit?.value
                ?? message.interpretedField(key: "altitude")?.valueUnit?.value

            let d = devRecords[index]                       // docs/fit-schema.md record 0–4
            sample.foilState = d["foil_state"]?.int
            sample.flightIndex = d["flight_index"]?.int
            sample.pumpCadence = d["pump_cadence"]?.int
            sample.turnMarker = d["turn_marker"]?.int
            sample.tick = d["tick"]?.int
            track.samples.append(sample)
        }
        track.startDate = start

        let laps = fit.messages(forMessageType: .lap)
        let devLaps = alignedDevFields(dev, Mesg.lap, count: laps.count)
        for (index, message) in laps.enumerated() {
            guard let ts = message.interpretedField(key: "start_time")?.time
                ?? message.interpretedField(key: "timestamp")?.time,
                let s = start else { continue }
            var lap = LapInfo(startT: ts.timeIntervalSince(s))
            lap.totalTimeS = message.interpretedField(key: "total_timer_time")?.valueUnit?.value
            lap.distanceM = message.interpretedField(key: "total_distance")?.valueUnit?.value
            lap.maxSpeedMps = message.interpretedField(key: "enhanced_max_speed")?.valueUnit?.value
                ?? message.interpretedField(key: "max_speed")?.valueUnit?.value
            lap.avgSpeedMps = message.interpretedField(key: "enhanced_avg_speed")?.valueUnit?.value
                ?? message.interpretedField(key: "avg_speed")?.valueUnit?.value

            let d = devLaps[index]                          // docs/fit-schema.md lap 10–16
            lap.lapType = d["lap_type"]?.int
            lap.flightNum = d["flight_num"]?.int
            lap.takeoffPumps = d["takeoff_pumps"]?.int
            lap.takeoffTimeS = d["takeoff_time"]?.double
            lap.pumpStrokes = d["pump_strokes"]?.int
            lap.turnCount = d["turn_count"]?.int
            lap.bestTurnScorePct = d["best_turn_score"]?.double
            track.laps.append(lap)
        }

        let sessions = fit.messages(forMessageType: .session)
        let devSessions = alignedDevFields(dev, Mesg.session, count: sessions.count)
        track.watchSummary = watchSummary(devSessions.first ?? [:])

        // The sanitizer strips `accelerometer_data` before the C decoder (it overflows the
        // decoder's fixed structs), so the SensorLogging stream is read from the *original*
        // bytes — see FitAccelReader. Rebased onto the record clock.
        track.accel = FitAccelReader.read(data, recordEpoch: start)

        var caps = SourceCapabilities()
        caps.hasSpeed = track.samples.contains { $0.speedMps != nil }
        caps.hasPosition = track.samples.contains { $0.lat != nil }
        caps.hasHR = track.samples.contains { $0.heartRate != nil }
        caps.hasDevFields = devRecords.contains { !$0.keys.filter(devRecordFields.contains).isEmpty }
        caps.hasWatchLaps = track.laps.count > 1
        // The sanitizer strips `accelerometer_data`, but the channel still existed in the
        // source — report the capability rather than losing the fact. `three_d_sensor_-
        // calibration` counts too, matching the lab's `has_accel`.
        caps.hasAccel = [Mesg.accelerometerData, Mesg.threeDSensorCalibration].contains {
            (sanitized.droppedMessageTypes[$0] ?? 0) > 0
                || fit.hasMessageType(messageType: FitMessageType($0))
        }
        if track.samples.count > 1 {
            let dts = zip(track.samples.dropFirst(), track.samples).map { $0.t - $1.t }
            let sorted = dts.sorted()
            let median = sorted[sorted.count / 2]
            caps.sampleRateHz = median > 0 ? (1.0 / median).rounded(toPlaces: 3) : 0
        }
        if let session = sessions.first,
           let sportField = session.interpretedField(key: "sport") {
            caps.sport = sportField.name ?? sportField.valueUnit.map { String(Int($0.value)) }
        }
        // The session dev field is the authoritative discipline tag, not the sport code
        // (docs/fit-schema.md): sport 43 alone cannot tell wingfoiling from windsurfing.
        caps.discipline = track.watchSummary.discipline
        track.capabilities = caps
        // Only the file's own exact answer here. The coarse longitude guess is a rung
        // further down a ladder `SessionIngestor` owns, because intervals.icu's `timezone`
        // sits between the two and the parser has never heard of intervals.icu.
        track.startUtcOffsetS = utcOffsetS(fit)
        return track
    }

    /// The session's own UTC offset in seconds, from the `activity` message.
    ///
    /// `activity.local_timestamp` and `activity.timestamp` are written at save time from
    /// one clock, so their difference is exactly the offset that was in force **for this
    /// session** — DST included, and unaffected by where the file is read afterwards.
    /// Present and correct (+7200) on every fixture in the corpus, our CIQ recordings and
    /// native Garmin ones alike. Mirrors `activity_utc_offset_s` in
    /// lab/src/wingfoil_lab/parse.py — Python is the reference.
    ///
    /// nil, never 0, when the message or either field is missing: "this file does not say"
    /// and "this session was recorded at UTC" are different facts and only one of them
    /// licenses a fallback.
    static func utcOffsetS(_ fit: FitFile) -> Int? {
        for message in fit.messages(forMessageType: FitMessageType(Mesg.activity)) {
            guard let local = message.interpretedField(key: "local_timestamp")?.time,
                  let utc = message.interpretedField(key: "timestamp")?.time else { continue }
            return Int(local.timeIntervalSince(utc).rounded())
        }
        return nil
    }

    /// A whole-hour offset guessed from longitude — the fallback, and only ever that.
    ///
    /// `round(lon / 15°)` hours is the *solar* offset, not the civil one: right to the hour
    /// across most of Europe in winter, an hour out there all summer (DST), up to two hours
    /// out inside wide zones (China, Spain), and blind to the half-hour zones (India,
    /// Newfoundland). It exists for one case — a source with GPS fixes and no `activity`
    /// message — where "within an hour or two" beats formatting an Italian afternoon in the
    /// reader's Californian morning. Anything that can answer exactly wins over it.
    static func coarseUtcOffsetS(_ lon: Double) -> Int? {
        guard lon.isFinite else { return nil }
        return Int((lon / 15.0).rounded()) * 3600
    }

    // MARK: - Developer fields

    /// Developer fields for one message type, padded/truncated to `count` so it can be
    /// indexed in lockstep with `FitFile.messages(forMessageType:)`. Both sequences are in
    /// file order over the same sanitized bytes, so they line up; a mismatch means one of
    /// the two decoders skipped something, and we fail soft to no developer fields rather
    /// than silently attaching values to the wrong samples.
    private static func alignedDevFields(_ dev: FitDeveloperFields, _ type: UInt16,
                                         count: Int) -> [[String: FitDevValue]] {
        let fields = dev.fields(forMessageType: type)
        guard fields.count == count else {
            return [[String: FitDevValue]](repeating: [:], count: count)
        }
        return fields
    }

    /// docs/fit-schema.md session 20–43 (v1) and 54–56 (v2 packed). Speeds are uint16 cm/s
    /// on the wire; the schema declares no FIT scale for them, so the conversions live here.
    /// Internal rather than private so the tests can build a summary from a synthetic
    /// developer-field dictionary without synthesizing FIT bytes.
    static func watchSummary(_ d: [String: FitDevValue]) -> WatchSummary {
        var s = WatchSummary()
        guard !d.isEmpty else { return s }
        func mps(_ key: String) -> Double? { d[key]?.double.map { $0 / 100.0 } }

        s.discipline = d["discipline"]?.string
        s.foilTimeS = d["foil_time"]?.double
        s.foilPct = d["foil_pct"]?.double
        s.flightCount = d["flight_count"]?.int
        s.longestFlightS = d["longest_flight_s"]?.double
        s.longestFlightM = d["longest_flight_m"]?.double
        s.best2sMps = mps("best_2s")
        s.best10sMps = mps("best_10s")
        s.best5x10sMps = mps("best_5x10s")
        s.best500mMps = mps("best_500m")
        s.bestNmMps = mps("best_nm")
        s.alpha500LiteMps = mps("alpha500_lite")
        s.tackCount = d["tack_count"]?.int
        s.jibeCount = d["jibe_count"]?.int
        s.turnSuccessPct = d["turn_success_pct"]?.double
        s.takeoffAttempts = d["takeoff_attempts"]?.int
        s.takeoffSuccesses = d["takeoff_successes"]?.int
        s.avgPumpsToTakeoff = d["avg_pumps_to_takeoff"]?.double.map { $0 / 10.0 }
        s.totalPumpStrokes = d["total_pump_strokes"]?.int
        // 65535 is the schema's "unset" for both wind fields. A well-behaved decoder drops a
        // uint16 invalid pattern before it gets here, but the watch writes the sentinel
        // deliberately (docs/fit-schema.md session 39/44) and a sentinel read as a bearing
        // would be a wind from 65535° — and, worse, would look to `demoteUnclassifiedTurnCounts`
        // like an axis that was set.
        func windDeg(_ key: String) -> Double? {
            guard let v = d[key]?.double, v < 65535 else { return nil }
            return v
        }
        s.windDirUserDeg = windDeg("wind_dir_user")
        s.windDirAutoDeg = windDeg("wind_dir_auto")
        s.cfgEntrySpeedMps = mps("cfg_entry_speed")
        s.cfgExitSpeedMps = mps("cfg_exit_speed")
        s.cfgMinFlightS = d["cfg_min_flight"]?.double
        s.appVersion = d["app_version"]?.int
        // …then let any packed field override its v1 counterpart. Presence decides, the
        // schema version is only corroboration: the data-field variant (class d) writes
        // `cfg_pack` under schema v1, and a file may carry no `app_version` at all.
        for pack in Self.sessionPacks { pack.unpack(d, into: &s) }
        demoteUnclassifiedTurnCounts(&s)
        return s
    }

    /// `0/0` turn counts with **no wind axis of either kind** mean *unclassified*, not
    /// *none* — drop them.
    ///
    /// Naming a sweep a tack or a jibe needs a wind axis. Until device app 0.9.0 the watch had
    /// exactly one source for one: the bearing the rider entered by hand (`wind_dir_user`).
    /// Since 0.9.0 it can also estimate one for itself and writes that in `wind_dir_auto`
    /// (docs/algorithms.md "Watch approximation: auto wind"); either field means the split is
    /// a real observation. Older builds still wrote `tack_count`/`jibe_count` when there was
    /// no axis at all, and the only value they could write was a literal 0 — so a session of
    /// fifty clean jibes arrives claiming zero of each, and the divergence banner reports
    /// "Jibes: watch 0 vs phone 50" as if the two implementations disagreed. They do not: the
    /// watch never counted.
    ///
    /// docs/presentation.md's formatter rule is that missing must be *absent*, never 0, so
    /// the pair is dropped here at the parser boundary. `DivergenceCheck` skips nil counts
    /// and therefore stops comparing them. This runs after the pack unpacking so a future
    /// packed turn field is demoted on the same rule.
    ///
    /// Deliberately narrow: only the `0/0`-with-no-wind-at-all case, which cannot be a real
    /// observation the watch made — one non-zero count, or either wind field, means an axis
    /// was in effect and a 0 is a genuine "none of those", still worth comparing.
    private static func demoteUnclassifiedTurnCounts(_ s: inout WatchSummary) {
        guard s.windDirUserDeg == nil, s.windDirAutoDeg == nil,
              s.tackCount == 0, s.jibeCount == 0 else { return }
        s.tackCount = nil
        s.jibeCount = nil
    }

    // MARK: - v2 packed session fields

    /// One session developer field that folds several v1 fields into a single uint32.
    ///
    /// Schema v2 exists because the device hard-limits developer fields to **16 per message
    /// type** — undocumented, and not a catchable exception: the 17th `createField` killed
    /// the app on START. v1's 20 session fields therefore never ran; v2 packs the three
    /// groups of small fields into 54/55/56 (garmin/source/fit/FitSchema.mc,
    /// docs/fit-schema.md). Unpacking here, at the parser boundary, keeps every v2 summary
    /// bit-identical to the v1 one, so nothing downstream knows the schema changed.
    private struct PackedSessionField: Sendable {
        struct Part: Sendable {
            let shift: UInt32
            let mask: UInt32
            /// Applied to the extracted integer, in the same units the v1 field used.
            let assign: @Sendable (inout WatchSummary, Double) -> Void
        }
        let name: String
        let parts: [Part]

        /// Fail-soft, like the rest of the parser: absent, non-numeric or non-integral
        /// values leave the summary untouched rather than throwing or writing garbage.
        func unpack(_ d: [String: FitDevValue], into s: inout WatchSummary) {
            guard let raw = d[name]?.double,
                  raw >= 0, raw <= Double(UInt32.max), raw == raw.rounded()
            else { return }
            let bits = UInt32(raw)
            for part in parts { part.assign(&s, Double((bits >> part.shift) & part.mask)) }
        }
    }

    /// docs/fit-schema.md session 54–56, mirroring `FitSchema.packCfg/packTakeoff/packLongest`.
    private static let sessionPacks: [PackedSessionField] = [
        // 54 entry_cms << 16 | min_flight_s << 11 | exit_cms — also written by class (d).
        PackedSessionField(name: "cfg_pack", parts: [
            .init(shift: 16, mask: 0xFFFF, assign: { $0.cfgEntrySpeedMps = $1 / 100.0 }),
            .init(shift: 11, mask: 0x1F, assign: { $0.cfgMinFlightS = $1 }),
            .init(shift: 0, mask: 0x7FF, assign: { $0.cfgExitSpeedMps = $1 / 100.0 }),
        ]),
        // 55 avg_pumps_x10 << 16 | attempts << 8 | successes
        PackedSessionField(name: "takeoff_pack", parts: [
            .init(shift: 16, mask: 0xFF, assign: { $0.avgPumpsToTakeoff = $1 / 10.0 }),
            .init(shift: 8, mask: 0xFF, assign: { $0.takeoffAttempts = Int($1) }),
            .init(shift: 0, mask: 0xFF, assign: { $0.takeoffSuccesses = Int($1) }),
        ]),
        // 56 seconds << 16 | metres
        PackedSessionField(name: "longest_pack", parts: [
            .init(shift: 16, mask: 0xFFFF, assign: { $0.longestFlightS = $1 }),
            .init(shift: 0, mask: 0xFFFF, assign: { $0.longestFlightM = $1 }),
        ]),
    ]
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}
