import Foundation

/// The only thing the watch complication is allowed to say about a finished session.
///
/// **Three measured facts, and deliberately not a headline.** ADR-016 is explicit that the
/// watch detects nothing: there is no flight detection, no turn detection and no jibe tally on
/// the wrist, because a second implementation of them would be a second answer to every
/// question the phone already answers. So a complication cannot print "9 clean jibes" — the
/// watch does not know, and inventing a number for a watch face would be the exact failure
/// ADR-016 exists to prevent. What the watch *measured* is duration, distance and top speed,
/// and those are what travel here.
///
/// Written by `SessionRecorder.stop()` after the container is assembled — after, so a session
/// that failed to save never leaves a summary behind claiming it did.
struct WatchLastSession: Codable, Equatable, Sendable {
    var startedAt: Date
    var durationS: Double
    var distanceM: Double
    var maxSpeedMps: Double
}

/// Where the snapshot lives, and what happens when the app group is not available.
///
/// **A deliberate copy of `WidgetSnapshotStore`'s arrangement**, for the same reason and with
/// the same consequence. The App Store provisioning profiles in use today do not carry
/// `group.de.lahmann.wingfoil`, and requesting an entitlement a profile does not grant fails
/// the archive — which would break TestFlight for the whole watch app in order to put a date
/// on a complication. So the store probes the shared container at runtime: with the group, the
/// complication shows the last session; without it, the write is a no-op and the complication
/// shows "Start session", which is the state on every build shipped so far.
///
/// Turning it on is a portal change and not a code change: add App Groups to the watch app id
/// and to `de.lahmann.wingfoil.watchkitapp.widgets`, add
/// `com.apple.security.application-groups` to both `entitlements` blocks in `ios/project.yml`,
/// and the date appears by itself.
///
/// `containerURL(forSecurityApplicationGroupIdentifier:)` is the only honest probe — a
/// `UserDefaults(suiteName:)` round-trip succeeds *within one process* even with no group at
/// all, because the unentitled suite is just a plist in the app's own container. That false
/// positive is precisely the bug this check exists to avoid.
enum WatchLastSessionStore {

    static let appGroupID = "group.de.lahmann.wingfoil"
    static let defaultsKey = "watchLastSession.v1"

    static var appGroupAvailable: Bool {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    private static var sharedDefaults: UserDefaults? {
        guard appGroupAvailable else { return nil }
        return UserDefaults(suiteName: appGroupID)
    }

    /// Publishes the snapshot. Returns whether it reached the *shared* container — i.e.
    /// whether the complication process can actually see it.
    @discardableResult
    static func write(_ session: WatchLastSession) -> Bool {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(session) else { return false }
        defaults.set(data, forKey: defaultsKey)
        return true
    }

    static func read() -> WatchLastSession? {
        guard let data = sharedDefaults?.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WatchLastSession.self, from: data)
    }
}
