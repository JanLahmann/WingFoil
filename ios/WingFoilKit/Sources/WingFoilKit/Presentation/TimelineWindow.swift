import Foundation

/// The stretch of session clock a time chart is currently showing.
///
/// On an 80-minute ride the speed chart draws a couple of hundred event marks across 350
/// points of screen, and they pile onto each other until the picture is texture rather than
/// information. Zooming is the declutter: fewer seconds per point means fewer marks in the
/// frame, and the ones that remain are far enough apart to read. So the visible domain is a
/// *model* value rather than a scroll offset — the chart, its marks, its shading and the
/// little range bar under it all have to agree on exactly which seconds are on screen.
///
/// Transient by design. Nothing here is persisted: zoom is a way of looking at the session
/// you have open, not a preference about sessions in general.
public struct TimelineWindow: Sendable, Equatable {

    /// The whole session — the window can never show anything outside this.
    public let full: ClosedRange<Double>
    public private(set) var visible: ClosedRange<Double>

    /// The tightest window we ever hand out, in seconds. A jibe takes 3–5 s, so ~20 s is
    /// "one maneuver and its approach", which is the smallest thing worth looking at.
    public static let minSpanS: Double = 20
    /// …and the deepest zoom, so a long session cannot be magnified into a domain so narrow
    /// that the bucketed speed series has nothing left to draw.
    public static let maxFactor: Double = 60

    public init(full: ClosedRange<Double>) {
        self.full = full
        self.visible = full
    }

    /// Smallest window this session allows: a short recording must still be zoomable, and a
    /// long one must not be zoomable past the resolution of its own speed series.
    public var minSpan: Double {
        min(fullSpan, max(Self.minSpanS, fullSpan / Self.maxFactor))
    }

    public var fullSpan: Double { full.upperBound - full.lowerBound }
    public var span: Double { visible.upperBound - visible.lowerBound }

    /// How much of the session one screen width now holds, as a multiplier. 1 = everything.
    public var factor: Double { span > 0 ? fullSpan / span : 1 }

    /// A hair of slack, so floating-point dust after a pinch-and-back does not leave the
    /// reset chip on screen with nothing to reset.
    public var isZoomed: Bool { span < fullSpan - 0.5 }

    /// Where the window sits in the session, 0…1 — the range bar under the chart.
    public var startFraction: Double {
        fullSpan > 0 ? (visible.lowerBound - full.lowerBound) / fullSpan : 0
    }

    public var endFraction: Double {
        fullSpan > 0 ? (visible.upperBound - full.lowerBound) / fullSpan : 1
    }

    public func contains(_ t: Double) -> Bool {
        t >= visible.lowerBound && t <= visible.upperBound
    }

    public func clamp(_ t: Double) -> Double {
        min(max(t, visible.lowerBound), visible.upperBound)
    }

    /// The part of a span (a flight, a pump run, a record window) that is on screen, or nil
    /// when none of it is. Shading is clipped rather than dropped: a flight that started
    /// before the window must still tint the water it covers inside it.
    public func clipped(start: Double, end: Double) -> ClosedRange<Double>? {
        let lo = max(start, visible.lowerBound)
        let hi = min(end, visible.upperBound)
        return lo <= hi ? lo...hi : nil
    }

    // MARK: - Moving the window

    /// Pinch. `scale` > 1 zooms in; `anchor` is the session time under the pinch centre and
    /// stays put on screen, which is what makes a pinch feel like it grabs the chart rather
    /// than a slider somewhere else.
    public mutating func magnify(by scale: Double, around anchor: Double) {
        guard scale > 0, span > 0, fullSpan > 0 else { return }
        let fraction = min(max((anchor - visible.lowerBound) / span, 0), 1)
        let newSpan = min(max(span / scale, minSpan), fullSpan)
        set(lower: anchor - fraction * newSpan, span: newSpan)
    }

    /// Zoom to an absolute factor around a time — the entry point for a fresh zoom (and for
    /// the screenshot hook), where there is no gesture history to multiply into.
    public mutating func zoom(to factor: Double, centeredOn center: Double) {
        guard fullSpan > 0 else { return }
        let newSpan = min(max(fullSpan / max(factor, 0.0001), minSpan), fullSpan)
        set(lower: center - newSpan / 2, span: newSpan)
    }

    public mutating func pan(bySeconds delta: Double) {
        set(lower: visible.lowerBound + delta, span: span)
    }

    /// Nudge just far enough to bring `t` back into view, keeping a margin so the playhead
    /// does not sit welded to the edge. Used when the replay walks out of the window.
    public mutating func reveal(_ t: Double) {
        guard !contains(t) || nearEdge(t) else { return }
        let margin = span * 0.15
        if t < visible.lowerBound + margin {
            set(lower: t - margin, span: span)
        } else if t > visible.upperBound - margin {
            set(lower: t + margin - span, span: span)
        }
    }

    public mutating func reset() { visible = full }

    private func nearEdge(_ t: Double) -> Bool {
        let margin = span * 0.15
        return t < visible.lowerBound + margin || t > visible.upperBound - margin
    }

    /// The one place the window is written: everything else states an intent and lets this
    /// keep it inside the session. Clamping the *start* after clamping the span is what
    /// stops a pinch near either end from sliding the window off the recording.
    private mutating func set(lower: Double, span: Double) {
        let width = min(max(span, minSpan), fullSpan)
        let start = min(max(lower, full.lowerBound), full.upperBound - width)
        visible = start...(start + width)
    }
}
