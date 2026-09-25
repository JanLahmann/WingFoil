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

    /// Three tiles to a row is a row at every ordinary text size and a row of ellipses at
    /// an accessibility one — "13.47 kn" set at 180 % does not fit a third of a phone at any
    /// scale factor its label is still legible at. Past the threshold each row of three
    /// wraps into two columns instead, which keeps the grouping (basics, speed, turns,
    /// rates) and gives every number half the width.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            row {
                ForEach(metrics.basics) { cell($0) }
            }

            // The session's fastest measured window leads the row in the block's largest
            // type: it is the one number a rider quotes, and the label says which window it
            // is rather than letting "max" imply a peak sample. The two composites sit
            // beside it at the ordinary size (6 Sep 2026 — the row was "a bit empty").
            row {
                cell(metrics.maxSpeed, font: .title.weight(.semibold))
                ForEach(metrics.speedExtras) { cell($0) }
            }

            // The tally is the **jibe** ladder and its caption says so ("of 57 jibes"), and
            // since 22 September 2026 the **tack** ladder sits next to it on the afternoons
            // that have tacks in them — same three counts, same inks, its own caption.
            // The falls cell beside them is the **session**, straight-line swims included —
            // a different question again, and one number until 20 September 2026, when a
            // tester who fell three times read a 1.
            //
            // The clean jibes lead the row in a cell of their own since 25 September 2026
            // (Jan, F8e): the star, in the clean ink, over the one number the product is
            // named for. It was a clause in the tally's caption.
            if metrics.cleanJibes != nil || metrics.tally != nil || metrics.tacks != nil
                || metrics.streaks != nil || metrics.falls != nil {
                row(count: tallyRowCount) {
                    if let clean = metrics.cleanJibes { cleanCell(clean) }
                    if let tally = metrics.tally { tallyCell(tally) }
                    if let tacks = metrics.tacks { tallyCell(tacks) }
                    if let falls = metrics.falls { cell(falls) }
                    if let streaks = metrics.streaks { pairCell(streaks) }
                }
            }

            if !metrics.rates.isEmpty {
                row {
                    ForEach(metrics.rates) { cell($0) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        // Two tiles to a line at accessibility sizes, and a ceiling even so: past
        // `.accessibility2` half a phone's width no longer holds a number and its label
        // either, and the block would stop being readable rather than become so.
        .denseRowTypeSizeCap()
    }

    /// How many tiles the tally row is carrying. Three is the block's shape everywhere
    /// else; the tack ladder makes it four on the sessions the rider tacked on, and four
    /// abreast is where `63 · 1 · 6` stops fitting a quarter of a phone.
    private var tallyRowCount: Int {
        [metrics.cleanJibes != nil, metrics.tally != nil, metrics.tacks != nil,
         metrics.falls != nil, metrics.streaks != nil].filter { $0 }.count
    }

    /// One line of tiles: side by side, or two to a line once the type is large enough that
    /// three would truncate — and the same two-column wrap once the line is carrying four
    /// of them, which is the shape the web's `auto-fit` grid takes at the same width.
    /// `.topLeading` so a tile whose label wraps onto three lines does not drag its
    /// neighbour's number down with it.
    @ViewBuilder
    private func row(count: Int = 3, @ViewBuilder _ content: () -> some View) -> some View {
        if typeSize.isAccessibilitySize || count > 3 {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12,
                                                         alignment: .topLeading),
                                     count: 2),
                      alignment: .leading, spacing: 12) { content() }
        } else {
            HStack(alignment: .top, spacing: 12) { content() }
        }
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
                .minimumScaleFactor(0.6)
            // No line limit: a label that needs four lines at the rider's text size gets
            // four. The row is `.top`-aligned, so a taller tile pushes nothing sideways.
            // The label, and the qualifier under it where the cell has one — the falls
            // cell's split today. Same separator the tally uses, so the two captions in
            // this row read as one kind of thing.
            Text(metric.caption.map { metric.label + Self.captionSep + $0 } ?? metric.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label), \(metric.value)")
    }

    /// **The clean jibes**: the star and the number in the clean ink, never the ladder's
    /// green — clean is the stricter reading of turns the ladder already counts
    /// (docs/presentation/clean-jibe.md, "Clean jibe").
    private func cleanCell(_ metric: KeyMetrics.Metric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: DesignTokens.Glyph.cleanJibe)
                    .font(.title3)
                Text(metric.value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(EventMarkerStyle.cleanJibe)
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.value) \(metric.label)")
    }

    /// **A pair cell, each half in its own ink** — the streaks' "3 flew · 5 dry", where the
    /// flew half wears the ladder's green (F8f). The words ride in the number's colour, one
    /// weight lighter, the shape `OutcomeTally` gives its own words.
    private func pairCell(_ metric: KeyMetrics.Metric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if metric.parts.isEmpty {
                Text(metric.value).font(.title2.weight(.semibold)).monospacedDigit()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    ForEach(Array(metric.parts.enumerated()), id: \.offset) { index, part in
                        if index > 0 { Text("·").foregroundStyle(.tertiary) }
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(part.value).font(.title2.weight(.semibold))
                            Text(part.label).font(.subheadline)
                        }
                        .foregroundStyle(Self.ink(part.colourRole))
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label), \(metric.value)")
    }

    /// A document `colourRole` as this surface's ink. Only the roles the block's cells
    /// carry are named; everything else is the body ink.
    private static func ink(_ role: String) -> Color {
        switch role {
        case "outcome.flew": DesignTokens.Outcome.flew
        case "outcome.touchdown": DesignTokens.Outcome.touchdown
        case "outcome.fellIn": DesignTokens.Outcome.fellIn
        case "clean.jibe": EventMarkerStyle.cleanJibe
        default: .primary
        }
    }

    /// The outcome ladder's own three counts, in the ladder's own inks — the same
    /// `OutcomeTally` the library row draws, one type size up because here it is a
    /// headline rather than a row detail.
    ///
    /// The " — " is the share card's `CAPTION_SEP`, the separator glyph between a pinned
    /// label and its caption, not a dash inside a rider sentence. `ShareCard.swift` and
    /// `web/js/cardstats.js` print the identical string and a verifier holds them to each
    /// other, so the rendered text here must not move.
    private static let captionSep = " — "

    private func tallyCell(_ tally: KeyMetrics.Tally) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            OutcomeTally(flewThrough: tally.flewThrough, touchdown: tally.touchdown,
                         fellIn: tally.fellIn, font: .title2)
            Text(tally.label + Self.captionSep + tally.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
