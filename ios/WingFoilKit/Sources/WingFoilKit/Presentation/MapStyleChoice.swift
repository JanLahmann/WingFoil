import Foundation

/// What the map is drawn **on** — the ground under the track, not the track.
///
/// Every map in the app opened on Apple's plain vector style, flat, with the points of
/// interest switched off, and there was no way to ask for anything else. That is the right
/// default and the wrong only answer: a rider looking at a session at his home spot knows the
/// water already and wants the track to be the loudest thing on the screen (Standard, or
/// Muted, which is the same map with its own colour turned down); a rider looking at a session
/// somewhere new wants to see the *shore* — the launch, the pier he jibed around, the shallows
/// he stayed off — and only photography shows him that (Satellite, or Hybrid, which is the
/// photography with Apple's labels over it).
///
/// **One choice for the whole app**, exactly like `MapLayerVisibility` and for the same
/// reason: "I want to see the water" is a statement about the rider, not about a particular
/// ride. It is persisted (`MapStyleStore`), so a relaunch comes back the way the map was left,
/// and it reaches all four map surfaces — the session's inline map, the full-screen map, the
/// Turns tab's map and the cinema replay a clip is recorded from — because a rider who
/// switched to satellite and then found one of them still grey would have to conclude the
/// setting is per-screen, which it is not.
///
/// **All four are flat.** A GPS trace is a plan view of a plane of water; 3-D terrain under it
/// buys nothing and moves the line when the camera tilts.
public enum MapStyleChoice: String, CaseIterable, Codable, Sendable, Identifiable {

    /// Apple's plain vector map. The default, and what every map in the app used to be.
    case standard
    /// The same map with its own colour turned down (`StandardEmphasis.muted`), so the phase
    /// tints are the only saturated thing on the screen.
    case muted
    /// Photography, no labels.
    case satellite
    /// Photography with Apple's labels and roads over it.
    case hybrid

    public var id: String { rawValue }

    /// Menu text. Lower-case would match the legend chips, but these are the names Apple's
    /// own Maps uses for the same four things, and a rider recognises them.
    public var label: String {
        switch self {
        case .standard: return "Standard"
        case .muted: return "Muted"
        case .satellite: return "Satellite"
        case .hybrid: return "Hybrid"
        }
    }

    /// The glyph beside the label in the menu, and the one the closed control wears.
    public var symbolName: String {
        switch self {
        case .standard: return "map"
        case .muted: return "map.fill"
        case .satellite: return "globe.americas.fill"
        case .hybrid: return "globe.americas"
        }
    }

    /// What VoiceOver reads after "Map style".
    public var accessibilityNoun: String {
        switch self {
        case .standard: return "standard map"
        case .muted: return "muted map"
        case .satellite: return "satellite imagery"
        case .hybrid: return "satellite imagery with labels"
        }
    }

    /// Whether the ground under the track is **photography**.
    ///
    /// The one thing the drawing code has to know about the style, and the reason this type
    /// is in the kit rather than being four `MapStyle` values in a view: a foil-teal line and
    /// a splash-cyan diamond are legible over a flat vector map and are not legible over a
    /// photograph of choppy water in afternoon sun. The shared track path gives every stroke
    /// and every mark a dark outer halo when this is true — see the map surfaces and
    /// docs/presentation.md, "Map style".
    public var isImagery: Bool { recipe.base != .standard }

    /// Exactly what this choice asks MapKit for.
    ///
    /// Spelled as data so the mapping is a table that can be read and asserted, rather than a
    /// `switch` buried in a view that no test on a Mac can reach: `MapStyle` is opaque, not
    /// `Equatable`, and cannot be inspected once built. The view builds its `MapStyle` *from*
    /// this, so the table is the thing that ships.
    public var recipe: MapStyleRecipe {
        switch self {
        case .standard:
            return MapStyleRecipe(base: .standard, isMuted: false,
                                  excludesPointsOfInterest: true)
        case .muted:
            return MapStyleRecipe(base: .standard, isMuted: true,
                                  excludesPointsOfInterest: true)
        case .satellite:
            // Imagery takes no points-of-interest argument at all: there is no label layer to
            // exclude. `nil` records that, rather than claiming an exclusion nobody made.
            return MapStyleRecipe(base: .imagery, isMuted: false,
                                  excludesPointsOfInterest: nil)
        case .hybrid:
            return MapStyleRecipe(base: .hybrid, isMuted: false,
                                  excludesPointsOfInterest: true)
        }
    }
}

/// The arguments one `MapStyleChoice` resolves to. See `MapStyleChoice.recipe`.
public struct MapStyleRecipe: Sendable, Equatable {

    public enum Base: String, Sendable, Equatable, Codable {
        case standard
        case imagery
        case hybrid
    }

    public var base: Base
    /// `StandardEmphasis.muted`. Only ever true on `.standard` — there is no muted photograph.
    public var isMuted: Bool
    /// Whether the style is asked to draw no points of interest, or `nil` when the style takes
    /// no such argument (imagery has no label layer).
    ///
    /// A session map is about one track. Restaurants and car parks on it are the map competing
    /// with the thing the map is for — so wherever the argument exists, it is used.
    public var excludesPointsOfInterest: Bool?

    /// Always. A track is a plan view; see the type comment on `MapStyleChoice`.
    public var isFlat: Bool { true }

    /// Whether the track needs its dark outer halo. True exactly where the ground is
    /// photography.
    public var needsTrackHalo: Bool { base != .standard }

    public init(base: Base, isMuted: Bool, excludesPointsOfInterest: Bool?) {
        self.base = base
        self.isMuted = isMuted
        self.excludesPointsOfInterest = excludesPointsOfInterest
    }
}

/// The one stored copy of the rider's choice — per user, not per session, and the twin of
/// `MapLayerVisibilityStore` down to the shape.
public enum MapStyleStore {

    public static let defaultsKey = "mapStyle.v1"

    /// Apple's plain map when nothing was ever stored — and also when the stored value names a
    /// style this build does not have, because a preference written by a later version must
    /// degrade to the default rather than to a crash or a blank map.
    public static func load(from defaults: UserDefaults) -> MapStyleChoice {
        guard let raw = defaults.string(forKey: defaultsKey),
              let choice = MapStyleChoice(rawValue: raw) else { return .standard }
        return choice
    }

    public static func save(_ choice: MapStyleChoice, to defaults: UserDefaults) {
        defaults.set(choice.rawValue, forKey: defaultsKey)
    }
}
