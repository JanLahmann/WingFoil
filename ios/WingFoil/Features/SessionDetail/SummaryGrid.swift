import SwiftUI
import WingFoilKit

/// The session's analysis cards, in four blocks — one per tab of `SessionDetailView`.
///
/// They used to be one 3 800 pt column: header, map, chart, foil, eight record tiles, turns,
/// takeoff, HR, gear, in that order, with five unrelated subjects stacked and no way to the
/// fifth except through the other four (`app-ui-review.md` §3.1). Splitting them is the
/// whole point of the tab bar, so each block is its own view and the tab picks one.
///
/// Records that the session could not produce (no qualifying run) stay visible with an
/// explicit placeholder rather than disappearing — the absence is information, and so is a
/// nil stroke count on a source with no accelerometer.

/// The columns every card grid on the page shares.
private let cardColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

/// A section heading with its `?`, over a grid of cards. Written once because four blocks
/// draw it and a heading that differs between them reads as two different pages.
private func cardSection(_ title: String, anchor: String? = nil, help: HelpTopicID? = nil,
                         @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
            Text(title).font(.headline)
            if let help { HelpButton(topic: help, size: .footnote) }
            Spacer()
        }
        LazyVGrid(columns: cardColumns, spacing: 12) { content() }
    }
    .id(anchor ?? title)
}

// MARK: - Foil

/// The flight facts, on the Map · Speed tab because that is where the flights are drawn.
/// Foil time and flight count are what the map's teal and the chart's shaded bands *are*,
/// and reading the number beside the picture of it is the reason they sit together.
struct SessionFoilGrid: View {
    let detail: SessionDetail

    private var summary: SessionSummary { detail.analysis.summary }

    var body: some View {
        cardSection("Foil", help: .foilPct) {
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
    }
}

// MARK: - Speed records

/// The GP3S records as a **table**, and the map's window picker.
///
/// Eight 2-up cards, ~130 pt each, spent ~520 pt to show eight numbers and one provenance
/// line apiece (`app-ui-review.md` §1.4). The web had shown the identical eight as a compact
/// table in about a third of the height for as long as it had existed, and it read *better*,
/// because a column of values can be compared by eye and a wall of tiles cannot. The owner's
/// stated taste is tables over decoration; this was the clearest place in the app where a
/// table wins, and a table has no odd-count parity problem either (§1.6).
///
/// The picker semantics are untouched, because `presentation.md` "Record windows" works
/// identically on a row: tapping a record moves the glow to *that* window on the map and the
/// chart, tapping the selected one returns to the 2 s default, and a record with no achieved
/// window is inert and says nothing. The orange selection ring became an orange row.
///
/// This is also why there is no separate Records *tab* inside the session (the review's
/// "deliberately not recommended"): the picker's entire purpose is to highlight a window on
/// the two figures, and a picker on a tab away from them highlights something you cannot see.
struct SessionRecordsTable: View {
    let detail: SessionDetail
    @Binding var selectedEffort: String?

    private var records: GP3SRecords { detail.analysis.records }

