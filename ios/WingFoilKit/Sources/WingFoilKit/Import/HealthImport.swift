import Foundation

/// One `CLLocation` out of an `HKWorkoutRoute`, as a value type with no HealthKit in it.
///
/// The kit cannot import HealthKit — it builds and tests on a machine with no Health
/// database, no entitlement and no watch in the room — so the app layer reads the route and
/// hands the samples over as plain numbers. That split is also what makes this mapper
/// testable at all: everything below is arithmetic on synthetic arrays.
public struct HealthRouteSample: Sendable, Equatable {
    public var timestamp: Date
    public var lat: Double
    public var lon: Double
    public var altitudeM: Double?
    /// `CLLocation.horizontalAccuracy` in metres. CoreLocation says "no reading" with a
    /// negative number; that convention is normalised away here (see `HealthImport`).
    public var horizontalAccuracyM: Double?
    /// `CLLocation.speed` in m/s — the GNSS chip's own Doppler solution, which is the whole
    /// reason an Apple Health workout is input class (b) rather than a GPX's class (c).
    /// Negative means invalid, and is read as "no reading".
    public var speedMps: Double?
    /// `CLLocation.course` in degrees. Carried because the caller has it and throwing a
    /// channel away at the door is how a source quietly becomes worse than it is — but it
    /// stops here: the engine derives course over ground from the positions themselves
    /// (`TrackCleaner`), so a second, differently-filtered answer in the same column would
    /// only ever disagree with the one every other source is measured on.
    public var courseDeg: Double?

    public init(timestamp: Date, lat: Double, lon: Double, altitudeM: Double? = nil,
                horizontalAccuracyM: Double? = nil, speedMps: Double? = nil,
                courseDeg: Double? = nil) {
        self.timestamp = timestamp
        self.lat = lat
        self.lon = lon
        self.altitudeM = altitudeM
        self.horizontalAccuracyM = horizontalAccuracyM
        self.speedMps = speedMps
        self.courseDeg = courseDeg
    }
}

/// One heart-rate sample from the workout's own `HKQuantitySample` stream, in bpm.
///
/// Its own clock, like the watch container's: the sensor reports when it has something to
/// say, every 1–5 s, and pinning it to the 1 Hz route would mean inventing readings.
public struct HealthHeartSample: Sendable, Equatable {
    public var timestamp: Date
    public var bpm: Double

    public init(timestamp: Date, bpm: Double) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

/// An Apple **Workout app** recording, read back out of Health, turned into the same
/// `RawTrack` + `SourceCapabilities` every other source produces (docs/decisions.md ADR-017).
///
/// **Why this is not a fourth format.** An `HKWorkoutRoute` is a run of `CLLocation`s with a
/// Doppler speed on each, plus a heart-rate stream on its own clock — which is, sample for
/// sample, what the CleanJibe watch app already writes into a `.cjw` container
/// (docs/watch-session-schema.md). So this maps into that container rather than inventing a
/// second binary shape for identical data: one packed track format, one parser
/// (`WatchSessionParser`), one set of capability rules, and the archived original re-analyses
/// on an engine bump exactly like every other session. `TrackFormat.watch` names the
/// *format*, never the producer — `meta.producer` says who wrote it, and
/// `session.importSource` (`applehealth`) says where the session came from.
///
/// **Source class (b), certified.** ADR-016 settled this for `CLLocation.speed` and the
/// argument transfers unchanged: docs/presentation.md's rule is about *provenance* — a speed
/// record is trustworthy when it came off the receiver's Doppler channel — and Apple's route
/// speed is exactly that, reported per fix by the GNSS chip rather than differentiated from
/// the positions afterwards. A GPX is class (c) because the file cannot prove where its speed
/// came from; a route can, because CoreLocation carries speed and position as two separate
/// channels and Health hands both over. It is **not** a GP3S validity claim, which this app
/// has never made for any source.
///
/// **What is missing, and stays missing.** No accelerometer (`hasAccel` false), so no pump
/// strokes, no failed takeoff attempts, no accelerometer-confirmed touchdowns; no developer
/// fields (`hasDevFields` false), so no watch summary to diverge from. That makes these
/// sessions plain class (b) — the same letter and the same sentence as a native Garmin FIT,
/// which is the honest answer: `SessionDisplay.sourceClassNote`'s Apple-Watch special case is
/// keyed on `applewatch` precisely because *that* source has an accelerometer and this one
/// does not.
public enum HealthImport {

