import SwiftUI
import WingFoilKit

/// The map legend, which is also the map's filter.
///
/// Every chip is a toggle: tapping it hides that category on the map *and* in the speed
/// chart, because the two are one reading of the same session and a marker that exists in
/// one but not the other is a lie. A hidden chip stays in place — dimmed, struck through
/// and outlined with a dashed capsule — so turning a category back on never requires
/// finding a settings screen. A category this session has no instances of is drawn the way
/// it always was: subdued and inert, since there is nothing to hide.
///
/// **The chips are the control; the explanation is behind the `?`.** Three grey paragraphs
/// of legend documentation used to sit under them on every visit to every session —
/// ~115 pt of a 956 pt phone screen, above the fold, telling a rider something he learned
/// the first time (`app-ui-review.md` §1.2). The words are unchanged, they now live in the
/// `mapLegend` help topic, and the one genuinely session-specific fact that was buried in
/// them — how many attempts failed — moved to the takeoff card, which is where a number
/// about takeoffs belongs.
///
/// **One legend, three maps** (6 Sep 2026). This view is now the *only* layer control in the
/// app: the Ride tab's track (inline and full screen), the Turns tab's maneuver map and the
/// Takeoffs tab's attempt map all mount it, each declaring the subset of categories it can
/// draw (`MapLayerScope`). Before, the two analysis maps had no legend at all and carried a
/// lone style chip in their captions, which made them look like a different kind of map
/// rather than the same map asking a narrower question. What is *not* shared is the
/// visibility set — three scopes, three stored sets, sensible defaults each — because hiding
/// "fell in" on Turns is a different intention from hiding it on the ride.
struct MapLegendView: View {
    let detail: SessionDetail
    /// The GP3S effort currently highlighted, which is what the `.effort` chip is labelled
    /// with. No effort selected ⇒ no chip, rather than a chip with nothing to name.
    let effort: SessionDetail.RecordEffort?
    /// Which map this legend belongs to: it decides both the chips that exist and the stored
    /// set they toggle.
    var scope: MapLayerScope = .ride
    /// True on the full-screen map, where the legend floats over the water on a material
    /// strip. It drops the `?`: the help sheet would cover the map the rider just went
    /// full-screen to look at, and the same button is one back-swipe away on the session.
    var compact = false

    @Environment(SessionStore.self) private var store

    /// Collapsed until the rider opens it, and then remembered — per rider, like the
    /// visibility set itself, because "I use the chips" and "I never touch the chips" are
    /// facts about a rider and not about a session. Deliberately **shared by all three
    /// maps**: it is a habit, not a per-map choice, and a rider who opens the chips on one
    /// map should not have to open them again on the next.
    @AppStorage(MapLegendView.expandedKey) private var expanded = false

    static let expandedKey = "mapLegend.expanded.v1"

    private var visibility: MapLayerVisibility { store.mapLayers(for: scope) }
    private var tally: MapLayerTally { detail.layerTally(effort: effort) }

    /// The chips this map has, split into the legend's two rows. `direction` rides with the
    /// route because that is what it is about — the route, not the events on it — even
    /// though it hides outright the way a marker layer does.
    private var routeLayers: [MapLayer] {
        scope.layers.filter { $0.isLine || $0 == .direction }
    }

    private var markerLayers: [MapLayer] {
        scope.layers.filter { !($0.isLine || $0 == .direction) }
    }

    /// Whether the marker row has anything to say on *this* session. A map whose event
    /// categories are all empty draws no second row rather than a row of inert captions.
    private var hasMarkers: Bool {
        let tally = self.tally
        return markerLayers.contains { tally.count($0) > 0 }
    }

    /// How many of this map's categories are hidden **that this session has any of** — the
    /// rule is in the kit (`MapLayerVisibility.hiddenCount(in:tally:)`) so all three maps
    /// count the same way and a test can hold them to it.
    private var hiddenHere: Int { visibility.hiddenCount(in: scope, tally: tally) }

