import SwiftUI
import WingFoilKit

/// Auto-clustered places (plan §3.3 "Spots: auto-cluster"). Sessions within ~500 m of
/// each other are one spot; names come from reverse geocoding when the network allows and
/// are otherwise placeholders the rider can overwrite — a rename is permanent and
/// survives re-clustering.
///
/// **Reached from the spot filter on Records and Trends, and from nowhere else.** The Gear
/// tab used to push this as a sub-page and now draws the same list inline (`GearView`); what
/// is left here is the "Manage spots…" door inside the chip that filters by spot, which is
/// the one place a rider is already thinking about the set of them.
struct SpotsView: View {
    @Environment(SessionStore.self) private var store

    @State private var renaming: SpotRow?
    @State private var draft = ""

    /// Same rule as the Gear tab's: a spot with no sessions under it is not a place the
    /// rider has been, and it must not offer itself for renaming or for filtering.
    private var spots: [SpotAggregate] { store.spots.filter { $0.sessions > 0 } }

    var body: some View {
        List {
            if spots.isEmpty {
                ContentUnavailableView(AppShellCopy.Gear.noSpots, systemImage: "mappin.slash",
                                       description: Text(AppShellCopy.Gear.noSpotsLine))
            } else {
                Section {
                    ForEach(spots) { entry in
                        Button {
                            draft = entry.spot.name
                            renaming = entry.spot
                        } label: {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Tap to rename. The pin sits in the middle of where your "
                         + "sessions start.")
                }
            }

            Section {
                Button("Rebuild spots") { Task { await store.reclusterSpots() } }
                    .disabled(store.sessions.isEmpty)
                Button("Look up names again") { Task { await store.nameSpots() } }
                    .disabled(!spots.contains { $0.spot.autoNamed })
            } footer: {
                // The Gear & spots tab's own footer line, so one fact has one sentence.
                Text(AppShellCopy.fill(AppShellCopy.Gear.spotsFooter,
                                       ["radius": String(Int(SpotClusterer.defaultRadiusM))]))
            }
        }
        .navigationTitle("Spots")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename spot", isPresented: Binding(get: { renaming != nil },
                                                   set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draft)
            Button("Save") {
                if let spot = renaming { Task { await store.renameSpot(spot, to: draft) } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ entry: SpotAggregate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.spot.name).font(.headline)
                if entry.spot.autoNamed {
                    Image(systemName: "wand.and.stars")
                        .font(.caption2)
                        .foregroundStyle(.readableSecondary)
                }
                Spacer()
            }
            // "3 sessions · last 12 Oct": a bare count and four-decimal coordinates were
            // numbers a rider could not name.
            HStack(spacing: 6) {
                Text("\(entry.sessions) " + (entry.sessions == 1 ? "session" : "sessions"))
                if let last = entry.lastVisit {
                    // `.current`: a spot spans sessions and has no one zone of its own. The
                    // date is "how long since I was there", asked from where you are now.
                    Text("· last " + Fmt.shortDate(last, zone: .current))
                }
            }
            .font(.caption)
            .foregroundStyle(.readableSecondary)
        }
        .padding(.vertical, 2)
    }
}
