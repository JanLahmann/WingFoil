// Settings → Garmin watch — a DEV door (docs/channels.md).
#if DEV
import SwiftUI
import WingFoilKit

/// The watch link, in Settings (phase 5).
///
/// Everything on this screen is a fact the rider can act on: which watch, whether it is
/// reachable, when a session last came through, and one button that pushes the wind. There
/// is no "connect" button, because there is nothing to connect — Garmin Connect Mobile owns
/// the Bluetooth link and this app is a guest on it.
struct WatchLinkSection: View {
    @Environment(SessionStore.self) private var store

    private var state: CompanionLinkState { store.companionState }

    var body: some View {
        Section {
            LabeledContent("Watch") {
                Text(state.headline)
                    .foregroundStyle(state.canSend ? .green : .secondary)
                    .multilineTextAlignment(.trailing)
            }

            switch state {
            case .noConnectMobile:
                // Nothing this app can do: no GCM, no link, and no button worth offering.
                EmptyView()
            case .noDevice:
                Button { store.chooseWatch() } label: {
                    Label("Choose your watch…", systemImage: "applewatch.radiowaves.left.and.right")
                }
            default:
                windRow
                mapRow
                Button { store.chooseWatch() } label: {
                    Label("Choose a different watch…", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) { store.forgetWatch() } label: {
                    Label("Forget this watch", systemImage: "minus.circle")
                }
            }

            if let probe = store.lastLinkProbe {
                // The dev build's link probe (docs/direct-transfer.md): the watch times the
                // send, the phone confirms what arrived.
                LabeledContent("Link probe", value: probe)
            }
            if let line = store.directPageLine {
                // Every page as it lands, before any session is whole: the line that says
                // whether the radio reached the app at all.
                LabeledContent("Direct pages", value: line)
            }
            if let line = store.directAnswerLine {
                LabeledContent("Answer to the watch", value: line)
            }
            if let direct = store.lastDirectTransfer {
                // The session the watch sent straight over (docs/transfer-format.md): when
                // it was ridden, how many pages crossed, how long they took.
                LabeledContent("Last direct session", value: Self.directSummary(direct))
            }
            if let last = store.lastCardAt {
                // `.current` deliberately: when the watch last reached this phone, which is an
                // event on the reader's clock rather than a moment in any session.
                LabeledContent("Last summary", value: Fmt.date(last, zone: .current))
            }
        } header: {
            Text("Garmin watch")
        } footer: {
            Text(state.detail)
        }
        .task { store.refreshCompanionState() }
    }

    /// The wind push. A compass picker rather than a free 0–359 field: nobody knows the
    /// wind to the degree, the watch only uses it to decide which side of the axis a turn
    /// happened on, and a wrong 12° costs nothing while a wrong 120° relabels every tack.
    @ViewBuilder
    private var windRow: some View {
        @Bindable var store = store
        Picker("Wind from", selection: $store.windToSend) {
            ForEach(Self.compass, id: \.degrees) { point in
                Text("\(point.name) (\(point.degrees)°)").tag(point.degrees)
            }
            Text("Not set").tag(CompanionWind.clear)
        }
        Button {
            Task { await store.sendWindToWatch(store.windToSend) }
        } label: {
            Label("Send wind to watch", systemImage: "wind")
        }
        .disabled(!state.canSend)
    }

    /// The map push. The row names the ground that is about to go over
    /// (docs/watch-map-snapshot.md) and opens the picker that chooses it: by default the
    /// two most-ridden spots, as it always was, and otherwise up to two of the library's
    /// spots and "Where I am now" — the afternoon at a lake the library has never seen
    /// (Jan, 13 Sep 2026).
    ///
    /// The button exists even though the push is automatic, for the same reason the wind
    /// one does: a link that only ever works silently is a link nobody believes in. It
    /// re-sends unconditionally, which is the point of pressing it.
    @ViewBuilder
    private var mapRow: some View {
        let targets = store.watchMapTargets
        NavigationLink {
            WatchMapChoiceView()
        } label: {
            LabeledContent("Map for the watch") {
                Text(targets.isEmpty ? "No spot with a fix yet"
                                     : targets.map(\.name).joined(separator: " · "))
                    .multilineTextAlignment(.trailing)
            }
        }
        if !targets.isEmpty {
            if let result = store.watchMapStatus {
                LabeledContent("Last map", value: result)
            }
            Button {
                Task { await store.sendMapsToWatch() }
            } label: {
                HStack {
                    Label("Send map to watch", systemImage: "map")
                    if store.isSendingWatchMap {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!state.canSend || store.isSendingWatchMap)
        }
    }

    /// "18 Sep 14:07 · 13 pages · 26 s", and "cut short" where the transfer stopped part
    /// way. Three facts on one line, in the order they answer "did it work": which session,
    /// how much of it, how long it took. `.current` deliberately for the date — this row is
    /// about a transfer to this phone, and the clock is the reader's.
    static func directSummary(_ receipt: DirectTransferReceipt) -> String {
        var parts = [Fmt.date(receipt.sessionStart, zone: .current),
                     "\(receipt.pages) page\(receipt.pages == 1 ? "" : "s")",
                     "\(Int(receipt.seconds.rounded())) s"]
        if receipt.cutShort { parts.append("cut short") }
        return parts.joined(separator: " · ")
    }

    /// Sixteen points would be false precision on a link whose whole job is telling port
    /// from starboard; eight is what a rider reads off a forecast anyway.
    private static let compass: [(name: String, degrees: Int)] = [
        ("N", 0), ("NE", 45), ("E", 90), ("SE", 135),
        ("S", 180), ("SW", 225), ("W", 270), ("NW", 315),
    ]
}

#endif
