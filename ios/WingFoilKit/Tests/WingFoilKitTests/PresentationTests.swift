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
        #expect(Set(lines) == [.flying, .offFoil, .effort])
        #expect(Set(markers) == [.flewThrough, .touchdown, .fellIn, .courseChange])
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
}
