import Foundation

/// Everything the session detail's HR-cost card prints, resolved once so the SwiftUI view
/// that renders it is pure layout — and so the *wording* can be tested without a renderer.
///
/// The split is the same one `ShareCardStats` follows: number-to-string logic lives here in
/// the kit with unit tests, the views live in the app. It matters more here than anywhere
/// else in the app, because this card's whole job is to be honest about a sensor that lies.
///
/// **The rules this type enforces, so no view can break them:**
/// * `make` returns `nil` when the session has no heart rate, or has one that measured
///   nothing at all. A card of em-dashes is worse than no card — it invites the reader to
///   assume the numbers were zero rather than absent.
/// * Every aggregate that has an `HrCoverage` prints it (`23 of 23 takeoffs`). An average
///   over three of forty takeoffs is a different claim from an average over forty, and the
///   reader cannot tell them apart unless the denominator is on the screen.
/// * A missing value is `nil` and renders as "—" *with the reason beside it*, never as 0.
///   0 bpm is a measurement ("this attempt cost nothing"), and it is one this session may
///   genuinely have made — see `bpm(_:)`.
///
/// Definitions: docs/algorithms.md "HR cost (phone)". Computation: `HrCost.swift`.
public struct HrCostCard: Sendable, Equatable {

    /// One secondary number with its label and the coverage/reason line under it.
    public struct Stat: Sendable, Equatable, Identifiable {
        public let key: String
        public let label: String
        /// Already formatted, "—" when the metric could not be measured.
        public let value: String
        /// The coverage when there is a number, the reason when there is not.
        public let caption: String
        /// True when `value` is a placeholder — the view dims it.
        public let missing: Bool
        /// True when the number exists but rests on too little of the session to lean on.
        public let thin: Bool

        public var id: String { key }

        public init(key: String, label: String, value: String, caption: String,
                    missing: Bool, thin: Bool = false) {
            self.key = key
            self.label = label
            self.value = value
            self.caption = caption
            self.missing = missing
            self.thin = thin
        }
    }

    /// One slice of the fatigue curve, ready to plot.
    ///
    /// The engine chose the edges (`hrBinMinutes`, 20 min) and the card does not re-bin:
    /// re-slicing presentation-side would put a second, undocumented definition of "the
    /// fatigue curve" in the app, and the golden files would no longer describe what the
    /// screen shows. Bins therefore arrive as-is, including the short final one.
    public struct Bin: Sendable, Equatable, Identifiable {
        public let id: Int
        /// Session-clock seconds — the same base the speed chart's x axis uses, so the two
        /// charts on the page can be read against each other.
        public let startS: Double
        public let endS: Double
        public var midS: Double { (startS + endS) / 2 }
        /// "20–40 min", for the accessibility label and the tests.
        public let label: String
        /// Median takeoff cost in the bin; nil when no attempt in it had usable HR.
        public let costBpm: Double?
        public let avgCostBpm: Double?
        /// Mean HR the bin's attempts *started* from. A late rise shrinks when the baseline
        /// has drifted up, so this is what stops the cost curve being read as fatigue.
        public let baselineBpm: Double?
        /// nil when nothing was attempted in the bin — "no attempts" is not "0 % success".
        public let successPct: Double?
        public let attempts: Int
        public let successes: Int
        /// "3 of 4" — how many of the bin's takeoffs yielded a cost.
        public let coverage: String?

        public init(id: Int, startS: Double, endS: Double, label: String, costBpm: Double?,
                    avgCostBpm: Double?, baselineBpm: Double?, successPct: Double?,
                    attempts: Int, successes: Int, coverage: String?) {
            self.id = id
            self.startS = startS
            self.endS = endS
            self.label = label
            self.costBpm = costBpm
            self.avgCostBpm = avgCostBpm
            self.baselineBpm = baselineBpm
            self.successPct = successPct
            self.attempts = attempts
            self.successes = successes
            self.coverage = coverage
        }

        /// One line a screen reader can read out, since a bar chart says nothing aloud.
        public var accessibilityText: String {
            var parts = [label]
            parts.append(costBpm.map { "cost \(HrCostCard.bpm($0))" } ?? "cost not measurable")
            if let successPct {
                parts.append(String(format: "%.0f%% of %d attempts", successPct, attempts))
            }
            if let baselineBpm {
                parts.append(String(format: "from %.0f bpm", baselineBpm))
            }
            return parts.joined(separator: ", ")
        }
    }

