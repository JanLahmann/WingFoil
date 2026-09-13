import Foundation

/// One of the two maps the rider asked the watch to hold.
///
/// A **spot** is a library cluster, named by its own id so a rename never loses the pick.
/// **Here** is not a spot at all: it is wherever the phone is standing at the moment of the
/// send — the answer for the afternoon at a lake the library has never seen, which is the
/// one afternoon the automatic rule cannot serve (Jan, 13 Sep 2026).
public enum WatchMapPick: Codable, Hashable, Sendable {
    case spot(id: String)
    case here
}

/// Which two maps go to the watch — the rider's answer, or none at all.
///
/// WHY EMPTY MEANS AUTOMATIC AND NOT "SEND NOTHING". Every install before this one had no
/// choice to make and got the two most-ridden spots; the same default has to survive the
/// upgrade without anyone opening Settings. So an empty list is not an empty answer, it is
/// *no answer yet*, and no answer keeps the old rule. It also gives the picker a real row
/// to check ("Two most-ridden spots") rather than making "nothing ticked" mean something.
///
/// WHY AT MOST TWO, AND WHY THE OLDEST GOES. `MapSnapshot.mc` has two slots and a third
/// send evicts one of them on the watch, blind. Better that the phone does the evicting,
/// where the rider can see it: a third pick drops the **oldest** one, because the pick he
/// just made is the one he is thinking about and the one he made first is the one he has
/// stopped thinking about.
public struct WatchMapChoice: Codable, Equatable, Sendable {

    /// How many maps the watch can hold — `MapSnapshot.SLOTS` and `WatchMapSender.slots`
    /// are the other two spellings of this number.
    public static let slots = 2

    /// The picks, oldest first. Empty means automatic.
    public var picks: [WatchMapPick]

    public init(picks: [WatchMapPick] = []) {
        self.picks = Array(picks.prefix(Self.slots))
    }

    /// True when nobody has chosen and the two most-ridden spots still answer.
    public var isAutomatic: Bool { picks.isEmpty }

    public func contains(_ pick: WatchMapPick) -> Bool { picks.contains(pick) }

    /// Tick or untick one row. A third tick drops the oldest pick rather than refusing the
    /// tap: a picker that goes dead on the third row reads as broken, and the rider's
    /// newest word is the one he means.
    public mutating func toggle(_ pick: WatchMapPick) {
        if let index = picks.firstIndex(of: pick) {
            picks.remove(at: index)
        } else {
            picks.append(pick)
            if picks.count > Self.slots { picks.removeFirst(picks.count - Self.slots) }
        }
    }

    // MARK: - Where it is kept

    /// Versioned because the shape of a pick is the sort of thing that grows a case, and a
    /// stale JSON that decodes into the wrong answer would be a map of the wrong lake.
    public static let defaultsKey = "watchMap.choice.v1"

    /// The stored choice, or automatic when nothing is stored — or when what is stored no
    /// longer decodes, which is the same situation from the rider's side.
    public static func load(from defaults: UserDefaults) -> WatchMapChoice {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(WatchMapChoice.self, from: data)
        else { return WatchMapChoice() }
        return WatchMapChoice(picks: stored.picks)
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    // MARK: - Turning a choice into ground

    /// The spots that have a coordinate and at least one session, most-ridden first.
    ///
    /// Ties break on the spot name so the answer is total: two spots with four afternoons
    /// each must not swap places between launches and re-push two masks for nothing. The
    /// picker lists spots through this same call, so the order the rider chooses from is
    /// the order the automatic rule would have chosen in.
    public static func mostRidden(_ spots: [SpotAggregate],
                                  limit: Int = .max) -> [SpotAggregate] {
        spots
            .filter { $0.sessions > 0 && $0.spot.lat.isFinite && $0.spot.lon.isFinite }
            .sorted {
                $0.sessions == $1.sessions ? $0.spot.name < $1.spot.name
                                           : $0.sessions > $1.sessions
            }
            .prefix(limit)
            .map { $0 }
    }

    /// What the sender should actually draw, in the order it should draw it.
    ///
    /// A pick can go stale in two ways and both are silently skipped rather than raised: a
    /// spot the library re-clustered out of existence, and "here" on a phone that has not
    /// been told where it is. Neither is a thing the rider can fix from a map row, and a
    /// send that quietly carries one map instead of two is better than one that carries
    /// none.
    public static func resolve(_ choice: WatchMapChoice, spots: [SpotAggregate],
                               here: (lat: Double, lon: Double)?,
                               limit: Int = slots) -> [WatchMapTarget] {
        guard limit > 0 else { return [] }
        guard !choice.isAutomatic else {
            return mostRidden(spots, limit: limit).map {
                WatchMapTarget(clusterKey: $0.spot.id, name: $0.spot.name,
                               lat: $0.spot.lat, lon: $0.spot.lon)
            }
        }
        var resolved: [WatchMapTarget] = []
        for pick in choice.picks where resolved.count < limit {
            switch pick {
            case .spot(let id):
                guard let match = spots.first(where: { $0.spot.id == id }),
                      match.spot.lat.isFinite, match.spot.lon.isFinite else { continue }
                resolved.append(WatchMapTarget(clusterKey: match.spot.id,
                                               name: match.spot.name,
                                               lat: match.spot.lat, lon: match.spot.lon))
            case .here:
                guard let here, here.lat.isFinite, here.lon.isFinite else { continue }
                resolved.append(WatchMapTarget(clusterKey: WatchMapTarget.hereKey,
                                               name: WatchMapTarget.hereName,
                                               lat: here.lat, lon: here.lon))
            }
        }
        return resolved
    }
}

/// One map to draw and push: a name for the caption, a centre for the box, and the cluster
/// key the watch hashes into its slot id.
///
/// WHY "here" HAS A LITERAL KEY. `mi` is a hash of this key (`WatchMapMask.spotID`), and
/// the watch replaces a slot whose id it already holds. "Where I am now" therefore has to
/// hash to the *same* number every time, or a rider who sends it twice from two beaches
/// would fill both slots with himself. The literal `"here"` gives it one id for life: the
/// second send replaces the first, which is what "now" means.
public struct WatchMapTarget: Equatable, Sendable {

    /// The cluster key for the phone's own position.
    public static let hereKey = "here"
    /// What the watch's caption says under that map.
    public static let hereName = "Where I am now"

    public let clusterKey: String
    public let name: String
    public let lat: Double
    public let lon: Double

    public init(clusterKey: String, name: String, lat: Double, lon: Double) {
        self.clusterKey = clusterKey
        self.name = name
        self.lat = lat
        self.lon = lon
    }

    /// True when this map is the phone's own position rather than a library spot.
    public var isHere: Bool { clusterKey == Self.hereKey }
}
