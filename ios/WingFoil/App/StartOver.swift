import Foundation
import WingFoilKit

// The wipe compiles in the beta and dev channels, where the rider has a button for it
// (Settings → Beta → Start over), and in every DEBUG build, where `UI_RESET=1` and
// `UI_START_OVER=1` drive the same code from the simulator. It does not exist in the App
// Store build (docs/channels.md).
#if BETA || DEBUG

/// **Everything this app has ever written down, removed in one pass.**
///
/// The reason it exists is a thing iOS does not do: deleting an app takes its container
/// with it but *leaves its keychain items behind*, so a tester who reinstalls to see a
/// first run finds his intervals.icu key and his Strava connection already there and never
/// sees the screens he was trying to test (Jan, 14 September 2026).
///
/// One wipe, two callers. `SessionStore.startOver()` closes the library around it and
/// reopens a fresh one afterwards, so the app is back on its first launch without being
/// killed; `SessionStore.resetIfRequested()` calls it from `WingFoilApp.init`, before the
/// store exists, which is what the screenshot hooks have always needed. Neither one owns a
/// list of keys or paths of its own — a second list is a list that goes stale.
///
/// **What it deliberately does not touch:** anything that is not on this phone. Sessions on
/// intervals.icu, activities on Strava, the recordings on a Garmin or an Apple Watch and
/// the authorisation Apple Health holds are all somebody else's copy, and a button in
/// Settings that reached them would be a delete button pretending to be a reset.
enum StartOver {

    /// Wipes the container, the defaults and the keychain.
    ///
    /// **The database must already be closed.** The file is deleted here like any other,
    /// and an open GRDB pool would go on holding the unlinked inode and writing into it —
    /// so the instance path swaps the pool for an in-memory one before calling this and
    /// opens a new one after. Called from `WingFoilApp.init` there is no pool yet, which is
    /// the same precondition met the easy way.
    static func wipe() {
        forgetSecrets()
        forgetDefaults()
        forgetFiles()
    }

    // MARK: - The keychain

    /// The two secrets, and the whole reason for this feature. `Keychain` is the only place
    /// in the app that writes one, and these are the only two accounts it uses.
    private static func forgetSecrets() {
        Keychain.remove(Keychain.icuApiKey)
        Keychain.remove(Keychain.stravaTokens)
    }

    // MARK: - UserDefaults

    /// The **whole** persistent domain rather than a list of keys.
    ///
    /// The app owns somewhere north of forty defaults keys — the welcome flag, the usage
    /// counters, the map style and the three map-layer sets, the replay length, framing and
    /// music, the notification marks, the Strava and Health bookkeeping, the watch's map
    /// picks, the tuning blob, the personal-best snapshot, `@AppStorage` scattered across
    /// half a dozen views — and a hand-maintained list of them is a list that is wrong the
    /// first time somebody adds a key and forgets this file. The domain is the enumeration,
    /// and it is exactly what deleting the app removes.
    ///
    /// The app group goes too: the widget's snapshot and the watch's last-session card live
    /// in that suite, and a widget still drawing last week's session over an empty library
    /// is the wipe visibly not having happened.
    private static func forgetDefaults() {
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        if let shared = WidgetSnapshotStore.sharedDefaults {
            shared.removePersistentDomain(forName: WidgetSnapshotStore.appGroupID)
        }
    }

    // MARK: - The container

    /// Application Support (the SQLite library and its journals, the `Sessions/` archive,
    /// the replay-music copy, the widget snapshot's local fallback), Caches (the reel
    /// renderer's scratch space and the system's own), tmp (a backup zip waiting to be
    /// shared, an export half made) and Documents.
    ///
    /// The *contents* of each, not the directory: iOS creates these for the container and
    /// several of them are expected to exist by anything that writes into them next.
    private static func forgetFiles() {
        let fm = FileManager.default
        var roots: [URL] = [URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)]
        for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory,
                          .cachesDirectory, .documentDirectory] {
            roots.append(contentsOf: fm.urls(for: directory, in: .userDomainMask))
        }
        for root in roots {
            let contents = (try? fm.contentsOfDirectory(at: root,
                                                        includingPropertiesForKeys: nil))
                ?? []
            for url in contents { try? fm.removeItem(at: url) }
        }
    }
}

#endif
