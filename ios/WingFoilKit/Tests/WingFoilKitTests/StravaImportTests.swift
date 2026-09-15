import Foundation
import Testing
@testable import WingFoilKit

/// `StravaImport` — an activity pulled from Strava, turned into the same `RawTrack` every
/// other source produces (docs/decisions.md ADR-023).
///
/// **Nothing here touches the network.** The mapper takes the decoded streams as plain value
/// types, so everything below is arithmetic on a synthetic afternoon; the client is exercised
/// separately through a stub transport (`StravaClientTests`).
///
/// The load-bearing assertion in this file is the source class. Strava has no Doppler channel
/// to give, so a Strava session must be **class (c)** — positions-only, records uncertified —
/// and it must be that for a *structural* reason rather than because some flag was set by
/// hand: the mapper writes a GPX, and `GpxSessionParser` decides the class the way it decides
/// it for every other positions-only file.
struct StravaImportTests {

    // MARK: - Fixture

    /// The same thirty minutes `HealthImportTests` uses, in Strava's shape:
    ///
    /// * 0–119 s   drifting at 1 m/s — below the flight entry speed, so not flying
    /// * 120–719 s a straight run east at 11 m/s (flight 1)
    /// * 720–725 s a 180° turn over 6 s at 8 m/s
    /// * 726–1319 s the straight run back west
    /// * 1320–1439 s stopped at 0.2 m/s — the flight ends here
    /// * 1440–1499 s **missing**: the rider paused, and Strava's elapsed clock simply jumps
    /// * 1500–1799 s riding again at 11 m/s (flight 2)
    ///
    /// Positions are integrated from heading and speed rather than written down, because a
    /// class-(c) source's speed *is* its geometry — a fixture whose positions and speeds
    /// disagreed would be testing neither.
    static func streams(withGap: Bool = true, heart: Bool = true,
                        altitude: Bool = true) -> StravaStreams {
        var time: [Double] = []
        var latlng: [[Double]] = []
        var ele: [Double] = []
        var bpm: [Double] = []
        var lat = 45.8722, lon = 10.8747
        let metresPerDegLat = 110_540.0
        let metresPerDegLon = 111_320.0 * cos(45.8722 * .pi / 180)

        for second in 0..<1800 {
            if withGap, (1440..<1500).contains(second) { continue }
            let speed: Double
            var headingDeg: Double
            switch second {
            case 0..<120: speed = 1.0; headingDeg = 90
            case 120..<720: speed = 11.0; headingDeg = 90
            case 720..<726: speed = 8.0; headingDeg = 90 + 30 * Double(second - 720)
            case 726..<1320: speed = 11.0; headingDeg = 270
            case 1320..<1440: speed = 0.2; headingDeg = 270
            default: speed = 11.0; headingDeg = 90
            }
            headingDeg = headingDeg.truncatingRemainder(dividingBy: 360)
            let radians = headingDeg * .pi / 180
            time.append(Double(second))
            latlng.append([lat, lon])
            ele.append(0.5)
            bpm.append(134 + 14 * sin(Double(second) / 90))
            lat += speed * cos(radians) / metresPerDegLat
            lon += speed * sin(radians) / metresPerDegLon
        }
        return StravaStreams(time: .init(data: time),
                             latlng: .init(data: latlng),
                             altitude: altitude ? .init(data: ele) : nil,
                             heartrate: heart ? .init(data: bpm) : nil,
                             // Requested on the wire and ignored by the mapper — the fixture
                             // carries it so that fact is actually exercised.
                             velocitySmooth: .init(data: time.map { _ in 11.0 }))
    }

    /// 2026-08-24T02:26:40Z — the fixture's own instant, spelled once.
    static let start = Date(timeIntervalSince1970: 1_787_538_400)

