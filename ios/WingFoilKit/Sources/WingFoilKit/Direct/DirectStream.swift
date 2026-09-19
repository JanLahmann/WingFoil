import Foundation

// THE WIRE FORMAT OF THE DIRECT TRANSFER. Documented in docs/transfer-format.md, which is the
// contract; `lab/tools/cjr_ref.py` is the third, plain-Python statement of the same bytes and
// this file mirrors it line for line. A number that differs from either is a bug here.
//
// The watch encodes in Monkey C, this decodes in Swift, and the reference encodes in Python.
// Three implementations of one format is two too many to keep in step by reading, so the
// worked example of §2.3 is pinned in all three (`DirectStreamTests`, `cjr_ref.py --check`,
// the watch's `WingfoilTests`).
//
// Everything is LITTLE-ENDIAN, stated rather than inherited, exactly as
// `WatchSessionContainer` already states it for the Apple Watch's `.cjw`.

/// The constants of docs/transfer-format.md §2, in one place.
public enum DirectStream {

    /// File and page-0 magic. `TrackParser.format` sniffs it, so it must not collide with
    /// FIT (`.FIT` at byte 8), with the watch container (`CJWS`) or with a leading `<`.
    public static let magic: [UInt8] = Array("CJR1".utf8)

    /// The bytes open with the magic. What `ZipWalker.classify` asks before anything else
    /// looks at a file; a page-0 payload and an archived stream answer alike.
    public static func isStream(_ data: Data) -> Bool {
        data.count >= magic.count && Array(data.prefix(magic.count)) == magic
    }
    /// Field-meaning version. A stream that states another one is refused rather than
    /// guessed at: a delta record read at the wrong stride is a plausible-looking track.
    public static let schema: UInt8 = 2
    /// Schema 1 wrote a 16-byte header without the clock offset (19 September 2026, the
    /// day the first direct session landed an hour off). Still read; never written.
    public static let legacySchema: UInt8 = 1
    public static let legacyHeaderBytes = 16
    public static let utcOffsetNone: Int16 = 0x7FFF
    /// Stream 0, one record per GPS fix, encoding `rec.v1`. Stream 1 is dev3's wrist
    /// magnitudes and gets its own encoding when it exists.
    public static let recordStream: UInt8 = 0

    public static let headerBytes = 20
    public static let keyframeTag: UInt8 = 0xFF
    public static let keyframeBytes = 22
    public static let deltaBytes = 13
    /// A gap longer than this cannot be expressed as a `dt` and forces a keyframe.
    public static let dtMax = 254
    /// Records between keyframes. A page also always opens with one, so a page that never
    /// arrives costs its own seconds and not the session.
    public static let keyframeEvery = 60
    /// Payload bytes per `Communications.transmit`. The measured ceiling, not a guess:
    /// 16 KB and a second transmit in flight both killed the watch app (docs/direct-transfer.md §5).
    public static let pageBytes = 8000
    /// The `int16` altitude that means "no reading".
    public static let altitudeNone: Int32 = 0x7FFF

    /// Keyframe positions are `int32` in 1e-7 degrees.
    public static let keyScale: Double = 1e7
    /// Delta positions are `int16` in 1e-6 degrees, so ±0.032° ≈ ±3.6 km per step.
    public static let deltaScale: Double = 1e6

    /// The extension the archive stores a direct stream under.
    public static let fileExtension = "cjr"

    // MARK: Quantisation

    // ROUNDING IS HALF AWAY FROM ZERO, EVERYWHERE, and it is spelled out rather than taken
    // off a library. Monkey C, Python and Swift disagree about what `round` means at exactly
    // .5 — Python rounds half to even, Swift's `rounded()` rounds half away from zero, Monkey
    // C's `Math.round` follows C — and a wire format whose three implementations disagree on
    // one ten-millionth of a degree produces a delta that is off by one for the rest of the
    // page. `int(x ± 0.5)` truncated is the one form all three can state.

