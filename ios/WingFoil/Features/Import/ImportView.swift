import SwiftUI
import UniformTypeIdentifiers
import WingFoilKit

/// Everything that gets sessions into the library, **in the one order every surface prints
/// the ways in** (docs/review-checklist.md, pattern J).
///
/// The order is `docs/guide/getting-started.json`, through `ImportDoor.ordered(channel:)`:
/// Garmin through intervals.icu, the CleanJibe Apple Watch app, Apple's own Workout app, any
/// file, Strava — and the Garmin export ZIP last, under *Full history*, because it is a
/// backfill rather than a way to record an afternoon. It used to open this screen, which put
/// a rider's whole archive in front of him before the door he actually came for.
///
/// **Import does, Settings configures** (Jan, build 63). Every row here is an action — pick a
/// file, sync, list what a connected account holds — and nothing on it asks for a key,
/// connects an account or reports who you are connected as.
///
/// **Every door this channel has is drawn** (pattern E/G). A source that is not set up yet
/// keeps its row and changes its label: *Set up in Settings → Strava* where the action would
/// be. A build with no Strava keys, or an iPhone with no Health, says so on one line instead
/// of dropping the section — a rider looking for Strava must find out where it went, not
/// wonder whether he imagined it.
///
/// **A footer says what you get, in one line** (pattern K). The *how* is the help topic each
/// door names, opened from the footer itself (pattern B) rather than retyped into it. The
/// mechanism prose that used to fill these footers is in those topics.
struct ImportView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Handed down by the library, which owns the one sheet both screens are (`LibrarySheet`),
    /// so "set it up" replaces Import with Settings rather than stacking a second sheet on it.
    @Environment(\.openIcuSettings) private var openSettings

    @State private var showFileImporter = false
    @State private var showStravaImporter = false
    #if BETA
    /// The Garmin export ZIP and the Apple Health picker are both beta doors
    /// (docs/channels.md), and so is the state that raises them.
    @State private var showBulkImporter = false
    @State private var showHealthImporter = false
    #endif
    @State private var helpTopic: HelpTopicID?
    @State private var log: [ImportLogRow] = []

    /// The doors this build has, in the guide's order. Nothing on this screen decides the
    /// order or the channel: both are the kit's, and `ImportDoorsTests` holds them against
    /// `GettingStartedGuide.routes`.
    private static let doors = ImportDoor.ordered(channel: AppChannel.channel)

    var body: some View {
        NavigationStack {
            List {
                if let progress = store.importProgress {
                    Section("Importing") { ProgressCard(progress: progress) }
                }

                ForEach(Self.doors) { door in
                    Section {
                        row(for: door)
                    } header: {
                        header(for: door)
                    } footer: {
                        footer(for: door)
                    }
                }

                if !log.isEmpty {
                    Section("Recent imports") {
                        ForEach(log) { entry in ImportLogRowView(entry: entry) }
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: store.libraryGeneration) {
                log = (try? await store.library.importLog()) ?? []
            }
            .sheet(item: $helpTopic) { HelpTopicSheet(id: $0) }
            .sheet(isPresented: $showStravaImporter) { StravaImportView() }
            #if BETA
            .sheet(isPresented: $showHealthImporter) { HealthImportView() }
            .fileImporter(isPresented: $showBulkImporter,
                          allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result {
                    Task { await store.importBulk(urls: urls) }
                }
            }
            #endif
            // The types the picker offers, which is also what this channel's Info.plist
            // declares it can open: FIT and zip, with GPX and TCX added by the beta
            // (docs/channels.md). A picker offering a type the binary has no parser path
            // for would be a door onto an error message.
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: Self.importableTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await store.importPicked(urls: urls) }
                }
            }
        }
    }

    // MARK: - One door, one section

    /// The action, or — where the door needs an account this phone has not given yet — the
    /// one line that earns it. Never a disabled button with nothing said about why
    /// (pattern G).
    @ViewBuilder
    private func row(for door: ImportDoor) -> some View {
        switch door {
        case .icu:
            if store.apiKey.isEmpty {
                SetUpInSettingsRow(door: door, open: openSettings)
            } else {
                action(door) { Task { await store.syncFromIntervals() } }
            }
        case .appleWatchApp:
            // Nothing to import: the session crosses on its own. The row is the way to the
            // page that says how, which is the only thing this door has to offer.
            helpRow(door)
        case .appleHealth:
            #if BETA
            if store.isHealthAvailable {
                action(door) { showHealthImporter = true }
            } else {
                unavailable(ImportDoor.unavailableOnDevice)
            }
            #else
            unavailable(ImportDoor.unavailableOnDevice)
            #endif
        case .file:
            action(door) { showFileImporter = true }
        case .strava:
            if !store.isStravaConfigured {
                // Nothing to set up and nothing to import: this binary carries no Strava
                // keys. The same sentence Settings gives, so the two screens do not send
                // the rider back and forth over it.
                unavailable(ImportDoor.unavailableInBuild)
            } else if store.isStravaConnected {
                action(door) { showStravaImporter = true }
            } else {
                // Connecting is Strava's own consent screen and a decision about an
                // account — Settings' business, and the one place *Connect with Strava*
                // lives.
                SetUpInSettingsRow(door: door, open: openSettings)
            }
        case .garminZip:
            #if BETA
            action(door) { showBulkImporter = true }
            #else
            unavailable(ImportDoor.unavailableInBuild)
            #endif
        }
    }

    @ViewBuilder
    private func action(_ door: ImportDoor, run: @escaping () -> Void) -> some View {
        if let title = door.actionTitle(channel: AppChannel.channel) {
            Button(action: run) { Label(title, systemImage: door.symbolName) }
                .disabled(store.isBusy)
        }
    }

    private func unavailable(_ line: String) -> some View {
        Text(line).foregroundStyle(.secondary)
    }

    /// The way to the topic that answers *how*, by that topic's own title so the row says
    /// where it goes.
    private func helpRow(_ door: ImportDoor) -> some View {
        Button { helpTopic = door.helpTopic } label: {
            Label(HelpCatalog.topic(door.helpTopic, channel: AppChannel.channel).title,
                  systemImage: "questionmark.circle")
        }
    }

    /// The service, or the kind of thing. Strava's section carries Strava's mark: rule 2 of
    /// their brand guidelines asks for attribution wherever Strava data is shown, and a
    /// section header is exactly the level at which "this part of the screen is Strava's" is
    /// true — beside the section's own name, never above CleanJibe's own mark.
    @ViewBuilder
    private func header(for door: ImportDoor) -> some View {
        if door == .strava {
            HStack {
                Text(door.sectionTitle)
                Spacer(minLength: 12)
                StravaCompatibleMark()
            }
        } else {
            Text(door.sectionTitle)
        }
    }

    /// The recording class as a label, one line on what the door brings in, and the way to
    /// the page that says how (patterns H, K and B in that order).
    @ViewBuilder
    private func footer(for door: ImportDoor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(door.classLabel(channel: AppChannel.channel))
                .font(.caption.weight(.semibold))
            Text(door.footer(channel: AppChannel.channel))
                .fixedSize(horizontal: false, vertical: true)
            // Not under the door whose own row is already that link.
            if door.actionTitle(channel: AppChannel.channel) != nil {
                Button { helpTopic = door.helpTopic } label: {
                    Text(HelpCatalog.topic(door.helpTopic,
                                           channel: AppChannel.channel).title)
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - What this channel can read

    /// FIT and zip everywhere; GPX and TCX in the beta (docs/channels.md). The label, the
    /// footer and the type list sit together so a channel can never offer a door in its
    /// button and close it in its picker. The label and the footer are
    /// `ImportDoor.file`'s; this is the list the picker itself is given.
    ///
    /// Not private: the empty library's "Import a file" row raises the same picker from the
    /// Sessions screen (`LibraryView.waysInCard`), and two lists of openable types is one
    /// list that goes stale.
    #if BETA
    static let importableTypes: [UTType] =
        [.fitActivity, .gpxTrack, .tcxTrack, .zip, .gzip]
    /// The picker offers GPX (engine 0.9.0) and TCX, so the next question is what they cost
    /// — answered here, before the rider imports one and wonders why the pump section is
    /// missing, rather than after. The intervals.icu sentence names the other watch brands
    /// because the sync button above is the only way most of their riders get in at all:
    /// their apps sync to intervals.icu, and CleanJibe syncs from there.
    private static let filePickerFooter =
        "Garmin Connect → activity → \"Export File\" gives one FIT. "
        // **COROS, in capitals**, the way docs/channels.md and the release branch of this
        // same footer already spell it. One brand, two spellings, in two branches of one
        // file (15 Sep 2026).
        + "AirDrop and the share sheet land here too.\n\n"
        + "Polar, Suunto and COROS are supported through intervals.icu. "
        + "Their apps sync there, and CleanJibe syncs from there.\n\n"
        + "A FIT gives the full analysis. A GPX, or a TCX without a speed "
        + "channel, gives a positions-only analysis.\n\n"
        + "Its speed records are estimated from positions and marked "
        + "uncertified.\n\n"
        + "None of the three carries an accelerometer. Pump strokes and "
        + "takeoff effort are missing."
    #else
    static let importableTypes: [UTType] = [.fitActivity, .zip, .gzip]
    /// No GPX or TCX sentence, because there is no GPX or TCX door — and no mention of the
    /// beta either: this screen is the App Store app, and an answer that names a build the
    /// reader does not have is not an answer. So the last line says which doors *this* app
    /// has for a Polar, a Suunto or a COROS, and both of them work today.
    private static let filePickerFooter =
        "Garmin Connect → activity → \"Export File\" gives one FIT. "
        + "AirDrop and the share sheet land here too.\n\n"
        + "Polar, Suunto and COROS sessions come in through Strava, or through "
        + "intervals.icu. Their apps sync there, and CleanJibe syncs from there."
    #endif
}

/// **One line where an action would be, for a source that is not set up yet.**
///
/// It replaces the row rather than sitting under it: a disabled button *and* an
/// explanation is two rows saying one thing, and the thing they say is "not here". The
/// arrow is the app's own path notation (`Settings → intervals.icu`), the same way the
/// help topics and the getting-started guide write a route, so a rider who has read either
/// recognises where he is being sent — and the tap takes him there, so he does not have to
/// walk it. The door itself never disappears: only this label tells him it is not armed.
private struct SetUpInSettingsRow: View {
    let door: ImportDoor
    let open: (@MainActor () -> Void)?

    var body: some View {
        if let open {
            Button { open() } label: { label }
        } else {
            label.foregroundStyle(.secondary)
        }
    }

    private var label: some View {
        Label(door.setUpTitle ?? "", systemImage: "gearshape")
    }
}

/// The class line each **section** of the Import screen opens with (docs/channels.md, "the
/// three recording classes"; item 12 of the 14 Sep 2026 review).
///
/// **Before the import, not after it.** Every footer on this screen already answered *what
/// does this door bring in and what does it cost* — in prose, in its own words, one door at a
/// time. What none of them did was let a rider match the door in front of him to the row he
/// read on cleanjibe.org. The class name does that in four words, so it goes first and the
/// prose that was already there follows it.
private enum ImportClass {

    /// The Garmin GDPR ZIP holds whatever the watch originally wrote, so it is both of the
    /// Garmin classes at once and the honest footer says so rather than picking one.
    static let fullHistory =
        RecordingClass.a.name + ", or " + RecordingClass.b.name
        + ": whichever each recording originally was.\n\n"
        + "The ZIP holds the untouched files. A session is worth what it was worth on "
        + "the day it was ridden."

    /// Apple's own Workout app is class B: its speed came off the watch's GPS receiver and
    /// certifies, and nothing recorded the wrist. The B+ sentence is here because this is the
    /// screen where an Apple Watch owner is thinking about Apple Watches, and the door that
    /// gets him the missing half is the one door on this screen that is not on this screen.
    static let appleHealth =
        RecordingClass.b.footerLine + "\n"
        + RecordingClass.bPlus.name
        + " is the other way. Record with the CleanJibe watch app instead. The session "
        + "arrives on its own, with the wrist in it. No import needed."

    static let strava = RecordingClass.c.footerLine

    // MARK: - The prose under each class line
    //
    // Hoisted out of the `Text(…)` calls in the list, and not for tidiness: a section footer
    // built inline from a class line plus nine concatenated literals is an expression the
    // Swift type-checker gives up on ("unable to type-check this expression in reasonable
    // time"), because every `+` is an overload it has to resolve inside a result builder.
    // Named constants type-check once, in one place, and the list reads as a list.

    static let fullHistoryDoor =
        "Garmin Connect → Account → Export Your Data.\n\n"
        + "The mail arrives with a ZIP of ZIPs holding every original FIT you ever "
        + "uploaded.\n\n"
        + "Pick it here. Non-watersport activities are skipped and anything already in "
        + "the library is recognised as a duplicate, so re-running is safe."

    static let healthDoor =
        "Record with Apple's Workout app on an Apple Watch. Pick Surfing, Water Sports "
        + "or Sailing.\n\n"
        + "The GPS track and heart rate land in Health. CleanJibe reads the workouts you "
        + "pick and analyses them on this phone.\n\n"
        + "Speed comes off the watch's own GPS, so the speed records are certified.\n\n"
        + "A Health workout has no accelerometer, so pump strokes and takeoff effort are "
        + "missing."

    // Only the opening clause changed (15 September 2026): the footer began "Connect your
    // Strava account and…", and connecting is Settings' job now. What the
    // door *brings in* — the class line, the four activity types, the two costs, the
    // intervals.icu preference — is untouched.
    static let stravaDoor =
        "Imports the sessions you pick from your Strava account.\n\n"
        + "Windsurf, Kitesurf, Surf and Workout come by default, and anything whose name "
        + "says wing or foil.\n\n"
        + "Strava hands over positions, a clock, elevation and heart rate. Two things "
        + "are missing from the analysis.\n\n"
        + "Speed is worked out from the positions, so those records are marked "
        + "uncertified. Nothing records your wrist, so there are no pump strokes.\n\n"
        + "If the same session is on intervals.icu, take it from there instead."
}

/// Live counters while a container is being unpacked: found / imported / duplicates /
/// skipped, plus the file currently being parsed.
private struct ProgressCard: View {
    let progress: ImportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView().controlSize(.small)
                Text(progress.current ?? "Unpacking…")
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 0) {
                counter("\(progress.processed)", "found", .primary)
                counter("\(progress.imported)", "imported", .green)
                counter("\(progress.duplicates)", "duplicates", .secondary)
                counter("\(progress.skipped)", "skipped", .secondary)
                counter("\(progress.failed.count)", "failed",
                        progress.failed.isEmpty ? .secondary : .orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func counter(_ value: String, _ label: String, _ tone: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(tone)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ImportLogRowView: View {
    let entry: ImportLogRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.container ?? entry.source)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                // `.current` deliberately: an import is something that happened to this phone.
                Text(Fmt.shortDate(entry.startedAt, zone: .current))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let detail = entry.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
    }

    private var summary: String {
        var parts = [String(entry.found) + " found", String(entry.imported) + " imported"]
        if entry.duplicates > 0 {
            let noun = entry.duplicates == 1 ? " duplicate" : " duplicates"
            parts.append(String(entry.duplicates) + noun)
        }
        if entry.skipped > 0 { parts.append(String(entry.skipped) + " skipped") }
        if entry.failed > 0 { parts.append(String(entry.failed) + " failed") }
        return parts.joined(separator: " · ")
    }
}
