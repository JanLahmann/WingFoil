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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            lineRow
            if !detail.markers.isEmpty { markerRow }
            if !compact {
                Text(caption)
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
        if !detail.markers.isEmpty {
            text += " Solid = maneuver outcome · hollow = straight-line flight end."
        }
        return text
    }

    // MARK: - Rows

    private var lineRow: some View {
        HStack(spacing: 6) {
            chip(.flying, swatch: .line(.teal))
            chip(.offFoil, swatch: .line(.secondary))
            if let effort {
                chip(.effort, swatch: .line(.orange), label: effort.label.lowercased())
            }
            Spacer(minLength: 0)
            if !visibility.isEverythingVisible { showAllButton }
        }
    }

    private var markerRow: some View {
        HStack(spacing: 6) {
            chip(.flewThrough, swatch: .dot(EventMarkerStyle.color(.flew)))
            chip(.touchdown, swatch: .dot(EventMarkerStyle.color(.touchdown)))
            chip(.fellIn, swatch: .dot(EventMarkerStyle.color(.fell)))
            chip(.courseChange, swatch: .dot(EventMarkerStyle.color(.course)))
            Spacer(minLength: 0)
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
        }
    }
}

extension SessionDetail {

    /// What this session actually contains per legend category — the input to "is this chip
    /// a control or just a caption?".
    func layerTally(effort: RecordEffort?) -> MapLayerTally {
        var tally = MapLayerTally()
        for segment in segments { tally.add(segment.flying ? .flying : .offFoil) }
        for marker in markers { tally.add(marker.layer) }
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
