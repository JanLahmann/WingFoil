// The watch map picker, and the app's only location prompt — DEV (docs/channels.md).
#if DEV
import SwiftUI
import WingFoilKit

/// Which two maps the watch holds — Settings → Garmin watch → Map for the watch.
///
/// WHY THERE IS A PAGE AT ALL NOW. The phone used to choose for the rider, and for a
/// library with a home spot in it that is still the right answer — so it is still the
/// default, sitting at the top with a tick on it. What it could not answer was the
/// afternoon somewhere new: a lake the library has never seen has no cluster, so the
/// automatic rule cannot name it, and the watch would draw the breadcrumb over nothing.
/// "Where I am now" is that afternoon (Jan, 13 Sep 2026).
///
/// WHY A TICK LIST AND NOT TWO PICKERS. Two slots is a fact about the watch, not a shape
/// for a form: a rider who wants one map and nothing else should not have to fill a second
/// picker with "none". Ticks say "these" and the footer says how many fit.
struct WatchMapChoiceView: View {
    @Environment(SessionStore.self) private var store

    /// Set when a tap on "Where I am now" came back without a fix and Core Location is not
    /// authorized — the one case the rider can act on, and only from the system's Settings.
    @State private var locationRefused = false
    /// True while the phone is asking. The row is not disabled — a second tap should still
    /// be able to untick the pick — but it says what it is doing.
    @State private var isAskingLocation = false

    private var choice: WatchMapChoice { store.watchMapChoice }

    /// Every spot with a coordinate, most-ridden first — the same order the automatic rule
    /// picks in, so the row above the list and the list under it tell one story.
    private var spots: [SpotAggregate] { WatchMapChoice.mostRidden(store.spots) }

    var body: some View {
        List {
            Section("Automatic") {
                row(title: "Two most-ridden spots", isPicked: choice.isAutomatic) {
                    store.setWatchMapChoice(WatchMapChoice())
                }
            }

            if !spots.isEmpty {
                Section("Spots") {
                    ForEach(spots) { spot in
                        row(title: spot.spot.name,
                            caption: "\(spot.sessions) session\(spot.sessions == 1 ? "" : "s")",
                            isPicked: choice.contains(.spot(id: spot.spot.id))) {
                            toggle(.spot(id: spot.spot.id))
                        }
                    }
                }
            }

            Section {
                row(title: "Where I am now",
                    caption: "Asks this phone for its position once, each time a map is sent.",
                    systemImage: "location.fill",
                    isPicked: choice.contains(.here),
                    isBusy: isAskingLocation) {
                    tapHere()
                }
                if locationRefused {
                    Text("Location is off for CleanJibe in iPhone Settings")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Now")
            } footer: {
                Text("The watch holds two maps. Pick up to two; a third replaces the "
                     + "oldest pick.")
            }
        }
        .readableColumn()
        .navigationTitle("Map for the watch")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - One row

    /// Every row on this page is the same shape: a name, maybe a line under it, and a tick
    /// on the right when it is one of the two. A tick and not a switch, because these rows
    /// are alternatives to each other and a column of switches would read as independent.
    @ViewBuilder
    private func row(title: String, caption: String? = nil, systemImage: String? = nil,
                     isPicked: Bool, isBusy: Bool = false,
                     tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.tint)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let caption {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isBusy {
                    ProgressView()
                } else if isPicked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Picked")
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
    }

    // MARK: - Taps

    private func toggle(_ pick: WatchMapPick) {
        var next = choice
        next.toggle(pick)
        store.setWatchMapChoice(next)
    }

    /// Ticking "Where I am now" asks for the position **here**, on this tap, rather than
    /// during the next send: a permission sheet belongs under the finger that asked for it,
    /// and a rider who sees the map row say "Where I am now" wants to know right away
    /// whether this phone will actually answer.
    private func tapHere() {
        let wasPicked = choice.contains(.here)
        toggle(.here)
        guard !wasPicked else {
            locationRefused = false
            return
        }
        Task {
            isAskingLocation = true
            let gotFix = await store.refreshPhoneFix()
            isAskingLocation = false
            // Only "off" is worth a footnote. No fix with permission granted is a phone
            // indoors, which fixes itself by the time the rider is at the water.
            locationRefused = !gotFix && !store.phoneLocationIsAuthorized
        }
    }
}

#endif
