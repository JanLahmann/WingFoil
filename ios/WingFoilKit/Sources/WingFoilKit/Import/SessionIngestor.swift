import Foundation
import GRDB

/// Where a session entered the library. Stored in `session.importSource`; a session that
/// arrives twice keeps every source it was seen from (`"file+icu"`).
public enum ImportSource: String, Sendable, CaseIterable {
    case icu
    case file
    case gdpr
    case airdrop
    case fixtures
    /// The FIT bundled with the app (`ExampleSession`). The only source that sets
    /// `SessionRow.isExample`, and the only one a later real import can override.
    case example
    /// The watch's BLE card (phase 5, `CompanionSummary`). The only source that carries
    /// no FIT, so the only one that can leave a row `isProvisional`.
    ///
    /// "Watch" unqualified means **Garmin** throughout this app, which predates the Apple
    /// Watch recorder by four phases; `appleWatch` below is the other one, deliberately
    /// spelled out.
    case watch
    /// A `.cjw` container handed over by the CleanJibe watchOS app
    /// (docs/watch-session-schema.md). Distinct from `.watch` because the two are not the
    /// same event: that one is a Garmin summary card with no recording behind it, this one
    /// is a complete recording that arrived without ever touching an account, a cable or
    /// anybody's cloud.
    ///
    /// Read by `SessionDisplay.sourceClassNote` (a watch session is class (b) but *does*
    /// have an accelerometer, so the standard class-(b) sentence would understate it) and by
    /// `SessionStore.writeNewSessionsToHealth` (the watch already filed this workout with
    /// Health itself, live, with the ring credit the phone's after-the-fact stub cannot give).
    case appleWatch = "applewatch"
    /// The Garmin watch's **direct** stream (docs/transfer-format.md), sent page by page over
    /// the Connect IQ link and imported as a `.cjr` — a DEV door (docs/channels.md).
    ///
    /// The fourth source with a watch in its story and the fourth that means something else
    /// by it. `.watch` is the Garmin summary card, twenty integers with no recording behind
    /// them; this is the recording itself, off the same watch, arriving while the rider is
    /// still on the beach. A card that came first left a provisional row and this fills it,
    /// by the ±60 s rule every other import uses.
    case watchDirect = "watchdirect"
    /// A workout recorded with **Apple's own Workout app** and read back out of Health
    /// (docs/decisions.md ADR-017). The third source with "watch" somewhere in its story and
    /// the third that means something different by it: `.watch` is a Garmin BLE summary card,
    /// `.appleWatch` is a recording the CleanJibe watch app handed over directly, and this one
    /// is a recording made by somebody else's app that we were allowed to read.
    ///
    /// It is the reason `SessionStore.writeNewSessionsToHealth` has a second exclusion: these
    /// workouts are *already in* Health — writing our own stub back would put two overlapping
    /// `.surfingSports` workouts on the same afternoon, and the rider would have imported a
    /// session in order to be shown it twice.
    case appleHealth = "applehealth"
    /// An activity pulled from **Strava** (docs/decisions.md ADR-023). The second cloud
    /// source beside intervals.icu, and the one that is class (c) by construction: Strava
    /// hands back positions, a clock, an elevation and a heart rate — no Doppler channel and
    /// no accelerometer — so `StravaImport` writes exactly what it has, a GPX, and the source
    /// class follows from the format rather than from a special case anywhere downstream.
    case strava

    /// Whether a merged `session.importSource` names this source.
    ///
    /// The column is a `+`-joined set (`"applewatch+icu"` once a sync has seen the same
    /// session), so membership is a split-and-search rather than a comparison — and
    /// emphatically not a substring test, which would have `.watch` matching `"applewatch"`
    /// and quietly conflating a Garmin BLE card with an Apple Watch recording.
    public func isNamed(in importSource: String?) -> Bool {
        guard let importSource else { return false }
        return importSource.split(separator: "+").contains(Substring(rawValue))
    }
}

/// What the importer refuses, as an error rather than as a crash.
///
/// One entry: a recording whose own clock says it lasted longer than any session can. It is
/// a *typed* error because it has to reach `IcuSyncSummary.failed` beside the activity id —
/// the rider who syncs seventy-four files and loses one deserves to be told which, and the
/// alternative (letting the number through into an engine that sizes arrays with it) is an
/// out-of-memory kill that leaves no crash report at all.
public enum IngestError: Error, CustomStringConvertible {
    case implausibleDuration(durationS: TimeInterval)

    public var description: String {
        switch self {
        case .implausibleDuration(let s):
            guard s.isFinite else { return "the recording's timestamps are broken" }
            let days = Int(clamped: s / 86_400)
            return "the recording's timestamps are broken (it claims to span "
                + "\(days) day\(days == 1 ? "" : "s"))"
        }
    }
}

public enum IngestOutcome: Sendable {
    case imported(SessionRow)
    /// Already in the library (dedupe key matched); the row carries the merged note.
    case duplicate(SessionRow)
    /// Already in the library as a **weaker copy** — positions only, a Strava or GPX file —
    /// and this recording carries speed, so it took the copy's place (release round A,
    /// finding F-6). `SessionRow` is the row as it is now, same id, with the rider's name,
    /// caption, rider, gear and spot kept; `weaker` is the row as it was, for the one line
    /// the rider is told (`SessionIngestor.replacedLine`).
    case replaced(SessionRow, weaker: SessionRow)
    /// Bulk import only: a FIT that is not a watersport session.
    case skipped(reason: String)
}

public struct ImportSummary: Sendable, Equatable {
    /// FITs discovered in the container (imported + duplicates + skipped + failed).
    public var found = 0
    public var imported = 0
    public var duplicates = 0
    public var skipped = 0
    public var failed: [String] = []
    /// The weaker copies a recording with speed replaced (F-6), as the rows were before.
    /// Counted in none of the three tallies above, and told once by `shortDescription`.
    public var replaced: [SessionRow] = []
    /// Name of the file currently being processed — live progress for the UI.
    public var current: String?

