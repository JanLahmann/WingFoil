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
        return track
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

    /// docs/fit-schema.md session 20–43. Speeds are uint16 cm/s on the wire; the schema
    /// declares no FIT scale for them, so the conversions live here.
    private static func watchSummary(_ d: [String: FitDevValue]) -> WatchSummary {
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
        s.windDirUserDeg = d["wind_dir_user"]?.double
        s.cfgEntrySpeedMps = mps("cfg_entry_speed")
        s.cfgExitSpeedMps = mps("cfg_exit_speed")
        s.cfgMinFlightS = d["cfg_min_flight"]?.double
        s.appVersion = d["app_version"]?.int
        return s
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}
