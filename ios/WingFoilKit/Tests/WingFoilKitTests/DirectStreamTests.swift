import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// **The direct transfer's wire format** (docs/transfer-format.md) and the `Direct/` path
/// that turns a stream into a `RawTrack` and then into a library row.
///
/// The worked example of §2.3 is the pin. Three implementations encode these bytes — the
/// watch in Monkey C, `lab/tools/cjr_ref.py` in Python and `DirectStreamEncoder` here — and
/// the only thing that keeps them in step is that all three are held against the same hex
/// string. It is copied out of the format document character for character below; a change
/// to it is a change to the format, and has to be made in four places on purpose.
///
/// Everything else is synthesised in-test. Nothing reads a real recording: what these tests
/// are about is that the format round-trips and that the capabilities come out honest, and
/// both are properties of the code rather than of anybody's afternoon.
@Suite struct DirectStreamTests {

    // MARK: - The worked example (docs/transfer-format.md §2.3)

    static let exampleHeader = DirectStreamHeader(appVersion: 9 * 256 + 2,
                                                  startEpochS: 1_756_556_820,
                                                  windDirDeg: 200, utcOffsetS: 7200)

    static let exampleRecords: [DirectRecord] = [
        DirectRecord(t: 1_756_556_820, lat: 45.8710000, lon: 10.8630000, speedCms: 0,
                     altitudeM: 66, heartRate: 98, foilState: 0, pumpCadence: 0,
                     turnMarker: 0, tick: 0),
        DirectRecord(t: 1_756_556_821, lat: 45.8710050, lon: 10.8630120, speedCms: 310,
                     altitudeM: 66, heartRate: 101, foilState: 1, pumpCadence: 0,
                     turnMarker: 0, tick: 1),
        DirectRecord(t: 1_756_556_822, lat: 45.8710110, lon: 10.8630250, speedCms: 640,
                     altitudeM: 65, heartRate: 104, foilState: 2, pumpCadence: 12,
                     turnMarker: 3, tick: 2),
    ]

    /// The 64 bytes docs/transfer-format.md §2.3 prints, and `lab/tools/cjr_ref.py --check`
    /// re-derives: header, keyframe, delta, delta.
    static let exampleHex =
        "434a5231" + "02" + "00" + "0209" + "14eeb268" + "c800" + "00" + "00" + "7800" + "0000"
        + "ff" + "14eeb268" + "f05b571b" + "f08f7906" + "0000" + "4200" + "62"
        + "00" + "00" + "00" + "00"
        + "01" + "0500" + "0c00" + "3601" + "00" + "65" + "01" + "00" + "00" + "01"
        + "01" + "0600" + "0d00" + "8002" + "ff" + "68" + "02" + "0c" + "03" + "02"

    static func exampleBytes() -> Data {
        var encoder = DirectStreamEncoder(header: exampleHeader)
        for record in exampleRecords { encoder.push(record) }
        return encoder.archive()
    }

    @Test func theWorkedExampleEncodesToThePinnedHex() {
        let bytes = Self.exampleBytes()
        #expect(bytes.count == 68)
        #expect(Self.hex(bytes) == Self.exampleHex)
    }

    @Test func theWorkedExampleIsOnePage() {
        var encoder = DirectStreamEncoder(header: Self.exampleHeader)
        for record in Self.exampleRecords { encoder.push(record) }
        #expect(encoder.close().count == 1)
    }

    @Test func theWorkedExampleDecodesBack() throws {
        let (header, records) = try DirectStreamDecoder.decode(Self.exampleBytes())
        #expect(header == Self.exampleHeader)
        #expect(header.windDirUserDeg == 200)
        #expect(records.count == 3)
        for (back, expected) in zip(records, Self.exampleRecords) {
            #expect(back.t == expected.t)
            #expect(abs(back.lat - expected.lat) < 0.5e-6)
            #expect(abs(back.lon - expected.lon) < 0.5e-6)
            #expect(back.speedCms == expected.speedCms)
            #expect(back.altitudeM == expected.altitudeM)
            #expect(back.heartRate == expected.heartRate)
            #expect(back.foilState == expected.foilState)
            #expect(back.pumpCadence == expected.pumpCadence)
            #expect(back.turnMarker == expected.turnMarker)
            #expect(back.tick == expected.tick)
        }
    }

