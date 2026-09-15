import SwiftUI
import WingFoilKit

/// Manage the quiver and see what each item actually did (plan §3.3 "Gear"). A session
/// carries at most one wing, one board and one foil; new sessions inherit the last combo
/// and every session stays editable from its detail screen.
///
/// **Spots and gear are one page** (Jan, build 58). Spots are the same kind of object as a
/// wing — a named thing sessions reference and that you filter the aggregate screens by
/// (`app-ui-review.md` §6.1) — and this tab is the one that owns the rider's named things.
/// They arrived here from four levels down the Settings sheet as a *row* that pushed a
/// sub-page of their own, which is a menu entry for a list of four places: one tap to find
/// out there is nothing to find out. Now they are the first section of this list, drawn the
/// way the three gear groups are drawn — a header with an icon, a row per named thing with
/// its session count, the actions at the foot of the section — so the page has one shape
/// all the way down and the tab's name is literally true.
struct GearView: View {
    @Environment(SessionStore.self) private var store

    @State private var editing: GearRow?
    @State private var adding: GearKind?
    @State private var showRetired = false
    /// The spot being renamed, and the name being typed. A rename is one short string, so
    /// it is an alert with a field in it rather than a screen.
    @State private var renaming: SpotRow?
    @State private var spotName = ""

    var body: some View {
        NavigationStack {
            List {
                spotsSection

                ForEach(GearKind.allCases) { kind in
                    Section {
                        let items = aggregates(for: kind)
                        if items.isEmpty {
                            // Plural: this is an empty *collection*, and "No wing yet"
                            // under a "Wing" header reads as a missing thing rather than
                            // an empty shelf. All three kinds pluralise with an s.
                            Text("No \(kind.label.lowercased())s yet")
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
                FeedbackFooter.section
            }
            // Same measure as the library list: a form of named things, in the middle of
            // the window rather than stretched across it.
            .readableColumn()
            .navigationTitle("Gear & spots")
            .sheet(item: $editing) { gear in
                GearEditor(gear: gear) { saved in Task { await store.saveGear(saved) } }
            }
            .sheet(item: $adding) { kind in
                GearEditor(gear: GearRow(name: "", kind: kind)) { saved in
                    Task { await store.saveGear(saved) }
                }
            }
            .alert("Rename spot", isPresented: Binding(get: { renaming != nil },
                                                       set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $spotName)
                Button("Save") {
                    if let spot = renaming {
                        Task { await store.renameSpot(spot, to: spotName) }
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    // MARK: - Spots

    /// The first section of the page, in the gear groups' own shape: an icon and a name in
    /// the header, one row per spot with its session count, and the section's two actions
    /// at its foot where every gear group keeps "Add wing".
    private var spotsSection: some View {
        Section {
            if visibleSpots.isEmpty {
                Text("No spots yet")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(visibleSpots) { entry in
                    Button {
                        spotName = entry.spot.name
                        renaming = entry.spot
                    } label: {
                        SpotRowView(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                Task { await store.reclusterSpots() }
            } label: {
                Label("Re-cluster spots", systemImage: "arrow.triangle.merge")
                    .font(.footnote)
            }
            .disabled(store.sessions.isEmpty)
            Button {
                Task { await store.nameSpots() }
            } label: {
                Label("Look up names again", systemImage: "text.magnifyingglass")
                    .font(.footnote)
            }
            .disabled(!visibleSpots.contains { $0.spot.autoNamed })
        } header: {
            Label { Text("Spots") } icon: { Image(systemName: "mappin.and.ellipse") }
        } footer: {
            Text("Tap a spot to rename it — a name you type sticks through a re-cluster. "
                 + "Sessions starting within \(Int(SpotClusterer.defaultRadiusM)) m of each "
                 + "other are one spot, and names come from the map when the network "
                 + "allows.")
        }
    }

    /// **A spot with no sessions is not a place you have been.** Clustering can leave one
    /// behind — a session deleted, a re-cluster that moved its afternoons into a neighbour
    /// — and an empty spot on this page is a name with nothing under it that still shows up
    /// in every spot filter. The count is the whole of the evidence, so the count is the
    /// whole of the filter; the row that produced the empty spot is somebody else's fix.
    private var visibleSpots: [SpotAggregate] {
        store.spots.filter { $0.sessions > 0 }
    }

    private func aggregates(for kind: GearKind) -> [GearAggregate] {
        store.gearAggregates.filter {
            $0.gear.gearKind == kind && (showRetired || $0.gear.active)
        }
    }
}

/// One spot, drawn the way `GearRowView` draws one wing: the name on top, the figures
/// underneath in the caption size, the chevron that says the row opens something.
private struct SpotRowView: View {
    let entry: SpotAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.spot.name).font(.headline)
                if entry.spot.autoNamed {
                    // Named by the map rather than by the rider — which is the one thing
                    // worth knowing before you decide whether to rename it.
                    Image(systemName: "wand.and.stars")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            HStack(spacing: 14) {
                stat("\(entry.sessions)", "sessions")
                if let last = entry.lastVisit {
                    // `.current`: a spot spans sessions and has no one zone of its own. The
                    // date is "how long since I was there", asked from where you are now.
                    stat(Fmt.shortDate(last, zone: .current), "last")
                }
            }
            .font(.caption)
            .denseRowTypeSizeCap()
        }
        .padding(.vertical, 3)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
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
            // Five figures in one line. They scale, and stop where five of them stop
            // fitting a phone — the name and the notes above them scale the whole way.
            .denseRowTypeSizeCap()
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
            Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
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