    public init() {}

    public var isEmpty: Bool {
        imported == 0 && duplicates == 0 && skipped == 0 && failed.isEmpty && replaced.isEmpty
    }

    public var processed: Int { imported + duplicates + skipped + failed.count + replaced.count }

    public var shortDescription: String {
        var parts: [String] = ["\(imported) imported"]
        if duplicates > 0 { parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s")") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        let tally = parts.joined(separator: ", ")
        guard let line = SessionIngestor.replacedLine(replaced) else { return tally }
        // A run that did nothing but replace says only that.
        return imported == 0 && duplicates == 0 && skipped == 0 && failed.isEmpty
            ? line : "\(line). \(tally)"
    }

    /// Merges another container's tally into this one (multi-file picks, live progress).
    public mutating func absorb(_ other: ImportSummary) {
        found += other.found
        imported += other.imported
        duplicates += other.duplicates
        skipped += other.skipped
        failed.append(contentsOf: other.failed)
        replaced.append(contentsOf: other.replaced)
    }
}

/// Recording bytes (FIT or GPX) → analysis → archive + `session` row + the schema-v2
/// child tables. Dedupe key per plan §3.3: start within ±60 s **and** duration within
/// ±60 s (the same session reaches us from intervals.icu, a GDPR bulk ZIP and AirDrop
/// with slightly different rounding).
public struct SessionIngestor: Sendable {

    /// Sports we accept during bulk (ZIP) import. Everything else needs our developer
    /// fields to qualify — Jan's CIQ recordings land as `walking`.
    /// Compared lower-cased, which is why Strava's `sport_type` spellings sit here beside
    /// the FIT's: since engine 0.19.0 a GPX's `<trk><type>` reaches `caps.sport`, and
    /// Strava calls the same afternoon `Windsurf` where a Garmin calls it `windsurfing`.
    public static let watersportSports: Set<String> = [
        "windsurfing", "kitesurfing", "sailing", "surfing", "stand_up_paddleboarding",
        "windsurf", "kitesurf", "sail", "standuppaddling", "wingfoil",
        "43", "44",
    ]

    /// The longest span a recording may claim and still be read as one session — a week.
    /// See the guard in `ingest(fitData:…)`; this is a corruption gate, not a rule about
    /// how long anybody may stay on the water.
    public static let maxSessionDurationS: TimeInterval = 7 * 24 * 3600

    public var database: AppDatabase
    public var archive: SessionArchive
    public var filterConfig = FilterConfig()
    public var flightConfig = FlightConfig()
    public var recordsConfig = RecordsConfig()
    /// Carries the rider's declared `defaultTurnType` into the wind estimator
    /// (docs/algorithms/wind.md "Default turn type").
    public var windConfig = WindConfig()
    /// Settings → Tuning: the published thresholds, moved by hand on this phone — **one set
    /// per discipline** (`TuningOverrideSets`). Empty on every install that has not touched
    /// the page, and an empty set applies nothing and stamps nothing, so an untuned library is
    /// byte-identical to one produced by a build without the feature. A session is analysed
    /// under its own discipline's set and no other.
    public var tuning = TuningOverrideSets()
    /// **Settings → "I mostly ride"**: the preset every imported session gets when its
    /// recording does not say (docs/presentation/labels.md, "Confirming the discipline on import").
    ///
    /// Wingfoil by default, and on a wingfoil rider's phone this property changes nothing at
    /// all — it is the value the resolver already fell back to. It exists for the windsurfer,
    /// whose every file arrives tagged as something else or as nothing: Garmin, Strava,
    /// intervals.icu and Apple Health have no wingfoil, and the one sport code they do agree
    /// on is the one ADR-004 made unusable as evidence.
    public var riderDiscipline: Discipline = .wingfoil
    /// **Settings → Analysis → "Windsurf (experimental)"**, off on a fresh install
    /// (docs/presentation.md, Settings). `true` here, because the kit is not the place the
    /// default lives: the app reads the stored flag and sets this, and a caller that has never
    /// heard of the switch keeps the behaviour this type had before it existed.
    ///
    /// With it off, an import does two things differently and nothing else: the rider's
    /// declared default is not consulted (there is no picker to declare it with, so a stale
    /// stored value must not outlive the switch), and the row is written down as **confirmed**
    /// rather than as a guess. Confirmed because on a wingfoil-only phone nothing was guessed
    /// — wingfoil is the only reading on offer — and because a rider who turns the switch on a
    /// year later should meet the feature, not a backlog of questions about afternoons he has
    /// already looked at. A recording that states its own discipline is still believed: that
    /// is the file talking, not a setting.
    public var windsurfEnabled = true
    public var dedupeToleranceS: TimeInterval = 60
    public var spotRadiusM: Double = SpotClusterer.defaultRadiusM

    public init(database: AppDatabase, archive: SessionArchive) {
        self.database = database
        self.archive = archive
    }

    public var library: LibraryStore { LibraryStore(database: database) }

    // MARK: - Ingest