    /// Window keys this session actually produced — the set that decides which rows are
    /// live. A record with no window (alpha never achieved, no 1 NM run) is inert.
    private var locatable: Set<String> { Set(detail.efforts.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Speed records").font(.headline)
                HelpButton(topic: .recordSet, size: .footnote)
                Spacer()
                if !detail.efforts.isEmpty {
                    Text(selectedEffort == nil ? "tap to locate" : "tap again for 2 s")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            VStack(spacing: 0) {
                headerRow
                Divider()
                ForEach(Array(RecordWindowSelection.catalogue.enumerated()), id: \.offset) {
                    index, kind in
                    if index > 0 { Divider() }
                    row(kind)
                }
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        }
        .id("summary")
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("record").frame(width: 74, alignment: .leading)
            Text("kn").frame(width: 62, alignment: .trailing)
            Text("where").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func row(_ kind: RecordKind) -> some View {
        let key = kind.rawValue
        let value = kind.value(in: records)
        let isSelected = selectedEffort == key
        let isLive = locatable.contains(key)
        return Button {
            selectedEffort = RecordWindowSelection.tapped(key, current: selectedEffort,
                                                          available: locatable)
        } label: {
            HStack(spacing: 10) {
                Text(SessionDetail.effortLabel(kind))
                    .font(.subheadline)
                    .frame(width: 74, alignment: .leading)
                Text(Fmt.kn(value))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(value == nil ? .secondary : .primary)
                    .frame(width: 62, alignment: .trailing)
                Text(value == nil ? "no qualifying run" : caption(for: records.windows[key]))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The card's selection ring, as a row: a filled band plus a leading orange bar,
            // because a 2 pt stroke around a 38 pt row reads as a rendering artefact.
            .background {
                if isSelected {
                    HStack(spacing: 0) {
                        Rectangle().fill(DesignTokens.Effort.window).frame(width: 3)
                        DesignTokens.Effort.window.opacity(0.14)
                    }
                }
            }
            .contentShape(.rect)
            .opacity(isLive ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isLive)
        .accessibilityLabel("\(SessionDetail.effortLabel(kind)) record")
        .accessibilityValue(value == nil ? "no qualifying run" : Fmt.kn(value))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func caption(for window: RecordWindow?) -> String {
        guard let window else { return " " }
        return "at \(Fmt.clock(window.startTs)) · \(Fmt.duration(window.durS))"
    }
}

// MARK: - Turns & losses

/// The turn cards. The drill-in they used to link to is now **inline underneath them**, on
/// the Turns tab, because it was the best screen in the app and it was two taps and ~2 400 pt
/// of scroll away (`app-ui-review.md` §2.1).
struct SessionTurnsSection: View {
    let detail: SessionDetail

    private var summary: SessionSummary { detail.analysis.summary }

    var body: some View {
        let t = summary.turns
        let split = summary.outcomeSplit
        if t.turnsCounted > 0 || t.rejected > 0 || summary.flightEnds.all.total > 0 {
            VStack(alignment: .leading, spacing: 20) {
                cardSection("Turns & losses", anchor: "turns", help: .turnOutcomes) {
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
                if t.turnsCounted > 0 {
                    Divider()
                    TurnsAnalysisView(detail: detail)
                }
            }
        }
    }

    private func outcomeCaption(_ counts: OutcomeCounts) -> String {
        guard counts.total > 0 else { return "none detected" }
        return "\(counts.flewThrough) flew · \(counts.touchdown) touch · \(counts.fellIn) fell"
    }
}

// MARK: - Takeoff & pumping

/// The takeoff cards, led by the number of attempts that did not get up.
struct SessionTakeoffSection: View {
    let detail: SessionDetail

    private var summary: SessionSummary { detail.analysis.summary }

    var body: some View {
        let k = summary.takeoff
        if k.takeoffSuccesses > 0 {
            VStack(alignment: .leading, spacing: 14) {
                failedHeadline(k)
                cardSection("Takeoff & pumping", anchor: "takeoff", help: .takeoffAttempts) {
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
    }

    /// **The headline of this tab is what did not work.**
    ///
    /// The number spent its life as a clause in the map legend's grey body copy — "38 failed
    /// attempts this session", 13 pt, mid-paragraph, under three paragraphs of legend
    /// documentation (`app-ui-review.md` §1.2). It is the most interesting fact the takeoff
    /// analysis produces: attempts that got up are the ones the rider remembers, and the ones
    /// that did not are the ones worth working on. So it opens the tab, at the size the HR
    /// card gives its own headline.
    ///
    /// A source with no accelerometer cannot see a failed attempt at all, and reports zero
    /// where it means unknown — so the headline is absent there rather than congratulating
    /// the rider on a perfect session he was never measured for.
    @ViewBuilder
    private func failedHeadline(_ k: TakeoffSummary) -> some View {
        if detail.analysis.capabilities.hasAccel {
            VStack(alignment: .leading, spacing: 4) {
                Text("Failed attempts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(k.failedAttempts)")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                Text(k.failedAttempts == 0
                     ? "every attempt got up"
                     : "of \(k.takeoffAttempts) attempts · red u-turns on the map")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Card

struct StatCard: View {
    let title: String
    let value: String
    var caption: String = " "
    var dimmed = false
    var highlighted = false
    /// When set, a small `?` sits beside the title and opens that topic.
    var help: HelpTopicID?
    /// Tints the caption away from tertiary. Used by the HR card to mark a number that is
    /// real but rests on too few measurable attempts to lean on — which is a different
    /// state from `dimmed` (no number at all), so it needs its own signal.
    var captionColor: Color?

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
                .foregroundStyle(captionColor ?? Color(.tertiaryLabel))
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
