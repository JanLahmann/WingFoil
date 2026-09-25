import Foundation
import Testing
@testable import WingFoilKit

/// **The ways in have one order, and one place that decides it**
/// (docs/review-checklist.md, pattern J).
///
/// `docs/guide/getting-started.json` is the source: the app's help topic, cleanjibe.org/start
/// and the Import screen all print its routes, and the Import screen used to print its own
/// order with the Garmin export ZIP at the top. These tests hold the two lists against each
/// other, per channel, so the screen cannot drift from the guide again.
struct ImportDoorsTests {

    @Test("the doors follow the getting-started routes, per channel")
    func orderMatchesTheGuide() {
        for channel in HelpChannel.allCases {
            let doors = ImportDoor.ordered(channel: channel)
            let routes = GettingStartedGuide.routes
                .filter { channel.has($0.channel) }
                .map(\.id)
            #expect(doors.compactMap(\.guideRouteID) == routes,
                    "Import's order left the guide on \(channel)")
        }
    }

    @Test("the Garmin export ZIP is last, in every channel that has it")
    func zipIsLast() {
        for channel in HelpChannel.allCases {
            let doors = ImportDoor.ordered(channel: channel)
            guard doors.contains(.garminZip) else { continue }
            #expect(doors.last == .garminZip)
        }
    }

    @Test("the release channel has three doors, the beta all six")
    func channelsHaveTheirDoors() {
        #expect(ImportDoor.ordered(channel: .release) == [.icu, .file, .strava])
        #expect(ImportDoor.ordered(channel: .beta).count == 6)
        #expect(ImportDoor.ordered(channel: .dev).count == 6)
    }

    /// Pattern E/G: a build that has a door draws it. Nothing here may be absent for any
    /// reason but the channel, so every door in a channel's list has to be drawable — which
    /// means a header, a footer, a class label and a topic, whatever the rider has done.
    @Test("every door has a header, a class label, a footer and a help topic")
    func everyDoorIsDrawable() {
        for channel in HelpChannel.allCases {
            for door in ImportDoor.ordered(channel: channel) {
                #expect(!door.sectionTitle.isEmpty)
                #expect(!door.classLabel(channel: channel).isEmpty)
                #expect(!door.footer(channel: channel).isEmpty)
                // Throws rather than returns nil if the topic is missing.
                _ = HelpCatalog.topic(door.helpTopic, channel: channel)
            }
        }
    }

    /// Pattern K: a footer says what you get in one line. The budget is 25 words, the same
    /// one docs/review-checklist.md sets for a Settings or Import footer.
    @Test("no import footer is longer than 25 words")
    func footersAreOneLine() {
        for channel in HelpChannel.allCases {
            for door in ImportDoor.ordered(channel: channel) {
                let words = door.footer(channel: channel).split(separator: " ").count
                #expect(words <= 25,
                        "\(door.rawValue) on \(channel): \(words) words")
            }
        }
    }

    /// Pattern D: a text that lists doors takes the channel that asks. The file picker is
    /// the one door whose answer differs, and it must differ in both directions.
    @Test("the file door names the beta's two extra formats only in the beta")
    func theFileDoorIsChannelAware() {
        let release = ImportDoor.file.footer(channel: .release)
        let beta = ImportDoor.file.footer(channel: .beta)
        #expect(!release.contains("GPX"))
        #expect(beta.contains("GPX"))
        #expect(ImportDoor.file.actionTitle(channel: .release) == "FIT or ZIP…")
        #expect(ImportDoor.file.recordingClasses(channel: .release) == [.a, .b])
        #expect(ImportDoor.file.recordingClasses(channel: .beta) == [.a, .b, .c])
    }

    /// The two doors that need an account keep their row and change its label; the rest have
    /// no Settings section to be sent to.
    @Test("only the account doors offer a way to Settings")
    func setUpLinesBelongToAccounts() {
        #expect(ImportDoor.icu.setUpTitle == "Set up in Settings → intervals.icu")
        #expect(ImportDoor.strava.setUpTitle == "Set up in Settings → Strava")
        #expect(ImportDoor.file.setUpTitle == nil)
        #expect(ImportDoor.appleWatchApp.setUpTitle == nil)
    }

    /// The CleanJibe watch app is the one door with nothing to import: it delivers on its
    /// own, and the screen has to say so rather than leave a tester hunting for her session
    /// in the Health list (18 Sep 2026).
    @Test("the Apple Watch door has no action and says why")
    func theWatchAppDoorIsAStatement() {
        #expect(ImportDoor.appleWatchApp.actionTitle(channel: .beta) == nil)
        #expect(ImportDoor.appleWatchApp.footer(channel: .beta)
            .contains("arrive by themselves"))
    }
}

/// **Settings → Apple Health draws both switches, always** (pattern E/G).
struct HealthSwitchesTests {

