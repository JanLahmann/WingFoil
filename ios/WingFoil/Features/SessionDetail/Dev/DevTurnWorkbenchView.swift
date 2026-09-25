import SwiftUI
import WingFoilKit

// **Dev build only** — see `DevWorkbench`.
#if TUNING

/// **The workbench block on one turn's page** — four tools under one heading, in the order a
/// question about a verdict is actually asked.
///
/// 1. *Was it right?* — the three-way ground-truth control, one tap, remembered per turn.
/// 2. *Why did it say that?* — the outcome ladder's working, step by step, on the turn's clock.
/// 3. *Would the defaults have said the same?* — the two-column what-if, where anything is tuned.
/// 4. *Show me the numbers* — one row per sample, and the same table as a CSV.
///
/// It is deliberately **one view** inserted at **one place** on `TurnDetailView`, so the merge
/// with whatever else is moving in that file is a single hunk. Everything it needs is either on
/// the `SessionDetail` it is handed or on `DevWorkbench.shared`.
///
/// **It is a screen since 19 September 2026** (pattern A, docs/review-checklist.md). It was a
/// heading called *Dev workbench* stacked under the turn page's own content, which
/// docs/presentation.md already named as if it were a screen — four tools, no title bar and
/// no way to refer to it. `DevTurnWorkbenchLink` is the row on the turn page and
/// `DevTurnWorkbenchScreen` is what it pushes; this view is unchanged inside it.
struct DevTurnWorkbenchView: View {
    let detail: SessionDetail
    /// Index into `detail.analysis.turns`.
    let index: Int

    @Environment(SessionStore.self) private var store
    @State private var workbench = DevWorkbench.shared
    @State private var labels = TurnLabelStore.shared
    @State private var showEvidence = false
    @State private var csvURL: URL?
    /// Derived once per turn rather than in `body`: rebuilding the sweep's heading series walks
    /// a whole sailing run, and a scrolling page would do it on every frame.
    @State private var trace: TurnTrace?
    @State private var rows: [TurnEvidenceRow] = []

    private var turn: TurnRecord? {
        detail.analysis.turns.indices.contains(index) ? detail.analysis.turns[index] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            labelControl
            if let trace {
                tracePanel(trace)
                whatIfCard()
                evidencePanel()
            } else {
                ProgressView("Rebuilding this session's channels…")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: taskID) { await derive() }
    }

    /// Re-runs `derive` when the session's channels land as well as when the turn changes.
    ///
    /// Reading `workbench.entry` here is what registers the observation: the turn sheet is a
    /// paging `TabView` that builds and tears down the pages either side of the one on screen,
    /// so a `.task` waiting on the shared load is routinely cancelled halfway through and its
    /// page is left on the spinner for ever. Keyed on whether the entry exists, the page simply
    /// asks again the moment it does — and the second pass finds it cached and returns at once.
    private var taskID: String {
        let loaded = workbench.entry(for: detail) != nil
        return detail.row.id + "#" + String(index) + "#" + String(loaded)
    }

    /// Loads the session's channels (once, cached) and cuts this turn's trace and table out of
    /// them. Both are pure kit calls, so they run off the main actor.
    private func derive() async {
        await workbench.load(detail: detail, store: store)
        guard let context = workbench.context(for: detail) else { return }
        let analysis = detail.analysis
        let index = self.index
        let built = await Task.detached(priority: .userInitiated) {
            (TurnTraceBuilder.trace(turnIndex: index, analysis: analysis, context: context),
             TurnEvidenceTable.rows(turnIndex: index, analysis: analysis, context: context))
        }.value
        trace = built.0
        rows = built.1
        writeCSV(built.1)
    }

    // MARK: - 1. Ground truth