    static func activity(id: String = "14123456789", name: String? = "Wingfoil Torbole",
                         sportType: String? = "Windsurf",
                         utcOffsetS: Int? = 7200) -> StravaActivity {
        StravaActivity(id: id, name: name, sportType: sportType,
                       startDateUtc: "2026-08-24T02:26:40Z",
                       startDateLocal: "2026-08-24T04:26:40",
                       timezone: "(GMT+01:00) Europe/Rome",
                       utcOffsetS: utcOffsetS,
                       elapsedTimeS: 1800, movingTimeS: 1740,
                       distanceM: 17_000, startLatLng: [45.8722, 10.8747])
    }

    static func track(withGap: Bool = true, heart: Bool = true,
                      utcOffsetS: Int? = 7200) throws -> RawTrack {
        let gpx = try StravaImport.gpx(activity: activity(utcOffsetS: utcOffsetS),
                                       streams: streams(withGap: withGap, heart: heart),
                                       producer: "CleanJibe iOS test fixture (Strava)")
        return try TrackParser.parse(data: gpx)
    }

    // MARK: - Streams → samples

    @Test func mapsTheParallelStreamsOntoOneClock() throws {
        let samples = try StravaImport.samples(Self.streams())
        #expect(samples.count == 1800 - 60)
        #expect(samples[0].t == 0)
        #expect(samples.last?.t == 1799)
        #expect(samples[0].lat == 45.8722)
        #expect(samples[10].heartRate != nil)
        #expect(samples[10].altitudeM == 0.5)
    }

    /// Strava sends only the channels an activity actually has. A watch with no optical
    /// sensor sends no `heartrate`, and that is a session with no HR — not a failure.
    @Test func missingChannelsAreAbsencesRatherThanFailures() throws {
        let samples = try StravaImport.samples(Self.streams(heart: false, altitude: false))
        #expect(samples.count == 1740)
        #expect(samples.allSatisfy { $0.heartRate == nil })
        #expect(samples.allSatisfy { $0.altitudeM == nil })
    }

    @Test func unusableFixesAreDroppedAndTheClockIsNormalised() throws {
        let messy = StravaStreams(
            time: .init(data: [2, 0, 0, 1, 3, 4]),
            latlng: .init(data: [[45.87, 10.87], [45.87, 10.87], [45.87, 10.87],
                                 [0, 0],                     // the "no fix" sentinel
                                 [.nan, 10.87],              // unusable
                                 [91, 10.87]]))              // off the planet
        let samples = try StravaImport.samples(messy)
        #expect(samples.map(\.t) == [0, 2])                  // sorted, de-duplicated
    }

