import Foundation

// THE WIRE FORMAT BETWEEN THE WATCH AND THE PHONE. Documented in docs/watch-session-schema.md,
// which is the contract; this file is its only implementation and must not drift from it.
//
// SHARED SOURCE, NOT A LINKED LIBRARY. This file is compiled into *both* WingFoilKit and the
// watchOS app target (see ios/project.yml, `WingFoilWatch.sources`) — the same arrangement
// `Presentation/WidgetSnapshot.swift` already uses for the widget. The alternative is linking
// WingFoilKit into the watch app, which would drag GRDB, FitFileParser and ZIPFoundation onto
// a wrist in order to write four floats at a time.
//
// It therefore depends on **Foundation and nothing else**: no RawTrack, no engine types, no
// GRDB. The translation into `RawTrack` lives next door in `WatchSessionParser.swift`, which
// is phone-only. Keep that split — an import of anything else here breaks the watch build,
// and it breaks it at link time on a target Jan cannot run on real hardware.

// MARK: - Samples

/// One position fix as the watch saw it: CoreLocation, nominally 1 Hz.
///
/// `speedMps` is `CLLocation.speed` — **Doppler-derived**, measured by the GNSS chip rather
/// than differentiated from the positions, which is the whole reason a watch session is an
/// input class (b) and not a (c) like a GPX (docs/watch-session-schema.md, "Source class").
/// nil where CoreLocation reported the channel invalid (it signals that with a negative
/// number, which is never written to the wire as such — see `encode`).
public struct WatchTrackSample: Sendable, Equatable {
    /// Seconds from session start. The one clock every stream in the container shares.
    public var t: Double
    public var lat: Double
    public var lon: Double
    public var speedMps: Double?
    /// `CLLocation.horizontalAccuracy` in metres. Kept because it is the only evidence the
    /// phone has for how much to trust a fix, and throwing it away on the watch would be
    /// throwing it away for good.
    public var horizontalAccuracyM: Double?
    public var altitudeM: Double?
    /// The recorder is telling us it stopped here: the rider paused, or the workout was
    /// interrupted. Same claim a GPX `<trkseg>` boundary makes, and it reaches
    /// `TrackCleaner` by the same door (`RecordSample.gapBefore`).
    public var gapBefore: Bool

    public init(t: Double, lat: Double, lon: Double, speedMps: Double? = nil,
                horizontalAccuracyM: Double? = nil, altitudeM: Double? = nil,
                gapBefore: Bool = false) {
        self.t = t
        self.lat = lat
        self.lon = lon
        self.speedMps = speedMps
        self.horizontalAccuracyM = horizontalAccuracyM
        self.altitudeM = altitudeM
        self.gapBefore = gapBefore
    }
}

/// One heart-rate reading off `HKLiveWorkoutBuilder`. Irregular — the sensor reports when it
/// has something, roughly every 1–5 s — so it gets its own stream with its own times rather
/// than a column in the track.
public struct WatchHeartSample: Sendable, Equatable {
    public var t: Double
    public var bpm: Double

    public init(t: Double, bpm: Double) {
        self.t = t
        self.bpm = bpm
    }
}

/// One wrist-accelerometer sample: |a| in **g**, gravity included, so a resting wrist reads
/// about 1.0.
///
/// Magnitude only, exactly like the Garmin stream (`AccelSample`): the pump detector is
/// orientation-free by construction (docs/algorithms.md "Pumping"), the wrist rotates
/// constantly, and three axes at 50 Hz would triple the biggest stream in the container to
/// carry information nothing reads.
public struct WatchAccelSample: Sendable, Equatable {
    public var t: Double
    public var magnitudeG: Double

    public init(t: Double, magnitudeG: Double) {
        self.t = t
        self.magnitudeG = magnitudeG
    }
}

// MARK: - Header

