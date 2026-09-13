import Foundation
import Testing
@testable import WingFoilKit

/// The TCX door — the one format that is not one input class.
///
/// The Swift parser mirrors `lab/src/wingfoil_lab/tcx.py`; the numbers are held to the lab's
/// by `GoldenTests` against the two `2026-08-30-1407_nago-torbole-{speed,nospeed}` goldens.
/// What is asserted *here* is the behaviour a golden cannot express, and above all the rule
/// that makes this format different from every other: one element,
/// `Extensions/TPX/Speed`, decides whether the speed records may be called certified.
@Suite struct TcxParseTests {

    private static let head = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase \
        xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" \
        xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
        """

    private func doc(_ body: String) -> Data {
        Data("\(Self.head)\(body)</TrainingCenterDatabase>".utf8)
    }

    private func activity(_ laps: String) -> String {
        "<Activities><Activity Sport=\"Other\"><Id>2026-08-30T12:00:00Z</Id>"
            + "\(laps)</Activity></Activities>"
    }

    private func lap(_ tracks: String, start: String = "2026-08-30T12:00:00Z") -> String {
        "<Lap StartTime=\"\(start)\"><TotalTimeSeconds>10.0</TotalTimeSeconds>"
            + "<DistanceMeters>120.0</DistanceMeters>\(tracks)</Lap>"
    }

    private func track(_ points: String) -> String { "<Track>\(points)</Track>" }

    private func point(lat: Double?, lon: Double? = 10.87,
                       time: String? = "2026-08-30T12:00:00Z",
                       ele: Double? = nil, hr: Int? = nil, speed: Double? = nil) -> String {
        var inner = ""
        if let time { inner += "<Time>\(time)</Time>" }
        if let lat, let lon {
            inner += "<Position><LatitudeDegrees>\(lat)</LatitudeDegrees>"
                + "<LongitudeDegrees>\(lon)</LongitudeDegrees></Position>"
        }
        if let ele { inner += "<AltitudeMeters>\(ele)</AltitudeMeters>" }
        if let hr { inner += "<HeartRateBpm><Value>\(hr)</Value></HeartRateBpm>" }
        if let speed {
            inner += "<Extensions><ns3:TPX><ns3:Speed>\(speed)</ns3:Speed>"
                + "</ns3:TPX></Extensions>"
        }
        return "<Trackpoint>\(inner)</Trackpoint>"
    }

    /// `n` points a second apart walking north — a track with a speed to derive.
    private func line(_ n: Int, startSecond: Int = 0, stepDeg: Double = 0.0001,
                      hr: Int? = nil, speed: Double? = nil) -> String {
        (0..<n).map { i in
            let second = startSecond + i
            let stamp = String(format: "2026-08-30T12:%02d:%02dZ", second / 60, second % 60)
            return point(lat: 45.86 + Double(i) * stepDeg, time: stamp, hr: hr, speed: speed)
        }.joined()
    }

    private func simple(_ n: Int = 5, hr: Int? = nil, speed: Double? = nil) -> Data {
        doc(activity(lap(track(line(n, hr: hr, speed: speed)))))
    }

    // MARK: - The class rule

    /// No stated speed: the field is populated by differentiation, the capability is not.
    ///
    /// The same invariant `GpxParseTests` states, reached by the other XML door. `hasSpeed`
    /// false is what makes `sourceClass` "c", which is what `LibraryQueries.certified`,
    /// `ShareCard` and `SessionDisplay.sourceClassNote` read to mark the records uncertified.
    @Test func aTcxWithoutTpxSpeedIsClassC() throws {
        let t = try TcxSessionParser.parse(data: simple(5))
        #expect(t.capabilities.hasSpeed == false)
        #expect(t.capabilities.sourceClass == "c")
        #expect(t.capabilities.hasPosition)
        #expect(t.capabilities.hasDevFields == false)
        #expect(t.accel.isEmpty)
        // ~0.0001° of latitude is ~11 m, walked in a second — the GPX module's arithmetic.
        #expect(t.samples.allSatisfy { ($0.speedMps ?? 0) > 10 && ($0.speedMps ?? 0) < 12 })
    }

    /// `Extensions/TPX/Speed` is the receiver's own measurement, so the file certifies.
    /// The one thing a TCX can say that a GPX cannot, and the whole reason this format
    /// needed a rule of its own rather than being filed under "XML, therefore class (c)".
    @Test func aTcxWithTpxSpeedIsClassB() throws {
        let t = try TcxSessionParser.parse(data: simple(5, speed: 6.25))
        #expect(t.capabilities.hasSpeed)
        #expect(t.capabilities.sourceClass == "b")
        #expect(t.samples.map(\.speedMps) == Array(repeating: 6.25, count: 5))
    }

    /// A class-(b) TCX's speed is the file's, never a differentiation of its positions. The
    /// points below walk ~11 m/s and the file says 3.0; if the parser ever silently preferred
    /// its own arithmetic the session would report a speed nobody recorded.
    @Test func theStatedSpeedIsCarriedThroughUntouched() throws {
        let t = try TcxSessionParser.parse(data: simple(4, speed: 3.0))
        #expect(t.samples.allSatisfy { $0.speedMps == 3.0 })
    }

    /// The capability is a question about the *file*, not about coverage: a speed on one
    /// point and none on the rest is a channel with holes in it, which is what a FIT with
    /// dropped samples is. The rows without one carry nil and `TrackCleaner` drops them.
    @Test func oneStatedSpeedMakesTheWholeFileClassB() throws {
        let body = track(point(lat: 45.86, speed: 4.0)
            + point(lat: 45.8601, time: "2026-08-30T12:00:01Z")
            + point(lat: 45.8602, time: "2026-08-30T12:00:02Z"))
        let t = try TcxSessionParser.parse(data: doc(activity(lap(body))))
        #expect(t.capabilities.sourceClass == "b")
        #expect(t.samples.map { $0.speedMps != nil } == [true, false, false])
    }

    /// Fail-soft, and a negative speed is not a measurement of anything — either way the
    /// file has said nothing, and the session falls back to class (c).
    @Test func aNegativeSpeedIsNotASpeed() throws {
        let body = track(point(lat: 45.86, speed: -1)
            + point(lat: 45.8601, time: "2026-08-30T12:00:01Z", speed: -1))
        let t = try TcxSessionParser.parse(data: doc(activity(lap(body))))
        #expect(t.capabilities.sourceClass == "c")
    }

    // MARK: - Shape

    @Test func aMinimalTcxBecomesATrack() throws {
        let t = try TcxSessionParser.parse(data: simple(3))
        #expect(t.samples.count == 3)
        #expect(t.samples.map(\.t) == [0, 1, 2])
        #expect(t.capabilities.sampleRateHz == 1)
        #expect(t.laps.count == 1)
        #expect(t.laps.first?.totalTimeS == 10.0)
        #expect(t.laps.first?.distanceM == 120.0)
    }

    @Test func aTrackpointWithoutATimeOrAPositionIsNotASample() throws {
        let body = track(point(lat: 45.86)
            + point(lat: 45.8601, time: nil)
            + point(lat: nil, lon: nil, time: "2026-08-30T12:00:01Z", hr: 140)
            + point(lat: 45.8602, time: "2026-08-30T12:00:02Z"))
        let t = try TcxSessionParser.parse(data: doc(activity(lap(body))))
        #expect(t.samples.map(\.t) == [0, 2])
    }

    /// `<Value>` means heart rate only inside `<HeartRateBpm>`; TCX reuses the tag for a
    /// lap's average and maximum, which are not per-sample facts.
    @Test func heartRateAndAltitudeComeOffTheTrackpoint() throws {
        let body = track(point(lat: 45.86, ele: 66.6, hr: 142)
            + point(lat: 45.8601, time: "2026-08-30T12:00:01Z", ele: 65.1, hr: 143))
        let t = try TcxSessionParser.parse(data: doc(activity(lap(body))))
        #expect(t.capabilities.hasHR)
        #expect(t.samples.map(\.heartRate) == [142, 143])
        #expect(t.samples.map(\.altitudeM) == [66.6, 65.1])
    }

    /// The two container levels mean different things, and only one of them is a stop.
    /// A `<Lap>` is a marker the rider pressed and the board kept moving through it; a
    /// second `<Track>` is the recorder having stopped, which is what a `<trkseg>` boundary
    /// says in a GPX — so that is the join `gapBefore` marks.
    @Test func aSecondTrackIsAGapAndASecondLapIsNot() throws {
        let two = try TcxSessionParser.parse(data: doc(activity(
            lap(track(line(4)))
            + lap(track(line(4, startSecond: 4, stepDeg: 0.0002)),
                  start: "2026-08-30T12:00:04Z"))))
        #expect(two.samples.map(\.gapBefore) == [false, false, false, false,
                                                 true, false, false, false])
        #expect(two.laps.count == 2)
        #expect(two.capabilities.hasWatchLaps)

        let one = try TcxSessionParser.parse(data: doc(activity(lap(track(line(8))))))
        #expect(one.samples.allSatisfy { !$0.gapBefore })
        #expect(one.capabilities.hasWatchLaps == false)
    }

    /// Two `<Activity>`s are two sessions, not two halves of one — the rule the GPX parser
    /// applies to several `<trk>`s, one level up.
    @Test func onlyTheFirstActivityIsRead() throws {
        let body = "<Activities>"
            + "<Activity Sport=\"Other\"><Id>morning</Id>\(lap(track(line(3))))</Activity>"
            + "<Activity Sport=\"Other\"><Id>afternoon</Id>"
            + "\(lap(track(line(5, startSecond: 120))))</Activity></Activities>"
        let t = try TcxSessionParser.parse(data: doc(body))
        #expect(t.samples.count == 3)
    }

    /// TCX admits Running | Biking | Other, so every watersport session is `Other`. Filing
    /// that as the sport would turn "this file cannot say" into a claim a watersport gate
    /// would then act on.
    @Test func theSportAttributeIsNotReadAsASport() throws {
        let t = try TcxSessionParser.parse(data: simple(3))
        #expect(t.capabilities.sport == nil)
        #expect(t.capabilities.discipline == nil)
    }

    // MARK: - The clock

    @Test func aZTimestampStatesAnInstantAndNoClock() throws {
        let t = try TcxSessionParser.parse(data: simple(3))
        #expect(t.startUtcOffsetS == nil)
        let rung = SessionIngestor.resolveUtcOffset(track: t, fallback: nil)
        #expect(rung.offset == 3600)          // lon 10.87° → round(10.87/15) = 1 h
        #expect(rung.source == .longitude)
    }

    @Test func aStatedOffsetRanksWithTheFilesOwnAnswer() throws {
        let body = track(point(lat: 45.86, time: "2026-08-30T14:00:00+02:00")
            + point(lat: 45.8601, time: "2026-08-30T14:00:01+02:00"))
        let t = try TcxSessionParser.parse(data: doc(activity(lap(body))))
        #expect(t.startUtcOffsetS == 7200)
        #expect(t.startUtcOffsetSource == .activity)
    }

    // MARK: - The door

    @Test func theSnifferReadsContentNotNames() throws {
        #expect(TcxSessionParser.isTcx(simple(2)))
        #expect(TcxSessionParser.isTcx(Data("<?xml version=\"1.0\"?><gpx/>".utf8)) == false)
        #expect(TcxSessionParser.isTcx(Data()) == false)
        #expect(TcxSessionParser.isTcx(Data("<html><body>no</body></html>".utf8)) == false)
        // And the one door every caller comes through picks the right parser from the bytes.
        #expect(TrackParser.format(simple(2)) == .tcx)
        #expect(TrackParser.format(Data("<?xml version=\"1.0\"?><gpx/>".utf8)) == .gpx)
    }

    // MARK: - The fixtures

    /// The two TCX fixtures are the bundled CIQ recording converted twice
    /// (`lab/tools/fit_to_tcx.py`), differing by one element: the speed-bearing one keeps the
    /// FIT's Doppler channel in `TPX/Speed`, the other omits it. Same positions, same clock,
    /// same rider — so every difference between their goldens is the source class and
    /// nothing else, which is the experiment the pair exists to run.
    @Test func theTwoConvertedFixturesDifferByOneElement() throws {
        let fastURL = try #require(findFixtureTrack(stem: "2026-08-30-1407_nago-torbole-speed"))
        let slowURL = try #require(
            findFixtureTrack(stem: "2026-08-30-1407_nago-torbole-nospeed"))
        let fitURL = try #require(
            findFixtureTrack(stem: "2026-08-30-1407_nago-torbole-windsurfen_ciq"))
        let fast = try TrackParser.parse(url: fastURL)
        let slow = try TrackParser.parse(url: slowURL)
        let fit = try TrackParser.parse(url: fitURL)

        #expect(fast.capabilities.sourceClass == "b")
        #expect(slow.capabilities.sourceClass == "c")
        #expect(fast.samples.count == 640)
        #expect(slow.samples.count == 640)
        #expect(fast.startDate == slow.startDate)
        #expect(fast.startDate == fit.startDate)

        // The positions are the same file twice; only the speed channel moved.
        for (a, b) in zip(fast.samples, slow.samples) {
            #expect(a.lat == b.lat)
            #expect(a.lon == b.lon)
        }
        // The speed-bearing one is the FIT's own channel: every one of the 640 fixes.
        let fixes = fit.samples.filter { $0.lat != nil && $0.lon != nil }
        #expect(fast.samples.count == fixes.count)
        for (a, b) in zip(fast.samples, fixes) where b.speedMps != nil {
            #expect(abs((a.speedMps ?? 0) - (b.speedMps ?? 0)) < 5e-4)
        }
    }

    /// The speedless TCX and the GPX are the same afternoon with its speed channel removed,
    /// in the two XML formats. They must land on the *same* derived speed to the last digit
    /// — the whole claim of sharing `GpxSessionParser.segmentSpeed` rather than writing the
    /// arithmetic twice.
    @Test func theSpeedlessTcxAndTheGpxDeriveTheSameSpeeds() throws {
        let tcxURL = try #require(
            findFixtureTrack(stem: "2026-08-30-1407_nago-torbole-nospeed"))
        let gpxURL = try #require(findFixtureTrack(stem: "2026-08-30-1407_nago-torbole"))
        let tcx = try TrackParser.parse(url: tcxURL)
        let gpx = try TrackParser.parse(url: gpxURL)
        #expect(tcx.samples.count == gpx.samples.count)
        for (a, b) in zip(tcx.samples, gpx.samples) {
            #expect(abs((a.speedMps ?? 0) - (b.speedMps ?? 0)) < 1e-9)
        }
    }
}
