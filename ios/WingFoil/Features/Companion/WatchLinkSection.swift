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
                Button { store.chooseWatch() } label: {
                    Label("Choose a different watch…", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) { store.forgetWatch() } label: {
                    Label("Forget this watch", systemImage: "minus.circle")
                }
            }

            if let last = store.lastCardAt {
                LabeledContent("Last summary", value: Fmt.date(last))
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

    /// Sixteen points would be false precision on a link whose whole job is telling port
    /// from starboard; eight is what a rider reads off a forecast anyway.
    private static let compass: [(name: String, degrees: Int)] = [
        ("N", 0), ("NE", 45), ("E", 90), ("SE", 135),
        ("S", 180), ("SW", 225), ("W", 270), ("NW", 315),
    ]
}
