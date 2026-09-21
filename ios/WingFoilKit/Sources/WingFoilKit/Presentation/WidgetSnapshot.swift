import Foundation

/// What the home-screen widgets draw. A widget extension cannot open the app's SQLite
/// library (different process, different container without an app group), so the app
/// publishes this tiny denormalized snapshot after every library change and the widget
/// only ever decodes it.
///
/// **This file has no dependencies on the rest of the kit on purpose.** The widget target
/// compiles this one source directly instead of linking `WingFoilKit`, which would drag
/// GRDB, the FIT parser and ZIPFoundation into an extension that reads a few hundred bytes
/// of JSON. The half that *builds* a snapshot from library rows lives next door in
/// `WidgetSnapshot+Library.swift`, which the widget does not compile.
///
/// **Every field added after the first version is optional**, and that is load-bearing
/// rather than decorative: a synthesized `init(from:)` does *not* fall back to a property's
/// default value for a missing key, so one new non-optional field would make every blob
/// already sitting in the shared container fail to decode — and the widget would go blank
/// until the rider next opened the app. nil here always means "the build that wrote this
/// did not know the question", never "the answer is none".
public struct WidgetSnapshot: Codable, Sendable, Equatable {

    /// A session's track, thinned and normalized into a unit square, ready to stroke.
    ///
    /// The widget owns no projection code and must not: normalizing is the builder's job
    /// (`TrackThumbnail.Projection`, the same one the list row, the map and the share card
    /// draw through), so what arrives here is already x/y in 0…1 with **y pointing down**,
    /// the aspect preserved by centring the shorter axis in the square.
    public struct Track: Codable, Sendable, Equatable {

        /// The vertices, x and y interleaved — `[x0, y0, x1, y1, …]`.
        ///
        /// Flat rather than an array of points because this is the one field in the
        /// snapshot with a size worth thinking about: a `{"x":…,"y":…}` object per vertex
        /// costs about three times the JSON of a bare number, and the whole blob has to
        /// stay small enough to sit in `UserDefaults` without anyone worrying about it.
        public var xy: [Double]

        /// The sub-rectangle of the unit square the track actually occupies, so the widget
        /// can fit the *track* into its rect instead of the square it was normalized into
        /// — the same reason `TrackThumbnail.contentBox` exists. A session sailed up and
        /// down one reach fills the full width and a third of the height, and a drawing
        /// that inscribed the box would waste most of the widget.
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        /// The side of that unit square in metres (`TrackThumbnail.Bounds.spanM`) — what
        /// the normalization threw away, kept so a caption could say how big the afternoon
        /// was without the widget re-deriving anything.
        public var spanM: Double

        public init(xy: [Double], minX: Double, minY: Double, maxX: Double, maxY: Double,
                    spanM: Double) {
            self.xy = xy
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
            self.spanM = spanM
        }

        public var count: Int { xy.count / 2 }
        /// Two vertices are the fewest that can be a line; one is a dot and draws nothing.
        public var isEmpty: Bool { count < 2 }

        public func point(_ index: Int) -> (x: Double, y: Double) {
            (x: xy[index * 2], y: xy[index * 2 + 1])
        }

        public var points: [(x: Double, y: Double)] {
            (0..<count).map { point($0) }
        }

        /// The content box's own extent, floored so a track that never moved on one axis
        /// cannot divide by zero in a renderer.
        public var boxWidth: Double { max(maxX - minX, 0.0001) }
        public var boxHeight: Double { max(maxY - minY, 0.0001) }
    }

    /// One thing worth saying about the library on a day with no session to report.
    ///
    /// The numbers travel, never the sentence: the widget formats them with the rules it
    /// copies out of the kit, so a fact reads the same as the same number on the session
    /// page. `kind` is a `String` rather than an enum for the reason every other
    /// closed-vocabulary field in this codebase is (`TurnRecord.outcomeReason`): a kind
    /// written by a newer build has to decode, not throw away the whole snapshot.
    public struct Fact: Codable, Sendable, Equatable, Identifiable {