    /// Degrees → integer units, half away from zero. `scale` is `keyScale` or `deltaScale`.
    ///
    /// Clamped rather than trapped: `Int32(_:)` on a NaN or on a number past `Int32.max` is
    /// a runtime crash in Swift, and a decoder that crashes on bad bytes is worse than one
    /// that reads a wrong position. Real latitudes and longitudes are three orders inside
    /// the clamp.
    public static func quantise(_ degrees: Double, scale: Double) -> Int32 {
        let v = degrees * scale
        guard v.isFinite else { return 0 }
        let shifted = v >= 0 ? v + 0.5 : v - 0.5
        if shifted >= Double(Int32.max) { return Int32.max }
        if shifted <= Double(Int32.min) { return Int32.min }
        return Int32(shifted)          // Swift's Int32(Double) truncates toward zero
    }

    /// The 1e-6 base a delta is measured from, out of the encoder's 1e-7 state.
    ///
    /// `(q7 ± 5) / 10` with C-style (truncating) integer division, which is what Swift's `/`
    /// on integers already does. So `base6(q7) * 10` is `q7` rounded to the nearest ten, half
    /// away from zero, and the residual the next delta carries forward is in [−5, +5] —
    /// 0.5e-6 degrees, about 5 cm, and bounded rather than accumulating.
    public static func base6(_ q7: Int32) -> Int32 {
        let shifted = q7 >= 0 ? q7 &+ 5 : q7 &- 5
        return shifted / 10
    }
}

// MARK: - Header

/// The 16-byte stream header, on page 0 only (docs/transfer-format.md §2.1).
public struct DirectStreamHeader: Sendable, Equatable {
    /// 0 for the record stream. Carried so dev3's wrist stream needs no new message.
    public var stream: UInt8
    /// `minor << 8 | fitSchema`, the same number the FIT writes as `SES_APP_VERSION`.
    public var appVersion: Int
    /// Session start, epoch seconds — the card's `KEY_START`, and half of the dedupe key.
    public var startEpochS: Int
    /// The axis the rider entered, 0…359, or −1 where he entered none.
    public var windDirDeg: Int
    /// 0 = wingfoil, the only value 0.9.x writes.
    public var discipline: Int
    public var flags: Int
    /// The watch's clock offset at start, seconds east of UTC, from schema 2 on. The
    /// recording saying so itself is the `activity` rung; without it the phone guesses
    /// from longitude, which is the solar offset and an hour out under summer time.
    public var utcOffsetS: Int?

    public init(stream: UInt8 = DirectStream.recordStream, appVersion: Int, startEpochS: Int,
                windDirDeg: Int, discipline: Int = 0, flags: Int = 0, utcOffsetS: Int? = nil) {
        self.stream = stream
        self.appVersion = appVersion
        self.startEpochS = startEpochS
        self.windDirDeg = windDirDeg
        self.discipline = discipline
        self.flags = flags
        self.utcOffsetS = utcOffsetS
    }

    /// The rider's wind axis as the rest of the app states one, or nil where he set none.
    /// `−1` is the wire's "unset" and never reaches a screen as a bearing.
    public var windDirUserDeg: Double? {
        (0...359).contains(windDirDeg) ? Double(windDirDeg) : nil
    }
}

// MARK: - Records

/// One GPS fix as the watch recorded it. The four developer fields are the FIT record's,
/// byte for byte, so `FitSchema` stays the one definition of what they mean.
public struct DirectRecord: Sendable, Equatable {
    /// Epoch seconds. Absolute in a keyframe, `dt` from the previous record in a delta.
    public var t: Int
    public var lat: Double
    public var lon: Double
    /// Doppler speed in cm/s, absolute in both record shapes.
    public var speedCms: Int
    /// Metres, or nil where the watch had none.
    public var altitudeM: Int?
    /// Beats per minute; 0 means no reading, and never reaches `RecordSample` as one.
    public var heartRate: Int
    public var foilState: Int
    public var pumpCadence: Int
    public var turnMarker: Int
    /// Rolling 0–255 counter whose only job is to defeat smart-recording collapse.
    public var tick: Int

    public init(t: Int, lat: Double, lon: Double, speedCms: Int, altitudeM: Int?,
                heartRate: Int = 0, foilState: Int = 0, pumpCadence: Int = 0,
                turnMarker: Int = 0, tick: Int = 0) {
        self.t = t
        self.lat = lat
        self.lon = lon
        self.speedCms = speedCms
        self.altitudeM = altitudeM
        self.heartRate = heartRate
        self.foilState = foilState
        self.pumpCadence = pumpCadence
        self.turnMarker = turnMarker
        self.tick = tick
    }
}

