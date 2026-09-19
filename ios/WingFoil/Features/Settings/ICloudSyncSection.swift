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
            Text("Your sessions and what you called them live in one iCloud Drive folder. "
                 + "Both devices read it. Deleted sessions stay deleted.")
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
        LabeledContent("Last sync") {
            Text(store.syncLastAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
                 ?? "Never")
        }
        if let plan = store.syncPlan {
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
