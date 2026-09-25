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

/// The columns every card grid on the page shares — **scaled**, because the minimum is the
/// width of a card holding a title, a number and a caption, and all three grow with the
/// rider's text size. At 150 pt flat, a phone set to an accessibility size kept laying two
/// cards to a row and squeezed every one of them; scaled, the grid drops to one column of
/// full-width cards at exactly the size where two stop fitting, which is what `.adaptive`
/// is for.
private struct CardGrid<Content: View>: View {
    @ScaledMetric(relativeTo: .title3) private var minimum: CGFloat = 150
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 12)],
                  spacing: 12) { content }
    }
}

/// A section heading with its `?`, over a grid of cards. Written once because four blocks
/// draw it and a heading that differs between them reads as two different pages.
@MainActor
private func cardSection(_ title: String, anchor: String? = nil, help: HelpTopicID? = nil,
                         @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
            Text(title).font(.headline)
            if let help { HelpButton(topic: help, size: .footnote) }
            Spacer()
        }
        CardGrid { content() }
    }
    .id(anchor ?? title)
}

// MARK: - Foil

/// The flight facts, on the Ride tab because that is where the flights are drawn.
/// Foil time and flight count are what the map's teal and the chart's shaded bands *are*,
/// and reading the number beside the picture of it is the reason they sit together.
struct SessionFoilGrid: View {
    let detail: SessionDetail

    private var summary: SessionSummary { detail.analysis.summary }

    /// The words this session is read in (docs/presentation/labels.md, "Discipline lexicon").
    private var words: DisciplineLexicon { detail.row.analysisDiscipline.lexicon }