// MARK: - Errors

/// What a stream can be wrong about. Typed, and never a crash: these bytes arrive over a
/// radio from another process on another device, and a truncated page is the ordinary case.
public enum DirectStreamError: Error, CustomStringConvertible, Equatable {
    case notAStream
    case unsupportedSchema(Int)
    case truncated(String)
    case deltaBeforeKeyframe

    public var description: String {
        switch self {
        case .notAStream: "not a CleanJibe direct stream"
        case .unsupportedSchema(let v): "direct stream schema \(v) is newer than this app understands"
        case .truncated(let what): "the direct stream is truncated: \(what)"
        case .deltaBeforeKeyframe: "the direct stream opens with a delta record"
        }
    }
}

// MARK: - Decoder

/// Reads the concatenation of a stream's pages, in order — which is the archive of a stream
/// and nothing added (docs/transfer-format.md §1).
public enum DirectStreamDecoder {

    /// Cheap content sniff, the peer of `WatchSessionContainer.isContainer`.
    public static func isStream(_ data: Data) -> Bool {
        guard data.count >= DirectStream.magic.count else { return false }
        for (i, byte) in DirectStream.magic.enumerated()
        where data[data.startIndex + i] != byte { return false }
        return true
    }

    /// The header's length for the schema the bytes state: 16 for schema 1, 20 from 2.
    public static func headerLength(_ data: Data) throws -> Int {
        guard isStream(data), data.count > 4 else { throw DirectStreamError.notAStream }
        return data[data.startIndex + 4] == DirectStream.legacySchema
            ? DirectStream.legacyHeaderBytes : DirectStream.headerBytes
    }

    public static func header(_ data: Data) throws -> DirectStreamHeader {
        guard isStream(data) else { throw DirectStreamError.notAStream }
        let length = try headerLength(data)
        guard data.count >= length else {
            throw DirectStreamError.truncated("stream header")
        }
        let b = [UInt8](data.prefix(length))
        let schema = b[4]
        guard schema == DirectStream.schema || schema == DirectStream.legacySchema else {
            throw DirectStreamError.unsupportedSchema(Int(schema))
        }
        var offset: Int?
        if schema == DirectStream.schema {
            let minutes = readInt16(b, 16)
            if minutes != DirectStream.utcOffsetNone { offset = Int(minutes) * 60 }
        }
        return DirectStreamHeader(stream: b[5],
                                  appVersion: Int(readUInt16(b, 6)),
                                  startEpochS: Int(readUInt32(b, 8)),
                                  windDirDeg: Int(readInt16(b, 12)),
                                  discipline: Int(b[14]),
                                  flags: Int(b[15]),
                                  utcOffsetS: offset)
    }

