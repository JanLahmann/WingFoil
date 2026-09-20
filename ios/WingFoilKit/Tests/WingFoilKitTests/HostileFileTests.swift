import Foundation
import Testing
@testable import WingFoilKit

/// **Files from strangers.**
///
/// Every door in this kit reads bytes somebody else wrote. Usually that somebody is Garmin,
/// intervals.icu or the rider's own watch; sometimes it is a co-rider's export, an AirDropped
/// `.cjw`, a ZIP off a forum. The tests beside this one ask what the parsers do with a
/// *broken* file. These ask what they do with a **hostile** one — a file built to make the
/// app do something rather than to be read — and the answer each of them pins down is the
/// same: a refusal the rider can read, never a trap, a hang or a phone out of memory.
///
/// One suite rather than a few lines in each parser's own file, because the shapes here
/// recur: an attacker-supplied *count*, an attacker-supplied *offset*, an attacker-supplied
/// *ratio*. Keeping them together is what makes a new door's missing check obvious.
@Suite struct HostileFileTests {

    // MARK: - The XML doors

    /// The billion laughs: three kilobytes of file, a gigabyte of string.
    ///
    /// Written with only three levels here — the test must not actually build the gigabyte
    /// if the guard ever regresses, and three levels is already a thousand copies. What is
    /// asserted is the *refusal*, which is what makes the depth irrelevant.
    private static let entityBomb = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE gpx [
          <!ENTITY a "aaaaaaaaaa">
          <!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">
          <!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
        ]>
        <gpx version="1.1"><trk><trkseg><trkpt lat="45.87" lon="10.87">
        <time>2026-08-30T12:00:00Z</time><ele>&c;</ele>
        </trkpt></trkseg></trk></gpx>
        """.utf8)

    private static let tcxEntityBomb = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE TrainingCenterDatabase [
          <!ENTITY a "aaaaaaaaaa">
          <!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">
        ]>
        <TrainingCenterDatabase><Activities><Activity Sport="Other"><Lap><Track>
        <Trackpoint><Time>2026-08-30T12:00:00Z</Time><Position>
        <LatitudeDegrees>45.87</LatitudeDegrees><LongitudeDegrees>10.87</LongitudeDegrees>
        </Position><AltitudeMeters>&b;</AltitudeMeters></Trackpoint>
        </Track></Lap></Activity></Activities></TrainingCenterDatabase>
        """.utf8)

    /// `<trk><type>` is the one GPX element whose text the parser keeps and the app then
    /// prints, so it is where a substituted entity would surface. `file:///etc/passwd`
    /// exists on the test machine, which makes a leak visible rather than theoretical.
    private static let externalEntity = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE gpx [<!ENTITY leak SYSTEM "file:///etc/passwd">]>
        <gpx version="1.1"><trk><type>&leak;</type><trkseg>
        <trkpt lat="45.8700" lon="10.87"><time>2026-08-30T12:00:00Z</time></trkpt>
        <trkpt lat="45.8701" lon="10.87"><time>2026-08-30T12:00:01Z</time></trkpt>
        </trkseg></trk></gpx>
        """.utf8)

    @Test func aGpxThatDeclaresEntitiesIsRefusedRatherThanExpanded() {
        #expect(throws: GpxSessionParser.ParseError.self) {
            _ = try GpxSessionParser.parse(data: Self.entityBomb)
        }
    }

    @Test func aTcxThatDeclaresEntitiesIsRefusedTheSameWay() {
        #expect(throws: TcxSessionParser.ParseError.self) {
            _ = try TcxSessionParser.parse(data: Self.tcxEntityBomb)
        }
    }

    /// The external-entity half, asserted on the **outcome** rather than on the refusal.
    ///
    /// An *external* declaration is not reported to the delegate at all when resolution is
    /// off, so there is nothing to abort on and the document simply parses with the
    /// reference gone. That is the safe outcome and the one worth pinning: whatever else
    /// changes in Foundation, the contents of a file on the phone must never arrive inside
    /// a session's fields. An internal declaration — the only kind that can also be a bomb
    /// — is still refused outright by the test above.
    @Test func anExternalEntityNeverSubstitutesFileContent() throws {
        let track = try GpxSessionParser.parse(data: Self.externalEntity)
        let sport = track.capabilities.sport ?? ""
        #expect(!sport.contains("root:"))
        #expect(!sport.contains("/bin/"))
        #expect(sport.count < 64)
    }

    /// The guard is a refusal of a header no exporter writes, not a stricter schema: an
    /// ordinary GPX and an ordinary TCX still come through whole.
    @Test func theEntityRefusalCostsAnOrdinaryRecordingNothing() throws {
        let gpx = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
            <trkpt lat="45.8700" lon="10.87"><time>2026-08-30T12:00:00Z</time></trkpt>
            <trkpt lat="45.8701" lon="10.87"><time>2026-08-30T12:00:01Z</time></trkpt>
            <trkpt lat="45.8702" lon="10.87"><time>2026-08-30T12:00:02Z</time></trkpt>
            </trkseg></trk></gpx>
            """.utf8)
        #expect(try GpxSessionParser.parse(data: gpx).samples.count == 3)

        let tcx = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <TrainingCenterDatabase><Activities><Activity Sport="Other"><Lap><Track>
            <Trackpoint><Time>2026-08-30T12:00:00Z</Time><Position>
            <LatitudeDegrees>45.8700</LatitudeDegrees><LongitudeDegrees>10.87</LongitudeDegrees>
            </Position></Trackpoint>
            <Trackpoint><Time>2026-08-30T12:00:01Z</Time><Position>
            <LatitudeDegrees>45.8701</LatitudeDegrees><LongitudeDegrees>10.87</LongitudeDegrees>
            </Position></Trackpoint>
            </Track></Lap></Activity></Activities></TrainingCenterDatabase>
            """.utf8)
        #expect(try TcxSessionParser.parse(data: tcx).samples.count == 2)
    }

    // MARK: - The compression doors

    /// A gzip bomb is a small file by construction: the ratio is the weapon, not the size.
    /// Sixteen megabytes of zeroes compress to a few kilobytes, which is the same shape as
    /// the gigabytes-from-kilobytes a real one uses — and the cap is passed explicitly so
    /// the test proves the mechanism without building the gigabytes.
    @Test func aGzipBombIsRefusedAtTheCapRatherThanInflatedWhole() throws {
        let bomb = try Gzip.compress(Data(repeating: 0, count: 16 * 1024 * 1024))
        #expect(bomb.count < 128 * 1024)                    // small file, huge payload
        #expect(throws: IcuPayload.Error.tooLarge) {
            _ = try Gzip.decompress(bomb, limit: 1024 * 1024)
        }
        // …and the same bytes under an honest cap are still just a recording's worth of data.
        #expect(try Gzip.decompress(bomb).count == 16 * 1024 * 1024)
    }

    @Test func theInflationCapIsStatedRatherThanInherited() {
        // A change to either of these is a change to how much a hostile file may cost, so
        // it is a change a reader should have to make on purpose.
        #expect(ZipSizes.maxInflatedBytes == 512 * 1024 * 1024)
        #expect(ZipSizes.refusesDeclared(UInt64(ZipSizes.maxInflatedBytes) + 1))
        #expect(!ZipSizes.refusesDeclared(UInt64(ZipSizes.maxInflatedBytes)))
        // The *reservation* cap is the optimisation and stays well under it.
        #expect(ZipSizes.reservation(.max) == ZipSizes.maxReservationBytes)
    }

    // MARK: - The `.cjw` container

    /// A legal container, and the four numbers of its stream table in one place so each
    /// test below can move exactly one of them.
    private func container(trackSamples: Int = 3) throws -> Data {
        let meta = WatchSessionMeta(sessionId: "hostile", startEpoch: 1_756_555_000,
                                    utcOffsetS: 7200, durationS: Double(trackSamples),
                                    activityType: "surfingSports", producer: "test")
        let track = (0..<trackSamples).map {
            WatchTrackSample(t: Double($0), lat: 45.87 + Double($0) * 0.0001, lon: 10.87,
                             speedMps: 8)
        }
        return try WatchSessionContainer.encode(meta: meta, track: track, heart: [], accel: [])
    }

    /// Rewrites the JSON header of a container, keeping the envelope legal. The payload is
    /// left exactly where it was, which is the point: the *header* is the attacker's input.
    private func retampered(_ data: Data,
                            _ edit: (inout WatchSessionHeader) -> Void) throws -> Data {
        var head = try WatchSessionContainer.header(data)
        edit(&head)
        let bytes = [UInt8](data)
        let oldLength = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16
            | Int(bytes[11]) << 24
        let payload = data.dropFirst(12 + oldLength)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let headerData = try encoder.encode(head)
        var out = Data(data.prefix(8))
        var length = UInt32(headerData.count).littleEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(headerData)
        out.append(payload)
        return out
    }

    /// `offset: Int.max` used to overflow `payloadStart + stream.offset` — and Swift's `+`
    /// traps on overflow, which is a process death the app cannot report and the rider
    /// cannot get past except by deleting the file.
    @Test func aStreamOffsetThatWouldOverflowIsRefused() throws {
        let tampered = try retampered(try container()) { head in
            head.streams[0].offset = Int.max
        }
        #expect(throws: WatchSessionContainer.Error.self) {
            _ = try WatchSessionContainer.decode(tampered)
        }
    }

    /// `length: -1` made `available` negative, then `count` negative, then `0..<count` a
    /// trap: "Range requires lowerBound <= upperBound".
    @Test func negativeExtentsAreRefusedBeforeAnyRangeIsFormed() throws {
        for edit in [{ (h: inout WatchSessionHeader) in h.streams[0].length = -1 },
                     { (h: inout WatchSessionHeader) in h.streams[0].count = -1 },
                     { (h: inout WatchSessionHeader) in h.streams[0].offset = -1 }] {
            let tampered = try retampered(try container(), edit)
            #expect(throws: WatchSessionContainer.Error.self) {
                _ = try WatchSessionContainer.decode(tampered)
            }
        }
    }

    /// `recordBytes: 1` on a `track.v1` stream passed the old `> 0` test, and the decoder
    /// then read a 40-byte record at a 1-byte stride — off the end of the array on the last
    /// one. A known tag must state the width this build actually reads.
    @Test func aKnownStreamMustStateTheWidthThisBuildReads() throws {
        let tampered = try retampered(try container()) { head in
            head.streams[0].recordBytes = 1
            head.streams[0].count = 120
        }
        #expect(throws: WatchSessionContainer.Error.self) {
            _ = try WatchSessionContainer.decode(tampered)
        }
    }

    /// A stream tag this build has never heard of is still *skipped* rather than refused —
    /// the format's additive-growth promise — and its width is nobody's business.
    @Test func anUnknownStreamIsStillSkippedRatherThanRefused() throws {
        let tampered = try retampered(try container()) { head in
            head.streams.append(WatchStreamIndex(name: "wind", encoding: "wind.v9",
                                                 recordBytes: 3, count: 1,
                                                 offset: 0, length: 3))
        }
        let payload = try WatchSessionContainer.decode(tampered)
        #expect(payload.track.count == 3)
    }

    /// A NaN latitude is a perfectly well-formed 64-bit pattern, and it used to travel
    /// straight through into the analysis: a pin at no place, a distance of NaN, and a
    /// share card with a hole in it. A sample that cannot say where it was is not a sample.
    @Test func aNonFiniteFixIsDroppedRatherThanCarried() throws {
        var data = try container(trackSamples: 3)
        let head = try WatchSessionContainer.header(data)
        let payloadStart = data.count - head.streams.reduce(0) { $0 + $1.length }
        let latOffset = payloadStart + head.streams[0].offset
            + WatchSessionContainer.trackRecordBytes + 8      // second record's `lat`
        var nan = Double.nan.bitPattern.littleEndian
        withUnsafeBytes(of: &nan) { raw in
            for (i, byte) in raw.enumerated() { data[latOffset + i] = byte }
        }
        let payload = try WatchSessionContainer.decode(data)
        #expect(payload.track.count == 2)
        #expect(payload.track.allSatisfy { $0.lat.isFinite && $0.lon.isFinite && $0.t.isFinite })
    }
}
