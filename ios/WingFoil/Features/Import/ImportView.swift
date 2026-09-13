import SwiftUI
import UniformTypeIdentifiers
import WingFoilKit

/// Everything that gets sessions into the library, with the full-history backfill
/// (Garmin's GDPR "Export Your Data" ZIP) as the headline. The same dedupe key that
/// protects the intervals.icu sync protects the backfill, so a re-run is a no-op — the
/// phase-4 acceptance criterion, visible on screen as "n duplicates".
struct ImportView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showBulkImporter = false
    @State private var showFileImporter = false
    @State private var showHealthImporter = false
    @State private var showStravaImporter = false
    @State private var log: [ImportLogRow] = []

    var body: some View {
        NavigationStack {
            List {
                if let progress = store.importProgress {
                    Section("Importing") { ProgressCard(progress: progress) }
                }

                Section {
                    Button {
                        showBulkImporter = true
                    } label: {
                        Label("Garmin export ZIP…", systemImage: "shippingbox")
                    }
                    .disabled(store.isBusy)
                } header: {
                    Text("Full history")
                } footer: {
                    Text("Garmin Connect → Account → Export Your Data. The mail arrives with "
                         + "a ZIP of ZIPs holding every original FIT you ever uploaded. Pick it "
                         + "here: non-watersport activities are skipped and anything already in "
                         + "the library is recognised as a duplicate, so re-running is safe.")
                }

                Section {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("FIT, GPX, TCX or ZIP…", systemImage: "doc.badge.plus")
                    }
                    .disabled(store.isBusy)
                    Button {
                        Task { await store.syncFromIntervals() }
                    } label: {
                        Label("Sync intervals.icu", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.isBusy || store.apiKey.isEmpty)
                } header: {
                    Text("Single sessions")
                } footer: {
                    // The picker offers GPX (engine 0.9.0) and TCX, so the next question is
                    // what they cost — answered here, before the rider imports one and
                    // wonders why the pump section is missing, rather than after. The
                    // intervals.icu sentence names the other watch brands because the sync
                    // button above is the only way most of their riders get in at all: their
                    // apps sync to intervals.icu, and CleanJibe syncs from there.
                    Text("Garmin Connect → activity → \"Export Original\" gives one FIT; "
                         + "AirDrop and the share sheet land here too. Polar, Suunto and "
                         + "Coros are supported through intervals.icu — their apps sync "
                         + "there, and CleanJibe syncs from there. A FIT gives the full "
                         + "analysis; a GPX, or a TCX without a speed channel, gives a "
                         + "positions-only analysis with speed records estimated from "
                         + "positions and marked uncertified. None of the three carries an "
                         + "accelerometer, so there is no pump or takeoff effort.")
                }

                // The third door, and the only one that needs no account, no cable and no
                // file: a workout the rider already recorded with Apple's own Workout app
                // (ADR-017). It sits under "Single sessions" rather than beside the GDPR ZIP
                // because that is what it is — one afternoon at a time, picked by hand.
                if store.isHealthAvailable {
                    Section {
                        Button {
                            showHealthImporter = true
                        } label: {
                            Label("Import from Health…", systemImage: "heart.text.square")
                        }
                        .disabled(store.isBusy)
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text("Record with Apple's Workout app on an Apple Watch — Surfing, "
                             + "Water Sports or Sailing — and the GPS track and heart rate "
                             + "land in Health. CleanJibe reads the workouts you pick and "
                             + "analyses them on this phone: speed comes off the watch's own "
                             + "GPS, so the speed records are certified. There is no "
                             + "accelerometer in a Health workout, so pump strokes and "
                             + "takeoff effort are missing — the same limit a Garmin "
                             + "recording has.")
                    }
                }

                // The second cloud source (ADR-023), under intervals.icu rather than beside
                // it — deliberately in that order, because for the same afternoon
                // intervals.icu hands over the original file from the watch and Strava hands
                // over positions. The footer says so, so a rider with both accounts does not
                // have to find out by importing the worse copy.
                Section {
                    Button {
                        showStravaImporter = true
                    } label: {
                        // "Import from Strava…" under a "Strava" header, exactly as the
                        // Health row reads under "Apple Health": the header names the
                        // service, the row names the action, and neither repeats the other.
                        Label("Import from Strava…", systemImage: "figure.wave")
                    }
                    .disabled(store.isBusy)
                    if store.isStravaConnected, let athlete = store.stravaAthlete {
                        LabeledContent("Connected as", value: athlete)
                    }
                } header: {
                    Text("Strava")
                } footer: {
                    Text("Connect your Strava account and import the sessions you pick — "
                         + "Windsurf, Kitesurf, Surf and Workout by default, and anything "
                         + "whose name says wing or foil. Strava hands over positions, a "
                         + "clock, elevation and heart rate, so the analysis is complete "
                         + "except for two things: speed is worked out from the positions, "
                         + "so those records are marked uncertified, and nothing records "
                         + "your wrist, so there are no pump strokes. If the same session is "
                         + "on intervals.icu, take it from there instead.")
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
            .sheet(isPresented: $showHealthImporter) { HealthImportView() }
            .sheet(isPresented: $showStravaImporter) { StravaImportView() }
            .fileImporter(isPresented: $showBulkImporter,
                          allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result {
                    Task { await store.importBulk(urls: urls) }
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.fitActivity, .gpxTrack, .tcxTrack,
                                                .zip, .gzip],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await store.importPicked(urls: urls) }
                }
            }
        }
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
                Text(entry.container ?? entry.source).font(.subheadline).lineLimit(1)
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
        var parts = ["\(entry.found) found", "\(entry.imported) imported"]
        if entry.duplicates > 0 {
            parts.append("\(entry.duplicates) duplicate\(entry.duplicates == 1 ? "" : "s")")
        }
        if entry.skipped > 0 { parts.append("\(entry.skipped) skipped") }
        if entry.failed > 0 { parts.append("\(entry.failed) failed") }
        return parts.joined(separator: " · ")
    }
}
