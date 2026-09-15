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
    /// The second table: all-time bests that are not speeds. Same filter, same tie rule,
    /// no certification — see `SessionRecordKind`.
    @State private var sessionRecords: [SessionRecordBest] = []
    @State private var loaded = false
    @State private var confetti: Int?
    /// Kinds beaten by the last import, so their rows can say so.
    @State private var freshlyBeaten: Set<RecordKind> = []
    /// The clean-jibe records beaten by the same import (engine 0.10.0). They have no row in
    /// a table of knots, so they get a line of their own above it — a burst nobody can read
    /// is a burst nobody believes.
    @State private var freshCleanJibes: [NewCleanJibeBest] = []

    /// Whether the speed table is still a table — see `RecordRowView`.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LibraryFilterBar(filter: $filter)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    #if TUNING
                    // An all-time record is the app's strongest claim, and it is the one place
                    // a tuned threshold is easiest to forget: the table looks exactly the same.
                    // The chip reads the *current* setting rather than any one session's,
                    // because this page is an aggregate over the whole library — and for the
                    // same reason it counts every discipline's set, not the one that happens
                    // to be selected on the tuning page: a library with one fin session in it
                    // has a record that was measured at the fin's thresholds.
                    if !store.tuning.isEmpty {
                        TunedChip(count: store.tuning.totalChangedCount)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16,
                                                      bottom: 8, trailing: 16))
                    }
                    #endif
                }
                .listRowBackground(Color.clear)

                if !freshCleanJibes.isEmpty {
                    Section { cleanJibeBanner }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16,
                                                  bottom: 8, trailing: 16))
                }

                if records.isEmpty && sessionRecords.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if !records.isEmpty {
                    Section {
                        // Absent, not empty, at an accessibility text size: the rows are no
                        // longer columns there, so an empty list row with a separator would
                        // be the only thing left of the header.
                        if !typeSize.isAccessibilitySize {
                            recordsHeader
                                .listRowInsets(EdgeInsets(top: 4, leading: 16,
                                                          bottom: 4, trailing: 16))
                                // Header and rows share one ceiling — see `RecordRowView`.
                                .denseRowTypeSizeCap()
                        }
                        ForEach(records) { best in
                            NavigationLink(value: best.sessionId) {
                                RecordRowView(best: best, title: title(of: best.sessionId),
                                              isNew: freshlyBeaten.contains(best.kind))
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16,
                                                      bottom: 6, trailing: 16))
                            // Four columns — name, knots, +Δ, when · where — and the fourth
                            // is a sentence. They scale to `.accessibility2`, which is the
                            // last size at which four columns are still four columns on a
                            // phone. The Session records table below has no fixed columns
                            // and is left to scale the whole way.
                            .denseRowTypeSizeCap()
                        }
                    } header: {
                        Text("Speed records")
                    } footer: {
                        Text(footnote)
                    }
                }
                if !sessionRecords.isEmpty {
                    Section {
                        ForEach(sessionRecords) { best in
                            NavigationLink(value: best.sessionId) {
                                SessionRecordRowView(best: best,
                                                     title: title(of: best.sessionId))
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16,
                                                      bottom: 6, trailing: 16))
                        }
                    } header: {
                        Text("Session records")
                    } footer: {
                        Text("Best afternoons rather than best windows. No certification "
                             + "applies here: a degraded recording can misreport a speed, "
                             + "but the number of jibes it holds and the minutes it lasted "
                             + "are not claims its speed channel makes.")
                    }
                }
                FeedbackFooter.section
            }
            .listStyle(.insetGrouped)
            // Two tables of "a number, a session and a date". Left to fill an iPad they put
            // the knots and the afternoon they were ridden on opposite edges of the glass.
            .readableColumn()
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
            Text("Your best afternoon of clean jibes. Clean: you flew all the way "
                 + "through and held your speed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Three empty screens, not one.
    ///
    /// **The middle one was the bug** (15 Sep 2026): a rider who took the one-tap path —
    /// install, *Try the example session* — landed here and was told there was "no
    /// qualifying speed window under this filter" with no filter set. The example is kept
    /// out of personal records on purpose (`LibraryStore.clause`), and nothing on this
    /// screen said so or could be changed to fix it. `ExampleOnlyNote` is that fact in the
    /// rider's words with the step that changes it; the filter sentence stays for the case
    /// it was written for, which is a filter that really is set.
    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "trophy")
        } description: {
            Text(store.sessions.isEmpty
                 ? "Import or sync a session and its speed records appear here."
                 : store.hasOnlyExampleSessions
                   ? ExampleOnlyNote.records
                   : "No qualifying speed window under this filter.")
        }
    }

    private var emptyTitle: String {
        guard loaded else { return "Loading…" }
        return store.hasOnlyExampleSessions ? ExampleOnlyNote.recordsTitle : "No records yet"
    }

    private var recordsHeader: some View { RecordTableHeader() }

    private var footnote: String {
        let certified = records.filter(\.certified).count
        // "Uncertified" is the rider's word for a class-(c) GP3S source: a recording with
        // no Doppler speed channel of its own. It is the badge the row already wears.
        let head = "Doppler speed, GP3S windows. " + String(certified) + " of "
            + String(records.count) + " come from certified sources. "
        let tail = "A certified source is the recording device's own speed channel. "
            + "Uncertified sources are marked. "
            + "The dot on a record's name says how fresh it is. "
            + "Filled within a month. Hollow within the season. "
            + "Faint when it is older than 6 months."
        return head + tail
    }

    private func title(of sessionID: String) -> String {
        store.session(id: sessionID).map(SessionDisplay.title) ?? "Session"
    }

    private func reload() async {
        records = (try? await store.library.records(filter)) ?? []
        sessionRecords = (try? await store.library.sessionRecords(filter)) ?? []
        loaded = true
    }
}