    /// Ingests one recording — a FIT, or since engine 0.9.0 a GPX (`TrackParser` decides
    /// from the bytes). `requireWatersport` gates bulk imports (ZIP walking); a file the
    /// user picked by hand is always accepted, which is also the only way a GPX gets in:
    /// it carries no sport and no discipline, so nothing about it can pass a sport gate.
    ///
    /// `rider` is whose session this is — nil for the app owner's own, a friend's name for
    /// a FIT they shared. Only the hand-picked paths ever pass a name: an intervals.icu
    /// sync and a Garmin GDPR backfill are the rider's own account by construction, and a
    /// prompt on either would be asking a question that cannot have a second answer.
    ///
    /// `utcOffsetS` is what the *caller* knows about the session's timezone — intervals.icu
    /// states one per activity, and it is an exact answer where our own fallback is a
    /// guess. It is consulted only when the FIT itself cannot say (see
    /// `resolveUtcOffset`); a hand-picked file passes nil and simply has one fewer rung.
    @discardableResult
    public func ingest(fitData: Data, filename: String?, source: ImportSource,
                       icuActivityId: String? = nil,
                       rider: String? = nil,
                       utcOffsetS: Int? = nil,
                       requireWatersport: Bool = false) async throws -> IngestOutcome {
        // FIT or GPX, decided by the bytes (engine 0.9.0). Everything below this line is
        // written against `RawTrack` + `SourceCapabilities` and never asks which.
        let track = try TrackParser.parse(data: fitData)
        let caps = track.capabilities
        if requireWatersport, !Self.isWatersport(caps) {
            return .skipped(reason: caps.sport ?? "unknown sport")
        }
        guard let startDate = track.startDate, let first = track.samples.first,
              let last = track.samples.last else {
            throw FitSessionParser.ParseError.noRecords
        }
        let duration = last.t - first.t
        // **A session has to have lasted a plausible length of time.**
        //
        // Every number below this line is measured against `duration`, and several of them
        // size an array with it: the rolling-rate series is one point a minute, the HR
        // fatigue bins one per twenty. On a recording whose clock survived the trip those
        // are a few hundred entries. On one whose clock did not — a download cut off
        // mid-stream, a device that stamped a record in 1989 — `duration` comes back as
        // decades, and the same arithmetic asks for tens of millions of entries on a phone.
        // That is not a crash anybody can report: iOS takes the memory back by killing the
        // app, which leaves no crash log, so the rider sees the sync die on the twelfth of
        // his seventy-four files and can say nothing about it but "it crashed".
        //
        // So it is refused here, by name, and the sync puts it in `failed` beside the
        // activity id and carries on with the rest. A week is chosen to be obviously
        // outside any session and obviously inside any clock that works.
        guard duration.isFinite, duration >= 0, duration <= Self.maxSessionDurationS else {
            throw IngestError.implausibleDuration(durationS: duration)
        }

        let existing = try await duplicate(startDate: startDate, durationS: duration,
                                          fixSpanS: Self.fixSpan(of: track),
                                          icuActivityId: icuActivityId)
        if let existing, !existing.isProvisional,
           !Self.yields(existing, to: source, sourceClass: caps.sourceClass) {
            let merged = try await note(existing, source: source, icuActivityId: icuActivityId)
            return .duplicate(merged)
        }
        // F-6: the row this recording takes over is a positions-only copy, not a card or a
        // direct stream. Same takeover as theirs below; the outcome says so, because this
        // is the one takeover a rider can see happen to a session he has already looked at.
        let weaker = existing.flatMap {
            !$0.isProvisional && Self.isWeakerCopy($0, than: caps.sourceClass) ? $0 : nil
        }

        // A provisional row is the watch's card holding this session's place until the FIT
        // syncs (phase 5). This IS that FIT, so it takes over the SAME row — same id, real
        // analysis, flag cleared — instead of appearing beside it. Replacing rather than
        // inserting keeps the gear the rider already picked, keeps anything holding the id
        // valid, and means the library never shows one session twice.
        // **Which preset this session is read under**, decided once, here (docs/algorithms/disciplines.md
        // "Disciplines"). The recording's own `discipline` field if it has one — the CleanJibe
        // watch app's, authoritative, never asked about again. Else whatever the rider already
        // settled on a provisional row this FIT is taking over. Else his declared default,
        // which is a *guess* and says so in the column below. The sport code is not consulted
        // at any rung: it is not an argument to `Discipline.imported`.
        let stated = Discipline.stated(tag: caps.discipline)
        let settled = existing.flatMap {
            $0.disciplineGuessed ? nil : Discipline.stated(tag: $0.disciplineOverride)
        }
        let preset = settled ?? stated ?? (windsurfEnabled ? riderDiscipline : .wingfoil)
        let analysis = analyze(track, discipline: preset)
        let id = existing?.id ?? UUID().uuidString
        try archive.storeOriginal(fitData, id: id)
        do {
            try archive.writeAnalysis(analysis, id: id)
        } catch {
            // Analysis JSON is a cache — a write failure must not lose the session.
        }

        var row = SessionRow(id: id, startDate: startDate, durationS: duration,
                             sourceClass: caps.sourceClass)
        row.sport = caps.sport
        row.discipline = caps.discipline
        // The override column holds only what the *tag* does not already say, exactly as
        // `setDiscipline` writes it: a rider default that agrees with the recording is not an
        // override, it is an agreement, and storing it would make a later "he said so" and a
        // "nobody asked" indistinguishable.
        row.disciplineOverride = preset == Discipline.resolve(tag: caps.discipline)
            ? nil : preset.rawValue
        // Nobody is asked about a rig on a phone that only knows one (`windsurfEnabled`).
        row.disciplineGuessed = windsurfEnabled && settled == nil && stated == nil
        row.originalFilename = filename
        // What clock this session's times are drawn on, and how well we know it — see
        // `resolveUtcOffset`. It survives a provisional-row upgrade the same way the id
        // does: the FIT is a better source than anything the BLE card could imply, so it
        // overwrites rather than defers, and only an answer of "nothing" leaves the
        // existing value standing — the two fields together, so a kept offset never ends up
        // wearing this file's provenance.
        let resolved = Self.resolveUtcOffset(track: track, fallback: utcOffsetS)
        row.startUtcOffsetS = resolved.offset ?? existing?.startUtcOffsetS
        row.startUtcOffsetSource = resolved.offset == nil
            ? existing?.startUtcOffsetSource : resolved.source.rawValue
        // The card's "watch" tag survives the upgrade: the row really did reach the
        // library over BLE first, and that is worth being able to see afterwards.
        row.importSource = Self.merge(sources: existing?.importSource, adding: source)
        row.icuActivityId = icuActivityId ?? existing?.icuActivityId
        row.isExample = source == .example
        // A blank name means "mine": the prompt's text field can be left empty after the
        // rider has tapped "a friend's", and an empty string in the column would exclude
        // the session from every aggregate while showing an empty badge.
        row.rider = Self.riderName(rider) ?? existing?.rider
        // What the *rider* called it, and what he wanted said about it (schema v9). Carried
        // across the provisional-row upgrade for the same reason the gear and the id are:
        // the watch's card can sit in the library for an hour before the FIT syncs, that is
        // long enough to name the session, and a name that vanished when the recording
        // arrived would look exactly like the app losing it. Nothing here derives them —
        // they are the one pair of columns no import ever writes.
        row.customTitle = existing?.customTitle
        row.shareNote = existing?.shareNote
        if let fix = track.samples.first(where: { $0.lat != nil && $0.lon != nil }) {
            row.startLat = fix.lat
            row.startLon = fix.lon
        }
        row.apply(analysis)

        // A spot the row already has is kept: the rider may have moved the session to
        // another spot, and the recording that takes the row over was ridden at the same
        // beach. Assigning again would also count this session twice in the spot's centre.
        row.spotId = existing?.spotId
        let inserted = row
        row.spotId = try await database.writer.write { db -> String? in
            // `save`, not `insert`: on the provisional path the row already exists and
            // this call is the moment the card's numbers are overwritten by real ones.
            try inserted.save(db)
            try SessionDerivation.write(analysis, session: inserted, db: db)
            if let kept = inserted.spotId { return kept }
            guard let lat = inserted.startLat, let lon = inserted.startLon else { return nil }
            return try SpotClusterer.assign(sessionId: inserted.id, lat: lat, lon: lon, db: db,
                                            radiusM: spotRadiusM)
        }
        // Fresh sessions inherit the combo the rider last used (editable per session) —
        // except the example, which was not ridden on the rider's kit.
        if !row.isExample {
            _ = try? await library.applyDefaultGear(sessionId: row.id)
        }
        if let weaker { return .replaced(row, weaker: weaker) }
        return .imported(row)
    }

