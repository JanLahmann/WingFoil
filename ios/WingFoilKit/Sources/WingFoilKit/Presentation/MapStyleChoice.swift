import Foundation

/// What the map is drawn **on** — the ground under the track, not the track.
///
/// **Two grounds**, since 25 Sep 2026. There used to be four — Standard, Muted, Satellite,
/// Hybrid — and a rider could not tell two of the pairs apart on a phone at arm's length:
/// Muted was Standard with its colour turned down, Hybrid was Satellite with a few labels
/// (Jan, F8i). Four names for two grounds is a control that makes him compare, so the menu
/// now offers the two things that actually differ:
///
/// - **Map** — Apple's plain vector map. The default. A rider at his home spot knows the water
///   already and wants the track to be the loudest thing on the screen.
/// - **Satellite** — photography, with Apple's place names and roads over it (MapKit's hybrid).
///   A rider looking at a session somewhere new wants to see the *shore* — the launch, the pier
///   he jibed around, the shallows he stayed off — and the name of the beach beside it.
///
/// **One choice for the whole app**, exactly like `MapLayerVisibility` and for the same
/// reason: "I want to see the water" is a statement about the rider, not about a particular
/// ride. It is persisted (`MapStyleStore`), and a value stored by an older build (`muted`,
/// `hybrid`) comes back as the ground it looked like (`MapStyleChoice.stored(_:)`).
///
/// **Both are flat.** A GPS trace is a plan view of a plane of water; 3-D terrain under it
/// buys nothing and moves the line when the camera tilts.
public enum MapStyleChoice: String, CaseIterable, Codable, Sendable, Identifiable {

    /// Apple's plain vector map. The default, and what every map in the app used to be.
    case standard
    /// Photography with Apple's labels and roads over it — MapKit's *hybrid*. The raw value
    /// stays `satellite` because that is the word a rider says and the word an older build
    /// already stored for the photographic ground.
    case satellite

    public var id: String { rawValue }

    /// Menu text, and the closed chip's text lower-cased.
    public var label: String {
        switch self {
        case .standard: return "Map"
        case .satellite: return "Satellite"
        }
    }

    /// The glyph beside the label in the menu, and the one the closed control wears.
    public var symbolName: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.americas.fill"
        }
    }

    /// What VoiceOver reads after "Map style".
    public var accessibilityNoun: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "satellite"
        }
    }

    /// A stored or staged raw value, including the two retired ones. `muted` was the plain
    /// map with its colour turned down and comes back as `standard`; `hybrid` was photography
    /// with labels, which is exactly what `satellite` now is. Anything else is nil.
    public static func stored(_ raw: String) -> MapStyleChoice? {
        switch raw {
        case "muted": return .standard
        case "hybrid": return .satellite
        default: return MapStyleChoice(rawValue: raw)
        }
    }

    /// Whether the ground under the track is **photography**.
    ///
    /// The one thing the drawing code has to know about the style: a foil-teal line and a
    /// splash-cyan diamond are legible over a flat vector map and are not legible over a
    /// photograph of choppy water in afternoon sun, sunlit sand and white wake within one
    /// session. The shared track path draws with `TrackPalette.imagery` when this is true —
    /// see docs/presentation/layers-map-colour-type.md, "Map style".
    public var isImagery: Bool { recipe.base != .standard }

    /// The inks and casings the track is drawn in on this ground.
    public var palette: TrackPalette { isImagery ? .imagery : .vector }

    /// Exactly what this choice asks MapKit for.
    ///
    /// Spelled as data so the mapping is a table that can be read and asserted, rather than a
    /// `switch` buried in a view that no test on a Mac can reach: `MapStyle` is opaque, not
    /// `Equatable`, and cannot be inspected once built. The view builds its `MapStyle` *from*
    /// this, so the table is the thing that ships.
    public var recipe: MapStyleRecipe {
        switch self {
        case .standard:
            return MapStyleRecipe(base: .standard, excludesPointsOfInterest: true)
        case .satellite:
            return MapStyleRecipe(base: .hybrid, excludesPointsOfInterest: true)
        }
    }
}

/// The arguments one `MapStyleChoice` resolves to. See `MapStyleChoice.recipe`.
public struct MapStyleRecipe: Sendable, Equatable {

    public enum Base: String, Sendable, Equatable, Codable {
        case standard
        case hybrid
    }

    public var base: Base
    /// Whether the style is asked to draw no points of interest.
    ///
    /// A session map is about one track. Restaurants and car parks on it are the map competing
    /// with the thing the map is for — so it is always asked. Place names and roads stay: they
    /// are how a rider recognises the beach.
    public var excludesPointsOfInterest: Bool

    /// Always. A track is a plan view; see the type comment on `MapStyleChoice`.
    public var isFlat: Bool { true }

