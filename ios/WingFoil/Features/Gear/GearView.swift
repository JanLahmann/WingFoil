import SwiftUI
import WingFoilKit

/// Manage the quiver and see what each item actually did (plan §3.3 "Gear"). A session
/// carries at most one wing, one board and one foil; new sessions inherit the last combo
/// and every session stays editable from its detail screen.
struct GearView: View {
    @Environment(SessionStore.self) private var store

    @State private var editing: GearRow?
    @State private var adding: GearKind?
    @State private var showRetired = false

    var body: some View {
        NavigationStack {
            List {
                // Spots live here because a spot is the same kind of object as a wing: a
                // named thing sessions reference and that you filter the aggregate screens
                // by (`app-ui-review.md` §6.1). They used to be four levels deep in the
                // Settings sheet — behind the gear icon, past the help rows, the API key,
                // the sync section and the watch section — while "All spots" was a
                // top-level filter chip on both Records and Trends. This tab is the one
                // that owns the rider's named things, so it owns these too.
                Section {
                    NavigationLink { SpotsView() } label: {
                        Label {
                            LabeledContent("Spots", value: "\(store.spots.count)")
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                    }
                } footer: {
                    Text("Sessions starting within "
                         + "\(Int(SpotClusterer.defaultRadiusM)) m of each other are one "
                         + "spot. Names come from the map when the network allows; rename "
                         + "any of them and it sticks.")
                }

                ForEach(GearKind.allCases) { kind in
                    Section {
                        let items = aggregates(for: kind)
                        if items.isEmpty {
                            Text("No \(kind.label.lowercased()) yet")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        } else {
                            ForEach(items) { entry in
                                Button { editing = entry.gear } label: {
                                    GearRowView(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                let doomed = offsets.map { items[$0].gear }
                                Task { for gear in doomed { await store.deleteGear(gear) } }
                            }
                        }
                        Button {
                            adding = kind
                        } label: {
                            Label("Add \(kind.label.lowercased())", systemImage: "plus")
                                .font(.footnote)
                        }
                    } header: {
                        Label { Text(kind.label) } icon: { GearKindIcon(kind: kind, size: 13) }
                    }
                }

                Section {
                    Toggle("Show retired gear", isOn: $showRetired)
                } footer: {
                    Text("Retiring keeps a wing's history — its sessions still reference it, "
                         + "it just drops out of the pickers. Swipe to delete removes the link "
                         + "for good.")
                }
            }
            .navigationTitle("Gear & spots")
            .sheet(item: $editing) { gear in
                GearEditor(gear: gear) { saved in Task { await store.saveGear(saved) } }
            }
            .sheet(item: $adding) { kind in
                GearEditor(gear: GearRow(name: "", kind: kind)) { saved in
                    Task { await store.saveGear(saved) }
                }
            }
        }
    }

    private func aggregates(for kind: GearKind) -> [GearAggregate] {
        store.gearAggregates.filter {
            $0.gear.gearKind == kind && (showRetired || $0.gear.active)
        }
    }
}

private struct GearRowView: View {
    let entry: GearAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.gear.name).font(.headline)
                if !entry.gear.active {
                    Text("retired")
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.16), in: .capsule)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            if let notes = entry.gear.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                stat("\(entry.sessions)", "sessions")
                stat(String(format: "%.0f h", entry.hours), "time")
                stat(Fmt.pct(entry.foilPct), "foil")
                stat(Fmt.kn(entry.best2sKn), "best 2s")
                stat(Fmt.pct(entry.jibeFlewThroughPct), "jibes")
            }
            .font(.caption)
            if let last = entry.lastUsed {
                // `.current`: an aggregate over many sessions, which have no single zone
                // between them. "How long since I rode this" is asked from here and now.
                Text("Last used \(Fmt.shortDate(last, zone: .current))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct GearEditor: View {
    @State var gear: GearRow
    let onSave: (GearRow) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $gear.name)
                    Picker("Kind", selection: kindBinding) {
                        ForEach(GearKind.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("e.g. \"Duotone Unit 5 m\", \"Armstrong HA 925\".")
                }
                Section("Notes") {
                    TextField("Size, year, anything worth remembering",
                              text: Binding(get: { gear.notes ?? "" },
                                            set: { gear.notes = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Toggle("In the quiver", isOn: $gear.active)
                } footer: {
                    Text("Turn off to retire it without losing its sessions.")
                }
            }
            .navigationTitle(gear.name.isEmpty ? "New gear" : gear.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(gear)
                        dismiss()
                    }
                    .disabled(gear.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var kindBinding: Binding<GearKind> {
        Binding(get: { gear.gearKind ?? .wing }, set: { gear.kind = $0.rawValue })
    }
}