    /// The name as it goes in the column, or nil for "mine".
    ///
    /// Whitespace-trimmed and empty-to-nil, because the prompt's text field can be left
    /// blank after tapping "a friend's": an empty string would exclude the session from
    /// every aggregate while showing a badge with nothing in it — the worst of both.
    public static func riderName(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// **Does this row step aside for the recording that just arrived?** (ADR-013.)
    ///
    /// A provisional row does, and always has: the card held the session's place until its
    /// FIT synced. Since the direct transfer there is a second row of that kind — one whose
    /// only source is the watch's own `.cjr` stream (docs/transfer-format.md). That stream is
    /// a real recording with a real analysis behind it, so its row is **not** provisional and
    /// counts in every total from the moment it lands. It is still the thinner copy: the
    /// positions are quantised to half a micro-degree, there is no wrist stream, there are no
    /// laps and there is no local clock. So when the FIT of the same afternoon reaches the
    /// library through intervals.icu, a Garmin ZIP or a file, it takes over the same row —
    /// same id, gear, name and note kept, sources merged — exactly as a FIT takes over a
    /// card's.
    ///
    /// Only for a row the direct link brought in **alone**. Once a FIT has replaced it the
    /// column reads `"icu+watchdirect"` and a later copy of that FIT is an ordinary duplicate
    /// again. A second arrival of the same direct stream is one too: a stream does not step
    /// aside for itself.
    ///
    /// **A positions-only row steps aside too** (release round A, F-6, Jan 26 Sep 2026):
    /// a Strava or GPX copy — class (c), records uncertified — gives way to the recording
    /// with speed of the same afternoon when it arrives later, from intervals.icu, a Garmin
    /// ZIP or a file. And **never the other way**: a recording without speed never takes
    /// over a row that has it, whichever door it came through, the direct stream included.
    static func yields(_ existing: SessionRow, to source: ImportSource,
                       sourceClass: String) -> Bool {
        if sourceClass == "c", existing.sourceClass != "c" { return false }
        if isWeakerCopy(existing, than: sourceClass) { return true }
        guard source != .watchDirect else { return false }
        let sources = (existing.importSource ?? "").split(separator: "+")
        return sources == [Substring(ImportSource.watchDirect.rawValue)]
    }

    /// Is this row a positions-only copy of what a recording of `sourceClass` holds?
    /// Class (c) against (a) or (b): the source class is the one fact that says whether a
    /// recording measured its speed (docs/algorithms/imports.md, "One afternoon, one session").
    static func isWeakerCopy(_ existing: SessionRow, than sourceClass: String) -> Bool {
        existing.sourceClass == "c" && sourceClass != "c"
    }

    /// **The one line a rider is told** when a recording with speed replaced a weaker copy
    /// (F-6): *Replaced the Strava copy of 13 June with your watch's recording.* The copy is
    /// named by where it came from, Strava or a GPX file; the date is the session's own day.
    /// Several in one run are counted in one line. Nil when nothing was replaced.
    public static func replacedLine(_ weaker: [SessionRow]) -> String? {
        guard let first = weaker.first else { return nil }
        let copy = weaker.allSatisfy { ImportSource.strava.isNamed(in: $0.importSource) }
            ? "Strava" : "positions-only"
        guard weaker.count == 1 else {
            return "Replaced \(weaker.count) \(copy) copies with your watch's recordings"
        }
        let formatter = DateFormatter()
        formatter.timeZone = first.displayZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM"
        return "Replaced the \(copy) copy of \(formatter.string(from: first.startDate))"
            + " with your watch's recording"
    }

    /// **The span a recording is compared on besides its own** (release round A, F-5): from
    /// its first GPS fix to its last. A watch left running in the van records on without a
    /// position, and a copy made of its fixes (Strava's, a GPX) spans the fixes alone. Nil
    /// for a recording with no fix at all.
    static func fixSpan(of track: RawTrack) -> Double? {
        guard let first = track.samples.first(where: { $0.lat != nil && $0.lon != nil }),
              let last = track.samples.last(where: { $0.lat != nil && $0.lon != nil })
        else { return nil }
        return last.t - first.t
    }

    public static func isWatersport(_ caps: SourceCapabilities) -> Bool {
        if caps.discipline != nil || caps.hasDevFields { return true }
        guard let sport = caps.sport?.lowercased() else { return false }
        return watersportSports.contains(sport)
    }

    /// Bulk entry point: streams nested ZIPs/gzip and ingests every qualifying FIT, one
    /// member at a time. Writes an `import_log` row for the run and reports progress
    /// after every file so the UI can show "n found / imported / duplicates / skipped".
    @discardableResult
    public func ingestContainer(data: Data, name: String, source: ImportSource,
                                rider: String? = nil,
                                progress: (@Sendable (ImportSummary) -> Void)? = nil)
    async -> ImportSummary {
        var log = ImportLogRow(source: source, container: name)
        let opened = log
        try? await database.writer.write { db in try opened.insert(db) }

        // A hand-picked single FIT keeps its sport whatever it is; anything unpacked from
        // a real container is gated on sport, so a GDPR export of runs stays out.
        let gate: Bool
        if case .track = ZipWalker.classify(data) { gate = false } else { gate = true }
        let box = SummaryBox()
        let walk = await ZipWalker.walk(data: data, name: name) { fit in
            let short = (fit.name as NSString).lastPathComponent
            await box.begin(short)
            progress?(await box.snapshot)
            do {
                switch try await ingest(fitData: fit.data, filename: short, source: source,
                                        rider: rider, requireWatersport: gate) {
                case .imported: await box.count(\.imported)
                case .duplicate: await box.count(\.duplicates)
                case .skipped: await box.count(\.skipped)
                case .replaced(_, let weaker): await box.replace(weaker)
                }
            } catch {
                await box.fail("\(short): \(error)")
            }
            progress?(await box.snapshot)
        }

        var summary = await box.snapshot
        summary.found = walk.fitCount
        summary.current = nil
        if walk.unreadable > 0 { summary.failed.append("\(walk.unreadable) unreadable") }
        if walk.fitCount == 0 && summary.failed.isEmpty {
            summary.failed.append("\(name): no FIT found")
        }

        log.absorb(summary)
        log.finishedAt = Date()
        let finished = log
        try? await database.writer.write { db in try finished.update(db) }
        progress?(summary)
        return summary
    }

    /// Mutable tally shared with the streaming walker's sink.
    private actor SummaryBox {
        private var summary = ImportSummary()

        var snapshot: ImportSummary { summary }

        func begin(_ name: String) { summary.current = name }
        func count(_ key: WritableKeyPath<ImportSummary, Int>) { summary[keyPath: key] += 1 }
        func fail(_ message: String) { summary.failed.append(message) }
        func replace(_ weaker: SessionRow) { summary.replaced.append(weaker) }
    }

    // MARK: - Analysis access (lazy re-analysis)

    /// What a document produced *by this ingestor* is stamped with: the engine version, the
    /// discipline preset where it is not the default (`DisciplineStamp`), and the fingerprint
    /// of **that discipline's** tuning set where the rider has moved a threshold in it
    /// (`TuningStamp`). It is the staleness key everything below compares on, which is what
    /// makes both a moved slider and a switched discipline behave exactly like an engine bump
    /// — the library re-derives itself, lazily, on the next pass, through one mechanism rather
    /// than three. Because the fingerprint is the *set's* and not the whole page's, a fin
    /// slider moves the fin stamp alone and leaves every wingfoil session where it was.
    public func analysisVersion(for discipline: Discipline = .wingfoil) -> String {
        tuning.engineVersionKey(discipline: discipline)
    }

    /// The stamp of a plain wingfoil run — what a session with no discipline of its own gets.
    public var analysisVersion: String { analysisVersion(for: .wingfoil) }

    private func analyze(_ track: RawTrack,
                         discipline: Discipline = .wingfoil) -> SessionAnalysis {
        // The two layers compose inside `analyze`, in the one order that is defensible —
        // preset, then this discipline's own overrides on top — so the ingestor hands over
        // its own base configs and the set to read them against, and never applies either.
        var analysis = SessionSummarizer.analyze(track, filterConfig: filterConfig,
                                                 flightConfig: flightConfig,
                                                 recordsConfig: recordsConfig,
                                                 windConfig: windConfig,
                                                 discipline: discipline,
                                                 tuning: tuning[discipline])
        // The engine states its own version; the stamp is the *ingestor's* fact about how it
        // was run, so it is applied here rather than threaded through the analyzer. On an
        // untuned wingfoil install this assignment changes nothing.
        analysis.engineVersion = analysisVersion(for: discipline)
        return analysis
    }

    /// Cached `analysis.json`, recomputed from the archived FIT when missing or stale.
    ///
    /// "Stale" is now a **per-row** question: the expected stamp carries this session's own
    /// discipline, so switching one session to a windsurf preset re-derives that session and
    /// leaves every other one alone.
    public func analysis(for row: SessionRow) async throws -> SessionAnalysis {
        let expected = analysisVersion(for: row.analysisDiscipline)
        if let cached = archive.analysis(for: row.id, engineVersion: expected),
           row.engineVersion == cached.engineVersion {
            return cached
        }
        return try await reanalyze(row)
    }

    @discardableResult
    public func reanalyze(_ row: SessionRow) async throws -> SessionAnalysis {
        let track = try archive.rawTrack(for: row.id)
        let analysis = analyze(track, discipline: row.analysisDiscipline)
        try? archive.writeAnalysis(analysis, id: row.id)
        let fix = track.samples.first(where: { $0.lat != nil && $0.lon != nil })
        let spotRadiusM = self.spotRadiusM
        try await database.writer.write { db in
            // **The row as it is now, not as the caller last saw it** (release round A).
            // `reanalyzeStale()` and the rerun button hand over rows read before a sweep
            // that can take minutes; writing that snapshot back would undo a rename, a rider
            // or a caption made in the meantime. Only the derived columns move here.
            // A session deleted meanwhile stays deleted: nothing is written for it.
            guard var stored = try SessionRow.fetchOne(db, key: row.id) else { return }
            if stored.startLat == nil, let fix {
                stored.startLat = fix.lat
                stored.startLon = fix.lon
            }
            stored.apply(analysis)
            try stored.update(db)
            try SessionDerivation.write(analysis, session: stored, db: db)
            if stored.spotId == nil, let lat = stored.startLat, let lon = stored.startLon {
                try SpotClusterer.assign(sessionId: stored.id, lat: lat, lon: lon, db: db,
                                         radiusM: spotRadiusM)
            }
        }
        return analysis
    }

    /// **The direct transfer's second stream, landing after the session did.**
    ///
    /// The watch sends the recording first and the 25 Hz wrist magnitudes minutes later
    /// (docs/transfer-format.md §6, ADR-031). This files the wrist archive beside the
    /// original the session was built from and re-derives — no second ingest, no second
    /// analysis path, and nothing invented: `SessionArchive.rawTrack` attaches the sidecar,
    /// `SourceCapabilities.hasAccel` becomes true because `track.accel` is no longer empty,
    /// and `PumpAnalyzer` produces a `PumpTrack` where it produced nil.
    ///
    /// **The class letter does not move and is not meant to.** `sourceClass` is already `a`:
    /// the stream carries the four record developer fields. What moves is what the summary
    /// can say — pumps to takeoff, failed attempts, the pump rung of the touchdown ladder,
    /// the pump-versus-cruise heart-rate split — all of which read nil without a `PumpTrack`.
    ///
    /// Returns nil where the session is not a direct one, because a wrist stream has nothing
    /// to attach to a FIT: the FIT carries its own.
    @discardableResult
    public func attachWristStream(_ data: Data, to row: SessionRow) async throws
            -> SessionAnalysis? {
        guard let original = try? archive.originalData(for: row.id),
              DirectStream.isStream(original) else { return nil }
        // Refused rather than filed if it cannot be read: a sidecar nothing can decode would
        // be re-attached and re-refused at every re-analysis for ever.
        guard let decoded = try? DirectWristDecoder.decode(data), !decoded.1.isEmpty else {
            return nil
        }
        try archive.storeWrist(data, id: row.id)
        return try await reanalyze(row)
    }

    /// Re-derives every session whose stored engine version is not the current one
    /// (plan §3.3, lazy re-analysis on an engine bump). The aggregate screens call this
    /// before they read, because a stale row would silently skew a whole trend line.
    /// Returns the number of sessions rebuilt.
    ///
    /// "The current one" includes the tuning fingerprint (`analysisVersion`), so moving a
    /// slider in Settings → Tuning marks the whole library stale by exactly this rule and
    /// gets exactly this sweep — no second mechanism, and no way to end up with half a
    /// library on one set of thresholds and half on another.
    @discardableResult
    public func reanalyzeStale(progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> Int {
        let rows = try await database.writer.read { db in
            // Provisional rows are excluded because there is nothing to re-derive from:
            // a card carries no track, so re-analysis would fail on every pass for ever
            // and the app would announce "re-derived 1 session" at every single launch.
            try SessionRow.filter(sql: "isProvisional = 0")
                .order(Column("startDate")).fetchAll(db)
        }
        // The comparison moved out of SQL when the discipline did: the version a row *should*
        // carry depends on that row's own preset, and one `engineVersion <> ?` cannot ask a
        // different question per row. It is the same rule, asked in Swift.
        let stale = rows.filter {
            $0.engineVersion != analysisVersion(for: $0.analysisDiscipline)
        }
        guard !stale.isEmpty else { return 0 }
        for (index, row) in stale.enumerated() {
            progress?(index + 1, stale.count)
            _ = try? await reanalyze(row)
        }
        return stale.count
    }

    /// **Analyse this session as another discipline** (docs/algorithms/disciplines.md "Disciplines").
    ///
    /// Writes the rider's answer into `disciplineOverride` and re-derives that one session
    /// through the ordinary path — the new stamp is what makes the stored document stale, so
    /// there is no second invalidation rule to keep in step with the first. Passing the
    /// preset the recording already resolves to clears the override rather than storing it,
    /// the same way a tuning slider dragged back to its default clears rather than sets.
    @discardableResult
    public func setDiscipline(_ discipline: Discipline,
                              for row: SessionRow) async throws -> SessionAnalysis {
        var updated = row
        let fromTag = Discipline.resolve(tag: row.discipline)
        updated.disciplineOverride = discipline == fromTag ? nil : discipline.rawValue
        // He has answered, so the preset is no longer a guess — whichever way he answered.
        updated.disciplineGuessed = false
        let stored = updated
        try await database.writer.write { db in try stored.update(db) }
        return try await reanalyze(stored)
    }

    /// **The rider looked at the guess and let it stand.** The review step's "keep it": the
    /// preset does not move, so nothing is re-derived and no analysis is touched — the only
    /// thing that changes is that the app stops marking these sessions as unasked.
    ///
    /// Separate from `setDiscipline` rather than a no-op call into it, because the two are
    /// different facts and only this one is free. Re-deriving a session to record that its
    /// numbers were already right would be the slowest possible way of changing nothing.
    public func confirmDiscipline(for rows: [SessionRow]) async throws {
        let ids = rows.filter(\.disciplineGuessed).map(\.id)
        guard !ids.isEmpty else { return }
        let holes = ids.map { _ in "?" }.joined(separator: ", ")
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE session SET disciplineGuessed = 0 WHERE id IN (\(holes))",
                           arguments: StatementArguments(ids))
        }
    }

