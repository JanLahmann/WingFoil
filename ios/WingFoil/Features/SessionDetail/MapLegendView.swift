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
struct MapLegendView: View {
    let detail: SessionDetail
    /// The GP3S effort currently highlighted, which is what the `.effort` chip is labelled
    /// with. No effort selected ⇒ no chip, rather than a chip with nothing to name.
    let effort: SessionDetail.RecordEffort?
    /// True on the full-screen map, where the legend floats over the map and the
    /// explanatory captions would cover the water.
    var compact = false

    @Environment(SessionStore.self) private var store

    private var visibility: MapLayerVisibility { store.mapLayers }
    private var tally: MapLayerTally { detail.layerTally(effort: effort) }

    private var hasMarkers: Bool {
        !detail.markers.isEmpty || !detail.takeoffMarks.isEmpty
            || !detail.splashMarks.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            lineRow
            if hasMarkers { markerRow }
            if !compact {
                VStack(alignment: .leading, spacing: 3) {
                    Text(caption)
                    if let note = takeoffNote { Text(note) }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var caption: String {
        var text = "Tap a chip to hide or show it on the map and chart."
        if !detail.segments.isEmpty {
            text += " Chevrons point the way you were riding."
        }
        if !detail.markers.isEmpty {
            text += " Solid = maneuver outcome · hollow = straight-line flight end."
        }
        return text
    }

    /// The takeoff chip now toggles two kinds of mark, and a legend that named only one of
    /// them would leave the reader guessing what the red arrow means.
    ///
    /// This note used to apologize: the failed attempts were counted and "carried no
    /// position". Engine 0.3.0 serializes the pumping episodes, so they carry a timestamp
    /// and therefore a place on the water — the sentence is now a key rather than a caveat.
    /// The count still comes from `summary.takeoff.failedAttempts` rather than from the
    /// marks: a mark is missing wherever the GPS had no fix, and the number the rider is
    /// owed is how often he tried, not how often we could draw it.
    private var takeoffNote: String? {
        let failed = detail.analysis.summary.takeoff.failedAttempts
        guard failed > 0 else { return nil }
        return "Takeoff carries both halves of an attempt: arrow up = got up, "
            + "red u-turn = did not. \(failed) failed attempt"
            + "\(failed == 1 ? "" : "s") this session."
    }

    // MARK: - Rows

    private var lineRow: some View {
        WrapRow(spacing: 6) {
            chip(.flying, swatch: .line(.teal))
            chip(.offFoil, swatch: .line(.secondary))
            chip(.pumping, swatch: .line(EventMarkerStyle.pumping))
            // Sits with the line chips rather than the marker ones because that is what it
            // is about — the route, not the events on it — even though hiding it removes
            // the arrows outright the way a marker layer does.
            chip(.direction, swatch: .glyph("chevron.up", .secondary))
            if let effort {
                chip(.effort, swatch: .line(.orange), label: effort.label.lowercased())
            }
            if !visibility.isEverythingVisible { showAllButton }
        }
    }

    private var markerRow: some View {
        WrapRow(spacing: 6) {
            chip(.flewThrough, swatch: .dot(EventMarkerStyle.color(.flew)))
            chip(.touchdown, swatch: .dot(EventMarkerStyle.color(.touchdown)))
            chip(.fellIn, swatch: .dot(EventMarkerStyle.color(.fell)))
            chip(.courseChange, swatch: .dot(EventMarkerStyle.color(.course)))
            chip(.takeoff, swatch: .glyph("arrow.up.circle.fill", EventMarkerStyle.takeoff))
            chip(.splash, swatch: .glyph("drop.fill", EventMarkerStyle.splash))
        }
    }

    /// Only shown while something *is* hidden: an always-present reset would read as
    /// clutter, and while it is present it is the one-tap way back to the full picture.
    private var showAllButton: some View {
        Button("show all") { store.showAllMapLayers() }
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
            store.toggleMapLayer(layer)
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
        for marker in markers { tally.add(marker.layer) }
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
        markers.filter { visibility.isVisible($0.layer) }
    }
}
