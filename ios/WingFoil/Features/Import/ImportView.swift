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
                        Label("FIT, GPX or ZIP…", systemImage: "doc.badge.plus")
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
                    // The picker offers GPX (engine 0.9.0), so the next question is what it
                    // costs — answered here, before the rider imports one and wonders why
                    // the pump section is missing, rather than after.
                    Text("Garmin Connect → activity → \"Export Original\" gives one FIT; "
                         + "AirDrop and the share sheet land here too. GPX works as well, "
                         + "with two limits: it carries no speed channel, so its speed "
                         + "records are estimated from positions and marked uncertified, "
                         + "and it carries no accelerometer, so there is no pump or takeoff "
                         + "effort.")
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
            .fileImporter(isPresented: $showBulkImporter,
                          allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result {
                    Task { await store.importBulk(urls: urls) }
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.fitActivity, .gpxTrack, .zip, .gzip],
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