    /// "+7 bpm", or "—" when no takeoff was measurable.
    public let headlineValue: String
    /// "median takeoff cost · 23 of 23 takeoffs".
    public let headlineCaption: String
    public let headlineMissing: Bool
    /// Set when the aggregates rest on so little usable HR that the reader should not lean
    /// on them. Shown as a banner *above* the numbers, not as a footnote below them.
    public let warning: String?
    /// Provenance line: how much of the session the sensor actually held, and the peak lag.
    public let footnote: String
    /// Empty when the session produced no bins at all — the view then draws no chart.
    public let bins: [Bin]
    /// What the chart is, in one line. nil when there is no chart.
    public let binCaption: String?
    /// Why a falling cost curve is not automatically good news. nil when no bin had a
    /// baseline to compare.
    public let baselineNote: String?
    public let stats: [Stat]

    public init(headlineValue: String, headlineCaption: String, headlineMissing: Bool,
                warning: String?, footnote: String, bins: [Bin], binCaption: String?,
                baselineNote: String?, stats: [Stat]) {
        self.headlineValue = headlineValue
        self.headlineCaption = headlineCaption
        self.headlineMissing = headlineMissing
        self.warning = warning
        self.footnote = footnote
        self.bins = bins
        self.binCaption = binCaption
        self.baselineNote = baselineNote
        self.stats = stats
    }

    // MARK: - Thresholds

    /// Below this share of an aggregate's attempts the number is flagged `thin`. It is the
    /// aggregate-level echo of `HrConfig.minCoverageShare`, which does the same job one
    /// window at a time: 60 % is where "measured, with holes" becomes "mostly guesswork".
    public static let thinCoveragePct = 60.0

    // MARK: - Building

    /// The card's content, or nil when there is nothing honest to put on it.
    ///
    /// nil in two cases, and both mean *render nothing*: the source carried no HR channel
    /// at all (`hasHR == false` — a fact about the file, docs/testing.md), or it carried one
    /// that survived no window anywhere in the session. The second is the wetsuit case: the
    /// samples exist, none of them are usable, and a card built from them would be five
    /// dashes and a chart of gaps.
    public static func make(_ hr: HrAnalysis?) -> HrCostCard? {
        guard let hr, hr.hasHR else { return nil }
        let s = hr.summary
        let bins = bins(hr.bins)
        let stats = stats(s)
        // "Measured something" = a takeoff cost, a pumping/cruising pair, a stroke ratio, a
        // recovery, or any bin with a cost. Anything less and the card is dashes only.
        let measuredAnything = s.medianTakeoffCostBpm != nil
            || stats.contains { !$0.missing }
            || bins.contains { $0.costBpm != nil }
        guard measuredAnything else { return nil }

        let coverage = s.takeoffCostCoverage
        var captionParts: [String] = ["median takeoff cost"]
        if let text = coverageText(coverage, noun: "takeoff") { captionParts.append(text) }
        // A native recording has no strokes to anchor on and falls back to the flight start,
        // which measures the off-foil → on-foil delta rather than the whole effort. Same
        // number, weaker claim, so it is said on the headline rather than buried in help.
        if s.approximateTakeoffs > 0 {
            captionParts.append("\(s.approximateTakeoffs) anchored on the flight start")
        }

        return HrCostCard(
            headlineValue: s.medianTakeoffCostBpm.map { bpm($0) } ?? "—",
            headlineCaption: captionParts.joined(separator: " · "),
            headlineMissing: s.medianTakeoffCostBpm == nil,
            warning: warning(s),
            footnote: footnote(s),
            bins: bins,
            binCaption: bins.isEmpty ? nil
                : "20-minute bins · bars are the median rise per takeoff, the line is how "
                    + "many attempts got up",
            baselineNote: baselineNote(bins),
            stats: stats)
    }

    /// The banner. Two independent ways this card can be built on sand: too little of the
    /// session recorded a usable heart rate at all, or too few of the takeoffs yielded a
    /// cost. Either alone is worth saying out loud before the numbers are read.
    static func warning(_ s: HrSummary) -> String? {
        var reasons: [String] = []
        if let usable = s.usablePct, usable < thinCoveragePct {
            reasons.append(String(format: "the sensor held a usable reading for only %.0f%% "
                                  + "of the session", usable))
        }
        let coverage = s.takeoffCostCoverage
        if coverage.total > 0, let pct = coverage.pct, pct < thinCoveragePct {
            reasons.append("only \(coverage.valid) of \(coverage.total) takeoffs could be "
                           + "measured")
        }
        guard !reasons.isEmpty else { return nil }
        return "Heart rate is patchy here — " + reasons.joined(separator: ", ")
            + ". Read these as the parts that were recorded, not as the session."
    }