    public func rawTrack(for row: SessionRow) throws -> RawTrack {
        try archive.rawTrack(for: row.id)
    }

    /// `"file"` + `.icu` → `"file+icu"`. Sorted and de-duplicated, so a session that
    /// arrived four ways still reads as one stable string.
    static func merge(sources existing: String?, adding source: ImportSource) -> String {
        var sources = Set((existing ?? "").split(separator: "+").map(String.init))
        sources.remove("")
        sources.insert(source.rawValue)
        return sources.sorted().joined(separator: "+")
    }

    // MARK: - Queries

    public func allSessions() async throws -> [SessionRow] {
        try await database.writer.read { db in
            try SessionRow.order(Column("startDate").desc).fetchAll(db)
        }
    }

    public func session(id: String) async throws -> SessionRow? {
        try await database.writer.read { db in try SessionRow.fetchOne(db, key: id) }
    }

    /// Would a recording of this shape land on a session the library already holds?
    ///
    /// THE dedupe rule, asked *before* the bytes exist. The Apple Health import is the caller:
    /// its list can say "already imported" beside a workout without fetching and mapping the
    /// route first, which for a season of workouts is the difference between a list and a
    /// wait. It answers with the same `duplicate` the ingest path uses rather than with a
    /// second copy of the ±60 s rule, because two rules would eventually disagree and the
    /// screen would promise one thing while the import did another.
    ///
    /// It is a *preview*, not the decision: what a workout's route actually spans is a little
    /// shorter than what Health calls its duration, so a borderline answer here can differ
    /// from the one the ingest reaches. That is safe in the direction that matters — the
    /// ingest still dedupes — and the screen says "already imported" rather than promising it.
    public func holdsSession(startDate: Date, durationS: Double) async throws -> Bool {
        try await duplicate(startDate: startDate, durationS: durationS) != nil
    }

