import Foundation

/// One toggleable overlay category on the session map.
///
/// This is the *shared vocabulary*: the legend chips, the map polylines/annotations and the
/// speed chart all resolve through these cases, so a chip can never mean one thing to the
/// map and something else to the chart. Marker cases cover both channels of their outcome
/// (solid = maneuver outcome, hollow = straight-line flight end) — the rider thinks
/// "touchdowns", not "solid touchdowns".
public enum MapLayer: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Track tinted as flying (on foil).
    case flying
    /// Track tinted as off foil.
    case offFoil
    /// The highlighted GP3S window (best 2 s by default) on the map, shaded in the chart.
    case effort
    /// The takeoff runs he pumped through, tinted along the track and shaded in the chart.
    /// A span, not a moment, which is why it is a line category.
    case pumping
    /// **The clean jibes**, as filled stars over the outcome dots they replace: a counted
    /// jibe flown all the way through carrying its speed (docs/presentation.md, "Clean
    /// jibe"). Its own chip because it is its own question — "where did it go right" — and
    /// it cuts across the ladder rather than sitting on it, which is why a starred jibe
    /// also still answers to its outcome chip. Hidden, the star goes back to being the dot
    /// its outcome says it is.
    case cleanJibe
    case flewThrough
    case touchdown
    case fellIn
    case courseChange
    /// Takeoff *attempts*: every flight start the analysis carries, and — since engine
    /// 0.3.0 gave the pumping episodes timestamps — every attempt that never became one.
    /// One chip, because to the rider they are one act: pumping to get up.
    case takeoff
    /// The wrist went under: the barometer's submersion evidence on a turn or a flight end.
    case splash
    /// Which way he was riding: chevrons along the track, oriented to the course. A marker
    /// category rather than a line one — hiding it removes the arrows and leaves the route
    /// exactly as it was, because the arrows are not the route.
    case direction

    public var id: String { rawValue }

    /// Line categories tint the route itself. Hiding one must never erase the route — see
    /// `MapLayerVisibility.lineStyle(flying:)` — which is why they are kept apart from the
    /// markers, whose overlays simply disappear.
    public var isLine: Bool {
        switch self {
        case .flying, .offFoil, .effort, .pumping: return true
        case .cleanJibe, .flewThrough, .touchdown, .fellIn, .courseChange, .takeoff,
             .splash, .direction:
            return false
        }
    }

    public var isMarker: Bool { !isLine }

    /// Chip text. `.effort` is labelled with the selected record instead ("best 2 s"), so
    /// its generic name is only a fallback.
    public var label: String {
        switch self {
        case .flying: return "flying"
        case .offFoil: return "off foil"
        case .effort: return "best effort"
        case .pumping: return "pumping"
        case .cleanJibe: return "clean jibe"
        case .flewThrough: return "flew through"
        case .touchdown: return "touchdown"
        case .fellIn: return "fell in"
        case .courseChange: return "course change"
        case .takeoff: return "takeoff"
        case .splash: return "splash"
        case .direction: return "direction"
        }
    }

    /// The noun VoiceOver reads after "Hide" / "Show".
    public var accessibilityNoun: String {
        switch self {
        case .flying: return "flying track"
        case .offFoil: return "off foil track"
        case .effort: return "best effort highlight"
        case .pumping: return "pumping runs"
        case .cleanJibe: return "clean jibe stars"
        case .flewThrough: return "flew through markers"
        case .touchdown: return "touchdown markers"
        case .fellIn: return "fell in markers"
        case .courseChange: return "course change markers"
        case .takeoff: return "takeoff and failed attempt markers"
        case .splash: return "splash markers"
        case .direction: return "direction of travel chevrons"
        }
    }
}

/// How one track segment is drawn under the current visibility set.
///
/// `neutral` is the whole point of the type: a hidden *line* category drops its tint but
/// keeps a thin gray route, because a rider who hides "flying" wants the colour gone, not
/// the ride.
public enum TrackLineStyle: String, Sendable, Equatable, Codable {
    case flying
    case offFoil
    case neutral
}

/// Which map/chart overlay categories the rider wants to see.
///
/// Stored as the set of *hidden* layers so the default — an empty set — is "show
/// everything", and so a category added in a later version is visible by default rather
/// than silently off.
public struct MapLayerVisibility: Sendable, Equatable, Codable {

    private var hidden: Set<MapLayer>

    public init(hidden: Set<MapLayer> = []) {
        self.hidden = hidden
    }

    public static let allVisible = MapLayerVisibility()

    public var hiddenLayers: Set<MapLayer> { hidden }

    public var isEverythingVisible: Bool { hidden.isEmpty }

    public func isVisible(_ layer: MapLayer) -> Bool { !hidden.contains(layer) }

    public mutating func setVisible(_ visible: Bool, for layer: MapLayer) {
        if visible { hidden.remove(layer) } else { hidden.insert(layer) }
    }

    public mutating func toggle(_ layer: MapLayer) {
        setVisible(!isVisible(layer), for: layer)
    }

    public mutating func showAll() { hidden.removeAll() }

    /// The stroke a segment gets. A hidden line category falls back to `neutral` rather
    /// than disappearing (see `TrackLineStyle`).
    public func lineStyle(flying: Bool) -> TrackLineStyle {
        let layer: MapLayer = flying ? .flying : .offFoil
        guard isVisible(layer) else { return .neutral }
        return flying ? .flying : .offFoil
    }

    // MARK: - Codable

    /// Encoded as a sorted array of raw values, and decoded *leniently*: a layer this build
    /// does not know (an older app reading a newer default) is dropped instead of failing
    /// the whole decode, which would silently reset the rider's choices.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String].self)
        hidden = Set(raw.compactMap(MapLayer.init(rawValue:)))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hidden.map(\.rawValue).sorted())
    }
}

/// How many instances of each category a session actually has.
///
/// A chip for a category with nothing in it is not a control — there is nothing to hide —
/// so the legend renders it subdued and inert. Counting is kept here (rather than inside a
/// view) so the "is this chip live?" rule is testable.
public struct MapLayerTally: Sendable, Equatable {

    private var counts: [MapLayer: Int]

    public init(_ counts: [MapLayer: Int] = [:]) {
        self.counts = counts
    }

    public mutating func add(_ layer: MapLayer, _ amount: Int = 1) {
        counts[layer, default: 0] += amount
    }

    public func count(_ layer: MapLayer) -> Int { counts[layer] ?? 0 }

    /// Whether the chip for `layer` is a live toggle in this session.
    public func isToggleable(_ layer: MapLayer) -> Bool { count(layer) > 0 }
}

/// The one stored copy of the rider's choice: per user, not per session, so the map looks
/// the same on every session and survives a relaunch.
public enum MapLayerVisibilityStore {

    public static let defaultsKey = "mapLayerVisibility.v1"

    /// Everything visible when nothing was ever stored — and also when the stored blob is
    /// unreadable, because a corrupt preference must not leave the map half blank with no
    /// way to reason about why.
    public static func load(from defaults: UserDefaults) -> MapLayerVisibility {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(MapLayerVisibility.self, from: data)
        else { return .allVisible }
        return decoded
    }

    public static func save(_ visibility: MapLayerVisibility, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(visibility) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
