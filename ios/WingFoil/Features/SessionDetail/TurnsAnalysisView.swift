import CoreLocation
import MapKit
import SwiftUI
import WingFoilKit

/// One session's maneuvers under two filters at once — **the Turns tab's own content**.
///
/// It exists because "how are my jibes?" is really four questions — jibes or tacks, entered
/// on port or on starboard — and the session cards can only answer the first two as totals.
/// Here the two segmented controls compose (AND), and **everything below them obeys both**:
/// the map dots, the outcome tally and the list are three views of the same filtered set,
/// never of three different ones.
///
/// The side filter is the tack the turn was **entered** on (`side`), not the direction the
/// board rotated (`direction`) — see `TurnSideFilter`, which is why the labels say "entry".
///
/// **It used to be a pushed page, and that was the mistake.** `app-ui-review.md` §2.1 called
/// this the best screen in the app and noted that nothing led to it: it opened with the
/// outcome tally as a headline and a percentage as the giant over a dense scannable list —
/// verbatim the design language the watch had just adopted and verbatim the owner's taste —
/// and it was reached only by scrolling ~2 400 pt to an "All 51 turns" row and tapping it.
/// So it is not a page any more. It is the body of the Turns tab, folded in under the turn
/// cards it belongs with, and the extra push is gone. This view is therefore layout only:
/// no `ScrollView` and no navigation title, because it is one block on a scrolling tab.
struct TurnsAnalysisView: View {
    let detail: SessionDetail

    /// Read here rather than passed in, for the one thing this page shares with the session
    /// map: the ground it is drawn on (`MapStyleChoice`). Everything else about this map is
    /// deliberately its own.
    @Environment(SessionStore.self) private var store

    @State private var filter = TurnFilter()
    /// The row the reader tapped, drawn larger on the map. Transient, like the record
    /// window picker — it is a way of pointing, not a preference.
    @State private var focused: Int?
    /// The turn whose detail sheet is open. A row tap does both things: it enlarges the pin
    /// (so the page behind the sheet is showing the turn being read) and it opens the sheet.
    @State private var opened: TurnDetailRequest?

    private var items: [TurnListItem] {
        TurnAnalytics.items(detail.analysis.turns, filter: filter)
    }

    private var tally: TurnOutcomeTally { TurnAnalytics.tally(items) }