    /// The committed fixture is the same 64 bytes — a file a decoder in any language can be
    /// pointed at without reading a hex string out of a document first.
    @Test func theCommittedFixtureIsTheWorkedExample() throws {
        let url = testFixturesDir.appendingPathComponent("direct/example.cjr")
        let data = try Data(contentsOf: url)
        #expect(Self.hex(data) == Self.exampleHex)
        #expect(TrackParser.format(data) == .direct)
    }

    // MARK: - Rounding

    /// Half away from zero, both signs, both scales — the one arithmetic Monkey C, Python
    /// and Swift can all state, and the reason `DirectStream.quantise` does not call
    /// `rounded()`.
    @Test func quantisingRoundsHalfAwayFromZero() {
        #expect(DirectStream.quantise(0.000_000_05, scale: 1e7) == 1)
        #expect(DirectStream.quantise(-0.000_000_05, scale: 1e7) == -1)
        #expect(DirectStream.quantise(0.000_000_15, scale: 1e7) == 2)
        #expect(DirectStream.quantise(-0.000_000_15, scale: 1e7) == -2)
        #expect(DirectStream.quantise(45.871, scale: 1e7) == 458_710_000)
        #expect(DirectStream.quantise(10.863, scale: 1e6) == 10_863_000)
        // A number that is not a position reads as one, and never as a crash: `Int32(_:)`
        // on a NaN or an infinity traps in Swift, and these bytes come off a radio.
        #expect(DirectStream.quantise(.nan, scale: 1e7) == 0)
        #expect(DirectStream.quantise(.infinity, scale: 1e7) == 0)
        #expect(DirectStream.quantise(1e30, scale: 1e7) == Int32.max)
        #expect(DirectStream.quantise(-1e30, scale: 1e7) == Int32.min)
    }

    /// `(q7 ± 5) / 10` truncating, so `base6(q) * 10` is `q` rounded to the nearest ten.
    @Test func theDeltaBaseRoundsTheSameWay() {
        #expect(DirectStream.base6(458_710_000) == 45_871_000)
        #expect(DirectStream.base6(458_710_005) == 45_871_001)
        #expect(DirectStream.base6(458_710_004) == 45_871_000)
        #expect(DirectStream.base6(-5) == -1)
        #expect(DirectStream.base6(-4) == 0)
        #expect(DirectStream.base6(4) == 0)
        #expect(DirectStream.base6(5) == 1)
    }

    // MARK: - A whole session

    /// 7 300 fixes at 1 Hz with every keyframe trigger of §2.2 in them: a 400 s pause, a
    /// position jump past ±0.032°, an altitude gap, and a heart rate that only appears part
    /// way through.
    static func syntheticSession() -> (DirectStreamHeader, [DirectRecord]) {
        let start = 1_756_556_820
        let header = DirectStreamHeader(appVersion: 9 * 256 + 2, startEpochS: start,
                                        windDirDeg: 225)
        var records: [DirectRecord] = []
        var t = start
        var lat = 45.8722
        var lon = 10.8747
        for i in 0..<7300 {
            // 6–14 m/s, a slow oscillation: fast enough to fly, varied enough that the
            // flight segmenter and the record windows both have something to chew on.
            let speed = 10 + 4 * sin(Double(i) / 25)
            if i == 3000 {
                t += 400                      // a pause: dt over 254 s forces a keyframe
            } else if i > 0 {
                t += 1
            }
            if i == 5000 { lon += 0.5 }       // a jump past ±0.032°
            lon += speed / (111_320 * cos(45.8722 * .pi / 180))
            lat += 0.000_001 * sin(Double(i) / 60)
            // Altitude drops out for a minute in the middle, which is the one keyframe
            // trigger a delta genuinely cannot express.
            let altitude: Int? = (1200..<1260).contains(i) ? nil : (i > 5000 ? 200 : 1)
            records.append(DirectRecord(t: t, lat: lat, lon: lon,
                                        speedCms: Int((speed * 100).rounded()),
                                        altitudeM: altitude,
                                        heartRate: i < 400 ? 0 : 140,
                                        foilState: speed > 9 ? 2 : 0,
                                        pumpCadence: speed > 9 ? 0 : 40,
                                        turnMarker: i % 600 == 0 ? 1 : 0,
                                        tick: i % 256))
            }
        return (header, records)
    }