    public enum ImportError: Error, CustomStringConvertible, Equatable {
        case noRoute

        public var description: String {
            switch self {
            case .noRoute:
                "this workout has no GPS route — Health kept no positions for it"
            }
        }
    }

    /// A jump this long between consecutive fixes is read as the recorder having stopped, and
    /// marked `RecordSample.gapBefore`.
    ///
    /// `TrackCleaner`'s own rule (dt > max(3 s, 2 × median dt)) already catches most of these
    /// and this never subtracts from it — the two are ORed, exactly as they are for a GPX
    /// `<trkseg>` boundary. What the explicit mark buys is the case the dt rule cannot see:
    /// a route delivered at 3–5 s per fix (Apple thins the stream in Low Power Mode and when
    /// the wrist is under water) raises the median, and with it the threshold, until a real
    /// pause stops looking unusual. 10 s is well clear of any thinning Apple does and well
    /// under any pause worth calling one.
    public static let gapThresholdS: Double = 10

    /// The authoritative discipline tag every session mapped here carries.
    ///
    /// Apple has no wingfoil workout type — the rider picked Surfing, Water Sports or Sailing
    /// because those are the choices — so the type it was filed under says nothing about the
    /// discipline, and the *import* is where the rider says what it was: he pointed a wingfoil
    /// app at a workout and asked for it. Same claim the watch app makes about its own
    /// recordings, and for the same reason. The type Health actually holds is not thrown away:
    /// it lands in `SourceCapabilities.sport`.
    public static let discipline = "wingfoil"

    // MARK: - Mapping

    /// The container payload: the one place the arithmetic lives, so `track` and `container`
    /// below cannot drift apart.
    ///
    /// `utcOffsetS` is what the *workout* said its clock was — `HKMetadataKeyTimeZone`,
    /// resolved at the session's own instant — or nil when it carried none, which is the
    /// ordinary case for Apple's own Workout app. nil is written into the header as "this
    /// number is not the recording's word" (`WatchSessionMeta.utcOffsetKnown`) so that
    /// `SessionIngestor.resolveUtcOffset` falls through to the longitude rung rather than
    /// having a guess handed to it wearing rung 1's provenance. Every other source in the app
    /// is held to that distinction and this one is no different.
    public static func payload(sessionId: String,
                               activityType: String,
                               route: [HealthRouteSample],
                               heart: [HealthHeartSample] = [],
                               utcOffsetS: Int?,
                               producer: String) throws -> WatchSessionPayload {
        let fixes = usable(route)
        guard let first = fixes.first, let last = fixes.last else { throw ImportError.noRoute }

        let start = first.timestamp
        var samples: [WatchTrackSample] = []
        samples.reserveCapacity(fixes.count)
        var previous: Date?
        for fix in fixes {
            let t = fix.timestamp.timeIntervalSince(start)
            let gap = previous.map { fix.timestamp.timeIntervalSince($0) > gapThresholdS } ?? false
            samples.append(WatchTrackSample(t: t, lat: fix.lat, lon: fix.lon,
                                            speedMps: reading(fix.speedMps),
                                            horizontalAccuracyM: reading(fix.horizontalAccuracyM),
                                            altitudeM: fix.altitudeM.flatMap {
                                                $0.isFinite ? $0 : nil
                                            },
                                            gapBefore: gap))
            previous = fix.timestamp
        }

        // The heart stream is joined onto the record timeline by `WatchSessionParser`, which
        // is where the ±5 s tolerance and the two-pointer walk already live. All this has to
        // do is put it on the same clock and drop anything outside the route's own span —
        // Health hands back the whole workout's samples, and a reading from the ten minutes
        // before the first fix is not this track's heart rate.
        let span = last.timestamp.timeIntervalSince(start)
        let beats = heart
            .filter { $0.bpm.isFinite && $0.bpm > 0 }
            .map { WatchHeartSample(t: $0.timestamp.timeIntervalSince(start), bpm: $0.bpm) }
            .filter { $0.t >= -WatchSessionParser.heartJoinToleranceS
                && $0.t <= span + WatchSessionParser.heartJoinToleranceS }
            .sorted { $0.t < $1.t }

        var meta = WatchSessionMeta(sessionId: sessionId,
                                    startEpoch: start.timeIntervalSince1970,
                                    // Unread when `utcOffsetKnown` is false; written as zero
                                    // rather than as a plausible-looking guess, so a human
                                    // reading the header cannot mistake it for one.
                                    utcOffsetS: utcOffsetS ?? 0,
                                    durationS: span,
                                    activityType: activityType,
                                    discipline: discipline,
                                    locationRateHz: rateHz(samples),
                                    // No accelerometer reaches us from Health at all.
                                    accelRateHz: 0,
                                    producer: producer)
        meta.utcOffsetKnown = utcOffsetS != nil
        return WatchSessionPayload(meta: meta, track: samples, heart: beats, accel: [])
    }

