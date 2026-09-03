import SwiftUI
import WingFoilKit

/// Import → Apple Health: the workouts Apple's own Workout app recorded, offered one by one
/// (docs/decisions.md ADR-017).
///
/// Three states, in the order a first-time reader meets them: an explainer with one button,
/// then a list, then — for the rider who said no, which HealthKit never tells us about — an
/// empty list with the one sentence that fixes it. There is no fourth state for "denied",
/// because Apple deliberately makes a read denial indistinguishable from having no workouts,
/// and inventing a verdict we cannot know would be worse than naming both possibilities.
struct HealthImportView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Rows the rider has picked. Empty means "import all", which is what the toolbar offers
    /// when nothing is selected — the common case is a rider with one new afternoon.
    @State private var selection: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                if !store.hasAskedHealthPermission {
                    permissionSection
                } else if store.isReadingHealth && store.healthCandidates.isEmpty {
                    Section { HStack { ProgressView().controlSize(.small); Text("Reading Health…") } }
                } else if store.healthCandidates.isEmpty {
                    emptySection
                } else {
                    workoutSection
                    if store.hasImportedFromHealth { automaticSection }
                }
                typesSection
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if !importable.isEmpty {
                        Button(selection.isEmpty ? "Import all" : "Import \(selection.count)") {
                            Task { await runImport() }
                        }
                        .disabled(store.isBusy || store.isReadingHealth)
                    }
                }
            }
            .task {
                guard store.hasAskedHealthPermission else { return }
                await store.refreshHealthCandidates()
            }
        }
    }

    // MARK: - Sections

    /// The explainer, and the only button on the screen. It is here rather than as an alert
    /// because the iOS permission sheet is about to appear and a rider who does not know why
    /// says no — this is the sentence that has to come first.
    private var permissionSection: some View {
        Section {
            Button {
                Task {
                    await store.requestHealthPermission()
                    await store.refreshHealthCandidates()
                }
            } label: {
                Label("Allow CleanJibe to read workouts", systemImage: "heart.text.square")
            }
        } header: {
            Text("Recorded with Apple's Workout app?")
        } footer: {
            Text("If you record on an Apple Watch with Apple's own Workout app — Surfing, "
                 + "Water Sports or Sailing — the GPS track and heart rate are in the Health "
                 + "app, and CleanJibe can analyse them like any other recording. It reads "
                 + "the workouts you pick and nothing else: no steps, no sleep, no weight. "
                 + "Everything stays on this phone.")
        }
    }

    private var emptySection: some View {
        Section {
            Button {
                Task { await store.refreshHealthCandidates() }
            } label: {
                Label("Look again", systemImage: "arrow.clockwise")
            }
            .disabled(store.isReadingHealth)
        } header: {
            Text("Nothing to import")
        } footer: {
            // Both halves are named because Health genuinely does not tell us which one it is.
            Text("Either there are no \(typeList) workouts in Health from the last two years, "
                 + "or CleanJibe was not given permission to read them. Permission lives in "
                 + "the Health app: **Health → Sharing → Apps → CleanJibe**, or "
                 + "**Settings → Health → Data Access & Devices → CleanJibe**. Turn on "
                 + "Workouts, Workout Routes and Heart Rate.")
        }
    }

    private var workoutSection: some View {
        Section {
            ForEach(store.healthCandidates) { candidate in
                HealthWorkoutRow(candidate: candidate,
                                 isSelected: selection.contains(candidate.id)) {
                    guard !candidate.isAlreadyImported else { return }
                    if selection.contains(candidate.id) {
                        selection.remove(candidate.id)
                    } else {
                        selection.insert(candidate.id)
                    }
                }
            }
        } header: {
            Text("Workouts in Health")
        } footer: {
            Text("Tap to pick, or use Import all. \(importable.count) of "
                 + "\(store.healthCandidates.count) can be imported — the rest are already in "
                 + "your library. A workout with no GPS route is skipped and counted, because "
                 + "there is nothing to analyse without one.")
        }
    }

    private var automaticSection: some View {
        Section {
            Toggle("Import new Health workouts automatically", isOn: Binding(
                get: { store.healthAutoImport },
                set: { store.healthAutoImport = $0 }))
        } footer: {
            Text("CleanJibe checks Health when you open the app and imports anything new of "
                 + "the types below. iOS also wakes apps for new workouts, but it decides "
                 + "when — so opening CleanJibe is what reliably picks up the session you "
                 + "just finished.")
        }
    }

    private var typesSection: some View {
        Section {
            ForEach(HealthWorkoutType.allCases) { type in
                Toggle(type.label, isOn: Binding(
                    get: { store.healthWorkoutTypes.contains(type) },
                    set: { on in
                        var types = store.healthWorkoutTypes
                        if on { types.insert(type) } else { types.remove(type) }
                        store.healthWorkoutTypes = types
                        selection = []
                        Task { await store.refreshHealthCandidates() }
                    }))
            }
        } header: {
            Text("Which workouts to offer")
        } footer: {
            Text("Apple Health has no wingfoil activity, so pick whichever one you record "
                 + "under. Surfing and Water Sports are on by default because those are what "
                 + "the Workout app puts in front of you; Sailing is off, because for most "
                 + "people that bucket holds boats.")
        }
    }

    // MARK: - Helpers

    private var importable: [HealthWorkoutCandidate] {
        store.healthCandidates.filter { !$0.isAlreadyImported }
    }

    private var typeList: String {
        let names = HealthWorkoutType.allCases
            .filter { store.healthWorkoutTypes.contains($0) }
            .map(\.label)
        guard !names.isEmpty else { return "matching" }
        guard names.count > 1 else { return names[0] }
        return names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1]
    }

    private func runImport() async {
        let ids = selection.isEmpty ? importable.map(\.id)
                                    : importable.filter { selection.contains($0.id) }.map(\.id)
        selection = []
        await store.importFromHealth(ids)
    }
}

/// One workout, as much as can be said about it before its route has been fetched: when, how
/// long, what Apple called it and which app wrote it.
private struct HealthWorkoutRow: View {
    let candidate: HealthWorkoutCandidate
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(candidate.isAlreadyImported ? AnyShapeStyle(.secondary)
                                                                : AnyShapeStyle(Color.accentColor))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    // `.current` deliberately, and it is the honest choice here: a workout
                    // Health has not been asked about yet carries no clock of its own, so the
                    // only zone this screen can name is the reader's. The session gets its own
                    // once it is imported and the offset ladder has answered.
                    Text(Fmt.date(candidate.start, zone: .current))
                        .font(.subheadline)
                    Text("\(candidate.type.label) · \(Fmt.duration(candidate.durationS)) · "
                         + candidate.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if candidate.isAlreadyImported {
                    Text("In your library")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(candidate.isAlreadyImported)
    }

    private var symbol: String {
        if candidate.isAlreadyImported { return "checkmark.circle.fill" }
        return isSelected ? "circle.inset.filled" : "circle"
    }
}