    @Test func aWholeSessionRoundTripsThroughItsPages() throws {
        let (header, records) = Self.syntheticSession()
        var encoder = DirectStreamEncoder(header: header)
        for record in records { encoder.push(record) }
        let pages = encoder.close()

        // Nine pages for 65 KB was the estimate; 7 300 records is a little over that.
        #expect(pages.count > 1)
        for page in pages { #expect(page.count <= DirectStream.pageBytes) }

        var archive = Data()
        for page in pages { archive.append(page) }
        let (back, decoded) = try DirectStreamDecoder.decode(archive)
        #expect(back == header)
        #expect(decoded.count == records.count)

        for (a, b) in zip(records, decoded) {
            #expect(a.t == b.t)
            // **The position budget, stated exactly.** A delta lands the position on the
            // 1e-6 grid, which is half a micro-degree of error, and the keyframe it was
            // measured from sat on the 1e-7 grid, whose last digit rides along unchanged
            // for the rest of the run. So a micro-degree in the worst case, about eleven
            // centimetres, and bounded rather than accumulating: the carried digit is a
            // constant, not a sum. Both ends hold the identical integers, which is the
            // property that actually matters.
            #expect(abs(a.lat - b.lat) <= 1e-6)
            #expect(abs(a.lon - b.lon) <= 1e-6)
            #expect(a.speedCms == b.speedCms)
            #expect(a.altitudeM == b.altitudeM)
            #expect(a.heartRate == b.heartRate)
            #expect(a.foilState == b.foilState)
            #expect(a.pumpCadence == b.pumpCadence)
            #expect(a.turnMarker == b.turnMarker)
            #expect(a.tick == b.tick)
        }
    }

    /// Every page decodes on its own, which is what makes a page that never arrives cost its
    /// own seconds and not the session. Page 0 opens with the 16-byte header, every later
    /// page with a keyframe.
    @Test func everyPageOpensWithAKeyframe() throws {
        let (header, records) = Self.syntheticSession()
        var encoder = DirectStreamEncoder(header: header)
        for record in records { encoder.push(record) }
        let pages = encoder.close()

        #expect(Array(pages[0].prefix(4)) == DirectStream.magic)
        #expect(pages[0][pages[0].startIndex + DirectStream.headerBytes] == DirectStream.keyframeTag)
        for page in pages.dropFirst() {
            #expect(page[page.startIndex] == DirectStream.keyframeTag)
            // …and therefore reads back on its own, with page 0's header in front of it.
            var standalone = DirectStreamEncoder.pack(header)
            standalone.append(page)
            let (_, records) = try DirectStreamDecoder.decode(standalone)
            #expect(!records.isEmpty)
        }
    }

    /// A keyframe every 60 records, and on every case §2.2 lists.
    @Test func keyframesLandWhereTheFormatSaysTheyDo() {
        let (header, records) = Self.syntheticSession()
        var encoder = DirectStreamEncoder(header: header)
        for record in records { encoder.push(record) }
        var archive = Data()
        for page in encoder.close() { archive.append(page) }

        var index = DirectStream.headerBytes
        var recordIndex = 0
        var sinceKeyframe = 0
        while index < archive.count {
            let isKeyframe = archive[archive.startIndex + index] == DirectStream.keyframeTag
            if isKeyframe {
                sinceKeyframe = 0
            } else {
                sinceKeyframe += 1
                #expect(sinceKeyframe < DirectStream.keyframeEvery)
            }
            // The pause, the jump and the altitude gap all have to be keyframes.
            if [0, 3000, 5000, 1200, 1260].contains(recordIndex) { #expect(isKeyframe) }
            index += isKeyframe ? DirectStream.keyframeBytes : DirectStream.deltaBytes
            recordIndex += 1
        }
        #expect(recordIndex == records.count)
    }

    // MARK: - Bad bytes

    @Test func foreignBytesAreNotAStream() {
        #expect(!DirectStreamDecoder.isStream(Data()))
        #expect(!DirectStreamDecoder.isStream(Data("<gpx/>".utf8)))
        #expect(throws: DirectStreamError.notAStream) {
            try DirectStreamDecoder.header(Data("CJWS".utf8))
        }
    }

    /// A schema-1 stream, the shape the first field test wrote, still reads; its header is
    /// 16 bytes and carries no clock offset, so the phone guesses the zone as before.
    @Test func aSchemaOneStreamStillDecodesWithoutAnOffset() throws {
        let v1 = Self.data(hex: "434a5231" + "01" + "00" + "0209" + "14eeb268" + "c800" + "00"
                           + "00" + String(Self.exampleHex.dropFirst(40)))
        let (header, records) = try DirectStreamDecoder.decode(v1)
        #expect(header.utcOffsetS == nil)
        #expect(header.startEpochS == 1_756_556_820)
        #expect(records.count == 3)
        let track = try DirectStreamParser.parse(data: v1)
        #expect(track.startUtcOffsetSource != .activity)
    }

    @Test func aFutureSchemaIsRefusedRatherThanGuessedAt() {
        var bytes = Self.exampleBytes()
        bytes[bytes.startIndex + 4] = 99
        #expect(throws: DirectStreamError.unsupportedSchema(99)) {
            try DirectStreamDecoder.decode(bytes)
        }
    }

