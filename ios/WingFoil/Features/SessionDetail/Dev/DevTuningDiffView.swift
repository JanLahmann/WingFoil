import SwiftUI
import WingFoilKit

// **Dev build only** — see `DevWorkbench`.
#if TUNING

/// **What the tuning did to this session** — the Turns tab's dev block.
///
/// "Re-analysed 41 sessions with 3 tuned thresholds" is a statement about a sweep, not about a
/// rider's afternoon. This is the same fact read where it can be checked: the same session
/// analysed a second time on the published defaults (`DevWorkbench`), the two counts subtracted,
/// and — expanded — the turns that actually moved, each one a tap away from its own page.
///
/// **Absent when nothing is tuned.** With no override the two runs are the same run, and a
/// block saying "nothing changed" on every session would be noise on the one page that is
/// supposed to be about maneuvers.
struct DevTuningDiffView: View {
    let detail: SessionDetail
    /// The Turns tab's own sheet binding, so a changed turn opens the same page its row does.
    @Binding var opened: TurnDetailRequest?

    @Environment(SessionStore.self) private var store
    @State private var workbench = DevWorkbench.shared
    @State private var expanded = false

    private var base: SessionAnalysis? { workbench.baseAnalysis(for: detail) }

    var body: some View {
        Group {
            if !store.tuning.isEmpty {
                if let base {
                    card(TuningDiffBuilder.diff(tuned: detail.analysis, base: base))
                } else {
                    ProgressView("Analysing this session on the published defaults…")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: detail.row.id) { await workbench.load(detail: detail, store: store) }
    }

    private func card(_ diff: TuningDiff) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(diff.headline).font(.subheadline.weight(.semibold))
            Text("\(store.tuning.changedCount) threshold"
                 + "\(store.tuning.changedCount == 1 ? "" : "s") moved · this session only, "
                 + "computed in memory, nothing stored.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if !diff.changes.isEmpty {
                Button {
                    expanded.toggle()
                } label: {
                    Label("\(diff.changes.count) turn"
                          + "\(diff.changes.count == 1 ? "" : "s") changed",
                          systemImage: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                if expanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(diff.changes) { change in row(change) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    /// One changed turn. A `removed` turn has no page to open — the tuned run does not have it
    /// — so its row is inert and says so rather than opening the wrong maneuver.
    private func row(_ change: TuningDiff.Change) -> some View {
        Button {
            if let index = change.tunedIndex { opened = TurnDetailRequest(id: index) }
        } label: {
            HStack(spacing: 8) {
                Text(Fmt.clock(change.ts))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 46, alignment: .leading)
                Text(change.kind.label)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.16)))
                Text(change.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if change.tunedIndex == nil {
                    Text("default only").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(change.tunedIndex == nil)
    }
}

#endif
