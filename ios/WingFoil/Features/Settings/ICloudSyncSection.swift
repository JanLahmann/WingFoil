import SwiftUI
import WingFoilKit

#if DEV
/// **Settings → iCloud Drive** — two devices, one library (issue #7, ADR-026).
///
/// Dev channel only (docs/channels.md). The folder it writes into is the rider's own iCloud
/// Drive storage and the switch turns the whole library into something that leaves this
/// phone, so it stays on a handful of hand-picked devices until the four rules are met.
///
/// One switch, one status line, one action. The status line is what a rider actually asks of
/// a sync — did it run, is everything there, is anything still on its way — and it is read
/// from a dry run, so it costs nothing and claims nothing the folder does not show.
struct ICloudSyncSection: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            Toggle("Sync the library with iCloud Drive", isOn: $store.iCloudSyncEnabled)

            if store.iCloudSyncEnabled {
                statusRows
                Button {
                    store.syncLibraryNow()
                } label: {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isBusy || store.syncRunning)
            }
        } header: {
            Text("iCloud Drive")
        } footer: {
            // Pattern K: what you get, in one line. Register 3, and no promise the folder
            // cannot keep — the recordings and the names travel, the analysis is redone here.
            // Not "both devices": the dev build runs on iPhone and iPad, a rider may have
            // three, and the folder is this app's own. The App Store app does not read it.
            Text("Your sessions and their names live in iCloud Drive. "
                 + "Every iPhone and iPad on your account reads them.")
        }
        .task { await store.refreshSyncPlan() }
    }

    @ViewBuilder
    private var statusRows: some View {
        if store.syncRunning {
            HStack {
                ProgressView().controlSize(.small)
                Text("Syncing…").font(.footnote)
            }
        } else if store.syncUnavailable {
            Text("Sign in to iCloud and turn on iCloud Drive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !store.syncRunning, let trouble = store.syncTroubles[.iCloud], trouble.isShown {
            Text(trouble.settingsLine)
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        LabeledContent("Last sync") {
            Text(store.syncLastAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
                 ?? "Never")
        }
        if let plan = store.syncPlan {
            // Sessions, not folders: a deleted session keeps its folder so the other device
            // learns of the deletion, and counting folders read "69" beside a library of 63.
            // Now the count Storage shows, once Pending is 0.
            LabeledContent("In iCloud Drive") {
                Text(plan.containerSessions == 1 ? "1 session"
                     : String(plan.containerSessions) + " sessions")
            }
            LabeledContent("Pending") {
                Text(String(plan.pending))
                    .foregroundStyle(plan.pending > 0 ? .orange : .secondary)
            }
        }
    }
}
#endif