    /// A page cut off mid-record throws rather than inventing a fix, and never traps: these
    /// bytes arrive over a radio and a short page is the ordinary case.
    @Test func truncatedBytesThrowRatherThanCrash() {
        let bytes = Self.exampleBytes()
        // A cut inside the header, and a cut inside any record after it.
        for length in (0..<DirectStream.headerBytes) {
            #expect(throws: (any Error).self) {
                try DirectStreamDecoder.decode(Data(bytes.prefix(length)))
            }
        }
        // A whole number of records is a legal short stream — the header, then a keyframe,
        // then a delta. Anything between two of those boundaries is a torn record.
        let h = DirectStream.headerBytes
        let whole = [h: 0, h + 22: 1, h + 35: 2, h + 48: 3]
        for length in (DirectStream.headerBytes..<bytes.count) where whole[length] == nil {
            #expect(throws: DirectStreamError.self) {
                try DirectStreamDecoder.decode(Data(bytes.prefix(length)))
            }
        }
        for (length, count) in whole {
            let (_, records) = try! DirectStreamDecoder.decode(Data(bytes.prefix(length)))
            #expect(records.count == count)
        }
    }

    @Test func aStreamThatOpensWithADeltaIsRefused() {
        var bytes = DirectStreamEncoder.pack(Self.exampleHeader)
        bytes.append(contentsOf: [UInt8](repeating: 1, count: DirectStream.deltaBytes))
        #expect(throws: DirectStreamError.deltaBeforeKeyframe) {
            try DirectStreamDecoder.decode(bytes)
        }
    }

    // MARK: - The page message (§3)

    @Test func aPageMessageDecodesFromABytearray() throws {
        let payload: [String: Any] = ["cjr": 1, "sid": 1_756_556_820, "st": 0, "p": 3,
                                      "n": 0, "b": Data([1, 2, 3, 4])]
        let page = try DirectPage(payload: payload)
        #expect(page.sessionStartEpochS == 1_756_556_820)
        #expect(page.stream == 0)
        #expect(page.index == 3)
        #expect(page.pageCount == 0)
        #expect(!page.isLast)
        #expect(page.bytes == Data([1, 2, 3, 4]))
        #expect(page.ack["cjrAck"] as? Int == 3)
        #expect(page.ack["cjrSid"] as? Int == 1_756_556_820)
        #expect(page.ack["cjrSt"] as? Int == 0)
        // Flat: no value in the message is an array or a dictionary (19 September 2026).
        #expect(page.ack.values.allSatisfy { $0 is Int })
    }

    /// The fenix 7 and the fenix 5 Plus predate `ByteArray`, so a page from one is an array
    /// of Numbers, one byte each.
    @Test func aPageMessageDecodesFromAnArrayOfNumbers() throws {
        let payload: [String: Any] = ["cjr": 1, "sid": 1_756_556_820, "st": 0, "p": 12,
                                      "n": 13, "e": 1, "b": [255, 0, 7, 128]]
        let page = try DirectPage(payload: payload)
        #expect(page.bytes == Data([255, 0, 7, 128]))
        #expect(page.pageCount == 13)
        #expect(page.isLast)
    }

    // MARK: - The fenix 5 Plus packed page (0.9.18-dev1)

    /// **Four payload bytes per 32-bit Number**, little-endian within the word, with `f` and
    /// `bl` on the message saying so. One byte per Number is what 0.9.14-dev2 sent, and
    /// `PhoneLink.estimateBytes` prices a Number at five wire bytes — so an 8 000 B page cost
    /// 40 KB and no pre-6.0.0 watch was ever going to carry one.
    @Test func aPackedPageUnpacksFourBytesPerNumber() throws {
        // 0x04030201, 0x08070605, then one word holding a single byte.
        let words: [Any] = [0x04030201, 0x08070605, 0x09]
        let payload: [String: Any] = ["cjr": 1, "sid": 1_756_556_820, "st": 1, "p": 0,
                                      "n": 2, "f": DirectPage.packedFlag, "bl": 9,
                                      "b": words]
        let page = try DirectPage(payload: payload)
        #expect(page.stream == 1)
        #expect(page.bytes == Data([1, 2, 3, 4, 5, 6, 7, 8, 9]))
    }

    /// A Monkey C Number is signed, so a word whose top byte is ≥ 0x80 arrives negative.
    /// The bit pattern is what matters and both signs give the same one.
    @Test func aPackedWordSurvivesItsSignBit() throws {
        let page = try DirectPage(payload: ["cjr": 1, "sid": 1_756_556_820, "st": 1, "p": 0,
                                            "n": 1, "f": 1, "bl": 4,
                                            "b": [Int(Int32.min)]])
        #expect(page.bytes == Data([0x00, 0x00, 0x00, 0x80]))
    }

    @Test func aPackedPageThatLiesAboutItsLengthIsRefused() throws {
        func message(_ length: Any?) -> [String: Any] {
            var out: [String: Any] = ["cjr": 1, "sid": 1_756_556_820, "st": 1, "p": 0,
                                      "n": 1, "f": 1, "b": [0x04030201, 0x08070605]]
            if let length { out["bl"] = length }
            return out
        }
        // Eight bytes in two words: five through eight are the only honest claims.
        for length in [5, 6, 7, 8] {
            #expect(try DirectPage(payload: message(length)).bytes.count == length)
        }
        for length in [0, 4, 9, -1] {
            #expect(throws: CompanionDecodeError.notAnInteger(key: "b")) {
                try DirectPage(payload: message(length))
            }
        }
        // And a page that says it is packed without saying how long it is cannot be
        // unpacked at all: guessing would invent up to three trailing zeros.
        #expect(throws: CompanionDecodeError.missingKey("bl")) {
            try DirectPage(payload: message(nil))
        }
    }

    /// A whole page, packed and unpacked, is the page.
    @Test func aPackedPageRoundTripsAtEveryRemainder() throws {
        let (header, records) = Self.syntheticSession()
        var encoder = DirectStreamEncoder(header: header)
        for record in records { encoder.push(record) }
        for page in encoder.close() {
            for trim in 0..<4 {
                let bytes = page.prefix(page.count - trim)
                var words: [Any] = []
                for offset in stride(from: 0, to: bytes.count, by: 4) {
                    var word: UInt32 = 0
                    for i in 0..<4 where offset + i < bytes.count {
                        word |= UInt32(bytes[bytes.startIndex + offset + i]) << (8 * i)
                    }
                    words.append(Int(Int32(bitPattern: word)))
                }
                let message: [String: Any] = ["cjr": 1, "sid": 1_756_556_820, "st": 0,
                                              "p": 0, "n": 1, "f": 1, "bl": bytes.count,
                                              "b": words]
                #expect(try DirectPage(payload: message).bytes == Data(bytes))
            }
        }
    }

    @Test func aBadPageMessageIsRefusedWhole() {
        #expect(throws: CompanionDecodeError.notADictionary) { try DirectPage(payload: "cjr") }
        #expect(throws: CompanionDecodeError.unsupportedSchemaVersion(2)) {
            try DirectPage(payload: ["cjr": 2, "sid": 1_756_556_820, "st": 0, "p": 0,
                                     "n": 1, "b": Data([1])])
        }
        #expect(throws: CompanionDecodeError.missingKey("b")) {
            try DirectPage(payload: ["cjr": 1, "sid": 1_756_556_820, "st": 0, "p": 0, "n": 1])
        }
        // A Number outside 0…255 with no `f` on the message is a packing this build was not
        // told about, not a byte — the page is refused rather than truncated into nonsense.
        #expect(throws: CompanionDecodeError.notAnInteger(key: "b")) {
            try DirectPage(payload: ["cjr": 1, "sid": 1_756_556_820, "st": 0, "p": 0,
                                     "n": 1, "b": [70_000]])
        }
        // A 1970 start is a watch whose clock never got a fix, not a session.
        #expect(throws: CompanionDecodeError.outOfRange(key: "sid", value: 0)) {
            try DirectPage(payload: ["cjr": 1, "sid": 0, "st": 0, "p": 0, "n": 1,
                                     "b": Data([1])])
        }
    }

    /// The need list goes out on every completed stream, empty when nothing is missing —
    /// the empty list is what tells the watch it may free the stream.
    @Test func theNeedListIsCappedAndAlwaysSent() {
        let none = DirectPage.need(sessionStartEpochS: 7, stream: 0, pages: [])
        #expect(none["cjrNeed"] as? String == "")
        #expect(none["cjrSid"] as? Int == 7)
        let many = DirectPage.need(sessionStartEpochS: 7, stream: 0,
                                   pages: Array(0..<100))
        let list = try? #require(many["cjrNeed"] as? String)
        #expect(list?.split(separator: ",").count == DirectPage.maxNeed)
        #expect(DirectPage.need(sessionStartEpochS: 7, stream: 0, pages: [1, 4])["cjrNeed"]
                as? String == "1,4")
    }

    // MARK: - The stream as a RawTrack

    @Test func parsesIntoARawTrackWithHonestCapabilities() throws {
        let (header, records) = Self.syntheticSession()
        var encoder = DirectStreamEncoder(header: header)
        for record in records { encoder.push(record) }
        let track = try DirectStreamParser.parse(data: encoder.archive())
        let caps = track.capabilities

        #expect(caps.hasSpeed)                   // the receiver's own Doppler channel
        #expect(caps.hasPosition)
        #expect(caps.hasHR)                      // it appears at record 400
        #expect(caps.hasDevFields)               // the four record fields of docs/fit-schema.md
        #expect(!caps.hasAccel)                  // the wrist stream is not here yet
        #expect(!caps.hasWatchLaps)
        #expect(caps.sampleRateHz == 1)
        #expect(caps.discipline == "wingfoil")
        // The class follows the capabilities and nothing here invents a letter.
        #expect(caps.sourceClass == "a")

        #expect(track.startDate == Date(timeIntervalSince1970: Double(header.startEpochS)))
        #expect(track.samples.count == records.count)
        #expect(track.samples[0].t == 0)
        #expect(track.laps.isEmpty)
        // 0 bpm is the wire's "no reading" and never reaches the engine as a heart rate.
        #expect(track.samples[0].heartRate == nil)
        #expect(track.samples[500].heartRate == 140)
        // The odometer the watch does not send, filled with the engine's own arithmetic.
        #expect((track.samples.last?.distanceM ?? 0) > 10_000)
        #expect(track.samples[0].distanceM == 0)
        // The wind axis the rider set, in the field the FIT parser puts `wind_dir_user` in.
        #expect(track.watchSummary.windDirUserDeg == 225)
        #expect(track.watchSummary.windDirAutoDeg == nil)
        // The four developer fields survive the wire.
        #expect(track.samples[600].turnMarker == 1)
        #expect(track.samples.contains { ($0.pumpCadence ?? 0) > 0 })
        #expect(track.samples[10].tick == 10)
    }

    @Test func anUnsetWindAxisIsAbsentRatherThanMinusOne() throws {
        var header = Self.exampleHeader
        header.windDirDeg = -1
        var encoder = DirectStreamEncoder(header: header)
        for record in Self.exampleRecords { encoder.push(record) }
        let track = try DirectStreamParser.parse(data: encoder.archive())
        #expect(track.watchSummary.windDirUserDeg == nil)
    }

    @Test func anEmptyStreamIsNotASession() throws {
        let bytes = DirectStreamEncoder.pack(Self.exampleHeader)
        #expect(throws: DirectStreamParser.ParseError.self) {
            try DirectStreamParser.parse(data: bytes)
        }
    }

    /// The engine reads it like any other source: the door is a format, and nothing past
    /// `RawTrack` knows these bytes crossed a radio.
    @Test func theEngineAnalysesADirectSession() throws {
        let (header, records) = Self.syntheticSession()
        var encoder = DirectStreamEncoder(header: header)
        for record in records { encoder.push(record) }
        let track = try TrackParser.parse(data: encoder.archive())
        let analysis = SessionSummarizer.analyze(track)
        #expect(analysis.summary.flightCount > 0)
        #expect(analysis.summary.foilTimeS > 0)
        #expect(analysis.summary.distanceKm > 1)
    }

    // MARK: - Dedupe (ADR-013)

    private func makeIngestor() throws -> (SessionIngestor, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-direct-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SessionIngestor(database: try AppDatabase.inMemory(),
                                archive: SessionArchive(root: root)), root)
    }

    private func sessionBytes() -> Data {
        let (header, records) = Self.syntheticSession()
        var encoder = DirectStreamEncoder(header: header)
        for record in records { encoder.push(record) }
        return encoder.archive()
    }

    /// The card holds the afternoon's place; the stream that follows fills the same row.
    /// **The door, not the parser.** Every file the app imports — the inbox's `.cjr`
    /// exactly as much as a hand-picked FIT — goes through `SessionIngestor.ingestContainer`,
    /// which asks `ZipWalker.classify` what the bytes are first. The first real stream
    /// (19 September 2026) parsed perfectly and was dropped there as "no FIT found", because
    /// every test above went through the parser. This one goes through the door.
    @Test func aDirectStreamImportsThroughTheOrdinaryFileDoor() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let data = sessionBytes()
        guard case .track(let payload) = ZipWalker.classify(data) else {
            Issue.record("a direct stream must classify as a track, not as ignored")
            return
        }
        #expect(payload == data)

        let summary = await ingestor.ingestContainer(data: data, name: "1756556820.cjr",
                                                     source: .watchDirect)
        #expect(summary.found == 1)
        #expect(summary.imported == 1)
        #expect(summary.failed.isEmpty)
        let sessions = try await ingestor.allSessions()
        #expect(sessions.count == 1)
        let row = try #require(sessions.first)
        #expect(row.importSource == "watchdirect")
        #expect(row.sourceClass == "a")
        #expect(ingestor.archive.originalFormat(for: row.id) == .direct)
    }

    @Test func aDirectStreamFillsTheCardsProvisionalRow() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let data = sessionBytes()
        let track = try DirectStreamParser.parse(data: data)
        let start = try #require(track.startDate)
        let duration = (track.samples.last?.t ?? 0) - (track.samples.first?.t ?? 0)

        let card = try CompanionSummary(payload: CompanionTests.payload(
            start: Int(start.timeIntervalSince1970), duration: Int(duration.rounded())))
        guard case .provisional(let placed) = try await ingestor.ingest(card: card) else {
            Issue.record("expected the card to place a provisional row")
            return
        }
        #expect(placed.isProvisional)

        guard case .imported(let row) = try await ingestor.ingest(
            fitData: data, filename: "session.cjr", source: .watchDirect) else {
            Issue.record("expected the stream to fill the row")
            return
        }
        #expect(row.id == placed.id)                       // the same row, not a second one
        #expect(!row.isProvisional)
        #expect(row.importSource == "watch+watchdirect")
        #expect(row.sourceClass == "a")
        #expect(try await ingestor.allSessions().count == 1)
    }

    /// And the FIT that follows the stream takes the row over in turn — same id, sources
    /// merged, the thinner copy replaced in place.
    @Test func aLaterFitReplacesTheDirectRowInPlace() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let data = sessionBytes()
        guard case .imported(let direct) = try await ingestor.ingest(
            fitData: data, filename: "session.cjr", source: .watchDirect) else {
            Issue.record("expected the stream to import")
            return
        }
        #expect(direct.importSource == "watchdirect")

        // The same afternoon, as a FIT. Its own start and duration are what the dedupe key
        // compares, so a stream built on the FIT's clock and span collides with it by the
        // ±60 s rule rather than by luck.
        let fit = try #require(allFixtureFITs().first)
        let fitData = try Data(contentsOf: fit)
        let fitTrack = try FitSessionParser.parse(data: fitData)
        let fitStart = try #require(fitTrack.startDate)
        let fitDuration = (fitTrack.samples.last?.t ?? 0) - (fitTrack.samples.first?.t ?? 0)

        let (ingestor2, root2) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root2.deletingLastPathComponent()) }
        let onTheFitsClock = Self.streamBytes(startEpoch: Int(fitStart.timeIntervalSince1970),
                                              seconds: Int(fitDuration.rounded()))
        guard case .imported(let onClock) = try await ingestor2.ingest(
            fitData: onTheFitsClock, filename: "session.cjr", source: .watchDirect) else {
            Issue.record("expected the shifted stream to import")
            return
        }

        guard case .imported(let replaced) = try await ingestor2.ingest(
            fitData: fitData, filename: fit.lastPathComponent, source: .icu,
            icuActivityId: "i4242") else {
            Issue.record("expected the FIT to take the direct row over")
            return
        }
        #expect(replaced.id == onClock.id)
        #expect(replaced.importSource == "icu+watchdirect")
        #expect(replaced.icuActivityId == "i4242")
        #expect(try await ingestor2.allSessions().count == 1)

        // …and a second copy of that FIT is an ordinary duplicate again.
        let again = try await ingestor2.ingest(fitData: fitData,
                                               filename: fit.lastPathComponent,
                                               source: .gdpr)
        guard case .duplicate = again else {
            Issue.record("expected the second FIT to dedupe")
            return
        }
    }

    /// A stream does not step aside for itself: the same pages arriving twice is one row and
    /// no second analysis.
    @Test func theSameStreamTwiceIsADuplicate() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let data = sessionBytes()
        _ = try await ingestor.ingest(fitData: data, filename: "a.cjr", source: .watchDirect)
        let second = try await ingestor.ingest(fitData: data, filename: "a.cjr",
                                               source: .watchDirect)
        guard case .duplicate = second else {
            Issue.record("expected the second stream to dedupe")
            return
        }
        #expect(try await ingestor.allSessions().count == 1)
    }

    @Test func theDoorIsNamedInTheRidersWords() {
        #expect(ImportSource.watchDirect.rawValue == "watchdirect")
        #expect(ImportSource.watchDirect.libraryFilterLabel == "Garmin watch, direct")
        #expect(SessionProvenance.line(importSource: "watchdirect") == "Garmin watch, direct")
        // …and it is not the summary card, which is a different event with a different label.
        #expect(!ImportSource.watch.isNamed(in: "watchdirect"))
        #expect(!ImportSource.watchDirect.isNamed(in: "watch"))
        #expect(ImportSource.watchDirect.isNamed(in: "icu+watchdirect"))
        // The FIT is nearer the water than the account, so the line names the watch.
        #expect(SessionProvenance.line(importSource: "icu+watchdirect") == "Garmin watch, direct")
    }

    // MARK: - Helpers

    /// A plain 1 Hz stream of `seconds + 1` fixes, no pause and no jump — for the dedupe
    /// tests, where what matters is the start and the span rather than the shape.
    static func streamBytes(startEpoch: Int, seconds: Int) -> Data {
        var encoder = DirectStreamEncoder(
            header: DirectStreamHeader(appVersion: 0x0902, startEpochS: startEpoch,
                                       windDirDeg: 225))
        var lat = 45.8722
        var lon = 10.8747
        for i in 0...max(0, seconds) {
            let speed = 10 + 4 * sin(Double(i) / 25)
            lon += speed / (111_320 * cos(45.8722 * .pi / 180))
            lat += 0.000_001 * sin(Double(i) / 60)
            encoder.push(DirectRecord(t: startEpoch + i, lat: lat, lon: lon,
                                      speedCms: Int((speed * 100).rounded()),
                                      altitudeM: 1, heartRate: 140,
                                      foilState: speed > 9 ? 2 : 0, pumpCadence: 0,
                                      turnMarker: 0, tick: i % 256))
        }
        return encoder.archive()
    }

    static func data(hex: String) -> Data {
        var out = Data(capacity: hex.count / 2)
        var chars = Array(hex)
        while chars.count >= 2 {
            out.append(UInt8(String(chars[0...1]), radix: 16)!)
            chars.removeFirst(2)
        }
        return out
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