        /// `FactKind.rawValue`.
        public var kind: String
        /// The number, in the unit its kind implies: knots (`best2s`), seconds
        /// (`longestFlight`), per hour (`bestJph`), maneuvers (`longestDryStreak`),
        /// flights (`onThisDay`).
        public var value: Double
        /// The session's name — the library's own title rule, which is the spot where the
        /// rider has named one.
        public var spot: String?
        public var date: Date?
        /// `FactScope.rawValue` — whether the fact is the season's or all-time, because the
        /// widget says which out loud and must not guess.
        public var scope: String?
        /// `onThisDay` only: how many years back that week was, and what it was worth.
        public var yearsAgo: Int?
        public var best2sKn: Double?
        public var flights: Int?

        public var id: String { kind + "·" + (scope ?? "") }

        public var factKind: FactKind? { FactKind(rawValue: kind) }
        public var factScope: FactScope? { scope.flatMap(FactScope.init(rawValue:)) }

        public init(kind: FactKind, value: Double, spot: String? = nil, date: Date? = nil,
                    scope: FactScope? = nil, yearsAgo: Int? = nil, best2sKn: Double? = nil,
                    flights: Int? = nil) {
            self.kind = kind.rawValue
            self.value = value
            self.spot = spot
            self.date = date
            self.scope = scope?.rawValue
            self.yearsAgo = yearsAgo
            self.best2sKn = best2sKn
            self.flights = flights
        }
    }

    public enum FactKind: String, Codable, Sendable, CaseIterable {
        case best2s, longestFlight, bestJph, longestDryStreak, onThisDay
    }

    public enum FactScope: String, Codable, Sendable, CaseIterable {
        case season, allTime
    }

    /// The season so far — the app's own season, 1 April → 31 March (`PeriodRules`), named
    /// the way the Periods screen names it ("2026/27").
    public struct Season: Codable, Sendable, Equatable {
        public var label: String
        public var sessions: Int
        /// Hours **on the foil**, not hours out: the widget's whole point is the number the
        /// sport is about.
        public var foilHours: Double
        public var cleanJibes: Int

        public init(label: String, sessions: Int, foilHours: Double, cleanJibes: Int) {
            self.label = label
            self.sessions = sessions
            self.foilHours = foilHours
            self.cleanJibes = cleanJibes
        }
    }

    /// One ridden afternoon in the recent past, so the widget can re-add "this week" for
    /// the day it is being *drawn* on rather than the day the snapshot was written.
    ///
    /// The stored `weekly*` fields below were a fixed window around `generatedAt`, which is
    /// right on the day of an import and drifts by one day every day after it: a Sunday
    /// session still counted towards "this week" the following Saturday. With the days
    /// themselves carried, the timeline's daily entry recomputes the window and the number
    /// is right on every one of them.
    public struct Day: Codable, Sendable, Equatable {
        public var date: Date
        public var foilMinutes: Double
        public var hours: Double

        public init(date: Date, foilMinutes: Double, hours: Double) {
            self.date = date
            self.foilMinutes = foilMinutes
            self.hours = hours
        }
    }

    public struct LastSession: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var date: Date
        public var foilPct: Double?
        public var best2sKn: Double?
        public var flightCount: Int?
        public var durationS: Double
        /// The turn outcome tally — "9 · 9 · 12" on the widget.
        public var flewThrough: Int
        public var touchdown: Int
        public var fellIn: Int
        /// The afternoon's shape, drawn behind the numbers. nil when the session has no
        /// positions, or when its thumbnail has not been built yet — absent, never a
        /// straight line between two fixes.
        public var track: Track?

        public var hasTurnTally: Bool { flewThrough + touchdown + fellIn > 0 }

