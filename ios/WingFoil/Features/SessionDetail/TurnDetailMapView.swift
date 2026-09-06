import SwiftUI
import WingFoilKit

/// One turn, drawn at the scale of one turn.
///
/// **Why this is a `Canvas` and not a `Map`.** Two reasons, and both are disqualifying on
/// their own. The frame has to *rotate* — wind up is the whole point of the orientation
/// control, and MapKit's heading is a camera animation, not a projection this drawing can be
/// composed against. And the picture has to be deterministic: a turn is thirty metres of
/// water, the tick marks are one second apart, and a map that reprojects on a camera settle
/// would move them under the reader. So the geometry arrives already in metres
/// (`TurnSlice`) and this view only places it.
///
/// There is deliberately no ground under it. A satellite tile at 30 m across is a photograph
/// of water, and it would bury every one of the six things this drawing is actually saying.
struct TurnDetailMapView: View {
    let slice: TurnSlice
    /// The session's best clean jibe of the same rotation, laid underneath — see
    /// `TurnSlice.ghost`. nil when the toggle is off or there is nothing to compare with.
    let ghost: TurnSlice?
    let windUp: Bool
    /// Seconds from the turn's start, when the strip is being scrubbed.
    let playheadRt: Double?

    /// Layout points reserved on every edge, so a mark centred on the outermost vertex is not
    /// clipped in half against the frame.
    private static let inset: CGFloat = 14

    private var frame: TurnSlice.Bounds? {
        guard let base = slice.bounds(windUp: windUp) else { return nil }
        guard let ghostBounds = ghost?.bounds(windUp: windUp) else { return base }
        return base.union(ghostBounds)
    }

    var body: some View {
        Canvas { context, size in
            guard let frame, slice.hasGeometry else { return }
            let place = placer(frame, in: size)

            drawGhost(context: &context, place: place)
            drawContextTrack(context: &context, place: place)
            drawTurn(context: &context, place: place)
            drawSecondTicks(context: &context, place: place)
            drawMarks(context: &context, place: place)
            drawPlayhead(context: &context, place: place)
            drawScaleBar(context: &context, size: size, scale: place.scale)
            drawSpeedLegend(context: &context, size: size)
            drawOrientationMarks(context: &context, size: size)
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
        .figureHeight(regular: 260, compact: 200)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Placement

    private struct Placer {
        var scale: CGFloat
        var offsetX: CGFloat
        var offsetY: CGFloat

        func callAsFunction(_ point: TurnSlice.Point) -> CGPoint {
            // Screen y grows downward, the slice's grows north.
            CGPoint(x: offsetX + CGFloat(point.x) * scale,
                    y: offsetY - CGFloat(point.y) * scale)
        }
    }

    /// One scale for both axes — the shape has to stay honest — and the frame centred in the
    /// view, which is what makes a turn drawn wind-up and the same turn drawn north-up read as
    /// two views of one thing rather than two different sizes.
    private func placer(_ bounds: TurnSlice.Bounds, in size: CGSize) -> Placer {
        let w = max(size.width - Self.inset * 2, 1)
        let h = max(size.height - Self.inset * 2, 1)
        let scale = min(w / CGFloat(max(bounds.width, TurnSlice.minSpanM)),
                        h / CGFloat(max(bounds.height, TurnSlice.minSpanM)))
        return Placer(scale: scale,
                      offsetX: size.width / 2 - CGFloat(bounds.centerX) * scale,
                      offsetY: size.height / 2 + CGFloat(bounds.centerY) * scale)
    }

    private func path(_ points: [TurnSlice.Point], place: Placer) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let cg = place(point)
            if index == 0 { path.move(to: cg) } else { path.addLine(to: cg) }
        }
        return path
    }

    // MARK: - The six things it draws

    /// The comparison turn, underneath everything, dashed, in the clean-jibe ink.
    ///
    /// Dashed and faint on purpose: it is a reference, not a second measurement, and a solid
    /// line of equal weight would turn one picture into two.
    private func drawGhost(context: inout GraphicsContext, place: Placer) {
        guard let ghost, ghost.hasGeometry else { return }
        context.stroke(path(ghost.points(windUp: windUp), place: place),
                       with: .color(DesignTokens.Clean.jibe.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round,
                                          dash: [5, 4]))
    }

