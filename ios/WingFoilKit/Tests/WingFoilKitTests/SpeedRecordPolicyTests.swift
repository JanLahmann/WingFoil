import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// **Settings → Speed records, all three modes** (Jan, 22 September 2026).
///
/// Two layers, because there are two things that can be wrong: the rule itself, and
/// whether the query applies it in the right place. `SpeedRecordRule.eligible` is pure and
/// is checked directly; `LibraryStore.records(_:policy:)` is checked over a mixed library,
/// where the thing that matters is that the rule runs **before** the maximum is taken —
/// apply it after and "a verified record wins whenever one exists" silently becomes "the
/// fastest record wins, verified or not".
@Suite struct SpeedRecordPolicyTests {

    // MARK: - The rule

    /// The candidates of one kind, as the three modes see them.
    private struct Effort: Equatable {
        let name: String
        let verified: Bool
    }

    private let mixed = [Effort(name: "watch", verified: true),
                         Effort(name: "gpx", verified: false)]

    @Test func onlyVerifiedKeepsNothingElse() {
        #expect(SpeedRecordRule.eligible(mixed, policy: .onlyVerified, verified: \.verified)
                == [Effort(name: "watch", verified: true)])
    }

    @Test func includeUnverifiedKeepsEverything() {
        #expect(SpeedRecordRule.eligible(mixed, policy: .includeUnverified,
                                         verified: \.verified) == mixed)
    }

    /// The default, and the only one of the three that answers two ways for two kinds.
    @Test func preferVerifiedFallsBackOnlyWhenThereIsNothingToPrefer() {
        #expect(SpeedRecordRule.eligible(mixed, policy: .preferVerified,
                                         verified: \.verified)
                == [Effort(name: "watch", verified: true)])
        let onlyUnverified = [Effort(name: "gpx", verified: false),
                              Effort(name: "strava", verified: false)]
        #expect(SpeedRecordRule.eligible(onlyUnverified, policy: .preferVerified,
                                         verified: \.verified) == onlyUnverified)
    }

    /// An empty candidate list is an empty answer under all three, never a crash and never
    /// a row: a kind nobody has set has no row for the same reason.
    @Test func noCandidatesIsAnAnswer() {
        for policy in SpeedRecordPolicy.allCases {
            #expect(SpeedRecordRule.eligible([Effort](), policy: policy,
                                             verified: \.verified).isEmpty)
        }
    }

    /// The single-candidate question the card, the widget and the celebration ask: there
    /// is nothing to prefer, so `preferVerified` answers like `includeUnverified`.
    @Test func standsIsOnlyFalseUnderOnlyVerified() {
        #expect(!SpeedRecordRule.stands(verified: false, policy: .onlyVerified))
        #expect(SpeedRecordRule.stands(verified: true, policy: .onlyVerified))
        for policy in [SpeedRecordPolicy.preferVerified, .includeUnverified] {
            #expect(SpeedRecordRule.stands(verified: false, policy: policy))
            #expect(SpeedRecordRule.stands(verified: true, policy: policy))
        }
    }

    // MARK: - The store

    /// A library of two afternoons: a verified one that holds the best 2 s, and an
    /// unverified one that reads *higher* on best 2 s and is the only session that ever set
    /// a best 500 m. That pair is the whole point of `preferVerified` — it has to answer
    /// differently per kind on one library.
    private func mixedLibrary() async throws -> LibraryStore {
        let database = try AppDatabase.inMemory()
        let start = Date(timeIntervalSince1970: 1_785_916_800)
        try await database.writer.write { db in
            for (id, sourceClass, offset) in [("verified", "b", 0.0),
                                              ("unverified", "c", 3600.0)] {
                var row = SessionRow(id: id, startDate: start.addingTimeInterval(offset),
                                     durationS: 3600, sourceClass: sourceClass)
                row.best2sKn = sourceClass == "b" ? 20 : 31
                try row.insert(db)
            }
            for (session, kind, value, sourceClass) in [
                ("verified", RecordKind.best2s, 20.0, "b"),
                ("unverified", RecordKind.best2s, 31.0, "c"),
                ("unverified", RecordKind.best500m, 9.0, "c"),
            ] {
                try RecordEffortRow(sessionId: session, kind: kind, valueKn: value,
                                    achievedAt: start, window: nil,
                                    sourceClass: sourceClass).insert(db)
            }
        }
        return LibraryStore(database: database)
    }

    @Test func onlyVerifiedDropsAKindWhoseOnlyHolderIsUnverified() async throws {
        let records = try await mixedLibrary().records(policy: .onlyVerified)
        #expect(records.map(\.kind) == [.best2s])
        #expect(records[0].valueKn == 20)
        #expect(records[0].certified)
    }

    /// The default: the verified 2 s wins its row even though the unverified one is 11 kn
    /// faster, and the unverified 500 m fills a row nothing verified has reached.
    @Test func preferVerifiedAnswersPerKind() async throws {
        let records = try await mixedLibrary().records()
        #expect(records.map(\.kind) == [.best2s, .best500m])
        #expect(records[0].valueKn == 20)
        #expect(records[0].certified)
        #expect(records[1].valueKn == 9)
        #expect(!records[1].certified, "the row it fills still carries the mark")
    }

    @Test func includeUnverifiedLetsTheFastestStand() async throws {
        let records = try await mixedLibrary().records(policy: .includeUnverified)
        #expect(records.map(\.kind) == [.best2s, .best500m])
        #expect(records[0].valueKn == 31)
        #expect(!records[0].certified)
    }

    /// **The history behind a row is filtered too**, which is what keeps the sparkline and
    /// the "+0.4 kn" delta about the same set of efforts the row's value came from. A step
    /// curve drawn over efforts the policy excluded would report a personal best that the
    /// table never shows.
    @Test func theHistoryIsTheEligibleHistory() async throws {
        let store = try await mixedLibrary()
        #expect(try await store.records(policy: .onlyVerified)[0].history.count == 1)
        #expect(try await store.records(policy: .includeUnverified)[0].history.count == 2)
    }

    // MARK: - The stored choice

    @Test func theStoreFallsBackToPreferVerified() throws {
        let defaults = try #require(UserDefaults(suiteName: "speed-records-\(UUID())"))
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        #expect(SpeedRecordPolicyStore.load(from: defaults) == .preferVerified)
        defaults.set("somethingElse", forKey: SpeedRecordPolicyStore.defaultsKey)
        #expect(SpeedRecordPolicyStore.load(from: defaults) == .preferVerified,
                "an unknown stored value must not strand an older app on an empty table")
        for policy in SpeedRecordPolicy.allCases {
            SpeedRecordPolicyStore.save(policy, to: defaults)
            #expect(SpeedRecordPolicyStore.load(from: defaults) == policy)
        }
    }

    /// The three raw values are a storage contract *and* the browser's vocabulary
    /// (`library.SPEED_RECORD_POLICIES`, `web/js/appsettings.js`). They may not be renamed.
    @Test func theRawValuesAreTheBrowsersToo() {
        #expect(SpeedRecordPolicy.allCases.map(\.rawValue)
                == ["onlyVerified", "preferVerified", "includeUnverified"])
    }

    // MARK: - The card

    /// A card is one session, so `preferVerified` has nothing to prefer and the record cell
    /// stands, marked. Under `onlyVerified` the cell comes off rather than going out with
    /// a disclaimer, and the disclaimer goes with it: there is no speed claim left to
    /// qualify.
    @Test func theCardObeysTheSamePolicy() {
        var row = SessionRow(id: "s", startDate: Date(), durationS: 3600, sourceClass: "c")
        row.best2sKn = 31
        row.distanceKm = 12
        let zone = TimeZone(identifier: "UTC")!

        let marked = ShareCardStats.make(row: row, title: "Torbole", timeZone: zone)
        #expect(marked.disclaimer != nil)

        let dropped = ShareCardStats.make(row: row, title: "Torbole",
                                          policy: .onlyVerified, timeZone: zone)
        #expect(dropped.disclaimer == nil)
        #expect(!dropped.stats.contains { $0.key == ShareCardStats.Key.maxSpeed })
        #expect(dropped.stats.contains { $0.key == ShareCardStats.Key.distance },
                "only the record cell goes; the afternoon's own numbers stay")

        // A verified session is untouched by any of the three.
        var verified = row
        verified.sourceClass = "b"
        for policy in SpeedRecordPolicy.allCases {
            let card = ShareCardStats.make(row: verified, title: "Torbole",
                                           policy: policy, timeZone: zone)
            #expect(card.disclaimer == nil)
            #expect(card.stats.contains { $0.key == ShareCardStats.Key.maxSpeed })
        }
    }

    // MARK: - The widget snapshot

    /// The home-screen widget's "Best 2 s" is an all-time claim, so it reads the same rule.
    /// It used to be hard-wired to certified-only, which is exactly `onlyVerified`.
    @Test func theWidgetSnapshotObeysTheSamePolicy() {
        let start = Date(timeIntervalSince1970: 1_785_916_800)
        func row(_ id: String, _ sourceClass: String, _ kn: Double) -> SessionRow {
            var row = SessionRow(id: id, startDate: start, durationS: 3600,
                                 sourceClass: sourceClass)
            row.best2sKn = kn
            row.foilTimeS = 1800
            row.foilPct = 50
            return row
        }
        let rows = [row("verified", "b", 20), row("unverified", "c", 31)]
        func peak(_ policy: SpeedRecordPolicy) -> Double? {
            let snapshot = WidgetSnapshot.make(sessions: rows,
                                               now: start.addingTimeInterval(60),
                                               policy: policy, titleForRow: { $0.id })
            return (snapshot.bests ?? []).first { $0.factKind == .best2s }?.value
        }
        #expect(peak(.onlyVerified) == 20)
        #expect(peak(.preferVerified) == 20)
        #expect(peak(.includeUnverified) == 31)
    }
}