        public init(id: String, title: String, date: Date, foilPct: Double?, best2sKn: Double?,
                    flightCount: Int?, durationS: Double, flewThrough: Int, touchdown: Int,
                    fellIn: Int, track: Track? = nil) {
            self.id = id
            self.title = title
            self.date = date
            self.foilPct = foilPct
            self.best2sKn = best2sKn
            self.flightCount = flightCount
            self.durationS = durationS
            self.flewThrough = flewThrough
            self.touchdown = touchdown
            self.fellIn = fellIn
            self.track = track
        }
    }

    public var generatedAt: Date
    /// **The last session actually ridden** — the newest non-provisional row with foil time
    /// on it, and only the newest row of all where the library holds no ridden session at
    /// all. A dry test recording is a real row and stays in the library, but it is not the
    /// afternoon a rider wants on his home screen.
    public var lastSession: LastSession?
    /// Foiling time over the last 7 days, in minutes. Foil *time*, not session time — the
    /// widget's whole point is the number the sport is actually about.
    public var weeklyFoilMinutes: Double
    public var weeklySessions: Int
    /// Session time over the last 7 days, in hours (the denominator behind the foil share).
    public var weeklyHours: Double
    /// The ridden afternoons of the last fortnight, newest last — what `week(endingOn:)`
    /// re-adds per day. nil on a blob written before this existed.
    public var recent: [Day]?
    /// The season so far. nil on an older blob; a season with no sessions in it is still a
    /// season and is carried with zeroes.
    public var season: Season?
    /// The rotation the weekly widget falls back to in a week with no session — one fact
    /// per day, picked by day of year.
    public var facts: [Fact]?
    /// All-time personal bests: best 2 s, longest flight, best JPH. Rates are additive
    /// (CLAUDE.md) — JPH is here beside the speed, not instead of CPH anywhere else.
    public var bests: [Fact]?
    /// **The unit the rider reads speeds in** — `SpeedUnit.rawValue`, "knots" or "kmh".
    ///
    /// Every speed in this blob stays in knots, exactly as every speed in the engine does;
    /// this is the *rendering* instruction that travels with them, because a widget process
    /// cannot read the app's own defaults. nil is a blob written before the setting existed,
    /// and knots is what it meant (`WidgetFormat.speedUnit`, Settings → Units).
    public var speedUnit: String?

    public init(generatedAt: Date = Date(), lastSession: LastSession? = nil,
                weeklyFoilMinutes: Double = 0, weeklySessions: Int = 0,
                weeklyHours: Double = 0, recent: [Day]? = nil, season: Season? = nil,
                facts: [Fact]? = nil, bests: [Fact]? = nil, speedUnit: String? = nil) {
        self.generatedAt = generatedAt
        self.lastSession = lastSession
        self.weeklyFoilMinutes = weeklyFoilMinutes
        self.weeklySessions = weeklySessions
        self.weeklyHours = weeklyHours
        self.recent = recent
        self.season = season
        self.facts = facts
        self.bests = bests
        self.speedUnit = speedUnit
    }

    public var isEmpty: Bool { lastSession == nil && weeklySessions == 0 }

    // MARK: - What the widget asks it, on the day it is drawn

    /// The seven days ending on `date`, re-added from `recent`.
    ///
    /// nil when the blob predates `recent`, which is the honest answer and the signal to
    /// fall back to the stored `weekly*` numbers. The window is **seven local days
    /// inclusive of `date`**, the same "last seven days" the builder used.
    public func week(endingOn date: Date,
                     calendar: Calendar = .current) -> (sessions: Int, foilMinutes: Double,
                                                        hours: Double)? {
        guard let recent else { return nil }
        let today = calendar.startOfDay(for: date)
        guard let first = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }
        let inWindow = recent.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= first && day <= today
        }
        return (sessions: inWindow.count,
                foilMinutes: inWindow.reduce(0) { $0 + $1.foilMinutes },
                hours: inWindow.reduce(0) { $0 + $1.hours })
    }

    /// Whether the week ending on `date` holds a ridden session. False switches the weekly
    /// widget to "since your last session".
    public func hasRiddenWeek(endingOn date: Date, calendar: Calendar = .current) -> Bool {
        if let week = week(endingOn: date, calendar: calendar) { return week.sessions > 0 }
        // An older blob: the stored window is all there is, and it was the truth on the day
        // it was written.
        return weeklySessions > 0
    }

    /// Whole days between the last ridden session and `date`, in the reader's own calendar.
    /// 0 is today, 1 is yesterday. nil when nothing has ever been ridden.
    public func daysSinceLastSession(on date: Date, calendar: Calendar = .current) -> Int? {
        guard let last = lastSession?.date else { return nil }
        let from = calendar.startOfDay(for: last)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day.map { max(0, $0) }
    }

    /// The one fact of the day — the rotation, by day of year, so a rider who looks at his
    /// phone all afternoon sees one thing and tomorrow sees the next.
    ///
    /// Deliberately the *ordinal day* rather than a random pick: a rotation that changes
    /// when the timeline happens to be rebuilt is a flicker, and a fact has to stay put for
    /// the whole day it is the day's fact.
    public func fact(on date: Date, calendar: Calendar = .current) -> Fact? {
        guard let facts, !facts.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return facts[(day - 1) % facts.count]
    }

    public func best(_ kind: FactKind) -> Fact? {
        bests?.first { $0.kind == kind.rawValue }
    }
}

