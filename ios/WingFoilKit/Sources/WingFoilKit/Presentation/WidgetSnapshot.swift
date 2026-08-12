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
public struct WidgetSnapshot: Codable, Sendable, Equatable {

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

        public var hasTurnTally: Bool { flewThrough + touchdown + fellIn > 0 }

        public init(id: String, title: String, date: Date, foilPct: Double?, best2sKn: Double?,
                    flightCount: Int?, durationS: Double, flewThrough: Int, touchdown: Int,
                    fellIn: Int) {
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
        }
    }

    public var generatedAt: Date
    public var lastSession: LastSession?
    /// Foiling time over the last 7 days, in minutes. Foil *time*, not session time — the
    /// widget's whole point is the number the sport is actually about.
    public var weeklyFoilMinutes: Double
    public var weeklySessions: Int
    /// Session time over the last 7 days, in hours (the denominator behind the foil share).
    public var weeklyHours: Double

    public init(generatedAt: Date = Date(), lastSession: LastSession? = nil,
                weeklyFoilMinutes: Double = 0, weeklySessions: Int = 0,
                weeklyHours: Double = 0) {
        self.generatedAt = generatedAt
        self.lastSession = lastSession
        self.weeklyFoilMinutes = weeklyFoilMinutes
        self.weeklySessions = weeklySessions
        self.weeklyHours = weeklyHours
    }

    public var isEmpty: Bool { lastSession == nil && weeklySessions == 0 }
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
