import Foundation
import Testing
@testable import WingFoilKit

/// The GPX door (engine 0.9.0), and the honesty that has to come through it with the data.
///
/// The Swift parser mirrors `lab/src/wingfoil_lab/gpx.py`; the numbers are held to the lab's
/// by `GoldenTests` against `fixtures/goldens/2026-08-30-1407_nago-torbole.expected.json`.
/// What is asserted *here* is the behaviour a golden cannot express: what the parser does
/// with a malformed point, where a segment break comes from, which timestamps state a clock
/// — and, above all, that a derived speed is never presented as a measured one.
@Suite struct GpxParseTests {

    private static let head = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1" \
        xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
        """

    private func doc(_ body: String) -> Data {
        Data("\(Self.head)\(body)</gpx>".utf8)
    }

    private func point(lat: Double, lon: Double = 10.87, time: String? = "2026-08-30T12:00:00Z",
                       ele: Double? = nil, hr: Int? = nil) -> String {
        var inner = ""
        if let ele { inner += "<ele>\(ele)</ele>" }
        if let time { inner += "<time>\(time)</time>" }
        if let hr {
            inner += "<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>\(hr)"
                + "</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>"
        }
        return "<trkpt lat=\"\(lat)\" lon=\"\(lon)\">\(inner)</trkpt>"
    }

    /// `n` points a second apart walking north — a track with a speed to derive.
    private func line(_ n: Int, startSecond: Int = 0, stepDeg: Double = 0.0001,
                      hr: Int? = nil) -> String {
        (0..<n).map { i in
            let second = startSecond + i
            let stamp = String(format: "2026-08-30T12:%02d:%02dZ", second / 60, second % 60)
            return point(lat: 45.86 + Double(i) * stepDeg, time: stamp, hr: hr)
        }.joined()
    }

    // MARK: - The source class

    @Test func aMinimalGpxBecomesATrack() throws {
        let track = try GpxSessionParser.parse(data: doc("<trk><trkseg>\(line(3))</trkseg></trk>"))
        #expect(track.samples.count == 3)
        #expect(track.samples.map(\.t) == [0, 1, 2])
        // ~0.0001° of latitude is ~11 m, walked in a second.
        #expect(track.samples.allSatisfy { ($0.speedMps ?? 0) > 10 && ($0.speedMps ?? 0) < 12 })
        #expect(track.capabilities.sampleRateHz == 1)
    }

    /// THE invariant of source class (c): a derived number, and a flag that says so.
    ///
    /// `speedMps` is populated (the analysis has something to work with) and `hasSpeed` is
    /// false (the file never measured it). That pair is what makes `sourceClass` "c", which
    /// is what every surface reads to label these speed records uncertified.
    @Test func theSpeedChannelIsNotADopplerClaim() throws {
        let track = try GpxSessionParser.parse(data: doc("<trk><trkseg>\(line(5))</trkseg></trk>"))
        let caps = track.capabilities
        #expect(track.samples.allSatisfy { $0.speedMps != nil })
        #expect(caps.hasSpeed == false)
        #expect(caps.sourceClass == "c")
        #expect(caps.hasPosition)
        #expect(caps.hasDevFields == false)
        #expect(caps.hasAccel == false)
        #expect(track.accel.isEmpty)
        #expect(track.laps.isEmpty)
        #expect(track.watchSummary.isEmpty)
    }

    /// Every phase of the analysis is a function of time, so a point that cannot say when
    /// it happened is not a degraded sample — it is not a sample.
    @Test func aPointWithoutATimeOrACoordinateIsSkipped() throws {
        let body = "<trk><trkseg>"
            + point(lat: 45.86)
            + point(lat: 45.8601, time: nil)
            + "<trkpt><time>2026-08-30T12:00:01Z</time></trkpt>"
            + point(lat: 45.8602, time: "2026-08-30T12:00:02Z")
            + "</trkseg></trk>"
        let track = try GpxSessionParser.parse(data: doc(body))
        #expect(track.samples.map(\.t) == [0, 2])
    }

    @Test func aDocumentWithNoUsablePointsThrowsRatherThanReturningAnEmptySession() {
        #expect(throws: GpxSessionParser.ParseError.self) {
            _ = try GpxSessionParser.parse(data: doc("<trk><trkseg></trkseg></trk>"))
        }
        #expect(throws: GpxSessionParser.ParseError.self) {
            _ = try GpxSessionParser.parse(data: Data("not xml at all".utf8))
        }
    }

    // MARK: - Extensions

    @Test func heartRateComesOffTheTrackPointExtension() throws {
        let withHr = try GpxSessionParser.parse(
            data: doc("<trk><trkseg>\(line(4, hr: 142))</trkseg></trk>"))
        #expect(withHr.capabilities.hasHR)
        #expect(withHr.samples.compactMap(\.heartRate) == [142, 142, 142, 142])

        let without = try GpxSessionParser.parse(
            data: doc("<trk><trkseg>\(line(4))</trkseg></trk>"))
        #expect(without.capabilities.hasHR == false)
        #expect(without.samples.allSatisfy { $0.heartRate == nil })
    }

    @Test func elevationSurvivesForTheBarometerRule() throws {
        let body = "<trk><trkseg>"
            + point(lat: 45.86, ele: 66.6)
            + point(lat: 45.8601, time: "2026-08-30T12:00:01Z", ele: 65.1)
            + "</trkseg></trk>"
        let track = try GpxSessionParser.parse(data: doc(body))
        #expect(track.samples.compactMap(\.altitudeM) == [66.6, 65.1])
    }

    // MARK: - Structure

    /// A `<trkseg>` boundary is the recorder saying it stopped. The two sides here abut in
    /// time, so the dt-aware gap rule alone would see one continuous motion; the parser's
    /// `gapBefore` mark is what keeps them apart, and `TrackCleaner` ORs it into its own
    /// rule so the cleaned track really is two segments.
    @Test func segmentsAreJoinedAndTheJoinIsAGap() throws {
        let body = "<trk><trkseg>\(line(4))</trkseg>"
            + "<trkseg>\(line(4, startSecond: 4, stepDeg: 0.0002))</trkseg></trk>"
        let track = try GpxSessionParser.parse(data: doc(body))
        #expect(track.samples.count == 8)
        #expect(track.samples.map(\.gapBefore) == [false, false, false, false,
                                                   true, false, false, false])

        let clean = TrackCleaner.clean(track)
        #expect(clean.samples.count == 8)              // the spike filter resets on the seam
        #expect(clean.segments.map(\.count) == [4, 4])
        #expect(clean.samples[4].gapBefore)
        // Each segment's speed is its own: the second walks twice as fast, and no sample
        // straddles the join.
        let first = clean.samples[0..<4].compactMap(\.positionalMps).max() ?? 0
        let second = clean.samples[4..<8].compactMap(\.positionalMps).min() ?? 0
        #expect(first * 1.7 < second)
    }

    /// Two `<trk>`s are two activities, not two halves of one.
    @Test func onlyTheFirstTrackIsAnalysed() throws {
        let body = "<trk><name>morning</name><trkseg>\(line(3))</trkseg></trk>"
            + "<trk><name>afternoon</name><trkseg>\(line(5, startSecond: 600))</trkseg></trk>"
        let track = try GpxSessionParser.parse(data: doc(body))
        #expect(track.samples.count == 3)
    }

    // MARK: - Time zones

    /// `Z` says *when*, never *what the rider's clock read*. The parser therefore states no
    /// offset and `SessionIngestor.resolveUtcOffset` drops to the longitude rung of the
    /// 0.8.2 ladder — labelled as the guess it is, which is the common GPX case and the
    /// reason engine 0.9.1 records the rung at all.
    @Test func aZTimestampStatesAnInstantAndNoClock() throws {
        let track = try GpxSessionParser.parse(data: doc("<trk><trkseg>\(line(3))</trkseg></trk>"))
        #expect(track.startUtcOffsetS == nil)
        #expect(track.startUtcOffsetSource == nil)
        let rung = SessionIngestor.resolveUtcOffset(track: track, fallback: nil)
        #expect(rung.offset == 3600)
        #expect(rung.source == .longitude)
        #expect(track.startDate == Date(timeIntervalSince1970: 1_788_091_200))
    }

    /// `+02:00` is the exporter naming the local clock. Where a guess and an answer
    /// disagree, the answer wins — and here they do, by an hour of DST.
    @Test func aStatedOffsetBeatsTheLongitudeGuess() throws {
        let body = "<trk><trkseg>"
            + point(lat: 45.86, time: "2026-08-30T14:00:00+02:00")
            + point(lat: 45.8601, time: "2026-08-30T14:00:01+02:00")
            + "</trkseg></trk>"
        let track = try GpxSessionParser.parse(data: doc(body))
        #expect(track.startUtcOffsetS == 7200)
        // The file said so, so it ranks with a FIT's `activity` message, not with a guess.
        #expect(track.startUtcOffsetSource == .activity)
        let rung = SessionIngestor.resolveUtcOffset(track: track, fallback: nil)
        #expect(rung.offset == 7200)
        #expect(rung.source == .activity)
        // The instant is still the instant, exactly as a FIT's is.
        #expect(track.startDate == Date(timeIntervalSince1970: 1_788_091_200))
    }

    @Test func timestampShapesTheParserAccepts() {
        let epoch = Date(timeIntervalSince1970: 1_788_091_200)      // 2026-08-30T12:00:00Z
        #expect(GpxSessionParser.parseTime("2026-08-30T12:00:00Z")?.0 == epoch)
        #expect(GpxSessionParser.parseTime("2026-08-30T12:00:00Z")?.1 == nil)
        #expect(GpxSessionParser.parseTime("2026-08-30T14:00:00+02:00")?.0 == epoch)
        #expect(GpxSessionParser.parseTime("2026-08-30T14:00:00+02:00")?.1 == 7200)
        #expect(GpxSessionParser.parseTime("2026-08-30T09:00:00-0300")?.1 == -10800)
        // No zone designator: UTC by the GPX schema, and no claim about a clock.
        #expect(GpxSessionParser.parseTime("2026-08-30T12:00:00")?.0 == epoch)
        #expect(GpxSessionParser.parseTime("2026-08-30T12:00:00")?.1 == nil)
        #expect(GpxSessionParser.parseTime("2026-08-30T12:00:00.500Z")?.0
                == epoch.addingTimeInterval(0.5))
        #expect(GpxSessionParser.parseTime("not a time") == nil)
        #expect(GpxSessionParser.parseTime("") == nil)
    }

    // MARK: - Routing

    @Test func theDoorPicksTheParserFromTheBytes() throws {
        let gpx = doc("<trk><trkseg>\(line(3))</trkseg></trk>")
        #expect(GpxSessionParser.isGpx(gpx))
        #expect(TrackParser.format(gpx) == .gpx)
        #expect(try TrackParser.parse(data: gpx).capabilities.sourceClass == "c")

        let fitURL = try #require(allFixtureFITs().first)
        let fit = try Data(contentsOf: fitURL)
        #expect(GpxSessionParser.isGpx(fit) == false)
        #expect(TrackParser.format(fit) == .fit)
        #expect(GpxSessionParser.isGpx(Data()) == false)
        #expect(GpxSessionParser.isGpx(Data("<html><body>no</body></html>".utf8)) == false)
    }

    // MARK: - The fixture

    /// The GPX fixture is the bundled CIQ recording with the channels a GPX cannot carry
    /// removed (`lab/tools/fit_to_gpx.py`), so positions and clock survive exactly and only
    /// the derived channels move. The two goldens are where "how much" is measured; this is
    /// where "the same afternoon" is.
    @Test func theConvertedFixtureDescribesTheSameAfternoon() throws {
        let gpxURL = try #require(findFixtureTrack(stem: "2026-08-30-1407_nago-torbole"))
        let fitURL = try #require(
            findFixtureTrack(stem: "2026-08-30-1407_nago-torbole-windsurfen_ciq"))
        let gpx = try TrackParser.parse(url: gpxURL)
        let fit = try TrackParser.parse(url: fitURL)

        #expect(gpx.capabilities.sourceClass == "c")
        #expect(fit.capabilities.sourceClass == "a")
        #expect(gpx.startDate == fit.startDate)
        // Every GPX point is a FIT record that carried a fix; six of the 646 did not.
        let fixes = fit.samples.filter { $0.lat != nil && $0.lon != nil }
        #expect(gpx.samples.count == fixes.count)
        #expect(gpx.samples.count == 640)
        for (a, b) in zip(gpx.samples, fixes) {
            #expect(abs((a.lat ?? 0) - (b.lat ?? 0)) < 1e-6)
            #expect(abs((a.lon ?? 0) - (b.lon ?? 0)) < 1e-6)
        }
        // …and the two agree about the clock from opposite ends of the ladder: the FIT's
        // `activity` message says +2 h outright, the GPX gets +1 h from longitude alone.
        #expect(fit.startUtcOffsetS == 7200)
        #expect(fit.startUtcOffsetSource == .activity)
        #expect(gpx.startUtcOffsetS == nil)
        // The pair is the whole argument for engine 0.9.1: same afternoon, same rider, two
        // offsets an hour apart, and only the provenance tells a reader which to believe.
        let rung = SessionIngestor.resolveUtcOffset(track: gpx, fallback: nil)
        #expect(rung.offset == 3600)
        #expect(rung.source == .longitude)
    }
}