/// Where the snapshot lives, and what happens when the app group is not available.
///
/// **The app group is optional on purpose.** The App Store provisioning profile in use
/// today does not carry `group.de.lahmann.wingfoil`, and adding an entitlement the profile
/// does not grant breaks the archive — so the store probes the shared container at runtime
/// and falls back to the app's own Application Support directory. In the fallback the app
/// still writes and reads its snapshot (so nothing crashes and Settings can show it), but
/// the widget process cannot see it and renders its placeholder. Regenerating the profile
/// with the group turns the widget on with no code change.
public enum WidgetSnapshotStore {

    public static let appGroupID = "group.de.lahmann.wingfoil"
    public static let defaultsKey = "widgetSnapshot.v1"

    /// Whether this process really is entitled to the shared group.
    ///
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` is the only honest test:
    /// it returns nil unless the entitlement is present. Two cheaper-looking probes both
    /// give **false positives** — `UserDefaults(suiteName:)` hands back a usable-looking
    /// object either way, and a write/read round-trip through it succeeds even when the
    /// group does not exist, because the unentitled suite is just a plist inside the app's
    /// own container. It reads back fine *in the same process* and is invisible to the
    /// widget, which is exactly the bug this check exists to avoid.
    public static var appGroupAvailable: Bool {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    /// The shared defaults, or nil when the entitlement is missing.
    public static var sharedDefaults: UserDefaults? {
        guard appGroupAvailable else { return nil }
        return UserDefaults(suiteName: appGroupID)
    }

    /// Fallback location: readable by the app itself, invisible to the widget.
    ///
    /// Resolved here rather than through `AppPaths` so this file stays free of the rest of
    /// the kit — the widget target compiles it on its own. Both sides of the fallback (the
    /// app's write and the app's read) go through this one function, so they agree.
    public static func fallbackURL() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return root.appendingPathComponent("widget-snapshot.json")
    }

    /// Publishes the snapshot. Returns whether it reached the *shared* container — i.e.
    /// whether a widget can actually see it.
    ///
    /// The local copy is written unconditionally: it costs a few hundred bytes, and it
    /// means the app's own read-back never depends on an entitlement it may not have.
    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        if let url = try? fallbackURL() {
            try? data.write(to: url, options: .atomic)
        }
        guard let defaults = sharedDefaults else { return false }
        defaults.set(data, forKey: defaultsKey)
        return true
    }

    public static func read() -> WidgetSnapshot? {
        if let data = sharedDefaults?.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            return decoded
        }
        guard let url = try? fallbackURL(), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