    var body: some View {
        cardSection(words.isExperimental ? "Planing" : "Foil", help: .foilPct) {
            // **"On foil" is the share; "Foil time" is the duration.** The card prints the
            // percentage, so it takes the share's name — the one the web tile, the period
            // block and the watch's own "Foil %" already use. It was titled "Foil time"
            // over a percentage while the watch printed a *duration* under those same two
            // words, so a rider reading the watch and then the phone saw one label over two
            // quantities (docs/presentation/labels.md, "Label table"). The duration is still here,
            // in the caption, which is where it now reads as what the share is a share of.
            StatCard(title: words.onFoil, value: Fmt.pct(summary.foilPct),
                     caption: Fmt.duration(summary.foilTimeS) + " " + words.foilTimeLower,
                     help: .foilPct)
            // **No "Flights · N detected" card** (Jan, 25 Sep 2026, F8k): a count with
            // nothing to open meant nothing to a rider. The flights are a list now, one
            // row each, on the Flights tab (`FlightsListView`), with the count in its head.
            // The caption is `maxFlightM` (engine 0.13.0): the furthest any *one* flight
            // went, which is not in general the longest one's own distance. It used to read
            // "N m" under "Longest flight" and so claimed a fact the number does not carry.
            StatCard(title: "Longest flight",
                     value: Fmt.duration(summary.longestFlightS),
                     caption: "max " + Fmt.meters(summary.maxFlightM) + " in one flight",
                     help: .longestFlight)
            // The caption is the **engine's** cleaned span (`summary.durationS`), the same
            // number and the same spelling the key-metrics block prints two cards up. It
            // used to be `detail.durationS`, the raw sample span, which is 10338 s against
            // 7742 s on the corpus's Rheinstetten afternoon — two clocks, one word, eight
            // points apart on the screen (docs/presentation/one-clock.md, "One clock").
            StatCard(title: "Distance", value: Fmt.km(summary.distanceKm),
                     caption: KeyMetrics.duration(summary.durationS) + " elapsed",
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
/// **Nine rows since 21 September 2026**, `Best hour` among them: the table is one row
/// taller and nothing else about it changes. The column widths are the record name's and the
/// knots', so the ninth name — the shortest of the nine — needs none of the 92 pt the
/// widest already claims, and the row is inert or live by the same rule as the other eight.
/// Being a table rather than a grid is what makes this a non-event: nine cards would have
/// left a gap beside the ninth at two columns and a lone row at one (§1.6).
///
/// This is also why there is no separate Records *tab* inside the session (the review's
/// "deliberately not recommended"): the picker's entire purpose is to highlight a window on
/// the two figures, and a picker on a tab away from them highlights something you cannot see.
struct SessionRecordsTable: View {
    let detail: SessionDetail
    @Binding var selectedEffort: String?

    /// **The nine kinds, as the presentation document names them** — in catalogue order,
    /// all nine always present, so the table has its shape before it has its numbers
    /// (ADR-033, `docs/presentation/document.md`, "`records`"). Nothing about a record is
    /// re-derived here: the value, the provenance and the word are the document's, and the
    /// selection, the inks and the columns are this file's.
    private var kinds: [PresentationValue] {
        detail.document["records"]?["kinds"]?.arrayValue ?? []
    }

    /// Window keys this session actually produced — the set that decides which rows are
    /// live. A record with no window (alpha never achieved, no 1 NM run) is inert.
    private var locatable: Set<String> { Set(detail.efforts.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Speed records").font(.headline)
                HelpButton(topic: .speedRecords, size: .footnote)
                Spacer()
                if !detail.efforts.isEmpty {
                    Text(selectedEffort == nil ? "tap to locate" : "tap again for 2 s")
                        .font(.caption2).foregroundStyle(.readableSecondary)
                }
            }
            VStack(spacing: 0) {
                headerRow
                Divider()
                ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                    if index > 0 { Divider() }
                    row(kind)
                }
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            // Three columns — name, knots, where — and the third is a sentence. The columns
            // scale with the text size, and the table stops at `.accessibility2`, the last
            // size at which all three still fit a phone side by side.
            .denseRowTypeSizeCap()
        }
        .id("summary")
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            // 92 pt, not 74: the record names carry their "Best " prefix now, and
            // "Best 5×10 s" is the widest of them. Scaled, so the column still holds that
            // name when the phone is set to a larger text size.
            Text("record").scaledColumn(92, relativeTo: .subheadline)
            Text(Fmt.knUnit).scaledColumn(74, alignment: .trailing, relativeTo: .subheadline)
            Text("where").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(.readableSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func row(_ kind: PresentationValue) -> some View {
        let key = kind["key"]?.stringValue ?? ""
        let label = PresentationCopy.text(kind["labelId"]?.stringValue ?? "") ?? key
        let value: Double? = if case .number(let kn)? = kind["value"] { kn } else { nil }
        let isSelected = selectedEffort == key
        let isLive = locatable.contains(key)
        return Button {
            selectedEffort = RecordWindowSelection.tapped(key, current: selectedEffort,
                                                          available: locatable)
        } label: {
            HStack(spacing: 10) {
                Text(label)
                    .font(.subheadline)
                    .scaledColumn(92, relativeTo: .subheadline)
                // **One line, always** (25 Sep 2026): "13.25" over "kn" read as two numbers.
                // The column is wide enough for the widest value in either unit at the
                // default size, and shrinks the type a little rather than wrap past it.
                Text(Fmt.kn(value))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(value == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .scaledColumn(74, alignment: .trailing, relativeTo: .subheadline)
                Text(value == nil ? "no qualifying run"
                                  : caption(for: kind["windows"]?.arrayValue?.first))
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        .accessibilityLabel("\(label) record")
        .accessibilityValue(value == nil ? "no qualifying run" : Fmt.kn(value))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// **Where the record was set.** The provenance is the document's `{startTs, durS}`;
    /// the clock and the span are this table's two formatters. 5×10 s names its top run,
    /// which is the list's own first — the other four glow on the map together.
    private func caption(for window: PresentationValue?) -> String {
        guard case .number(let start)? = window?["startTs"],
              case .number(let duration)? = window?["durS"] else { return " " }
        return "at " + Fmt.clock(start) + " · " + Fmt.duration(duration)
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
                    // **Each kind of turn with its whole breakdown, in numbers** (Jan, 25
                    // Sep 2026, F9a/b). The ladder's counts were a caption of words under
                    // one total; they are the ladder's own marks and inks now, and the
                    // clean jibes lead the jibe card with the star. The separate
                    // "Flew through %" card said the same thing a third time and is gone.
                    BreakdownCard(title: "Jibes", value: "\(t.jibes)",
                                  parts: t.jibes > 0
                                      ? [BreakdownPart.clean(t.jibesSuccessful)]
                                        + BreakdownPart.ladder(t.jibeOutcomes)
                                      : [],
                                  caption: t.jibes > 0 ? nil : "none detected",
                                  help: .turnTypes)
                    BreakdownCard(title: "Tacks", value: "\(t.tacks)",
                                  parts: t.tacks > 0 ? BreakdownPart.ladder(t.tackOutcomes) : [],
                                  caption: t.tacks > 0 ? nil : "none detected",
                                  help: .turnTypes)
                    if t.unclassified > 0 {
                        StatCard(title: "Unclassified turns", value: "\(t.unclassified)",
                                 caption: "no usable wind axis", help: .windAxis)
                    }
                    StatCard(title: "Port / starboard",
                             value: "\(t.port) / \(t.starboard)",
                             caption: t.rejected > 0
                                 ? String(t.rejected)
                                     + (t.rejected == 1 ? " course change" : " course changes")
                                     + " excluded"
                                 : "entered on each tack",
                             help: .portStarboard)
                    // **Every fall, from one channel** (20 September 2026): the flight-end
                    // channel, one event per actual swim, `all == inTurn + straight` by
                    // construction (docs/algorithms/rates.md, "Wet is every fall, not every
                    // fallen jibe"). The same number WPH divides and the block prints.
                    StatCard(title: MetricGlossary.entry("fellIn").term,
                             value: "\(summary.flightEnds.all.fellIn)",
                             caption: String(summary.flightEnds.inTurn.fellIn)
                                 + " in a turn · "
                                 + String(summary.flightEnds.straight.fellIn)
                                 + " in a straight line",
                             help: .falls)
                    // **Touchdowns and glide-outs on one card** (Jan, F9e). Both are a
                    // flight that ended without a swim; the engine tells them apart by
                    // whether the speed reached the stop floor. The glide-out wears its
                    // own neutral ring — the map's hollow mark — never the flew check.
                    BreakdownCard(title: "Touchdowns · glide-outs",
                                  value: nil,
                                  parts: [.touchdown(split.touchdowns),
                                          .glideOut(split.glideOuts)],
                                  caption: String(split.turnTouchdowns) + " in turns · "
                                      + String(split.straightTouchdowns) + " straight-line"
                                      + (split.unknownEnds > 0
                                         ? " · " + String(split.unknownEnds)
                                             + (split.unknownEnds == 1 ? " end" : " ends")
                                             + " cut by the recording"
                                         : ""),
                                  help: .touchdowns)
                }
                if t.turnsCounted > 0 {
                    Divider()
                    TurnsAnalysisView(detail: detail)
                }
            }
        }
    }

}

// MARK: - Takeoff & pumping

/// The takeoff cards, led by the number of attempts that did not get up.
///
/// The top of the Takeoffs section, not the whole of it: `TakeoffsAnalysisView` puts the
/// attempts on the water underneath, and `HrCostCardView` prices them below that. The three
/// are one subject — how getting up went, where it happened, and what it took out of you.
struct SessionTakeoffSection: View {
    let detail: SessionDetail

    private var summary: SessionSummary { detail.analysis.summary }

    private var words: DisciplineLexicon { detail.row.analysisDiscipline.lexicon }

    var body: some View {
        let k = summary.takeoff
        if k.takeoffSuccesses > 0 {
            VStack(alignment: .leading, spacing: 14) {
                failedHeadline(k)
                // **Absent, not zero.** With no pump channel there are no attempts to fail,
                // no strokes to count and no success rate to quote — an attempt *is* a
                // pumping burst — so the section reduces to the two facts the speed channel
                // alone can state: how many times he got planing, and how long the run took.
                cardSection(words.pumping ? "Takeoff & pumping" : "Planing starts",
                            anchor: "takeoff", help: .takeoffAttempts) {
                    if !words.pumping {
                        StatCard(title: "Planing starts", value: "\(k.takeoffSuccesses)",
                                 caption: "one per planing run", help: .takeoffAttempts)
                        runCard(k, title: "Run to planing")
                    } else {
                        // **One card for takeoffs and attempts** (Jan, F12b). "Takeoffs 19 of
                        // 19 attempts" and "Attempts 19 · all got up" were one fact twice,
                        // and "all got up" beside "failures invisible without accel" was a
                        // claim the recording could not make. With an accelerometer the card
                        // names the attempts; without one it names what a takeoff is.
                        StatCard(title: MetricGlossary.entry("takeoffs").term,
                                 value: "\(k.takeoffSuccesses)",
                                 caption: hasAccel
                                     ? "of \(k.takeoffAttempts) attempts"
                                         + (k.successPct.map { " · " + Fmt.pct($0) + " got up" }
                                            ?? "")
                                     : "one starts every flight",
                                 help: .takeoffAttempts)
                        if hasAccel {
                            StatCard(title: "Pumps to takeoff",
                                     value: k.avgPumpsToTakeoff.map { String(format: "%.1f", $0) }
                                         ?? "—",
                                     caption: "median \(k.medianPumpsToTakeoff.map { String(format: "%.0f", $0) } ?? "—")"
                                         + " · \(k.freeTakeoffs) free",
                                     dimmed: k.avgPumpsToTakeoff == nil, help: .pumpsToTakeoff)
                        }
                        runCard(k, title: "Takeoff run")
                        if hasAccel, let strokes = k.totalPumpStrokes {
                            StatCard(title: "Pump strokes", value: "\(strokes)",
                                     caption: "\(k.inFlightPumpStrokes ?? 0) in flight · "
                                         + "\(k.inFlightEpisodes) episodes",
                                     help: .pumpStrokes)
                        }
                    }
                }
                // **One small note instead of a row of dashes** (Jan, F12a). Every card that
                // needs the wrist accelerometer is left out on a recording that has none;
                // a "—" under "Pumps to takeoff" read as a measurement that failed.
                if words.pumping, !hasAccel {
                    Label("No accelerometer in this recording, so pumps and failed "
                          + "attempts are not counted.", systemImage: "sensor.tag.radiowaves.forward")
                        .font(.caption2)
                        .foregroundStyle(.readableSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var hasAccel: Bool { detail.analysis.capabilities.hasAccel }

    /// How long the run to foil (or to planing) took, and how many runs that is over.
    private func runCard(_ k: TakeoffSummary, title: String) -> some View {
        StatCard(title: title,
                 value: k.avgTakeoffS.map { String(format: "%.1f s", $0) } ?? "—",
                 caption: k.runsTruncated > 0
                     ? String(k.runsJudged) + " judged · "
                         + String(k.runsTruncated) + " not in the record"
                     : "average over " + String(k.runsJudged) + " runs",
                 dimmed: k.avgTakeoffS == nil)
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
        // `words.pumping` as well as the capability: a windsurf recording off a CleanJibe
        // watch *has* an accelerometer, and the preset simply never asked it anything —
        // "0 failed attempts · every attempt got up" would be a congratulation nobody earned.
        if detail.analysis.capabilities.hasAccel, words.pumping {
            VStack(alignment: .leading, spacing: 4) {
                Text("Failed attempts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(k.failedAttempts)")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                Text(k.failedAttempts == 0
                     ? "every attempt got up"
                     : "of " + String(k.takeoffAttempts)
                        + " attempts · red u-turns on the map")
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(captionColor ?? Color.readableSecondary)
                .minimumScaleFactor(0.8)
                // No line limit: the card is as tall as its caption needs, and the grid row
                // takes the tallest card. Two lines was a ceiling measured at the default
                // text size and a truncation at every size above it.
                .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Breakdown card

/// One number of a breakdown: its count, its short word, its mark and its ink.
struct BreakdownPart: Hashable {
    let value: Int
    let word: String
    let symbol: String
    let color: Color

    /// The clean jibes: the star, in the clean ink, never the ladder's green.
    static func clean(_ n: Int) -> BreakdownPart {
        BreakdownPart(value: n, word: "clean", symbol: DesignTokens.Glyph.cleanJibe,
                      color: EventMarkerStyle.cleanJibe)
    }

    /// The ladder's three rungs, in the ladder's marks and inks — the same `symbolName`
    /// and colour every turn row and tally chip wears.
    static func ladder(_ counts: OutcomeCounts) -> [BreakdownPart] {
        [BreakdownPart(value: counts.flewThrough, word: "flew",
                       symbol: TurnOutcomeKind.flewThrough.symbolName,
                       color: TurnOutcomeStyle.color(.flewThrough)),
         touchdown(counts.touchdown),
         BreakdownPart(value: counts.fellIn, word: "fell",
                       symbol: TurnOutcomeKind.fellIn.symbolName,
                       color: TurnOutcomeStyle.color(.fellIn))]
    }

    static func touchdown(_ n: Int) -> BreakdownPart {
        BreakdownPart(value: n, word: "touch", symbol: TurnOutcomeKind.touchdown.symbolName,
                      color: TurnOutcomeStyle.color(.touchdown))
    }

    /// A glide-out's own neutral ring (`FlightPairing.Outcome.glidedOut`), the hollow mark
    /// the map draws it as — never the flew-through check (F9e).
    static func glideOut(_ n: Int) -> BreakdownPart {
        BreakdownPart(value: n, word: "glide-out",
                      symbol: FlightPairing.Outcome.glidedOut.symbolName,
                      color: .secondary)
    }
}

/// **A card whose answer is a breakdown**, drawn as numbers in their own marks and inks
/// rather than as a caption of words (Jan, 25 Sep 2026, F9a/b). `value` is the total when
/// there is one; the breakdown sits under it, and the caption, where there is one, under
/// that. Same frame, type and ink as `StatCard`, so the grid reads as one kind of card.
struct BreakdownCard: View {
    let title: String
    let value: String?
    let parts: [BreakdownPart]
    var caption: String?
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
            if let value {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if !parts.isEmpty {
                // Wraps rather than shrinks: four figures with their words do not fit half a
                // phone at every text size, and a breakdown squeezed to 60 % is unreadable.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { ForEach(parts, id: \.self, content: figure) }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(parts, id: \.self, content: figure)
                    }
                }
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Color.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func figure(_ part: BreakdownPart) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemName: part.symbol)
                .font(.caption2)
            Text("\(part.value)")
                .font(value == nil ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                .monospacedDigit()
            Text(part.word)
                .font(.caption2)
        }
        .foregroundStyle(part.color)
        .opacity(part.value == 0 ? 0.55 : 1)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(part.value) \(part.word)")
    }
}
