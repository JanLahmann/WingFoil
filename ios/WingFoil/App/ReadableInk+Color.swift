import SwiftUI
import UIKit
import WingFoilKit

/// The kit's two readable inks as dynamic colours (`ReadableInk`). Use `.readableSecondary`
/// for a word a rider needs — a legend, a caption, a footnote — and `.helpLink` for the way
/// to a help topic. The system tertiary and quaternary stay for chevrons, separators and
/// disabled figures only.
extension ShapeStyle where Self == Color {
    static var readableSecondary: Color { ReadableInkColor.secondary }
    static var helpLink: Color { ReadableInkColor.link }
}

private enum ReadableInkColor {
    static let secondary = Color(uiColor: .readable(ReadableInk.secondary))
    static let link = Color(uiColor: .readable(ReadableInk.link))
}

private extension UIColor {
    static func readable(_ pair: ReadableInk.Pair) -> UIColor {
        UIColor { traits in
            let c = ReadableInk.components(traits.userInterfaceStyle == .dark ? pair.dark
                                                                             : pair.light)
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        }
    }
}
