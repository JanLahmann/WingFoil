import Foundation

/// **One anonymous count, as the beta and dev apps send it to umami** (docs/analytics.md, "The
/// iPhone app — Jan's decision of 18 October 2026"; docs/decisions.md ADR-039).
///
/// This type is the body of one `POST` to umami's collector and nothing else: it knows no
/// URL, opens no connection and keeps nothing. The sender lives in the app target behind
/// `#if BETA`, so the App Store binary has no network path to umami at all; the kit compiles
/// this in every channel (CLAUDE.md) because it is pure and the test suite reads it.
///
/// **The guard is `web/js/track.js`'s, rule for rule.** Strings are trimmed and capped at 32
/// characters, an empty one is dropped, a number must be finite, and at most six properties
/// travel. What may travel at all is the same as on the web: a count, a format, a source
/// class, a screen name, a card shape, a fixed word out of a closed set the call site names.
/// Never a file name, a spot, a coordinate, a date, a title, a number off a ride, an error
/// text or any identifier. Swift's types do half of that guard before a value gets here — a
/// `Value` cannot be an object — and `scrub` does the other half.
///
/// **One umami website, two hostnames.** The property is shared with the Fun with Quantum
/// family and with cleanjibe.org itself, so every event name carries the `CleanJibe: ` prefix
/// (added in one place, `body`), and the app reports as `ios.cleanjibe.org` so its screens
/// never mix with the website's pages in the dashboard.
public struct UmamiEvent: Equatable, Sendable {

    /// The shared umami website — the same id cleanjibe.org's pages carry in their script tag.
    public static let website = "97f347ac-e7ba-4be3-b26f-ab4b328bdbf2"
    /// The app's own hostname in the dashboard. Not a host anybody serves: umami files events
    /// by the hostname the client names, and this one keeps the app apart from the site.
    public static let hostname = "ios.cleanjibe.org"
    /// What every event name starts with in the shared dashboard (track.js's `SITE_PREFIX`).
    public static let sitePrefix = "CleanJibe: "
    /// track.js's `MAX_LEN`: a format is 3 characters and a screen name 8.
    public static let maxLength = 32
    /// track.js's `MAX_PROPS`: a counter with fifteen columns is a log.
    public static let maxProperties = 6

    // MARK: - What a property may be

    /// The three kinds track.js lets through: a string, a finite number, a boolean.
    public enum Value: Equatable, Sendable {
        case text(String)
        case int(Int)
        case number(Double)
        case flag(Bool)

        /// The value as it may travel, or nil when it may not: an empty string, a
        /// non-finite number.
        var scrubbed: Value? {
            switch self {
            case .text(let raw):
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : .text(String(text.prefix(UmamiEvent.maxLength)))
            case .number(let x):
                return x.isFinite ? self : nil
            case .int, .flag:
                return self
            }
        }

        var json: Any {
            switch self {
            case .text(let s): s
            case .int(let n): n
            case .number(let x): x
            case .flag(let b): b
            }
        }
    }

    /// One named property. A list rather than a dictionary, so "the first six" means the
    /// same thing every run — a JavaScript object keeps insertion order, a Swift
    /// dictionary does not.
    public struct Property: Equatable, Sendable {
        public let key: String
        public let value: Value

        public init(_ key: String, _ value: Value) {
            self.key = key
            self.value = value
        }

        public static func text(_ key: String, _ value: String) -> Property { .init(key, .text(value)) }
        public static func int(_ key: String, _ value: Int) -> Property { .init(key, .int(value)) }
        public static func flag(_ key: String, _ value: Bool) -> Property { .init(key, .flag(value)) }
    }

    /// track.js's `scrub`: each value through the guard, a key that is already taken skipped,
    /// and the list cut after six survivors.
    public static func scrub(_ properties: [Property]) -> [Property] {
        var out: [Property] = []
        var seen = Set<String>()
        for property in properties {
            if out.count >= maxProperties { break }
            let key = property.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !seen.contains(key), let value = property.value.scrubbed
            else { continue }
            seen.insert(key)
            out.append(Property(key, value))
        }
        return out
    }

    // MARK: - The screens

    /// The top-level screens a pageview names. The path is what umami lists under Pages.
    public enum Screen: String, CaseIterable, Sendable {
        case library, session, turn, share, settings, help

        public var path: String { "/" + rawValue }
    }

    /// What the device says about itself in a browser's terms: the language and the screen
    /// in points, which is what a browser's `screen.width` reports. Nothing else about the
    /// phone travels.
    public struct Context: Equatable, Sendable {
        public let language: String
        public let width: Int
        public let height: Int

