import SwiftUI
import WingFoilKit

/// **The Sessions tab's filter** — one toolbar menu, four questions, beside the Import
/// button it shares a corner with.
///
/// A menu rather than the chip bar Records and Trends carry (`LibraryFilterBar`): those two
/// screens are *about* a spot and a set of kit, and their pickers are the screen. This one
/// narrows a list that is complete without it, so it stays out of the way until it is
/// wanted and says so in the chip row under the title when it is on.
///
/// The rules are the kit's (`LibraryListFilter`); this file is the wording and the order.
/// Every entry carries its own tick, so the menu also answers "what am I looking at" — the
/// question a rider asks it far more often than "narrow this".
struct LibraryFilterMenu: View {
    @Binding var filter: LibraryListFilter
    /// Raised when the rider picks "Custom range…". Owned by the screen, because the sheet
    /// is the screen's and a menu is gone by the time it appears.
    @Binding var editingRange: Bool
    /// The **unfiltered** library — what "the sources that actually occur" is asked of. A
    /// menu built from what survives the current filter would offer a door, be tapped, and
    /// then no longer offer the door it came from.
    let library: [SessionRow]

    @Environment(SessionStore.self) private var store

    var body: some View {
        Menu {
            Section("Spot") {
                entry("All spots", on: filter.spotId == nil) { filter.spotId = nil }
                ForEach(store.spots) { spot in
                    entry(spot.spot.name, on: filter.spotId == spot.spot.id) {
                        filter.spotId = spot.spot.id
                    }
                }
            }
            Section("Source") {
                entry("All sources", on: filter.source == nil) { filter.source = nil }
                ForEach(sources, id: \.self) { source in
                    entry(source.libraryFilterLabel, on: filter.source == source) {
                        filter.source = source
                    }
                }
            }
            // Only with the windsurf switch on. Off, every session is a wingfoil session as
            // far as the app will say so, and a picker with one real answer in it is a
            // control that teaches the rider to stop reading the menu.
            if store.windsurfEnabled {
                Section("Discipline") {
                    entry("All", on: filter.discipline == nil) { filter.discipline = nil }
                    ForEach(Discipline.allCases, id: \.self) { discipline in
                        entry(discipline.title, on: filter.discipline == discipline) {
                            filter.discipline = discipline
                        }
                    }
                }
            }
            Section("Date") {
                let window = LibraryDateWindow.window(for: filter.dateRange)
                entry(LibraryDateWindow.allTime.title, on: window == .allTime) {
                    filter.dateRange = nil
                }
                entry(LibraryDateWindow.thisYear.title, on: window == .thisYear) {
                    filter.dateRange = LibraryDateWindow.year(thisYear)
                }
                entry(LibraryDateWindow.lastYear.title, on: window == .lastYear) {
                    filter.dateRange = LibraryDateWindow.year(thisYear - 1)
                }
                entry(LibraryDateWindow.custom.title, on: window == .custom) {
                    editingRange = true
                }
            }
        } label: {
            Label("Filter", systemImage: filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    /// The doors this library actually holds, in the order a reader wants them: the two that
    /// carry a recording off a watch, then the clouds, then the hand-made ones. A door that
    /// brought nothing in is not offered — a filter that can only ever empty the list is not
    /// a filter, it is a trap.
    private var sources: [ImportSource] {
        let order: [ImportSource] = [.watch, .appleWatch, .icu, .strava, .appleHealth,
                                     .file, .airdrop, .gdpr, .example, .fixtures]
        return order.filter { source in library.contains { source.isNamed(in: $0.importSource) } }
    }

    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    /// One row, ticked when it is the one in force — the shape iOS menus use for a choice.
    private func entry(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if on {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// **The chip row** under the navigation title: what is narrowing this list, one capsule
/// each, each one its own undo.
///
/// The menu says what is on; this says it without being opened, which is the half that
/// matters — a list quietly three sessions long because a chip was left on last week is the
/// failure this row exists to prevent.
struct LibraryFilterChips: View {
    @Binding var filter: LibraryListFilter
    @Environment(SessionStore.self) private var store

    var body: some View {
        let chips = filter.chips(spotName: { store.spot(id: $0)?.name })
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        filter.clear(chip.field)
                    } label: {
                        HStack(spacing: 4) {
                            Text(chip.label).lineLimit(1)
                            Image(systemName: "xmark").imageScale(.small)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.18), in: .capsule)
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                // One button for "off, all of it", and only where there is more than one
                // chip to clear: beside a single capsule that already has its own ×, it
                // would be two controls doing the same thing.
                if chips.count >= 2 {
                    Button("Clear all") { filter = LibraryListFilter() }
                        .font(.footnote)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

/// **A range of your own** — the two dates behind "Custom range…", with the Periods
/// screen's own semantics and its own sentence: both dates count.
struct LibraryDateRangeSheet: View {
    @Binding var filter: LibraryListFilter
    /// Seeded from the library rather than from today, for the reason `PeriodsView` gives:
    /// a rider opening this in February is looking for the month he last sailed in, and an
    /// empty "1 – 8 February" is a worse first answer than that.
    let seed: ClosedRange<Date>

    @Environment(\.dismiss) private var dismiss
    @State private var from = Date()
    @State private var to = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                } footer: {
                    Text("Both dates count. The filter narrows this list only. Your "
                         + "records and trends stay all-time.")
                }
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Whichever way round they were picked: two dates are a range, and
                        // a rider who set "to" first has not made a mistake to be told about.
                        filter.dateRange = min(from, to)...max(from, to)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            let range = filter.dateRange ?? seed
            from = range.lowerBound
            to = range.upperBound
        }
    }
}
