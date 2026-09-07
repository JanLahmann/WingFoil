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
    /// The shape and its four marks. A turn hands over `TurnSlice.figure`, a straight-line
    /// flight end `FlightEndSlice.figure`, and this view cannot tell which it got — see
    /// `ManeuverFigure`.
    let figure: ManeuverFigure
    /// The session's best clean jibe of the same rotation, laid underneath — see
    /// `TurnSlice.ghost`. nil when the toggle is off, when there is nothing to compare with,
    /// or on a flight end, which has no comparison of its own.
    let ghost: ManeuverFigure?
    let windUp: Bool
    /// Seconds from `t = 0`, when a strip is being scrubbed.
    let playheadRt: Double?
    /// **A tap on the drawing puts the playhead here**, so the strip's rule and the drawing's
    /// dot are the same instant however the reader got there. nil makes the drawing inert,
    /// which is what a thumbnail or a share card would want.
    var onPick: ((Double) -> Void)?
    /// The spoken sentence, which only the owning page can compose — it knows the verdict.
    var spoken: String = ""

    /// The turn page's own call, unchanged: the sheet passes a slice and this is what makes
    /// that keep working while the drawing itself stopped knowing about turns.
    init(slice: TurnSlice, ghost: TurnSlice?, windUp: Bool, playheadRt: Double?,
         onPick: ((Double) -> Void)? = nil) {
        self.figure = slice.figure
        self.ghost = ghost?.figure
        self.windUp = windUp
        self.playheadRt = playheadRt
        self.onPick = onPick
        self.spoken = Self.turnSpoken(slice, windUp: windUp, hasGhost: ghost != nil)
    }

    init(figure: ManeuverFigure, ghost: ManeuverFigure? = nil, windUp: Bool,
         playheadRt: Double?, onPick: ((Double) -> Void)? = nil, spoken: String) {
        self.figure = figure
        self.ghost = ghost
        self.windUp = windUp
        self.playheadRt = playheadRt
        self.onPick = onPick
        self.spoken = spoken
    }

    /// Layout points reserved on every edge, so a mark centred on the outermost vertex is not
    /// clipped in half against the frame.
    private static let inset: CGFloat = 14

    private var frame: TurnSlice.Bounds? {
        guard let base = figure.bounds(windUp: windUp) else { return nil }
        guard let ghostBounds = ghost?.bounds(windUp: windUp) else { return base }
        return base.union(ghostBounds)
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let frame, figure.hasGeometry else { return }
                let place = placer(frame, in: size)

                drawGhost(context: &context, place: place)
                drawContextTrack(context: &context, place: place)
                drawTurn(context: &context, place: place)
                drawSecondTicks(context: &context, place: place)
                drawTimeLabels(context: &context, place: place, size: size)
                drawAxisTick(context: &context, place: place)
                drawMarks(context: &context, place: place)
                drawPlayhead(context: &context, place: place)
                drawScaleBar(context: &context, size: size, scale: place.scale)
                drawSpeedLegend(context: &context, size: size)
                drawOrientationMarks(context: &context, size: size)
            }
            .contentShape(.rect)
            .onTapGesture(coordinateSpace: .local) { pick($0, in: geometry.size) }
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
        .overlay(alignment: .topLeading) { callout }
        .figureHeight(regular: 260, compact: 200)
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }

    /// **What the rider was doing at the instant under the playhead** — four readings, in one
    /// line, top left.
    ///
    /// It answers to the playhead rather than to the tap, deliberately: a finger on the strip
    /// and a finger on the drawing are the same gesture asking the same question, and a
    /// callout that only appeared for one of them would make the two surfaces feel like two
    /// features. Absent until something is scrubbed — the drawing's own marks are the resting
    /// state, and a permanent readout would compete with them.
    ///
    /// TWA is present **only where the wind is known**, which is the same gate that enables
    /// wind up and names tacks and jibes. Heading is always there: it is a compass bearing and
    /// it is true whatever the wind was doing — and it is read off the **north-up** vertex
    /// even while the wind-up frame is drawn, because the rotation has already subtracted the
    /// wind from those headings and printing one would say the TWA twice under two names.
    @ViewBuilder
    private var callout: some View {
        if let playheadRt, let point = figure.point(atRelative: playheadRt, windUp: false) {
            HStack(spacing: 8) {
                reading(String(format: "%+.1f s", point.rt))
                reading(String(format: "%.1f kn", point.kn))
                if let heading = point.headingDeg {
                    reading(String(format: "%.0f°", heading), caption: "hdg")
                }
                if let wind = figure.windDirDeg, let twa = point.twaDeg(windFromDeg: wind) {
                    reading(String(format: "%.0f°", abs(twa)), caption: "TWA")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: .rect(cornerRadius: 8))
            .padding(8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func reading(_ value: String, caption: String? = nil) -> some View {
        HStack(spacing: 2) {
            Text(value).font(.caption2.monospacedDigit())
            if let caption {
                Text(caption).font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - The tap

    /// **A finger on the water picks the nearest sample.** The drawing has been readable
    /// since it was built and inert since it was built: everything on it — the ticks, the
    /// ring, the outcome dot — was something the *page* had decided to mark, and the rider's
    /// own question ("what was I doing *there*, at the top of the arc") had no answer.
    ///
    /// It picks the nearest **vertex**, in metres, in whichever frame is drawn, and hands its
    /// relative time to the page — which puts it in `playheadRt`, which the strips draw as
    /// their rule and this view draws as its dot. So one gesture on either surface moves one
    /// playhead, which is the app's rule everywhere else (docs/presentation.md, "Scrub and
    /// zoom") and was the one place it did not hold.
    ///
    /// **A tap, and deliberately not a drag.** The first version was a
    /// `DragGesture(minimumDistance: 0)`, so a finger run along the arc would keep picking.
    /// Two things killed it on the simulator: both pages live inside a paging `TabView`, and a
    /// zero-distance drag over the drawing both **swallowed the swipe to the next turn** and
    /// fired spuriously as the pager settled — the flight-end page opened with a playhead ring
    /// and a callout nobody had asked for. Scrubbing belongs to the strips, which are not
    /// inside a horizontal gesture; the drawing answers a tap.
    private func pick(_ location: CGPoint, in size: CGSize) {
        guard let onPick, let frame, figure.hasGeometry else { return }
        let place = placer(frame, in: size)
        guard place.scale > 0 else { return }
        let x = Double((location.x - place.offsetX) / place.scale)
        let y = Double((place.offsetY - location.y) / place.scale)
        // A fingertip is about 26 points; in metres that depends entirely on how wide the
        // frame is, which is why the tolerance is computed and not a constant. Outside it
        // the tap was on empty water and picks nothing.
        let tolerance = Double(Self.tapToleranceP / place.scale)
        guard let point = figure.point(nearX: x, y: y, windUp: windUp,
                                       withinM: tolerance) else { return }
        onPick(point.rt)
    }

    /// The tap radius, in layout points rather than metres — a fingertip is a fingertip
    /// whatever the drawing is scaled to.
    private static let tapToleranceP: CGFloat = 26

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
        context.stroke(path(figure.points(windUp: windUp), place: place),
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
        let points = figure.points(windUp: windUp).filter(\.inTurn)
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            var segment = Path()
            segment.move(to: place(points[index]))
            segment.addLine(to: place(points[index + 1]))
            let kn = (points[index].kn + points[index + 1].kn) / 2
            let position = TurnSpeedRamp.position(kn: kn, entryKn: figure.entryKn)
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
        let points = figure.points(windUp: windUp).filter(\.inTurn)
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

    /// **The clock, written on the path**: a small number every five seconds, on the outside
    /// of the curve.
    ///
    /// The second ticks have carried *rhythm* since the drawing was built — bunched ticks are
    /// a rider who stopped — but they could not carry *position*. A reader looking at the
    /// strip's "low at 4.2 s" had to count ticks along the arc to find where on the water that
    /// was, and on a turn whose ticks bunch exactly where he is counting, that is the one
    /// stretch the counting fails on. Five seconds is the interval: closer and the numbers
    /// crowd a six-second jibe, wider and a short turn gets none at all.
    ///
    /// **Across the whole drawn span, not just the sweep**, unlike the second ticks. The pads
    /// are where the approach and the run-out are, and "−5" is exactly as much of an answer
    /// as "+5" to a rider asking where he was before it started. The negative sign is kept —
    /// it is what says which side of the sweep the number is on.
    ///
    /// **Outside the curve**, which is the side away from the centre of rotation, so the
    /// numbers never sit inside the arc where the ring, the outcome dot and the ghost already
    /// are. Where the sweep's own rate cannot say which side that is, the label goes to the
    /// right of the heading, which is a choice and not a claim.
    private func drawTimeLabels(context: inout GraphicsContext, place: Placer,
                                size: CGSize) {
        let points = figure.points(windUp: windUp)
        guard points.count >= 2 else { return }
        let axisAt = figure.axisRt.flatMap { figure.point(atRelative: $0, windUp: windUp) }
            .map { place($0) }
        for (rt, point) in figure.pathLabels(everyS: Self.labelEveryS, windUp: windUp) {
            guard let heading = point.headingDeg else { continue }
            let centre = place(point)
            // The `axis` word owns its own patch of the drawing; a number printed over it
            // makes two marks unreadable instead of one.
            if let axisAt, hypot(axisAt.x - centre.x, axisAt.y - centre.y) < 26 { continue }
            let outward = (heading + 90 * outwardSign(at: point, in: points)) * .pi / 180
            let at = CGPoint(x: centre.x + CGFloat(sin(outward)) * Self.labelOffsetP,
                             y: centre.y - CGFloat(cos(outward)) * Self.labelOffsetP)
            // Top right is the north/wind block's; the foot of the frame is the scale
            // bar's and the speed legend's. A number printed into either would be one more
            // mark in a corner that already has two.
            guard !Self.reserved(in: size).contains(where: { $0.contains(at) }) else { continue }
            context.draw(Text(String(format: "%.0f", rt))
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color(.label).opacity(0.5)),
                         at: at, anchor: .center)
        }
    }

    private static let labelEveryS = 5.0
    private static let labelOffsetP: CGFloat = 13

    /// The two patches of the canvas that already belong to something: the north/wind block
    /// top right, and the strip along the foot that carries the scale bar and the speed
    /// legend.
    private static func reserved(in size: CGSize) -> [CGRect] {
        [CGRect(x: size.width - 74, y: 0, width: 74, height: 34),
         CGRect(x: 0, y: size.height - 28, width: size.width, height: 28)]
    }

    /// +1 when the outside of the curve is to the right of the heading, −1 when it is to the
    /// left. A board turning clockwise has its centre of rotation to the right, so the
    /// outside is to the left, and vice versa.
    private func outwardSign(at point: TurnSlice.Point, in points: [TurnSlice.Point]) -> Double {
        guard let index = points.firstIndex(where: { $0.rt == point.rt }) else { return 1 }
        let ahead = min(index + 2, points.count - 1)
        let behind = max(index - 2, 0)
        guard ahead != behind,
              let from = points[behind].headingDeg,
              let to = points[ahead].headingDeg else { return 1 }
        let swept = TurnSlice.delta(from: from, to: to)
        return swept > 0.5 ? -1 : (swept < -0.5 ? 1 : 1)
    }

    /// **Where the board went through the wind** (engine 0.15.0) — a longer tick across the
    /// line at `axisTs`, with the word `axis` beside it.
    ///
    /// A tick and not a third dot on purpose. The drawing already spends its two dots on the
    /// two things that *happened to the rider* — the hollow ring at the low point, the filled
    /// outcome dot at the end — and a third would read as a third verdict. The crossing is not
    /// a verdict; it is the instant the maneuver is *named* by, which is what a mark across
    /// the track says and a dot on it does not. It is drawn in the same ink as the `wind`
    /// arrow top right rather than in a hue of its own, because it belongs to the wind
    /// reference and not to the speed ramp the line is coloured with.
    ///
    /// Nothing is drawn where the engine recorded no crossing: a course change, a session with
    /// no usable wind, or a stored analysis written before 0.15.0 (`TurnSlice.axisRt`).
    private func drawAxisTick(context: inout GraphicsContext, place: Placer) {
        guard let axisRt = figure.axisRt,
              let point = figure.point(atRelative: axisRt, windUp: windUp),
              let heading = point.headingDeg else { return }
        let radians = (heading + 90) * .pi / 180
        let dx = CGFloat(sin(radians)) * 9
        let dy = -CGFloat(cos(radians)) * 9
        let centre = place(point)
        var tick = Path()
        tick.move(to: CGPoint(x: centre.x - dx, y: centre.y - dy))
        tick.addLine(to: CGPoint(x: centre.x + dx, y: centre.y + dy))
        let ink = Color(.label).opacity(0.55)
        context.stroke(tick, with: .color(ink),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        // Off the outboard end of the tick, so the word never sits on the track it labels.
        context.draw(Text("axis").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ink),
                     at: CGPoint(x: centre.x + dx * 1.7, y: centre.y + dy * 1.7),
                     anchor: .center)
    }

    /// The two moments worth a mark: where the speed bottomed out, and how it ended.
    private func drawMarks(context: inout GraphicsContext, place: Placer) {
        if let lowRt = figure.lowRt,
           let low = figure.point(atRelative: lowRt, windUp: windUp) {
            let centre = place(low)
            let ring = CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10)
            context.stroke(Path(ellipseIn: ring), with: .color(Color(.label).opacity(0.75)),
                           lineWidth: 2)
        }
        if let endRt = figure.endRt,
           let end = figure.point(atRelative: endRt, windUp: windUp) {
            let centre = place(end)
            let dot = CGRect(x: centre.x - 5.5, y: centre.y - 5.5, width: 11, height: 11)
            context.fill(Path(ellipseIn: dot),
                         with: .color(TurnOutcomeStyle.color(TurnOutcomeKind(figure.outcome))))
            context.stroke(Path(ellipseIn: dot), with: .color(Color(.systemBackground)),
                           lineWidth: 1.5)
        }
    }

    /// Where the strip's finger is. The same "you are here, nothing happened here" shape the
    /// session map's playhead uses — a ring rather than a dot, so it cannot be misread as an
    /// outcome.
    private func drawPlayhead(context: inout GraphicsContext, place: Placer) {
        guard let playheadRt,
              let point = figure.point(atRelative: playheadRt, windUp: windUp) else { return }
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
                  rotationDeg: windUp ? -(figure.windDirDeg ?? 0) : 0, label: "N")
        if let windDirDeg = figure.windDirDeg {
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
        let entryKn = figure.entryKn
        guard entryKn >= TurnSpeedRamp.minReferenceKn else { return }
        let drawn = figure.points(windUp: windUp).filter(\.inTurn).map(\.kn)
        let topKn = TurnSpeedRamp.legendTopKn(entryKn: entryKn, maxKn: drawn.max() ?? entryKn)
        let barWidth: CGFloat = 104
        let barHeight: CGFloat = 5
        let right = size.width - Self.inset
        let left = right - barWidth
        // Left of the scale bar's own label, or the two would fight for the same strip.
        guard left > Self.inset + 60 else { return }
        let y = size.height - Self.inset - barHeight

        // The bar runs from the ramp's cold end (half the entry speed) to the top, not from
        // 0 kn: the speeds a jibe is actually ridden at are what the colours are spent on.
        let bottomKn = TurnSpeedRamp.legendBottomKn(entryKn: entryKn)
        let stops = stride(from: 0.0, through: 1.0, by: 0.125).map { fraction in
            Gradient.Stop(color: TurnSpeedRamp.color(kn: bottomKn + (topKn - bottomKn) * fraction,
                                                     entryKn: entryKn),
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
        context.draw(text(String(format: "%.1f", bottomKn)),
                     at: CGPoint(x: left, y: y - 2), anchor: .bottomLeading)
        context.draw(text(String(format: "%.1f kn", topKn)),
                     at: CGPoint(x: right, y: y - 2), anchor: .bottomTrailing)
        // The anchor's own tick, unless it has arrived at the top of the bar — where the two
        // numbers would be the same number printed twice.
        let entryFraction = CGFloat((entryKn - bottomKn) / max(topKn - bottomKn, 0.001))
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

    /// A turn's spoken sentence, composed where the turn is still a turn. It moved out of
    /// `body` when the drawing stopped knowing what it was drawing: the verdict, the radius
    /// and the entry tack are the *slice's* facts, and a figure deliberately carries none of
    /// them.
    static func turnSpoken(_ slice: TurnSlice, windUp: Bool, hasGhost: Bool) -> String {
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
        if let axisRt = slice.axisRt {
            parts.append(String(format: "through the wind axis %.0f seconds in", axisRt))
        }
        if hasGhost { parts.append("compared with your best clean jibe, dashed") }
        return parts.joined(separator: ", ")
    }
}
