import SwiftUI
import WingFoilKit

/// One palette for the outcome markers so the map, the chart and the legend can never
/// drift apart. Colour carries the verdict (docs/algorithms.md "Turn outcome" /
/// "Flight-end outcome"), fill carries the *channel*: solid = a maneuver's outcome,
/// hollow = a straight-line flight end that no turn explains.
///
/// The *values* are not written here any more: they come from `DesignTokens`, generated
/// from `design/tokens.json`, so the same edit reaches the web app's CSS in the same
/// commit (docs/presentation.md "Enforcement"). This file still owns the *meanings* —
/// which tone belongs to which verdict, and which glyph to which takeoff kind.
enum EventMarkerStyle {

    static func color(_ tone: SessionDetail.EventMarker.Tone) -> Color {
        switch tone {
        case .flew: return DesignTokens.Outcome.flew
        case .touchdown: return DesignTokens.Outcome.touchdown
        case .fell: return DesignTokens.Outcome.fellIn
        case .course: return DesignTokens.Outcome.courseChange
        }
    }

    /// The three layers that are about *effort and water* rather than about an outcome.
    /// They are deliberately outside the green/amber/red ladder: nothing here is a verdict,
    /// so borrowing the verdict palette would make a takeoff look like a good jibe.
    static let pumping = DesignTokens.Effort.pumping
    static let takeoff = DesignTokens.Effort.takeoff
    static let splash = DesignTokens.Effort.splash
    /// The one exception, and it earns it: a *failed* attempt is the single event in these
    /// three layers that has an outcome, so it borrows the ladder's red. Shape and fill
    /// carry the distinction on their own (see `takeoffMark`), so nothing here depends on
    /// telling red from blue.
    static let failedTakeoff = DesignTokens.Effort.failedTakeoff

    /// The **clean jibe**'s own ink — a green that is deliberately not the ladder's.
    ///
    /// "Flew through" is how the turn ended; clean is what it cost, and the two disagree on
    /// purpose (docs/presentation.md, "Clean jibe"). A star drawn in `Outcome.flew` would
    /// quietly claim they are the same reading of the same jibe.
    static let cleanJibe = DesignTokens.Clean.jibe

    /// The dot itself, at a size that stays legible on a zoomed-out track — or a **star**,
    /// when the jibe was clean.
    ///
    /// The star *replaces* the dot rather than sitting beside it: two marks on one turn at
    /// map scale is two events to the eye. Shape carries it, so nothing here depends on
    /// telling one green from another; the outcome is still one tap away in the callout,
    /// and still governs whether the mark is drawn at all.
    @ViewBuilder
    static func dot(_ marker: SessionDetail.EventMarker, size: CGFloat = 11) -> some View {
        if marker.isCleanJibe {
            Image(systemName: DesignTokens.Glyph.cleanJibe)
                .font(.system(size: size + 2, weight: .semibold))
                .foregroundStyle(cleanJibe)
                .shadow(radius: 1)
        } else {
            let tint = color(marker.tone)
            Circle()
                .fill(marker.filled ? tint : Color.clear)
                .stroke(marker.filled ? Color.white.opacity(0.9) : tint, lineWidth: 2)
                .frame(width: size, height: size)
                .shadow(radius: 1)
        }
    }

    /// Takeoffs and splashes are glyphs, not dots, so they can never be mistaken for an
    /// outcome at a glance on a busy track. A `free` takeoff — up on wind alone — gets the
    /// hollow arrow: the pumped one is the filled, "this cost something" variant.
    ///
    /// A **failed** attempt turns the arrow around. It is the only mark in this layer that
    /// did not end in a flight, so it must not merely be a differently-tinted up-arrow: the
    /// u-turn glyph says "went at it and came back down" at any zoom, hollow says nothing
    /// came of it, and red says it on a third channel for anyone who cannot use the first
    /// two. The takeoff arrows stay blue and unchanged around it.
    static func takeoffSymbol(_ kind: SessionDetail.TakeoffMark.Kind) -> String {
        switch kind {
        case .pumped: return DesignTokens.Glyph.takeoffPumped
        case .free: return DesignTokens.Glyph.takeoffFree
        case .failed: return DesignTokens.Glyph.takeoffFailed
        }
    }

    @ViewBuilder
    static func takeoffMark(_ mark: SessionDetail.TakeoffMark,
                            size: CGFloat = 11) -> some View {
        let hollow = mark.kind != .pumped
        Image(systemName: takeoffSymbol(mark.kind))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(mark.isFailed ? failedTakeoff : takeoff)
            .background(Circle().fill(.white.opacity(hollow ? 0.85 : 0)).padding(1))
            .shadow(radius: 1)
    }

    @ViewBuilder
    static func splashMark(size: CGFloat = 12) -> some View {
        Image(systemName: DesignTokens.Glyph.splash)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(splash)
            .shadow(radius: 1)
    }
}

extension SessionDetail.EventMarker {

    /// The legend chip this marker answers to. Both channels of an outcome share one
    /// chip — the rider hides "touchdowns", not "solid touchdowns" — so the hollow
    /// straight-line variant disappears with its solid maneuver twin.
    var layer: MapLayer {
        switch tone {
        case .flew: return .flewThrough
        case .touchdown: return .touchdown
        case .fell: return .fellIn
        case .course: return .courseChange
        }
    }

    /// Every chip that has to be on for this mark to be drawn — exactly one.
    ///
    /// A clean jibe answers to the `cleanJibe` chip alone (Jan, 5 Sep 2026: the star's chip
    /// and the flew-through chip are independent). It used to answer to both, when "clean"
    /// could still sit on a touchdown; now a clean jibe is by definition one that flew
    /// through, so the star is simply its own category of mark: hide "flew through" and the
    /// plain flew-through dots go while the stars stay, hide "clean jibe" and the stars go
    /// while the dots stay. Nothing is ever drawn twice, and nothing answers to two chips.
    var layers: [MapLayer] { isCleanJibe ? [.cleanJibe] : [layer] }
}
