import Foundation

/// Parses a `.cjw` container written by the CleanJibe watchOS app into a `RawTrack`.
///
/// The peer of `FitSessionParser` and `GpxSessionParser`, and deliberately the *third* door
/// rather than a special case bolted onto either: `TrackParser` sniffs the bytes, this turns
/// them into the same `RawTrack` + `SourceCapabilities` everything downstream already reads,
/// and nothing past this file knows an Apple Watch exists (docs/plan.md §3.3 — the pipeline
/// degrades on capabilities, not on formats).
///
/// **Source class (b), certified.** The rule the whole app reads is
/// `LibraryQueries.certified` = `sourceClass != "c"`, and `sourceClass` is `"b"` here because
/// `hasSpeed` is true and `hasDevFields` is false. Both halves are meant:
///
/// * **`hasSpeed` is true, and it is not the GPX situation.** docs/presentation.md's rule is
///   about *provenance*: "a speed record is only trustworthy when it came off the receiver's
///   Doppler channel". `CLLocation.speed` is exactly that — the GNSS chip's own Doppler
///   solution, reported per fix, not differentiated from the positions afterwards. A GPX is
///   class (c) because the file cannot prove where its speed came from; this container can,
///   because we wrote it, and it writes the speed channel and the positions as two separate
///   things. Certifying it is the same claim already made for a native Garmin FIT.
///   It is *not* a claim of GP3S submission validity — the app has never made that claim for
///   any source, and Apple has published no receiver spec that would support one.
/// * **`hasDevFields` is false, and that is honest.** The MVP watch app records; it does not
///   detect. There is no on-wrist foil state, no flight index, no turn marker and no watch
///   summary to diverge from, so there is nothing to claim class (a) with.
///
/// **But the capabilities carry more than the letter does.** A watch session has class (b)'s
/// Doppler *and* class (a)'s accelerometer, so `PumpTrack`, `TakeoffAnalyzer` and the
/// accel-corroborated flight-end and turn rules all run — the analysis a native Garmin FIT
/// cannot have. That is why the letter is not the whole story anywhere it matters, and why
/// `SessionDisplay.sourceClassNote` reads the import source as well as the class before it
/// tells the rider what this session can show.
public enum WatchSessionParser {

    public enum ParseError: Error, CustomStringConvertible {
        case noRecords

        public var description: String {
            switch self {
            case .noRecords: "the watch session contains no position fixes"
            }
        }
    }

    /// Heart rate is sampled when the sensor has something to say — every 1–5 s, irregularly
    /// — so it is carried on its own clock and joined to the 1 Hz track here. A reading more
    /// than this far from a record is not that record's heart rate and is left off rather
    /// than stretched to cover the gap.
    static let heartJoinToleranceS: Double = 5

    public static func parse(data: Data) throws -> RawTrack {
        try build(WatchSessionContainer.decode(data))
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

    static func build(_ payload: WatchSessionPayload) throws -> RawTrack {
        guard !payload.track.isEmpty else { throw ParseError.noRecords }

        var track = RawTrack()
        let meta = payload.meta
        let start = Date(timeIntervalSince1970: meta.startEpoch)
        track.startDate = start

        // Rung 1 of the offset ladder (`SessionIngestor.resolveUtcOffset`): the recording
        // saying so itself. The watch read its own calendar at start, DST included, so a
        // watch session never falls through to the longitude guess a GPX has to use.
        track.startUtcOffsetS = meta.utcOffsetS
        track.startUtcOffsetSource = .activity

        var samples: [RecordSample] = []
        samples.reserveCapacity(payload.track.count)
        // Two-pointer join rather than a search per record: both streams are sorted, and a
        // two-hour session is 7 000 records against 3 000 readings.
        var heartIndex = 0
        for point in payload.track {
            var s = RecordSample(t: point.t,
                                 timestamp: Date(timeIntervalSince1970: meta.startEpoch + point.t))
            s.lat = point.lat
            s.lon = point.lon
            s.speedMps = point.speedMps
            s.altitudeM = point.altitudeM
            s.gapBefore = point.gapBefore
            // `distanceM` is deliberately left nil: the watch does not carry an odometer, and
            // the engine's own projection is what every other distance in the app is measured
            // with. A second, worse number in the same column would only ever disagree.
            s.heartRate = heartRate(at: point.t, in: payload.heart, cursor: &heartIndex)
            samples.append(s)
        }
        track.samples = samples

        track.accel = payload.accel.map { AccelSample(t: $0.t, magnitudeG: $0.magnitudeG) }

        var caps = SourceCapabilities()
        // The container's own claim, checked against what actually arrived: a session that
        // never got a fix with a speed on it does not get to say it has a speed channel.
        caps.hasSpeed = samples.contains { $0.speedMps != nil }
        caps.hasPosition = true
        caps.hasHR = !payload.heart.isEmpty
        caps.hasAccel = !payload.accel.isEmpty
        // No developer fields and no laps: the MVP watch app records, it does not detect.
        caps.hasDevFields = false
        caps.hasWatchLaps = false
        caps.sampleRateHz = sampleRateHz(samples)
        // The HealthKit type the workout was actually filed under (`surfingSports`), so the
        // row records what Health will show rather than what we wish it showed.
        caps.sport = meta.activityType
        // Authoritative, and for once not an approximation: this app records one discipline.
        // It is also what gets a watch session past `SessionIngestor.isWatersport`, which a
        // GPX can never pass.
        caps.discipline = meta.discipline
        track.capabilities = caps

        return track
    }

    /// Nearest heart-rate reading to `t`, or nil when the nearest is too far away.
    ///
    /// `cursor` walks forward across the whole track and is never rewound — the records are
    /// sorted, so the first reading at or after `t` only ever moves right.
    static func heartRate(at t: Double, in heart: [WatchHeartSample], cursor: inout Int) -> Double? {
        guard !heart.isEmpty else { return nil }
        while cursor + 1 < heart.count, heart[cursor + 1].t <= t { cursor += 1 }
        var best = heart[cursor]
        if cursor + 1 < heart.count,
           abs(heart[cursor + 1].t - t) < abs(best.t - t) { best = heart[cursor + 1] }
        return abs(best.t - t) <= heartJoinToleranceS ? best.bpm : nil
    }

    /// Median inter-sample interval turned into a rate — median rather than mean so a single
    /// pause in the middle of the session does not report the whole recording as 0.2 Hz.
    static func sampleRateHz(_ samples: [RecordSample]) -> Double {
        guard samples.count > 1 else { return 0 }
        var deltas: [Double] = []
        deltas.reserveCapacity(samples.count - 1)
        for i in 1..<samples.count {
            let dt = samples[i].t - samples[i - 1].t
            if dt > 0 { deltas.append(dt) }
        }
        guard !deltas.isEmpty else { return 0 }
        deltas.sort()
        let median = deltas[deltas.count / 2]
        return median > 0 ? 1 / median : 0
    }
}
