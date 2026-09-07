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
            Divider()
            Text("Dev workbench")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

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
        "\(detail.row.id)#\(index)#\(workbench.entry(for: detail) != nil)"
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
                     : "disagrees — the engine said "
                        + TurnOutcomeKind(turn.outcome).label)
                    .font(.caption2)
                    .foregroundStyle(agrees ? .secondary : Color.orange)
            } else {
                Text("What actually happened, in your words — scored against the engine in "
                     + "Settings → Tuning → Labels. Never read by the analysis.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
            Text("Seconds are from the sweep's start — the same clock as the strip above.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private func traceRow(_ step: TurnTrace.Step) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(step.atRt.map { String(format: "%+.0f s", $0) } ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title).font(.caption.weight(.medium))
                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                switch step.note {
                case .disagrees(let derived, let record):
                    Text("re-derived \(derived), the record says \(record)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.orange)
                case .assumed(let parameter):
                    Text("\(parameter) was not echoed — published default assumed")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                case .none:
                    EmptyView()
                }
                if let rule = step.rule {
                    Text(rule).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 3. What-if

    @ViewBuilder
    private func whatIfCard() -> some View {
        if store.tuning.isEmpty {
            Text("Nothing is tuned, so the published defaults *are* what you are looking at.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
                        Text("Identical — the thresholds you moved did not touch this turn.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else if workbench.entry(for: detail)?.complete == true {
                    Text("The published defaults find no turn here at all — this maneuver is "
                         + "one your tuning discovered.")
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
            Text(label).font(.caption2).foregroundStyle(.tertiary)
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
                    Label("Evidence · \(rows.count) samples",
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
                Text("−\(Int(TurnEvidenceTable.leadS)) s to +\(Int(TurnEvidenceTable.trailS)) s "
                     + "around the sweep, tinted by the window each sample falls in. "
                     + "A row marked ⌁ is the far side of a recording gap, where every window "
                     + "in the engine stops.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
        .foregroundStyle(.tertiary)
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
        Text(text).frame(width: width, alignment: .trailing).lineLimit(1)
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

#endif
