import Foundation
import Testing
@testable import WingFoilKit

/// **The beta's anonymous counts** (docs/analytics.md, ADR-039). Every assertion is about what
/// leaves a phone: the guard is web/js/track.js's, and nothing the suite does not pin may
/// reach the body.
@Suite struct UmamiEventTests {

    private let context = UmamiEvent.Context(language: "de-DE", width: 440, height: 956)

    private func json(_ event: UmamiEvent) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: event.body())
        return try #require(object as? [String: Any])
    }

    private func payload(_ event: UmamiEvent) throws -> [String: Any] {
        try #require(try json(event)["payload"] as? [String: Any])
    }

    // MARK: - The guard

    @Test func stringsAreTrimmedAndCappedAtThirtyTwo() {
        let long = String(repeating: "x", count: 50)
        let out = UmamiEvent.scrub([.text("a", "  fit  "), .text("b", long)])
        #expect(out == [.text("a", "fit"), .text("b", String(repeating: "x", count: 32))])
    }

    @Test func emptyStringsAndNonFiniteNumbersAreDropped() {
        let out = UmamiEvent.scrub([
            .text("empty", "   "), .init("nan", .number(.nan)), .init("inf", .number(.infinity)),
            .init("x", .number(1.5)), .int("n", 3), .flag("b", false),
        ])
        #expect(out.map(\.key) == ["x", "n", "b"])
    }

    @Test func atMostSixPropertiesTravelAndTheFirstKeyWins() {
        let many = (0..<10).map { UmamiEvent.Property.int("k\($0)", $0) }
        #expect(UmamiEvent.scrub(many).map(\.key) == ["k0", "k1", "k2", "k3", "k4", "k5"])
        // A dropped value does not use up a slot, exactly as in track.js.
        let gappy = [UmamiEvent.Property.text("gap", "")] + many
        #expect(UmamiEvent.scrub(gappy).count == 6)
        let twice = UmamiEvent.scrub([.text("a", "one"), .text("a", "two")])
        #expect(twice == [.text("a", "one")])
    }

    // MARK: - The body

    @Test func anEventCarriesThePrefixedNameAndItsData() throws {
        let event = UmamiEvent.event("app-card-made", [.text("shape", "story"), .flag("map", true)],
                                     on: .share, context: context)
        let outer = try json(event)
        #expect(outer["type"] as? String == "event")
        let p = try payload(event)
        #expect(p["website"] as? String == "97f347ac-e7ba-4be3-b26f-ab4b328bdbf2")
        #expect(p["hostname"] as? String == "ios.cleanjibe.org")
        #expect(p["url"] as? String == "/share")
        #expect(p["title"] as? String == "share")
        #expect(p["language"] as? String == "de-DE")
        #expect(p["screen"] as? String == "440x956")
        #expect(p["name"] as? String == "CleanJibe: app-card-made")
        let data = try #require(p["data"] as? [String: Any])
        #expect(data["shape"] as? String == "story")
        #expect(data["map"] as? Bool == true)
        #expect(Set(p.keys) == ["website", "hostname", "url", "title", "language", "screen",
                                "name", "data"])
    }

    @Test func aPageviewHasNoNameAndNoData() throws {
        let p = try payload(.pageview(.library, context: context))
        #expect(p["name"] == nil)
        #expect(p["data"] == nil)
        #expect(p["url"] as? String == "/library")
    }

    @Test func anEventWithNothingWorthSendingHasNoDataKey() throws {
        let p = try payload(.event("app-opened", [.text("x", "")], on: .library, context: context))
        #expect(p["data"] == nil)
        #expect(p["name"] as? String == "CleanJibe: app-opened")
    }

    @Test func theSameEventIsTheSameBytes() {
        let a = UmamiEvent.counted(.shareCard, detail: "story · clean · map", on: .share,
                                   context: context)
        let b = UmamiEvent.counted(.shareCard, detail: "story · clean · map", on: .share,
                                   context: context)
        #expect(a.body() == b.body())
        #expect(!a.body().isEmpty)
    }

    // MARK: - The counters as events

    @Test func everyCounterHasAKebabNameWithoutThePrefix() {
        for feature in UsageCounters.Feature.allCases {
            let name = feature.umamiName
            #expect(name.hasPrefix("app-"), "\(feature)")
            #expect(name.allSatisfy { $0.isLowercase || $0 == "-" }, "\(feature): \(name)")
            #expect(!name.contains("CleanJibe"))
        }
    }

    @Test func theWebsNamesAreKeptWhereTheyMeanTheSameThing() {
        #expect(UsageCounters.Feature.sessionOpened.umamiName == "app-session-opened")
        #expect(UsageCounters.Feature.turnPage.umamiName == "app-turn-page-opened")
        #expect(UsageCounters.Feature.shareCard.umamiName == "app-card-made")
        #expect(UsageCounters.Feature.backupMade.umamiName == "app-backup-exported")
        #expect(UsageCounters.Feature.backupRestored.umamiName == "app-backup-restored")
        #expect(UsageCounters.Feature.importShareSheet.umamiName == "app-shared-file-taken")
    }

    @Test func theShareCardsVariantBecomesTheWebsProperties() {
        let session = UmamiEvent.counted(.shareCard, detail: "story · max2s · photo",
                                         on: .share, context: context)
        #expect(session.properties == [.text("how", "share"), .text("kind", "session"),
                                       .text("shape", "story"), .text("hero", "max2s"),
                                       .flag("map", false), .flag("photo", true)])
        let period = UmamiEvent.counted(.periodShare, detail: "square · clean · map · stack",
                                        on: .share, context: context)
        #expect(period.properties.first(where: { $0.key == "kind" })?.value == .text("period"))
        #expect(period.properties.first(where: { $0.key == "tracks" })?.value == .text("stack"))
        #expect(period.properties.count == 6)
    }

    @Test func aDetailOnAnUnmappedFeatureIsDropped() {
        let event = UmamiEvent.counted(.rename, detail: "Lake Garda 14 Sep", on: .session,
                                       context: context)
        #expect(event.properties.isEmpty)
    }

    @Test func aBatchSaysHowMany() {
        #expect(UmamiEvent.counted(.mostWanted, times: 3, on: .settings, context: context)
            .properties == [.int("ticks", 3)])
        #expect(UmamiEvent.counted(.filters, times: 2, on: .library, context: context)
            .properties == [.int("times", 2)])
    }

    @Test func anImportIsTheWebsFileAnalyzedWithASource() {
        let icu = UmamiEvent.imported(.icu, automatic: false, sessions: 4, on: .library,
                                      context: context)
        #expect(icu?.name == "app-file-analyzed")
        #expect(icu?.properties == [.text("source", "icu"), .int("sessions", 4)])
        #expect(UmamiEvent.importSource(.icu, automatic: true) == "icu-auto")
        #expect(UmamiEvent.importSource(.airdrop, automatic: false) == "shared")
        #expect(UmamiEvent.importSource(.file, automatic: false) == "picker")
        #expect(UmamiEvent.imported(.example, automatic: false, sessions: 1, on: .library,
                                    context: context) == nil)
    }
}