    /// **Three rows, one question each** — and the utilities are not one of the questions.
    ///
    /// Until the clean-jibe star arrived the rows were "route layers, plus show-all, plus
    /// the map-style menu, plus the `?`" and then "markers", which put three controls that
    /// are about the *map* in among the chips that are about the *ride*: on a narrow phone
    /// the style menu wrapped between "direction" and "best 2 s", and the row read as a list
    /// of eight unrelated things. The rows now split by what a tap changes:
    ///
    /// 1. **the route** — how the track itself is drawn;
    /// 2. **the events on it** — the clean-jibe star first, because it is the mark the rider
    ///    came to find, then the ladder, then the effort marks;
    /// 3. **the utilities** — show-all (only while something is hidden), the ground the map
    ///    is drawn on, and the help sheet. Trailing-aligned, so they read as the block's
    ///    right-hand furniture rather than as a third kind of layer; they ride on the header
    ///    row, which is the one line that is always on screen.
    ///
    /// The web's `drawChips` groups the identical three (`web/js/session.js`).
    ///
    /// **The two chip groups are behind a header now** (Jan, 6 Sep 2026). Twelve chips over
    /// two or three wrapped lines is ~70 pt between the map and the speed chart on every
    /// visit, and the pair are one instrument: the rider was scrolling past the controls to
    /// reach the second half of the figure they control. So the block collapses to its own
    /// one-line header, which keeps the utilities — the style menu and the `?` — on that
    /// line, since neither is a chip and neither needs the block open to be useful.
    ///
    /// **Collapsed, the header still says when something is off.** "Layers · all shown" is
    /// a statement about the map, and "Layers · 3 hidden" is the reason to open it: a
    /// collapsed control that hid a filter would be exactly the bug the chips exist to
    /// prevent (a marker on the map and not in the chart, or neither, with nothing saying
    /// why).
    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 6 : 0) {
            headerRow
            if expanded {
                routeRow
                if hasMarkers { markerRow }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - Rows

    /// The one line that is always there: what the chips are doing, and the two controls
    /// that were never chips.
    private var headerRow: some View {
        HStack(spacing: 8) {
            disclosure
            Spacer(minLength: 0)
            if !visibility.isEverythingVisible(in: scope) { showAllButton }
            MapStyleChip()
            // A chip-sized affordance among chips, and it costs one line where the prose it
            // replaced cost three paragraphs (§1.2). Dropped on the full-screen map, where
            // the sheet would cover the water the rider went full-screen to look at.
            if !compact { HelpButton(topic: .mapLegend, size: .caption) }
        }
    }

    private var disclosure: some View {
        let hidden = hiddenHere
        return Button {
            withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text("Layers")
                Text("·")
                Text(hidden > 0 ? "\(hidden) hidden" : "all shown")
                    .foregroundStyle(hidden > 0 ? AnyShapeStyle(Color.accentColor)
                                                : AnyShapeStyle(.secondary))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Map layers")
        .accessibilityValue(hidden > 0 ? "\(hidden) hidden" : "all shown")
        .accessibilityHint(expanded ? "Hides the layer chips" : "Shows the layer chips")
    }

    private var routeRow: some View {
        WrapRow(spacing: 6) {
            ForEach(routeLayers) { layer in
                // The effort chip is the one that is labelled with what it is currently
                // highlighting ("best 2 s") rather than with its own name — and with no
                // record selected there is nothing to name, so there is no chip.
                if layer != .effort {
                    chip(layer, swatch: Self.swatch(for: layer))
                } else if let effort {
                    chip(.effort, swatch: .line(DesignTokens.Effort.window),
                         label: effort.label.lowercased())
                }
            }
        }
    }

    /// The events, clean jibe first.
    ///
    /// It leads because it is the mark a rider opens the map to find, and because it is the
    /// one mark here that is not a rung of the ladder: putting it after "fell in" would file
    /// the strict verdict as the ladder's fourth outcome, which is precisely what it is not
    /// (docs/presentation.md, "Clean jibe"). The order is the scope's
    /// (`MapLayerScope.layers`), so a map's chips read in the same order as every other
    /// map's, minus the ones it cannot draw.
    private var markerRow: some View {
        WrapRow(spacing: 6) {
            ForEach(markerLayers) { layer in
                chip(layer, swatch: Self.swatch(for: layer))
            }
        }
    }

    /// **A chip has to look like the thing it toggles**, so the swatch is the catalogue's
    /// twelfth column: a line for the route tints, a dot for the outcome ladder, the mark's
    /// own glyph for the categories the map draws as glyphs. One table, read by all three
    /// legends.
    private static func swatch(for layer: MapLayer) -> LegendChip.Swatch {
        switch layer {
        case .flying: return .line(DesignTokens.Phase.flying)
        case .offFoil: return .line(DesignTokens.Phase.offFoil)
        case .pumping: return .line(EventMarkerStyle.pumping)
        case .effort: return .line(DesignTokens.Effort.window)
        case .direction: return .glyph("chevron.up", DesignTokens.Direction.ink)
        case .cleanJibe: return .glyph(DesignTokens.Glyph.cleanJibe, EventMarkerStyle.cleanJibe)
        case .flewThrough: return .dot(EventMarkerStyle.color(.flew))
        case .touchdown: return .dot(EventMarkerStyle.color(.touchdown))
        case .fellIn: return .dot(EventMarkerStyle.color(.fell))
        case .courseChange: return .dot(EventMarkerStyle.color(.course))
        case .takeoff: return .glyph("arrow.up.circle.fill", EventMarkerStyle.takeoff)
        case .splash: return .glyph("drop.fill", EventMarkerStyle.splash)
        }
    }

    /// Only shown while something *is* hidden: an always-present reset would read as
    /// clutter, and while it is present it is the one-tap way back to the full picture.
    private var showAllButton: some View {
        Button("show all") { store.showAllMapLayers(in: scope) }
            .font(.caption2.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Show all map categories")
    }

    private func chip(_ layer: MapLayer, swatch: LegendChip.Swatch,
                      label: String? = nil) -> some View {
        LegendChip(layer: layer,
                   label: label ?? layer.label,
                   swatch: swatch,
                   isOn: visibility.isVisible(layer),
                   count: tally.count(layer)) {
            store.toggleMapLayer(layer, in: scope)
        }
    }
}

/// One legend entry. Three states, deliberately distinguishable without colour vision:
/// **on** (filled swatch, tinted capsule), **off** (dimmed, struck-through label, dashed
/// outline) and **absent** (no capsule, tertiary text, not a button at all).
private struct LegendChip: View {
    enum Swatch {
        case line(Color)
        case dot(Color)
        /// An SF Symbol, for the marker categories whose map annotation is a glyph rather
        /// than a plain dot — the chip has to look like the thing it toggles.
        case glyph(String, Color)
    }

    let layer: MapLayer
    let label: String
    let swatch: Swatch
    let isOn: Bool
    let count: Int
    let toggle: () -> Void

    private var isToggleable: Bool { count > 0 }

    var body: some View {
        if isToggleable {
            Button(action: toggle) { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isOn ? "Hide" : "Show") \(layer.accessibilityNoun)")
                .accessibilityValue("\(count)")
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(layer.accessibilityNoun), none in this session")
        }
    }

    private var content: some View {
        HStack(spacing: 5) {
            swatchView
            Text(label)
                .strikethrough(isToggleable && !isOn)
                .lineLimit(1)
        }
        .padding(.horizontal, isToggleable ? 8 : 0)
        .padding(.vertical, isToggleable ? 4 : 0)
        .background(background)
        .foregroundStyle(isToggleable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        .opacity(opacity)
        .contentShape(.capsule)
    }

    @ViewBuilder
    private var background: some View {
        if isToggleable && isOn {
            Capsule().fill(Color.secondary.opacity(0.14))
        } else if isToggleable {
            // Dashed rather than solid: "this is a slot that is currently empty", which is
            // a different statement from the filled capsule of a live category.
            Capsule().strokeBorder(Color.secondary.opacity(0.45),
                                   style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
    }

    private var opacity: Double {
        guard isToggleable else { return 0.45 }
        return isOn ? 1 : 0.5
    }

    @ViewBuilder
    private var swatchView: some View {
        switch swatch {
        case .line(let color):
            Capsule()
                .fill(isOn ? color : Color.clear)
                .stroke(color, lineWidth: isOn ? 0 : 1)
                .frame(width: 16, height: 5)
        case .dot(let color):
            Circle()
                .fill(isOn ? color : Color.clear)
                .stroke(color, lineWidth: isOn ? 0 : 1.5)
                .frame(width: 9, height: 9)
        case .glyph(let name, let color):
            Image(systemName: name)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .opacity(isOn ? 1 : 0.55)
                .frame(width: 11, height: 11)
        }
    }
}

/// A row of chips that wraps instead of squeezing.
///
/// The legend outgrew a single `HStack` when pumping, takeoff and splash joined it: on a
/// narrow iPhone six chips in one line either truncate their labels or push each other off
/// the edge, and a chip whose label is gone is not a legend entry. Written against
/// `Layout` rather than a `LazyVGrid` because the chips are different widths and should
/// keep them — a grid would give "splash" the same column as "course change".
private struct WrapRow: Layout {
    var spacing: CGFloat = 6
    /// Vertical gap between wrapped lines; a touch tighter than the horizontal one, which
    /// reads as one block rather than two rows.
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let lines = layout(subviews, width: proposal.width ?? .infinity)
        let height = lines.reduce(0) { $0 + $1.height } +
            lineSpacing * CGFloat(max(0, lines.count - 1))
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var y = bounds.minY
        for line in layout(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var range: Range<Int>
        var width: CGFloat
        var height: CGFloat
    }

    private func layout(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var start = 0
        var x: CGFloat = 0
        var height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let advance = x == 0 ? size.width : x + spacing + size.width
            if advance > width, index > start {
                lines.append(Line(range: start..<index, width: x, height: height))
                start = index
                x = size.width
                height = size.height
            } else {
                x = advance
                height = max(height, size.height)
            }
        }
        if start < subviews.count {
            lines.append(Line(range: start..<subviews.count, width: x, height: height))
        }
        return lines
    }
}

extension SessionDetail {

    /// What this session actually contains per legend category — the input to "is this chip
    /// a control or just a caption?".
    func layerTally(effort: RecordEffort?) -> MapLayerTally {
        var tally = MapLayerTally()
        for segment in segments { tally.add(segment.flying ? .flying : .offFoil) }
        // Counted per run of track, not per chevron: how many arrows the camera decides to
        // draw is a question about the *camera*, and the chip has to be live or inert
        // before anything has been laid out.
        tally.add(.direction, segments.count)
        for marker in markers {
            tally.add(marker.layer)
            if marker.isCleanJibe { tally.add(.cleanJibe) }
        }
        tally.add(.pumping, pumpSpans.count)
        tally.add(.takeoff, takeoffMarks.count)
        tally.add(.splash, splashMarks.count)
        // Two points is the same floor the map uses before it draws the highlight at all.
        if let effort, effort.points.count >= 2 { tally.add(.effort) }
        return tally
    }

    /// The markers left after the legend's filter — the one list the map and the chart both
    /// draw, so the two can never disagree about what is on screen.
    func visibleMarkers(_ visibility: MapLayerVisibility) -> [EventMarker] {
        markers.filter { marker in marker.layers.allSatisfy(visibility.isVisible) }
    }

    /// The rejected sweeps — bear-aways and round-ups. Their own list because the Turns map
    /// draws them as *context* behind the `courseChange` chip while its type/side filter is
    /// about counted maneuvers only: a course change has no verdict, no score and no entry
    /// tack, so it can never be one of the rows.
    var courseChangeMarkers: [EventMarker] {
        markers.filter { $0.tone == .course }
    }
}