/// The JSON header's `meta` object — everything about the session that is not a sample.
///
/// Codable and additive-only: a reader must tolerate keys it does not know (JSONDecoder does)
/// and a writer must never remove one without bumping `WatchSessionContainer.version`.
public struct WatchSessionMeta: Codable, Sendable, Equatable {
    /// docs/watch-session-schema.md's schema number. Distinct from the container version:
    /// the container is the *envelope* (magic, header, stream table), this is the *meaning*
    /// of the fields inside it.
    public var schema: Int
    /// The watch's own id for the recording. Not the library's — the phone mints that — but
    /// it makes a re-sent file recognisable in a log.
    public var sessionId: String
    /// Session start as seconds since 1970, **UTC**.
    public var startEpoch: Double
    /// The UTC offset the watch was wearing at start, in seconds.
    ///
    /// This is rung 1 of the offset ladder (`SessionIngestor.resolveUtcOffset`): the
    /// recording saying so itself, DST included. A watch session therefore never needs the
    /// longitude guess a GPX falls back to.
    public var utcOffsetS: Int
    /// Wall-clock length of the recording including pauses; `t` of the last sample is the
    /// authority for analysis and this is a cross-check.
    public var durationS: Double
    /// The `HKWorkoutActivityType` the workout was recorded under, by name
    /// (e.g. `"surfingSports"`). Lands in `SourceCapabilities.sport`.
    public var activityType: String
    /// The authoritative discipline tag — `"wingfoil"`. The watch app records one thing, so
    /// unlike a FIT's sport code this is not an approximation.
    public var discipline: String
    /// Nominal rates, for the phone to record in `SourceCapabilities` and for a human
    /// reading a header to see what the file was *meant* to contain.
    public var locationRateHz: Double
    public var accelRateHz: Double
    /// "CleanJibe watchOS 0.12.0 (14)" — who wrote this and which build.
    public var producer: String
    /// `WKInterfaceDevice` model and system version, for triage. Optional: a synthetic
    /// fixture has neither and must still be a legal container.
    public var device: String?
    public var systemVersion: String?

    public init(schema: Int = WatchSessionContainer.schema,
                sessionId: String,
                startEpoch: Double,
                utcOffsetS: Int,
                durationS: Double,
                activityType: String,
                discipline: String = "wingfoil",
                locationRateHz: Double = 1,
                accelRateHz: Double = 50,
                producer: String,
                device: String? = nil,
                systemVersion: String? = nil) {
        self.schema = schema
        self.sessionId = sessionId
        self.startEpoch = startEpoch
        self.utcOffsetS = utcOffsetS
        self.durationS = durationS
        self.activityType = activityType
        self.discipline = discipline
        self.locationRateHz = locationRateHz
        self.accelRateHz = accelRateHz
        self.producer = producer
        self.device = device
        self.systemVersion = systemVersion
    }
}

/// Where one stream's bytes are and how to read them. Offsets are from the start of the
/// payload (i.e. from the first byte after the header), never from the start of the file, so
/// a header that grows by one character does not move every stream.
public struct WatchStreamIndex: Codable, Sendable, Equatable {
    public var name: String
    /// Record layout tag, e.g. `"track.v1"`. A reader that does not know the tag must fail
    /// loudly rather than guess a stride.
    public var encoding: String
    public var recordBytes: Int
    public var count: Int
    public var offset: Int
    public var length: Int
}

/// The whole header: metadata plus the stream table.
public struct WatchSessionHeader: Codable, Sendable, Equatable {
    public var meta: WatchSessionMeta
    public var streams: [WatchStreamIndex]
}

/// A decoded container.
public struct WatchSessionPayload: Sendable, Equatable {
    public var meta: WatchSessionMeta
    public var track: [WatchTrackSample]
    public var heart: [WatchHeartSample]
    public var accel: [WatchAccelSample]
}

// MARK: - Container

