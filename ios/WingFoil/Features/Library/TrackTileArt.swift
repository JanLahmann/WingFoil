import SwiftUI
import UIKit
import WingFoilKit

/// The three inks a row's tile is drawn in, resolved for one appearance, at one scale.
///
/// Resolved on the main actor from the list's own environment (`resolve(in:)`), so the
/// picture is drawn in exactly the colours `TrackOutlineView` and `SpeedSparklineView` would
/// have resolved there; a change of appearance is a new key and a new picture.
struct TileInks: Hashable, Sendable {
    var flying: Color.Resolved
    var offFoil: Color.Resolved
    var tint: Color.Resolved
    var scale: CGFloat

    @MainActor
    init(in environment: EnvironmentValues, scale: CGFloat) {
        flying = DesignTokens.Phase.flying.resolve(in: environment)
        offFoil = DesignTokens.Phase.offFoil.resolve(in: environment)
        tint = Color.accentColor.resolve(in: environment)
        self.scale = scale
    }
}

/// A row's outline and sparkline as two finished bitmaps.
struct TileArt: Sendable {
    var inks: TileInks
    var outline: UIImage?
    var sparkline: UIImage?
}

/// **The library row's tile, drawn once, off the main thread** (Jan, dev 126: "hakelig
/// when scrolling for the first time").
///
/// The row used to draw its outline and its sparkline on two `Canvas` views, and putting a
/// row with those on screen for the first time cost the main thread several times what the
/// rest of the row did — every row, on the first scroll of every launch
/// (`LibraryScrollUITests`). The same strokes, in the same inks, widths, caps and fit, are
/// drawn here into two images when the library is warmed (`ThumbnailStore.warm`), and the
/// row shows the images. The `Canvas` views stay for the share card, and as the row's
/// fallback for the moment before a picture exists.
enum TrackTileArt {
    /// The outline's well and the sparkline's strip, in points — the row's two frames.
    static let outlineSize = ListMapBackdrop.size
    static let sparklineSize = CGSize(width: 62, height: 14)

    /// `TrackOutlineView`'s defaults: a 1.6 pt flying line, off-foil legs at 0.6 of that
    /// in the off-foil ink at 55 %, inscribed in the square the inset leaves.
    static let lineWidth: Double = 1.6
    static let offFoilScale: Double = 0.6

    static func make(_ thumbnail: TrackThumbnail, inks: TileInks) -> TileArt {
        TileArt(inks: inks,
                outline: thumbnail.points.isEmpty ? nil : outline(thumbnail, inks: inks),
                sparkline: thumbnail.speed.count >= 2 ? sparkline(thumbnail.speed, inks: inks)
                                                      : nil)
    }

    private static func renderer(_ size: CGSize, scale: CGFloat) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    static func outline(_ thumbnail: TrackThumbnail, inks: TileInks) -> UIImage {
        let size = outlineSize
        let inset = ListMapBackdrop.inset
        let box = CGRect(x: inset, y: inset,
                         width: max(size.width - inset * 2, 1),
                         height: max(size.height - inset * 2, 1))
        let fit = TrackOutlineView.fit(thumbnail, in: box, fillsBox: false)
        let flying = inks.flying.cgColor
        let offFoil = inks.offFoil.cgColor.copy(alpha: inks.offFoil.cgColor.alpha * 0.55)
            ?? inks.offFoil.cgColor
        return renderer(size, scale: inks.scale).image { context in
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for run in thumbnail.runs {
                cg.beginPath()
                cg.addLines(between: run.points.map {
                    CGPoint(x: fit.originX + $0.x * fit.scale, y: fit.originY + $0.y * fit.scale)
                })
                cg.setStrokeColor(run.flying ? flying : offFoil)
                cg.setLineWidth(run.flying ? lineWidth : lineWidth * offFoilScale)
                cg.strokePath()
            }
        }
    }

    static func sparkline(_ values: [Double], inks: TileInks) -> UIImage {
        let size = sparklineSize
        let tint = inks.tint.cgColor
        let fill = tint.copy(alpha: tint.alpha * 0.18) ?? tint
        return renderer(size, scale: inks.scale).image { context in
            let cg = context.cgContext
            let step = size.width / Double(values.count - 1)
            // As `SpeedSparklineView`: the baseline lifted so a slow session keeps a shape.
            let usable = max(size.height - 2, 1)
            let points = values.indices.map {
                CGPoint(x: Double($0) * step, y: size.height - 1 - values[$0] * usable)
            }
            cg.beginPath()
            cg.addLines(between: points)
            cg.addLine(to: CGPoint(x: size.width, y: size.height))
            cg.addLine(to: CGPoint(x: 0, y: size.height))
            cg.closePath()
            cg.setFillColor(fill)
            cg.fillPath()
            cg.beginPath()
            cg.addLines(between: points)
            cg.setStrokeColor(tint)
            cg.setLineWidth(1.2)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.strokePath()
        }
    }
}