    /// The whole stream.
    ///
    /// **Fail-soft in exactly one direction**, matching the FIT, GPX and watch-container
    /// parsers: a structurally broken stream throws, because a half-read session would be a
    /// lie with a map on it; a *trailing* record that is short of its own width is dropped,
    /// because a transfer cut off mid-page still contains real minutes of real riding. A
    /// delta before any keyframe is structural — nothing can be reconstructed from it.
    public static func decode(_ data: Data) throws -> (DirectStreamHeader, [DirectRecord]) {
        let head = try header(data)
        let b = [UInt8](data)
        var i = try headerLength(data)
        var out: [DirectRecord] = []
        var qlat: Int32 = 0
        var qlon: Int32 = 0
        var previous: DirectRecord?

        while i < b.count {
            if b[i] == DirectStream.keyframeTag {
                guard i + DirectStream.keyframeBytes <= b.count else {
                    throw DirectStreamError.truncated("keyframe at byte \(i)")
                }
                qlat = readInt32(b, i + 5)
                qlon = readInt32(b, i + 9)
                let altitude = readInt16(b, i + 15)
                let record = DirectRecord(
                    t: Int(readUInt32(b, i + 1)),
                    lat: Double(qlat) / DirectStream.keyScale,
                    lon: Double(qlon) / DirectStream.keyScale,
                    speedCms: Int(readUInt16(b, i + 13)),
                    altitudeM: Int32(altitude) == DirectStream.altitudeNone ? nil : Int(altitude),
                    heartRate: Int(b[i + 17]),
                    foilState: Int(b[i + 18]),
                    pumpCadence: Int(b[i + 19]),
                    turnMarker: Int(b[i + 20]),
                    tick: Int(b[i + 21]))
                i += DirectStream.keyframeBytes
                out.append(record)
                previous = record
            } else {
                guard let prev = previous else { throw DirectStreamError.deltaBeforeKeyframe }
                guard i + DirectStream.deltaBytes <= b.count else {
                    throw DirectStreamError.truncated("delta record at byte \(i)")
                }
                // The decoder moves the SAME quantised state the encoder moved, by the same
                // `Δ × 10`, so both ends hold identical integers and the error never grows.
                qlat &+= Int32(readInt16(b, i + 1)) &* 10
                qlon &+= Int32(readInt16(b, i + 3)) &* 10
                let deltaAltitude = Int(Int8(bitPattern: b[i + 7]))
                let record = DirectRecord(
                    t: prev.t + Int(b[i]),
                    lat: Double(qlat) / DirectStream.keyScale,
                    lon: Double(qlon) / DirectStream.keyScale,
                    speedCms: Int(readUInt16(b, i + 5)),
                    altitudeM: prev.altitudeM.map { $0 + deltaAltitude },
                    heartRate: Int(b[i + 8]),
                    foilState: Int(b[i + 9]),
                    pumpCadence: Int(b[i + 10]),
                    turnMarker: Int(b[i + 11]),
                    tick: Int(b[i + 12]))
                i += DirectStream.deltaBytes
                out.append(record)
                previous = record
            }
        }
        return (head, out)
    }

    // MARK: Little-endian reads

    private static func readUInt16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }

    private static func readInt16(_ b: [UInt8], _ o: Int) -> Int16 {
        Int16(bitPattern: readUInt16(b, o))
    }

    private static func readUInt32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }

    private static func readInt32(_ b: [UInt8], _ o: Int) -> Int32 {
        Int32(bitPattern: readUInt32(b, o))
    }
}

// MARK: - Encoder

/// Feeds records in, yields closed pages. `close()` yields the last one.
///
/// **Why the phone has an encoder at all.** The watch is the only thing that will ever encode
/// a stream in the field. This exists so the format can be round-tripped in a test, so a
/// fixture can be built from records rather than from a hex string, and so the arithmetic the
/// decoder undoes is written down twice in the same language. It mirrors `Encoder` in
/// `lab/tools/cjr_ref.py` statement for statement, including the order of the two checks in
/// `push` — a page that rolls over re-encodes the record as a keyframe, which is what makes
/// every page decode on its own.
public struct DirectStreamEncoder {

    private var pages: [Data] = []
    private var buffer: Data
    private var sinceKeyframe: Int
    private var state: DirectRecord?
    private var qlat: Int32 = 0
    private var qlon: Int32 = 0

    public init(header: DirectStreamHeader) {
        buffer = DirectStreamEncoder.pack(header)
        sinceKeyframe = DirectStream.keyframeEvery       // the first record keys
    }

    public static func pack(_ header: DirectStreamHeader) -> Data {
        var out = Data(capacity: DirectStream.headerBytes)
        out.append(contentsOf: DirectStream.magic)
        out.append(DirectStream.schema)
        out.append(header.stream)
        out.appendLE(UInt16(truncatingIfNeeded: header.appVersion))
        out.appendLE(UInt32(truncatingIfNeeded: header.startEpochS))
        out.appendLE(Int16(truncatingIfNeeded: header.windDirDeg))
        out.append(UInt8(truncatingIfNeeded: header.discipline))
        out.append(UInt8(truncatingIfNeeded: header.flags))
        let minutes = header.utcOffsetS.map { Int16(clamping: $0 / 60) } ?? DirectStream.utcOffsetNone
        out.appendLE(minutes)
        out.appendLE(UInt16(0))
        return out
    }

    public mutating func push(_ record: DirectRecord) {
        var encoded: Data?
        if state != nil, sinceKeyframe < DirectStream.keyframeEvery {
            encoded = delta(record)
        }
        if encoded == nil {
            encoded = keyframe(record)
            sinceKeyframe = 0
        }
        var bytes = encoded!
        if buffer.count + bytes.count > DirectStream.pageBytes {
            pages.append(buffer)
            buffer = Data()
            // Every page opens with a keyframe, so a delta that happened to land on the
            // boundary is thrown away and re-encoded.
            if bytes.first != DirectStream.keyframeTag { bytes = keyframe(record) }
            sinceKeyframe = 0
        }
        buffer.append(bytes)
        sinceKeyframe += 1
        state = record
    }