    /// The mapper the analysis pipeline consumes. Deliberately `WatchSessionParser.build` and
    /// not a second implementation of it: the capability rules, the heart join and the sample
    /// rate are decided in exactly one place, so a session analysed straight after import and
    /// the same session re-analysed from its archived container cannot disagree.
    public static func track(sessionId: String,
                             activityType: String,
                             route: [HealthRouteSample],
                             heart: [HealthHeartSample] = [],
                             utcOffsetS: Int? = nil,
                             producer: String) throws -> RawTrack {
        try WatchSessionParser.build(payload(sessionId: sessionId, activityType: activityType,
                                             route: route, heart: heart,
                                             utcOffsetS: utcOffsetS, producer: producer))
    }

    /// The bytes that get archived — what `SessionIngestor.ingest` is handed, and what
    /// `reanalyze` reads back on an engine bump.
    public static func container(sessionId: String,
                                 activityType: String,
                                 route: [HealthRouteSample],
                                 heart: [HealthHeartSample] = [],
                                 utcOffsetS: Int? = nil,
                                 producer: String) throws -> Data {
        let payload = try payload(sessionId: sessionId, activityType: activityType,
                                  route: route, heart: heart,
                                  utcOffsetS: utcOffsetS, producer: producer)
        return try WatchSessionContainer.encode(meta: payload.meta, track: payload.track,
                                                heart: payload.heart, accel: payload.accel)
    }

    /// The filename the archive and the import log show for one imported workout.
    public static func filename(start: Date, utcOffsetS: Int?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        formatter.timeZone = utcOffsetS.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
        return "\(formatter.string(from: start))-health.\(WatchSessionContainer.fileExtension)"
    }

    // MARK: - Internals

    /// Sorted, de-duplicated, and stripped of anything that cannot be placed on a map or a
    /// timeline. Same three refusals `GpxSessionParser` makes, for the same reasons: a fix
    /// with no usable position is not a degraded sample, it is not a sample, and two fixes at
    /// one instant divide by zero in every speed the engine derives.
    static func usable(_ route: [HealthRouteSample]) -> [HealthRouteSample] {
        var seen = Set<Date>()
        return route
            .filter { $0.lat.isFinite && $0.lon.isFinite
                && abs($0.lat) <= 90 && abs($0.lon) <= 180
                && $0.timestamp.timeIntervalSince1970.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
            .filter { seen.insert($0.timestamp).inserted }
    }

    /// CoreLocation's "no reading" is a negative number. The container encodes that as NaN
    /// and the parser reads NaN back as nil, but `track` above never goes through the wire —
    /// so the normalisation happens here, once, and both paths see the same channel.
    static func reading(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Nominal rate for the header, from the median interval. The authority for analysis is
    /// `SourceCapabilities.sampleRateHz`, which `WatchSessionParser` computes the same way
    /// from the samples themselves; this is the header's own record of what arrived.
    static func rateHz(_ samples: [WatchTrackSample]) -> Double {
        guard samples.count > 1 else { return 0 }
        var deltas: [Double] = []
        deltas.reserveCapacity(samples.count - 1)
        for i in 1..<samples.count where samples[i].t > samples[i - 1].t {
            deltas.append(samples[i].t - samples[i - 1].t)
        }
        guard !deltas.isEmpty else { return 0 }
        deltas.sort()
        let median = deltas[deltas.count / 2]
        return median > 0 ? (1 / median * 100).rounded() / 100 : 0
    }
}
