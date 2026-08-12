import SwiftUI
import WingFoilKit

/// Draws a normalized track outline (`TrackThumbnail.Point`, 0…1 in both axes, aspect
/// already preserved by the projection) into whatever rectangle it is given.
///
/// One drawing definition, three users: the library row's thumbnail, the share card, and
/// anything later that needs a track at a glance. `Canvas` rather than `Path` shapes
/// because a session is a few hundred vertices in two colours, and one draw call beats a
/// view per segment in a scrolling list.
struct TrackOutlineView: View {
    let thumbnail: TrackThumbnail
    var flyingColor: Color = .teal
    var offFoilColor: Color = .secondary
    var lineWidth: Double = 1.6
    /// Off-foil legs are drawn thinner; the flying line is the one that matters.
    var offFoilScale: Double = 0.6
    /// Inset so a stroke on the bounding edge is not clipped in half.
    var padding: Double = 2

    var body: some View {
        Canvas(opaque: false) { context, size in
            let box = CGRect(x: padding, y: padding,
                             width: max(size.width - padding * 2, 1),
                             height: max(size.height - padding * 2, 1))
            // The normalization is square; fit it into the (possibly wider) view without
            // stretching, centred.
            let side = min(box.width, box.height)
            let originX = box.minX + (box.width - side) / 2
            let originY = box.minY + (box.height - side) / 2

            func place(_ point: TrackThumbnail.Point) -> CGPoint {
                CGPoint(x: originX + point.x * side, y: originY + point.y * side)
            }

            for run in thumbnail.runs {
                var path = Path()
                path.addLines(run.points.map(place))
                context.stroke(
                    path,
                    with: .color(run.flying ? flyingColor : offFoilColor.opacity(0.55)),
                    style: StrokeStyle(lineWidth: run.flying ? lineWidth
                                                             : lineWidth * offFoilScale,
                                       lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The speed sparkline that sits beside the thumbnail: a filled area under a line, with
/// the values already normalized to 0…1 of the session's peak.
struct SpeedSparklineView: View {
    let values: [Double]
    var tint: Color = .accentColor

    var body: some View {
        Canvas(opaque: false) { context, size in
            guard values.count >= 2 else { return }
            let step = size.width / Double(values.count - 1)
            // A flat line at the very bottom reads as "no data"; lift the baseline so a
            // slow session still shows a shape.
            let usable = max(size.height - 2, 1)
            func point(_ index: Int) -> CGPoint {
                CGPoint(x: Double(index) * step, y: size.height - 1 - values[index] * usable)
            }

            var line = Path()
            line.addLines((0..<values.count).map(point))

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            context.fill(area, with: .color(tint.opacity(0.18)))
            context.stroke(line, with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round,
                                              lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// "9 · 9 · 12" — flew / touched down / fell, in the outcome palette.
struct OutcomeTally: View {
    let flewThrough: Int
    let touchdown: Int
    let fellIn: Int
    var font: Font = .caption2

    var total: Int { flewThrough + touchdown + fellIn }

    var body: some View {
        if total > 0 {
            HStack(spacing: 3) {
                part(flewThrough, EventMarkerStyle.color(.flew))
                separator
                part(touchdown, EventMarkerStyle.color(.touchdown))
                separator
                part(fellIn, EventMarkerStyle.color(.fell))
            }
            .font(font.weight(.semibold).monospacedDigit())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(flewThrough) flew through, \(touchdown) touchdowns, "
                                + "\(fellIn) falls")
        }
    }

    private func part(_ value: Int, _ color: Color) -> some View {
        Text("\(value)").foregroundStyle(color)
    }

    private var separator: some View {
        Text("·").foregroundStyle(.tertiary)
    }
}