    /// The pages, the last one included. Calling it twice yields the same list.
    public mutating func close() -> [Data] {
        if !buffer.isEmpty {
            pages.append(buffer)
            buffer = Data()
        }
        return pages
    }

    /// Everything a stream's pages concatenate to — what the phone writes as `<sid>.cjr`.
    public mutating func archive() -> Data {
        var out = Data()
        for page in close() { out.append(page) }
        return out
    }

    // MARK: Record shapes

    private mutating func keyframe(_ s: DirectRecord) -> Data {
        qlat = DirectStream.quantise(s.lat, scale: DirectStream.keyScale)
        qlon = DirectStream.quantise(s.lon, scale: DirectStream.keyScale)
        var out = Data(capacity: DirectStream.keyframeBytes)
        out.append(DirectStream.keyframeTag)
        out.appendLE(UInt32(truncatingIfNeeded: s.t))
        out.appendLE(qlat)
        out.appendLE(qlon)
        out.appendLE(UInt16(clamping: s.speedCms))
        out.appendLE(Int16(truncatingIfNeeded: s.altitudeM.map { Int32($0) }
                                               ?? DirectStream.altitudeNone))
        out.append(UInt8(clamping: s.heartRate))
        out.append(UInt8(truncatingIfNeeded: s.foilState))
        out.append(UInt8(truncatingIfNeeded: s.pumpCadence))
        out.append(UInt8(truncatingIfNeeded: s.turnMarker))
        out.append(UInt8(truncatingIfNeeded: s.tick))
        return out
    }

    /// nil where a delta cannot say it: a gap over 254 s, a position jump beyond ±0.032°, an
    /// altitude jump beyond ±127 m, or altitude appearing or disappearing. The caller then
    /// writes a keyframe, which is the list docs/transfer-format.md §2.2 gives.
    private mutating func delta(_ s: DirectRecord) -> Data? {
        guard let previous = state else { return nil }
        let dt = s.t - previous.t
        guard dt >= 1, dt <= DirectStream.dtMax else { return nil }

        let dlat = Int(DirectStream.quantise(s.lat, scale: DirectStream.deltaScale))
            - Int(DirectStream.base6(qlat))
        let dlon = Int(DirectStream.quantise(s.lon, scale: DirectStream.deltaScale))
            - Int(DirectStream.base6(qlon))
        guard dlat >= -32768, dlat <= 32767, dlon >= -32768, dlon <= 32767 else { return nil }

        let dalt: Int
        switch (s.altitudeM, previous.altitudeM) {
        case (nil, nil): dalt = 0
        case (let new?, let old?): dalt = new - old
        default: return nil                       // altitude appeared or disappeared
        }
        guard dalt >= -128, dalt <= 127 else { return nil }

        qlat &+= Int32(dlat) &* 10
        qlon &+= Int32(dlon) &* 10

        var out = Data(capacity: DirectStream.deltaBytes)
        out.append(UInt8(dt))
        out.appendLE(Int16(dlat))
        out.appendLE(Int16(dlon))
        out.appendLE(UInt16(clamping: s.speedCms))
        out.append(UInt8(bitPattern: Int8(dalt)))
        out.append(UInt8(clamping: s.heartRate))
        out.append(UInt8(truncatingIfNeeded: s.foilState))
        out.append(UInt8(truncatingIfNeeded: s.pumpCadence))
        out.append(UInt8(truncatingIfNeeded: s.turnMarker))
        out.append(UInt8(truncatingIfNeeded: s.tick))
        return out
    }
}

// MARK: - Little-endian append

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLE(_ value: Int16) { appendLE(UInt16(bitPattern: value)) }

    mutating func appendLE(_ value: UInt32) {
        for i in 0..<4 { append(UInt8(truncatingIfNeeded: value >> (8 * i))) }
    }

    mutating func appendLE(_ value: Int32) { appendLE(UInt32(bitPattern: value)) }
}