    /// Positions for the turns that survived the filter, in the list's order.
    private var pins: [SessionDetail.TurnPin] {
        let kept = Set(items.map(\.id))
        return detail.turnPins.filter { kept.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("All \(detail.analysis.summary.turns.turnsCounted) turns")
                .font(.headline)
            filters
            tallyStrip
            if !detail.segments.isEmpty { map }
            list
            footnote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $opened) { request in
            TurnDetailSheet(detail: detail, start: request.id)
        }
        #if DEBUG && targetEnvironment(simulator)
        // Screenshot hook, same family as `UI_HIDE_LAYERS`: `simctl` cannot tap a segment,
        // so `UI_TURN_FILTER=jibes,starboard` opens the tab with both filters engaged.
        .onAppear {
            guard let raw = ProcessInfo.processInfo.environment["UI_TURN_FILTER"] else { return }
            for token in raw.split(separator: ",") {
                let key = token.trimmingCharacters(in: .whitespaces)
                if let type = TurnTypeFilter(rawValue: key) { filter.type = type }
                if let side = TurnSideFilter(rawValue: key) { filter.side = side }
            }
        }
        #endif
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Maneuver", selection: $filter.type) {
                ForEach(TurnTypeFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Maneuver type")

            Picker("Entry tack", selection: $filter.side) {
                ForEach(TurnSideFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Entry tack")

            // Said once, here, rather than trusted to the word "port": the rider's other
            // mental model of a jibe is which way the board spun, and that is a different
            // field of the same turn.
            Text("Entry tack is the tack you came into the turn on — not which way the "
                 + "board rotated.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id("filters")
    }

    // MARK: - Tally

    private var tallyStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.pct(tally.flewThroughPct))
                    .font(.title2.weight(.semibold).monospacedDigit())
                VStack(alignment: .leading, spacing: 1) {
                    Text("flew through")
                        .font(.subheadline.weight(.medium))
                    Text(tally.total > 0
                         ? "\(tally.flewThrough) of \(tally.total) \(filter.description)"
                         : "no \(filter.description) in this session")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    // The stricter verdict, under the looser one and never on the ladder's
                    // inks: "flew through" is how the turn ended, "clean" is whether the
                    // speed came through it. Same set of turns, two different questions.
                    if tally.total > 0 {
                        Text(tally.cleanCaption)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(TurnOutcomeKind.allCases, id: \.rawValue) { outcome in
                    outcomeChip(outcome)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tally.total > 0
                            ? "\(filter.description): \(tally.caption), \(tally.cleanCaption)"
                            : "\(filter.description): \(tally.caption)")
        .id("tally")
    }

    private func outcomeChip(_ outcome: TurnOutcomeKind) -> some View {
        let count = tally.count(outcome)
        return HStack(spacing: 4) {
            Image(systemName: outcome.symbolName)
                .font(.caption2)
                .foregroundStyle(TurnOutcomeStyle.color(outcome))
            Text("\(count)").font(.caption.monospacedDigit().weight(.medium))
            Text(outcome.label).font(.caption2)
        }
        .foregroundStyle(count == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(count == 0 ? 0.06 : 0.14)))
    }

    // MARK: - Map

    /// The track in neutral grey with only the filtered turns on it. Deliberately *not*
    /// the session map: this page is about one subset, and the outcome dots of the turns
    /// the filter excluded would be exactly the thing that makes the answer unreadable.
    private var map: some View {
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(detail.region), interactionModes: [.zoom, .pan]) {
                // Over photography the neutral grey route would be the first thing to
                // disappear — it is *meant* to recede, and a photograph gives it far more to
                // recede into than a vector map does. So it gets the same dark outer edge the
                // session map's track gets, from the same place (`TrackHalo`).
                if store.mapStyle.isImagery {
                    ForEach(detail.segments) { segment in
                        MapPolyline(coordinates: segment.points.map {
                            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                        })
                        .stroke(TrackHalo.ink,
                                style: StrokeStyle(
                                    lineWidth: TrackHalo.width(under: segment.flying ? 3 : 1.5),
                                    lineCap: .round, lineJoin: .round))
                    }
                }
                ForEach(detail.segments) { segment in
                    MapPolyline(coordinates: segment.points.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                    })
                    // Neutral grey is "recede" said in the app's own ink, and over a photograph
                    // of deep water it recedes all the way out of sight. Same intent, read
                    // against what is actually underneath (`TrackHalo.ink`).
                    .stroke(TrackHalo.ink(Color.secondary, on: store.mapStyle,
                                          opacity: segment.flying ? 0.45 : 0.22,
                                          overImagery: segment.flying ? 0.8 : 0.45),
                            style: StrokeStyle(lineWidth: segment.flying ? 3 : 1.5,
                                               lineCap: .round, lineJoin: .round))
                }
                ForEach(pins) { pin in
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: pin.lat,
                                                                      longitude: pin.lon),
                               anchor: .center) {
                        TrackHalo.around(TurnOutcomeStyle.pin(pin.outcome,
                                                              focused: focused == pin.id),
                                         on: store.mapStyle)
                            .accessibilityHidden(true)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(store.mapStyle.mapStyle)
            .figureHeight(regular: 240, compact: 180)
            .clipShape(.rect(cornerRadius: 14))
            // The caption, and the map's one control. This page has no legend to put the style
            // chip in — the filters above are about the turns, not the map — so it sits with
            // the line that is already about the picture.
            HStack(alignment: .firstTextBaseline) {
                Text(pins.isEmpty
                     ? "Nothing to mark — widen the filters."
                     : "\(pins.count) turn\(pins.count == 1 ? "" : "s") marked · "
                         + "tap a row below to open it.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                MapStyleChip()
                    .font(.caption2)
            }
        }
        .id("turnsMap")
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            ContentUnavailableView("No \(filter.description)",
                                   systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                                   description: Text("This session has none. Course changes "
                                                     + "— bear-aways and round-ups — are "
                                                     + "never counted as maneuvers."))
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    Button {
                        // The pin enlarge stays — it is what tells the reader which dot on
                        // the map above is the row they just opened — but it is a side
                        // effect now rather than the whole answer.
                        focused = item.id
                        opened = TurnDetailRequest(id: item.id)
                    } label: {
                        TurnRowView(item: item, focused: focused == item.id)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            .id("turnList")
        }
    }

    private var footnote: some View {
        let rejected = detail.analysis.summary.turns.rejected
        return VStack(alignment: .leading, spacing: 3) {
            Text("Score is how much of your entry speed you carried through, 0–100. "
                 + "A clean jibe is one you fly all the way through, carrying your speed "
                 + "— no touchdown, no swim, at or above the success threshold. "
                 + "Flew through / touchdown / fell in is the engine's outcome ladder, "
                 + "which says how the turn ended rather than what it cost.")
            if rejected > 0 {
                Text("\(rejected) course change\(rejected == 1 ? "" : "s") "
                     + "(bear-away / round-up) excluded, as everywhere else in the app.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One turn: when, what, which entry tack, how well, and how it ended.
private struct TurnRowView: View {
    let item: TurnListItem
    let focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.clock(item.ts))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(item.typeLabel) · \(item.sideLabel)")
                    .font(.subheadline)
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(item.scoreText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: item.outcome.symbolName)
                .font(.footnote)
                .foregroundStyle(TurnOutcomeStyle.color(item.outcome))
                .frame(width: 18)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(focused ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Fmt.clock(item.ts)), \(item.accessibilityText)")
    }
}

/// The outcome ladder's colours and pins, in one place so the turns page cannot drift away
/// from the session map's dots. Same three colours as `EventMarkerStyle`, reached from the
/// kit's `TurnOutcomeKind` rather than from the map's marker tone.
enum TurnOutcomeStyle {

    static func color(_ outcome: TurnOutcomeKind) -> Color {
        switch outcome {
        case .flewThrough: return DesignTokens.Outcome.flew
        case .touchdown: return DesignTokens.Outcome.touchdown
        case .fellIn: return DesignTokens.Outcome.fellIn
        }
    }

    @ViewBuilder
    static func pin(_ outcome: TurnOutcomeKind, focused: Bool) -> some View {
        let tint = color(outcome)
        Circle()
            .fill(tint)
            .stroke(.white.opacity(0.9), lineWidth: focused ? 3 : 2)
            .frame(width: focused ? 18 : 11, height: focused ? 18 : 11)
            .shadow(radius: focused ? 3 : 1)
    }
}
