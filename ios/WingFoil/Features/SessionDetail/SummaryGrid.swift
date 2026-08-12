import SwiftUI
import WingFoilKit

/// Foil/flight summary, GP3S records, the turn/flight-end outcome split, and the takeoff
/// & pumping card. Records that the session could not produce (no qualifying run) stay
/// visible with an explicit placeholder rather than disappearing — the absence is
/// information, and so is a nil stroke count on a source with no accelerometer.
struct SummaryGrid: View {
    let detail: SessionDetail
    /// Which record effort is currently highlighted on the map and chart.
    @Binding var selectedEffort: String?

    private var summary: SessionSummary { detail.analysis.summary }
    private var records: GP3SRecords { detail.analysis.records }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Foil", help: .foilPct) {
                StatCard(title: "Foil time", value: Fmt.pct(summary.foilPct),
                         caption: Fmt.duration(summary.foilTimeS), help: .foilPct)
                StatCard(title: "Flights", value: "\(summary.flightCount)",
                         caption: summary.flightCount == 0 ? "none detected" : "detected",
                         help: .flights)
                StatCard(title: "Longest flight",
                         value: Fmt.duration(summary.longestFlightS),
                         caption: Fmt.meters(summary.longestFlightM), help: .longestFlight)
                StatCard(title: "Distance", value: Fmt.km(summary.distanceKm),
                         caption: Fmt.duration(detail.durationS) + " elapsed",
                         help: .distance)
            }

            speedRecords
            turns
            takeoff
        }
    }

    // MARK: - Records

    private var speedRecords: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Speed records").font(.headline)
                // The cards themselves are buttons (tap to locate the effort on the map),
                // so the `?` lives on the heading rather than nested inside them — a
                // button inside a button swallows the outer tap.
                HelpButton(topic: .recordSet, size: .footnote)
                Spacer()
                if !detail.efforts.isEmpty {
                    Text("tap to locate").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            LazyVGrid(columns: columns, spacing: 12) {
                record("Best 2 s", records.best2sKn, window: "best2s")
                record("Best 10 s", records.best10sKn, window: "best10s")
                record("5 × 10 s", records.best5x10sKn, window: "best5x10s")
                record("Best 500 m", records.best500mKn, window: "best500m")
                record("Alpha 500", records.alpha500Kn, window: "alpha500")
                record("Best 1 NM", records.bestNmKn, window: "bestNm")
            }
        }
    }

    private func record(_ title: String, _ value: Double?, window: String) -> some View {
        let locatable = detail.efforts.contains { $0.id == window }
        return Button {
            guard locatable else { return }
            selectedEffort = selectedEffort == window ? nil : window
        } label: {
            StatCard(title: title,
                     value: Fmt.kn(value),
                     caption: value == nil ? "no qualifying run"
                                           : caption(for: records.windows[window]),
                     dimmed: value == nil,
                     highlighted: selectedEffort == window)
        }
        .buttonStyle(.plain)
        .disabled(!locatable)
    }

    private func caption(for window: RecordWindow?) -> String {
        guard let window else { return " " }
        return "at \(Fmt.clock(window.startTs)) · \(Fmt.duration(window.durS))"
    }

    // MARK: - Turns & flight ends

    @ViewBuilder
    private var turns: some View {
        let t = summary.turns
        let split = summary.outcomeSplit
        if t.turnsCounted > 0 || t.rejected > 0 || summary.flightEnds.all.total > 0 {
            section("Turns & losses", help: .turnOutcomes) {
                StatCard(title: "Jibes", value: "\(t.jibes)",
                         caption: outcomeCaption(t.jibeOutcomes), help: .turnTypes)
                StatCard(title: "Tacks", value: "\(t.tacks)",
                         caption: outcomeCaption(t.tackOutcomes), help: .turnTypes)
                if t.unclassified > 0 {
                    StatCard(title: "Unclassified turns", value: "\(t.unclassified)",
                             caption: "no usable wind axis", help: .windAxis)
                }
                StatCard(title: "Carried through",
                         value: Fmt.pct(t.successPct),
                         caption: "\(t.turnsSuccessful) of \(t.turnsCounted) turns",
                         help: .turnSuccess)
                StatCard(title: "Port / starboard",
                         value: "\(t.port) / \(t.starboard)",
                         caption: t.rejected > 0
                             ? "\(t.rejected) course change\(t.rejected == 1 ? "" : "s") excluded"
                             : "entered on each tack",
                         help: .portStarboard)
                StatCard(title: "Falls",
                         value: "\(split.falls)",
                         caption: "\(split.turnFalls) in turns · "
                             + "\(split.straightFalls) straight-line",
                         help: .falls)
                StatCard(title: "Touchdowns",
                         value: "\(split.touchdowns)",
                         caption: "\(split.turnTouchdowns) in turns · "
                             + "\(split.straightTouchdowns) straight-line",
                         help: .touchdowns)
                StatCard(title: "Glide-outs", value: "\(split.glideOuts)",
                         caption: split.unknownEnds > 0
                             ? "\(split.unknownEnds) flight end\(split.unknownEnds == 1 ? "" : "s") "
                                 + "unknown (recording cut)"
                             : "came off and kept moving",
                         help: .glideOuts)
            }
        }
    }

    private func outcomeCaption(_ counts: OutcomeCounts) -> String {
        guard counts.total > 0 else { return "none detected" }
        return "\(counts.flewThrough) flew · \(counts.touchdown) touch · \(counts.fellIn) fell"
    }

    // MARK: - Takeoff & pumping

    @ViewBuilder
    private var takeoff: some View {
        let k = summary.takeoff
        if k.takeoffSuccesses > 0 {
            section("Takeoff & pumping", anchor: "takeoff", help: .takeoffAttempts) {
                StatCard(title: "Pumps to takeoff",
                         value: k.avgPumpsToTakeoff.map { String(format: "%.1f", $0) } ?? "—",
                         caption: k.avgPumpsToTakeoff == nil
                             ? "no accelerometer stream"
                             : "median \(k.medianPumpsToTakeoff.map { String(format: "%.0f", $0) } ?? "—")"
                                 + " · \(k.freeTakeoffs) free",
                         dimmed: k.avgPumpsToTakeoff == nil, help: .pumpsToTakeoff)
                StatCard(title: "Attempts",
                         value: "\(k.takeoffAttempts)",
                         caption: k.failedAttempts > 0
                             ? "\(k.failedAttempts) failed" : "all got up",
                         help: .takeoffAttempts)
                StatCard(title: "Success rate",
                         value: k.successPct.map { Fmt.pct($0) } ?? "—",
                         caption: k.successPct == nil
                             ? "failures invisible without accel"
                             : "\(k.takeoffSuccesses) of \(k.takeoffAttempts)",
                         dimmed: k.successPct == nil, help: .takeoffAttempts)
                StatCard(title: "Takeoff run",
                         value: k.avgTakeoffS.map { String(format: "%.1f s", $0) } ?? "—",
                         caption: k.runsTruncated > 0
                             ? "\(k.runsJudged) judged · \(k.runsTruncated) not in the record"
                             : "average over \(k.runsJudged) runs",
                         dimmed: k.avgTakeoffS == nil)
                if let strokes = k.totalPumpStrokes {
                    StatCard(title: "Pump strokes", value: "\(strokes)",
                             caption: "\(k.inFlightPumpStrokes ?? 0) in flight · "
                                 + "\(k.inFlightEpisodes) episodes",
                             help: .pumpStrokes)
                }
            }
        }
    }

    private func section(_ title: String, anchor: String? = nil, help: HelpTopicID? = nil,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.headline)
                if let help { HelpButton(topic: help, size: .footnote) }
                Spacer()
            }
            LazyVGrid(columns: columns, spacing: 12) { content() }
        }
        .id(anchor ?? title)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var caption: String = " "
    var dimmed = false
    var highlighted = false
    /// When set, a small `?` sits beside the title and opens that topic.
    var help: HelpTopicID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let help { HelpButton(topic: help, size: .caption2) }
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(dimmed ? .secondary : .primary)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange, lineWidth: highlighted ? 2 : 0)
        }
    }
}
