import SwiftUI
import WingFoilKit

/// Draws a normalized track outline (`TrackThumbnail.Point`, 0…1 in both axes, aspect
/// already preserved by the projection) into whatever rectangle it is given, optionally
/// with the session's outcome and splash marks on it.
///
/// One drawing definition, three users: the library row's thumbnail, the share card, and
/// anything later that needs a track at a glance. `Canvas` rather than `Path` shapes
/// because a session is a few hundred vertices in two colours, and one draw call beats a
/// view per segment in a scrolling list.
struct TrackOutlineView: View {
    let thumbnail: TrackThumbnail
    var flyingColor: Color = DesignTokens.Phase.flying
    var offFoilColor: Color = DesignTokens.Phase.offFoil
    var lineWidth: Double = 1.6
    /// Off-foil legs are drawn thinner; the flying line is the one that matters.
    var offFoilScale: Double = 0.6
    /// Inset so a stroke on the bounding edge is not clipped in half.
    var padding: Double = 2

    /// Fit the *track* to the box rather than the square it was normalized into.
    ///
    /// The projection centres the shorter axis in a square (so the shape stays honest), and
    /// this view then inscribes that square in the view rect. For a session sailed up and
    /// down one reach — which is most of them — the result is a line across the middle of a
    /// square parked in the middle of a wider box: two rounds of letterboxing, and the
    /// "there is a lot of white space around it" the share card was reported for. With this
    /// on, the scale comes from the track's own extent (`TrackThumbnail.contentBox`)
    /// instead, so the ride touches the edges. Off for the library row, whose thumbnail
    /// sits in a fixed square well and reads as a consistent shape at a glance.
    var fillsBox = false

    /// Radius of an outcome dot, in points. 0 draws none — the list row's 44 pt square has
    /// no room for fifty of them, and the marks are a share-card idea.
    var markRadius: Double = 0

    var body: some View {
        Canvas(opaque: false) { context, size in
            // The inset carries the mark radius as well as the stroke's, because a dot on
            // the outermost vertex is centred *on* the fitted edge and would otherwise lose
            // its outer half to the canvas bounds.
            let inset = padding + markRadius
            let box = CGRect(x: inset, y: inset,
                             width: max(size.width - inset * 2, 1),
                             height: max(size.height - inset * 2, 1))
            let fit = Self.fit(thumbnail, in: box, fillsBox: fillsBox)

            func place(x: Double, y: Double) -> CGPoint {
                CGPoint(x: fit.originX + x * fit.scale, y: fit.originY + y * fit.scale)
            }

            for run in thumbnail.runs {
                var path = Path()
                path.addLines(run.points.map { place(x: $0.x, y: $0.y) })
                context.stroke(
                    path,
                    with: .color(run.flying ? flyingColor : offFoilColor.opacity(0.55)),
                    style: StrokeStyle(lineWidth: run.flying ? lineWidth
                                                             : lineWidth * offFoilScale,
                                       lineCap: .round, lineJoin: .round))
            }

            guard markRadius > 0 else { return }
            // Splashes last, so the one mark that is *evidence* rather than a verdict sits
            // on top of the verdict it belongs to instead of hiding under it.
            let ordered = thumbnail.marks.sorted { ($0.kind == .splash ? 1 : 0)
                                                 < ($1.kind == .splash ? 1 : 0) }
            for mark in ordered {
                let centre = place(x: mark.x, y: mark.y)
                let shape = Self.markPath(mark.kind, at: centre, radius: markRadius)
                // A dark halo first: a green dot on a teal reach is invisible without one,
                // and the card is exported over a photo as often as over the gradient.
                context.stroke(shape, with: .color(.black.opacity(0.55)),
                               style: StrokeStyle(lineWidth: markRadius * 0.75))
                context.fill(shape, with: .color(Self.markColor(mark.kind)))
            }
        }
        .accessibilityHidden(true)
    }

    /// Where the unit box lands in the view, as an origin and one uniform scale. Uniform
    /// because a track stretched to fill both axes is a different-shaped session.
    static func fit(_ thumbnail: TrackThumbnail, in box: CGRect,
                    fillsBox: Bool) -> (originX: Double, originY: Double, scale: Double) {
        // The square the normalization produced, inscribed and centred — the behaviour
        // every caller had before `fillsBox`, and still the fallback for a track with no
        // extent at all (a rider who never moved), where fitting to nothing divides by it.
        func inscribed() -> (originX: Double, originY: Double, scale: Double) {
            let side = min(box.width, box.height)
            return (box.minX + (box.width - side) / 2,
                    box.minY + (box.height - side) / 2, side)
        }
        guard fillsBox, let content = thumbnail.contentBox else { return inscribed() }
        let width = content.maxX - content.minX
        let height = content.maxY - content.minY
        guard width > 0.001 || height > 0.001 else { return inscribed() }
        // A perfectly straight leg has zero extent on one axis; that axis then imposes no
        // limit, which is exactly right — `min` takes the other one.
        let scale = min(width > 0.001 ? box.width / width : .infinity,
                        height > 0.001 ? box.height / height : .infinity)
        let centreX = (content.minX + content.maxX) / 2
        let centreY = (content.minY + content.maxY) / 2
        return (box.midX - centreX * scale, box.midY - centreY * scale, scale)
    }

    /// The ladder's inks for the three verdicts, the effort layer's cyan for the splash —
    /// the map's own tokens, so a mark means the same thing on a card as on the map.
    static func markColor(_ kind: TrackThumbnail.Mark.Kind) -> Color {
        switch kind {
        case .flewThrough: DesignTokens.Outcome.flew
        case .touchdown: DesignTokens.Outcome.touchdown
        case .fellIn: DesignTokens.Outcome.fellIn
        case .splash: DesignTokens.Effort.splash
        }
    }

    /// Shape is a channel of its own (docs/presentation.md): the three verdicts are dots,
    /// the splash is a diamond. Colour alone would not separate the swim evidence from the
    /// fell-in verdict it usually sits on — and would separate neither for a reader who
    /// cannot tell cyan from green.
    static func markPath(_ kind: TrackThumbnail.Mark.Kind, at centre: CGPoint,
                         radius: Double) -> Path {
        guard kind == .splash else {
            return Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                          width: radius * 2, height: radius * 2))
        }
        let arm = radius * 1.3
        var path = Path()
        path.move(to: CGPoint(x: centre.x, y: centre.y - arm))
        path.addLine(to: CGPoint(x: centre.x + arm, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + arm))
        path.addLine(to: CGPoint(x: centre.x - arm, y: centre.y))
        path.closeSubpath()
        return path
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
