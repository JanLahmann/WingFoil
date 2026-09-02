// No `import Charts` any more: the per-row sparkline is gone (see the note below the row).
import SwiftUI
import UIKit
import WingFoilKit

/// All-time GP3S personal bests in knots (plan §3.3 "Records: all-time/per-spot/per-gear,
/// kn"), each row backed by the `record_effort` history: the sparkline is every session's
/// effort for that kind, the highlighted step is the PB that stands today.
///
/// A record beaten by the most recent import arrives here flagged, and gets the one
/// celebration the app has: a confetti burst and a haptic, once, on the screen where the
/// number actually lives.
struct RecordsView: View {
    @Environment(SessionStore.self) private var store

    @State private var filter = LibraryFilter()
    @State private var records: [RecordBest] = []
    @State private var loaded = false
    @State private var confetti: Int?
    /// Kinds beaten by the last import, so their rows can say so.
    @State private var freshlyBeaten: Set<RecordKind> = []
    /// The clean-jibe records beaten by the same import (engine 0.10.0). They have no row in
    /// a table of knots, so they get a line of their own above it — a burst nobody can read
    /// is a burst nobody believes.
    @State private var freshCleanJibes: [NewCleanJibeBest] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LibraryFilterBar(filter: $filter)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listRowBackground(Color.clear)

                if !freshCleanJibes.isEmpty {
                    Section { cleanJibeBanner }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16,
                                                  bottom: 8, trailing: 16))
                }

                if records.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        recordsHeader
                            .listRowInsets(EdgeInsets(top: 4, leading: 16,
                                                      bottom: 4, trailing: 16))
                        ForEach(records) { best in
                            NavigationLink(value: best.sessionId) {
                                RecordRowView(best: best, title: title(of: best.sessionId),
                                              isNew: freshlyBeaten.contains(best.kind))
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16,
                                                      bottom: 6, trailing: 16))
                        }
                    } footer: {
                        Text(footnote)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Records")
            .navigationDestination(for: String.self) { SessionDetailView(sessionID: $0) }
            .refreshable { await reload() }
            .task(id: reloadKey) { await reload() }
            .task(id: store.celebrationCount) { celebrateIfNeeded() }
            .overlay { ConfettiBurst(trigger: confetti) }
            #if DEBUG && targetEnvironment(simulator)
            // Headless-driving hook: a real burst needs an import that beats a standing
            // record, which an automated screenshot run cannot stage. `UI_CONFETTI=1`
            // fires the same burst against the first two records.
            .task {
                guard ProcessInfo.processInfo.environment["UI_CONFETTI"] == "1" else { return }
                // Wait for the query rather than guessing at a delay, or the burst races
                // the reload and fires against an empty record list.
                for _ in 0..<40 where records.isEmpty {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                freshlyBeaten = Set(records.prefix(2).map(\.kind))
                confetti = (confetti ?? 0) + 1
            }
            #endif
        }
    }

    /// Any of these changing means the query has to run again.
    private var reloadKey: String {
        "\(filter.spotId ?? "-")|\(filter.gearId ?? "-")|\(store.libraryGeneration)"
    }

    /// One burst per import, on arrival at the screen that owns the number.
    ///
    /// **One burst for both kinds.** A speed record and a clean-jibe record are the same
    /// moment to a rider — "that was my best ever" — and two confetti bursts in a row would
    /// make the second one furniture. The line above the table says which it was.
    private func celebrateIfNeeded() {
        let beaten = store.celebration
        let clean = store.cleanJibeCelebration
        guard !beaten.isEmpty || !clean.isEmpty else { return }
        freshlyBeaten = Set(beaten.map(\.kind))
        freshCleanJibes = clean
        confetti = (confetti ?? 0) + 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.clearCelebration()
    }

    /// What the clean-jibe half of the celebration was, in the words the rest of the app
    /// uses for it. Not a row in the table: the table is knots, and a count of jibes in a
    /// column headed "kn" would be the one thing a records screen may never do.
    private var cleanJibeBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("New personal best", systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.green)
            ForEach(freshCleanJibes) { best in
                Text(best.headline)
                    .font(.subheadline.weight(.medium))
            }
            Text("Your best afternoon of clean jibes — the jibes you flew all the way "
                 + "through carrying your speed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(loaded ? "No records yet" : "Loading…", systemImage: "trophy")
        } description: {
            Text(store.sessions.isEmpty
                 ? "Import or sync a session and its speed records appear here."
                 : "No qualifying speed window under this filter.")
        }
    }

    /// The table's column names. A header row rather than four repeated labels down the
    /// page: naming a column once is the whole economy a table buys.
    private var recordsHeader: some View {
        HStack(spacing: 10) {
            Text("record").frame(width: 66, alignment: .leading)
            Text("kn").frame(width: 58, alignment: .trailing)
            Text("+Δ PB").frame(width: 56, alignment: .trailing)
            Text("when · where").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }

    private var footnote: String {
        let certified = records.filter(\.certified).count
        return "Doppler speed, GP3S windows. \(certified) of \(records.count) from certified "
            + "sources (a recording device's own speed channel); class (c) sources are "
            + "marked. The dot on the record's "
            + "name says how fresh it is — filled within a month, hollow within the season, "
            + "faint when it is older than six months."
    }

    private func title(of sessionID: String) -> String {
        store.session(id: sessionID).map(SessionDisplay.title) ?? "Session"
    }

    private func reload() async {
        records = (try? await store.library.records(filter)) ?? []
        loaded = true
    }
}

