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
        HelpTopicLink(door.helpTopic, style: .row) { helpTopic = door.helpTopic }
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
                HelpTopicLink(door.helpTopic) { helpTopic = door.helpTopic }
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
    #else
    static let importableTypes: [UTType] = [.fitActivity, .zip, .gzip]
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