/// The `.cjw` container: a magic number, a JSON header, and packed binary sample streams.
///
/// **Why not JSON throughout.** A two-hour session is ~360 000 accelerometer samples. As JSON
/// that is roughly 12 MB to serialise on a watch, hand to `WCSession.transferFile` and parse
/// on a phone; packed it is 2.9 MB, and the packing is eight lines of arithmetic. The header
/// stays JSON because it is small, self-describing and the part a human ever has to read.
///
/// **Why the streams are appendable.** Every stream is a flat run of fixed-width records with
/// no framing, so the recorder writes them straight to three files as they arrive
/// (`SessionRecorder`) and the container is assembled at stop by concatenation. Nothing is
/// ever held in memory that grows with session length, and a crash leaves partial stream
/// files that are still individually valid.
///
/// **Endianness.** Little-endian IEEE 754 throughout, stated rather than inherited: both ends
/// are ARM today, and a format that only works because nobody checked is a format that breaks
/// silently.
public enum WatchSessionContainer {

    /// File magic. Also what `TrackParser.format` sniffs for, so it must not collide with
    /// FIT (`.FIT` at byte 8) or GPX (a leading `<`).
    public static let magic: [UInt8] = Array("CJWS".utf8)
    /// Envelope version. Bumped only when the magic/header/stream-table arrangement changes.
    public static let version: UInt32 = 1
    /// Field-meaning version — see `WatchSessionMeta.schema`.
    public static let schema = 1

    public static let trackEncoding = "track.v1"
    public static let heartEncoding = "heart.v1"
    public static let accelEncoding = "accel.v1"

    public static let trackRecordBytes = 40
    public static let heartRecordBytes = 12
    public static let accelRecordBytes = 8

    /// The extension the archive stores a watch session under.
    public static let fileExtension = "cjw"

    public enum Error: Swift.Error, CustomStringConvertible, Equatable {
        case notAContainer
        case unsupportedVersion(UInt32)
        case badHeader(String)
        case truncated(String)
        case unknownEncoding(String)

        public var description: String {
            switch self {
            case .notAContainer: "not a CleanJibe watch session container"
            case .unsupportedVersion(let v): "watch container version \(v) is newer than this app understands"
            case .badHeader(let why): "unreadable watch container header: \(why)"
            case .truncated(let what): "watch container is truncated: \(what)"
            case .unknownEncoding(let tag): "unknown watch stream encoding \"\(tag)\""
            }
        }
    }

    /// Cheap content sniff, the peer of `GpxSessionParser.isGpx`. Bytes, not filename: the
    /// callers that matter (a transferred file, an archived original, a re-analysis) all have
    /// bytes and only sometimes have a trustworthy name.
    public static func isContainer(_ data: Data) -> Bool {
        guard data.count >= magic.count else { return false }
        for (i, byte) in magic.enumerated() where data[data.startIndex + i] != byte {
            return false
        }
        return true
    }

    // MARK: Record encoding

    /// 40 bytes: f64 t · f64 lat · f64 lon · f32 speed · f32 accuracy · f32 altitude · u32 flags.
    ///
    /// A missing float is NaN on the wire rather than a magic number — NaN is the one value
    /// that cannot be mistaken for a reading, and it survives every arithmetic a careless
    /// reader might do to it. CoreLocation's own "invalid" convention (a negative speed or
    /// accuracy) is normalised away here so the phone never has to know it.
    public static func encodeRecord(_ s: WatchTrackSample) -> Data {
        var out = Data(capacity: trackRecordBytes)
        out.appendLE(s.t)
        out.appendLE(s.lat)
        out.appendLE(s.lon)
        out.appendLE(Float(nonNegative(s.speedMps)))
        out.appendLE(Float(nonNegative(s.horizontalAccuracyM)))
        out.appendLE(Float(s.altitudeM ?? .nan))
        out.appendLE(UInt32(s.gapBefore ? 1 : 0))
        return out
    }

    /// 12 bytes: f64 t · f32 bpm.
    public static func encodeRecord(_ s: WatchHeartSample) -> Data {
        var out = Data(capacity: heartRecordBytes)
        out.appendLE(s.t)
        out.appendLE(Float(s.bpm))
        return out
    }

