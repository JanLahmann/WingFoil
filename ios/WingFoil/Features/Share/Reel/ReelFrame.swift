import CoreGraphics
import CoreText
import Foundation
import UIKit
import WingFoilKit

/// One frame of a session video, drawn into a `CGContext` as a pure function of reel time.
///
/// **Pure, and deliberately so.** Frame 317 does not depend on frame 316: it asks the plan
/// where in the session it is, draws the track up to there, and asks the plan what should be
/// on screen. That is what makes the render restartable, cancellable at any frame, and — the
/// reason that actually matters — *checkable*, because a frame can be pulled out of a
/// finished file and compared against what the plan says should have been in it.
///
/// Nothing here is on the main actor and nothing here is UIKit drawing: `CGContext` plus
/// Core Text, straight into the pixel buffer the encoder handed over. `UIFont` appears only
/// as a font descriptor, which is thread-safe, and every colour arrived pre-resolved in
/// `ReelInk`.
enum ReelFrame {

    // MARK: - Geometry, in frame pixels

    private static let margin: CGFloat = 64
    /// Where the live strip's first baseline sits.
    private static let stripTop: CGFloat = 1610
    /// Where a callout is centred — above the strip, in the lower third where a viewer's
    /// eye already is, rather than over the top of the track.
    private static let calloutY: CGFloat = 1430
    private static let progressHeight: CGFloat = 6

    // MARK: - The frame

    static func draw(_ context: CGContext, scene: ReelScene, reelTime r: Double) {
        let size = ReelScene.size
        let plan = scene.plan
        let t = plan.sessionTime(atReelTime: r)

        context.saveGState()
        // Think top-left, like every layout in the app; Core Text is flipped back per line.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(scene.ink.navy)
        context.fill(CGRect(origin: .zero, size: size))
        image(context, scene.ground, in: CGRect(origin: .zero, size: size))
        scrim(context, size: size, ink: scene.ink)

        track(context, scene: scene, upTo: t)
        marks(context, scene: scene, upTo: t)
        head(context, scene: scene, at: t)

        header(context, scene: scene)
        strip(context, scene: scene, at: t)
        progress(context, scene: scene, reelTime: r)

        if let callout = plan.callout(atReelTime: r) {
            self.callout(context, scene: scene, moment: callout.moment,
                         progress: callout.progress)
        }

        // The end card fades over the finished track rather than cutting to it: a hard cut
        // on the last frame of a twenty-second video reads as the video ending twice.
        let fade = min(plan.endCardProgress(atReelTime: r) / 0.15, 1)
        if fade > 0 {
            context.saveGState()
            context.setAlpha(fade)
            image(context, scene.endCard, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        }

        context.restoreGState()
    }

    // MARK: - The ground

    /// A bitmap the right way up.
    ///
    /// The frame is drawn in a **flipped** context so every layout in it can be written
    /// top-left like the rest of the app, and `CGContext.draw(_:in:)` is the one call that
    /// does not want that: it assumes Core Graphics' own bottom-left space and comes out
    /// upside down. Flipping locally, per image, is cheaper than thinking about it — and it
    /// is exactly the bug the first render of this feature shipped with, a whole map of Lake
    /// Garda with mirrored place names under a correctly placed track.
    private static func image(_ context: CGContext, _ bitmap: CGImage, in rect: CGRect) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(bitmap, in: CGRect(x: rect.minX, y: 0, width: rect.width,
                                        height: rect.height))
        context.restoreGState()
    }