        public init(language: String, width: Int, height: Int) {
            self.language = language
            self.width = width
            self.height = height
        }

        var screen: String { String(width) + "x" + String(height) }
    }

    // MARK: - The event

    /// The bare kebab name (`app-card-made`), or nil for a pageview.
    public let name: String?
    /// Where the rider is: a pageview's own screen, or the screen an event happened on.
    public let screen: Screen
    /// Already through `scrub`. Empty on a pageview.
    public let properties: [Property]
    public let context: Context

    /// A screen opened.
    public static func pageview(_ screen: Screen, context: Context) -> UmamiEvent {
        UmamiEvent(name: nil, screen: screen, properties: [], context: context)
    }

    /// A named action, on the screen it happened on.
    public static func event(_ name: String, _ properties: [Property] = [], on screen: Screen,
                             context: Context) -> UmamiEvent {
        UmamiEvent(name: name, screen: screen, properties: scrub(properties), context: context)
    }

    /// The JSON umami's `/api/send` takes. Sorted keys, so the same event is the same bytes.
    public func body() -> Data {
        var payload: [String: Any] = [
            "website": Self.website,
            "hostname": Self.hostname,
            "url": screen.path,
            "title": screen.rawValue,
            "language": context.language,
            "screen": context.screen,
        ]
        if let name {
            payload["name"] = Self.sitePrefix + name
            if !properties.isEmpty {
                payload["data"] = Dictionary(properties.map { ($0.key, $0.value.json) },
                                             uniquingKeysWith: { first, _ in first })
            }
        }
        let envelope: [String: Any] = ["type": "event", "payload": payload]
        return (try? JSONSerialization.data(withJSONObject: envelope,
                                            options: [.sortedKeys, .withoutEscapingSlashes]))
            ?? Data()
    }
}

// MARK: - The usage counters, as umami events

extension UmamiEvent {

    /// **The one place a counted feature becomes an event.** `Usage.record` in the app hands
    /// every success it counts here as well (beta and dev only), so the umami dashboard and the
    /// feedback mail's usage block count the same doors.
    ///
    /// `detail` is the counter's own variant code. Only the features below that name a key
    /// for it send it, and only as the closed-set word the call site wrote; a detail on any
    /// other feature is dropped, so a future call site cannot leak something by accident.
    public static func counted(_ feature: UsageCounters.Feature, times: Int = 1,
                               detail: String? = nil, on screen: Screen,
                               context: Context) -> UmamiEvent {
        event(feature.umamiName, properties(feature, times: times, detail: detail),
              on: screen, context: context)
    }

    /// An import that brought sessions in: track.js's `app-file-analyzed`, with the way in as
    /// `source` and how many sessions it brought as `sessions`. Nil for a source the usage
    /// report does not count (the example, the fixtures, the Garmin card).
    public static func imported(_ source: ImportSource, automatic: Bool, sessions: Int,
                                on screen: Screen, context: Context) -> UmamiEvent? {
        guard let word = importSource(source, automatic: automatic) else { return nil }
        return event("app-file-analyzed", [.text("source", word), .int("sessions", sessions)],
                     on: screen, context: context)
    }

    /// The `source` words. The web's where they mean the same thing (`picker`, `shared`,
    /// `icu`), the phone's own for the doors a browser does not have.
    public static func importSource(_ source: ImportSource, automatic: Bool) -> String? {
        switch source {
        case .icu: automatic ? "icu-auto" : "icu"
        case .file: "picker"
        case .airdrop: "shared"
        case .gdpr: "zip"
        case .strava: "strava"
        case .appleHealth: automatic ? "health-auto" : "health"
        case .appleWatch: "apple-watch"
        case .watchDirect: "watch-direct"
        default: nil
        }
    }

