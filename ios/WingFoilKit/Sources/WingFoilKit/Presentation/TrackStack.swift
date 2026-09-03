import Foundation

/// Where a **set** of track outlines lands when they are drawn on one another — one scale,
/// one centre, fitted to the union of what they cover.
///
/// This is the period card's artwork rule, and it is the reason the type exists at all. A
/// single outline is placed against itself (`TrackOutlineView.fit`), which is right: a list
/// row wants every session to read as the same consistent shape. A dozen outlines laid on one
/// another want the opposite — if each is normalized against its own extent, a half-hour
/// paddle is drawn exactly as large as a three-hour reach and the picture says nothing about
/// either. Fitted to the union in **metres**, a short session draws small inside a long one,
/// which is the true shape of the week.
///
/// **This is the twin of `fittedPlacer` / `drawTrackStack` in web/js/sharecard.js**, line for
/// line, including the two edge cases: an axis with no extent imposes no limit (a perfectly
/// straight leg is fitted by the other axis alone), and a set with no extent at all is placed
/// at 1 point per metre rather than dividing by zero. The two are pinned against one shared
/// fixture — `fixtures/periods/outlines.expected.json` — read by `TrackStackTests` here and
/// re-derived by `web/tools/verify_presentation.py` §5e, so a card composed on the phone and
/// a card composed in the browser place the same outlines in the same places.
public enum TrackStack {

    /// A rectangle in layout points, in the card's own coordinates.
    public struct Box: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double

        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
        }
    }

    /// One track's extent, in metres. `y` is metres **north**, as the engine's own local
    /// frame has it and as `TrackThumbnail.Bounds` carries it.
    public struct Extent: Sendable, Equatable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }
    }

    /// One metres → layout-points projection, shared by every outline in the stack.
    public struct Placement: Sendable, Equatable {
        /// Layout points per metre. The number the whole type is about: it is the same for
        /// every track in the stack, which is what "one scale" means.
        public var scale: Double
        /// The centre of the union extent, in metres.
        public var centreX: Double
        public var centreY: Double
        /// The centre of the box, in layout points.
        public var boxCentreX: Double
        public var boxCentreY: Double

        public init(scale: Double, centreX: Double, centreY: Double,
                    boxCentreX: Double, boxCentreY: Double) {
            self.scale = scale
            self.centreX = centreX
            self.centreY = centreY
            self.boxCentreX = boxCentreX
            self.boxCentreY = boxCentreY
        }

        /// Where one metre coordinate lands. The vertical axis is flipped, because `y` is
        /// metres north and screen `y` grows downward — north up, the same way the map draws.
        public func place(x: Double, y: Double) -> (x: Double, y: Double) {
            (x: boxCentreX + (x - centreX) * scale, y: boxCentreY - (y - centreY) * scale)
        }
    }

    /// The smallest extent covering all of them. nil for an empty set.
    public static func union(_ extents: [Extent]) -> Extent? {
        guard let first = extents.first else { return nil }
        var out = first
        for extent in extents.dropFirst() {
            out.minX = min(out.minX, extent.minX)
            out.minY = min(out.minY, extent.minY)
            out.maxX = max(out.maxX, extent.maxX)
            out.maxY = max(out.maxY, extent.maxY)
        }
        return out
    }

    /// An axis narrower than this is treated as having no extent, so it imposes no limit on
    /// the fit — the twin of the `0.01` in `fittedPlacer`. A centimetre of drift is not a
    /// reach, and dividing a box by it would put one vertex on the moon.
    public static let flatAxisM = 0.01

    /// What a stack with no extent at all is given: one point per metre, rather than a
    /// division by zero. It never reaches a card — a set of tracks that covers nothing has
    /// nothing to draw — but the rule has to have an answer, and both platforms give this one.
    public static let degenerateScale = 1.0

    /// Fit a set of extents into `box`, reserving `inset` on every side.
    ///
    /// `inset` is the margin the card's track box already reserves for a stroke — and, on the
    /// session card, for a mark centred on the outermost vertex. The stack draws no marks, and
    /// it still reserves the same margin, because a mapped stack and a plain one must come out
    /// the same size (`ShareCardMapper.inset`, `TRACK_INSET` in web/js/sharecard.js).
    public static func placement(of extents: [Extent], in box: Box,
                                 inset: Double) -> Placement? {
        guard let ext = union(extents) else { return nil }
        let w = max(box.w - inset * 2, 1), h = max(box.h - inset * 2, 1)
        let dx = ext.maxX - ext.minX, dy = ext.maxY - ext.minY
        // A perfectly straight leg has zero extent on one axis; that axis then imposes no
        // limit, which is exactly right — `min` takes the other one.
        let s = min(dx > flatAxisM ? w / dx : .infinity, dy > flatAxisM ? h / dy : .infinity)
        return Placement(scale: s.isFinite ? s : degenerateScale,
                         centreX: (ext.minX + ext.maxX) / 2,
                         centreY: (ext.minY + ext.maxY) / 2,
                         boxCentreX: box.x + box.w / 2,
                         boxCentreY: box.y + box.h / 2)
    }

    /// How faint each outline is drawn, so a dozen read as one shape rather than a scribble.
    /// The overlap is what draws the eye: the water everything was ridden over comes out
    /// brightest. The twin of the same expression in `drawTrackStack`.
    public static func opacity(count: Int) -> Double {
        max(0.22, min(0.6, 2.4 / Double(max(1, count))))
    }
}