/// One session record, as a table row.
///
/// Not the speed table's four columns: those labels are two characters wide ("2 s", "1 NM")
/// and these are phrases, so a fixed 66 pt name column would truncate every one of them.
/// The value keeps the right edge, which is what makes the column of numbers scannable —
/// that was the point of the speed table's geometry and it survives here without it.
private struct SessionRecordRowView: View {
    let best: SessionRecordBest
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(best.kind.label)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            Text(provenance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let note = best.kind.caption {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(best.kind.label), \(value)")
        .accessibilityValue(provenance)
    }

    /// The date and session, plus the one fact a duration cannot carry: how far the longest
    /// flight actually went. Six minutes downwind and six minutes of pumping in a lull are
    /// not the same flight.
    private var provenance: String {
        let stamp = Fmt.shortDate(best.achievedAt, zone: best.displayZone) + " · " + title
        guard let metres = best.distanceM else { return stamp }
        return String(Int(metres.rounded())) + " m · " + stamp
    }

    private var value: String {
        switch best.kind.unit {
        // A **session** duration follows the block's rule (`10:45 min` / `1:57 h`), so the
        // record and the session page it opens print the same string. A *flight* keeps the
        // long spelling: it is a clip-scale clock, minutes and seconds by design, and
        // "6 m 12 s" is how the flight table and the replay caption already say it.
        case .seconds:
            best.kind == .longestSession ? KeyMetrics.duration(best.value)
                                         : Fmt.duration(best.value)
        case .count: "\(Int(best.value.rounded()))"
        case .percent: String(format: "%.1f %%", best.value)
        case .perHour: String(format: "%.2f / h", best.value)
        case .km: String(format: "%.2f km", best.value)
        }
    }
}

/// **The speed table's column widths**, in one place because the header and every row have
/// to agree on them to the point.
///
/// They are constants on a phone and were constants everywhere, which is what made `Best
/// 5×10 s` read as `Best 5×…` — a 66 pt column truncates the two longest record names at
/// any screen width, and on an iPad it did it with 300 pt of empty "when · where" beside it.
/// The three fixed columns are the scannable part of the table, so on an iPad-sized window
/// they get the room to print what they are rather than the room a 390 pt phone could spare.
private struct RecordColumns {
    let name: CGFloat
    let value: CGFloat
    let delta: CGFloat

