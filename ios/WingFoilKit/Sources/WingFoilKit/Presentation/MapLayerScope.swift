import Foundation

/// **Which map is asking.**
///
/// The session page draws three maps — the Ride tab's track (inline, full screen and the
/// cinema clip it records), the Turns tab's filtered maneuver map and the Takeoffs tab's
/// attempt map — and since 6 Sep 2026 all three are controlled the same way: the collapsible
/// `MapLegendView` header, the same chips, the same "show all", the same style picker. What
/// differs between them is *which* categories they can draw at all, and what a sensible
/// starting state is for each.
///
/// Two rules, and they are the whole type:
///
/// * **A map gets chips only for the layers it draws.** A `pumping` chip on the Turns map
///   would be a control that changes nothing, which is worse than no control: it tells the
///   rider the page has a state it does not have. So the subset is declared here, once,
///   beside the defaults, where a test can hold the two to each other.
/// * **Visibility is per map.** Hiding "fell in" on Turns — where the whole page is a
///   verdict, and the reader may want to look only at the ones that worked — must not blank
///   the falls on the Ride map, which is a picture of the afternoon. Three stored sets,
///   three keys, one shared collapsed/expanded header state (`mapLegend.expanded.v1`),
///   because "I use the chips" is a fact about a rider and not about a map.
///
/// The **data** filters are not in here and must never be: the Turns tab's type/side
/// segments and the Takeoffs tab's outcome chips choose *which attempts the page is about*,
/// and the legend chooses *what is drawn about them*. Two questions, two controls — see
/// `TurnFilter` and `TakeoffOutcomeFilter`.
public enum MapLayerScope: String, CaseIterable, Sendable, Identifiable, Codable {
    /// The session track: everything the catalogue has.
    case ride
    /// The Turns tab's maneuver map.
    case turns
    /// The Takeoffs tab's attempt map.
    case takeoffs

    public var id: String { rawValue }

    /// The categories this map can draw, in the order the legend lists them (route group
    /// first, then the events).
    ///
    /// **Turns draws no line layers.** Its route is deliberately neutral grey — the page is
    /// about one filtered subset of turns, and a phase-tinted track under them would be the
    /// loudest thing on a 240 pt figure. So `flying` / `offFoil` / `effort` / `pumping` are
    /// absent rather than present-and-inert. `courseChange` *is* there, and it is the one
    /// place the two kinds of control meet without colliding: the type/side filter is about
    /// counted maneuvers, and the grey non-verdict sweeps are context you can switch on
    /// beside them.
    ///
    /// **Takeoffs draws the pumping spans**, because an attempt is the burst plus what came
    /// of it, and it draws its neutral route for the same reason Turns does.
    /// The order is the legend's, not the catalogue's: the route group (the line categories
    /// plus `direction`, which is about the route even though it hides like a marker) and
    /// then the events, clean jibe first. `effort` closes the route group because its chip
    /// is labelled with the selected record rather than with its own name. Splitting the
    /// list into the legend's two rows is `isLine || .direction`, and nothing else needs to
    /// know the order.
    public var layers: [MapLayer] {
        switch self {
        case .ride:
            return [.flying, .offFoil, .pumping, .direction, .effort,
                    .cleanJibe, .flewThrough, .touchdown, .fellIn, .courseChange,
                    .takeoff, .splash]
        case .turns:
            return [.direction, .cleanJibe, .flewThrough, .touchdown, .fellIn, .courseChange]
        case .takeoffs:
            return [.pumping, .direction, .takeoff, .splash]
        }
    }

    public func draws(_ layer: MapLayer) -> Bool { layers.contains(layer) }

    /// What is off when a rider first opens this map.
    ///
    /// Ride hides nothing — that contract predates the split and is the one a rider who
    /// never touches a chip relies on. The two analysis maps each hide the one category that
    /// is texture rather than subject: the direction chevrons, which on a small figure full
    /// of pins read as a second dotted line. Turns also opens without the grey course
    /// changes, because the page's headline is a percentage of *maneuvers* and a bear-away
    /// is not one.
    public var hiddenByDefault: Set<MapLayer> {
        switch self {
        case .ride: return []
        case .turns: return [.direction, .courseChange]
        case .takeoffs: return [.direction]
        }
    }

    public var defaultVisibility: MapLayerVisibility {
        MapLayerVisibility(hidden: hiddenByDefault)
    }

    /// Where this map's set is stored. Ride keeps the original key, so a rider who hid
    /// "course change" months ago still has it hidden on the map he hid it on.
    public var defaultsKey: String {
        switch self {
        case .ride: return MapLayerVisibilityStore.defaultsKey
        case .turns: return "mapLayerVisibility.turns.v1"
        case .takeoffs: return "mapLayerVisibility.takeoffs.v1"
        }
    }
}

extension MapLayerVisibility {

    /// How many of *this map's own* categories are hidden **and present in this session** —
    /// the number the legend header prints.
    ///
    /// Three conditions, and each one is a bug it prevents. Only the scope's layers, or a
    /// map would report a filter on something it cannot draw. Only categories the session
    /// has any of, or a rider who hid "splash" months ago is told something is off on every
    /// session he never went under on. And only hidden ones, obviously — the number's whole
    /// job is to be the reason to open the block.
    public func hiddenCount(in scope: MapLayerScope, tally: MapLayerTally) -> Int {
        scope.layers.filter { !isVisible($0) && tally.count($0) > 0 }.count
    }

    /// "Show all" for one map: everything in its subset comes back, and a category it does
    /// not draw is left exactly as the rider set it on the map that does.
    public mutating func showAll(in scope: MapLayerScope) {
        for layer in scope.layers { setVisible(true, for: layer) }
    }

    /// Whether this map has anything hidden — what decides if "show all" is on screen.
    /// Scoped for the same reason the count is: a hidden `pumping` is not the Turns map's
    /// business.
    public func isEverythingVisible(in scope: MapLayerScope) -> Bool {
        scope.layers.allSatisfy(isVisible)
    }
}

extension MapLayerVisibilityStore {

    /// One map's stored set, or that map's own defaults when nothing was ever stored — and
    /// also when the stored blob is unreadable, because a corrupt preference must not leave
    /// a map half blank with no way to reason about why.
    public static func load(scope: MapLayerScope, from defaults: UserDefaults)
        -> MapLayerVisibility {
        guard let data = defaults.data(forKey: scope.defaultsKey),
              let decoded = try? JSONDecoder().decode(MapLayerVisibility.self, from: data)
        else { return scope.defaultVisibility }
        return decoded
    }

    public static func save(_ visibility: MapLayerVisibility, scope: MapLayerScope,
                            to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(visibility) else { return }
        defaults.set(data, forKey: scope.defaultsKey)
    }

    /// Every key the three maps use — what a "forget my preferences" sweep has to clear.
    public static var allDefaultsKeys: [String] { MapLayerScope.allCases.map(\.defaultsKey) }
}
