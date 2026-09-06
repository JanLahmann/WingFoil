import Charts
import SwiftUI
import WingFoilKit

/// What pumping costs in heartbeats, and whether it got worse as the session went on.
///
/// Every string on this card comes from `HrCostCard` in the kit, which is where the honesty
/// rules are enforced and tested; this file is layout only. Two of those rules are visible
/// here as *structure* rather than as text:
///
/// * The whole card is behind `if let card` — `HrCostCard.make` returns nil for a session
///   with no heart rate, or with one that measured nothing, and nothing is drawn at all.
///   A card full of em-dashes would read as "measured, and it was nothing".
/// * Coverage (`23 of 23 takeoffs`) sits in the caption of every number that has a
///   denominator, because optical HR under a wetsuit drops out constantly and an average
///   over a third of the attempts is a different claim from an average over all of them.
///
/// Definitions: docs/algorithms.md "HR cost (phone)".
struct HrCostCardView: View {
    let detail: SessionDetail

    private var card: HrCostCard? { HrCostCard.make(detail.analysis.hr) }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        if let card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    // "Effort — " was the tab's name repeated into the card's, and the tab
                    // that carried it is gone (6 Sep 2026): the card sits under the takeoff
                    // tiles now, on a tab that already says Takeoffs, so the heading only
                    // has to say which half of the takeoff question this half answers.
                    Text("What pumping cost").font(.headline)
                    HelpButton(topic: .heartRate, size: .footnote)
                    Spacer()
                }
                if let warning = card.warning { patchyBanner(warning) }
                headline(card)
                if !card.bins.isEmpty { fatigue(card) }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(card.stats) { stat in
                        StatCard(title: stat.label, value: stat.value, caption: stat.caption,
                                 dimmed: stat.missing,
                                 // Orange marks a number that exists but rests on too few
                                 // measurable attempts — distinct from dimmed, which means
                                 // there is no number at all.
                                 captionColor: stat.thin ? .orange : nil)
                    }
                }
                Text(card.footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("hr")
        }
    }

    /// The coverage banner. Deliberately above the numbers rather than under them: it is a
    /// condition on how everything below should be read, and the same orange the
    /// watch-vs-phone divergence banner uses, because both say "this needs a caveat".
    private func patchyBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "waveform.path.ecg")
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private func headline(_ card: HrCostCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Takeoff cost")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(card.headlineValue)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(card.headlineMissing ? .secondary : .primary)
            Text(card.headlineCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Fatigue curve

    /// Cost per bin over the session, with the success rate under it on the same time axis.
    ///
    /// Two stacked charts rather than one: bpm and per-cent are different scales, and
    /// squeezing a 0–100 % series into a −10…+16 bpm domain would mean drawing one of them
    /// on an axis that is not shown — the sort of chart that is read wrong every time.
    /// The bins are the engine's 20-minute slices; see `HrCostCard.Bin`.
    private func fatigue(_ card: HrCostCard) -> some View {
        let domain = (card.bins.first?.startS ?? 0)...(card.bins.last?.endS ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                unmeasuredBins(card.bins)
                costBars(card.bins)
                RuleMark(y: .value("No change", 0))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(.separator))
            }
            .chartYAxisLabel("bpm")
            .chartXScale(domain: domain)
            .chartXAxis(.hidden)
            .frame(height: 110)
            .accessibilityLabel("Takeoff cost per bin")
            .accessibilityValue(card.bins.map(\.accessibilityText).joined(separator: "; "))

            Chart { successMarks(card.bins) }
            .chartYAxisLabel("% up")
            .chartYScale(domain: 0...100)
            .chartXScale(domain: domain)
            // The same round-time rule as the speed chart above it — the two are read
            // against each other on one page, so they share an axis vocabulary.
            .chartXAxis {
                AxisMarks(values: TimeAxisTicks.values(for: domain, desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) { Text(Fmt.clock(seconds)) }
                    }
                }
            }
            .frame(height: 80)
            .accessibilityLabel("Share of attempts that got up, per bin")

            if let caption = card.binCaption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = card.baselineNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    /// A bin nothing could be measured in is shaded, not skipped: an empty gap would read
    /// as "cost zero here", which is exactly the lie the whole card is built to avoid.
    @ChartContentBuilder
    private func unmeasuredBins(_ bins: [HrCostCard.Bin]) -> some ChartContent {
        ForEach(bins.filter { $0.costBpm == nil }) { bin in
            RectangleMark(xStart: .value("Bin start", bin.startS),
                          xEnd: .value("Bin end", bin.endS))
                .foregroundStyle(Color(.tertiaryLabel).opacity(0.18))
        }
    }

    /// One column per measured bin, spanning the minutes it covers.
    ///
    /// A `RectangleMark` spanning x range × y range rather than a `BarMark`: the bins are
    /// the engine's and the last one is short, so a bar has to show the minutes it actually
    /// covers (which `BarMark`'s plottable initialisers cannot express in both axes), and it
    /// has to grow from the zero line in whichever direction the cost went.
    /// A negative cost is a real result — an attempt begun while still recovering — so it
    /// goes below the line in a different colour rather than being clamped away.
    @ChartContentBuilder
    private func costBars(_ bins: [HrCostCard.Bin]) -> some ChartContent {
        ForEach(measured(bins)) { bar in
            RectangleMark(xStart: .value("Bin start", bar.startS),
                          xEnd: .value("Bin end", bar.endS),
                          yStart: .value("No change", 0),
                          yEnd: .value("Cost", bar.costBpm))
                .foregroundStyle(bar.costBpm < 0 ? Color.orange : Color.accentColor)
                .opacity(0.8)
        }
    }

    /// The success rate over the same time axis.
    @ChartContentBuilder
    private func successMarks(_ bins: [HrCostCard.Bin]) -> some ChartContent {
        ForEach(attempted(bins)) { point in
            // `series` is the run the point belongs to, so the line breaks rather than
            // being drawn straight across a stretch he attempted nothing in.
            LineMark(x: .value("Time", point.t), y: .value("Got up", point.pct),
                     series: .value("Run", point.run))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.teal)
            PointMark(x: .value("Time", point.t), y: .value("Got up", point.pct))
                .symbolSize(28)
                .foregroundStyle(Color.teal)
        }
    }

    // Chart-ready rows. The optionals are resolved *here* rather than inside the chart
    // builders: a mark that has to unwrap its own value is a mark that can be given a 0
    // by accident, which on this card is the one mistake that matters.

    private struct CostBar: Identifiable {
        let id: Int
        let startS: Double
        let endS: Double
        let costBpm: Double
    }

    private struct SuccessPoint: Identifiable {
        let id: Int
        /// Index of the unbroken run of attempted bins this point belongs to.
        let run: Int
        let t: Double
        let pct: Double
    }

    private func measured(_ bins: [HrCostCard.Bin]) -> [CostBar] {
        bins.compactMap { bin in
            bin.costBpm.map { CostBar(id: bin.id, startS: bin.startS, endS: bin.endS,
                                      costBpm: $0) }
        }
    }

    private func attempted(_ bins: [HrCostCard.Bin]) -> [SuccessPoint] {
        var out: [SuccessPoint] = []
        var run = 0
        var open = false
        for bin in bins {
            guard let pct = bin.successPct else {
                if open { run += 1 }      // the next measured bin starts a new line
                open = false
                continue
            }
            out.append(SuccessPoint(id: bin.id, run: run, t: bin.midS, pct: pct))
            open = true
        }
        return out
    }
}