    static let phone = RecordColumns(name: 66, value: 58, delta: 56)
    static let wide = RecordColumns(name: 112, value: 78, delta: 64)

    init(name: CGFloat, value: CGFloat, delta: CGFloat) {
        self.name = name
        self.value = value
        self.delta = delta
    }

    init(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) {
        self = SizeClass.isWideScreen(horizontal, vertical) ? .wide : .phone
    }
}

/// The table's column names. A header row rather than four repeated labels down the page:
/// naming a column once is the whole economy a table buys.
private struct RecordTableHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// **No header at an accessibility text size.** `RecordRowView` stops being four columns
    /// there (see its note), so there are no columns left to name, and a row of names that
    /// line up with nothing reads as a fourth kind of number.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = RecordColumns(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
        if !typeSize.isAccessibilitySize {
            HStack(spacing: 10) {
                Text("record").scaledColumn(columns.name, relativeTo: .subheadline)
                Text("kn")
                    .scaledColumn(columns.value, alignment: .trailing, relativeTo: .subheadline)
                Text("+Δ PB")
                    .scaledColumn(columns.delta, alignment: .trailing, relativeTo: .caption)
                Text("when · where").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// **Four columns is a table until the type gets big, and then it is not one.** Three
    /// fixed columns and a sentence take more than a phone's width at an accessibility text
    /// size however well the columns scale, and the row came out clipped at both edges with
    /// "when · where" squeezed to two characters. Past the threshold the row gives the table
    /// up honestly: the name takes the width it needs, the two numbers keep the right edge —
    /// which is what made a column of values scannable in the first place — and the
    /// provenance moves to a line of its own. It is the shape `SessionRecordRowView` below
    /// already uses, for the same reason its own note gives.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var stacked: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        let columns = RecordColumns(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    FreshnessDot(age: Medal.of(best.achievedAt))
                    Text(best.kind.label)
                        .font(.subheadline)
                        .lineLimit(stacked ? 2 : 1)
                        .minimumScaleFactor(0.8)
                }
                .scaledColumn(stacked ? nil : columns.name, relativeTo: .subheadline)

                if stacked { Spacer(minLength: 6) }

                Text(Fmt.kn(best.valueKn))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                    .scaledColumn(stacked ? nil : columns.value, alignment: .trailing,
                                  relativeTo: .subheadline)

                // The delta was the smallest text in the old row and it is the reason a
                // rider opens this screen: it is a column of its own now.
                if !stacked { delta }

                if !stacked { provenance }
            }
            // Stacked, the delta leads the second line: the name and the value fill the
            // first one at these sizes, and "+1.27" in front of the date reads as what it
            // is — how much this record beat the last one by, and when.
            if stacked {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    delta
                    provenance
                }
            }
            // The two badges are exceptions rather than columns — a column that is empty on
            // seven rows out of eight is a column that should not exist — so they wrap onto
            // a second line only on the rows that have one.
            if isNew || !best.certified || best.history.count == 1 {
                HStack(spacing: 6) {
                    if !stacked { Spacer().scaledColumn(columns.name, relativeTo: .subheadline) }
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

    /// How much this record beat the previous one by — the third column, or, stacked, the
    /// head of the second line.
    private var delta: some View {
        Group {
            if let previous = best.previousBest {
                Text(String(format: "+%.2f", best.valueKn - previous))
                    .foregroundStyle(DesignTokens.Outcome.flew)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .scaledColumn(stacked ? nil : RecordColumns(horizontal: horizontalSizeClass,
                                                    vertical: verticalSizeClass).delta,
                      alignment: .trailing, relativeTo: .caption)
    }

    /// When and where the record was set — the fourth column, or the second line.
    private var provenance: some View {
        Text(Fmt.shortDate(best.achievedAt, zone: best.displayZone) + " · " + title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(stacked ? 3 : 1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
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
