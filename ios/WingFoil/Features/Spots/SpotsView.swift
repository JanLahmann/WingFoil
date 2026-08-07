import SwiftUI
import WingFoilKit

/// Auto-clustered places (plan §3.3 "Spots: auto-cluster"). Sessions within ~500 m of
/// each other are one spot; names come from reverse geocoding when the network allows and
/// are otherwise placeholders the rider can overwrite — a rename is permanent and
/// survives re-clustering.
struct SpotsView: View {
    @Environment(SessionStore.self) private var store

    @State private var renaming: SpotRow?
    @State private var draft = ""

    var body: some View {
        List {
            if store.spots.isEmpty {
                ContentUnavailableView("No spots yet", systemImage: "mappin.slash",
                                       description: Text("Spots appear once sessions with GPS "
                                                         + "are in the library."))
            } else {
                Section {
                    ForEach(store.spots) { entry in
                        Button {
                            draft = entry.spot.name
                            renaming = entry.spot
                        } label: {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Tap to rename. Coordinates are the running centroid of the "
                         + "sessions that start there.")
                }
            }

            Section {
                Button("Re-cluster spots") { Task { await store.reclusterSpots() } }
                    .disabled(store.sessions.isEmpty)
                Button("Look up names again") { Task { await store.nameSpots() } }
                    .disabled(!store.spots.contains { $0.spot.autoNamed })
            } footer: {
                Text("Re-clustering rebuilds every spot from the session coordinates at a "
                     + "\(Int(SpotClusterer.defaultRadiusM)) m radius; names you typed are kept.")
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
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entry.sessions)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(String(format: "%.4f, %.4f", entry.spot.lat, entry.spot.lon))
                if let last = entry.lastVisit {
                    Text("· last \(Fmt.shortDate(last))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
