import Foundation

/// **The two text inks a rider must be able to read at arm's length on a beach.**
///
/// Jan, 25 September 2026: the row legend under the numbers (*foil · clean · best 2 s*),
/// the links to a help topic and the captions under the session tiles were washed out.
/// They were drawn in the system's tertiary label (about 2.3 : 1 on a light list) or, for
/// the links, in the accent mint, which is 1.6 : 1 on white. Neither meets WCAG AA, and
/// both carry something the rider needs: what a number is, and where the answer is.
///
/// So one secondary ink and one link ink, each a light/dark pair, each at least 4.5 : 1 on
/// every ground the app puts text on (`grounds`). The system's own tertiary and quaternary
/// stay for what they are good at — a chevron, a separator dot, a disabled figure —
/// never for a word. The web twin is `--ink-3` and `--link-ink` in web/css/style.css.
///
/// Values only, no SwiftUI: the app turns them into a dynamic colour (`Color.readable…`),
/// and `ReadableInkTests` holds every pair against every ground.
public enum ReadableInk {

    /// One ink, as the two sRGB values it has in light and dark appearance.
    public struct Pair: Sendable, Equatable {
        public let light: UInt32
        public let dark: UInt32
        public init(light: UInt32, dark: UInt32) {
            self.light = light
            self.dark = dark
        }
    }

    /// Secondary text that carries information: a legend under a number, a tile caption, a
    /// footnote. Darker than the system secondary label in light, brighter in dark.
    public static let secondary = Pair(light: 0x636366, dark: 0xAEAEB2)

    /// The link to a help topic: the brand mint where it reads (dark), a deep green of the
    /// same family where it would not (light).
    public static let link = Pair(light: 0x00704E, dark: 0x2EE6A8)

    /// The grounds text sits on: grouped background, cell, raised cell and the fill a tile
    /// is drawn on — in a screen and in a sheet (dark sheets are one step lighter).
    public static let lightGrounds: [UInt32] = [0xFFFFFF, 0xF2F2F7, 0xE5E5EA]
    public static let darkGrounds: [UInt32] = [0x000000, 0x1C1C1E, 0x2C2C2E, 0x3A3A3C]

    /// The AA floor for body and caption text.
    public static let minimumContrast = 4.5

    /// WCAG 2.x contrast ratio of two opaque sRGB colours, 1 … 21.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Relative luminance (WCAG 2.x) of an sRGB colour written 0xRRGGBB.
    public static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// The components, 0 … 1, for building a platform colour.
    public static func components(_ rgb: UInt32) -> (red: Double, green: Double, blue: Double) {
        (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255,
         Double(rgb & 0xFF) / 255)
    }
}
