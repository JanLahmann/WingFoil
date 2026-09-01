import SwiftUI
import UniformTypeIdentifiers
import WingFoilKit

/// One file out, one file in — the Settings section that exists because of the one thing a
/// fresh install cannot get back (`LibraryBackup`).
///
/// The footer answers the question a rider arrives with, which is *do I need this at all*.
/// The honest answer for most of them is no: setting up a new iPhone from the old one
/// carries the library across on its own, and so does an iCloud device backup. This section
/// is for the case neither covers — a phone set up as new, an app deleted and reinstalled —
/// and for keeping an archive somewhere that is not a phone.
///
/// Both directions are shown with their own state rather than as a spinner over the whole
/// screen: a backup of a season with accelerometer streams is minutes of work, and a rider
/// watching a count go up is a rider who knows the app has not hung.
struct LibraryBackupSection: View {
    @Environment(SessionStore.self) private var store

    @State private var showRestorePicker = false
    @State private var helpTopic: HelpTopicID?

    var body: some View {
        Section {
            sizeRow
            backupRow
            restoreRow
            Button { helpTopic = .libraryBackup } label: {
                Label("What a backup covers", systemImage: "questionmark.circle")
            }
            // On the row rather than on the Section: two `.sheet(item:)` on one view is
            // the classic way to end up with only one of them ever presenting.
            .sheet(item: $helpTopic) { HelpTopicSheet(id: $0) }
        } header: {
            Text("Library backup")
        } footer: {
            Text("Setting up a new iPhone from this one carries your library across by "
                 + "itself, and so does an iCloud backup — this is for the case neither "
                 + "covers: a phone set up as new, or the app deleted and installed again. "
                 + "The file holds every recording you have imported **and** the things "
                 + "nothing else can bring back — what you called each session, its caption, "
                 + "whose it was, the gear on it, your spot names, and the sessions you "
                 + "deleted on purpose.\n\n"
                 + "Restoring only ever adds. Sessions already in your library keep their "
                 + "own analysis, details you have changed since are left alone, and "
                 + "restoring the same file twice does nothing the second time.")
        }
        .task { await store.refreshBackupEstimate() }
        .sheet(item: Binding(get: { store.restoreOffer },
                             set: { store.restoreOffer = $0 })) { offer in
            RestoreConfirmation(offer: offer)
        }
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.zip],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result {
                Task { await store.offerRestore(urls: urls) }
            }
        }
    }

    // MARK: - Backing up

    /// The size, before the work rather than after it. A backup that turns out to be 3 GB
    /// on a phone with 4 GB free is a failure the rider should have been able to see coming.
    @ViewBuilder
    private var sizeRow: some View {
        if let estimate = store.backupEstimate, estimate.sessionCount > 0 {
            LabeledContent("Backup size") {
                Text("about \(Fmt.bytes(estimate.totalBytes))")
                    .foregroundStyle(estimate.isLarge ? .orange : .secondary)
            }
            if let warning = estimate.warning {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var backupRow: some View {
        if let progress = store.backupProgress {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(progress.total > 0
                         ? "Packing session \(min(progress.packed + 1, progress.total)) "
                           + "of \(progress.total)…"
                         : "Packing your library…")
                        .font(.footnote)
                }
                if progress.total > 0 {
                    ProgressView(value: Double(progress.packed), total: Double(progress.total))
                }
                Button("Stop", role: .cancel) { store.cancelBackup() }
                    .font(.footnote)
            }
            .padding(.vertical, 4)
        } else if let file = store.backupFile {
            // A *file*, handed to the share sheet: this app never picks the destination.
            // iCloud Drive is the natural one and it is the rider's storage, not ours.
            ShareLink(item: file.url) {
                Label("Save \(file.filename) · \(Fmt.bytes(file.bytes))",
                      systemImage: "square.and.arrow.up")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("\(file.manifest.sessionCount) session"
                 + "\(file.manifest.sessionCount == 1 ? "" : "s"), "
                 + "\(file.manifest.gearCount) gear item"
                 + "\(file.manifest.gearCount == 1 ? "" : "s"), "
                 + "\(file.manifest.tombstoneCount) deleted. "
                 + "The file is temporary — save it somewhere before you leave Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Discard the file") { store.discardBackup() }
        } else {
            Button { store.makeBackup() } label: {
                Label("Back up library", systemImage: "arrow.down.doc")
            }
            .disabled(store.isBusy || store.sessions.isEmpty)
        }
    }

    // MARK: - Restoring

    @ViewBuilder
    private var restoreRow: some View {
        if let progress = store.restoreProgress {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(progress.total > 0
                         ? "Restoring session \(min(progress.done + 1, progress.total)) "
                           + "of \(progress.total)…"
                         : "Restoring…")
                        .font(.footnote)
                }
                if let current = progress.current {
                    Text(current)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                }
                // Between sessions, never inside one — so stopping leaves whole sessions,
                // and running it again picks up exactly where it left off.
                Button("Stop", role: .cancel) { store.cancelRestore() }
                    .font(.footnote)
            }
            .padding(.vertical, 4)
        } else {
            Button { showRestorePicker = true } label: {
                Label("Restore from backup…", systemImage: "arrow.up.doc")
            }
            .disabled(store.isBusy)
        }
    }
}

/// What the picked file turns out to be, before a single row is written.
///
/// A sheet rather than a confirmation dialog because there are four facts worth reading —
/// when it was taken, how many sessions, which app version wrote it, and what restoring
/// will and will not do — and a dialog that says all that is a wall of text with buttons
/// under it.
private struct RestoreConfirmation: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let offer: SessionStore.RestoreOffer

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // `.current` deliberately: when *you* took this backup, on your clock.
                    LabeledContent("Taken", value: Fmt.date(offer.manifest.createdAt,
                                                            zone: .current))
                    LabeledContent("Sessions", value: "\(offer.manifest.sessionCount)")
                    if offer.manifest.gearCount > 0 {
                        LabeledContent("Gear", value: "\(offer.manifest.gearCount)")
                    }
                    if offer.manifest.tombstoneCount > 0 {
                        LabeledContent("Deleted sessions",
                                       value: "\(offer.manifest.tombstoneCount)")
                    }
                    if let version = offer.manifest.appVersion {
                        LabeledContent("Written by", value: version)
                    }
                } header: {
                    Text(offer.url.lastPathComponent)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } footer: {
                    Text("Nothing is deleted and nothing already in your library is "
                         + "overwritten. Sessions you already have keep their own analysis; "
                         + "only details you have never filled in are taken from the "
                         + "backup. Sessions you deleted after this backup was taken stay "
                         + "deleted.")
                }

                Section {
                    Button {
                        dismiss()
                        store.confirmRestore()
                    } label: {
                        Label("Restore \(offer.manifest.sessionCount) session"
                              + "\(offer.manifest.sessionCount == 1 ? "" : "s")",
                              systemImage: "arrow.up.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Restore library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.restoreOffer = nil
                        dismiss()
                    }
                }
            }
        }
    }
}