    /// Where the numbers come from, in the tertiary voice the page's other footers use.
    static func footnote(_ s: HrSummary) -> String {
        var parts: [String] = []
        parts.append(s.usablePct.map { String(format: "HR usable %.0f%% of the session", $0) }
            ?? "HR coverage unknown")
        if let lag = s.medianPeakLagS {
            parts.append(String(format: "peak %.0f s after the effort", lag))
        }
        return parts.joined(separator: " · ")
    }

    static func bins(_ raw: [FatigueBin]) -> [Bin] {
        raw.enumerated().map { index, b in
            Bin(id: index, startS: b.startT, endS: b.endT,
                label: binLabel(b.startT, b.endT),
                costBpm: b.medianCostBpm, avgCostBpm: b.avgCostBpm,
                baselineBpm: b.avgBaselineBpm, successPct: b.successPct,
                attempts: b.attempts, successes: b.successes,
                coverage: coverageText(b.costCoverage, noun: nil))
        }
    }

    /// The four secondary numbers, always all four and always in this order.
    ///
    /// They stay on the card when they are missing, each carrying the reason it is missing,
    /// because *why* a number is absent is itself an answer: "no accelerometer on this
    /// source" and "your HR never rose enough to recover from" are different sessions.
    static func stats(_ s: HrSummary) -> [Stat] {
        [strokeStat(s), pumpCruiseStat(s), recoveryStat(s, kind: .takeoff),
         recoveryStat(s, kind: .swim)]
    }

    private static func strokeStat(_ s: HrSummary) -> Stat {
        let coverage = s.bpmPerStrokeCoverage
        guard let pooled = s.bpmPerStroke else {
            return Stat(key: "bpmPerStroke", label: "Per pump stroke", value: "—",
                        caption: coverage.total == 0 ? "no takeoffs to rate"
                            : "no stroke counts on this source",
                        missing: true)
        }
        var caption = s.medianBpmPerStroke.map { String(format: "median %.2f", $0) } ?? ""
        if let text = coverageText(coverage, noun: "takeoff") {
            caption = caption.isEmpty ? text : caption + " · " + text
        }
        return Stat(key: "bpmPerStroke", label: "Per pump stroke",
                    value: String(format: "%.2f bpm", pooled), caption: caption,
                    missing: false, thin: isThin(coverage))
    }

    private static func pumpCruiseStat(_ s: HrSummary) -> Stat {
        let pc = s.pumpCruise
        // The engine's own `deltaBpm` is still the gate — it is nil exactly when one of the
        // two windows could not be measured — but the *printed* delta is derived below
        // from the printed operands, so the three numbers on the card reconcile.
        guard pc.deltaBpm != nil, let pumping = pc.pumpingBpm,
              let cruising = pc.cruisingBpm else {
            return Stat(key: "pumpCruise", label: "Pumping vs cruising", value: "—",
                        caption: pc.pumpingSpans == 0 ? "no pump bursts on this source"
                            : "not enough usable HR in one of the two",
                        missing: true)
        }
        // **The delta and its operands are printed from the SAME rounded numbers.**
        //
        // The card used to read `Pumping vs cruising · -0.1 bpm · 119 vs 119 bpm on the
        // foil` (app-ui-review.md §5.7): a delta claiming a negative difference over two
        // operands that, as displayed, were identical. Two things were wrong with it and
        // both are fixed here. The operands are printed at the delta's own precision —
        // both are time-weighted means, so the first decimal is a real digit on each of
        // them — and the delta is then re-derived from those *printed* values rather than
        // from the unrounded pair, so a reader who does the subtraction always gets the
        // headline back. The correction is at most half a display digit (0.05 bpm) and it
        // is the difference between a card that reconciles and one that does not.
        let shownPumping = (pumping * 10).rounded() / 10
        let shownCruising = (cruising * 10).rounded() / 10
        var caption = String(format: "%.1f vs %.1f bpm on the foil",
                             shownPumping, shownCruising)
        // Time-share coverage rather than n-of-n: these two means are weighted by recorded
        // seconds, so the honest denominator is seconds, not events.
        let covered = min(pc.pumpingCoverage ?? 1, pc.cruisingCoverage ?? 1)
        if covered < 0.995 {
            caption += String(format: " · %.0f%% covered", covered * 100)
        }
        return Stat(key: "pumpCruise", label: "Pumping vs cruising",
                    value: bpm(shownPumping - shownCruising, decimals: 1),
                    caption: caption, missing: false,
                    thin: covered < thinCoveragePct / 100)
    }