    /// "I flew · I touched · I fell", plus clear. First person on purpose: this is the rider's
    /// claim about his own afternoon, not a second opinion about the engine's.
    private var labelControl: some View {
        let current = labels.label(sessionID: detail.row.id, turnIndex: index)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(TurnLabel.allCases, id: \.self) { label in
                    Button {
                        labels.set(current == label ? nil : label,
                                   sessionID: detail.row.id, turnIndex: index)
                    } label: {
                        Text(label.label)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(current == label
                                                       ? Color.accentColor.opacity(0.25)
                                                       : Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                if current != nil {
                    Button("clear") {
                        labels.set(nil, sessionID: detail.row.id, turnIndex: index)
                    }
                    .font(.caption2)
                }
                Spacer(minLength: 0)
            }
            if let current, let turn {
                let agrees = current.verdict == TurnOutcomeKind(turn.outcome)
                Text(agrees
                     ? "agrees with the engine"
                     : "disagrees. The engine said "
                        + TurnOutcomeKind(turn.outcome).label)
                    .font(.caption2)
                    .foregroundStyle(agrees ? .secondary : Color.orange)
            } else {
                Text("What actually happened, in your words. Scored against the engine in "
                     + "Settings → Tuning → Labels. Never read by the analysis.")
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 2. Why this verdict

    private func tracePanel(_ trace: TurnTrace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Why this verdict").font(.subheadline.weight(.semibold))
                if trace.disagreements > 0 {
                    Label("\(trace.disagreements) disagree",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                }
                Spacer(minLength: 0)
            }
            ForEach(trace.steps) { step in traceRow(step) }
            if !trace.assumedDefaults.isEmpty {
                Text("This analysis was stored before "
                     + trace.assumedDefaults.joined(separator: ", ")
                     + " were echoed, so the published defaults are assumed above. Re-analyse "
                     + "the session to read the real values.")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Seconds count from the sweep's start. The strip above uses the same clock.")
                .font(.caption2)
                .foregroundStyle(.readableSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private func traceRow(_ step: TurnTrace.Step) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(step.atRt.map { String(format: "%+.0f s", $0) } ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.readableSecondary)
                .scaledColumn(44, alignment: .trailing, relativeTo: .caption2)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title).font(.caption.weight(.medium))
                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                switch step.note {
                case .disagrees(let derived, let record):
                    Text("re-derived " + derived + ", the record says " + record)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.orange)
                case .assumed(let parameter):
                    Text(parameter + " was not echoed. Published default assumed")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                case .none:
                    EmptyView()
                }
                if let rule = step.rule {
                    Text(rule).font(.caption2.monospaced()).foregroundStyle(.readableSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 3. What-if

    @ViewBuilder
    private func whatIfCard() -> some View {
        // This session's own rig, and no other: the comparison below is the tuned run against
        // its own preset, so it is the *fin* set that decides whether a fin session has
        // anything to compare with.
        if store.tuning[detail.row.analysisDiscipline].isEmpty {
            let discipline = detail.row.analysisDiscipline.title.lowercased()
            Text(markdown: "Nothing is tuned for " + discipline
                 + ", so the preset defaults *are* what you are looking at.")
                .font(.caption2)
                .foregroundStyle(.readableSecondary)
        } else if let card = TurnWhatIf.make(turnIndex: index, tuned: detail.analysis,
                                             base: workbench.baseAnalysis(for: detail)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tuned vs published defaults").font(.subheadline.weight(.semibold))
                if let base = card.base {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text("").font(.caption2)
                            Text("tuned").font(.caption2.weight(.semibold))
                            Text("default").font(.caption2.weight(.semibold))
                        }
                        whatIfRow("verdict", card.tuned.verdict.label, base.verdict.label)
                        whatIfRow("clean", card.tuned.clean ? "yes" : "no",
                                  base.clean ? "yes" : "no")
                        whatIfRow("score",
                                  String(format: "%.0f %%", card.tuned.score * 100),
                                  String(format: "%.0f %%", base.score * 100))
                        whatIfRow("in / low / out",
                                  speeds(card.tuned), speeds(base))
                        whatIfRow("outcome window",
                                  String(format: "%.0f s", card.tuned.outcomeWindowS),
                                  String(format: "%.0f s", base.outcomeWindowS))
                    }
                    if card.identical {
                        Text("Identical. The thresholds you moved did not touch this turn.")
                            .font(.caption2)
                            .foregroundStyle(.readableSecondary)
                    }
                } else if workbench.entry(for: detail)?.complete == true {
                    Text("The published defaults find no turn here at all. Your tuning "
                         + "discovered this maneuver.")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().font(.caption2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
        }
    }

    private func speeds(_ column: TurnWhatIf.Column) -> String {
        String(format: "%.1f → %.1f → %.1f", column.entryKn, column.minKn, column.exitKn)
    }

    private func whatIfRow(_ label: String, _ tuned: String, _ base: String) -> some View {
        GridRow {
            Text(label).font(.caption2).foregroundStyle(.readableSecondary)
            Text(tuned).font(.caption.monospacedDigit())
            Text(base)
                .font(.caption.monospacedDigit())
                .foregroundStyle(tuned == base ? AnyShapeStyle(.secondary)
                                 : AnyShapeStyle(Color.orange))
        }
    }

    // MARK: - 4. The evidence table

    private func evidencePanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    showEvidence.toggle()
                } label: {
                    Label("Evidence · " + String(rows.count) + " samples",
                          systemImage: showEvidence ? "chevron.down" : "chevron.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Image(systemName: "square.and.arrow.up").font(.caption)
                    }
                }
            }
            if showEvidence {
                // Horizontal only, and **no height cap**. A nested vertical scroll view inside
                // the page's own would either fight it for the drag or — with a fixed height —
                // clip the forty-odd rows it cannot scroll. The table simply extends the page,
                // which is what a reader walking down a turn's samples wants anyway.
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        evidenceHeader
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            evidenceRow(row)
                        }
                    }
                }
                let lead = String(Int(TurnEvidenceTable.leadS))
                let trail = String(Int(TurnEvidenceTable.trailS))
                // Built in a local: one `+` chain long enough to carry the whole caption is
                // what the type checker gives up on inside a ViewBuilder.
                let span = "−" + lead + " s to +" + trail + " s "
                    + "around the sweep, tinted by the window each sample falls in. "
                let gap = "A row marked ⌁ is the far side of a recording gap, where every "
                    + "window in the engine stops."
                Text(span + gap)
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var evidenceHeader: some View {
        HStack(spacing: 8) {
            cell("t", width: 54)
            cell("dop", width: 40)
            cell("man", width: 40)
            cell("hdg", width: 40)
            cell("°/s", width: 40)
            cell("twa", width: 42)
            cell("fly", width: 26)
            cell("stop", width: 30)
            cell("wet", width: 26)
            cell("pump", width: 34)
            cell("band", width: 52)
        }
        .font(.caption2.weight(.semibold).monospaced())
        .foregroundStyle(.readableSecondary)
        .padding(.vertical, 3)
    }

    private func evidenceRow(_ row: TurnEvidenceRow) -> some View {
        HStack(spacing: 8) {
            cell((row.gapBefore ? "⌁" : "") + String(format: "%+.0f", row.rt), width: 54)
            cell(String(format: "%.1f", row.dopplerKn), width: 40)
            cell(String(format: "%.1f", row.manoeuvreKn), width: 40)
            cell(row.headingDeg.map { String(format: "%.0f", $0) } ?? "·", width: 40)
            cell(row.turnRateDegS.map { String(format: "%+.0f", $0) } ?? "·", width: 40)
            cell(row.twaDeg.map { String(format: "%+.0f", $0) } ?? "·", width: 42)
            cell(row.flying ? "✓" : "·", width: 26)
            cell(row.stopped ? "✓" : "·", width: 30)
            cell(row.submerged ? "✓" : "·", width: 26)
            cell(row.pumpStrokes > 0 ? "\(row.pumpStrokes)" : "·", width: 34)
            cell(row.band.label, width: 52)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.vertical, 1)
        .background(Self.tint(row.band))
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .scaledColumn(width, alignment: .trailing, relativeTo: .caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// One tint per window, all of them faint: this is a table, not a chart, and the colour is
    /// there to group rows rather than to be read as a value.
    static func tint(_ band: TurnEvidenceRow.Band) -> Color {
        switch band {
        case .entry: return Color.blue.opacity(0.10)
        case .sweep: return Color.accentColor.opacity(0.16)
        case .minLag: return Color.purple.opacity(0.10)
        case .outcome: return Color.orange.opacity(0.10)
        case .quietTail: return Color.green.opacity(0.08)
        case .none: return .clear
        }
    }

    /// The same table, in `tmp/`, ready for the share sheet. Rewritten whenever the row count
    /// changes, which is once per turn.
    private func writeCSV(_ rows: [TurnEvidenceRow]) {
        guard !rows.isEmpty else { csvURL = nil; return }
        let name = TurnEvidenceTable.filename(session: SessionDisplay.title(detail.row),
                                              turnIndex: index)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DevWorkbench", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        guard let data = TurnEvidenceTable.csv(rows).data(using: .utf8),
              (try? data.write(to: url, options: .atomic)) != nil else {
            csvURL = nil
            return
        }
        csvURL = url
    }
}

/// **The workbench's name**, in one place: the row on the turn page and the title of the
/// screen it pushes say the same three words.
///
/// Not plain "Tuning": Settings → **Tuning** is the 27 sliders, and two screens with one name
/// is the pattern this rename exists to remove. This one is the sliders applied to *this
/// turn* — was the verdict right, why did the ladder say so, would the defaults have agreed.
enum DevTurnWorkbench {
    static let screenTitle = "Tuning this turn"
}

/// The door on the turn page. A row rather than the block itself, because the four tools are
/// a page of their own and the turn page is already four screens tall.
struct DevTurnWorkbenchLink: View {
    let detail: SessionDetail
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            NavigationLink {
                DevTurnWorkbenchScreen(detail: detail, index: index)
            } label: {
                Label(DevTurnWorkbench.screenTitle, systemImage: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}

/// The workbench, on a page with a title bar.
struct DevTurnWorkbenchScreen: View {
    let detail: SessionDetail
    let index: Int

    var body: some View {
        ScrollView {
            DevTurnWorkbenchView(detail: detail, index: index)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .readableColumn()
        }
        .navigationTitle(DevTurnWorkbench.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#endif
