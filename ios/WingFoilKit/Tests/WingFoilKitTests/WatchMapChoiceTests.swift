import Foundation
import Testing
@testable import WingFoilKit

/// Which two maps the watch gets — the rule that used to be a sort in the app target and is
/// now an answer with a rider's word in it (docs/watch-map-snapshot.md).
///
/// The interesting cases are all about a choice going stale between the tap and the send: a
/// spot that re-clustered away, a phone that never got a fix, a third pick on a watch with
/// two slots. None of them may throw and none of them may send the wrong ground.
@Suite struct WatchMapChoiceTests {

    // MARK: - Fixtures

    static func spot(_ id: String, _ name: String, sessions: Int,
                     lat: Double = 45.87, lon: Double = 10.87) -> SpotAggregate {
        SpotAggregate(spot: SpotRow(id: id, name: name, lat: lat, lon: lon),
                      sessions: sessions, lastVisit: nil)
    }

    /// Torbole most-ridden, then two spots tied on four afternoons, then one nobody rode.
    static let library: [SpotAggregate] = [
        spot("a", "Fehmarn", sessions: 4, lat: 54.405, lon: 11.183),
        spot("b", "Nago-Torbole", sessions: 31, lat: 45.869, lon: 10.874),
        spot("c", "Brouwersdam", sessions: 4, lat: 51.75, lon: 3.85),
        spot("d", "Never rode here", sessions: 0, lat: 50.0, lon: 8.0),
    ]

    // MARK: - Automatic

    @Test func automaticTakesTheTwoMostRiddenAndBreaksTiesOnName() {
        let targets = WatchMapChoice.resolve(WatchMapChoice(), spots: Self.library,
                                             here: nil, limit: 2)
        #expect(targets.map(\.name) == ["Nago-Torbole", "Brouwersdam"])
        // The 4-session tie went to Brouwersdam on the name, not on the array order, so a
        // relaunch cannot swap the pair and re-push two masks for nothing.
        #expect(WatchMapChoice.mostRidden(Self.library).map(\.spot.name)
                == ["Nago-Torbole", "Brouwersdam", "Fehmarn"])
    }

    @Test func automaticIgnoresASpotWithNoSessionsAndOneWithNoFix() {
        var broken = Self.library
        broken.append(Self.spot("e", "No fix", sessions: 99, lat: .nan, lon: .nan))
        let names = WatchMapChoice.mostRidden(broken).map(\.spot.name)
        #expect(!names.contains("No fix"))
        #expect(!names.contains("Never rode here"))
    }

    // MARK: - Toggling

    @Test func toggleAddsAndRemoves() {
        var choice = WatchMapChoice()
        #expect(choice.isAutomatic)
        choice.toggle(.spot(id: "b"))
        #expect(choice.picks == [.spot(id: "b")])
        #expect(!choice.isAutomatic)
        choice.toggle(.here)
        #expect(choice.picks == [.spot(id: "b"), .here])
        choice.toggle(.spot(id: "b"))
        #expect(choice.picks == [.here])
        choice.toggle(.here)
        #expect(choice.isAutomatic)
    }

    @Test func aThirdPickDropsTheOldest() {
        var choice = WatchMapChoice()
        choice.toggle(.spot(id: "a"))
        choice.toggle(.spot(id: "b"))
        choice.toggle(.here)
        #expect(choice.picks == [.spot(id: "b"), .here])
        #expect(choice.picks.count == WatchMapChoice.slots)
    }

    // MARK: - Resolving a chosen pair

    @Test func explicitPicksKeepTheirOrder() {
        let choice = WatchMapChoice(picks: [.here, .spot(id: "a")])
        let targets = WatchMapChoice.resolve(choice, spots: Self.library,
                                             here: (lat: 47.5, lon: 9.1), limit: 2)
        #expect(targets.map(\.name) == ["Where I am now", "Fehmarn"])
        #expect(targets.first?.clusterKey == WatchMapTarget.hereKey)
        #expect(targets.first?.isHere == true)
        #expect(targets.first?.lat == 47.5)
        #expect(targets.last?.clusterKey == "a")
    }

    @Test func aVanishedSpotIsSkippedRatherThanSentEmpty() {
        let choice = WatchMapChoice(picks: [.spot(id: "gone"), .spot(id: "b")])
        let targets = WatchMapChoice.resolve(choice, spots: Self.library,
                                             here: nil, limit: 2)
        #expect(targets.map(\.name) == ["Nago-Torbole"])
    }

    @Test func hereWithoutAFixIsSkipped() {
        let choice = WatchMapChoice(picks: [.here, .spot(id: "b")])
        #expect(WatchMapChoice.resolve(choice, spots: Self.library, here: nil, limit: 2)
                    .map(\.name) == ["Nago-Torbole"])
        // …and a fix that is not a number is the same as no fix.
        #expect(WatchMapChoice.resolve(choice, spots: Self.library,
                                       here: (lat: .nan, lon: 9.1), limit: 2)
                    .map(\.name) == ["Nago-Torbole"])
    }

    @Test func neverMoreThanTheLimit() {
        let choice = WatchMapChoice(picks: [.spot(id: "b"), .spot(id: "a")])
        #expect(WatchMapChoice.resolve(choice, spots: Self.library, here: nil, limit: 1)
                    .count == 1)
        #expect(WatchMapChoice.resolve(WatchMapChoice(), spots: Self.library,
                                       here: nil, limit: 1).count == 1)
    }

    // MARK: - Remembering it

    @Test func roundTripsThroughDefaults() throws {
        let suite = "watchmap.choice.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(WatchMapChoice.load(from: defaults).isAutomatic)

        var choice = WatchMapChoice()
        choice.toggle(.spot(id: "b"))
        choice.toggle(.here)
        choice.save(to: defaults)
        #expect(WatchMapChoice.load(from: defaults) == choice)

        // Back to automatic is a stored fact too, not an absence: the rider who turns the
        // picker off must not be handed his old pair again at the next launch.
        WatchMapChoice().save(to: defaults)
        #expect(WatchMapChoice.load(from: defaults).isAutomatic)

        // Nonsense under the key reads as automatic rather than as a crash.
        defaults.set(Data([0x7B, 0x7B]), forKey: WatchMapChoice.defaultsKey)
        #expect(WatchMapChoice.load(from: defaults).isAutomatic)
    }

    /// The watch's slot id is a hash of the cluster key, so "here" must hash to the same
    /// number every time or two sends from two beaches would fill both slots with the rider.
    @Test func hereAlwaysGetsTheSameSlotID() {
        #expect(WatchMapMask.spotID(clusterKey: WatchMapTarget.hereKey)
                == WatchMapMask.spotID(clusterKey: "here"))
        #expect(WatchMapMask.spotID(clusterKey: WatchMapTarget.hereKey)
                != WatchMapMask.spotID(clusterKey: "b"))
    }
}