    private enum RecoveryKind { case takeoff, swim }

    private static func recoveryStat(_ s: HrSummary, kind: RecoveryKind) -> Stat {
        // Two nouns, because the denominator and the absence are about different things:
        // the coverage counts the events that *rose* ("14 of 15 rises"), while the reason a
        // number is missing is about the events themselves ("no takeoff raised HR…").
        let (key, label, noun, event, seconds, coverage) = kind == .takeoff
            ? ("takeoffRecovery", "Recovery after takeoff", "rise", "takeoff",
               s.medianTakeoffRecoveryS, s.takeoffRecoveryCoverage)
            : ("swimRecovery", "Recovery after a swim", "swim", "swim",
               s.medianSwimRecoveryS, s.swimRecoveryCoverage)
        guard let seconds else {
            // The denominator is the events that rose by at least `hrMinRise`. Zero of them
            // and there was nothing to recover from; some of them and the decay never landed
            // inside the 2-minute window, or ran into a recording hole.
            return Stat(key: key, label: label, value: "—",
                        caption: coverage.total == 0
                            ? "no \(event) raised HR enough to recover from"
                            : "HR never fell halfway back within 2 min",
                        missing: true)
        }
        var caption = "halfway back"
        if let text = coverageText(coverage, noun: noun) { caption += " · " + text }
        return Stat(key: key, label: label, value: String(format: "%.0f s", seconds),
                    caption: caption, missing: false, thin: isThin(coverage))
    }

    /// The sentence that stops a falling cost curve being read as "it got easier".
    ///
    /// On the corpus the late-session cost collapses (7.3 → 9.3 → −0.5 bpm by thirds) while
    /// the success rate collapses too — because the attempts started 8–14 bpm higher and
    /// there was no headroom left to rise into. Plotting cost without the baseline beside it
    /// would show a rider getting *stronger* as he fell apart.
    static func baselineNote(_ bins: [Bin]) -> String? {
        let measured = bins.compactMap { bin in bin.baselineBpm.map { (bin, $0) } }
        guard let first = measured.first, let last = measured.last, measured.count >= 2
        else { return nil }
        let drift = last.1 - first.1
        let span = String(format: "%.0f → %.0f bpm", first.1, last.1)
        if drift >= 5 {
            return "Attempts started at \(span) as the session went on — a smaller late rise "
                + "is missing headroom, not a cheaper takeoff."
        }
        if drift <= -5 {
            return "Attempts started at \(span) — later takeoffs began from a lower heart "
                + "rate, so their rises are the larger ones."
        }
        return "Attempts started from a steady \(span), so the bins compare like with like."
    }

    // MARK: - Formatting

    /// Signed bpm. **A rise is signed and a zero is not a dash**: a negative cost is a real
    /// result (he was still recovering when he started, docs/algorithms.md), and a measured
    /// 0 must not read as a missing value — so it drops the sign rather than printing the
    /// "-0 bpm" that `%+.0f` produces for a small negative.
    ///
    /// Whole bpm for the takeoff cost, whose inputs are integer sensor samples; one decimal
    /// for the pumping/cruising delta, which is a difference of two time-weighted means and
    /// where rounding 5.6 to 6 would throw away the only digit that moves.
    public static func bpm(_ value: Double, decimals: Int = 0) -> String {
        let scale = pow(10.0, Double(decimals))
        if (value * scale).rounded() == 0 { return "0 bpm" }
        return String(format: "%+.\(decimals)f bpm", value)
    }

    /// "23 of 23 takeoffs", or nil when there is no denominator to state.
    public static func coverageText(_ coverage: HrCoverage, noun: String?) -> String? {
        guard coverage.total > 0 else { return nil }
        let core = "\(coverage.valid) of \(coverage.total)"
        guard let noun else { return core }
        return core + " \(noun)\(coverage.total == 1 ? "" : "s")"
    }

    /// "20–40 min", from session-clock seconds.
    static func binLabel(_ startS: Double, _ endS: Double) -> String {
        String(format: "%.0f–%.0f min", startS / 60, endS / 60)
    }

    static func isThin(_ coverage: HrCoverage) -> Bool {
        guard let pct = coverage.pct else { return false }
        return pct < thinCoveragePct
    }
}
