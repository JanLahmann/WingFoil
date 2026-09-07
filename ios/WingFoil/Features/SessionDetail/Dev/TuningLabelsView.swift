import SwiftUI
import WingFoilKit

// **Dev build only** — see `DevWorkbench`.
#if TUNING

/// **Settings → Tuning → Labels** — the ground truth, scored against the current analyses.
///
/// The tuning page can move a threshold; only this page can say whether moving it helped. It
/// reads every label the rider has left on a turn (`TurnLabelStore`), pairs each with the
/// verdict that session's *current* analysis gives that turn, and reports three things: how
/// often the two agree, where they disagree by kind (the confusion table), and which turns
/// those were.
///
/// **The pairing is by turn index, and that is deliberate.** A label is about a maneuver the
/// detector found; a re-tune that no longer finds it has nothing left to be right or wrong
/// about, and the entry simply drops out of the score rather than being silently re-attached to
/// whichever turn inherited the index. The count at the top says how many labels were paired,
/// so a tuning that dissolves half the corpus is visible rather than flattering.
///
/// **Opening a disagreement opens the turn, from here.** The Settings sheet sits over the
/// library and dismissing back through it to push a session would lose the reader's place on
/// this page — so the turn's own sheet is presented from this row instead, loading the session
/// on demand. Same destination as a tap on the Turns tab (`TurnDetailSheet`), one screen closer.
struct TuningLabelsView: View {
    @Environment(SessionStore.self) private var store
    @State private var labels = TurnLabelStore.shared

    /// Everything the score is computed from, rebuilt whenever the library or a label moves.
    @State private var entries: [LabelledTurn] = []
    @State private var loading = true
    /// The session a disagreement row asked to open, once its detail has been read.
    @State private var opening: OpenedTurn?
    @State private var openingFailed: String?
    @State private var csvURL: URL?
    @State private var confirmClearAll = false

    /// A turn on another session, loaded and ready to present.
    private struct OpenedTurn: Identifiable {
        let id: String
        let detail: SessionDetail
        let index: Int
    }

    private var score: TurnLabelScore { TurnLabelScoring.score(entries) }