    @Test("both directions are on the list")
    func bothSwitchesExist() {
        #expect(HealthSwitch.ordered == [.write, .autoImport])
        #expect(Set(HealthSwitch.ordered) == Set(HealthSwitch.allCases))
        #expect(HealthSwitch.write.title == "Add sessions to Apple Health")
        #expect(HealthSwitch.autoImport.title
                == "Import new Health workouts automatically")
    }

    @Test("each footer is one line and names a topic that exists")
    func footersAreOneLine() {
        for setting in HealthSwitch.ordered {
            let words = setting.footer.split(separator: " ").count
            #expect(words <= 25, "\(setting.rawValue): \(words) words")
            _ = HelpCatalog.topic(setting.helpTopic, channel: .beta)
        }
    }
}

/// **The app's one menu, in one order** (pattern M).
struct AppMenuRowsTests {

    @Test("six rows, in the order a rider meets the app")
    func theOrderIsFixed() {
        #expect(AppMenuRow.ordered == [.whatItDoes, .gettingStarted, .settings,
                                       .help, .support, .beta])
        #expect(Set(AppMenuRow.ordered) == Set(AppMenuRow.allCases))
    }

    /// **The beta row is the Beta page's own name**, the way the support row is the
    /// feedback door's: one string, one home.
    @Test("the beta row is named by the page it opens")
    func betaIsNamedOnce() {
        #expect(AppMenuRow.beta.title == BetaGuide.joinTitle)
    }

    /// The family section is under 120 words, because a rider reading it wants the shape
    /// of the product and not its history (docs/voice.md, the paragraph budgets).
    @Test("the family section is the apps, briefly")
    func theFamilyIsBrief() {
        #expect(CleanJibeFamily.apps.count == 4)
        let words = ([CleanJibeFamily.title, CleanJibeFamily.intro, CleanJibeFamily.here,
                      CleanJibeFamily.howSessionsGetIn]
                     + CleanJibeFamily.apps.flatMap { [$0.title, $0.line] })
            .flatMap { $0.split(separator: " ") }
            .count
        #expect(words <= 120, "\(words) words")
    }

    @Test("one divider, and it falls before Settings")
    func oneDivider() {
        #expect(AppMenuRow.ordered.filter(\.opensAfterDivider) == [.settings])
    }

    @Test("the support row is the feedback door's own name")
    func supportIsNamedOnce() {
        #expect(AppMenuRow.support.title == FeedbackDoors.menuRow)
    }

    /// **App-wide furniture sits on every tab** (pattern M). The menu is one `View` with four
    /// call sites, and the rule that matters is that all four tab roots are among them — which
    /// is a fact about the app target, so it is read off the sources rather than asserted
    /// about a type this test cannot see.
    @Test("all four tab roots place the shared menu")
    func everyTabRootPlacesTheMenu() throws {
        let app = CopyContractTests.repoRoot.appendingPathComponent("ios/WingFoil")
        let roots = [
            ("Features/Library/LibraryView.swift", "AppMenuButton("),
            ("Features/Records/RecordsView.swift", ".appMenuHost()"),
            ("Features/Trends/TrendsView.swift", ".appMenuHost()"),
            ("Features/Gear/GearView.swift", ".appMenuHost()"),
        ]
        for (path, marker) in roots {
            let source = try String(contentsOf: app.appendingPathComponent(path),
                                    encoding: .utf8)
            #expect(source.contains(marker), "\(path) does not place the app menu")
        }
    }
}

/// **Where a recording came from, in one line under the date.**
struct SessionProvenanceTests {

    @Test("the app that made the recording beats the account it travelled through")
    func theNearestDoorWins() {
        #expect(SessionProvenance.line(importSource: "applewatch+icu")
                == "Apple Watch · CleanJibe")
        #expect(SessionProvenance.line(importSource: "icu") == "intervals.icu")
        #expect(SessionProvenance.line(importSource: "file+icu") == "intervals.icu")
        #expect(SessionProvenance.line(importSource: "strava") == "Strava")
        #expect(SessionProvenance.line(importSource: "applehealth") == "Apple Health")
        #expect(SessionProvenance.line(importSource: "file") == "File")
    }

    @Test("a column that says nothing gets no line")
    func silenceIsNotAGuess() {
        #expect(SessionProvenance.line(importSource: nil) == nil)
        #expect(SessionProvenance.line(importSource: "") == nil)
        #expect(SessionProvenance.line(importSource: "something-else") == nil)
    }

    /// `.watch` must never be matched by `"applewatch"`: they are a Garmin summary card and
    /// an Apple Watch recording, and the column is a `+`-joined set rather than a substring.
    @Test("a Garmin card and an Apple Watch recording stay apart")
    func theTwoWatchesAreNotOne() {
        #expect(SessionProvenance.line(importSource: "watch") == "Garmin watch")
        #expect(SessionProvenance.line(importSource: "applewatch")
                == "Apple Watch · CleanJibe")
    }

    @Test("every door the filter menu offers can be named here")
    func everySourceHasAWord() {
        for source in SessionProvenance.order {
            #expect(!SessionProvenance.label(source).isEmpty)
        }
    }
}
