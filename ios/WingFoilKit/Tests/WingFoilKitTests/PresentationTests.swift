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

    // MARK: - Help pictures

    /// The app's asset catalogue, found from this file rather than from a bundle.
    ///
    /// `HelpImage` carries only a *name*, and the picture it names lives in the app target's
    /// catalogue, which the kit's test bundle cannot load. A misspelt name would therefore
    /// compile, ship, and draw nothing at all — a blank gap in a help topic that nobody
    /// notices because nobody re-reads help. So the check is made against the checked-in
    /// image sets on disk, which is the thing the name actually has to agree with.
    private static let helpAssetsDirectory: URL = {
        URL(filePath: #filePath)                       // …/Tests/WingFoilKitTests/this file
            .deletingLastPathComponent()               // …/Tests/WingFoilKitTests
            .deletingLastPathComponent()               // …/Tests
            .deletingLastPathComponent()               // …/WingFoilKit
            .deletingLastPathComponent()               // …/ios
            .appending(path: "WingFoil/Resources/Assets.xcassets/Help")
    }()

    @Test func everyHelpImageNamesAnImageSetThatExists() {
        let root = Self.helpAssetsDirectory
        #expect(FileManager.default.fileExists(atPath: root.path()),
                "the Help asset folder moved — \(root.path())")

        let withImages = HelpCatalog.topics.compactMap { topic in
            topic.image.map { (topic.id, $0) }
        }
        #expect(!withImages.isEmpty, "no topic carries a picture any more")

        for (id, image) in withImages {
            let set = root.appending(path: "\(image.asset).imageset")
            #expect(FileManager.default.fileExists(atPath: set.path()),
                    "\(id.rawValue) names \"\(image.asset)\", which is not an image set")
            #expect(FileManager.default
                        .fileExists(atPath: set.appending(path: "Contents.json").path()),
                    "\(image.asset).imageset has no Contents.json")
            // An empty image set draws nothing just as silently as a misspelt name does.
            let files = (try? FileManager.default.contentsOfDirectory(atPath: set.path())) ?? []
            #expect(files.contains { $0.lowercased().hasSuffix(".png") },
                    "\(image.asset).imageset holds no PNG")
            #expect(!image.caption.isEmpty, "\(id.rawValue)'s picture has no caption")
            #expect(image.caption.count > 20, "\(id.rawValue)'s caption is a stub")
        }
    }

    /// Pictures belong on the topics that describe a *screen*. A definition — what a flight
    /// is, what "uncertified" means — is not made clearer by a photograph of a number, and
    /// a decorative screenshot in a reference work costs every reader who came for the
    /// sentence. This is the rule written down, so adding a picture to a definition has to
    /// be a decision rather than a habit.
    @Test func onlyScreenTopicsCarryPictures() {
        let illustrated = Set(HelpCatalog.topics.filter { $0.image != nil }.map(\.id))
        #expect(illustrated == [.exampleSession, .mapLegend, .turnOutcomes,
                                .replayClip, .shareCard])
    }

    // MARK: - Sharing

    /// The four doors a rider would otherwise never find, and the promise each of them
    /// makes about what leaves the phone.
    @Test func theSharingSectionIsWrittenAndSaysWhereThingsGo() {
        #expect(HelpCatalog.topics(in: .sharing).map(\.id)
                == [.shareCard, .replayClip, .shareFit, .riderAttribution])

        // The card and the clip are both rendered locally, and both say so — that is the
        // half of each topic a rider is actually deciding on.
        for id in [HelpTopicID.shareCard, .replayClip] {
            let prose = HelpCatalog.topic(id).body.joined(separator: " ").lowercased()
            #expect(prose.contains("phone"), "\(id.rawValue) never says where it is made")
        }
        // The clip topic covers the two choices the setup sheet asks for and nothing else
        // explains: how long, what shape, and the rider's own music.
        let clip = HelpCatalog.topic(.replayClip).body.joined(separator: " ").lowercased()
        for word in ["9:16", "music", "second"] {
            #expect(clip.contains(word), "the clip topic never mentions \(word)")
        }
        // The shared FIT is scrubbed, and the topic names the analyzer that can open it.
        let fit = HelpCatalog.topic(.shareFit)
        #expect(fit.body.joined(separator: " ").contains(Branding.site))
        #expect(fit.links.contains { $0.url.absoluteString == Branding.siteURL })
        // A friend's session is shown but never counted — the whole point of the prompt.
        let rider = HelpCatalog.topic(.riderAttribution).body.joined(separator: " ")
        #expect(rider.lowercased().contains("records"))
        #expect(rider.lowercased().contains("trends"))
    }

    /// The de-jargoned source topic. The engine's letters are allowed to survive in the
    /// code; they are not allowed to survive in the copy, because "class b" names a bucket
    /// in somebody else's taxonomy and answers nothing a rider asked.
    @Test func theSourceTopicAnswersDoINeedTheWatchApp() {
        let topic = HelpCatalog.topic(.sourceClass)
        let all = ([topic.title, topic.summary] + topic.body
                   + topic.items.flatMap { [$0.term, $0.detail] }).joined(separator: " ")
        for jargon in ["class a", "class b", "class c", "Class a", "Class b", "Class c"] {
            #expect(!all.contains(jargon), "the source topic still says \"\(jargon)\"")
        }
        #expect(topic.summary.contains("CleanJibe watch app"))
        #expect(topic.items.count == 3)
    }

    /// The app says *you* and *CleanJibe*, never *we*. A help catalogue is the one place
    /// the author slips into the first person, because he is describing his own work —
    /// and "our own recordings" tells a rider nothing about which of his files qualifies.
    @Test func theHelpCatalogueNeverSpeaksInTheFirstPerson() {
        // Whole words: "your own" and "your watch" both contain the letters of the slips,
        // and both are exactly the voice the app is supposed to be in.
        let firstPerson = try! Regex(#"\b(our|we|we've|us)\b"#).ignoresCase()
        for topic in HelpCatalog.topics {
            let prose = ([topic.title, topic.summary] + topic.body
                         + topic.items.flatMap { [$0.term, $0.detail] }
                         + [topic.image?.caption].compactMap { $0 })
                .joined(separator: " ")
            #expect(prose.firstMatch(of: firstPerson) == nil,
                    "\(topic.id.rawValue) speaks in the first person")
            // And the watch app has one name.
            let lower = prose.lowercased()
            #expect(!lower.contains("wingfoil watch"), "\(topic.id.rawValue) uses the old name")
            #expect(!lower.contains("wingfoil connect iq"),
                    "\(topic.id.rawValue) uses the old name")
        }
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

    /// The card's stats *are* the key-metrics block, cell for cell. This is the assertion
    /// that keeps a posted picture and the app's own summary of the same session from
    /// naming different numbers with different words.
    @Test func shareCardCompletePresetMirrorsTheKeyMetricsBlock() {
        var records = GP3SRecords()
        records.best2sKn = 13.209
        let block = KeyMetrics.make(summary: torboleSummary(), records: records)
        let stats = ShareCardStats.make(row: sampleRow(), title: "Torbole", metrics: block,
                                        preset: .complete,
                                        timeZone: TimeZone(identifier: "UTC")!)

        #expect(stats.title == "Torbole")
        #expect(stats.stats.map(\.key)
                == ["duration", "distance", "avgSpeed", "max2s", "tally", "streaks",
                    "jph", "wph"])
        // Labels and values verbatim from the block — no rewording, no reformatting.
        for metric in block.basics + [block.maxSpeed] + block.rates {
            let cell = stats.stats.first { $0.key == metric.key }
            #expect(cell?.label == metric.label)
            #expect(cell?.value == metric.value)
        }
        #expect(stats.stats.first { $0.key == "streaks" }?.value == "5 flew · 11 dry")
        // The tally keeps its three counts *as counts*, so the card can draw them on the
        // ladder's inks, and carries the block's own caption.
        let tally = stats.stats.first { $0.key == "tally" }
        #expect(tally?.value == "35 · 8 · 7")
        #expect(tally?.caption == "of 50 jibes · 12 clean")
        #expect(tally?.tally == block.tally)
        #expect(stats.disclaimer == nil)
    }

    /// The flight count is gone. It was the card's own invention — the key-metrics block
    /// never carried it — and "23 flights" says nothing a rider wants on a picture.
    @Test func shareCardNoLongerCarriesTheFlightCount() {
        var records = GP3SRecords()
        records.best2sKn = 13.209
        let block = KeyMetrics.make(summary: torboleSummary(), records: records)
        for preset in ShareCardStats.Preset.allCases {
            let stats = ShareCardStats.make(row: sampleRow(), title: "x", metrics: block,
                                            preset: preset, timeZone: fixtureZone)
            #expect(!stats.stats.contains { $0.key == "flights" },
                    "\(preset.rawValue) still carries the flight count")
            #expect(!stats.stats.contains { $0.key == "foilPct" })
            #expect(!stats.stats.contains { $0.key == "longestFlight" })
        }
    }

    /// The **clip's closing card** is the block plus one cell, and that cell is the one thing
    /// the old highlight lines said that the grid did not already carry.
    ///
    /// The outro used to print the eight-cell grid and then, underneath it, two or three
    /// sentences off the commentary — "Top speed — 13.47 kn over 2 s" over a max-2 s cell
    /// saying 13.47, "New streak — 8 dry jibes" over a streaks cell saying 8. The lines are
    /// gone; the longest flight, which really was missing, is a ninth cell, and nine cells is
    /// a clean 3 × 3.
    @Test func theOutroGridIsTheBlockPlusTheLongestFlight() {
        var records = GP3SRecords()
        records.best2sKn = 13.209
        let block = KeyMetrics.make(summary: torboleSummary(), records: records)
        let outro = ShareCardStats.outro(row: sampleRow(), title: "Torbole", metrics: block,
                                         longestFlightS: 392, timeZone: fixtureZone)

        #expect(outro.stats.map(\.key)
                == ["duration", "distance", "avgSpeed", "max2s", "tally", "streaks",
                    "jph", "wph", "longestFlight"])
        #expect(outro.stats.count == 9)
        // "6:32" — the same string the replay's own caption said and the flight table prints.
        #expect(outro.stats.last?.value == FlightPairing.clock(392))
        #expect(outro.stats.last?.value == "6:32")
        #expect(outro.stats.last?.label == "longest flight")

        // Everything before it is the complete preset, cell for cell — the outro adds, it
        // never rewords.
        let card = ShareCardStats.make(row: sampleRow(), title: "Torbole", metrics: block,
                                       preset: .complete, timeZone: fixtureZone)
        #expect(Array(outro.stats.dropLast()) == card.stats)
        #expect(outro.disclaimer == card.disclaimer)
        // …and the exported card itself is untouched: it stays the strict `KeyMetrics` mirror.
        #expect(!card.stats.contains { $0.key == ShareCardStats.Key.longestFlight })
    }

    /// A session where nothing flew has an *unknown* longest flight, not a zero-second one.
    /// The grid is then eight cells, which is what it was before.
    @Test func theOutroOmitsTheFlightCellRatherThanPrintingZero() {
        var records = GP3SRecords()
        records.best2sKn = 13.209
        let block = KeyMetrics.make(summary: torboleSummary(), records: records)
        for seconds in [nil, 0, -1] as [Double?] {
            let outro = ShareCardStats.outro(row: sampleRow(), title: "x", metrics: block,
                                             longestFlightS: seconds, timeZone: fixtureZone)
            #expect(outro.stats.count == 8)
            #expect(!outro.stats.contains { $0.key == ShareCardStats.Key.longestFlight })
        }
        #expect(ShareCardStats.longestFlightStat(nil) == nil)
        #expect(ShareCardStats.longestFlightStat(0) == nil)
        #expect(ShareCardStats.longestFlightStat(65)?.value == "1:05")
    }

    /// Lean can only *remove*. If it ever substituted or reworded a cell it would be a
    /// second vocabulary again, and the card would be free to disagree with the app.
    @Test func leanPresetIsAStrictSubsetOfComplete() {
        var records = GP3SRecords()
        records.best2sKn = 13.209
        let block = KeyMetrics.make(summary: torboleSummary(), records: records)
        let complete = ShareCardStats.make(row: sampleRow(), title: "x", metrics: block,
                                           preset: .complete, timeZone: fixtureZone).stats
        let lean = ShareCardStats.make(row: sampleRow(), title: "x", metrics: block,
                                       preset: .lean, timeZone: fixtureZone).stats

        #expect(lean.map(\.key) == ["duration", "distance", "max2s", "tally"])
        #expect(lean.count < complete.count)
        for cell in lean {
            #expect(complete.contains(cell), "\(cell.key) was reworded by the preset")
        }
        // The order the block reads in survives the filter.
        #expect(lean.map(\.key) == complete.map(\.key).filter(lean.map(\.key).contains))
        #expect(ShareCardStats.Preset.complete == ShareCardStats.Preset.allCases.last)
    }

    /// The rate cells disappear on a session with no hour to divide by — the same rule
    /// `KeyMetrics` applies, because it is the same list.
    @Test func shareCardHidesTheRatesWhenTheBlockHasNone() {
        var summary = SessionSummary(foilTimeS: 0, foilPct: 0, flightCount: 0,
                                     longestFlightS: 0, longestFlightM: 0, distanceKm: 0)
        summary.apply(SessionRates(durationS: 0, distanceM: 0, turnsCounted: 0, dryJibes: 0,
                                   fellIn: 0))
        let block = KeyMetrics.make(summary: summary, records: GP3SRecords())
        let stats = ShareCardStats.make(row: sampleRow(), title: "x", metrics: block, timeZone: fixtureZone)
        #expect(stats.stats.map(\.key) == ["duration", "distance", "avgSpeed", "max2s"])
        #expect(!stats.stats.contains { $0.key == "jph" || $0.key == "wph" })
        // Nothing measured is "—", never a fabricated 0.00 kn.
        #expect(stats.stats.allSatisfy { !$0.value.contains("0.00") })
        #expect(stats.stats.first { $0.key == "max2s" }?.value == "—")
    }

    /// The card is an image, so "not measured" has to be printed, not left to an optional
    /// binding — a card claiming "0.00 kn" would be a lie with a share sheet attached.
    ///
    /// Without an analysis the card falls back to the three facts the index row carries.
    /// It must not reconstruct a tally out of the whole-turn columns: the block one screen
    /// away counts *jibe* outcomes, and the two sets differ on most sessions.
    @Test func shareCardPrintsPlaceholdersRatherThanZero() {
        var row = SessionRow(id: "s2", startDate: Date(), durationS: 600, sourceClass: "c")
        row.flightCount = nil
        let stats = ShareCardStats.make(row: row, title: "Session", timeZone: fixtureZone)
        #expect(stats.stats.map(\.key) == ["duration", "distance", "max2s"])
        #expect(stats.stats.allSatisfy { !$0.value.contains("0.00") })
        #expect(stats.stats.first { $0.key == "max2s" }?.value == "—")
        #expect(stats.stats.first { $0.key == "distance" }?.value == "—")
        // A ten-minute session, said in minutes and seconds. This printed "0:10" until
        // 0.8.2 — an hours-and-minutes reading of a number that is not hours.
        #expect(stats.stats.first { $0.key == "duration" }?.value == "10:00 min")
        #expect(!stats.stats.contains { $0.key == "tally" })
    }

    @Test func shareCardDisclaimsUncertifiedSources() {
        let stats = ShareCardStats.make(row: sampleRow(sourceClass: "c"), title: "Session", timeZone: fixtureZone)
        #expect(stats.disclaimer != nil)
    }

    /// A preference, not a per-session choice — and one that defaults to showing the whole
    /// block, because a rider who never touched the picker asked for the app's own summary.
    @Test func shareCardPresetSurvivesTheRoundTripAndDefaultsToComplete() throws {
        let defaults = try scratchDefaults()
        #expect(ShareCardPresetStore.load(from: defaults) == .complete)

        ShareCardPresetStore.save(.lean, to: defaults)
        #expect(ShareCardPresetStore.load(from: defaults) == .lean)

        // A value from a build that knows a preset this one does not must not strand the
        // composer on a blank card.
        defaults.set("exhaustive", forKey: ShareCardPresetStore.defaultsKey)
        #expect(ShareCardPresetStore.load(from: defaults) == .complete)
    }

    /// The card names the app and where to find it, from one constant — the same one the
    /// invitation that travels with a shared FIT reads. Both halves have moved once already
    /// (the GitHub Pages URL, before `cleanjibe.org` was registered; the name, when the
    /// domain became the brand), which is why they are constants and not six string
    /// literals.
    @Test func brandingCreditIsTheNameAndTheSite() {
        #expect(Branding.credit == "CleanJibe · cleanjibe.org")
        #expect(Branding.siteURL == "https://cleanjibe.org")
        #expect(Branding.credit.hasPrefix(Branding.appName))
        #expect(Branding.credit.hasSuffix(Branding.site))
    }

    /// The brand, pinned. Every one of these is print — a card that has left the phone as a
    /// PNG, a message already in somebody's chat — so a drift here is not a thing that can be
    /// fixed by shipping an update.
    ///
    /// **The call to action is pinned character for character** because the web share card
    /// prints the same line (`docs/presentation.md`, the card contract) and the two are read
    /// side by side in the same feed. Note the case: `CleanJibe` is the brand, `wingfoil` in
    /// the CTA is the sport, and the CTA leads lowercase because it is a subtitle under the
    /// wordmark rather than a sentence beside it.
    @Test func theBrandIsCleanJibeAndTheCallToActionMatchesTheWeb() {
        #expect(Branding.appName == "CleanJibe")
        #expect(Branding.site == "cleanjibe.org")
        #expect(Branding.callToAction
                == "analyze your wingfoil sessions free — cleanjibe.org")
        // The sport word stays lowercase; the brand never appears in the CTA.
        #expect(!Branding.callToAction.contains("WingFoil"))
        #expect(!Branding.callToAction.contains(Branding.appName))
        #expect(Branding.callToAction.hasSuffix(Branding.site))
        // Nothing that leaves the phone still carries the old name.
        for line in [Branding.credit, Branding.callToAction, Branding.siteURL] {
            #expect(!line.contains("WingFoil"))
        }
    }

    @Test func shareCardShapesAreTheDocumentedPixelSizes() {
        #expect(ShareCardStats.Shape.portrait.size == (1080, 1350))
        #expect(ShareCardStats.Shape.square.size == (1080, 1080))
        #expect(ShareCardStats.Shape.landscape.size == (1920, 1080))
    }

    /// The renderer switches its whole axis on `isWide` rather than on a case, so the flag
    /// and the pixels have to agree — a shape that lied here would put the track above the
    /// stats on a 16:9 card and squash both.
    @Test func onlyTheWideShapeLaysOutSideBySide() {
        #expect(ShareCardStats.Shape.landscape.isWide)
        #expect(!ShareCardStats.Shape.portrait.isWide)
        #expect(!ShareCardStats.Shape.square.isWide)
        for shape in ShareCardStats.Shape.allCases {
            #expect(shape.isWide == (shape.size.width > shape.size.height))
            #expect(!shape.label.isEmpty)
        }
        // The picker shows all three; the card content itself does not vary by shape, so
        // one set of stats has to survive every aspect.
        #expect(ShareCardStats.Shape.allCases.count == 3)
        #expect(Set(ShareCardStats.Shape.allCases.map(\.label)).count == 3)
    }

    // MARK: - Key metrics

    private func outcomes(_ flew: Int, _ touch: Int, _ fell: Int) -> OutcomeCounts {
        var counts = OutcomeCounts()
        counts.flewThrough = flew
        counts.touchdown = touch
        counts.fellIn = fell
        return counts
    }

    /// The 29 Aug Torbole session's own numbers, from its golden — the block is eyeballed
    /// against this one, so it is the one pinned here.
    private func torboleSummary() -> SessionSummary {
        var summary = SessionSummary(foilTimeS: 3780, foilPct: 53.8, flightCount: 31,
                                     longestFlightS: 424, longestFlightM: 1580,
                                     distanceKm: 22.985)
        summary.apply(SessionRates(durationS: 7029, distanceM: 22_985, turnsCounted: 51,
                                   dryJibes: 43, fellIn: 25))
        summary.turns.turnsCounted = 51
        summary.turns.jibes = 50
        // The strict verdict: 12 of the 50 jibes were flown all the way through with the
        // speed carried. Deliberately far below the ladder's 35 fly-throughs — the two
        // numbers answer different questions and the block prints both.
        summary.turns.jibesSuccessful = 12
        summary.turns.turnsSuccessful = 12
        summary.turns.longestDryStreak = 11
        summary.turns.longestFlewStreak = 5
        summary.turns.outcomes = outcomes(35, 8, 8)
        summary.turns.jibeOutcomes = outcomes(35, 8, 7)
        return summary
    }

    @Test func keyMetricsCarryTheFourRowsInOrder() {
        var records = GP3SRecords()
        records.best2sKn = 13.209
        let block = KeyMetrics.make(summary: torboleSummary(), records: records)

        #expect(block.basics.map(\.key) == ["duration", "distance", "avgSpeed"])
        #expect(block.basics[0].value == "1:57 h")
        #expect(block.basics[1].value == "23.0 km")
        // 11.77 km/h in the app's own unit — every other speed on the screen is knots.
        #expect(block.basics[2].value == "6.36 kn")
        #expect(block.maxSpeed.value == "13.21 kn")
        #expect(block.maxSpeed.label == "max 2 s")
        #expect(block.tally?.flewThrough == 35)
        #expect(block.tally?.touchdown == 8)
        #expect(block.tally?.fellIn == 7)
        #expect(block.tally?.caption == "of 50 jibes · 12 clean")
        #expect(block.streaks?.value == "5 flew · 11 dry")
        #expect(block.rates.map(\.key) == ["jph", "wph"])
        // 43 dry jibes of 50 over 1:57 — the rate counts the ones he sailed out of, and the
        // label says so, because 50/h would be a different number under the same word.
        #expect(block.rates[0].label == "JPH · dry jibes per hour")
        #expect(block.rates[0].value == "22.0")
        #expect(block.rates[1].value == "12.8")
    }

    /// No duration ⇒ the engine reports every rate as null, and the row disappears rather
    /// than printing "0.0 JPH" over a rider who was never given an hour to divide by.
    @Test func keyMetricsHideTheRateRowWithoutADuration() {
        var summary = SessionSummary(foilTimeS: 0, foilPct: 0, flightCount: 0,
                                     longestFlightS: 0, longestFlightM: 0, distanceKm: 0)
        summary.apply(SessionRates(durationS: 0, distanceM: 0, turnsCounted: 0, dryJibes: 0,
                                   fellIn: 0))
        let block = KeyMetrics.make(summary: summary, records: GP3SRecords())
        #expect(block.rates.isEmpty)
        #expect(block.basics[0].value == "0:00 min")
        // Nothing measured is "—", never a fabricated 0.00 kn.
        #expect(block.maxSpeed.value == "—")
        #expect(block.basics[2].value == "—")
        // No counted turn ⇒ no tally and no streaks: three zeros are not a verdict.
        #expect(block.tally == nil)
        #expect(block.streaks == nil)
    }

    /// A session whose wind axis never resolved has turns and no jibes. JPH would read
    /// 0.0 over an afternoon of jibing, so both the rate and the tally fall back to the
    /// turn channel — and both say so in their own label.
    @Test func keyMetricsFallBackToTurnsWhenNoJibeWasNamed() {
        var summary = SessionSummary(foilTimeS: 600, foilPct: 30, flightCount: 4,
                                     longestFlightS: 60, longestFlightM: 300,
                                     distanceKm: 5)
        summary.apply(SessionRates(durationS: 3600, distanceM: 5000, turnsCounted: 12,
                                   dryJibes: 0, fellIn: 3))
        summary.turns.turnsCounted = 12
        summary.turns.turnsSuccessful = 4
        summary.turns.unclassified = 12
        summary.turns.longestDryStreak = 4
        summary.turns.longestFlewStreak = 2
        summary.turns.outcomes = outcomes(6, 4, 2)
        let block = KeyMetrics.make(summary: summary, records: GP3SRecords())

        #expect(block.rates.map(\.key) == ["tph", "wph"])
        #expect(block.rates[0].label == "TPH · turns per hour")
        #expect(block.rates[0].value == "12.0")
        #expect(block.tally?.caption == "of 12 turns · 4 clean")
        #expect(block.tally?.flewThrough == 6)
    }

    /// A measured zero is a value: a session with a duration and no turns really did do
    /// 0.0 jibes an hour, and that is JPH — not the TPH fallback, which exists only for
    /// turns the wind axis could not name.
    @Test func keyMetricsKeepJPHWhenThereWereNoTurnsAtAll() {
        var summary = SessionSummary(foilTimeS: 30, foilPct: 50, flightCount: 1,
                                     longestFlightS: 30, longestFlightM: 100,
                                     distanceKm: 0.226)
        summary.apply(SessionRates(durationS: 59, distanceM: 226, turnsCounted: 0,
                                   dryJibes: 0, fellIn: 0))
        let block = KeyMetrics.make(summary: summary, records: GP3SRecords())
        #expect(block.rates.map(\.key) == ["jph", "wph"])
        #expect(block.rates[0].value == "0.0")
        #expect(block.tally == nil)
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

    // MARK: - Thumbnail marks

    /// The card's three semantics and no more: the verdict ladder on the *counted* turns,
    /// and the barometer's submersion evidence on both of its channels. A bear-away is a
    /// course change, not a verdict, and gets no dot — the same rule the map draws by.
    ///
    /// Asserted against a decoded golden rather than a hand-built session, for the reason
    /// `ReplayBeatsTests` gives: a synthetic analysis can be made to agree with any rule at
    /// all. 29 Aug Torbole has 51 counted turns (35 · 8 · 8), 11 uncounted ones, and seven
    /// splashes across three turns and four straight-line flight ends.
    @Test func thumbnailEventsAreTheLadderPlusTheSplashes() throws {
        let url = testFixturesDir.appendingPathComponent(
            "goldens/2026-08-29-1440_nago-torbole-windsurfen_ciq.expected.json")
        let analysis = try JSONDecoder().decode(SessionAnalysis.self,
                                                from: Data(contentsOf: url))
        let events = TrackThumbnail.events(analysis)
        let counts = Dictionary(grouping: events, by: \.kind).mapValues(\.count)

        #expect(counts[.flewThrough] == 35)
        #expect(counts[.touchdown] == 8)
        #expect(counts[.fellIn] == 8)
        #expect(counts[.splash] == 7)
        // 62 turns in the session, 51 of them counted: the eleven course changes are not
        // verdicts and are not marked.
        #expect(events.count == 58)
        #expect(events.map(\.t) == events.map(\.t).sorted(), "marks must be in time order")
    }

    /// A mark has to land on the vertex it belongs to, which means going through the
    /// outline's own projection rather than a second normalization of its own.
    @Test func thumbnailMarksLandOnTheTrackTheyBelongTo() {
        let track = syntheticTrack()                       // 400 m east, then back
        let flights = [FlightRecord(Flight(startT: 0, endT: 199, distM: 400, maxKn: 20))]
        let thumb = TrackThumbnail.make(
            track: track, flights: flights,
            events: [TrackThumbnail.Event(t: 0, kind: .flewThrough),
                     TrackThumbnail.Event(t: 199, kind: .fellIn),
                     TrackThumbnail.Event(t: 199, kind: .splash)])

        #expect(thumb.marks.map(\.kind) == [.flewThrough, .fellIn, .splash])
        // t = 0 is the western end of the reach, t = 199 the eastern one.
        #expect(thumb.marks[0].x < 0.02)
        #expect(thumb.marks[1].x > 0.98)
        #expect(thumb.marks[1].x == thumb.marks[2].x)
        // Every mark sits on the polyline's own band, not in the letterbox above or below.
        let ys = thumb.points.map(\.y)
        for mark in thumb.marks {
            #expect(mark.y >= ys.min()! - 0.01 && mark.y <= ys.max()! + 0.01)
        }
    }

    /// A moment with no fix anywhere near it is dropped. A dot in the wrong bay cannot be
    /// corrected by tapping it — a card is looked at, not queried.
    @Test func thumbnailDropsAMarkWithNoPositionNearIt() {
        let thumb = TrackThumbnail.make(
            track: syntheticTrack(), flights: [],
            events: [TrackThumbnail.Event(t: 50, kind: .fellIn),
                     TrackThumbnail.Event(t: 9_999, kind: .fellIn)])
        #expect(thumb.marks.count == 1)
    }

    /// What lets the share card stop letterboxing the ride twice: the extent the track
    /// actually occupies inside the square it was normalized into. A 400 m out-and-back is
    /// a horizontal band, so its content box is full width and a sliver high.
    @Test func thumbnailContentBoxIsTheTrackNotTheUnitSquare() throws {
        let thumb = TrackThumbnail.make(track: syntheticTrack(), flights: [])
        let box = try #require(thumb.contentBox)
        #expect(box.minX < 0.01 && box.maxX > 0.99)
        #expect(box.maxY - box.minY < 0.05)
        #expect(box.minY > 0.4 && box.maxY < 0.6, "the short axis is centred")
        // Nothing to fit is nothing to divide by.
        #expect(TrackThumbnail(points: [], speed: [], maxKn: 0).contentBox == nil)
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
                                 .takeoff, .splash, .direction])
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

    /// A real session's own figures (fixtures/goldens, 2026-08-07 ciq `hr.summary`).
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
        // One decimal on the operands too — see `hrPumpCruiseDeltaAgreesWithItsOperands`.
        #expect(card.stats[1].caption == "101.6 vs 96.0 bpm on the foil")
        #expect(card.stats[2].value == "12 s")
        #expect(card.stats[2].caption == "halfway back · 14 of 15 rises")
        #expect(card.stats[3].value == "18 s")
        #expect(card.stats[3].caption == "halfway back · 4 of 7 swims")
        #expect(card.stats.prefix(3).allSatisfy { !$0.thin })
        // 4 of 7 is below `thinCoveragePct`: the number is real, and the reader is told not
        // to lean on it. This is that session's own figure.
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
        #expect(card.stats[1].caption == "101.6 vs 96.0 bpm on the foil · 44% covered")
        #expect(card.stats[1].thin)
    }

    /// **The delta and the two numbers it came from must reconcile on screen.**
    ///
    /// The card read `Pumping vs cruising · -0.1 bpm · 119 vs 119 bpm on the foil` on the
    /// corpus (app-ui-review.md §5.7): a delta asserting a difference over two operands
    /// that, as displayed, were the same number. The contract already forbids the adjacent
    /// version of this ("a measured zero is a value, and −0 must never appear"), and this
    /// is the same rule one step out — do not print a delta finer than the numbers beside
    /// it. So all three are printed at one decimal, and the delta is derived from the
    /// *printed* operands rather than the raw ones, which makes the arithmetic exact
    /// rather than merely usually right.
    @Test func hrPumpCruiseDeltaAgreesWithItsOperands() throws {
        // The pair that produced the bad card: a real difference, invisible at 0 decimals.
        var s = exampleSummary()
        s.pumpCruise.pumpingBpm = 119.24
        s.pumpCruise.cruisingBpm = 119.31
        s.pumpCruise.deltaBpm = -0.07
        let card = try #require(HrCostCard.make(analysis(s)))
        #expect(card.stats[1].caption == "119.2 vs 119.3 bpm on the foil")
        #expect(card.stats[1].value == "-0.1 bpm")

        // The rounding boundary that a delta taken from the raw pair would get wrong: the
        // operands print 0.2 apart, so the delta has to say 0.2 and not the raw 0.102.
        s.pumpCruise.pumpingBpm = 119.351
        s.pumpCruise.cruisingBpm = 119.249
        s.pumpCruise.deltaBpm = 0.102
        let boundary = try #require(HrCostCard.make(analysis(s)))
        #expect(boundary.stats[1].caption == "119.4 vs 119.2 bpm on the foil")
        #expect(boundary.stats[1].value == "+0.2 bpm")

        // And a genuinely equal pair still prints the measured zero, unsigned, rather than
        // the "-0.0 bpm" that a signed formatter produces for a small negative.
        s.pumpCruise.pumpingBpm = 118.0
        s.pumpCruise.cruisingBpm = 118.0
        s.pumpCruise.deltaBpm = -0.004
        let equal = try #require(HrCostCard.make(analysis(s)))
        #expect(equal.stats[1].caption == "118.0 vs 118.0 bpm on the foil")
        #expect(equal.stats[1].value == "0 bpm")
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
            // Carried its speed (0.78 clears the threshold) and still touched down: the
            // one turn where "clean" and "flew through" disagree, which is the whole
            // reason they are two numbers.
            try turn(300, type: "jibe", side: "starboard", direction: "port",
                     outcome: "touchdown", score: 0.78),
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
        // The stricter verdict over the same six turns: the four that cleared the success
        // threshold (0.82, 0.78, 0.90, 0.75). Deliberately *not* the flew-through count —
        // the 0.78 jibe carried its speed and still touched down.
        #expect(all.clean == 4)
        #expect(all.cleanCaption == "4 of 6 clean")

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
        // Nothing to be clean out of, so the strict line is absent rather than "0 of 0".
        #expect(noTacks.clean == 0)
        #expect(noTacks.cleanCaption == "")
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
        #expect(submerged.clean, "0.90 clears the success threshold")
        #expect(submerged.detail.contains("wrist under"))
        #expect(submerged.accessibilityText.contains("Jibe, starboard entry"))
        #expect(submerged.accessibilityText.contains("flew through"))
        #expect(submerged.accessibilityText.contains("clean"))

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

    // MARK: - Trends: flew through by entry tack

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

    // MARK: - Timeline zoom

    private func window(minutes: Double) -> TimelineWindow {
        TimelineWindow(full: 1000...(1000 + minutes * 60))
    }

    /// The reason zoom exists: on a long session the marks pile up, and the fix is to show
    /// fewer seconds. So the window must actually *narrow*, and it must report by how much.
    @Test func pinchingNarrowsTheWindowAndKeepsTheAnchorUnderTheFinger() {
        var w = window(minutes: 80)
        #expect(!w.isZoomed)
        #expect(w.factor == 1)

        let anchor = 1000 + 2400.0                     // half way in
        w.magnify(by: 4, around: anchor)
        #expect(w.isZoomed)
        #expect(abs(w.factor - 4) < 0.001)
        #expect(abs(w.span - 1200) < 0.001)
        // The pinch centre was in the middle of the window and stays in the middle of it.
        #expect(abs((anchor - w.visible.lowerBound) / w.span - 0.5) < 0.001)

        // Pinches compose: a second 3× on top of a 4× is a 12× view, not a 3× one.
        w.magnify(by: 3, around: anchor)
        #expect(abs(w.factor - 12) < 0.001)
    }

    /// A pinch at either end must not slide the window off the recording — the commonest
    /// way a hand-rolled visible domain shows you a chart of nothing.
    @Test func zoomingClampsAtBothSessionEdges() {
        var w = window(minutes: 80)
        w.magnify(by: 8, around: w.full.lowerBound)
        #expect(w.visible.lowerBound == w.full.lowerBound)
        #expect(w.visible.upperBound <= w.full.upperBound)
        #expect(abs(w.startFraction) < 0.0001)

        w.reset()
        w.magnify(by: 8, around: w.full.upperBound)
        #expect(w.visible.upperBound == w.full.upperBound)
        #expect(w.visible.lowerBound >= w.full.lowerBound)
        #expect(abs(w.endFraction - 1) < 0.0001)

        // Panning past the end stops at the end rather than scrolling into empty water.
        w.pan(bySeconds: 99_999)
        #expect(w.visible.upperBound == w.full.upperBound)
        w.pan(bySeconds: -99_999)
        #expect(w.visible.lowerBound == w.full.lowerBound)
    }

    /// Zooming out past the session, or in past the resolution of the speed series, are both
    /// refusals rather than surprises.
    @Test func theWindowNeverLeavesItsLimits() {
        var w = window(minutes: 80)
        w.magnify(by: 1000, around: 1000 + 2400)
        #expect(abs(w.span - w.minSpan) < 0.001)
        #expect(abs(w.factor - TimelineWindow.maxFactor) < 0.001)

        w.magnify(by: 0.01, around: 1000 + 2400)
        #expect(w.span == w.fullSpan)
        #expect(!w.isZoomed, "back to the whole session must retire the reset chip")

        // A short session still zooms — to 20 s, the floor, not to a proportional sliver.
        var short = window(minutes: 4)
        short.magnify(by: 1000, around: 1000)
        #expect(abs(short.span - TimelineWindow.minSpanS) < 0.001)
    }

    /// What the chart draws is `contains` and `clipped`: marks outside the window are not
    /// drawn at all (that decluttering *is* the feature), while a flight band that straddles
    /// the edge is cut to fit rather than dropped — the water it covers was still flown.
    @Test func theWindowFiltersMarksAndClipsSpans() {
        var w = window(minutes: 80)
        w.zoom(to: 8, centeredOn: 1000 + 2400)         // 600 s around the middle
        #expect(abs(w.visible.lowerBound - (1000 + 2100)) < 0.001)
        #expect(abs(w.visible.upperBound - (1000 + 2700)) < 0.001)

        let marks = [1000.0, 3000, 3100, 3400, 3700, 4200]
        #expect(marks.filter(w.contains) == [3100, 3400, 3700])

        // Straddling both edges, one edge, and missing entirely.
        #expect(w.clipped(start: 0, end: 9999) == w.visible)
        #expect(w.clipped(start: 2000, end: 3200) == 3100...3200)
        #expect(w.clipped(start: 3800, end: 4000) == nil)
        // A zero-length span exactly on the edge still belongs to the window.
        #expect(w.clipped(start: 3700, end: 3700) == 3700...3700)

        #expect(w.clamp(0) == w.visible.lowerBound)
        #expect(w.clamp(9999) == w.visible.upperBound)
    }

    /// Replay has to stay watchable while zoomed: when the playhead walks out of the window,
    /// the window follows it instead of the rider losing the dot.
    @Test func theWindowFollowsAPlayheadThatWalksOutOfIt() {
        var w = window(minutes: 80)
        w.zoom(to: 10, centeredOn: 1000 + 1000)        // 480 s wide
        let span = w.span
        let inside = w.visible.lowerBound + span / 2
        w.reveal(inside)
        #expect(abs(w.span - span) < 0.001, "a playhead in the middle moves nothing")

        let ahead = w.visible.upperBound + 5
        w.reveal(ahead)
        #expect(w.contains(ahead))
        #expect(abs(w.span - span) < 0.001, "revealing pans, it never rezooms")

        let behind = w.visible.lowerBound - 60
        w.reveal(behind)
        #expect(w.contains(behind))

        // And at the very end of the session it stops rather than scrolling past it.
        w.reveal(w.full.upperBound)
        #expect(w.visible.upperBound == w.full.upperBound)
        #expect(w.contains(w.full.upperBound))

        w.reset()
        #expect(!w.isZoomed)
        #expect(w.visible == w.full)
    }

    /// The tapped flight frames itself, with its approach and its landing either side.
    @Test func focusingOnAFlightFramesItWithAMargin() {
        var w = window(minutes: 80)                       // 1000…5800
        w.focus(on: 2000...2200)
        #expect(w.isZoomed)
        #expect(abs(w.visible.lowerBound - 1960) < 0.001, "20 % of 200 s of margin in front")
        #expect(abs(w.visible.upperBound - 2240) < 0.001)
        #expect(w.contains(2000) && w.contains(2200))

        // A flight at the very start cannot be centred; the window clamps rather than
        // scrolling off the recording.
        w.focus(on: 1000...1100)
        #expect(w.visible.lowerBound == w.full.lowerBound)
        #expect(w.contains(1100))

        // A hop shorter than the floor still opens a readable window rather than a sliver.
        w.focus(on: 3000...3002)
        #expect(abs(w.span - w.minSpan) < 0.001)
        #expect(w.contains(3000) && w.contains(3002))
    }

    // MARK: - Phase cut at the flight boundaries
    //
    // The bug this exists for: on a coarse source an off-foil span can contain no positioned
    // sample at all, so "is this fix inside a flight?" never changes across the landing and
    // two flights draw as one. Every case below is a boundary that no sample sits inside.

    private func line(_ times: [Double], segment: Int = 0) -> [TrackPhaseCut.Point] {
        // Due east from Torbole, 10 m per second of session clock, so a point's longitude
        // is a direct reading of its time and an interpolation can be checked by hand.
        let lat = 45.87
        let metresPerDegLon = 111_320 * cos(lat * .pi / 180)
        return times.map { TrackPhaseCut.Point(t: $0, lat: lat,
                                               lon: 10.87 + ($0 * 10) / metresPerDegLon,
                                               segment: segment) }
    }

    /// The longitude a point *should* have if it sits at time `t` on the line above.
    private func lon(at t: Double) -> Double {
        10.87 + (t * 10) / (111_320 * cos(45.87 * .pi / 180))
    }

    @Test func aBoundaryInsideASampleIntervalIsCutOnAnInterpolatedPoint() {
        let points = line([0, 10, 20, 30])
        let runs = TrackPhaseCut.runs(points, flights: [TrackPhaseCut.Span(start: 5, end: 25)])

        #expect(runs.map(\.flying) == [false, true, false])
        // The cut lands at t = 5, between the fixes at 0 and 10, and it is the last point of
        // one run and the first of the next — a shared vertex, so the line has no hole.
        #expect(runs[0].points.last?.t == 5)
        #expect(runs[1].points.first?.t == 5)
        #expect(abs((runs[0].points.last?.lon ?? 0) - lon(at: 5)) < 1e-9,
                "the cut coordinate must sit on the line the map already draws")
        #expect(runs[1].points.last?.t == 25)
        #expect(runs[2].points.first?.t == 25)
        #expect(abs((runs[2].points.first?.lon ?? 0) - lon(at: 25)) < 1e-9)
        // Nothing was invented: every interior point is still a real fix.
        #expect(runs[1].points.map(\.t) == [5, 10, 20, 25])
    }

    /// The corpus case: the boundary falls exactly *on* a fix, and the two fixes either side
    /// of the landing are both inside a flight. Tinting per sample sees no change at all.
    @Test func aBoundaryExactlyOnASampleStillCutsTheTrack() {
        // Flight one ends at 364 (a fix), flight two starts at 369 (a fix), and nothing was
        // recorded in between — the 2026-08-06 wingfoiling session's own shape.
        let points = line([360, 362, 364, 369, 371])
        let flights = [TrackPhaseCut.Span(start: 358, end: 364),
                       TrackPhaseCut.Span(start: 369, end: 375)]
        let runs = TrackPhaseCut.runs(points, flights: flights)

        #expect(runs.map(\.flying) == [true, false, true],
                "the landing must produce an off-foil run of its own")
        let stub = runs[1]
        #expect(stub.points.map(\.t) == [364, 369], "the stub is the two fixes that bracket it")
        #expect(runs[0].points.last?.t == 364)
        #expect(runs[2].points.first?.t == 369)
        // No duplicated vertex where a cut landed on a fix.
        #expect(runs[0].points.map(\.t) == [360, 362, 364])
    }

    /// The same gap, but the recording itself broke across it (the engine's own segment id
    /// changes). The line still has to be cut and the stub still has to be drawn: those two
    /// fixes are the only evidence there is of where the phase changed.
    @Test func aRecordingGapBreaksTheLineExceptAcrossABoundary() {
        var points = line([360, 362, 364])
        points += line([369, 371], segment: 1)
        let flights = [TrackPhaseCut.Span(start: 358, end: 364),
                       TrackPhaseCut.Span(start: 369, end: 375)]
        #expect(TrackPhaseCut.runs(points, flights: flights).map(\.flying)
                == [true, false, true])

        // Away from a boundary the gap does break the line — a pause on the beach is not a
        // stretch of water he rode across.
        var pause = line([100, 102, 104])
        pause += line([400, 402], segment: 1)
        let runs = TrackPhaseCut.runs(pause, flights: [])
        #expect(runs.count == 2)
        #expect(runs[0].points.map(\.t) == [100, 102, 104])
        #expect(runs[1].points.map(\.t) == [400, 402])
    }

    @Test func anOffFoilSpanningManyMissingSamplesIsOneStub() {
        // A 30 s swim with a single fix in the middle of it.
        let points = line([100, 110, 125, 140, 150])
        let flights = [TrackPhaseCut.Span(start: 90, end: 112),
                       TrackPhaseCut.Span(start: 142, end: 160)]
        let runs = TrackPhaseCut.runs(points, flights: flights)
        #expect(runs.map(\.flying) == [true, false, true])
        #expect(runs[1].points.map(\.t) == [112, 125, 140, 142])
        #expect(abs((runs[1].points.first?.lon ?? 0) - lon(at: 112)) < 1e-9)
        #expect(abs((runs[1].points.last?.lon ?? 0) - lon(at: 142)) < 1e-9)
    }

    /// A flight the recording never sampled: both of its boundaries fall inside one sample
    /// interval. It is still a flight, and it still gets a (short) teal run.
    @Test func aFlightShorterThanOneSampleIntervalStillDraws() {
        let points = line([0, 10, 20])
        let runs = TrackPhaseCut.runs(points, flights: [TrackPhaseCut.Span(start: 12, end: 16)])
        #expect(runs.map(\.flying) == [false, true, false])
        #expect(runs[1].points.map(\.t) == [12, 16])
        #expect(abs((runs[1].points[0].lon) - lon(at: 12)) < 1e-9)
        #expect(abs((runs[1].points[1].lon) - lon(at: 16)) < 1e-9)
        #expect(runs[0].points.map(\.t) == [0, 10, 12])
        #expect(runs[2].points.map(\.t) == [16, 20])
    }

    /// The degenerate inputs a real recording produces: nothing at all, a flight covering
    /// everything, and a boundary outside the samples entirely.
    @Test func thePhaseCutSurvivesDegenerateInput() {
        #expect(TrackPhaseCut.runs([], flights: [TrackPhaseCut.Span(start: 0, end: 1)]).isEmpty)
        let points = line([0, 10, 20])
        #expect(TrackPhaseCut.runs(points, flights: []).map(\.flying) == [false])
        let whole = TrackPhaseCut.runs(points,
                                       flights: [TrackPhaseCut.Span(start: -5, end: 25)])
        #expect(whole.map(\.flying) == [true])
        #expect(whole[0].points.map(\.t) == [0, 10, 20], "no cut, no invented point")
        // A single fix is not a stretch of water and draws nothing.
        #expect(TrackPhaseCut.runs(line([0]), flights: []).isEmpty)
    }

    // MARK: - Pairing (tap only)

    private func pairingFlight(index: Int = 11, count: Int = 55, start: Double = 2467,
                               end: Double = 2550, distM: Double? = 272,
                               pumps: Int? = 7,
                               outcome: FlightPairing.Outcome = .touchdown)
    -> FlightPairing.Flight {
        FlightPairing.Flight(index: index, count: count, startTs: start, endTs: end,
                             distM: distM, pumps: pumps, outcome: outcome)
    }

    /// The four lines, exactly as docs/presentation.md writes them. The web app draws the
    /// same four; a difference here is a difference the two apps would ship.
    @Test func thePairingLinesAreTheContractsWording() {
        let flight = pairingFlight()
        #expect(FlightPairing.takeoffLine(flight)
                == "starts flight 12 · 1:23 · ended: touchdown")
        #expect(FlightPairing.flightEndLine(flight)
                == "ends flight 12 · started 41:07 · 7 pumps")
        #expect(FlightPairing.flightLine(flight)
                == "flight 12 of 55 · 1:23 · 272 m · ended: touchdown")
        #expect(FlightPairing.failedLine(strokes: 3) == "no flight · 3 strokes")
        #expect(FlightPairing.failedLine(strokes: 1) == "no flight · 1 stroke")
    }

    /// Absence is absence: no accelerometer means the stroke count is *missing*, and a
    /// missing clause is dropped rather than written as a zero.
    @Test func thePairingOmitsWhatWasNeverMeasured() {
        let noAccel = pairingFlight(pumps: nil)
        #expect(FlightPairing.flightEndLine(noAccel) == "ends flight 12 · started 41:07")
        #expect(!FlightPairing.flightEndLine(noAccel).contains("0 pump"))

        let noDistance = pairingFlight(distM: nil)
        #expect(FlightPairing.flightLine(noDistance)
                == "flight 12 of 55 · 1:23 · ended: touchdown")
        // A measured single stroke is a value, not an absence.
        #expect(FlightPairing.flightEndLine(pairingFlight(pumps: 1))
                == "ends flight 12 · started 41:07 · 1 pump")
    }

    /// A recording that stopped is not a verdict, and the engine's label for it must not be
    /// repeated as one.
    @Test func aTruncatedFlightEndReportsTheRecordingNotAnOutcome() {
        #expect(FlightPairing.Outcome(endOutcome: "glide_out", truncated: true)
                == .recordingEnded)
        #expect(FlightPairing.Outcome(endOutcome: "unknown", truncated: false)
                == .recordingEnded)
        #expect(FlightPairing.Outcome(endOutcome: "fell_in", truncated: false) == .fellIn)
        #expect(FlightPairing.Outcome(endOutcome: "touchdown", truncated: false) == .touchdown)
        #expect(FlightPairing.Outcome(endOutcome: "glide_out", truncated: false) == .glidedOut)
        // Every outcome word is distinct, or two different endings would read the same.
        let words = FlightPairing.Outcome.allCases.map(\.rawValue)
        #expect(Set(words).count == words.count)
    }

    /// The clock the pairing prints is the web app's `hms`: m:ss, h:mm:ss past an hour.
    @Test func thePairingClockMatchesTheWebFormat() {
        #expect(FlightPairing.clock(0) == "0:00")
        #expect(FlightPairing.clock(83) == "1:23")
        #expect(FlightPairing.clock(2467) == "41:07")
        #expect(FlightPairing.clock(3600) == "1:00:00")
        #expect(FlightPairing.clock(5493.4) == "1:31:33")
        #expect(FlightPairing.clock(-4) == "0:00")
        #expect(FlightPairing.metres(272.7) == "273 m")
        #expect(FlightPairing.metres(1420) == "1.42 km")
    }

    /// A takeoff names its flight by the instant they share, so a mark that cannot resolve
    /// one gets no line at all rather than a wrong number.
    @Test func aTakeoffResolvesItsFlightByTheInstantTheyShare() {
        let flights = [pairingFlight(index: 0, count: 2, start: 100, end: 160),
                       pairingFlight(index: 1, count: 2, start: 300, end: 340)]
        #expect(FlightPairing.flight(startingAt: 300, in: flights)?.index == 1)
        #expect(FlightPairing.flight(startingAt: 100, in: flights)?.index == 0)
        #expect(FlightPairing.flight(startingAt: 999, in: flights) == nil)
        #expect(FlightPairing.flight(covering: 320, in: flights)?.index == 1)
        #expect(FlightPairing.flight(covering: 200, in: flights) == nil, "off the foil")
        #expect(FlightPairing.flight(at: 5, in: flights) == nil)
        #expect(flights[0].number == 1 && flights[1].number == 2)
        #expect(flights[1].durationS == 40)
    }

    // MARK: - Direction of travel

    /// A straight run of `count` samples heading due east from Torbole, `stepM` apart.
    private func eastwardTrack(count: Int, stepM: Double,
                               flyingFrom: Int = .max) -> [TrackDirection.Point] {
        let lat = 45.87
        let lonStep = stepM / (111_320 * cos(lat * .pi / 180))
        return (0..<count).map {
            TrackDirection.Point(lat: lat, lon: 10.87 + Double($0) * lonStep,
                                 flying: $0 >= flyingFrom)
        }
    }

    @Test func bearingIsClockwiseFromNorthAndSurvivesTheAntimeridian() {
        func bearing(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
            TrackDirection.bearingDeg(fromLat: aLat, fromLon: aLon, toLat: bLat, toLon: bLon)
        }
        #expect(abs(bearing(45.87, 10.87, 45.88, 10.87) - 0) < 0.01)     // north
        #expect(abs(bearing(45.87, 10.87, 45.87, 10.88) - 90) < 0.01)    // east
        #expect(abs(bearing(45.87, 10.87, 45.86, 10.87) - 180) < 0.01)   // south
        #expect(abs(bearing(45.87, 10.87, 45.87, 10.86) - 270) < 0.01)   // west

        // Every bearing is normalized into 0..<360 — a chevron rotated by -90° would point
        // the wrong way on some platforms and is simply not a value this returns.
        #expect((0..<36).allSatisfy { i in
            let b = bearing(45.87, 10.87, 45.87 + cos(Double(i) * 10), 10.87 + sin(Double(i) * 10))
            return b >= 0 && b < 360
        })

        // Crossing the antimeridian eastwards is 90°, not 270° — the flat-earth formula
        // gets this exactly backwards, which is why the great-circle one is used.
        #expect(abs(bearing(0.0, 179.99, 0.0, -179.99) - 90) < 0.1)
        #expect(abs(bearing(0.0, -179.99, 0.0, 179.99) - 270) < 0.1)

        // Two samples in the same place have no direction; 0 rather than a NaN rotation.
        #expect(bearing(45.87, 10.87, 45.87, 10.87) == 0)
    }

    /// The scale is the whole point: the same track at two zooms must produce a comparable
    /// *on-screen* rhythm, which means proportionally more chevrons when zoomed in.
    @Test func chevronSpacingFollowsTheMapScale() {
        let track = eastwardTrack(count: 101, stepM: 10)      // 1 000 m due east
        let far = TrackDirection.chevrons(along: track, metresPerPoint: 10,
                                          spacingPoints: 50, maxCount: 500)
        let near = TrackDirection.chevrons(along: track, metresPerPoint: 2,
                                           spacingPoints: 50, maxCount: 500)
        #expect(far.count == 2, "500 m apart on a 1 km track")
        #expect(near.count == 10, "100 m apart on the same track")
        #expect(near.allSatisfy { abs($0.bearingDeg - 90) < 0.5 }, "all of it heads east")

        // Evenly spaced, not clumped: consecutive gaps are the requested spacing.
        for pair in zip(near, near.dropFirst()) {
            let gap = TrackDirection.metresBetween(lat1: pair.0.lat, lon1: pair.0.lon,
                                                   lat2: pair.1.lat, lon2: pair.1.lon)
            #expect(abs(gap - 100) < 1)
        }
        // A scale of zero (a map that has not been laid out yet) draws nothing at all
        // rather than dividing by it.
        #expect(TrackDirection.chevrons(along: track, metresPerPoint: 0).isEmpty)
        #expect(TrackDirection.chevrons(along: [], metresPerPoint: 5).isEmpty)
    }

    /// The budget is enforced by widening the spacing, never by stopping half way: a track
    /// arrowed for its first third and bare afterwards reads as missing data.
    @Test func theChevronBudgetWidensTheSpacingInsteadOfTruncating() throws {
        let track = eastwardTrack(count: 401, stepM: 10)      // 4 km
        let capped = TrackDirection.chevrons(along: track, metresPerPoint: 0.5,
                                             spacingPoints: 50, maxCount: 12)
        #expect(capped.count <= 12)
        #expect(capped.count >= 10)
        let last = try #require(capped.last)
        let covered = TrackDirection.metresBetween(lat1: track[0].lat, lon1: track[0].lon,
                                                   lat2: last.lat, lon2: last.lon)
        #expect(covered > 3_500, "the arrows reach the end of the track")
    }

    /// Zooming in does not mean "the same arrows, bigger": the camera box is what makes a
    /// close-up stretch get its own dense set while the rest of the session costs nothing.
    @Test func chevronsOutsideTheCameraAreNotBuilt() {
        let track = eastwardTrack(count: 201, stepM: 10)      // 2 km
        let lat = track[0].lat
        let halfway = track[100].lon
        let box = TrackDirection.Box(minLat: lat - 0.01, maxLat: lat + 0.01,
                                     minLon: track[0].lon - 0.0001, maxLon: halfway)
        let all = TrackDirection.chevrons(along: track, metresPerPoint: 2, spacingPoints: 50)
        let clipped = TrackDirection.chevrons(along: track, metresPerPoint: 2,
                                              spacingPoints: 50, within: box)
        #expect(clipped.count < all.count)
        #expect(clipped.allSatisfy { box.contains(lat: $0.lat, lon: $0.lon) })
        // Ids stay a dense 0..<n so `ForEach` has no holes in it.
        #expect(clipped.map(\.id) == Array(0..<clipped.count))
    }

    /// A chevron is tinted like the water under it, so the phase has to survive decimation
    /// rather than being looked up again from a different clock.
    @Test func chevronsCarryThePhaseOfTheWaterUnderThem() {
        let track = eastwardTrack(count: 201, stepM: 10, flyingFrom: 100)
        let chevrons = TrackDirection.chevrons(along: track, metresPerPoint: 2,
                                               spacingPoints: 50)
        #expect(chevrons.contains { $0.flying })
        #expect(chevrons.contains { !$0.flying })
        // The phase flips exactly once, at the takeoff, and never flickers back.
        let flips = zip(chevrons, chevrons.dropFirst()).filter { $0.flying != $1.flying }
        #expect(flips.count == 1)
    }

    /// MapKit fits the region, so the scale that governs is the axis that had to shrink.
    @Test func metresPerPointTakesTheTighterAxis() {
        // A wide, short region in a tall, narrow view: longitude is what is squeezed.
        let wide = TrackDirection.metresPerPoint(latSpan: 0.001, lonSpan: 0.02,
                                                 centerLat: 45.87,
                                                 widthPoints: 390, heightPoints: 260)
        #expect(abs(wide - (0.02 * 111_320 * cos(45.87 * .pi / 180) / 390)) < 0.001)
        // Half the span in the same view is half the metres per point.
        let closer = TrackDirection.metresPerPoint(latSpan: 0.0005, lonSpan: 0.01,
                                                   centerLat: 45.87,
                                                   widthPoints: 390, heightPoints: 260)
        #expect(abs(closer - wide / 2) < 0.001)
        // A view with no size yet is not a division by zero.
        #expect(TrackDirection.metresPerPoint(latSpan: 0.01, lonSpan: 0.01, centerLat: 45.87,
                                              widthPoints: 0, heightPoints: 0) == 0)
    }

    /// The compatibility rule, again, for the layer added after the direction chevrons
    /// shipped: an existing preference must keep its choices and leave `direction` on.
    @Test func directionDefaultsVisibleForPreferencesWrittenBeforeIt() throws {
        let defaults = try scratchDefaults()
        defaults.set(Data(#"["courseChange","fellIn","splash"]"#.utf8),
                     forKey: MapLayerVisibilityStore.defaultsKey)

        var loaded = MapLayerVisibilityStore.load(from: defaults)
        #expect(loaded.hiddenLayers == [.fellIn, .courseChange, .splash])
        #expect(loaded.isVisible(.direction), "direction must default to visible")
        #expect(MapLayer(rawValue: "direction") != nil,
                "UI_HIDE_LAYERS=direction would be a no-op")

        // Hiding the chevrons must leave the route exactly as it was — they are an overlay
        // on the track, not the track.
        loaded.toggle(.direction)
        #expect(!loaded.isVisible(.direction))
        #expect(loaded.lineStyle(flying: true) == .flying)
        #expect(loaded.lineStyle(flying: false) == .offFoil)
        // A marker, not a line: hiding it removes the arrows outright rather than degrading
        // them to a neutral route they do not have.
        #expect(MapLayer.direction.isMarker && !MapLayer.direction.isLine)
    }

    // MARK: - Presentation goldens

    /// One `fixtures/presentation/*.expected.json`: what a session-detail screen is
    /// allowed to draw from the analysis of the same name.
    private struct PresentationGolden: Decodable {
        struct Markers: Decodable {
            let flewThrough: Int
            let touchdown: Int
            let fellIn: Int
            let courseChange: Int
        }

        struct Takeoff: Decodable {
            let pumped: Int
            let free: Int
            let failed: Int
            let total: Int
        }

        struct FlightEnds: Decodable {
            let drawn: Int
            let ownedByTurn: Int
            let truncated: Int
            let total: Int
        }

        struct Filter: Decodable {
            let type: String
            let side: String
            let count: Int
            let flewThrough: Int
        }

        let fixture: String
        let flightCount: Int
        let markers: Markers
        let flightEnds: FlightEnds
        let takeoff: Takeoff
        let splash: Int
        let pumpingSpans: Int
        let recordWindows: [String]
        let defaultRecordWindow: String?
        let filters: [Filter]
    }

    /// The other half of docs/presentation.md's enforcement: the *counts* are pinned, per
    /// fixture, and the web verification asserts the same file with the same rules
    /// (`web/tools/verify_presentation.py`). A marker that appears here and not there —
    /// or a filter that quietly starts counting bear-aways — fails on both platforms in
    /// the same commit rather than turning up as "the two apps disagree" months later.
    ///
    /// The analysis goldens are decoded rather than recomputed: this test is about the
    /// presentation rules, and `GoldenTests` already holds the engine to the same files.
    @Test func presentationGoldensPinEveryMarkerAndFilterCount() throws {
        let dir = testFixturesDir.appendingPathComponent("presentation")
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".expected.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(!files.isEmpty,
                     "fixtures/presentation is empty — run web/tools/make_presentation_goldens.py")

        for url in files {
            let want = try JSONDecoder().decode(PresentationGolden.self,
                                                from: Data(contentsOf: url))
            let source = testFixturesDir
                .appendingPathComponent("goldens/\(want.fixture).expected.json")
            let analysis = try JSONDecoder().decode(SessionAnalysis.self,
                                                    from: Data(contentsOf: source))
            let got = PresentationFacts(analysis)
            let name = want.fixture

            #expect(got.markers.flewThrough == want.markers.flewThrough,
                    "\(name): flew-through markers")
            #expect(got.markers.touchdown == want.markers.touchdown,
                    "\(name): touchdown markers")
            #expect(got.markers.fellIn == want.markers.fellIn, "\(name): fell-in markers")
            #expect(got.markers.courseChange == want.markers.courseChange,
                    "\(name): course-change markers")

            #expect(got.takeoff.pumped == want.takeoff.pumped, "\(name): pumped takeoffs")
            #expect(got.takeoff.free == want.takeoff.free, "\(name): free takeoffs")
            #expect(got.takeoff.failed == want.takeoff.failed, "\(name): failed attempts")
            #expect(got.takeoff.total == want.takeoff.total, "\(name): takeoff layer total")

            #expect(got.splash == want.splash, "\(name): splash marks")
            #expect(got.pumpingSpans == want.pumpingSpans, "\(name): pumping spans")

            // One takeoff starts every flight, one end stops it — docs/presentation.md
            // "Enforcement" 3. The pairing lines a callout draws are written from exactly
            // this arithmetic, so it is pinned rather than trusted: a takeoff with no
            // flight to name would print a wrong number in a popover long before any tally
            // looked odd. A `failed` attempt is deliberately outside both sums.
            #expect(got.flightCount == want.flightCount, "\(name): flight count")
            #expect(got.flightEnds.drawn == want.flightEnds.drawn, "\(name): drawn ends")
            #expect(got.flightEnds.ownedByTurn == want.flightEnds.ownedByTurn,
                    "\(name): turn-owned ends")
            #expect(got.flightEnds.truncated == want.flightEnds.truncated,
                    "\(name): truncated ends")
            #expect(got.flightEnds.total == want.flightEnds.total, "\(name): flight ends")
            #expect(got.takeoff.pumped + got.takeoff.free == got.flightCount,
                    "\(name): every flight is started by exactly one takeoff")
            #expect(got.flightEnds.total == got.flightCount,
                    "\(name): every flight is stopped by exactly one end")
            #expect(got.takeoff.total - got.takeoff.failed == got.flightCount,
                    "\(name): a failed attempt starts no flight")
            // The block the pairing actually reads has to line up with all of it.
            let pairings = FlightPairing.flights(analysis)
            #expect(pairings.count == got.flightCount, "\(name): pairing flights")
            #expect(pairings.allSatisfy { $0.count == got.flightCount })
            #expect(analysis.takeoffs.allSatisfy {
                FlightPairing.flight(startingAt: $0.startTs, in: pairings) != nil
            }, "\(name): a takeoff whose flight cannot be named")
            #expect(PresentationRules.drawnFlightEnds(analysis).allSatisfy {
                FlightPairing.flight(at: $0.flightIndex, in: pairings) != nil
            }, "\(name): a drawn end whose flight cannot be named")

            #expect(got.recordWindows == want.recordWindows, "\(name): record windows")
            #expect(got.defaultRecordWindow == want.defaultRecordWindow,
                    "\(name): default record window")

            #expect(got.filters.count == want.filters.count, "\(name): filter grid size")
            for row in want.filters {
                let type = try #require(TurnTypeFilter(rawValue: row.type))
                let side = try #require(TurnSideFilter(rawValue: row.side))
                let mine = try #require(got.filters.first { $0.type == type && $0.side == side },
                                        "\(name): no tally for \(row.type)/\(row.side)")
                #expect(mine.count == row.count, "\(name): \(row.type)/\(row.side) count")
                #expect(mine.flewThrough == row.flewThrough,
                        "\(name): \(row.type)/\(row.side) flew through")
            }

            // The legend reads the same numbers: a chip is live exactly when its layer has
            // something in it.
            let tally = got.layerTally
            #expect(tally.count(.fellIn) == want.markers.fellIn)
            #expect(tally.count(.takeoff) == want.takeoff.total)
            #expect(tally.isToggleable(.splash) == (want.splash > 0))
        }
    }

    /// The uncounted turns are the reason the rule exists: a bear-away is drawn as a
    /// course change and appears in no tally, on either platform.
    @Test func courseChangesAreMarkedButNeverTallied() throws {
        let turns = try turnSet()
        let rejected = turns.filter { !$0.counted }
        #expect(!rejected.isEmpty, "the fixture must contain a rejected sweep to prove anything")

        for turn in rejected {
            #expect(PresentationRules.layer(for: turn) == .courseChange,
                    "a rejected sweep is never a verdict")
        }
        for turn in turns where turn.counted {
            #expect(PresentationRules.layer(for: turn) != .courseChange)
        }
        // ... and the same turns are absent from every tally, which is the half a marker
        // count alone would not catch.
        #expect(TurnAnalytics.count(turns, filter: TurnFilter())
                == turns.count - rejected.count)
    }

    // MARK: - Design tokens

    /// The generated tokens and the code's own catalogues are one contract, so a layer or
    /// a record added on one side and not the other fails here rather than showing up as a
    /// legend chip the web app has never heard of (docs/presentation.md "Enforcement").
    @Test func designTokensCarryTheSameCataloguesAsTheCode() {
        #expect(DesignTokens.Layers.order == MapLayer.allCases.map(\.rawValue))
        for entry in DesignTokens.Layers.catalogue {
            let layer = MapLayer(rawValue: entry.id)
            #expect(layer != nil, "token layer \(entry.id) is not a MapLayer")
            #expect(layer?.label == entry.label, "layer \(entry.id) label")
        }
        // Everything visible by default is the whole catalogue — the stored preference is
        // the *hidden* set precisely so a new layer arrives switched on.
        #expect(DesignTokens.Layers.visibleByDefault == MapLayer.allCases.map(\.rawValue))
        #expect(MapLayerVisibility.allVisible.hiddenLayers.isEmpty)

        #expect(DesignTokens.RecordWindows.order
                == RecordWindowSelection.catalogue.map(\.rawValue))
        #expect(DesignTokens.RecordWindows.defaultID == RecordWindowSelection.defaultKey)
        for entry in DesignTokens.RecordWindows.catalogue {
            let kind = RecordKind(rawValue: entry.id)
            #expect(kind != nil, "token record \(entry.id) is not a RecordKind")
            #expect(kind?.label == entry.label, "record \(entry.id) label")
        }
    }

    /// The glyph names are values like any other: the takeoff arrows and the drop come out
    /// of the token file, and the failed attempt keeps its own shape *and* its own colour.
    @Test func takeoffGlyphsAreDistinctOnEveryChannel() {
        let glyphs = [DesignTokens.Glyph.takeoffPumped, DesignTokens.Glyph.takeoffFree,
                      DesignTokens.Glyph.takeoffFailed]
        #expect(Set(glyphs).count == glyphs.count, "two takeoff kinds share a glyph")
        #expect(DesignTokens.Glyph.takeoffFailed.contains("uturn"),
                "a failed attempt must not merely be a differently-tinted up-arrow")
        #expect(DesignTokens.Hex.effortFailedTakeoff == DesignTokens.Hex.outcomeFellIn,
                "the one effort-layer event with an outcome borrows the ladder's red")
        #expect(DesignTokens.Hex.effortTakeoff != DesignTokens.Hex.outcomeFellIn)
    }

    /// **A side is not a verdict.** The Trends screen drew the port/starboard success pair
    /// in the ladder's green and the takeoff blue, on a chart whose subject is "% flew
    /// through" — so the green line read as the flew-through line (app-ui-review.md §5.2),
    /// and the chart above it used a magenta belonging to no vocabulary at all (§5.3).
    /// Both are now the `side.*` pair, and this asserts the property that made them wrong:
    /// the side inks may not be any ink that already means something else.
    @Test func theSideInksBelongToNoOtherVocabulary() {
        let sides = [DesignTokens.Hex.sidePort, DesignTokens.Hex.sideStarboard]
        #expect(Set(sides).count == 2, "port and starboard must be tellable apart")
        let spoken = [DesignTokens.Hex.outcomeFlew, DesignTokens.Hex.outcomeTouchdown,
                      DesignTokens.Hex.outcomeFellIn, DesignTokens.Hex.outcomeCourseChange,
                      DesignTokens.Hex.effortPumping, DesignTokens.Hex.effortTakeoff,
                      DesignTokens.Hex.effortSplash, DesignTokens.Hex.effortWindow,
                      DesignTokens.Hex.phaseFlying, DesignTokens.Hex.phaseOffFoil,
                      DesignTokens.Hex.directionInk]
        for ink in sides {
            #expect(!spoken.contains(ink), "\(ink) already means something else")
        }
    }

    // MARK: - Session sections

    /// The switcher's shape, which is the part of it that is a decision rather than layout.
    ///
    /// Two of these are the review's "deliberately not recommended" list expressed as an
    /// assertion (`app-ui-review.md` §3.3): an `overview` section would compete with the
    /// key-metrics block that sits *above* the switcher, and a `records` section would put
    /// the record picker on a tab away from the map and chart whose windows it highlights.
    /// The third is §3.2's constraint — the figures share a playhead, so they share a tab.
    @Test func sessionSectionsAreTheFourTheReviewSettledOn() {
        #expect(SessionSection.allCases == [.mapSpeed, .turns, .takeoffs, .effort])
        #expect(SessionSection.allCases.first == .mapSpeed, "the default is the figures")
        let labels = SessionSection.allCases.map(\.label)
        #expect(labels == ["Map · Speed", "Turns", "Takeoffs", "Effort"])
        #expect(Set(labels).count == labels.count)
        // The chart and the map's own anchors are on one section, and that is the contract's
        // "one playhead" made structural — nothing may move them apart.
        let figures = SessionSection.mapSpeed.anchors
        #expect(figures.contains("chart"))
        #expect(figures.contains("replay"))
        #expect(SessionSection.section(owning: "chart") == .mapSpeed)
        #expect(SessionSection.section(owning: "replay") == .mapSpeed)
        // The record table is on the same section as the figures it annotates.
        #expect(SessionSection.section(owning: "summary") == .mapSpeed)
    }

    /// Every screenshot anchor `docs/testing.md` documents has to resolve to the section it
    /// lives on, or `UI_SCROLL_TO` silently photographs the wrong tab.
    @Test func everyScrollAnchorResolvesToExactlyOneSection() {
        let documented = ["chart", "replay", "summary", "turns", "takeoff", "hr", "gear"]
        for anchor in documented {
            #expect(SessionSection.section(owning: anchor) != nil,
                    "\(anchor) is on no section — UI_SCROLL_TO would reach nothing")
        }
        #expect(SessionSection.section(owning: "turns") == .turns)
        #expect(SessionSection.section(owning: "takeoff") == .takeoffs)
        #expect(SessionSection.section(owning: "hr") == .effort)
        #expect(SessionSection.section(owning: "gear") == .effort)

        // No anchor may belong to two sections: the mapping is what selects a tab, and an
        // ambiguous one would select whichever case happened to be declared first.
        let all = SessionSection.allCases.flatMap(\.anchors)
        #expect(Set(all).count == all.count, "an anchor is claimed by two sections")

        // And the key-metrics block belongs to none of them on purpose — it is above the
        // switcher, on every section, so scrolling to it must not change the selection.
        #expect(SessionSection.section(owning: "key") == nil)
        #expect(SessionSection.section(owning: "nonsense") == nil)
    }

    // MARK: - Time-axis ticks

    /// Swift Charts' `.automatic` divides the domain into equal parts, which on a session
    /// clock produced `0:00 · 33:20 · 66:40 · 100:00` — arithmetically correct, and a set
    /// of times nobody has ever thought in (app-ui-review.md §1.5).
    @Test func timeAxisTicksLandOnRoundTimes() {
        // The measured case: a 100-minute session, five labels wanted.
        let ticks = TimeAxisTicks.values(for: 0...6000, desiredCount: 5)
        #expect(ticks == [0, 1800, 3600, 5400], "half hours, not 2000-second intervals")

        // Every tick, on every reasonable window, is a whole multiple of a step a rider
        // would name. This is the property; the cases above are the illustrations.
        for span in [90.0, 300, 900, 3600, 7200, 12_000, 40_000] {
            for offset in [0.0, 137, 4321] {
                let range = offset...(offset + span)
                let values = TimeAxisTicks.values(for: range, desiredCount: 5)
                #expect(values.count <= 5, "\(span)s asked for too many labels")
                #expect(values.allSatisfy { range.contains($0) },
                        "\(span)s put a label outside the window")
                #expect(values == values.sorted())
                let step = TimeAxisTicks.steps.first { s in
                    values.allSatisfy { ($0 / s).rounded() * s == $0 }
                }
                #expect(step != nil, "\(span)s at +\(offset) is not on the ladder")
            }
        }
    }

    /// Zooming changes which rung of the ladder is in use, never the roundness of what is
    /// written on it — which is the whole reason the rule is a ladder and not a divisor.
    @Test func timeAxisTicksStayRoundAsTheChartIsZoomed() {
        // A ten-minute window takes five-minute steps: two-minute steps would need six
        // labels where there is room for five, so the ladder moves up a rung.
        #expect(TimeAxisTicks.values(for: 600...1200, desiredCount: 5) == [600, 900, 1200])
        // Forty seconds ⇒ ten-second marks.
        #expect(TimeAxisTicks.values(for: 100...140, desiredCount: 5)
            == [100, 110, 120, 130, 140])
        // And a window holding exactly one round time keeps it, rather than taking the
        // two-ragged-ends fallback: one round number beats two unround ones.
        #expect(TimeAxisTicks.values(for: 101...109, desiredCount: 5) == [105])
    }

    /// The two degenerate ends. A window with no round time inside it still gets an axis
    /// (its own two edges — better than a chart with no labels at all), and a range that
    /// is empty or reversed gets nothing rather than a division by zero.
    @Test func timeAxisTicksDegradeAtBothEnds() {
        let tiny = TimeAxisTicks.values(for: 101...103, desiredCount: 5)
        #expect(tiny == [101, 103], "below the finest rung, the window's own ends")
        #expect(TimeAxisTicks.values(for: 5...5, desiredCount: 5).isEmpty)
        #expect(TimeAxisTicks.values(for: 0...0, desiredCount: 2).isEmpty)
        // Longer than the coarsest rung: still on the hour, just a coarser multiple.
        let long = TimeAxisTicks.values(for: 0...(50 * 3600), desiredCount: 5)
        #expect(!long.isEmpty)
        #expect(long.allSatisfy { $0.truncatingRemainder(dividingBy: 3600) == 0 })
        #expect(long.count <= 5)
        // `desiredCount` below two is not an axis; it is treated as two.
        #expect(TimeAxisTicks.values(for: 0...6000, desiredCount: 0)
            == TimeAxisTicks.values(for: 0...6000, desiredCount: 2))
    }
}