    var body: some View {
        Form {
            summarySection
            if !entries.isEmpty {
                confusionSection
                disagreementSection
            }
            footerSection
        }
        .navigationTitle("Labels")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onChange(of: labels.totalLabels) { _, _ in Task { await reload() } }
        .sheet(item: $opening) { opened in
            TurnDetailSheet(detail: opened.detail, start: opened.index)
        }
        .alert("Could not open that session",
               isPresented: .init(get: { openingFailed != nil },
                                  set: { if !$0 { openingFailed = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openingFailed ?? "")
        }
        .confirmationDialog("Delete every label?", isPresented: $confirmClearAll,
                            titleVisibility: .visible) {
            Button("Delete \(labels.totalLabels) label"
                   + "\(labels.totalLabels == 1 ? "" : "s")", role: .destructive) {
                labels.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            if loading {
                ProgressView("Reading the labelled sessions…").font(.subheadline)
            } else if entries.isEmpty {
                Text("Nothing labelled yet. Open a turn and tap I flew, I touched or I fell — "
                     + "the label is kept on this phone and is never read by the analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(score.agreedPct.map { String(format: "%.0f %%", $0) } ?? "—")
                        .font(.title2.weight(.semibold).monospacedDigit())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("agree with the engine").font(.subheadline.weight(.medium))
                        Text(score.caption).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if labels.totalLabels != entries.count {
                    Text("\(labels.totalLabels - entries.count) label"
                         + "\(labels.totalLabels - entries.count == 1 ? "" : "s") could not be "
                         + "paired — the turn they were left on is not in the current analysis "
                         + "any more.")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                }
            }
        } header: {
            Text("Agreement")
        } footer: {
            Text("Your verdict against the engine's, over every turn you have labelled, on "
                 + "the analyses currently stored. Move a threshold in Tuning, let the library "
                 + "re-derive, and come back: this number is the answer.")
        }
    }

    /// Rows are what the rider said, columns what the engine said. The diagonal is agreement,
    /// and it is the only thing tinted — a confusion table read at a glance is read as
    /// "how much is off the diagonal".
    private var confusionSection: some View {
        Section("Confusion") {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text("").font(.caption2)
                    ForEach(TurnOutcomeKind.allCases, id: \.rawValue) { verdict in
                        Text(shortLabel(verdict)).font(.caption2.weight(.semibold))
                    }
                    Text("all").font(.caption2.weight(.semibold))
                }
                ForEach(TurnLabel.allCases, id: \.self) { label in
                    GridRow {
                        Text(label.label)
                            .font(.caption2)
                            .gridColumnAlignment(.leading)
                        ForEach(TurnOutcomeKind.allCases, id: \.rawValue) { verdict in
                            let count = score.count(label: label, verdict: verdict)
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(label.verdict == verdict
                                                 ? AnyShapeStyle(Color.accentColor)
                                                 : AnyShapeStyle(.secondary))
                        }
                        Text("\(score.labelled(label))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                GridRow {
                    Text("engine").font(.caption2).gridColumnAlignment(.leading)
                    ForEach(TurnOutcomeKind.allCases, id: \.rawValue) { verdict in
                        Text("\(score.called(verdict))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(score.total)").font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var disagreementSection: some View {
        Section {
            if score.disagreements.isEmpty {
                Text("Every label agrees with the engine.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(score.disagreements) { entry in
                    Button { Task { await open(entry) } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.sessionTitle) · \(Fmt.clock(entry.ts))")
                                .font(.caption)
                            Text("\(TurnAnalytics.typeLabel(entry.type).lowercased()) — you "
                                 + "said \(entry.label.label.lowercased()), the engine said "
                                 + entry.verdict.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Disagreements")
        } footer: {
            Text("Newest session first. Tap one to open that turn's page, with its trace and "
                 + "its evidence table.")
        }
    }

    private var footerSection: some View {
        Section {
            if let csvURL {
                ShareLink(item: csvURL) {
                    Label("Export labels as CSV", systemImage: "square.and.arrow.up")
                }
            }
            Button("Delete every label", role: .destructive) { confirmClearAll = true }
                .disabled(labels.totalLabels == 0)
        } footer: {
            Text("The CSV is one row per labelled turn — session, turn index, your label, the "
                 + "engine's verdict — the format docs/testing.md documents, so the lab can "
                 + "read it beside the goldens.")
        }
    }

    // MARK: - Loading

    /// Pairs every stored label with the verdict its session's current analysis gives.
    ///
    /// Only the sessions that carry a label are read, so the cost is the rider's own labelling
    /// effort rather than the size of his library.
    private func reload() async {
        loading = true
        defer { loading = false }
        let wanted = Set(labels.labelledSessionIDs)
        guard !wanted.isEmpty else { entries = []; csvURL = nil; return }
        let sheets = labels.sheets
        let rows = store.sessions.filter { wanted.contains($0.id) }
        let titles = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, SessionDisplay.title($0)) })
        let ingestor = store.ingestor
        let found = await Task.detached(priority: .userInitiated) { () -> [LabelledTurn] in
            var out: [LabelledTurn] = []
            for row in rows {
                guard let sheet = sheets[row.id],
                      let analysis = try? await ingestor.analysis(for: row) else { continue }
                for (key, label) in sheet.labels {
                    guard let index = Int(key), analysis.turns.indices.contains(index) else {
                        continue
                    }
                    let turn = analysis.turns[index]
                    guard turn.counted else { continue }
                    out.append(LabelledTurn(sessionID: row.id,
                                            sessionTitle: titles[row.id] ?? row.id,
                                            startDate: row.startDate, turnIndex: index,
                                            ts: turn.ts, type: turn.type,
                                            verdict: TurnOutcomeKind(turn.outcome),
                                            clean: turn.clean, label: label))
                }
            }
            return out
        }.value
        entries = found
        writeCSV(found)
    }

    private func open(_ entry: LabelledTurn) async {
        guard let row = store.session(id: entry.sessionID) else {
            openingFailed = "That session is no longer in the library."
            return
        }
        do {
            let detail = try await store.detail(for: row)
            guard detail.analysis.turns.indices.contains(entry.turnIndex) else {
                openingFailed = "That turn is not in the session's current analysis."
                return
            }
            opening = OpenedTurn(id: entry.id, detail: detail, index: entry.turnIndex)
        } catch {
            openingFailed = "\(error)"
        }
    }

    private func writeCSV(_ entries: [LabelledTurn]) {
        guard !entries.isEmpty else { csvURL = nil; return }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DevWorkbench", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("turn-labels.csv")
        guard let data = TurnLabelScoring.csv(entries).data(using: .utf8),
              (try? data.write(to: url, options: .atomic)) != nil else {
            csvURL = nil
            return
        }
        csvURL = url
    }

    private func shortLabel(_ verdict: TurnOutcomeKind) -> String {
        switch verdict {
        case .flewThrough: return "flew"
        case .touchdown: return "touch"
        case .fellIn: return "fell"
        }
    }
}

#endif
