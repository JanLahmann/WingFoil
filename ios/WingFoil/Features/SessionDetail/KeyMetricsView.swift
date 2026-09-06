import SwiftUI
import WingFoilKit

/// The KEY METRICS block: the first thing on the session, above the map and the chart.
///
/// It answers the four questions a rider has walking off the water — how long was I out,
/// how fast, how did the jibes go, how busy was it — and every one of them was already in
/// the analysis document while the screen opened on a map (`docs/app-ui-review.md` §1.1).
/// It is also the only place either app renders the turn streaks, which the engine has
/// computed since 0.4.0 and neither platform ever drew (§5.1).
///
/// Nothing is decided here: `KeyMetrics` resolves every string and the tally's three
/// counts, so this file is layout and the ladder's inks and nothing else. Same four rows,
/// same order, on the web (`web/js/render.js`).
struct KeyMetricsView: View {
    let metrics: KeyMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(metrics.basics) { cell($0) }
            }

            // The session's fastest measured window leads the row in the block's largest
            // type: it is the one number a rider quotes, and the label says which window it
            // is rather than letting "max" imply a peak sample. The two composites sit
            // beside it at the ordinary size (6 Sep 2026 — the row was "a bit empty").
            HStack(alignment: .top, spacing: 12) {
                cell(metrics.maxSpeed, font: .title.weight(.semibold))
                ForEach(metrics.speedExtras) { cell($0) }
            }

            if metrics.tally != nil || metrics.streaks != nil {
                HStack(alignment: .top, spacing: 12) {
                    if let tally = metrics.tally { tallyCell(tally) }
                    if let streaks = metrics.streaks { cell(streaks) }
                }
            }

            if !metrics.rates.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(metrics.rates) { cell($0) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    /// Number big, label small — the taste the watch review settled on and the library row
    /// already follows.
    private func cell(_ metric: KeyMetrics.Metric,
                      font: Font = .title2.weight(.semibold)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.value)
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label), \(metric.value)")
    }

    /// The outcome ladder's own three counts, in the ladder's own inks — the same
    /// `OutcomeTally` the library row draws, one type size up because here it is a
    /// headline rather than a row detail.
    private func tallyCell(_ tally: KeyMetrics.Tally) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            OutcomeTally(flewThrough: tally.flewThrough, touchdown: tally.touchdown,
                         fellIn: tally.fellIn, font: .title2)
            Text("flew · touchdown · fell — \(tally.caption)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
