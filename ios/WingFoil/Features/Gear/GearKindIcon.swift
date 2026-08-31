import SwiftUI
import WingFoilKit

/// The icon beside a gear kind's name.
///
/// Wing and board have SF Symbols that mean what they show (`wind`, `surfboard`). A
/// hydrofoil does not, and the app drew `airplane` for it until `app-ui-review.md` §6.3:
/// "no unclear icons" is an explicit owner preference, and a hydrofoil rendered as a
/// passenger jet is the definition of unclear — it is also the one glyph in the app that
/// says something actively false about the object it labels.
///
/// So the foil gets a drawn silhouette instead: a front wing seen from above, swept and
/// tapered, on a fuselage. It is the outline of the thing in the bag, and at 16 pt it is
/// distinguishable from the board's outline at a glance, which is all a list header icon
/// has to do. Drawn rather than shipped as an asset so it inherits the label's font size
/// and its foreground style like the two symbols beside it.
struct GearKindIcon: View {
    let kind: GearKind
    /// Matched to the surrounding text, the way `Label`'s own symbols are.
    var size: CGFloat = 15

    var body: some View {
        if let symbol = kind.symbol {
            Image(systemName: symbol)
        } else {
            FrontWingShape()
                .fill(.foreground)
                .frame(width: size * 1.35, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// A hydrofoil front wing from above: a swept leading edge, a straighter trailing edge
/// meeting it at the tips, and a short fuselage running aft from the centre.
///
/// Drawn in a unit box and scaled, so one set of coefficients serves every call site. The
/// sweep is the whole point of the shape — a symmetric lens would read as a leaf, and the
/// aft fuselage is what stops it reading as a bird.
private struct FrontWingShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let x = { (u: CGFloat) in rect.minX + u * w }
        let y = { (v: CGFloat) in rect.minY + v * h }

        var path = Path()
        // The wing: tip → swept-back leading edge → centre → out to the other tip, then
        // the trailing edge home. Quadratic curves on both edges, with the leading edge
        // pulled forward at the centre so the planform is a crescent rather than a delta.
        path.move(to: CGPoint(x: x(0.02), y: y(0.62)))
        path.addQuadCurve(to: CGPoint(x: x(0.98), y: y(0.62)),
                          control: CGPoint(x: x(0.50), y: y(0.04)))
        path.addQuadCurve(to: CGPoint(x: x(0.02), y: y(0.62)),
                          control: CGPoint(x: x(0.50), y: y(0.50)))
        path.closeSubpath()

        // The fuselage: a short spine aft of the wing's centre, which is what the mast
        // bolts to and what makes the silhouette a foil rather than a wing shape.
        path.addRoundedRect(in: CGRect(x: x(0.455), y: y(0.36),
                                       width: w * 0.09, height: h * 0.62),
                            cornerSize: CGSize(width: w * 0.045, height: w * 0.045))
        return path
    }
}