    @Test func anActivityWithNoPositionsOrNoClockIsRefused() {
        #expect(throws: StravaImport.ImportError.noClock) {
            try StravaImport.samples(StravaStreams(latlng: .init(data: [[45.87, 10.87]])))
        }
        #expect(throws: StravaImport.ImportError.noPositions) {
            try StravaImport.samples(StravaStreams(time: .init(data: [0, 1, 2])))
        }
    }

    // MARK: - The source class, which is the whole point

    /// **Class (c), structurally.** Strava's `velocity_smooth` is computed from the positions
    /// and then smoothed, so it is not a measurement and the file cannot prove one. The
    /// mapper writes what Strava actually has — a GPX — and the class follows from the format
    /// rather than from a flag anybody could forget to set.
    @Test func aStravaSessionIsPositionsOnlyAndUncertified() throws {
        let gpx = try StravaImport.gpx(activity: Self.activity(), streams: Self.streams(),
                                       producer: "test")
        #expect(TrackParser.format(gpx) == .gpx)

        let caps = try Self.track().capabilities
        #expect(caps.hasPosition)
        #expect(!caps.hasSpeed)                  // no Doppler channel — the uncertified mark
        #expect(caps.sourceClass == "c")
        #expect(!caps.hasAccel)                  // nothing recorded the wrist
        #expect(!caps.hasDevFields)              // nothing of ours ever reached Strava
        #expect(caps.hasHR)
        #expect(abs(caps.sampleRateHz - 1) < 0.001)
    }

    /// The speed column is still *populated* — the analysis has numbers to work with. That
    /// pair is the point of class (c): the column says there is a number, the capability says
    /// the file could not prove it was measured.
    @Test func speedIsDerivedFromThePositionsRatherThanTakenFromStrava() throws {
        let track = try Self.track()
        #expect(track.samples.allSatisfy { $0.speedMps != nil })
        // The straight run was integrated at 11 m/s and differentiating the positions gives
        // it back, whatever `velocity_smooth` claimed.
        let cruise = try #require(track.samples.first { $0.t == 400 }?.speedMps)
        #expect(abs(cruise - 11) < 0.2)
    }

    @Test func heartRateSurvivesTheRoundTripThroughTheExtension() throws {
        let track = try Self.track()
        #expect(track.capabilities.hasHR)
        #expect(track.samples.allSatisfy { $0.heartRate != nil })
        #expect(track.samples[0].heartRate.map { abs($0 - 134) <= 1 } == true)

        let none = try Self.track(heart: false)
        #expect(!none.capabilities.hasHR)
        #expect(none.samples.allSatisfy { $0.heartRate == nil })
        #expect(none.capabilities.sourceClass == "c")
    }

    /// Strava's clock is *elapsed*, so a pause is a jump in it. The jump is written as a
    /// `<trkseg>` boundary, which the parser reads as the recorder saying it stopped — the
    /// one case the dt rule alone cannot see once Strava has thinned a stream.
    @Test func aPauseBecomesADeclaredBreakRatherThanAStraightLineAcrossIt() throws {
        let track = try Self.track()
        let gaps = track.samples.enumerated().filter { $0.element.gapBefore }
        #expect(gaps.count == 1)
        #expect(gaps.first?.element.t == 1500)

        #expect(try Self.track(withGap: false).samples.allSatisfy { !$0.gapBefore })
    }

    // MARK: - The session's clock

    /// Rung 1 of `SessionIngestor.resolveUtcOffset`. Strava knows the rider's offset exactly
    /// (`utc_offset`), so the GPX states it as `+02:00` rather than as `Z` — a `Z` would
    /// state an instant and nothing about the clock, and leave the longitude guess to answer
    /// a question Strava had already answered.
    @Test func stravasOwnOffsetIsWrittenIntoTheTimestampsAndClaimedAsExact() throws {
        let stated = try Self.track(utcOffsetS: 7200)
        #expect(stated.startUtcOffsetS == 7200)
        #expect(stated.startUtcOffsetSource == .activity)
        #expect(stated.startUtcOffsetSource?.isExact == true)
        #expect(stated.startDate == Date(timeIntervalSince1970: 1_787_538_400))

        // Strip `utc_offset` and the zone name still answers — and it is the same answer.
        var noOffset = Self.activity(utcOffsetS: nil)
        #expect(noOffset.resolvedUtcOffsetS == 7200)
        // Strip both, and the file says `Z`: an instant, and no claim about any clock.
        noOffset.timezone = nil
        let gpx = try StravaImport.gpx(activity: noOffset, streams: Self.streams(),
                                       producer: "test")
        let silent = try TrackParser.parse(data: gpx)
        #expect(silent.startUtcOffsetS == nil)
        #expect(SessionIngestor.resolveUtcOffset(track: silent, fallback: nil).source
                == .longitude)
        // …and the instants themselves are unchanged, which is the point of writing the
        // offset rather than shifting the numbers.
        #expect(silent.startDate == Date(timeIntervalSince1970: 1_787_538_400))
    }

    /// The timestamp writer is the inverse of the parser's reader, and both are hand-rolled.
    /// A leap year, a year boundary and a negative offset are where that kind of arithmetic
    /// goes wrong.
    @Test func timestampsRoundTripThroughTheParsersOwnReader() throws {
        let cases: [(Double, Int, String)] = [
            (1_787_538_400, 7200, "2026-08-24T04:26:40+02:00"),
            (1_767_225_599, 0, "2025-12-31T23:59:59+00:00"),
            (1_709_164_800, -18_000, "2024-02-28T19:00:00-05:00"),
            (1_709_251_200, 0, "2024-03-01T00:00:00+00:00"),        // leap day, just after
        ]
        for (epoch, offset, expected) in cases {
            let text = StravaImport.TimestampWriter(offsetS: offset)
                .local(Date(timeIntervalSince1970: epoch))
            #expect(text == expected)
            let read = try #require(GpxSessionParser.parseTime(text))
            #expect(read.0 == Date(timeIntervalSince1970: epoch))
            #expect(read.1 == offset)
        }
    }

    /// A name with an ampersand in it is a name, not a parse error.
    @Test func activityNamesAreEscapedIntoTheDocument() throws {
        let named = StravaActivity(id: "1", name: "Wing & <foil> \"session\"",
                                   sportType: "Windsurf",
                                   startDateUtc: "2026-08-24T02:26:40Z",
                                   utcOffsetS: 7200, elapsedTimeS: 60,
                                   startLatLng: [45.8722, 10.8747])
        let gpx = try StravaImport.gpx(activity: named, streams: Self.streams(),
                                       producer: "test")
        let text = String(decoding: gpx, as: UTF8.self)
        #expect(text.contains("Wing &amp; &lt;foil&gt; &quot;session&quot;"))
        #expect(try TrackParser.parse(data: gpx).samples.count == 1740)
    }

    // MARK: - Dedupe and naming

    @Test func theDedupeKeyIsTheStartAndSpanTheLibraryWillSee() throws {
        let samples = try StravaImport.samples(Self.streams())
        let key = try #require(StravaImport.dedupeKey(activity: Self.activity(),
                                                      samples: samples))
        #expect(key.start == Date(timeIntervalSince1970: 1_787_538_400))
        #expect(key.durationS == 1799)
        // …and it is the span the ingested row actually gets, which is what makes it a key.
        let track = try Self.track()
        let span = try #require(track.samples.last?.t) - (try #require(track.samples.first?.t))
        #expect(abs(span - key.durationS) < 0.001)
    }

    @Test func theArchivedFilenameCarriesTheActivityName() {
        #expect(StravaImport.filename(for: Self.activity())
                == "14123456789_Wingfoil-Torbole_strava.gpx")
        #expect(StravaImport.filename(for: Self.activity(name: nil))
                == "14123456789_session_strava.gpx")
    }

    /// The round trip the "View on Strava" link rides on: Strava's brand guidelines require
    /// a link back to the activity, and the id it needs is the first field of the name the
    /// import wrote. Read back rather than stored in a column of its own — see
    /// `StravaImport.activityId`.
    @Test func theActivityIdReadsBackOutOfTheFilename() {
        for activity in [Self.activity(), Self.activity(name: nil)] {
            #expect(StravaImport.activityId(
                originalFilename: StravaImport.filename(for: activity)) == "14123456789")
        }
    }

    /// Every other door's filename gets no link, rather than a link to somebody else's ride.
    @Test func onlyStravasOwnFilenamesYieldAnId() {
        for other in [nil, "", "2026-08-30_nago_torbole.fit", "14123456789_ride.gpx",
                      "_strava.gpx", "notanid_wingfoil_strava.gpx",
                      "1412_3456_wing_strava.fit"] {
            #expect(StravaImport.activityId(originalFilename: other) == nil,
                    "\(other ?? "nil") should not yield a Strava id")
        }
    }

    // MARK: - The type filter

    /// Strava has no wingfoil type, so the rider picks the set — and the name rescues the
    /// activity filed under something nobody picked.
    @Test func theTypeFilterTakesWhatTheRiderChoseAndWhatTheNameSays() {
        let defaults = StravaActivityType.defaults
        #expect(defaults == [.windsurf, .kitesurf, .surfing, .workout])

        func made(_ type: String?, _ name: String?,
                  latlng: [Double]? = [45.8, 10.8], manual: Bool? = false) -> StravaActivity {
            StravaActivity(id: "1", name: name, sportType: type,
                           startDateUtc: "2026-08-24T02:26:40Z", elapsedTimeS: 600,
                           startLatLng: latlng, isManual: manual)
        }

        #expect(StravaActivityFilter.matches(made("Windsurf", "Lunch session"), types: defaults))
        #expect(StravaActivityFilter.matches(made("Workout", "Morning"), types: defaults))
        #expect(!StravaActivityFilter.matches(made("Ride", "Commute"), types: defaults))
        // The rescue: any type at all, if the rider named it.
        #expect(StravaActivityFilter.matches(made("Ride", "Wingfoil Torbole"), types: defaults))
        #expect(StravaActivityFilter.matches(made("Hike", "SUP downwinder"), types: defaults))
        // Off by default, on when asked for.
        #expect(!StravaActivityFilter.matches(made("Sail", "Regatta"), types: defaults))
        #expect(StravaActivityFilter.matches(made("Sail", "Regatta"),
                                             types: defaults.union([.sail])))
        // No recording behind it, whatever it is called.
        #expect(!StravaActivityFilter.matches(made("Windsurf", "Wing", latlng: nil),
                                              types: defaults))
        #expect(!StravaActivityFilter.matches(made("Windsurf", "Wing", latlng: [0, 0]),
                                              types: defaults))
        #expect(!StravaActivityFilter.matches(made("Windsurf", "Wing", manual: true),
                                              types: defaults))
    }

    /// Strava replaced `type` with `sport_type` and still sends both; an activity that only
    /// carries the old one must not fall through the filter.
    @Test func theDeprecatedTypeFieldIsStillRead() throws {
        let json = Data("""
            [{"id": 14123456789, "name": "Lunch", "type": "Kitesurf",
              "start_date": "2026-08-24T02:26:40Z", "start_date_local": "2026-08-24T04:26:40",
              "timezone": "(GMT+01:00) Europe/Rome", "utc_offset": 7200.0,
              "elapsed_time": 1800, "moving_time": 1740, "distance": 17000.0,
              "start_latlng": [45.8722, 10.8747], "manual": false}]
            """.utf8)
        let decoded = try JSONDecoder().decode([StravaActivity].self, from: json)
        let one = try #require(decoded.first)
        #expect(one.id == "14123456789")
        #expect(one.sportType == "Kitesurf")
        #expect(one.utcOffsetS == 7200)
        #expect(one.resolvedUtcOffsetS == 7200)
        #expect(one.durationS == 1800)
        #expect(one.hasRoute)
        #expect(one.startDate == Date(timeIntervalSince1970: 1_787_538_400))
        #expect(StravaActivityFilter.matches(one, types: .init([.kitesurf])))
    }

    /// The wire shape, decoded as it actually arrives — `key_by_type=true`, one object per
    /// channel, each with its own `data` array beside Strava's own metadata.
    @Test func theStreamsPayloadDecodesAsStravaSendsIt() throws {
        let json = Data("""
            {"time": {"data": [0, 1, 2], "series_type": "distance", "original_size": 3,
                      "resolution": "high"},
             "latlng": {"data": [[45.8722, 10.8747], [45.8722, 10.8748], [45.8723, 10.8749]],
                        "series_type": "distance", "original_size": 3, "resolution": "high"},
             "altitude": {"data": [65.2, 65.2, 65.1], "series_type": "distance"},
             "heartrate": {"data": [131, 133, 136], "series_type": "distance"},
             "velocity_smooth": {"data": [0.0, 7.6, 9.1], "series_type": "distance"}}
            """.utf8)
        let streams = try JSONDecoder().decode(StravaStreams.self, from: json)
        #expect(streams.time?.data == [0, 1, 2])
        #expect(streams.heartrate?.data == [131, 133, 136])
        #expect(streams.velocitySmooth?.data.count == 3)

        let samples = try StravaImport.samples(streams)
        #expect(samples.count == 3)
        #expect(samples[1].altitudeM == 65.2)
        #expect(samples[2].heartRate == 136)
    }

    // MARK: - All the way through the engine

    /// The engine does not know or care that this came from Strava: it sees positions and a
    /// clock, and finds the same flights and turns it finds in any other class-(c) file.
    @Test func theEngineFindsFlightsAndTurnsInAStravaActivity() throws {
        let analysis = SessionSummarizer.analyze(try Self.track())

        #expect(!analysis.capabilities.hasDoppler)       // the flag `certified` is built on
        #expect(!analysis.capabilities.hasAccel)
        #expect(analysis.capabilities.hasHR)
        #expect(analysis.engineVersion == AnalysisEngine.version)

        // Two rides either side of a 2-minute stop, and the 180° turn between them.
        #expect(analysis.flights.count >= 2)
        #expect(analysis.turns.count >= 1)
        #expect(analysis.summary.foilTimeS > 900)
        #expect((analysis.records.best2sKn ?? 0) > 18)   // 11 m/s ≈ 21 kn
    }

    // MARK: - All the way into the library

    private func makeIngestor() throws -> (SessionIngestor, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("strava-ingest-\(UUID().uuidString)/Sessions",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SessionIngestor(database: try AppDatabase.inMemory(),
                                archive: SessionArchive(root: root)), root)
    }

    /// The whole integration in one test: the sync hands `SessionIngestor` the mapped bytes
    /// and nothing else changes — same door, same ±60 s dedupe, same archive, same
    /// re-analysis on an engine bump.
    @Test func aStravaActivityImportsThroughTheOrdinaryDoor() async throws {
        let (ingestor, root) = try makeIngestor()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let gpx = try StravaImport.gpx(activity: Self.activity(), streams: Self.streams(),
                                       producer: "test")

        guard case .imported(let row) = try await ingestor.ingest(
            fitData: gpx, filename: StravaImport.filename(for: Self.activity()),
            source: .strava, utcOffsetS: 7200) else {
            Issue.record("expected a fresh import")
            return
        }
        #expect(row.importSource == "strava")
        #expect(row.sourceClass == "c")
        #expect(row.startUtcOffsetSource == UtcOffsetSource.activity.rawValue)
        #expect(row.startUtcOffsetS == 7200)
        #expect(row.flightCount ?? 0 >= 2)
        #expect(ingestor.archive.originalFormat(for: row.id) == .gpx)

        // The engine bump path — without an archived original these sessions would lose
        // every number the first time the engine changed.
        let reanalysed = try await ingestor.reanalyze(row)
        #expect(!reanalysed.capabilities.hasDoppler)
        #expect(reanalysed.capabilities.hasHR)

        // The same activity twice — an automatic pickup racing a hand-tapped import — is one
        // session, not two.
        guard case .duplicate = try await ingestor.ingest(
            fitData: gpx, filename: "again.gpx", source: .strava) else {
            Issue.record("expected the second import to be recognised")
            return
        }
        #expect(try await ingestor.allSessions().count == 1)
    }

    /// The provenance tags have to stay apart: `strava` is its own source, and merges beside
    /// the others rather than replacing one.
    @Test func stravaProvenanceStaysApartFromTheOtherSources() {
        #expect(ImportSource.strava.rawValue == "strava")
        #expect(ImportSource.strava.isNamed(in: "strava+icu"))
        #expect(!ImportSource.strava.isNamed(in: "icu"))
        #expect(!ImportSource.icu.isNamed(in: "strava"))
        // `merge` sorts, so the pair reads the same whichever door arrived first.
        #expect(SessionIngestor.merge(sources: "strava", adding: .icu) == "icu+strava")
        #expect(SessionIngestor.merge(sources: "file", adding: .strava) == "file+strava")
    }
}