/// One record, as a table row.
///
/// It was a ~245 pt card: a gold gradient disc containing the same text as the label beside
/// it, the value, a provenance line, a PB delta, and a ~90 px sparkline that at that width
/// read as a flat line with a bump on all eight rows. Eight of them was about 2 000 pt of
/// scroll — two full screens for eight numbers — and the genuinely good content, `+1.27 kn
/// on the previous best`, was the smallest text in the row (`app-ui-review.md` §6.2).
///
/// So: `record | value | +Δ PB | when · where`, on one line, under a header that names the
/// columns once. The disc is gone (it duplicated the title), the sparkline is gone (at 90 px
/// it carried no information, and widening it into a real PB step curve is the job of the
/// detail page the row still pushes to). What survives is what the row was for — the eight
/// values in a column, where the eye can compare them.
///
/// The medal's *information* survives without its decoration: freshness is now a small dot
/// beside the record's name, filled / hollow / faint. It is a fact worth keeping — a 2 s
/// from three seasons ago is a fact about a day, not about form — and it costs 9 pt instead
/// of 44.
private struct RecordRowView: View {
    let best: RecordBest
    let title: String
    var isNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    FreshnessDot(age: Medal.of(best.achievedAt))
                    Text(best.kind.label)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 66, alignment: .leading)

                Text(Fmt.kn(best.valueKn))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .frame(width: 58, alignment: .trailing)

                // The delta was the smallest text in the old row and it is the reason a
                // rider opens this screen: it is a column of its own now.
                Group {
                    if let previous = best.previousBest {
                        Text(String(format: "+%.2f", best.valueKn - previous))
                            .foregroundStyle(DesignTokens.Outcome.flew)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .font(.caption.monospacedDigit())
                .frame(width: 56, alignment: .trailing)

                Text("\(Fmt.shortDate(best.achievedAt, zone: best.displayZone)) · \(title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The two badges are exceptions rather than columns — a column that is empty on
            // seven rows out of eight is a column that should not exist — so they wrap onto
            // a second line only on the rows that have one.
            if isNew || !best.certified || best.history.count == 1 {
                HStack(spacing: 6) {
                    Spacer().frame(width: 66)
                    if isNew { badge("NEW", Color.accentColor) }
                    if !best.certified { badge("uncertified", .orange) }
                    if best.previousBest == nil, best.history.count == 1 {
                        Text("first session with this record")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(best.kind.label) record, \(Fmt.kn(best.valueKn))")
        .accessibilityValue(Medal.of(best.achievedAt).label)
    }

    private func badge(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(tint.opacity(0.18), in: .capsule)
            .foregroundStyle(tint)
    }
}

/// How fresh a standing record is, in 9 points instead of a 44 pt gradient disc. Filled,
/// hollow and faint rather than gold, silver and bronze: three shades of metal at 9 px are
/// three shades of grey, and a filled/hollow pair is legible without colour vision at all.
private struct FreshnessDot: View {
    let age: Medal

    var body: some View {
        Group {
            switch age {
            case .gold: Circle().fill(Color.accentColor)
            case .silver: Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
            case .bronze: Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
            }
        }
        .frame(width: 7, height: 7)
        .accessibilityHidden(true)
    }
}

/// How fresh a standing record is. It answers "which of my PBs still mean something" — a
/// 2 s from three seasons ago is a fact about a day, not about form.
///
/// The three brushed-metal gradients it used to carry went with the disc they filled; the
/// distinction they encoded did not, because it is the only thing on the row that a value
/// and a date cannot say. `FreshnessDot` draws it in 7 pt.
enum Medal {
    case gold, silver, bronze

    static func of(_ achievedAt: Date, now: Date = Date()) -> Medal {
        let days = now.timeIntervalSince(achievedAt) / 86400
        if days <= 30 { return .gold }
        if days <= 183 { return .silver }
        return .bronze
    }

    var label: String {
        switch self {
        case .gold: "set within the last month"
        case .silver: "set this season"
        case .bronze: "older than six months"
        }
    }
}

// The medal disc and the per-row PB sparkline used to live here and are deliberately gone
// (app-ui-review.md §6.2). The disc contained the same text as the label beside it — "2 s"
// struck into a gold gradient, next to a title reading "2 s" — so it was 44 pt of
// duplication; and the sparkline was ~90 px wide, at which width all eight rows read as a
// flat line with a bump, so it was decoration wearing the clothes of a chart. The PB
// history is still in `record_effort` and `RecordBest.personalBests` still carries it: a
// step curve drawn at a width where it means something belongs on a record detail screen,
// not eight times over in a list. What the rows kept is the number that curve was there to
// imply — `+Δ PB`, which had been the smallest text in the row and is now a column.