    /// 8 bytes: f32 t · f32 |a| in g.
    ///
    /// `t` is single-precision here and nowhere else, because this is the stream that is
    /// 50× the others and the only one where the width shows up in the transfer. The cost is
    /// bounded and known: near t = 7200 s (two hours, longer than any session Jan has ridden)
    /// consecutive Float values are 2^-10 s ≈ 0.49 ms apart, against a 20 ms sampling
    /// interval. Rounding is monotone, so the stream stays sorted, and `PumpAnalyzer` box-
    /// averages onto a 25 Hz grid anyway — two samples that collided would land in one bin
    /// and be averaged, which is what that code does with every bin regardless.
    public static func encodeRecord(_ s: WatchAccelSample) -> Data {
        var out = Data(capacity: accelRecordBytes)
        out.appendLE(Float(s.t))
        out.appendLE(Float(s.magnitudeG))
        return out
    }

    /// CoreLocation says "no reading" with a negative number; the wire says it with NaN.
    private static func nonNegative(_ value: Double?) -> Double {
        guard let value, value >= 0, value.isFinite else { return .nan }
        return value
    }

    // MARK: Assembly

    /// Builds a container from three already-encoded stream blobs — the recorder's path,
    /// where the blobs are files on disk that were appended to a record at a time.
    ///
    /// Counts are derived from the byte lengths rather than passed in: a stream file that was
    /// cut short by a crash mid-record then loses its ragged tail here instead of producing a
    /// header that promises a record the file does not contain.
    public static func assemble(meta: WatchSessionMeta,
                                trackBytes: Data,
                                heartBytes: Data,
                                accelBytes: Data) throws -> Data {
        var streams: [WatchStreamIndex] = []
        var payload = Data()

        func add(_ name: String, _ encoding: String, _ recordBytes: Int, _ bytes: Data) {
            let count = bytes.count / recordBytes
            let whole = bytes.prefix(count * recordBytes)
            streams.append(WatchStreamIndex(name: name, encoding: encoding,
                                            recordBytes: recordBytes, count: count,
                                            offset: payload.count, length: whole.count))
            payload.append(contentsOf: whole)
        }

        add("track", trackEncoding, trackRecordBytes, trackBytes)
        add("heart", heartEncoding, heartRecordBytes, heartBytes)
        add("accel", accelEncoding, accelRecordBytes, accelBytes)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let headerData = try encoder.encode(WatchSessionHeader(meta: meta, streams: streams))

        var out = Data(capacity: 12 + headerData.count + payload.count)
        out.append(contentsOf: magic)
        out.appendLE(version)
        out.appendLE(UInt32(headerData.count))
        out.append(headerData)
        out.append(payload)
        return out
    }

    /// Builds a container from in-memory samples — the test and fixture path.
    public static func encode(meta: WatchSessionMeta,
                              track: [WatchTrackSample],
                              heart: [WatchHeartSample],
                              accel: [WatchAccelSample]) throws -> Data {
        var trackBytes = Data(capacity: track.count * trackRecordBytes)
        for s in track { trackBytes.append(encodeRecord(s)) }
        var heartBytes = Data(capacity: heart.count * heartRecordBytes)
        for s in heart { heartBytes.append(encodeRecord(s)) }
        var accelBytes = Data(capacity: accel.count * accelRecordBytes)
        for s in accel { accelBytes.append(encodeRecord(s)) }
        return try assemble(meta: meta, trackBytes: trackBytes,
                            heartBytes: heartBytes, accelBytes: accelBytes)
    }

    // MARK: Decoding

    /// Reads just the header. Cheap enough to call on a file the phone has only received and
    /// not yet decided to import.
    public static func header(_ data: Data) throws -> WatchSessionHeader {
        guard isContainer(data) else { throw Error.notAContainer }
        guard data.count >= 12 else { throw Error.truncated("header prologue") }
        let bytes = [UInt8](data)
        let fileVersion = readUInt32(bytes, 4)
        guard fileVersion == version else { throw Error.unsupportedVersion(fileVersion) }
        let headerLength = Int(readUInt32(bytes, 8))
        guard bytes.count >= 12 + headerLength else { throw Error.truncated("header body") }
        let json = Data(bytes[12..<(12 + headerLength)])
        do {
            return try JSONDecoder().decode(WatchSessionHeader.self, from: json)
        } catch {
            throw Error.badHeader("\(error)")
        }
    }