    /// Two gradients, top and bottom, so white type has something to sit on whatever the
    /// water under it is doing. Deliberately lighter than the share card's scrim: the card
    /// carries a full stat grid over its map and this carries four short lines.
    private static func scrim(_ context: CGContext, size: CGSize, ink: ReelInk) {
        let space = CGColorSpaceCreateDeviceRGB()
        func band(_ rect: CGRect, from: CGFloat, to: CGFloat, flip: Bool) {
            let colors = [UIColor.black.withAlphaComponent(from).cgColor,
                          UIColor.black.withAlphaComponent(to).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors,
                                            locations: [0, 1]) else { return }
            context.saveGState()
            context.clip(to: rect)
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: flip ? rect.maxY : rect.minY),
                end: CGPoint(x: 0, y: flip ? rect.minY : rect.maxY),
                options: [])
            context.restoreGState()
        }
        band(CGRect(x: 0, y: 0, width: size.width, height: 400), from: 0.62, to: 0, flip: false)
        // Heavier than the top and reaching further, because the strip under it is four
        // lines rather than two and the ground it lands on is a sunlit standard map at its
        // brightest, not the darkened water at the top of the frame.
        band(CGRect(x: 0, y: size.height - 620, width: size.width, height: 620),
             from: 0.86, to: 0, flip: true)
    }

    // MARK: - The track, drawing itself

    /// Every vertex up to `t`, in phase runs, with the partial segment interpolated to the
    /// exact instant — without which the head of the breadcrumb visibly jumps from sample to
    /// sample on a slow passage, which is precisely where the plan has slowed down to be
    /// looked at.
    private static func track(_ context: CGContext, scene: ReelScene, upTo t: Double) {
        let drawn = trail(scene: scene, upTo: t)
        guard drawn.count >= 2 else { return }

        var runs: [(flying: Bool, points: [CGPoint])] = []
        var current: [CGPoint] = [drawn[0].point]
        var flying = drawn[0].flying
        for vertex in drawn.dropFirst() {
            if vertex.flying != flying {
                // Consecutive runs share a vertex, so the polyline has no gap where the
                // phase changes — the rule every other track drawing in the app follows.
                current.append(vertex.point)
                if current.count >= 2 { runs.append((flying, current)) }
                current = [current.last!]
                flying = vertex.flying
            } else {
                current.append(vertex.point)
            }
        }
        if current.count >= 2 { runs.append((flying, current)) }

        context.setLineCap(.round)
        context.setLineJoin(.round)

        // The halo is one pass under the whole track, never per stroke, so no join is
        // overdrawn and a busy corner does not smear (docs/presentation.md, "Map style").
        if scene.needsHalo {
            context.setStrokeColor(scene.ink.halo)
            for run in runs {
                context.setLineWidth(TrackHalo.width(under: width(run.flying)))
                stroke(context, run.points)
            }
        }
        for run in runs {
            context.setStrokeColor(run.flying ? scene.ink.flying : scene.ink.offFoil)
            context.setLineWidth(width(run.flying))
            stroke(context, run.points)
        }
    }

    /// The map's own weights, scaled from points to the reel's pixels.
    private static func width(_ flying: Bool) -> CGFloat {
        TrackContent.width(flying ? .flying : .offFoil) * ReelScene.snapshotScale * 1.6
    }

    private static func stroke(_ context: CGContext, _ points: [CGPoint]) {
        guard points.count >= 2 else { return }
        context.beginPath()
        context.move(to: points[0])
        context.addLines(between: points)
        context.strokePath()
    }

    /// Vertices up to `t`, with a final interpolated point at exactly `t`.
    private static func trail(scene: ReelScene, upTo t: Double) -> [ReelScene.Vertex] {
        let vertices = scene.vertices
        guard let first = vertices.first, t >= first.t else { return [] }
        let last = index(of: t, in: vertices)
        var out = Array(vertices[0...last])
        if last + 1 < vertices.count {
            let a = vertices[last], b = vertices[last + 1]
            let span = b.t - a.t
            if span > 0 {
                let f = min(max((t - a.t) / span, 0), 1)
                out.append(ReelScene.Vertex(
                    t: t,
                    point: CGPoint(x: a.point.x + (b.point.x - a.point.x) * f,
                                   y: a.point.y + (b.point.y - a.point.y) * f),
                    // The phase is the one it is *leaving*: a takeoff belongs to the flight
                    // it starts, and colouring the joining segment green before the sample
                    // that says so would draw the rider onto the foil early.
                    flying: a.flying,
                    kn: a.kn + (b.kn - a.kn) * f))
            }
        }
        return out
    }

    /// The last vertex at or before `t`.
    private static func index(of t: Double, in vertices: [ReelScene.Vertex]) -> Int {
        var low = 0, high = vertices.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if vertices[mid].t <= t { low = mid } else { high = mid }
        }
        return vertices[high].t <= t ? high : low
    }

    /// Where the rider is now: the same dot the map's playhead is, at the size a video
    /// wants.
    private static func head(_ context: CGContext, scene: ReelScene, at t: Double) {
        guard let point = trail(scene: scene, upTo: t).last?.point else { return }
        let box = CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)
        context.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
        context.fillEllipse(in: box.insetBy(dx: -5, dy: -5))
        context.setFillColor(scene.ink.flying)
        context.fillEllipse(in: box)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(6)
        context.strokeEllipse(in: box)
    }

    /// Every mark that has already happened, on the vocabulary every map in the app draws:
    /// the verdict ladder as dots, a clean jibe as a star, a submersion as the cyan diamond.
    private static func marks(_ context: CGContext, scene: ReelScene, upTo t: Double) {
        // Splashes last, so the one mark that is *evidence* rather than a verdict sits on
        // top of the verdict it belongs to instead of under it.
        let due = scene.marks.filter { $0.t <= t }
            .sorted { ($0.kind == .splash ? 1 : 0) < ($1.kind == .splash ? 1 : 0) }
        for mark in due {
            // A mark pops to full size over its first half second on the session clock, so
            // an outcome lands *as it happens* rather than appearing fully formed.
            let age = min(max((t - mark.t) / 0.5, 0), 1)
            let radius = 13 * (1 + 0.7 * (1 - age))
            let path: CGPath
            if mark.clean {
                path = star(at: mark.point, radius: radius * 1.5)
            } else {
                path = TrackOutlineView.markPath(mark.kind, at: mark.point,
                                                 radius: radius).cgPath
            }
            context.addPath(path)
            // The map's own rule: a dark outer edge only over photography, and the white
            // ring `TurnOutcomeStyle.pin` draws everywhere else. A heavy black ring on a
            // sunlit standard map is heavier than anything the app itself draws.
            context.setStrokeColor(scene.needsHalo
                                   ? scene.ink.halo
                                   : UIColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(scene.needsHalo ? radius * 0.7 : radius * 0.36)
            context.strokePath()
            context.addPath(path)
            context.setFillColor(mark.clean ? scene.ink.clean : scene.ink.mark(mark.kind))
            context.fillPath()
        }
    }

    /// A five-pointed star, because the clean jibe's glyph is one everywhere else in the app
    /// (`DesignTokens.Glyph.cleanJibe`) and an SF Symbol cannot be rasterised off the main
    /// actor without dragging UIKit's image machinery into the render loop.
    private static func star(at centre: CGPoint, radius: Double) -> CGPath {
        let path = CGMutablePath()
        for step in 0..<10 {
            let r = step.isMultiple(of: 2) ? radius : radius * 0.42
            let angle = -Double.pi / 2 + Double(step) * .pi / 5
            let point = CGPoint(x: centre.x + cos(angle) * r, y: centre.y + sin(angle) * r)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - The words

    private static func header(_ context: CGContext, scene: ReelScene) {
        text(context, scene.title, size: 46, weight: .bold, rounded: true,
             color: scene.ink.paper, at: CGPoint(x: margin, y: 84))
        text(context, scene.dateLine, size: 26, weight: .medium, rounded: false,
             color: scene.ink.paper.copy(alpha: 0.72) ?? scene.ink.paper,
             at: CGPoint(x: margin, y: 142))
    }

    /// The live strip: elapsed, speed, on-foil, and the two counters that only ever go up.
    private static func strip(_ context: CGContext, scene: ReelScene, at t: Double) {
        let ink = scene.ink
        let quiet = ink.paper.copy(alpha: 0.66) ?? ink.paper
        let elapsed = t - scene.plan.span.lowerBound
        let moment = scene.vertices.isEmpty ? nil : scene.vertices[index(of: t, in: scene.vertices)]
        let flying = moment?.flying ?? false

        text(context, "elapsed", size: 24, weight: .semibold, rounded: false,
             color: quiet, at: CGPoint(x: margin, y: stripTop))
        text(context, FlightPairing.clock(elapsed), size: 58, weight: .bold, rounded: true,
             color: ink.paper, at: CGPoint(x: margin, y: stripTop + 32))

        let right = ReelScene.size.width - margin
        text(context, "speed", size: 24, weight: .semibold, rounded: false,
             color: quiet, at: CGPoint(x: right, y: stripTop), align: .right)
        text(context, String(format: "%.1f kn", moment?.kn ?? 0), size: 58, weight: .bold,
             rounded: true, color: flying ? ink.flying : ink.paper,
             at: CGPoint(x: right, y: stripTop + 32), align: .right)

        // The on-foil flag, which is the one thing on the strip that is a *state* rather
        // than a number: a filled foil-teal pill while he is flying, an empty outline while
        // he is not. Same ink as the track under it, so the two say one thing.
        let pill = CGRect(x: ReelScene.size.width / 2 - 118, y: stripTop + 22, width: 236,
                          height: 66)
        let rounded = CGPath(roundedRect: pill, cornerWidth: 33, cornerHeight: 33,
                             transform: nil)
        context.addPath(rounded)
        if flying {
            context.setFillColor(ink.flying.copy(alpha: 0.9) ?? ink.flying)
            context.fillPath()
        } else {
            context.setStrokeColor(quiet)
            context.setLineWidth(3)
            context.strokePath()
        }
        text(context, flying ? "on foil" : "off foil", size: 32, weight: .bold, rounded: true,
             color: flying ? ink.navy : quiet,
             at: CGPoint(x: pill.midX, y: pill.midY - 20), align: .center)

        // The counters. "flew" and "dry" are the two the key-metrics block's streak pair
        // names, and "clean" wears the star it wears everywhere else.
        let tally = scene.plan.tally(throughSessionTime: t)
        var line = "\(tally.flew) flew · \(tally.dry) dry"
        if tally.clean > 0 { line += " · \(tally.clean) ★ clean" }
        text(context, line, size: 34, weight: .semibold, rounded: true, color: quiet,
             at: CGPoint(x: ReelScene.size.width / 2, y: stripTop + 122), align: .center)

        if let disclaimer = scene.disclaimer {
            text(context, disclaimer, size: 22, weight: .medium, rounded: false,
                 color: ink.uncertified, at: CGPoint(x: ReelScene.size.width / 2,
                                                     y: stripTop + 172), align: .center)
        }
    }

    /// How far through the cut, as a hairline across the very bottom — the one piece of
    /// chrome a viewer reads without looking at it.
    private static func progress(_ context: CGContext, scene: ReelScene, reelTime r: Double) {
        let size = ReelScene.size
        let y = size.height - progressHeight
        context.setFillColor(scene.ink.paper.copy(alpha: 0.22) ?? scene.ink.paper)
        context.fill(CGRect(x: 0, y: y, width: size.width, height: progressHeight))
        let done = min(max(r / scene.plan.totalS, 0), 1)
        context.setFillColor(scene.ink.flying)
        context.fill(CGRect(x: 0, y: y, width: size.width * done, height: progressHeight))
    }

    /// The callout: a dark plate with the moment's own ink down its leading edge, popping
    /// out of nothing and fading back into it.
    ///
    /// The shape is `ReplayCommentaryBubble`'s — a coloured rule, then the words — because a
    /// rider who has watched the cinema replay has already learned to read it.
    private static func callout(_ context: CGContext, scene: ReelScene, moment: ReelMoment,
                                progress: Double) {
        // In over the first eighth, out over the last quarter.
        let alpha = min(progress / 0.125, 1) * min((1 - progress) / 0.25, 1)
        guard alpha > 0.01 else { return }
        let scale = 0.86 + 0.14 * min(progress / 0.125, 1)

        let ink = colour(of: moment.kind, scene: scene)
        let font = self.font(46, weight: .bold, rounded: true)
        let width = measure(moment.headline, font: font)
        let box = CGRect(x: (ReelScene.size.width - (width + 148)) / 2,
                         y: calloutY - 48, width: width + 148, height: 96)

        context.saveGState()
        context.setAlpha(alpha)
        context.translateBy(x: box.midX, y: box.midY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.midX, y: -box.midY)

        context.addPath(CGPath(roundedRect: box, cornerWidth: 26, cornerHeight: 26,
                               transform: nil))
        context.setFillColor(UIColor.black.withAlphaComponent(0.62).cgColor)
        context.fillPath()

        let rule = CGRect(x: box.minX + 28, y: box.minY + 22, width: 10, height: 52)
        context.addPath(CGPath(roundedRect: rule, cornerWidth: 5, cornerHeight: 5,
                               transform: nil))
        context.setFillColor(ink)
        context.fillPath()

        text(context, moment.headline, size: 46, weight: .bold, rounded: true,
             color: scene.ink.paper, at: CGPoint(x: box.minX + 66, y: box.minY + 22))
        context.restoreGState()
    }

    /// The moment's own ink — the outcome ladder for a jibe, the star's mint for a clean
    /// one, the effort orange for a record, splash-cyan for a wrist-under, foil-teal for a
    /// takeoff. Every one of them a token, none of them chosen here.
    private static func colour(of kind: ReelMoment.Kind, scene: ReelScene) -> CGColor {
        switch kind {
        case .takeoff: scene.ink.flying
        case .jibe(_, clean: true): scene.ink.clean
        case .jibe(.flewThrough, _): scene.ink.flew
        case .jibe(.touchdown, _): scene.ink.touchdown
        case .jibe(.fellIn, _): scene.ink.fellIn
        case .record: scene.ink.record
        case .submersion: scene.ink.splash
        }
    }

    // MARK: - Core Text

    private enum Align { case left, center, right }

    private static func font(_ size: CGFloat, weight: UIFont.Weight,
                             rounded: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func line(_ string: String, font: UIFont,
                             color: CGColor = UIColor.white.cgColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes))
    }

    private static func measure(_ string: String, font: UIFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(string, font: font), nil, nil, nil))
    }

    /// `at` is the top-left of the line's ascent box in the flipped (top-left origin) space
    /// the frame is drawn in; Core Text's own matrix is flipped back per line so the glyphs
    /// come out the right way up.
    @discardableResult
    private static func text(_ context: CGContext, _ string: String, size: CGFloat,
                             weight: UIFont.Weight, rounded: Bool, color: CGColor,
                             at point: CGPoint, align: Align = .left) -> CGFloat {
        let font = self.font(size, weight: weight, rounded: rounded)
        let ctLine = line(string, font: font, color: color)
        var ascent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, nil, nil))
        let x = switch align {
        case .left: point.x
        case .center: point.x - width / 2
        case .right: point.x - width
        }
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: point.y + ascent)
        CTLineDraw(ctLine, context)
        context.restoreGState()
        return width
    }
}
