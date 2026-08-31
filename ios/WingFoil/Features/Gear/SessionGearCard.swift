import SwiftUI
import WingFoilKit

/// The combo one session was ridden on, editable in place. Freshly imported sessions
/// already carry the last-used combo, so the common case is confirming rather than typing.
struct SessionGearCard: View {
    let sessionID: String
    @Environment(SessionStore.self) private var store

    @State private var assigned: [GearKind: GearRow] = [:]
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gear").font(.headline)
                Spacer()
                if let spot = store.session(id: sessionID).flatMap({ store.spot(id: $0.spotId) }) {
                    Label(spot.name, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(GearKind.allCases) { kind in
                HStack {
                    Label { Text(kind.label) } icon: { GearKindIcon(kind: kind, size: 14) }
                        .font(.subheadline)
                        .frame(width: 90, alignment: .leading)
                    Menu {
                        Button("None") { assign(kind, nil) }
                        Divider()
                        ForEach(options(kind)) { item in
                            Button(item.name) { assign(kind, item) }
                        }
                    } label: {
                        HStack {
                            Text(assigned[kind]?.name ?? "Not set")
                                .foregroundStyle(assigned[kind] == nil ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if options(.wing).isEmpty && options(.board).isEmpty && options(.foil).isEmpty {
                Text("Add wings, boards and foils on the Gear tab to correlate sessions "
                     + "with what you rode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 14))
        .task(id: store.libraryGeneration) {
            guard !loaded || assigned.isEmpty else { return }
            assigned = (try? await store.library.gearOfSession(sessionID)) ?? [:]
            loaded = true
        }
    }

    private func options(_ kind: GearKind) -> [GearRow] {
        store.gearAggregates
            .filter { $0.gear.gearKind == kind && ($0.gear.active || $0.gear.id == assigned[kind]?.id) }
            .map(\.gear)
    }

    private func assign(_ kind: GearKind, _ gear: GearRow?) {
        assigned[kind] = gear
        Task { await store.assignGear(sessionID: sessionID, kind: kind, gearID: gear?.id) }
    }
}