    /// Reads the whole thing.
    ///
    /// Fail-soft in exactly one direction, matching the FIT and GPX parsers: a *structurally*
    /// broken file throws, because there is nothing to salvage and a half-read session would
    /// be a lie with a map on it; a stream that is short of what the header promised is read
    /// as far as it goes, because a transfer that was cut off still contains real minutes of
    /// real riding.
    public static func decode(_ data: Data) throws -> WatchSessionPayload {
        let head = try header(data)
        let bytes = [UInt8](data)
        let payloadStart = 12 + Int(readUInt32(bytes, 8))

        var track: [WatchTrackSample] = []
        var heart: [WatchHeartSample] = []
        var accel: [WatchAccelSample] = []

        for stream in head.streams {
            guard stream.recordBytes > 0 else { throw Error.badHeader("zero-width stream \"\(stream.name)\"") }
            let start = payloadStart + stream.offset
            guard start >= payloadStart, start <= bytes.count else {
                throw Error.truncated("stream \"\(stream.name)\" starts past end of file")
            }
            // As many whole records as actually arrived — see the fail-soft note above.
            let available = min(stream.length, bytes.count - start)
            let count = min(stream.count, available / stream.recordBytes)

            switch stream.encoding {
            case trackEncoding:
                track.reserveCapacity(count)
                for i in 0..<count { track.append(decodeTrack(bytes, start + i * stream.recordBytes)) }
            case heartEncoding:
                heart.reserveCapacity(count)
                for i in 0..<count { heart.append(decodeHeart(bytes, start + i * stream.recordBytes)) }
            case accelEncoding:
                accel.reserveCapacity(count)
                for i in 0..<count { accel.append(decodeAccel(bytes, start + i * stream.recordBytes)) }
            default:
                // A stream tag from a future writer. Skipping is the additive-growth promise
                // the format makes; throwing would make every new stream a breaking change.
                continue
            }
        }

        return WatchSessionPayload(meta: head.meta, track: track, heart: heart, accel: accel)
    }

    // MARK: Record decoding

    private static func decodeTrack(_ b: [UInt8], _ o: Int) -> WatchTrackSample {
        WatchTrackSample(t: readDouble(b, o),
                         lat: readDouble(b, o + 8),
                         lon: readDouble(b, o + 16),
                         speedMps: finite(readFloat(b, o + 24)),
                         horizontalAccuracyM: finite(readFloat(b, o + 28)),
                         altitudeM: finite(readFloat(b, o + 32)),
                         gapBefore: readUInt32(b, o + 36) & 1 == 1)
    }

    private static func decodeHeart(_ b: [UInt8], _ o: Int) -> WatchHeartSample {
        WatchHeartSample(t: readDouble(b, o), bpm: Double(readFloat(b, o + 8)))
    }

    private static func decodeAccel(_ b: [UInt8], _ o: Int) -> WatchAccelSample {
        WatchAccelSample(t: Double(readFloat(b, o)), magnitudeG: Double(readFloat(b, o + 4)))
    }

    private static func finite(_ v: Float) -> Double? {
        v.isFinite ? Double(v) : nil
    }

    private static func readUInt32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }

    private static func readUInt64(_ b: [UInt8], _ o: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in (0..<8).reversed() { v = v << 8 | UInt64(b[o + i]) }
        return v
    }

    private static func readFloat(_ b: [UInt8], _ o: Int) -> Float {
        Float(bitPattern: readUInt32(b, o))
    }

    private static func readDouble(_ b: [UInt8], _ o: Int) -> Double {
        Double(bitPattern: readUInt64(b, o))
    }
}

// MARK: - Little-endian append

private extension Data {
    mutating func appendLE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }

    mutating func appendLE(_ value: UInt64) {
        for i in 0..<8 { append(UInt8(truncatingIfNeeded: value >> (8 * i))) }
    }

    mutating func appendLE(_ value: Float) { appendLE(value.bitPattern) }
    mutating func appendLE(_ value: Double) { appendLE(value.bitPattern) }
}
