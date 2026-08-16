import Foundation
import Testing
@testable import WingFoilKit

/// The phase-5 presentation layer: the help catalogue's completeness, the share card's
/// content, the list-row thumbnail geometry, PB detection and the widget snapshot.
///
/// All of it is pure, and all of it is the sort of code where a mistake is invisible in a
/// screenshot — a thumbnail that silently stretches, a card that prints "0.00 kn" where it
/// means "unknown", a confetti burst on the first import.
@Suite struct PresentationTests {

    // MARK: - Help catalogue

    /// The reason the topic id is an enum: a `?` button on a card cannot compile against a
    /// topic that does not exist, and this asserts the other half — that no case ships
    /// without content.
    @Test func everyHelpTopicIDHasWrittenContent() {
        for id in HelpTopicID.allCases {
            let topic = HelpCatalog.topic(id)
            #expect(topic.id == id)
            #expect(!topic.title.isEmpty, "\(id.rawValue) has no title")
            #expect(!topic.summary.isEmpty, "\(id.rawValue) has no summary")
            #expect(!topic.body.isEmpty, "\(id.rawValue) has no body")
            #expect(topic.body.allSatisfy { $0.count > 40 },
                    "\(id.rawValue) has a stub paragraph")
            #expect(topic.items.allSatisfy { !$0.term.isEmpty && !$0.detail.isEmpty },
                    "\(id.rawValue) has an empty item")
        }
    }

    @Test func helpCatalogueHasNoDuplicatesAndNoDanglingLinks() {
        let ids = HelpCatalog.topics.map(\.id)
        #expect(Set(ids).count == ids.count, "a topic is declared twice")
        #expect(Set(ids) == Set(HelpTopicID.allCases))
        for topic in HelpCatalog.topics {
            #expect(!topic.related.contains(topic.id), "\(topic.id.rawValue) links to itself")
            for link in topic.related {
                #expect(HelpTopicID.allCases.contains(link),
                        "\(topic.id.rawValue) links to a missing topic")
            }
        }
    }

    /// Every section in the index must have something under it, and every topic must be
    /// reachable from the index.
    @Test func helpSectionsPartitionTheCatalogue() {
        let grouped = HelpCatalog.sections.flatMap { HelpCatalog.topics(in: $0) }
        #expect(grouped.count == HelpCatalog.topics.count)
        for section in HelpCatalog.sections {
            #expect(!HelpCatalog.topics(in: section).isEmpty)
        }
    }

    @Test func helpSearchMatchesBodyAndItems() {
        #expect(HelpCatalog.search("").count == HelpCatalog.topics.count)
        // "no-go zone" only appears in the wind topic's body.
        let wind = HelpCatalog.search("no-go zone")
        #expect(wind.map(\.id) == [.windAxis])
        // "bear-away" only appears in the turn-type topic's items.
        #expect(HelpCatalog.search("bear-away").contains { $0.id == .turnTypes })
        #expect(HelpCatalog.search("zzzznothing").isEmpty)
    }

    @Test func helpTopicLookupByRawStringRoundTrips() {
        #expect(HelpCatalog.topic(id: "foilPct")?.id == .foilPct)
        #expect(HelpCatalog.topic(id: "not-a-topic") == nil)
    }

    // MARK: - Share card

    private func sampleRow(sourceClass: String = "b") -> SessionRow {
        var row = SessionRow(id: "s1",
                             startDate: Date(timeIntervalSince1970: 1_785_000_000),
                             durationS: 5400, sourceClass: sourceClass)
        row.foilPct = 62.4
        row.foilTimeS = 3370
        row.flightCount = 23
        row.longestFlightS = 184
        row.longestFlightM = 1420
        row.best2sKn = 21.37
        row.distanceKm = 34.2
        row.jibes = 30
        row.jibesFlewThrough = 9
        row.turnsFlewThrough = 9
        row.turnsTouchdown = 9
        row.turnsFellIn = 12
        return row
    }

    @Test func shareCardCarriesTheHeadlineStats() {
        let stats = ShareCardStats.make(row: sampleRow(), title: "Torbole",
                                        timeZone: TimeZone(identifier: "UTC")!)
        #expect(stats.title == "Torbole")
        let keys = stats.stats.map(\.key)
        // Always exactly four: the card's 2 x 2 block is fixed-size artwork.
        #expect(keys == ["foilPct", "flights", "longestFlight", "best2s"])
        #expect(stats.stats[0].value == "62%")
        #expect(stats.stats[1].value == "23")
        #expect(stats.stats[2].value == "3 m")
        #expect(stats.stats[2].caption == "1.42 km")
        #expect(stats.stats[3].value == "21.37 kn")
        #expect(stats.turnLine == "30 jibes · 9 flew · 9 touch · 12 fell")
        #expect(stats.disclaimer == nil)
    }

    /// The card is an image, so "not measured" has to be printed, not left to an optional
    /// binding — a card claiming "0.00 kn" would be a lie with a share sheet attached.
    @Test func shareCardPrintsPlaceholdersRatherThanZero() {
        var row = SessionRow(id: "s2", startDate: Date(), durationS: 600, sourceClass: "c")
        row.flightCount = nil
        let stats = ShareCardStats.make(row: row, title: "Session")
        #expect(stats.stats.allSatisfy { !$0.value.contains("0.00") })
        #expect(stats.stats.first { $0.key == "best2s" }?.value == "—")
        #expect(stats.stats.first { $0.key == "foilPct" }?.value == "—")
        // No turn data at all ⇒ no tally line, and still exactly four stat cells.
        #expect(stats.turnLine == nil)
        #expect(stats.stats.count == 4)
    }

    /// "9 flew" alone does not say out of how many, so the jibe count is prefixed — but
    /// only when the session actually classified jibes.
    @Test func shareCardTurnLineOmitsTheJibeCountWhenThereIsNone() {
        var row = sampleRow()
        row.jibes = nil
        #expect(ShareCardStats.make(row: row, title: "x").turnLine
                == "9 flew · 9 touch · 12 fell")
    }

    @Test func shareCardDisclaimsUncertifiedSources() {
        let stats = ShareCardStats.make(row: sampleRow(sourceClass: "c"), title: "Session")
        #expect(stats.disclaimer != nil)
    }

    @Test func shareCardShapesAreTheDocumentedPixelSizes() {
        #expect(ShareCardStats.Shape.portrait.size == (1080, 1350))
        #expect(ShareCardStats.Shape.square.size == (1080, 1080))
    }

    // MARK: - Thumbnail geometry

    /// A synthetic out-and-back reach: 400 m east, then back, with the outbound leg flown.
    private func syntheticTrack(points: Int = 400) -> RawTrack {
        var track = RawTrack()
        let lat0 = 45.87, lon0 = 10.87
        // ~111.32 km per degree of longitude at the equator, times cos(lat).
        let metresPerDegLon = 111_320 * cos(lat0 * .pi / 180)
        for i in 0..<points {
            let t = Double(i)
            var sample = RecordSample(t: t, timestamp: Date(timeIntervalSince1970: t))
            let along = i < points / 2 ? Double(i) : Double(points - i)
            sample.lat = lat0
            sample.lon = lon0 + (along * 2) / metresPerDegLon
            sample.speedMps = i < points / 2 ? 10 : 2
            track.samples.append(sample)
        }
        return track
    }

    @Test func thumbnailNormalizesIntoAUnitBoxAndKeepsAspect() {
        let track = syntheticTrack()
        let flights = [FlightRecord(Flight(startT: 0, endT: 199, distM: 400, maxKn: 20))]
        let thumb = TrackThumbnail.make(track: track, flights: flights)

        #expect(!thumb.points.isEmpty)
        #expect(thumb.points.count <= TrackThumbnail.maxPoints + 8)
        #expect(thumb.points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        // The track is 400 m wide and (almost) zero high: aspect preservation must put it
        // in a horizontal band across the middle, not stretch it over the full height.
        let ys = thumb.points.map(\.y)
        #expect((ys.max()! - ys.min()!) < 0.05, "a straight line was stretched vertically")
        let xs = thumb.points.map(\.x)
        #expect(xs.min()! < 0.01 && xs.max()! > 0.99, "the long axis must fill the box")
        #expect(ys.allSatisfy { abs($0 - 0.5) < 0.05 }, "the short axis must be centred")
    }

    @Test func thumbnailSplitsRunsAtThePhaseChange() {
        let track = syntheticTrack()
        let flights = [FlightRecord(Flight(startT: 0, endT: 199, distM: 400, maxKn: 20))]
        let runs = TrackThumbnail.make(track: track, flights: flights).runs
        #expect(runs.count >= 2, "flying and off-foil must be separate runs")
        #expect(runs.contains { $0.flying })
        #expect(runs.contains { !$0.flying })
        // Consecutive runs share a vertex, so the drawn polyline has no hole.
        for (a, b) in zip(runs, runs.dropFirst()) {
            #expect(a.points.last == b.points.first)
        }
        #expect(runs.allSatisfy { $0.points.count >= 2 })
    }

    /// Bucketing by max, not by mean: a sparkline that averages the session's one fast
    /// reach away is worse than no sparkline.
    @Test func thumbnailSparklinePreservesThePeak() {
        var track = RawTrack()
        for i in 0..<300 {
            var sample = RecordSample(t: Double(i), timestamp: Date())
            sample.speedMps = i == 150 ? 12 : 2
            track.samples.append(sample)
        }
        let thumb = TrackThumbnail.make(track: track, flights: [])
        #expect(thumb.speed.count == TrackThumbnail.sparklineBuckets)
        #expect(abs(thumb.maxKn - 12 * Units.mpsToKn) < 0.001)
        #expect(thumb.speed.max() == 1)
        #expect(thumb.speed.allSatisfy { (0...1).contains($0) })
        #expect(thumb.speed.filter { $0 > 0.9 }.count == 1, "the peak leaked into neighbours")
    }

    /// Both halves degrade on their own: a position-less recording still gets a sparkline,
    /// a speed-less one still gets an outline.
    @Test func thumbnailDegradesPerChannel() {
        var noPositions = RawTrack()
        for i in 0..<100 {
            var sample = RecordSample(t: Double(i), timestamp: Date())
            sample.speedMps = 5
            noPositions.samples.append(sample)
        }
        let a = TrackThumbnail.make(track: noPositions, flights: [])
        #expect(a.points.isEmpty)
        #expect(!a.speed.isEmpty)

        var noSpeed = syntheticTrack()
        for index in noSpeed.samples.indices { noSpeed.samples[index].speedMps = nil }
        let b = TrackThumbnail.make(track: noSpeed, flights: [])
        #expect(!b.points.isEmpty)
        #expect(b.speed.isEmpty)
        #expect(b.maxKn == 0)
    }

    @Test func thumbnailSurvivesADegenerateTrack() {
        var track = RawTrack()
        for i in 0..<10 {
            var sample = RecordSample(t: Double(i), timestamp: Date())
            sample.lat = 45.87
            sample.lon = 10.87                 // never moved
            track.samples.append(sample)
        }
        let thumb = TrackThumbnail.make(track: track, flights: [])
        #expect(thumb.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test func thumbnailRoundTripsThroughItsCacheFormat() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-thumb-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(root: root)
        let thumb = TrackThumbnail.make(
            track: syntheticTrack(),
            flights: [FlightRecord(Flight(startT: 0, endT: 199, distM: 400, maxKn: 20))])

        #expect(archive.thumbnail(for: "s1") == nil)
        try archive.writeThumbnail(thumb, id: "s1")
        #expect(archive.thumbnail(for: "s1") == thumb)

        // A thumbnail from an older geometry is not returned — it is rebuilt instead.
        var stale = thumb
        stale.version = TrackThumbnail.currentVersion - 1
        try archive.writeThumbnail(stale, id: "s1")
        #expect(archive.thumbnail(for: "s1") == nil)

        archive.dropThumbnail(for: "s1")
        #expect(!FileManager.default.fileExists(atPath: archive.thumbnailURL(for: "s1").path))
    }

    // MARK: - Personal bests

    private func best(_ kind: RecordKind, _ kn: Double, sourceClass: String = "b") -> RecordBest {
        let effort = RecordEffortRow(sessionId: "s1", kind: kind, valueKn: kn,
                                     achievedAt: Date(), window: nil, sourceClass: sourceClass)
        return RecordBest(kind: kind, valueKn: kn, sessionId: "s1", achievedAt: Date(),
                          sourceClass: sourceClass, window: nil, history: [effort])
    }

    @Test func personalBestDetectionFindsOnlyRealImprovements() {
        let previous = PersonalBestSnapshot(bestByKind: ["best2s": 20.0, "best10s": 18.0])
        let current = [best(.best2s, 21.4), best(.best10s, 18.0), best(.best500m, 15.2)]
        let found = PersonalBestDetector.improvements(previous: previous, current: current)
        #expect(found.map(\.kind) == [.best2s, .best500m])
        #expect(found[0].previousKn == 20.0)
        #expect(abs((found[0].deltaKn ?? 0) - 1.4) < 0.0001)
        #expect(found[1].previousKn == nil, "a kind never achieved before has no delta")
    }

    /// Two query runs can disagree in the last float digit; that is not a personal best.
    @Test func personalBestDetectionIgnoresFloatNoise() {
        let previous = PersonalBestSnapshot(bestByKind: ["best2s": 20.0])
        let noise = PersonalBestDetector.improvements(previous: previous,
                                                      current: [best(.best2s, 20.0 + 1e-9)])
        #expect(noise.isEmpty)
    }

    /// The first import populates every kind at once. Calling that nine personal bests
    /// would fire the celebration at the one moment it means least.
    @Test func firstEverImportIsNotACelebration() {
        let found = PersonalBestDetector.improvements(
            previous: PersonalBestSnapshot(),
            current: [best(.best2s, 21.4), best(.best500m, 15.2)])
        #expect(found.isEmpty)
    }

    /// A class-(c) source can read high; confetti is exactly the wrong response to a bad
    /// speed sample.
    @Test func uncertifiedRecordsNeverCelebrate() {
        let previous = PersonalBestSnapshot(bestByKind: ["best2s": 20.0])
        let found = PersonalBestDetector.improvements(
            previous: previous, current: [best(.best2s, 99.0, sourceClass: "c")])
        #expect(found.isEmpty)
    }

    @Test func personalBestSnapshotTakesTheMaximumPerKind() {
        let snapshot = PersonalBestSnapshot(records: [best(.best2s, 20.0), best(.best10s, 18.0)])
        #expect(snapshot.value(for: .best2s) == 20.0)
        #expect(snapshot.value(for: .bestNm) == nil)
        #expect(!snapshot.isEmpty)
    }

    // MARK: - Widget snapshot

    private func row(id: String, daysAgo: Double, now: Date, durationS: Double,
                     foilTimeS: Double?) -> SessionRow {
        var row = SessionRow(id: id, startDate: now.addingTimeInterval(-daysAgo * 86400),
                             durationS: durationS, sourceClass: "a")
        row.foilTimeS = foilTimeS
        row.foilPct = foilTimeS.map { $0 / durationS * 100 }
        row.best2sKn = 21.3
        row.flightCount = 12
        row.turnsFlewThrough = 9
        row.turnsTouchdown = 9
        row.turnsFellIn = 12
        return row
    }

    @Test func widgetSnapshotTakesTheLatestSessionAndTheLastSevenDays() {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let sessions = [
            row(id: "old", daysAgo: 20, now: now, durationS: 3600, foilTimeS: 1800),
            row(id: "mid", daysAgo: 5, now: now, durationS: 3600, foilTimeS: 1800),
            row(id: "new", daysAgo: 1, now: now, durationS: 7200, foilTimeS: 3600),
        ]
        let snapshot = WidgetSnapshot.make(sessions: sessions, now: now) { "Spot " + $0.id }

        #expect(snapshot.lastSession?.id == "new")
        #expect(snapshot.lastSession?.title == "Spot new")
        #expect(snapshot.lastSession?.hasTurnTally == true)
        #expect(snapshot.weeklySessions == 2, "the 20-day-old session is outside the window")
        #expect(abs(snapshot.weeklyFoilMinutes - 90) < 0.001)
        #expect(abs(snapshot.weeklyHours - 3) < 0.001)
        #expect(!snapshot.isEmpty)
    }

    /// Rows written before the schema-v2 `foilTimeS` column still have to contribute.
    @Test func widgetSnapshotFallsBackToTheFoilPercentage() {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        var legacy = row(id: "legacy", daysAgo: 2, now: now, durationS: 3600, foilTimeS: nil)
        legacy.foilPct = 50
        let snapshot = WidgetSnapshot.make(sessions: [legacy], now: now) { _ in "x" }
        #expect(abs(snapshot.weeklyFoilMinutes - 30) < 0.001)
    }

    @Test func widgetSnapshotOfAnEmptyLibraryIsEmpty() {
        let snapshot = WidgetSnapshot.make(sessions: [], now: Date()) { _ in "x" }
        #expect(snapshot.isEmpty)
        #expect(snapshot.lastSession == nil)
    }

    /// The widget decodes what the app encodes — including a snapshot with no session yet.
    @Test func widgetSnapshotEncodingRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let snapshot = WidgetSnapshot.make(
            sessions: [row(id: "s", daysAgo: 1, now: now, durationS: 3600, foilTimeS: 1800)],
            now: now) { _ in "Torbole" }
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded == snapshot)

        let empty = try JSONDecoder().decode(
            WidgetSnapshot.self, from: try JSONEncoder().encode(WidgetSnapshot()))
        #expect(empty.lastSession == nil)
    }

    /// The app group is not in the current provisioning profile, so the store must survive
    /// its absence rather than assuming the shared container exists.
    @Test func widgetSnapshotStoreFallsBackWithoutAnAppGroup() throws {
        let snapshot = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 1_785_000_000),
                                      weeklySessions: 3)
        // The return value reports whether it reached the *shared* container. Either way
        // the local copy must exist and the app's own read-back must find it — that is
        // what makes the missing entitlement survivable rather than fatal.
        let shared = WidgetSnapshotStore.write(snapshot)
        #expect(WidgetSnapshotStore.read()?.weeklySessions == 3)
        let local = try WidgetSnapshotStore.fallbackURL()
        #expect(FileManager.default.fileExists(atPath: local.path),
                "the local copy must be written whether or not the group exists")
        // Whether a group container exists at all is a property of the host (an
        // unsandboxed macOS test process gets one; an unentitled iOS process does not),
        // so the assertion is the *invariant*: claiming the shared container and not
        // having one is the failure mode that leaves the widget staring at nothing.
        #expect(shared == WidgetSnapshotStore.appGroupAvailable)
        if shared { #expect(WidgetSnapshotStore.sharedDefaults != nil) }
    }

    // MARK: - Map legend visibility

    /// A scratch domain per test: the visibility set is a *user* preference, so its store
    /// talks to `UserDefaults`, and a shared suite would let one test see another's state.
    private func scratchDefaults() throws -> UserDefaults {
        let suite = "wingfoil.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// The default has to be "show everything": a rider who never touched a chip must not
    /// discover that the app decided to hide half the session for them.
    @Test func mapLayersDefaultToEverythingVisible() {
        let visibility = MapLayerVisibility()
        #expect(visibility.isEverythingVisible)
        #expect(visibility.hiddenLayers.isEmpty)
        for layer in MapLayer.allCases {
            #expect(visibility.isVisible(layer), "\(layer.rawValue) starts hidden")
        }
        #expect(visibility.lineStyle(flying: true) == .flying)
        #expect(visibility.lineStyle(flying: false) == .offFoil)
    }

    @Test func togglingALayerFlipsOnlyThatLayer() {
        var visibility = MapLayerVisibility()
        visibility.toggle(.fellIn)
        #expect(!visibility.isVisible(.fellIn))
        #expect(!visibility.isEverythingVisible)
        #expect(visibility.hiddenLayers == [.fellIn])
        for layer in MapLayer.allCases where layer != .fellIn {
            #expect(visibility.isVisible(layer), "\(layer.rawValue) was collateral damage")
        }
        visibility.toggle(.fellIn)
        #expect(visibility.isVisible(.fellIn))
        #expect(visibility.isEverythingVisible)
    }

    @Test func showAllClearsEveryHiddenLayer() {
        var visibility = MapLayerVisibility(hidden: [.fellIn, .courseChange, .flying])
        #expect(!visibility.isEverythingVisible)
        visibility.showAll()
        #expect(visibility.isEverythingVisible)
        #expect(visibility.lineStyle(flying: true) == .flying)
    }

    /// The edge case that makes the line chips different from the marker chips: hiding
    /// "flying" drops the *tint*, never the route. A rider who cannot see where they went
    /// has lost the map, which is not what tapping a legend chip should ever mean.
    @Test func hidingALineCategoryFallsBackToTheNeutralRoute() {
        var visibility = MapLayerVisibility()
        visibility.setVisible(false, for: .flying)
        #expect(visibility.lineStyle(flying: true) == .neutral)
        #expect(visibility.lineStyle(flying: false) == .offFoil,
                "hiding one phase must not restyle the other")

        visibility.setVisible(false, for: .offFoil)
        #expect(visibility.lineStyle(flying: true) == .neutral)
        #expect(visibility.lineStyle(flying: false) == .neutral)

        visibility.setVisible(true, for: .flying)
        #expect(visibility.lineStyle(flying: true) == .flying)
    }

    /// Line categories restyle, marker categories disappear — the split the legend draws
    /// as two rows has to hold in the model too.
    @Test func everyLayerIsEitherALineOrAMarker() {
        let lines = MapLayer.allCases.filter(\.isLine)
        let markers = MapLayer.allCases.filter(\.isMarker)
        #expect(Set(lines) == [.flying, .offFoil, .effort, .pumping])
        #expect(Set(markers) == [.flewThrough, .touchdown, .fellIn, .courseChange,
                                 .takeoff, .splash])
        #expect(lines.count + markers.count == MapLayer.allCases.count)
        let labels = MapLayer.allCases.map(\.label)
        #expect(Set(labels).count == labels.count, "two chips would read the same")
        let nouns = MapLayer.allCases.map(\.accessibilityNoun)
        #expect(Set(nouns).count == nouns.count, "two toggles would be spoken the same")
        #expect(nouns.allSatisfy { !$0.isEmpty })
    }

    /// Survives a relaunch — the whole point of storing it.
    @Test func visibilityRoundTripsThroughUserDefaults() throws {
        let defaults = try scratchDefaults()
        #expect(MapLayerVisibilityStore.load(from: defaults).isEverythingVisible,
                "an untouched install shows everything")

        var visibility = MapLayerVisibility()
        visibility.toggle(.fellIn)
        visibility.toggle(.courseChange)
        MapLayerVisibilityStore.save(visibility, to: defaults)

        let reloaded = MapLayerVisibilityStore.load(from: defaults)
        #expect(reloaded == visibility)
        #expect(reloaded.hiddenLayers == [.fellIn, .courseChange])
        #expect(reloaded.isVisible(.touchdown))

        // Turning them back on has to persist too, or the map would come back blank.
        visibility.showAll()
        MapLayerVisibilityStore.save(visibility, to: defaults)
        #expect(MapLayerVisibilityStore.load(from: defaults).isEverythingVisible)
    }

    /// An unreadable preference must not leave the rider with a half-blank map and no way
    /// to reason about it; the same leniency covers a layer a future build added.
    @Test func unreadableOrUnknownStoredLayersDegradeToVisible() throws {
        let defaults = try scratchDefaults()
        defaults.set(Data("not json".utf8), forKey: MapLayerVisibilityStore.defaultsKey)
        #expect(MapLayerVisibilityStore.load(from: defaults).isEverythingVisible)

        defaults.set(Data(#"["fellIn","windShadow"]"#.utf8),
                     forKey: MapLayerVisibilityStore.defaultsKey)
        let decoded = MapLayerVisibilityStore.load(from: defaults)
        #expect(decoded.hiddenLayers == [.fellIn], "an unknown layer is dropped, not fatal")
    }

    @Test func visibilityEncodesAsSortedRawValues() throws {
        let data = try JSONEncoder().encode(MapLayerVisibility(hidden: [.touchdown, .flying]))
        #expect(String(decoding: data, as: UTF8.self) == #"["flying","touchdown"]"#)
        #expect(try JSONDecoder().decode(MapLayerVisibility.self, from: data)
            .hiddenLayers == [.flying, .touchdown])
    }

    /// A chip for something this session does not contain is not a control — there is
    /// nothing to hide — so the legend renders it inert.
    @Test func chipsWithoutInstancesAreNotToggleable() {
        var tally = MapLayerTally()
        tally.add(.flying, 4)
        tally.add(.touchdown)
        tally.add(.touchdown)

        #expect(tally.count(.touchdown) == 2)
        #expect(tally.isToggleable(.touchdown))
        #expect(tally.isToggleable(.flying))
        #expect(tally.count(.fellIn) == 0)
        #expect(!tally.isToggleable(.fellIn), "a session with no swims has no swim toggle")
        #expect(!MapLayerTally().isToggleable(.flying))
    }

    // MARK: - HR-cost card
    //
    // The card is the only thing between a sensor with known failure modes and a screen
    // that looks authoritative, so its missing-value and thin-coverage paths are tested as
    // hard as its happy one.

    /// The example session's own figures (fixtures/goldens, 2026-08-07 ciq `hr.summary`).
    private func exampleSummary() -> HrSummary {
        var s = HrSummary()
        s.hasHR = true
        s.usablePct = 75.55
        s.avgTakeoffCostBpm = 6.891
        s.medianTakeoffCostBpm = 7.0
        s.takeoffCostCoverage = HrCoverage(valid: 23, total: 23)
        s.medianPeakLagS = 20.49
        s.bpmPerStroke = 0.762
        s.medianBpmPerStroke = 0.75
        s.bpmPerStrokeCoverage = HrCoverage(valid: 23, total: 23)
        s.pumpCruise.pumpingBpm = 101.597
        s.pumpCruise.cruisingBpm = 95.983
        s.pumpCruise.deltaBpm = 5.614
        s.pumpCruise.pumpingSpans = 88
        s.pumpCruise.cruisingSpans = 36
        s.pumpCruise.pumpingCoveredS = 455.64
        s.pumpCruise.pumpingSpanS = 455.64
        s.pumpCruise.cruisingCoveredS = 1557.14
        s.pumpCruise.cruisingSpanS = 1557.14
        s.medianTakeoffRecoveryS = 12
        s.takeoffRecoveryCoverage = HrCoverage(valid: 14, total: 15)
        s.medianSwimRecoveryS = 17.5
        s.swimRecoveryCoverage = HrCoverage(valid: 4, total: 7)
        return s
    }

    private func analysis(_ summary: HrSummary, bins: [FatigueBin] = []) -> HrAnalysis {
        HrAnalysis(hasHR: summary.hasHR, takeoffEvents: [], swimEvents: [], bins: bins,
                   summary: summary)
    }

    private func bin(_ startMin: Double, _ endMin: Double, attempts: Int, successes: Int,
                     cost: Double?, baseline: Double?, valid: Int, total: Int) -> FatigueBin {
        var b = FatigueBin(startT: startMin * 60, endT: endMin * 60)
        b.attempts = attempts
        b.successes = successes
        b.failed = attempts - successes
        if attempts > 0 { b.successPct = 100 * Double(successes) / Double(attempts) }
        b.medianCostBpm = cost
        b.avgCostBpm = cost
        b.avgBaselineBpm = baseline
        b.costCoverage = HrCoverage(valid: valid, total: total)
        return b
    }

    /// No HR channel ⇒ no card at all. A card of em-dashes reads as "measured, and it was
    /// nothing"; the absence of the card is the honest rendering of an absent sensor.
    @Test func hrCardIsAbsentWithoutAUsableHeartRate() {
        #expect(HrCostCard.make(nil) == nil)
        #expect(HrCostCard.make(HrAnalysis()) == nil, "hasHR false ⇒ nothing to show")

        // Samples existed but nothing survived the guards: still nothing to show.
        var empty = HrSummary()
        empty.hasHR = true
        empty.usablePct = 4
        #expect(HrCostCard.make(analysis(empty)) == nil)
    }

    /// The headline never appears without the denominator it was averaged over.
    @Test func hrCardHeadlineCarriesItsCoverage() throws {
        let card = try #require(HrCostCard.make(analysis(exampleSummary())))
        #expect(card.headlineValue == "+7 bpm")
        #expect(!card.headlineMissing)
        #expect(card.headlineCaption == "median takeoff cost · 23 of 23 takeoffs")
        #expect(card.warning == nil, "76 % usable and 23/23 measured is not a thin session")
        #expect(card.footnote == "HR usable 76% of the session · peak 20 s after the effort")
    }

    /// A native recording anchors on the flight start instead of the first pump stroke —
    /// a weaker claim, so it is said on the headline rather than left to the help screen.
    @Test func hrCardSaysWhenAnchorsWereApproximate() throws {
        var s = exampleSummary()
        s.approximateTakeoffs = 52
        s.takeoffCostCoverage = HrCoverage(valid: 52, total: 52)
        let card = try #require(HrCostCard.make(analysis(s)))
        #expect(card.headlineCaption
            == "median takeoff cost · 52 of 52 takeoffs · 52 anchored on the flight start")
    }

    /// Every secondary number that could not be measured says why, and none of them
    /// silently becomes a zero.
    @Test func hrCardNamesTheReasonForEveryMissingValue() throws {
        var s = HrSummary()
        s.hasHR = true
        // One measurable thing so the card exists at all; everything else is absent.
        s.medianTakeoffCostBpm = 3
        s.takeoffCostCoverage = HrCoverage(valid: 1, total: 1)
        let card = try #require(HrCostCard.make(analysis(s)))

        #expect(card.stats.map(\.key)
            == ["bpmPerStroke", "pumpCruise", "takeoffRecovery", "swimRecovery"])
        #expect(card.stats.allSatisfy { $0.missing })
        #expect(card.stats.allSatisfy { $0.value == "—" })
        #expect(card.stats.allSatisfy { !$0.value.contains("0") }, "never 0 for unmeasured")
        #expect(card.stats.allSatisfy { !$0.caption.isEmpty }, "a dash without a reason")
        #expect(card.stats[0].caption == "no takeoffs to rate")
        #expect(card.stats[1].caption == "no pump bursts on this source")
        #expect(card.stats[2].caption == "no takeoff raised HR enough to recover from")
        #expect(card.baselineNote == nil, "no bins, nothing to say about drift")
        #expect(card.binCaption == nil)
    }

    /// The two ways a recovery can be missing are different facts and read differently.
    @Test func hrCardSeparatesNoRiseFromNoDecay() throws {
        var s = exampleSummary()
        s.medianTakeoffRecoveryS = nil
        s.takeoffRecoveryCoverage = HrCoverage(valid: 0, total: 9)   // rose, never came back
        s.medianSwimRecoveryS = nil
        s.swimRecoveryCoverage = HrCoverage(valid: 0, total: 0)      // never rose at all
        let card = try #require(HrCostCard.make(analysis(s)))
        #expect(card.stats[2].caption == "HR never fell halfway back within 2 min")
        #expect(card.stats[3].caption == "no swim raised HR enough to recover from")
    }

    /// The happy-path secondary numbers, including the one decimal the pumping/cruising
    /// delta keeps because rounding 5.6 to 6 would drop the only digit that moves.
    @Test func hrCardSecondaryStatsQuoteTheirDenominators() throws {
        let card = try #require(HrCostCard.make(analysis(exampleSummary())))
        #expect(card.stats[0].value == "0.76 bpm")
        #expect(card.stats[0].caption == "median 0.75 · 23 of 23 takeoffs")
        #expect(card.stats[1].value == "+5.6 bpm")
        #expect(card.stats[1].caption == "102 vs 96 bpm on the foil")
        #expect(card.stats[2].value == "12 s")
        #expect(card.stats[2].caption == "halfway back · 14 of 15 rises")
        #expect(card.stats[3].value == "18 s")
        #expect(card.stats[3].caption == "halfway back · 4 of 7 swims")
        #expect(card.stats.prefix(3).allSatisfy { !$0.thin })
        // 4 of 7 is below `thinCoveragePct`: the number is real, and the reader is told not
        // to lean on it. This is the example session's own figure.
        #expect(card.stats[3].thin)
    }

    /// A patchy sensor is announced before the numbers are read, not after.
    @Test func hrCardWarnsWhenTheSessionIsMostlyMissing() throws {
        var s = exampleSummary()
        s.usablePct = 38
        s.takeoffCostCoverage = HrCoverage(valid: 3, total: 40)
        s.takeoffRecoveryCoverage = HrCoverage(valid: 2, total: 9)
        let card = try #require(HrCostCard.make(analysis(s)))
        let warning = try #require(card.warning)
        #expect(warning.contains("only 38% of the session"))
        #expect(warning.contains("only 3 of 40 takeoffs could be measured"))
        #expect(card.stats[2].thin, "2 of 9 recoveries is a number to distrust")
        #expect(!card.stats[0].thin, "23 of 23 stroke ratios is not")
    }

    /// Time-weighted means carry a *seconds* denominator, so the card states it in the one
    /// unit that is honest for them.
    @Test func hrCardReportsPumpCruiseCoverageInTime() throws {
        var s = exampleSummary()
        s.pumpCruise.pumpingCoveredS = 200
        s.pumpCruise.pumpingSpanS = 455.64
        let card = try #require(HrCostCard.make(analysis(s)))
        #expect(card.stats[1].caption == "102 vs 96 bpm on the foil · 44% covered")
        #expect(card.stats[1].thin)
    }

    @Test func hrBpmFormatterSignsRisesAndKeepsAMeasuredZero() {
        #expect(HrCostCard.bpm(7) == "+7 bpm")
        #expect(HrCostCard.bpm(-9) == "-9 bpm", "a negative cost is reported, not clamped")
        #expect(HrCostCard.bpm(0) == "0 bpm", "measured zero is not a missing value")
        #expect(HrCostCard.bpm(-0.4) == "0 bpm", "never the -0 bpm that %+.0f would print")
        #expect(HrCostCard.bpm(0.6) == "+1 bpm")
        #expect(HrCostCard.bpm(5.614, decimals: 1) == "+5.6 bpm")
        #expect(HrCostCard.bpm(-0.02, decimals: 1) == "0 bpm")
    }

    @Test func hrCoverageTextIsNilWithoutADenominator() {
        #expect(HrCostCard.coverageText(HrCoverage(valid: 0, total: 0), noun: "takeoff") == nil)
        #expect(HrCostCard.coverageText(HrCoverage(valid: 1, total: 1), noun: "takeoff")
            == "1 of 1 takeoff")
        #expect(HrCostCard.coverageText(HrCoverage(valid: 0, total: 4), noun: "swim")
            == "0 of 4 swims")
        #expect(HrCostCard.coverageText(HrCoverage(valid: 3, total: 4), noun: nil) == "3 of 4")
    }

    /// The fatigue bins are the engine's, edges and all — including the short final one —
    /// and a bin nothing could be measured in keeps a nil cost rather than a zero bar.
    @Test func hrCardBinsKeepTheEngineEdgesAndAbsentCosts() throws {
        let bins = [bin(0, 20, attempts: 11, successes: 7, cost: 10.5, baseline: 89.2,
                        valid: 7, total: 7),
                    bin(20, 40, attempts: 0, successes: 0, cost: nil, baseline: nil,
                        valid: 0, total: 0),
                    bin(40, 91.55, attempts: 3, successes: 1, cost: -9, baseline: 103,
                        valid: 1, total: 3)]
        let card = try #require(HrCostCard.make(analysis(exampleSummary(), bins: bins)))
        #expect(card.bins.map(\.label) == ["0–20 min", "20–40 min", "40–92 min"])
        #expect(card.bins.map(\.startS) == [0, 1200, 2400])
        #expect(card.bins[2].endS == 5493)
        #expect(card.bins[0].successPct == 100 * 7.0 / 11)
        #expect(card.bins[1].successPct == nil, "no attempts is not 0 % success")
        #expect(card.bins[1].costBpm == nil, "no usable HR is not a zero-cost bin")
        #expect(card.bins[1].coverage == nil)
        #expect(card.bins[2].coverage == "1 of 3")
        #expect(card.bins[2].costBpm == -9)
        #expect(card.binCaption?.contains("20-minute bins") == true)
        #expect(card.bins[1].accessibilityText == "20–40 min, cost not measurable")
        #expect(card.bins[2].accessibilityText
            == "40–92 min, cost -9 bpm, 33% of 3 attempts, from 103 bpm")
    }

    /// The sentence that stops a falling cost curve being read as "it got easier".
    @Test func hrCardExplainsBaselineDrift() throws {
        func note(_ first: Double, _ last: Double) -> String? {
            HrCostCard.baselineNote(HrCostCard.bins(
                [bin(0, 20, attempts: 4, successes: 3, cost: 8, baseline: first,
                     valid: 3, total: 3),
                 bin(20, 40, attempts: 4, successes: 3, cost: 2, baseline: last,
                     valid: 3, total: 3)]))
        }
        #expect(note(89, 103)?.contains("89 → 103 bpm") == true)
        #expect(note(89, 103)?.contains("missing headroom") == true)
        #expect(note(103, 95)?.contains("began from a lower heart rate") == true)
        #expect(note(89, 91)?.contains("steady 89 → 91 bpm") == true)
        // One bin with a baseline is not a drift; two are needed to compare.
        #expect(HrCostCard.baselineNote(HrCostCard.bins(
            [bin(0, 20, attempts: 1, successes: 1, cost: 8, baseline: 89, valid: 1, total: 1),
             bin(20, 40, attempts: 0, successes: 0, cost: nil, baseline: nil,
                 valid: 0, total: 0)])) == nil)
    }

    // MARK: - Turns page
    //
    // Two segmented filters that compose, over a field whose name ("side") means the
    // *entry* tack and not the rotation. Both halves are worth a test: the composition,
    // because an AND that silently became an OR would still look plausible on screen, and
    // the wording, because "left" would read as the wrong field entirely.

    /// A turn built field by field. `direction` is deliberately set *opposite* to `side`
    /// in most of these, which is the real corpus shape — the golden's first jibe is
    /// `side: starboard, direction: port` — so a filter that read the wrong field would
    /// fail these tests rather than pass them by luck.
    private func turn(_ ts: Double, type: String, side: String, direction: String,
                      outcome: String, counted: Bool = true, score: Double = 0.5,
                      submerged: Bool = false, stopped: Double = 0) throws -> TurnRecord {
        let json: [String: Any] = [
            "ts": ts, "endTs": ts + 8, "type": type, "counted": counted,
            "entryKn": 11.1, "minKn": 7.5, "score": score, "success": score >= 0.7,
            "side": side, "direction": direction, "netDeg": -151.1, "arcM": 44.0,
            "radiusM": 16.7, "outcome": outcome, "borderline": false, "offFoilS": 54.0,
            "stoppedS": stopped, "pumped": false, "submerged": submerged,
            "outcomeWindowS": 11.0,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(TurnRecord.self, from: data)
    }

    /// A session shaped like the corpus one: jibes on both entry tacks, a tack, and two
    /// course changes that must never be counted.
    private func turnSet() throws -> [TurnRecord] {
        [
            try turn(100, type: "jibe", side: "port", direction: "starboard",
                     outcome: "flew_through", score: 0.82),
            try turn(200, type: "jibe", side: "port", direction: "starboard",
                     outcome: "fell_in", score: 0.31),
            try turn(300, type: "jibe", side: "starboard", direction: "port",
                     outcome: "touchdown", score: 0.55),
            try turn(400, type: "jibe", side: "starboard", direction: "port",
                     outcome: "flew_through", score: 0.9, submerged: true),
            try turn(500, type: "tack", side: "port", direction: "port",
                     outcome: "touchdown", score: 0.6),
            try turn(600, type: "tack", side: "starboard", direction: "starboard",
                     outcome: "flew_through", score: 0.75),
            // Course changes: rejected by the engine, invisible to every filter here.
            try turn(700, type: "bear_away", side: "starboard", direction: "port",
                     outcome: "flew_through", counted: false),
            try turn(800, type: "round_up", side: "port", direction: "starboard",
                     outcome: "fell_in", counted: false),
        ]
    }

    /// The point of the page: the two filters are ANDed, not ORed, and each one reads its
    /// own field.
    @Test func bothTurnFiltersApplyAtOnce() throws {
        let turns = try turnSet()

        #expect(TurnAnalytics.items(turns, filter: TurnFilter()).map(\.ts)
            == [100, 200, 300, 400, 500, 600], "both/both is every *counted* turn")

        let jibesOnStarboard = TurnAnalytics.items(
            turns, filter: TurnFilter(type: .jibes, side: .starboard))
        #expect(jibesOnStarboard.map(\.ts) == [300, 400])
        #expect(jibesOnStarboard.allSatisfy { $0.side == "starboard" })

        // The same side filter over tacks picks a different turn entirely — an OR would
        // have returned all three.
        #expect(TurnAnalytics.items(turns, filter: TurnFilter(type: .tacks, side: .starboard))
            .map(\.ts) == [600])
        #expect(TurnAnalytics.items(turns, filter: TurnFilter(type: .jibes, side: .port))
            .map(\.ts) == [100, 200])
        #expect(TurnAnalytics.items(turns, filter: TurnFilter(type: .tacks, side: .port))
            .map(\.ts) == [500])
    }

    /// The filter reads `side` (the tack entered on), never `direction` (the rotation).
    /// Every jibe in the set turns the opposite way to the tack it came in on, so a filter
    /// on the wrong field would return the other pair.
    @Test func theSideFilterReadsTheEntryTackNotTheRotation() throws {
        let turns = try turnSet()
        let port = TurnAnalytics.items(turns, filter: TurnFilter(type: .jibes, side: .port))
        #expect(port.map(\.ts) == [100, 200])
        #expect(port.allSatisfy { $0.sideLabel == "port entry" })
        #expect(TurnSideFilter.port.label == "Port entry")
        #expect(TurnSideFilter.starboard.label == "Starboard entry")
        for side in TurnSideFilter.allCases {
            #expect(!side.label.lowercased().contains("left"))
            #expect(!side.label.lowercased().contains("right"))
        }
        #expect(TurnAnalytics.sideLabel("unknown") == "entry tack unknown")
    }

    /// Course changes stay out of every view of the page — the same rule the session
    /// summary applies with `counted`.
    @Test func courseChangesNeverReachTheTurnsPage() throws {
        let turns = try turnSet()
        for type in TurnTypeFilter.allCases {
            for side in TurnSideFilter.allCases {
                let items = TurnAnalytics.items(turns, filter: TurnFilter(type: type,
                                                                          side: side))
                #expect(!items.contains { $0.ts == 700 || $0.ts == 800 },
                        "\(type.rawValue)/\(side.rawValue) let a course change through")
            }
        }
        #expect(TurnAnalytics.count(turns, filter: TurnFilter()) == 6)
    }

    /// The tally is over the filtered set, and an empty filter reports *nothing*, not 0 %.
    @Test func theTallyFollowsTheFilter() throws {
        let turns = try turnSet()

        let all = TurnAnalytics.tally(turns, filter: TurnFilter())
        #expect((all.flewThrough, all.touchdown, all.fellIn) == (3, 2, 1))
        #expect(all.total == 6)
        #expect(all.flewThroughPct.map { Int($0.rounded()) } == 50)
        #expect(all.caption == "3 flew · 2 touch · 1 fell")

        let portJibes = TurnAnalytics.tally(turns, filter: TurnFilter(type: .jibes,
                                                                      side: .port))
        #expect((portJibes.flewThrough, portJibes.touchdown, portJibes.fellIn) == (1, 0, 1))
        #expect(portJibes.flewThroughPct == 50)

        let starboardJibes = TurnAnalytics.tally(turns, filter: TurnFilter(type: .jibes,
                                                                           side: .starboard))
        #expect((starboardJibes.flewThrough, starboardJibes.touchdown,
                 starboardJibes.fellIn) == (1, 1, 0))
        #expect(starboardJibes.count(.fellIn) == 0)

        // A filter that matches nothing: "you have never done this" is not "you fail at
        // it", so the rate is absent rather than zero.
        let noTacks = TurnAnalytics.tally(
            try [turn(100, type: "jibe", side: "port", direction: "starboard",
                      outcome: "fell_in")],
            filter: TurnFilter(type: .tacks, side: .both))
        #expect(noTacks.total == 0)
        #expect(noTacks.flewThroughPct == nil)
        #expect(noTacks.caption == "nothing matches this filter")
    }

    /// The row is the whole formatting contract: the view prints no number itself.
    @Test func turnRowsCarryTheirOwnWording() throws {
        let turns = try turnSet()
        let rows = TurnAnalytics.items(turns, filter: TurnFilter(type: .jibes,
                                                                 side: .starboard))
        let submerged = try #require(rows.last)
        #expect(submerged.id == 3, "the id is the index in the analysis, not in the filter")
        #expect(submerged.typeLabel == "Jibe")
        #expect(submerged.sideLabel == "starboard entry")
        #expect(submerged.outcome == .flewThrough)
        #expect(submerged.scoreText == "90")
        #expect(submerged.detail.contains("wrist under"))
        #expect(submerged.accessibilityText.contains("Jibe, starboard entry"))
        #expect(submerged.accessibilityText.contains("flew through"))

        // Every outcome gets a distinct shape as well as a distinct colour.
        let symbols = TurnOutcomeKind.allCases.map(\.symbolName)
        #expect(Set(symbols).count == symbols.count)
        #expect(TurnOutcomeKind("glide_out") == .flewThrough)
    }

    /// The filter's own description, which the empty state and VoiceOver both read.
    @Test func theFilterDescribesItselfInRiderWords() {
        #expect(TurnFilter().description == "all turns")
        #expect(TurnFilter().isEverything)
        #expect(TurnFilter(type: .jibes, side: .both).description == "jibes")
        #expect(TurnFilter(type: .both, side: .port).description == "turns entered on port")
        #expect(TurnFilter(type: .tacks, side: .starboard).description
            == "tacks entered on starboard")
    }

    // MARK: - Trends: turn success by entry tack

    /// The two series the Trends chart plots. Built from per-turn rows because the session
    /// summary counts the sides but not their outcomes.
    @Test func turnSuccessSplitsByTheEntryTack() throws {
        let split = TurnSideSplit.make(try turnSet())
        #expect(split.portCounted == 3)          // two jibes + one tack, course change out
        #expect(split.portFlewThrough == 1)
        #expect(split.starboardCounted == 3)
        #expect(split.starboardFlewThrough == 2)
        #expect(split.portSuccessPct.map { Int($0.rounded()) } == 33)
        #expect(split.starboardSuccessPct.map { Int($0.rounded()) } == 67)
        #expect(split.gapPct.map { Int($0.rounded()) } == -33, "port is the weaker side")
        #expect(!split.isEmpty)
    }

    /// A side he never entered on contributes no point — absent, not 0 %, which is the
    /// rule the rest of the Trends screen follows.
    @Test func aSideNeverRiddenIsAbsentFromTheSeriesNotZero() throws {
        let onlyPort = TurnSideSplit.make(try [
            turn(100, type: "jibe", side: "port", direction: "starboard",
                 outcome: "fell_in"),
        ])
        #expect(onlyPort.portSuccessPct == 0, "he did jibe on port, and failed: that is 0 %")
        #expect(onlyPort.starboardSuccessPct == nil, "he never entered on starboard")
        #expect(onlyPort.gapPct == nil, "a gap needs two numbers")

        // A turn with no usable wind axis has no entry tack and is attributed to neither.
        var unknown = TurnSideSplit()
        unknown.add(side: "unknown", flewThrough: true)
        #expect(unknown.isEmpty)
        #expect(unknown.portSuccessPct == nil)
        #expect(unknown.starboardSuccessPct == nil)
    }

    // MARK: - Record-window picker

    /// The three edges of the picker: where it starts, what a second tap does, and what a
    /// record with no window does (nothing).
    @Test func recordWindowSelectionStartsOnTheTwoSecondPeak() {
        let available: Set<String> = ["best2s", "best10s", "bestNm"]
        #expect(RecordWindowSelection.defaultKey == "best2s")
        #expect(RecordWindowSelection.initial(available: available) == "best2s")

        // A session with no 2 s window highlights nothing rather than substituting one.
        #expect(RecordWindowSelection.initial(available: ["best500m"]) == nil)
        #expect(RecordWindowSelection.initial(available: []) == nil)
    }

    @Test func tappingAnotherRecordMovesTheGlowAndTappingItAgainGoesBack() {
        let available: Set<String> = ["best2s", "best10s", "bestNm"]
        var selection: String? = RecordWindowSelection.initial(available: available)

        selection = RecordWindowSelection.tapped("best10s", current: selection,
                                                 available: available)
        #expect(selection == "best10s")

        // Tapping the *selected* row returns to the default, not to nothing: the glow is
        // the page's resting state, and this is the way back to it.
        selection = RecordWindowSelection.tapped("best10s", current: selection,
                                                 available: available)
        #expect(selection == "best2s")

        // Only re-tapping the default itself clears the glow.
        selection = RecordWindowSelection.tapped("best2s", current: selection,
                                                 available: available)
        #expect(selection == nil)
        selection = RecordWindowSelection.tapped("bestNm", current: selection,
                                                 available: available)
        #expect(selection == "bestNm")
    }

    /// A record the session never achieved is not tappable and says nothing: a tap on it
    /// leaves the selection exactly where it was.
    @Test func aRecordWithoutAWindowIsNotSelectable() {
        let available: Set<String> = ["best2s", "best10s"]
        #expect(RecordWindowSelection.tapped("alpha500", current: "best10s",
                                             available: available) == "best10s")
        #expect(RecordWindowSelection.tapped("alpha500", current: nil,
                                             available: available) == nil)
        // Every catalogue entry is a real engine window key, or the card could never light.
        for kind in RecordWindowSelection.catalogue {
            #expect(RecordKind(rawValue: kind.rawValue) != nil)
        }
        #expect(RecordWindowSelection.catalogue.first == .best2s)
        #expect(!RecordWindowSelection.catalogue.contains(.bestHour),
                "an hour-long window would light the whole track")
    }

    // MARK: - The new map layers

    /// The compatibility rule that matters on upgrade: a preference written by the build
    /// *before* pumping/takeoff/splash existed must decode, keep its choices, and leave
    /// the three new categories visible.
    @Test func oldStoredPreferencesLeaveTheNewLayersVisible() throws {
        let defaults = try scratchDefaults()
        // Exactly what the v1 build wrote: the old case set, sorted, as a JSON array.
        defaults.set(Data(#"["courseChange","fellIn"]"#.utf8),
                     forKey: MapLayerVisibilityStore.defaultsKey)

        let loaded = MapLayerVisibilityStore.load(from: defaults)
        #expect(loaded.hiddenLayers == [.fellIn, .courseChange], "the old choice survived")
        for layer in [MapLayer.pumping, .takeoff, .splash] {
            #expect(loaded.isVisible(layer), "\(layer.rawValue) must default to visible")
        }
        // And the round trip back out keeps the new ones out of the stored set.
        MapLayerVisibilityStore.save(loaded, to: defaults)
        let data = try #require(defaults.data(forKey: MapLayerVisibilityStore.defaultsKey))
        #expect(String(decoding: data, as: UTF8.self) == #"["courseChange","fellIn"]"#)
    }

    @Test func theNewLayersToggleAndPersistLikeTheOldOnes() throws {
        let defaults = try scratchDefaults()
        var visibility = MapLayerVisibility()
        visibility.toggle(.splash)
        visibility.toggle(.pumping)
        #expect(!visibility.isVisible(.splash))
        #expect(!visibility.isVisible(.pumping))
        #expect(visibility.isVisible(.takeoff))
        // Pumping is a line category, but it is an *overlay* on the route rather than a
        // phase, so hiding it must not neutralize the flying/off-foil colouring.
        #expect(visibility.lineStyle(flying: true) == .flying)
        #expect(visibility.lineStyle(flying: false) == .offFoil)

        MapLayerVisibilityStore.save(visibility, to: defaults)
        #expect(MapLayerVisibilityStore.load(from: defaults) == visibility)

        // The `UI_HIDE_LAYERS` debug hook resolves layers by raw value; the three new
        // names have to survive that round trip or the screenshot hook cannot stage them.
        for name in ["pumping", "takeoff", "splash"] {
            #expect(MapLayer(rawValue: name) != nil, "UI_HIDE_LAYERS=\(name) would be a no-op")
        }
    }

    @Test func theNewLayerChipsAreInertOnASessionWithoutThem() {
        var tally = MapLayerTally()
        tally.add(.pumping, 23)
        tally.add(.takeoff, 23)
        tally.add(.splash, 0)
        #expect(tally.isToggleable(.pumping))
        #expect(tally.count(.takeoff) == 23)
        #expect(!tally.isToggleable(.splash),
                "a session the barometer saw no submersion in has no splash toggle")
    }
}
