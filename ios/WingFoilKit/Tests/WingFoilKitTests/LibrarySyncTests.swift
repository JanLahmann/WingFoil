import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// **Two devices, one library** (ADR-026, issue #7). Every test here builds two real
/// libraries with their own databases and their own archives, points both at one temporary
/// directory standing in for the iCloud Drive container, and syncs them — because "it worked
/// on the device that wrote it" is the one thing a sync is not allowed to be.
@Suite struct LibrarySyncTests {

    // MARK: - Scaffolding

    private struct Device {
        var ingestor: SessionIngestor
        var home: URL

        var store: LibraryStore { ingestor.library }
    }

    private func makeDevice(_ name: String) throws -> Device {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-sync-\(name)-\(UUID().uuidString)",
                                    isDirectory: true)
        let root = home.appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Device(ingestor: SessionIngestor(database: try AppDatabase.inMemory(),
                                                archive: SessionArchive(root: root)),
                      home: home)
    }

    private func makeContainer() throws -> LibrarySyncContainer {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-sync-container-\(UUID().uuidString)",
                                    isDirectory: true)
        let container = LibrarySyncContainer(root: root)
        try container.prepare()
        return container
    }

    private func engine(_ device: Device, _ container: LibrarySyncContainer) -> LibrarySyncEngine {
        LibrarySyncEngine(ingestor: device.ingestor, container: container)
    }

    /// The two smallest FITs in the corpus, the same pair the backup suite uses.
    private static let stems = ["2026-08-05-0827_nago-torbole-windsurfen_native",
                                "2026-08-04-0822_nago-torbole-windsurfen_native"]

    private func fixture(_ index: Int) throws -> (data: Data, name: String) {
        let url = try #require(findFixtureFIT(stem: Self.stems[index]),
                               "fixture \(Self.stems[index]) is missing")
        return (try Data(contentsOf: url), url.lastPathComponent)
    }

    @discardableResult
    private func ingest(_ index: Int, into device: Device) async throws -> SessionRow {
        let (data, name) = try fixture(index)
        guard case .imported(let row) = try await device.ingestor.ingest(
            fitData: data, filename: name, source: .file) else {
            Issue.record("fixture \(index) did not import")
            throw CancellationError()
        }
        return row
    }

    // MARK: - The merge rule

    @Test func newerFieldWinsPerField() {
        let noon = Date(timeIntervalSince1970: 1_756_000_000)
        let evening = noon.addingTimeInterval(3600)

        var phone = SyncedSessionMeta(id: "a", startDate: noon, durationS: 3600)
        phone.customTitle = SyncedField("Morning at Torbole", at: noon)
        phone.shareNote = SyncedField("Glassy", at: evening)

        var pad = SyncedSessionMeta(id: "a", startDate: noon, durationS: 3600)
        pad.customTitle = SyncedField("First 20-knot run", at: evening)
        pad.shareNote = SyncedField("Windy", at: noon)

        let merged = phone.merged(with: pad)
        // Each side wins the field it touched last, and neither loses the other.
        #expect(merged.customTitle.value == "First 20-knot run")
        #expect(merged.shareNote.value == "Glassy")
        // And it is the same answer whichever device ran the merge.
        #expect(pad.merged(with: phone) == merged)
    }

    @Test func aTieKeepsWhatIsAlreadyHere() {
        let stamp = Date(timeIntervalSince1970: 1_756_000_000)
        let mine = SyncedField("mine", at: stamp)
        let theirs = SyncedField("theirs", at: stamp)
        #expect(mine.merged(with: theirs).value == "mine")
        #expect(theirs.merged(with: mine).value == "theirs")
    }

    @Test func clearingAFieldIsAValueAndCanWin() {
        let noon = Date(timeIntervalSince1970: 1_756_000_000)
        let named = SyncedField("Morning at Torbole", at: noon)
        let cleared = SyncedField<String>(nil, at: noon.addingTimeInterval(60))
        #expect(named.merged(with: cleared).value == nil)
    }

    @Test func aMetaFromANewerFormatIsNotRead() {
        var meta = SyncedSessionMeta(id: "a", startDate: .now, durationS: 60)
        meta.format = SyncedSessionMeta.currentFormat + 1
        #expect(!meta.isReadable)
    }

    // MARK: - The folder

    @Test func theFolderRoundTrips() async throws {
        let container = try makeContainer()
        defer { try? FileManager.default.removeItem(at: container.root) }
        let (data, _) = try fixture(0)
        let stamp = Date(timeIntervalSince1970: 1_756_000_000)

        var meta = SyncedSessionMeta(id: "session-1", startDate: stamp, durationS: 1800)
        meta.customTitle = SyncedField("Morning at Torbole", at: stamp)
        meta.gear = SyncedField(["wing": "Duotone Unit 5 m"], at: stamp)

        try container.writeOriginal(data, id: meta.id)
        try container.writeMeta(meta)
        try container.writeTombstones(SyncedTombstones(stones: [
            SyncedTombstone(id: "gone", startDate: stamp, durationS: 900, deletedAt: stamp),
        ]))

        // The layout the ADR promises, on disk, by name.
        let dir = container.root.appendingPathComponent("Sessions/session-1", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("original.fit").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meta.json").path))
        #expect(FileManager.default.fileExists(
            atPath: container.root.appendingPathComponent("tombstones.json").path))
        // And no analysis cache: each device re-analyses what it receives.
        #expect(!FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("analysis.json").path))

        #expect(container.sessionIDs() == ["session-1"])
        #expect(container.meta(for: "session-1") == meta)
        #expect(container.tombstones().stones.map(\.id) == ["gone"])
        #expect(container.originalURL(for: "session-1")?.lastPathComponent == "original.fit")
    }

    // MARK: - Two devices

    @Test func aSessionCrossesToTheOtherDevice() async throws {
        let container = try makeContainer()
        let phone = try makeDevice("phone")
        let pad = try makeDevice("pad")
        defer {
            try? FileManager.default.removeItem(at: container.root)
            try? FileManager.default.removeItem(at: phone.home)
            try? FileManager.default.removeItem(at: pad.home)
        }

        let row = try await ingest(0, into: phone)
        try await phone.store.renameSession(id: row.id, to: "Morning at Torbole")
        try await phone.store.setShareNote(id: row.id, to: "Cold and glassy")

        let out = try await engine(phone, container).sync()
        #expect(out.uploaded == 1)

        let back = try await engine(pad, container).sync()
        #expect(back.downloaded == 1)

        // The uuid is this device's own — the folder is keyed by the phone's, and nothing
        // renumbers a library row (ADR-026). What crossed is the session and its facts.
        let landed = try #require(try await pad.ingestor.allSessions().first)
        #expect(landed.customTitle == "Morning at Torbole")
        #expect(landed.shareNote == "Cold and glassy")
        #expect(landed.startDate == row.startDate)
        // The analysis is this device's own work, not a copied file.
        #expect(pad.ingestor.archive.analysis(for: landed.id) != nil)

        // And a second pass on either device adds nothing: one afternoon, one folder.
        try await engine(pad, container).sync()
        try await engine(phone, container).sync()
        #expect(container.sessionIDs() == [row.id])
        #expect(try await pad.ingestor.allSessions().count == 1)
    }

    @Test func aSessionAlreadyHeldIsRecognisedByTheDedupeRule() async throws {
        let container = try makeContainer()
        let phone = try makeDevice("phone")
        let pad = try makeDevice("pad")
        defer {
            try? FileManager.default.removeItem(at: container.root)
            try? FileManager.default.removeItem(at: phone.home)
            try? FileManager.default.removeItem(at: pad.home)
        }

        // The same afternoon on both devices, imported separately, so it carries two uuids.
        let mine = try await ingest(0, into: phone)
        let theirs = try await ingest(0, into: pad)
        #expect(mine.id != theirs.id)

        try await engine(phone, container).sync()
        let back = try await engine(pad, container).pull()

        #expect(back.duplicates == 1)
        #expect(back.downloaded == 0)
        // One session, not two: the ±60 s rule is the front door and it holds here too.
        #expect(try await pad.ingestor.allSessions().count == 1)
    }

    @Test func aRenameOnTheSecondDeviceReachesTheFirst() async throws {
        let container = try makeContainer()
        let phone = try makeDevice("phone")
        let pad = try makeDevice("pad")
        defer {
            try? FileManager.default.removeItem(at: container.root)
            try? FileManager.default.removeItem(at: phone.home)
            try? FileManager.default.removeItem(at: pad.home)
        }

        let row = try await ingest(0, into: phone)
        try await engine(phone, container).sync()
        try await engine(pad, container).sync()

        let there = try #require(try await pad.ingestor.allSessions().first)
        try await pad.store.renameSession(id: there.id, to: "First 20-knot run")
        try await engine(pad, container).push()
        try await engine(phone, container).pull()

        let here = try #require(try await phone.ingestor.session(id: row.id))
        #expect(here.customTitle == "First 20-knot run")
    }

    /// The baseline's whole job: a name typed on this device survives the pull that runs
    /// before the push, instead of being cleared by the folder's older, emptier copy.
    @Test func anEditMadeHereSurvivesTheNextPass() async throws {
        let container = try makeContainer()
        let phone = try makeDevice("phone")
        let pad = try makeDevice("pad")
        defer {
            try? FileManager.default.removeItem(at: container.root)
            try? FileManager.default.removeItem(at: phone.home)
            try? FileManager.default.removeItem(at: pad.home)
        }

        let row = try await ingest(0, into: phone)
        try await engine(phone, container).sync()
        try await engine(pad, container).sync()

        let there = try #require(try await pad.ingestor.allSessions().first)
        try await pad.store.renameSession(id: there.id, to: "Late session")
        try await engine(pad, container).sync()

        #expect(try await pad.ingestor.session(id: there.id)?.customTitle == "Late session")
        try await engine(phone, container).sync()
        #expect(try await phone.ingestor.session(id: row.id)?.customTitle == "Late session")
    }

    @Test func gearTravelsByNameAndIsCreatedOnArrival() async throws {
        let container = try makeContainer()
        let phone = try makeDevice("phone")
        let pad = try makeDevice("pad")
        defer {
            try? FileManager.default.removeItem(at: container.root)
            try? FileManager.default.removeItem(at: phone.home)
            try? FileManager.default.removeItem(at: pad.home)
        }

        let row = try await ingest(0, into: phone)
        let wing = try await phone.store.saveGear(GearRow(name: "Duotone Unit 5 m", kind: .wing))
        try await phone.store.assignGear(sessionId: row.id, kind: .wing, gearId: wing.id)

        try await engine(phone, container).sync()
        try await engine(pad, container).sync()

        let there = try #require(try await pad.ingestor.allSessions().first)
        let landed = try await pad.store.gearOfSession(there.id)
        #expect(landed[.wing]?.name == "Duotone Unit 5 m")
        // A row of its own on this device — the other phone's id names nothing here.
        #expect(landed[.wing]?.id != wing.id)
    }

    // MARK: - Deleting, and staying deleted

    @Test func aDeleteOnOneDeviceDeletesOnTheOther() async throws {
        let container = try makeContainer()
        let phone = try makeDevice("phone")
        let pad = try makeDevice("pad")
        defer {
            try? FileManager.default.removeItem(at: container.root)
            try? FileManager.default.removeItem(at: phone.home)
            try? FileManager.default.removeItem(at: pad.home)
        }

        let row = try await ingest(0, into: phone)
        try await engine(phone, container).sync()
        try await engine(pad, container).sync()
        #expect(try await pad.ingestor.allSessions().count == 1)

        try await phone.ingestor.delete(row)
        try await engine(phone, container).sync()

        let back = try await engine(pad, container).sync()
        #expect(back.deletedHere == 1)
        #expect(try await pad.ingestor.allSessions().isEmpty)
        // And the deletion is written down on this device too, so every other door is shut.
        // One stone for one afternoon, under this device's own uuid.
        #expect(try await pad.store.tombstoneCount() == 1)
        // The bytes do not linger in iCloud Drive.
        #expect(container.originalURL(for: row.id) == nil)
    }

    @Test func theSameRecordingDoesNotComeBackAfterATombstone() async throws {
        let container = try makeContainer()
        let phone = try makeDevice("phone")
        let pad = try makeDevice("pad")
        defer {
            try? FileManager.default.removeItem(at: container.root)
            try? FileManager.default.removeItem(at: phone.home)
            try? FileManager.default.removeItem(at: pad.home)
        }

        let row = try await ingest(0, into: phone)
        try await engine(phone, container).sync()
        try await engine(pad, container).sync()
        try await phone.ingestor.delete(row)
        try await engine(phone, container).sync()
        try await engine(pad, container).sync()
        #expect(try await pad.ingestor.allSessions().isEmpty)

        // The rider drops the very same file into the *other* device's folder again —
        // a re-import under a fresh uuid, which the id half of the rule would never catch.
        let (data, _) = try fixture(0)
        try container.writeOriginal(data, id: "a-fresh-uuid")
        var meta = SyncedSessionMeta(id: "a-fresh-uuid", startDate: row.startDate,
                                     durationS: row.durationS)
        meta.customTitle = SyncedField("Back again", at: .now)
        try container.writeMeta(meta)

        let back = try await engine(pad, container).pull()
        #expect(back.blocked > 0)
        #expect(back.downloaded == 0)
        #expect(try await pad.ingestor.allSessions().isEmpty)
    }

    @Test func tombstonesMergeBothWaysAndAreNeverDropped() async throws {
        let stamp = Date(timeIntervalSince1970: 1_756_000_000)
        let mine = SyncedTombstones(stones: [
            SyncedTombstone(id: "a", startDate: stamp, durationS: 900, deletedAt: stamp),
        ])
        let theirs = SyncedTombstones(stones: [
            SyncedTombstone(id: "b", startDate: stamp, durationS: 900, deletedAt: stamp),
        ])
        #expect(Set(mine.merged(with: theirs).stones.map(\.id)) == ["a", "b"])

        // A session deleted twice keeps the later deletion, not the earlier one.
        let later = SyncedTombstones(stones: [
            SyncedTombstone(id: "a", startDate: stamp, durationS: 900, title: "renamed",
                            deletedAt: stamp.addingTimeInterval(60)),
        ])
        #expect(mine.merged(with: later).stones.first?.title == "renamed")
    }

    @Test func aTombstoneBlocksByTheDedupeKeyAsWellAsByTheId() {
        let stamp = Date(timeIntervalSince1970: 1_756_000_000)
        let stones = SyncedTombstones(stones: [
            SyncedTombstone(id: "a", startDate: stamp, durationS: 1800, deletedAt: stamp),
        ])
        // Same afternoon, different uuid, thirty seconds off on both ends.
        #expect(stones.blocking(id: "other", startDate: stamp.addingTimeInterval(30),
                                durationS: 1830) != nil)
        // Two minutes out is a different session.
        #expect(stones.blocking(id: "other", startDate: stamp.addingTimeInterval(120),
                                durationS: 1800) == nil)
    }

    // MARK: - The dry run

    @Test func thePlanSaysWhatAPassWouldDoWithoutDoingIt() async throws {
        let container = try makeContainer()
        let phone = try makeDevice("phone")
        let pad = try makeDevice("pad")
        defer {
            try? FileManager.default.removeItem(at: container.root)
            try? FileManager.default.removeItem(at: phone.home)
            try? FileManager.default.removeItem(at: pad.home)
        }

        let row = try await ingest(0, into: phone)
        let before = try await engine(phone, container).plan()
        #expect(before.localSessions == 1)
        #expect(before.toUpload == [row.id])
        #expect(before.containerSessions == 0)
        // A dry run wrote nothing.
        #expect(container.sessionIDs().isEmpty)

        try await engine(phone, container).sync()
        let after = try await engine(phone, container).plan()
        #expect(after.pending == 0)

        let waiting = try await engine(pad, container).plan()
        #expect(waiting.toDownload == [row.id])
        #expect(waiting.pending == 1)
    }

    /// Settings → iCloud Drive said "69 sessions" beside a library of 63 (Jan's Dev 106, 25
    /// Sep 2026): a deleted session keeps its `meta.json` in the folder, and the count was
    /// of folders. The count is of sessions — one per afternoon, none deleted.
    @Test func theFolderCountIsSessionsNotFolders() async throws {
        let container = try makeContainer()
        let phone = try makeDevice("phone")
        let pad = try makeDevice("pad")
        defer {
            try? FileManager.default.removeItem(at: container.root)
            try? FileManager.default.removeItem(at: phone.home)
            try? FileManager.default.removeItem(at: pad.home)
        }

        let kept = try await ingest(0, into: phone)
        let gone = try await ingest(1, into: phone)
        try await engine(phone, container).sync()
        try await phone.ingestor.delete(gone)
        try await engine(phone, container).sync()

        let plan = try await engine(phone, container).plan()
        #expect(plan.containerFolders == 2)
        #expect(plan.containerDeleted == 1)
        #expect(plan.containerSessions == 1)
        #expect(plan.containerSessions == plan.localSessions)
        #expect(plan.pending == 0)

        // A second folder for the same afternoon under another uuid is one session, and the
        // device that lacks it has one to fetch, not two.
        let (data, _) = try fixture(0)
        try container.writeOriginal(data, id: "zz-second-folder")
        try container.writeMeta(SyncedSessionMeta(id: "zz-second-folder",
                                                  startDate: kept.startDate.addingTimeInterval(5),
                                                  durationS: kept.durationS))
        let doubled = try await engine(pad, container).plan()
        #expect(doubled.containerFolders == 3)
        #expect(doubled.containerSessions == 1)
        #expect(doubled.containerDuplicates == 1)
        #expect(doubled.toDownload.count == 1)
        #expect(doubled.pending == 1)
    }

    @Test func theContainerIdentifierFollowsTheChannel() {
        #expect(LibrarySyncLayout.containerIdentifier(bundleID: "de.lahmann.wingfoil")
                == LibrarySyncLayout.releaseContainer)
        #expect(LibrarySyncLayout.containerIdentifier(bundleID: "de.lahmann.wingfoil.dev")
                == LibrarySyncLayout.devContainer)
    }
}