    /// Whether the track needs its dark casing. True exactly where the ground is photography.
    public var needsTrackHalo: Bool { base != .standard }

    public init(base: Base, excludesPointsOfInterest: Bool) {
        self.base = base
        self.excludesPointsOfInterest = excludesPointsOfInterest
    }
}

/// How the track is inked on one ground — the numbers the drawing path reads, kept here so the
/// contrast of every ink on every ground is a test rather than an opinion.
///
/// **On the vector map nothing changes**: foil-teal on a pale map is the contrast the colour
/// vocabulary was chosen against, and the inks are the system label colours at today's weights.
///
/// **On photography** the ground is anything from deep water to sunlit sand to white wake within
/// one session, so no single ink contrasts with all of it. The answer is the one every map over
/// imagery uses: a **crisp dark casing** under every line, so the line's edge always contrasts,
/// and inks at the **light end** so the line's body reads against the water, which is most of
/// the picture. The hues keep their meaning — flying is still teal, only lifted towards white;
/// the verdict and effort inks do not move at all.
public struct TrackPalette: Sendable, Equatable {

    /// An sRGB ink with its opacity, in 0…1.
    public struct Ink: Sendable, Equatable {
        public var r: Double, g: Double, b: Double, a: Double
        public init(hex: UInt32, alpha: Double = 1) {
            r = Double((hex >> 16) & 0xff) / 255
            g = Double((hex >> 8) & 0xff) / 255
            b = Double(hex & 0xff) / 255
            a = alpha
        }

        /// This ink composited over an opaque ground.
        public func over(_ ground: Ink) -> Ink {
            var out = ground
            out.r = r * a + ground.r * (1 - a)
            out.g = g * a + ground.g * (1 - a)
            out.b = b * a + ground.b * (1 - a)
            out.a = 1
            return out
        }

        /// WCAG relative luminance of the opaque colour.
        public var luminance: Double {
            func lin(_ c: Double) -> Double {
                c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }

        /// WCAG contrast ratio between two opaque colours.
        public static func contrast(_ a: Ink, _ b: Ink) -> Double {
            let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
            return (hi + 0.05) / (lo + 0.05)
        }
    }

    /// The flying track, when the ground is photography. Nil on the vector map, where the
    /// view uses `DesignTokens.Phase.flying` itself.
    public var flying: Ink?
    /// Off-foil and neutral (hidden-layer) track, when the ground is photography. Nil on the
    /// vector map, where they are the secondary label colour at `offFoilOpacity` /
    /// `neutralOpacity`.
    public var offFoil: Ink?
    public var neutral: Ink?
    /// The weights on the vector map (today's, unchanged).
    public var offFoilOpacity: Double
    public var neutralOpacity: Double
    /// The dark edge under every line, or nil for none.
    public var casing: Ink?
    /// Points of casing on *each* side of the line.
    public var casingEdge: Double
    /// Radius of the dark outline around each marker, or 0 for none.
    public var markerOutline: Double

    /// Today's rendering on the plain map, exactly.
    public static let vector = TrackPalette(
        flying: nil, offFoil: nil, neutral: nil,
        offFoilOpacity: 0.65, neutralOpacity: 0.3,
        casing: nil, casingEdge: 0, markerOutline: 0)

    /// Over photography. Flying is phase teal (#40c8e0) lifted a quarter of the way to white,
    /// so it stays teal and gains the brightness deep water takes away; off-foil is white at a
    /// weight clearly below it, so the two phases keep their order; the casing is crisp — a
    /// narrow edge at high opacity rather than a wide soft blur, which read as a dirty smear
    /// along the line on bright chop.
    public static let imagery = TrackPalette(
        flying: Ink(hex: 0x70d6e8), offFoil: Ink(hex: 0xffffff, alpha: 0.7),
        neutral: Ink(hex: 0xffffff, alpha: 0.45),
        offFoilOpacity: 0.65, neutralOpacity: 0.3,
        casing: Ink(hex: 0x000000, alpha: 0.7), casingEdge: 1.5, markerOutline: 1.5)
}

/// The one stored copy of the rider's choice — per user, not per session, and the twin of
/// `MapLayerVisibilityStore` down to the shape.
public enum MapStyleStore {

    public static let defaultsKey = "mapStyle.v1"

    /// Apple's plain map when nothing was ever stored — and also when the stored value names a
    /// style this build does not know, because a preference written by a later version must
    /// degrade to the default rather than to a crash or a blank map.
    public static func load(from defaults: UserDefaults) -> MapStyleChoice {
        guard let raw = defaults.string(forKey: defaultsKey),
              let choice = MapStyleChoice.stored(raw) else { return .standard }
        return choice
    }

    public static func save(_ choice: MapStyleChoice, to defaults: UserDefaults) {
        defaults.set(choice.rawValue, forKey: defaultsKey)
    }
}
