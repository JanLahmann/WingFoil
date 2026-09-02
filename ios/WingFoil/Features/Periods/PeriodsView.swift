import SwiftUI
import WingFoilKit

/// **Periods** — the library talking about a week rather than an afternoon.
///
/// Trips, then months, then seasons, each a row that opens to one aggregate block
/// (`PeriodBlock`), plus a range the rider picks himself. Every rule is the analyzer's and
/// lives in `LibraryStore.periods`; this screen lists what it produced and hands one of them
/// to the card composer.
///
/// **Rows before blocks.** Fifteen numbers times a dozen periods is a screen nobody reads, so
/// the list is headings and one summary line each — "12 sessions · 31 July – 7 August 2026" —
/// and the block is one tap away for the period actually being looked for. It is the same
/// trade the Records tables make: a table of values beats a wall of tiles.
struct PeriodsView: View {
    @Environment(SessionStore.self) private var store

    @State private var filter = LibraryFilter()
    @State private var periods = PeriodSet()
    @State private var custom: Period?
    @State private var from = Date()
    @State private var to = Date()
    @State private var loaded = false
    @State private var sharing: Period?

    var body: some View {
        List {
            Section {
                LibraryFilterBar(filter: $filter)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listRowBackground(Color.clear)

            customSection

            if loaded && periods.isEmpty {
                ContentUnavailableView(
                    "No periods yet", systemImage: "calendar",
                    description: Text("A session needs a recorded start before it can belong "
                                      + "to a month. Import one and the months, seasons and "
                                      + "trips fill in."))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            group("Trips", periods.trips,
                  note: "Spells at one spot — a holiday the library noticed. No gap wider "
                      + "than \(PeriodRules.tripGapDays) days, at least "
                      + "\(PeriodRules.tripMinSessions) sessions.")
            group("Months", periods.months,
                  note: "Calendar months, on the day the rider had.")
            group("Seasons", periods.seasons,
                  note: "1 April to 31 March, so a February session counts towards the "
                      + "winter it belongs to.")
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Periods")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task(id: reloadKey) { await reload() }
        .sheet(item: $sharing) { period in
            PeriodShareView(period: period)
        }
    }

    private var reloadKey: String {
        "\(filter.spotId ?? "-")|\(filter.gearId ?? "-")|\(store.libraryGeneration)"
    }

    private func reload() async {
        periods = (try? await store.library.periods(filter)) ?? PeriodSet()
        // Seeded from the library rather than from today: a rider opening this screen in
        // February wants the range picker pointing at water, and an empty "1 – 8 February"
        // is a worse first answer than the month he last sailed in.
        if !loaded, let last = periods.months.first,
           let start = day(last.startDate), let end = day(last.endDate) {
            from = start
            to = end
        }
        loaded = true
        await reloadCustom()
    }

    private func reloadCustom() async {
        custom = try? await store.library.periodBlock(filter, from: key(from), to: key(to))
    }

    // MARK: - The rider's own range

    @ViewBuilder
    private var customSection: some View {
        Section {
            DatePicker("From", selection: $from, displayedComponents: .date)
            DatePicker("To", selection: $to, displayedComponents: .date)
            HStack {
                quick("This week", days: -((Calendar.current.component(.weekday, from: Date())
                                            + 5) % 7))
                quick("Last 7 days", days: -6)
                quick("This month", monthStart: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let custom, custom.sessions > 0 {
                PeriodBlockView(period: custom)
                Button {
                    sharing = custom
                } label: {
                    Label("Share card", systemImage: "square.and.arrow.up")
                }
            } else if loaded {
                Text("No session in that range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("A range of your own")
        } footer: {
            Text("Both dates count. Rates over a period divide the period's own totals — "
                 + "they are not the average of the sessions' own.")
        }
        .onChange(of: from) { Task { await reloadCustom() } }
        .onChange(of: to) { Task { await reloadCustom() } }
    }

    private func quick(_ label: String, days: Int = 0, monthStart: Bool = false) -> some View {
        Button(label) {
            let calendar = Calendar.current
            let now = Date()
            to = now
            from = monthStart
                ? calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
                : calendar.date(byAdding: .day, value: days, to: now) ?? now
        }
    }

    // MARK: - The three groups

    @ViewBuilder
    private func group(_ title: String, _ rows: [Period], note: String) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { period in
                    NavigationLink {
                        PeriodDetailView(period: period)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(period.title).font(.subheadline.weight(.semibold))
                            Text("\(period.sessions) session"
                                 + (period.sessions == 1 ? "" : "s")
                                 + " · \(period.dateLine)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(title)
            } footer: {
                Text(note)
            }
        }
    }

    // MARK: - Days

    /// The picker's dates as the `YYYY-MM-DD` the query takes. Formatted on the *reader's*
    /// clock, because that is the calendar he picked them from — the session side of the
    /// comparison is each session's own day, which is where the zone question actually lives.
    private func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func day(_ text: String?) -> Date? {
        guard let text else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1],
                                                          day: parts[2]))
    }
}

/// One period's block, as the two-column grid the rest of the app draws a list of numbers in.
struct PeriodBlockView: View {
    let period: Period

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(period.block) { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.value).font(.headline.monospacedDigit())
                    Text(entry.label).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One period on its own screen: the block, and the offer to make a picture of it.
struct PeriodDetailView: View {
    let period: Period

    @State private var sharing = false

    var body: some View {
        List {
            Section {
                PeriodBlockView(period: period)
            } header: {
                Text(period.dateLine)
            } footer: {
                Text("Rates over a period divide the period's own totals — clean jibes over "
                     + "the hours those afternoons actually cost, never the average of the "
                     + "sessions' own rates.")
            }
            Section {
                Button {
                    sharing = true
                } label: {
                    Label("Share card", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(period.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $sharing) { PeriodShareView(period: period) }
    }
}