    public func icuActivityIds() async throws -> Set<String> {
        let ids = try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT icuActivityId FROM session WHERE icuActivityId IS NOT NULL")
        }
        return Set(ids)
    }

    /// Removes a session and remembers that it was removed.
    ///
    /// **The tombstone is the point** (`SessionTombstoneRow`). Without it the next
    /// intervals.icu sync sees an activity that is no longer in the library, concludes it is
    /// new, and downloads it again — which is deletion as a suggestion rather than as an
    /// instruction.
    ///
    /// **Everything gets one except the example**, and the exception is not laziness about
    /// provenance. The tombstone is *only ever consulted by the intervals.icu sync* (see
    /// `IcuSyncService.sync`), so it never stands between a rider and a file he picks by
    /// hand — and it therefore costs nothing on a session that only ever arrived by hand.
    /// What it does buy is the case that is otherwise silently broken: a session imported
    /// from a Garmin GDPR ZIP carries no intervals.icu id, but *is* on intervals.icu, so
    /// deleting it and syncing would import it straight back under an id the library has
    /// never seen. Tombstoning by the dedupe key as well as by the id is what catches that,
    /// and it can only catch it if the tombstone was written.
    ///
    /// The bundled example is left out because it is not the rider's session and cannot come
    /// back from intervals.icu anyway: it comes back from a button that says so
    /// (`importExample`), and counting it in "Previously deleted: 1" would be offering to
    /// restore something no sync was ever going to restore.
    ///
    /// `title` is what the library row was called — the archive directory goes with the row,
    /// so a name that is not written down now cannot be recovered later.
    public func delete(_ row: SessionRow, title: String? = nil) async throws {
        let id = row.id
        let stone = row.isExample ? nil : SessionTombstoneRow(row, title: title)
        _ = try await database.writer.write { db -> Void in
            try SessionRow.deleteOne(db, key: id)
            try stone?.insert(db)
            // `session.spotId` carries no foreign key, so the last session leaving a place
            // would otherwise leave the place behind: "Spot 2 · 0 · Never sailed", a phantom
            // of a session the rider deleted on purpose. Same write, so the two facts are
            // never apart (docs/presentation/not-a-session-spots.md, "Spots").
            try SpotClusterer.pruneEmptySpots(db: db)
        }
        archive.delete(id: id)
    }

    /// Drops every cached analysis; the next open recomputes and rewrites the summary row.
    public func dropAllAnalyses() {
        archive.dropAllAnalyses()
    }

    // MARK: - Internals

    /// THE dedupe rule: start within ±60 s **and** duration within ±60 s (plan §3.3).
    ///
    /// Internal rather than private because the watch's BLE card goes through this exact
    /// call (`ingest(card:)`). A card and its FIT describe the same minutes of the same
    /// afternoon, so if the two ever used different rules the rider would see the session
    /// twice — and neither side can tell a duplicate from two back-to-back sessions.
    /// Which clock this session's times are drawn on, best source first:
    ///
    /// 1. **The FIT's own `activity` message** — `local_timestamp - timestamp`, the offset
    ///    the watch was wearing at save time. Exact, DST included, present on every file in
    ///    the corpus.
    /// 2. **What the caller was told** — intervals.icu's `timezone` for the activity,
    ///    resolved at the session's own instant. Also exact; second only because it is
    ///    about the athlete's account rather than about this recording.
    /// 3. **A coarse guess from the first GPS fix** — `round(lon / 15°)` hours. Solar, not
    ///    civil: an hour out under DST, up to two inside a wide zone, blind to the
    ///    half-hour zones. It is here for sources that carry position and nothing else,
    ///    where "within an hour or two" beats an Italian afternoon shown as a Californian
    ///    morning.
    /// 4. **Nothing.** nil is stored, and `SessionRow.displayZone` falls back to the
    ///    device's zone — flagged by `hasKnownZone`, so a surface can say so rather than
    ///    passing the guess off as the session's.
    ///
    /// Since engine 0.9.1 it returns **which rung answered** alongside the number, because
    /// rungs 1–2 and rung 3 are the same `Int` and different facts: only an exact answer
    /// licenses a surface to state the session's clock, and rung 3's guess is an hour out
    /// under DST. "Nothing" is `.device` rather than a silence — a stored row can then tell
    /// a session that asked and got nowhere from one written before the question existed.
    static func resolveUtcOffset(track: RawTrack,
                                 fallback: Int?) -> (offset: Int?, source: UtcOffsetSource) {
        if let exact = track.startUtcOffsetS {
            return (exact, track.startUtcOffsetSource ?? .activity)
        }
        if let fallback { return (fallback, .icu) }
        guard let lon = track.samples.first(where: { $0.lon != nil })?.lon,
              let guess = FitSessionParser.coarseUtcOffsetS(lon) else { return (nil, .device) }
        return (guess, .longitude)
    }

    ///
    /// **Two spans a side** (release round A, F-5, Jan 26 Sep 2026). A recording is compared
    /// on its record span and on its fix span (`fixSpan`), and two recordings are the same
    /// session when any span of one is within the tolerance of any span of the other. That
    /// is what lets a FIT whose watch recorded on without GPS meet the Strava copy of its
    /// fixes, in either order. The start stays one-to-one. A stored row carries its record
    /// span only, so its fix span is read from the archived original, and only for a row
    /// whose start already matched and whose record span did not.
    func duplicate(startDate: Date, durationS: Double, fixSpanS: Double? = nil,
                   icuActivityId: String? = nil) async throws -> SessionRow? {
        let tolerance = dedupeToleranceS
        let lower = startDate.addingTimeInterval(-tolerance)
        let upper = startDate.addingTimeInterval(tolerance)
        let incoming = [durationS] + (fixSpanS.map { [$0] } ?? [])
        let (hit, rest) = try await database.writer.read { db -> (SessionRow?, [SessionRow]) in
            if let icuActivityId,
               let hit = try SessionRow
                .filter(Column("icuActivityId") == icuActivityId).fetchOne(db) {
                return (hit, [])
            }
            let candidates = try SessionRow
                .filter(Column("startDate") >= lower && Column("startDate") <= upper)
                .fetchAll(db)
            // The record span first, so the ordinary case answers exactly as it always did.
            if let hit = candidates.first(where: { abs($0.durationS - durationS) <= tolerance }) {
                return (hit, [])
            }
            if let hit = candidates.first(where: { row in
                incoming.contains { abs(row.durationS - $0) <= tolerance }
            }) {
                return (hit, [])
            }
            return (nil, candidates.filter { !$0.isProvisional })
        }
        if let hit { return hit }
        // The stored side's fix span, from its archive. A card has no archive and is skipped.
        for row in rest {
            guard let track = try? archive.rawTrack(for: row.id),
                  let stored = Self.fixSpan(of: track) else { continue }
            if incoming.contains(where: { abs(stored - $0) <= tolerance }) { return row }
        }
        return nil
    }

    /// **The session a direct transfer's second stream belongs to.**
    ///
    /// Start within `dedupeToleranceS` and nothing else, because a wrist stream carries no
    /// duration to match a session on — its header states the start epoch the record
    /// stream's does, which is the card's `KEY_START` and half of ADR-013's key. The nearest
    /// row wins where two sessions somehow sit inside one minute of each other.
    public func session(nearStart start: Date) async throws -> SessionRow? {
        let tolerance = dedupeToleranceS
        let lower = start.addingTimeInterval(-tolerance)
        let upper = start.addingTimeInterval(tolerance)
        return try await database.writer.read { db in
            try SessionRow
                .filter(Column("startDate") >= lower && Column("startDate") <= upper)
                .fetchAll(db)
                .min { abs($0.startDate.timeIntervalSince(start))
                     < abs($1.startDate.timeIntervalSince(start)) }
        }
    }

    /// Records that an existing session was seen again from another source.
    ///
    /// The example session is a *real* recording, so a rider who owns it will eventually
    /// import it for real and land on the ±60 s dedupe key. When that happens the real
    /// import wins: the row stops being an example and rejoins Records and Trends. The
    /// reverse never happens — loading the example over an already-real row leaves the
    /// flag off, so nobody's own session is demoted by tapping a button.
    func note(_ row: SessionRow, source: ImportSource,
              icuActivityId: String?) async throws -> SessionRow {
        var updated = row
        updated.importSource = Self.merge(sources: row.importSource, adding: source)
        if updated.icuActivityId == nil { updated.icuActivityId = icuActivityId }
        if source != .example { updated.isExample = false }
        guard updated.importSource != row.importSource
                || updated.icuActivityId != row.icuActivityId
                || updated.isExample != row.isExample
        else { return row }
        let stored = updated
        try await database.writer.write { db in try stored.update(db) }
        return updated
    }
}
