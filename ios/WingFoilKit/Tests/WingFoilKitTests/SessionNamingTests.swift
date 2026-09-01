import Foundation
import GRDB
import Testing
@testable import WingFoilKit

/// Schema v9: the rider names his own session, and writes a line for whoever he sends it to.
///
/// Two columns and one preference rule, and the whole feature's failure mode is a *partial*
/// rename — the library row says "First 20 kn" and the video still says "Nago Torbole
/// Windsurfen". So what is pinned here is the chain rather than the columns: one function
/// decides the name, one function normalizes the caption, and the surfaces that print either
/// one are the ones that ask them.
@Suite struct SessionNamingTests {

    // MARK: - The schema

    /// A shipped v8 library gains two nullable columns and nothing else — in particular, no
    /// row loses its name, because there was never a name in the database to lose.
    @Test func v9AddsTheTwoNameColumnsAndLeavesEveryExistingRowDerived() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v8")
        let before = try queue.read { db in Set(try db.columns(in: "session").map(\.name)) }
        #expect(!before.contains("customTitle"))
        #expect(!before.contains("shareNote"))

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO session (id, startDate, durationS, sourceClass, originalFilename,
                                     isExample, isProvisional)
                VALUES ('legacy', ?, 3600, 'b', '2026-08-30-1407_nago-torbole_ciq.fit', 0, 0)
                """, arguments: [Date(timeIntervalSince1970: 1_788_048_000)])
        }

        _ = try AppDatabase(queue)                          // ← runs v9

        let after = try queue.read { db in Set(try db.columns(in: "session").map(\.name)) }
        #expect(after.contains("customTitle"))
        #expect(after.contains("shareNote"))

        let migrated = try #require(try queue.read { db in
            try SessionRow.fetchOne(db, key: "legacy")
        })
        // NULL, not "": a pre-v9 session has not been named, which is a different fact from
        // having been named nothing.
        #expect(migrated.customTitle == nil)
        #expect(migrated.shareNote == nil)
    }

    @Test func v9IsRegisteredAndReachableFromAV1Library() throws {
        #expect(AppDatabase.migrationNames.last == "v9")
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        _ = try AppDatabase(queue)
        let applied = try queue.read { db in try AppDatabase.migrator.appliedMigrations(db) }
        #expect(applied == AppDatabase.migrationNames)
    }

    // MARK: - The preference chain

    /// The one rule every surface follows. `SessionDisplay.title` in the app is this function
    /// plus the filename derivation, which is why a rename reaches eleven screens without any
    /// of them being edited.
    @Test func theRidersNameWinsAndBlankGivesTheDerivedOneBack() {
        #expect(SessionNaming.title(custom: "First 20 kn", derived: "Nago Torbole")
                == "First 20 kn")
        #expect(SessionNaming.title(custom: nil, derived: "Nago Torbole") == "Nago Torbole")
        // Cleared, and cleared-to-whitespace, are both "give me the derived name back".
        #expect(SessionNaming.title(custom: "", derived: "Nago Torbole") == "Nago Torbole")
        #expect(SessionNaming.title(custom: "   \n ", derived: "Nago Torbole")
                == "Nago Torbole")
        // The derived name is used verbatim, fallback included: the kit does not know that
        // "Session" is what the app produces for a recording that says nothing.
        #expect(SessionNaming.title(custom: nil, derived: "Session") == "Session")
    }

    @Test func aStoredTitleIsTrimmedCappedAndNeverBlank() {
        #expect(SessionNaming.customTitle("  Torbole  ") == "Torbole")
        #expect(SessionNaming.customTitle("") == nil)
        #expect(SessionNaming.customTitle("\t \n") == nil)
        #expect(SessionNaming.customTitle(nil) == nil)
        // Interior spacing is the rider's, not the normalizer's.
        #expect(SessionNaming.customTitle("First  20 kn") == "First  20 kn")
        let long = String(repeating: "a", count: SessionNaming.titleLimit + 40)
        #expect(SessionNaming.customTitle(long)?.count == SessionNaming.titleLimit)
    }

    // MARK: - What the composer's title field opens with

    /// The share composer prefills its title field, and this is the value it prefills with.
    /// It has to be the name the card is showing, or the rider is editing a string he has
    /// never seen; and it must never be blank, or the "prefill" is the empty field this
    /// replaced.
    @Test func theTitleFieldOpensOnWhateverTheSessionIsCurrentlyCalled() {
        // Nobody has renamed this one: the field opens on the derived name — corrected, so it
        // says Wingfoil and not the word the watch wrote.
        #expect(SessionNaming.titleDraft(custom: nil, derived: "Nago Torbole Wingfoil")
                == "Nago Torbole Wingfoil")
        // He has: the field opens on his own words, not on the derivation underneath them.
        #expect(SessionNaming.titleDraft(custom: "First 20 kn", derived: "Nago Torbole Wingfoil")
                == "First 20 kn")
        // A stored blank is "never named", the same as nil — and still opens on the derived
        // name rather than on nothing.
        #expect(SessionNaming.titleDraft(custom: "", derived: "Nago Torbole Wingfoil")
                == "Nago Torbole Wingfoil")
        #expect(SessionNaming.titleDraft(custom: "  \n ", derived: "Nago Torbole Wingfoil")
                == "Nago Torbole Wingfoil")
        // A recording that says nothing about itself still opens on a word.
        #expect(SessionNaming.titleDraft(custom: nil, derived: "Session") == "Session")

        // The draft and the title are one rule, deliberately: the field the rider edits and
        // the headline he is editing may not resolve differently.
        for custom in [nil, "", "  ", "First 20 kn"] {
            #expect(SessionNaming.titleDraft(custom: custom, derived: "Nago Torbole Wingfoil")
                    == SessionNaming.title(custom: custom, derived: "Nago Torbole Wingfoil"))
        }
    }

    /// The other half of the prefill: a sheet that is opened and closed is not a rename.
    /// `ShareComposerView` seeds its *committed* value with the same draft, so nothing is
    /// written unless a key is pressed — and a draft still equal to the derived name is
    /// written through as "", which is what leaves the row derived.
    @Test func aPrefilledFieldLeftAloneLeavesTheSessionDerived() async throws {
        let (store, database) = try harness()
        try await insert(database)
        let row = try await read(database)
        #expect(row.customTitle == nil)

        let derived = "Nago Torbole"                 // what the app derives from this filename
        let draft = SessionNaming.titleDraft(custom: row.customTitle, derived: derived)
        #expect(draft == derived)

        // The composer's rule, applied to an untouched draft.
        try await store.renameSession(id: "s1", to: draft == derived ? "" : draft)
        #expect(try await read(database).customTitle == nil)

        // One keystroke on the end of the prefill, and it *is* a rename.
        let edited = draft + " — first 20 kn"
        try await store.renameSession(id: "s1", to: edited == derived ? "" : edited)
        #expect(try await read(database).customTitle == "Nago Torbole — first 20 kn")
    }

    // MARK: - Garmin's word for it

    /// The watch has no wingfoil profile, so every session it records is named after the
    /// windsurf one — in the watch's own locale. The swap is display-only and it is the
    /// derived branch's alone.
    @Test func garminsSportWordBecomesTheOneTheAppIsAbout() {
        #expect(SessionNaming.sport == "Wingfoil")
        // The three spellings that arrive: a German watch, an English one, and the bare
        // profile name.
        #expect(SessionNaming.sportCorrected("Nago Torbole Windsurfen") == "Nago Torbole Wingfoil")
        #expect(SessionNaming.sportCorrected("Nago Torbole Windsurfing") == "Nago Torbole Wingfoil")
        #expect(SessionNaming.sportCorrected("Windsurf") == "Wingfoil")
        // The case of the position is kept, because the callers differ: the app's derivation
        // capitalises every word and nothing says the next caller will.
        #expect(SessionNaming.sportCorrected("torbole windsurfen") == "torbole wingfoil")
        // Standalone, not a substring. A windsurf school is still a windsurf school.
        #expect(SessionNaming.sportCorrected("Windsurfschule Torbole")
                == "Windsurfschule Torbole")
        #expect(SessionNaming.sportCorrected("Kitesurfing") == "Kitesurfing")
        // A name with nothing of Garmin's in it comes back untouched, spacing included.
        #expect(SessionNaming.sportCorrected("Nago  Torbole") == "Nago  Torbole")
        #expect(SessionNaming.sportCorrected("") == "")
    }

    /// The rider's own name is never corrected: he is naming his afternoon, and this app does
    /// not have opinions about what he calls it.
    @Test func aTypedTitleKeepsGarminsWordIfThatIsWhatHeTyped() {
        #expect(SessionNaming.title(custom: "Windsurfen mit Tobi",
                                    derived: "Nago Torbole Wingfoil") == "Windsurfen mit Tobi")
        #expect(SessionNaming.title(custom: nil, derived: SessionNaming
            .sportCorrected("Nago Torbole Windsurfen")) == "Nago Torbole Wingfoil")
    }

    /// The other end of the chain: the word is in the *filename* the sync writes, which is
    /// what the app's `SessionDisplay.derivedTitle` reads and corrects. Pinned here so a
    /// change to the slug cannot quietly move the word out of the part of the name the
    /// derivation uses.
    @Test func theIcuFilenameCarriesGarminsWordIntoTheDerivedPart() {
        let activity = IcuActivity(id: "i123", name: "Nago-Torbole Windsurfen")
        let name = IcuSyncService.filename(for: activity)
        #expect(name == "i123_nago-torbole-windsurfen_icu.fit")
        // What the app then makes of it, in the app's own two steps: the middle
        // underscore-part, hyphens to spaces, capitalised — and corrected.
        let stem = name.split(separator: "_")[1]
        let words = stem.replacingOccurrences(of: "-", with: " ").split(separator: " ")
            .map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
        #expect(SessionNaming.sportCorrected(words.joined(separator: " "))
                == "Nago Torbole Wingfoil")
    }

    // MARK: - The caption

    /// The cap is content, not chrome: a caption is drawn into a PNG, so the length at which
    /// it stops being legible is decided before a pixel exists and enforced on the way in.
    @Test func theCaptionIsOneTrimmedCappedLine() {
        #expect(SessionNaming.noteLimit == 80)
        #expect(SessionNaming.note("  cold and glassy  ") == "cold and glassy")
        #expect(SessionNaming.note("") == nil)
        #expect(SessionNaming.note("   ") == nil)
        #expect(SessionNaming.note(nil) == nil)

        // Pasted from a chat, two lines. Folded rather than refused — he meant both of them —
        // and folded to a space, because a newline reaching the card draws as a box on one
        // platform and as nothing on the other.
        #expect(SessionNaming.note("cold and glassy\nfinally got the tack")
                == "cold and glassy finally got the tack")
        #expect(SessionNaming.note("a\r\n\r\nb") == "a b")

        // 16 × "wind " is exactly 80 characters and the 80th is a space, so the cut lands on
        // one — and the second trim takes it off rather than storing a caption that draws a
        // gap before nothing.
        #expect(SessionNaming.note(String(repeating: "wind ", count: 40))?.count
                == SessionNaming.noteLimit - 1)
        // Whatever the cut lands on, the stored value never ends in whitespace.
        for length in (SessionNaming.noteLimit - 2)...(SessionNaming.noteLimit + 6) {
            let note = SessionNaming.note(String(repeating: "ab ", count: length))
            #expect(note?.hasSuffix(" ") == false, "a cap left a trailing space at \(length)")
            #expect((note?.count ?? 0) <= SessionNaming.noteLimit)
        }
    }

    // MARK: - The store

    private func harness() throws -> (LibraryStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (LibraryStore(database: database), database)
    }

    private func insert(_ database: AppDatabase, id: String = "s1") async throws {
        var row = SessionRow(id: id, startDate: Date(timeIntervalSince1970: 1_788_048_000),
                             durationS: 3600, sourceClass: "b")
        row.originalFilename = "2026-08-30-1407_nago-torbole_ciq.fit"
        let stored = row
        try await database.writer.write { db in try stored.insert(db) }
    }

    private func read(_ database: AppDatabase, id: String = "s1") async throws -> SessionRow {
        try #require(try await database.writer.read { db in
            try SessionRow.fetchOne(db, key: id)
        })
    }

    @Test func renamingASessionRoundTripsAndClearingItRestoresTheDerivedName() async throws {
        let (store, database) = try harness()
        try await insert(database)

        try await store.renameSession(id: "s1", to: "  First 20 kn  ")
        #expect(try await read(database).customTitle == "First 20 kn")

        // Cleared. NULL rather than "", so `SessionNaming.title` falls through to the
        // derived name and every surface follows in one step.
        try await store.renameSession(id: "s1", to: "   ")
        #expect(try await read(database).customTitle == nil)

        try await store.renameSession(id: "s1", to: nil)
        #expect(try await read(database).customTitle == nil)

        // Capped in the store as well as in the field: a value that arrived some other way
        // must not be able to put a paragraph in a 75-px headline.
        try await store.renameSession(id: "s1",
                                      to: String(repeating: "n", count: 400))
        #expect(try await read(database).customTitle?.count == SessionNaming.titleLimit)
    }

    @Test func theCaptionRoundTripsThroughTheStoreUnderTheSameRules() async throws {
        let (store, database) = try harness()
        try await insert(database)

        try await store.setShareNote(id: "s1", to: "cold and glassy\nfinally got the tack")
        #expect(try await read(database).shareNote == "cold and glassy finally got the tack")

        try await store.setShareNote(id: "s1", to: String(repeating: "z", count: 300))
        #expect(try await read(database).shareNote?.count == SessionNaming.noteLimit)

        try await store.setShareNote(id: "s1", to: "")
        #expect(try await read(database).shareNote == nil)

        // The two are independent: naming a session does not caption it, and captioning one
        // does not rename it.
        try await store.renameSession(id: "s1", to: "Torbole evening")
        #expect(try await read(database).shareNote == nil)
        try await store.setShareNote(id: "s1", to: "glassy")
        let row = try await read(database)
        #expect(row.customTitle == "Torbole evening")
        #expect(row.shareNote == "glassy")
    }

    // MARK: - What the card and the clip do with them

    private func row(note: String? = nil) -> SessionRow {
        var row = SessionRow(id: "s1", startDate: Date(timeIntervalSince1970: 1_785_000_000),
                             durationS: 5400, sourceClass: "b")
        row.distanceKm = 34.2
        row.best2sKn = 21.37
        row.shareNote = note
        return row
    }

    /// The caption is a second line of *identity*, not a ninth stat. The contract that the
    /// card's numbers are the app's numbers has to survive it untouched.
    @Test func theCaptionRidesOnTheCardWithoutTouchingItsStats() {
        let utc = TimeZone(identifier: "UTC")!
        let plain = ShareCardStats.make(row: row(), title: "Torbole", timeZone: utc)
        let captioned = ShareCardStats.make(row: row(), title: "Torbole",
                                            note: "cold and glassy", timeZone: utc)

        #expect(plain.note == nil)
        #expect(captioned.note == "cold and glassy")
        // Same cells, same order, same strings — the caption changed the header and nothing
        // else. This is the "absent = today's card" half of the layout contract, said in the
        // only place it can be said without a renderer.
        #expect(captioned.stats == plain.stats)
        #expect(captioned.title == plain.title)
        #expect(captioned.dateLine == plain.dateLine)
        #expect(captioned.preset == plain.preset)
        #expect(captioned.disclaimer == plain.disclaimer)
    }

    /// Normalized by the type, not by its callers — the same rules the store applies, so a
    /// caption that reached the card some other way is still one capped line.
    @Test func theCardNormalizesWhateverCaptionItIsGiven() {
        let utc = TimeZone(identifier: "UTC")!
        let card = ShareCardStats.make(row: row(), title: "Torbole",
                                       note: "  two\nlines  ", timeZone: utc)
        #expect(card.note == "two lines")
        let long = ShareCardStats.make(row: row(), title: "Torbole",
                                       note: String(repeating: "y", count: 300),
                                       timeZone: utc)
        #expect(long.note?.count == SessionNaming.noteLimit)
        #expect(ShareCardStats.make(row: row(), title: "Torbole", note: "   ",
                                    timeZone: utc).note == nil)
    }

    /// The closing frame of a clip does **not** repeat it: the rider's line has already been
    /// on screen, over the whole glass, on the opening card. See `ShareCardStats.outro`.
    @Test func theClipsClosingCardCarriesNoCaption() {
        let outro = ShareCardStats.outro(row: row(note: "cold and glassy"), title: "Torbole",
                                         longestFlightS: 184,
                                         timeZone: TimeZone(identifier: "UTC")!)
        #expect(outro.note == nil)
        #expect(outro.stats.contains { $0.key == ShareCardStats.Key.longestFlight })
    }

    /// The clip's opening card is where it does appear — third line, under the date, and
    /// under the same rules.
    @Test func theClipsTitleCardPrintsTheCaptionUnderTheDate() {
        let started = Date(timeIntervalSince1970: 1_788_048_000)
        let card = ReplayTitleCard.make(place: "Torbole", startedAt: started,
                                        timeZone: fixtureZone, note: " cold and glassy ")
        #expect(card.place == "Torbole")
        #expect(card.dateLine.contains("2026"))
        #expect(card.note == "cold and glassy")

        // No caption is the card as it has always been.
        #expect(ReplayTitleCard.make(place: "Torbole", startedAt: started,
                                     timeZone: fixtureZone).note == nil)
        #expect(ReplayTitleCard.make(place: "Torbole", startedAt: started,
                                     timeZone: fixtureZone, note: "  ").note == nil)
    }

    /// And the storyboard hands it down, so the cinema view never has to know the caption
    /// exists — it renders `storyboard.title`, which already carries it.
    @Test func theStoryboardHandsTheCaptionToItsTitleCard() {
        let board = ReplayStoryboard.make(span: 0...600, rate: 30, place: "Torbole",
                                          startedAt: Date(timeIntervalSince1970: 1_788_048_000),
                                          timeZone: fixtureZone,
                                          note: "cold and glassy")
        #expect(board.title.note == "cold and glassy")
        // The caption is words on a frame; it moves nothing about how long the clip runs.
        let silent = ReplayStoryboard.make(span: 0...600, rate: 30, place: "Torbole",
                                           startedAt: Date(timeIntervalSince1970: 1_788_048_000),
                                           timeZone: fixtureZone)
        #expect(board.runWallS == silent.runWallS)
    }
}