    static func properties(_ feature: UsageCounters.Feature, times: Int,
                           detail: String?) -> [Property] {
        var out: [Property] = []
        let parts = (detail ?? "").components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func part(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
        switch feature {
        case .shareCard:
            // `ShareCardDesign.variant`: "shape · hero · ground". The web's `map` flag,
            // and the phone's photo background beside it.
            out = [.text("how", "share"), .text("kind", "session"), .text("shape", part(0)),
                   .text("hero", part(1)), .flag("map", part(2) == "map"),
                   .flag("photo", part(2) == "photo")]
        case .periodShare:
            out = [.text("how", "share"), .text("kind", "period"), .text("shape", part(0)),
                   .text("hero", part(1)), .flag("map", part(2) == "map"),
                   .text("tracks", part(3))]
        case .turnPage: out = [.text("kind", "turn")]
        case .flightEndPage: out = [.text("kind", "end")]
        case .trends: out = [.text("tab", "trends")]
        case .records: out = [.text("tab", "records")]
        case .units: out = detail.map { [.text("units", $0)] } ?? []
        case .speedRecordPolicy: out = detail.map { [.text("rule", $0)] } ?? []
        case .grouping: out = detail.map { [.text("grouping", $0)] } ?? []
        case .mapStyle: out = detail.map { [.text("style", $0)] } ?? []
        case .replay: out = detail.map { [.flag("fullScreen", $0 == "full screen")] } ?? []
        case .riderAssign: out = detail.map { [.flag("mine", $0 == "mine")] } ?? []
        case .gearSpots: out = detail.map { [.text("what", $0)] } ?? []
        case .windsurfMode: out = detail.map { [.flag("on", $0 == "on")] } ?? []
        case .fitShare: out = detail.map { [.flag("wrist", $0 == "with wrist")] } ?? []
        case .mapToWatch: out = detail.map { [.flag("automatic", $0 == "automatic")] } ?? []
        case .chooseWatch: out = detail.map { [.text("action", $0)] } ?? []
        case .usageReport: out = detail.map { [.text("layout", $0)] } ?? []
        case .mostWanted: out = [.int("ticks", times)]
        default: break
        }
        if times != 1, feature != .mostWanted { out.append(.int("times", times)) }
        return out
    }
}

extension UsageCounters.Feature {

    /// The event name for this counter: the web's own name wherever docs/analytics.md maps
    /// one (`app-card-made`, `app-session-opened`, `app-turn-page-opened`, the backup pair),
    /// `app-<object>-<verb>` for the rest. Bare: `UmamiEvent.body` adds the site prefix.
    public var umamiName: String {
        switch self {
        case .appOpen: "app-opened"
        case .importIcu: "app-icu-sync-finished"
        case .icuBackground: "app-icu-check-finished"
        case .stravaConnected: "app-strava-connected"
        case .importStrava: "app-strava-import-finished"
        case .importHealth: "app-health-import-finished"
        case .healthAutoImport: "app-health-auto-imported"
        case .importFile: "app-file-imported"
        case .importShareSheet: "app-shared-file-taken"
        case .importZip: "app-zip-imported"
        case .watchTransfer: "app-watch-transfer-finished"
        case .mapToWatch: "app-watch-map-sent"
        case .windToWatch: "app-watch-wind-sent"
        case .chooseWatch: "app-watch-chosen"
        case .appleWatchRecording: "app-apple-watch-recorded"
        case .sessionOpened: "app-session-opened"
        case .reanalysis: "app-analysis-rerun"
        case .tuning: "app-tuning-changed"
        case .windsurfMode: "app-windsurf-set"
        case .turnDirection: "app-turn-direction-set"
        case .turnPage, .flightEndPage: "app-turn-page-opened"
        case .replay: "app-replay-played"
        case .recordReplay: "app-replay-recorded"
        case .mapStyle: "app-map-style-set"
        case .fullScreenMap: "app-map-opened-full"
        case .filters: "app-filter-set"
        case .grouping: "app-grouping-set"
        case .sessionPaging: "app-session-paged"
        case .trends, .records: "app-tab-switched"
        case .periods: "app-period-opened"
        case .sessionStory: "app-story-shown"
        case .shareCard, .periodShare: "app-card-made"
        case .clipExported: "app-clip-saved"
        case .videoExported: "app-video-exported"
        case .fitShare: "app-fit-shared"
        case .sendToDeveloper: "app-session-sent"
        case .rename: "app-session-renamed"
        case .riderAssign: "app-rider-assigned"
        case .gearSpots: "app-gear-set"
        case .deleteSession: "app-session-deleted"
        case .restoreDeleted: "app-deleted-restored"
        case .backupMade: "app-backup-exported"
        case .backupRestored: "app-backup-restored"
        case .iCloudSync: "app-icloud-synced"
        case .startOver: "app-start-over-done"
        case .settingsOpened: "app-settings-opened"
        case .units: "app-units-set"
        case .speedRecordPolicy: "app-speed-rule-set"
        case .rowMetrics: "app-row-metrics-set"
        case .notifications: "app-notification-delivered"
        case .healthExport: "app-health-exported"
        case .feedbackMail: "app-feedback-sent"
        case .usageReport: "app-usage-report-added"
        case .mostWanted: "app-wishlist-ticked"
        }
    }
}