    /// The padded window, in neutral grey: where he came from and where he went. It is
    /// context, so it is drawn thin and it recedes.
    private func drawContextTrack(context: inout GraphicsContext, place: Placer) {
        context.stroke(path(slice.points(windUp: windUp), place: place),
                       with: .color(DesignTokens.Phase.offFoil.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    /// The turn itself, thick, one short segment at a time so the speed can be read off the
    /// line.
    ///
    /// **The ink is the speed ramp** (`TurnSpeedRamp`, `speed.*` in design/tokens.json): five
    /// stops, cold to hot, anchored so that a standstill is the cold end, *this turn's entry
    /// speed* is the middle stop — which is the flying teal, the ink the app already means
    /// flying with — and 1.3× the entry speed is the hot end. Until 6 Sep 2026 the line was
    /// mixed between the off-foil grey and the flying teal instead, which could say only
    /// "more teal than grey" and drew a turn *accelerated* through exactly like one that
    /// merely held its speed. The width still ramps with it, so the line reads without
    /// colour too, and the legend at the foot of the card puts knots on all of it
    /// (docs/presentation.md, "Turn detail").
    private func drawTurn(context: inout GraphicsContext, place: Placer) {
        let points = slice.points(windUp: windUp).filter(\.inTurn)
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            var segment = Path()
            segment.move(to: place(points[index]))
            segment.addLine(to: place(points[index + 1]))
            let kn = (points[index].kn + points[index + 1].kn) / 2
            let position = TurnSpeedRamp.position(kn: kn, entryKn: slice.speed.entryKn)
            context.stroke(segment,
                           with: .color(TurnSpeedRamp.color(at: position)),
                           // The width ramp is read off the *entry* half of the colour ramp,
                           // so a turn held at its entry speed is drawn at full weight and a
                           // quicker one is not drawn fatter still: past the anchor the extra
                           // is the colour's to say.
                           style: StrokeStyle(lineWidth: 3 + 3 * min(position * 2, 1),
                                              lineCap: .round, lineJoin: .round))
        }
    }

    /// A tick across the line every whole second, so the drawing carries time as well as
    /// shape: evenly spaced ticks are a rider holding his speed, bunched ones are a rider who
    /// stopped. Drawn perpendicular to the heading, and skipped where the slice has no usable
    /// bearing to be perpendicular to.
    private func drawSecondTicks(context: inout GraphicsContext, place: Placer) {
        let points = slice.points(windUp: windUp).filter(\.inTurn)
        guard points.count >= 2 else { return }
        var next = ceil(points[0].rt)
        for point in points {
            guard point.rt >= next else { continue }
            next = floor(point.rt) + 1
            guard let heading = point.headingDeg else { continue }
            let radians = (heading + 90) * .pi / 180
            let dx = CGFloat(sin(radians)) * 4
            let dy = -CGFloat(cos(radians)) * 4
            let centre = place(point)
            var tick = Path()
            tick.move(to: CGPoint(x: centre.x - dx, y: centre.y - dy))
            tick.addLine(to: CGPoint(x: centre.x + dx, y: centre.y + dy))
            context.stroke(tick, with: .color(Color(.label).opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }

    /// The two moments worth a mark: where the speed bottomed out, and how it ended.
    private func drawMarks(context: inout GraphicsContext, place: Placer) {
        if let low = slice.point(atRelative: slice.speed.minRt, windUp: windUp) {
            let centre = place(low)
            let ring = CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10)
            context.stroke(Path(ellipseIn: ring), with: .color(Color(.label).opacity(0.75)),
                           lineWidth: 2)
        }
        if let end = slice.points(windUp: windUp).last(where: \.inTurn) {
            let centre = place(end)
            let dot = CGRect(x: centre.x - 5.5, y: centre.y - 5.5, width: 11, height: 11)
            context.fill(Path(ellipseIn: dot),
                         with: .color(TurnOutcomeStyle.color(TurnOutcomeKind(slice.turn.outcome))))
            context.stroke(Path(ellipseIn: dot), with: .color(Color(.systemBackground)),
                           lineWidth: 1.5)
        }
    }

    /// Where the strip's finger is. The same "you are here, nothing happened here" shape the
    /// session map's playhead uses — a ring rather than a dot, so it cannot be misread as an
    /// outcome.
    private func drawPlayhead(context: inout GraphicsContext, place: Placer) {
        guard let playheadRt,
              let point = slice.point(atRelative: playheadRt, windUp: windUp) else { return }
        let centre = place(point)
        let halo = CGRect(x: centre.x - 11, y: centre.y - 11, width: 22, height: 22)
        context.fill(Path(ellipseIn: halo),
                     with: .color(DesignTokens.Phase.flying.opacity(0.25)))
        let dot = CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: dot), with: .color(DesignTokens.Phase.flying))
        context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 2)
    }

    /// A bar and its number, bottom left. Without it the drawing has no size at all: the frame
    /// is fitted to the turn, so a tight pivot and a wide arc come out the same width on
    /// screen and only this line says which was which.
    private func drawScaleBar(context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        let metres = TurnSlice.scaleBarM(forSpanM: Double((size.width - Self.inset * 2) / scale))
        let length = CGFloat(metres) * scale
        guard length.isFinite, length > 8, length < size.width - Self.inset * 2 else { return }
        let y = size.height - Self.inset
        var bar = Path()
        bar.move(to: CGPoint(x: Self.inset, y: y))
        bar.addLine(to: CGPoint(x: Self.inset + length, y: y))
        context.stroke(bar, with: .color(Color(.label).opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
        context.draw(Text("\(Int(metres)) m").font(.caption2)
                        .foregroundStyle(Color(.label).opacity(0.6)),
                     at: CGPoint(x: Self.inset + length / 2, y: y - 9), anchor: .bottom)
    }

    /// **Both references, always** — a needle to north labelled `N`, and an arrow labelled
    /// `wind` blowing from its tail toward its head. Top right, small, in ink rather than a
    /// hue, so neither competes with the track.
    ///
    /// Until 6 Sep 2026 there was one arrow: north in north-up, the wind in wind-up. That
    /// made the mark the *label* of the orientation control rather than information — and it
    /// answered the question the rider already knew the answer to while hiding the other one.
    /// A jibe is read against both: which way the water was going, and which way home is. So
    /// in wind-up the wind arrow points straight down the frame and `N` swings with the
    /// rotation; in north-up `N` points up the frame and the wind arrow swings. The wind
    /// arrow is absent — not drawn at some default — on a session with no wind direction,
    /// which is the same gate that disables the wind-up option.
    private func drawOrientationMarks(context: inout GraphicsContext, size: CGSize) {
        let y = Self.inset + 10
        // North sits in the corner and the wind beside it, in that order whichever frame is
        // drawn: a mark that moved between orientations would have to be re-found every time
        // the control is tapped.
        drawArrow(context: &context, centre: CGPoint(x: size.width - Self.inset - 10, y: y),
                  rotationDeg: windUp ? -(slice.windDirDeg ?? 0) : 0, label: "N")
        if let windDirDeg = slice.windDirDeg {
            // The heading the wind blows *toward*: the tail is where it comes from, so the
            // head is 180° round from the direction the estimate names. In wind up that is
            // straight down the page by construction.
            drawArrow(context: &context,
                      centre: CGPoint(x: size.width - Self.inset - 44, y: y),
                      rotationDeg: (windUp ? 180 : windDirDeg + 180), label: "wind")
        }
    }

    /// One small arrow pointing up, rotated clockwise by `rotationDeg` about its own centre,
    /// with its word underneath. Screen y grows downward, so a positive rotation of the
    /// transform is a clockwise turn on the page — which is what a compass bearing is.
    private func drawArrow(context: inout GraphicsContext, centre: CGPoint,
                           rotationDeg: Double, label: String) {
        var arrow = Path()
        arrow.move(to: CGPoint(x: centre.x, y: centre.y - 9))
        arrow.addLine(to: CGPoint(x: centre.x - 4.5, y: centre.y + 5))
        arrow.addLine(to: CGPoint(x: centre.x, y: centre.y + 1.5))
        arrow.addLine(to: CGPoint(x: centre.x + 4.5, y: centre.y + 5))
        arrow.closeSubpath()
        let rotated = arrow.applying(
            CGAffineTransform(translationX: centre.x, y: centre.y)
                .rotated(by: rotationDeg * .pi / 180)
                .translatedBy(x: -centre.x, y: -centre.y))
        context.fill(rotated, with: .color(Color(.label).opacity(0.5)))
        context.draw(Text(label).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(.label).opacity(0.55)),
                     at: CGPoint(x: centre.x, y: centre.y + 7), anchor: .top)
    }

    /// The ramp, with knots on it — bottom right, beside the scale bar.
    ///
    /// Two numbers make the whole line readable: the entry speed, which is the ramp's anchor
    /// and the number the score is a ratio of, and the top of the bar, which is the fastest
    /// the rider actually went through this turn (never past the ramp's cap — there is no
    /// colour beyond it). A turn that never beat its entry speed gets a bar that ends at the
    /// entry speed and two labels instead of three: the top half of the ramp went unused, and
    /// printing a number nobody rode would be the overclaim.
    private func drawSpeedLegend(context: inout GraphicsContext, size: CGSize) {
        let entryKn = slice.speed.entryKn
        guard entryKn >= TurnSpeedRamp.minReferenceKn else { return }
        let drawn = slice.points(windUp: windUp).filter(\.inTurn).map(\.kn)
        let topKn = TurnSpeedRamp.legendTopKn(entryKn: entryKn, maxKn: drawn.max() ?? entryKn)
        let barWidth: CGFloat = 104
        let barHeight: CGFloat = 5
        let right = size.width - Self.inset
        let left = right - barWidth
        // Left of the scale bar's own label, or the two would fight for the same strip.
        guard left > Self.inset + 60 else { return }
        let y = size.height - Self.inset - barHeight

        let stops = stride(from: 0.0, through: 1.0, by: 0.125).map { fraction in
            Gradient.Stop(color: TurnSpeedRamp.color(kn: topKn * fraction, entryKn: entryKn),
                          location: fraction)
        }
        let bar = CGRect(x: left, y: y, width: barWidth, height: barHeight)
        context.fill(Path(roundedRect: bar, cornerRadius: barHeight / 2),
                     with: .linearGradient(Gradient(stops: stops),
                                           startPoint: CGPoint(x: left, y: y),
                                           endPoint: CGPoint(x: right, y: y)))

        let label = Color(.label).opacity(0.6)
        func text(_ string: String) -> Text {
            Text(string).font(.system(size: 9).monospacedDigit()).foregroundStyle(label)
        }
        context.draw(text("0"), at: CGPoint(x: left, y: y - 2), anchor: .bottomLeading)
        context.draw(text(String(format: "%.1f kn", topKn)),
                     at: CGPoint(x: right, y: y - 2), anchor: .bottomTrailing)
        // The anchor's own tick, unless it has arrived at the top of the bar — where the two
        // numbers would be the same number printed twice.
        let entryFraction = CGFloat(entryKn / topKn)
        if entryFraction < 0.88 {
            let x = left + barWidth * entryFraction
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: y - 1))
            tick.addLine(to: CGPoint(x: x, y: y + barHeight + 1))
            context.stroke(tick, with: .color(Color(.label).opacity(0.45)), lineWidth: 1)
            context.draw(text(String(format: "%.1f", entryKn)),
                         at: CGPoint(x: x, y: y - 2), anchor: .bottom)
        }
    }

    // MARK: - Spoken

    private var accessibilityText: String {
        let turn = slice.turn
        var parts = [
            "\(TurnAnalytics.typeLabel(turn.type)) drawn \(windUp ? "wind up" : "north up")",
            String(format: "%.1f knots in, %.1f at the low point after %.0f seconds, "
                   + "%.1f out", slice.speed.entryKn, slice.speed.minKn,
                   slice.speed.minRt, slice.speed.exitKn),
            String(format: "%.0f seconds long, %.0f metre radius", slice.durationS,
                   turn.radiusM),
            TurnOutcomeKind(turn.outcome).label,
        ]
        if let windDirDeg = slice.windDirDeg {
            parts.append(String(format: "wind from %.0f degrees", windDirDeg))
        }
        if ghost != nil { parts.append("compared with your best clean jibe, dashed") }
        return parts.joined(separator: ", ")
    }
}
