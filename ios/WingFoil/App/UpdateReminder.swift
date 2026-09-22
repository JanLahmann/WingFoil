#if BETA
import Foundation
import UIKit
import WingFoilKit

/// **"There is a newer build than the one you are holding."** — the beta's half of a problem
/// TestFlight does not actually solve (docs/channels.md, beta furniture; docs/presentation/status-feedback-start-widgets-ipad.md,
/// "The beta's update reminder").
///
/// TestFlight offers a build; it does not insist on one, and a tester who has notifications
/// off, or who simply has not opened TestFlight in a fortnight, goes on riding with a build
/// whose reports we have already read and fixed. That is the whole cost of this file: reports
/// against the wrong build, and a rider who thinks a fixed thing is still broken.
///
/// **One static file on cleanjibe.org is the entire mechanism.** `web/app/version.json` says,
/// per channel, the oldest build still worth a report; the app compares it with its own
/// `CFBundleVersion` and shows either nothing, one dismissable line, or one screen
/// (`UpdateVerdict`, in the kit, where the comparison is tested). There is no server, no
/// account and no push: Jan edits a JSON file in the repo, GitHub Pages serves it, and the
/// next launch of every beta on every phone reads it. Withdrawing a reminder is the same
/// edit backwards.
///
/// **What it costs the rider.** One GET of ~300 bytes, at most once every 24 hours, to the
/// site he already installed the app from. No query string, no header of ours, no cookie
/// store, no identifier — the request does not even say which build is asking, because the
/// comparison happens here. Nothing is uploaded, ever, and a failure of any kind (offline,
/// 404, a file with a typo in it) is silence: the app keeps the last answer it had and tries
/// again tomorrow. The privacy page says so in the rider's words, in "what leaves your phone".
///
/// **Beta and dev only.** The whole file is behind `#if BETA`, so the App Store binary
/// contains no URL, no defaults key and no screen — `strings` on it finds no `version.json`
/// (docs/testing.md, "Three channels").
@MainActor
@Observable
final class UpdateReminder {

    /// **A singleton, deliberately.** Three views reach it — the library's banner, the
    /// screen `RootView` puts over everything, and the row in Settings → Beta — and all
    /// three are one-line insertions into files that belong to other features. Handing it
    /// through the environment would mean an edit to `WingFoilApp`, an edit to every
    /// preview, and a store that owns a thing which has nothing to do with sessions.
    ///
    /// It is also what starts the clock: the first body that reads a verdict builds this,
    /// and building it asks the question. Nothing else has to remember to.
    static let shared = UpdateReminder()

    // MARK: - What the rest of the app reads

    /// The current answer. `current` until proven otherwise, which is also what it stays
    /// after every kind of failure.
    private(set) var verdict: UpdateVerdict = .current
    /// Jan's sentence for this build, as the file carries it. Shown on the banner and on the
    /// screen, and nowhere else.
    private(set) var message: String?
    /// Where *Update* goes: the public TestFlight link for the beta, `itms-beta://` for dev
    /// (whose builds are internal and have no public page). Missing or unparsable falls back
    /// to the public link rather than drawing a button that does nothing.
    private(set) var updateURL: URL?
    /// When the file was last read successfully. `nil` until the first one lands, which is
    /// what Settings prints as "not checked yet".
    private(set) var lastCheck: Date?
    /// A check is in flight — only Settings shows it, and only to stop a second tap.
    private(set) var isChecking = false

    /// The build this app is, as a number. `0` when the plist key is missing or not a
    /// number, which `UpdateVerdict` reads as "say nothing".
    let runningBuild: Int = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
        ?? 0

    // MARK: - The switch

    /// The one file. Root-level `app/` rather than a path of its own because that is where
    /// the web app lives and the service worker's bypass list names it there (web/sw.js).
    private static let feed = URL(string: "https://cleanjibe.org/app/version.json")!

    /// Which entry of the file is ours. The kit cannot see a compile flag, so the app tells
    /// it — `AppChannel.channel` is the one `#if` in the app that answers this, and it
    /// answers it for the help catalogue too.
    private static var channelKey: String {
        switch AppChannel.channel {
        case .dev: "dev"
        case .beta: "beta"
        case .release: "release"
        }
    }

    /// Once a day. Not an hour — the thing being watched changes about once a week, and a
    /// rider who reopens the app eleven times on a beach day is not eleven questions.
    private static let interval: TimeInterval = 24 * 60 * 60
    /// After a failure, the soonest another attempt is made in this run. A phone in a car
    /// park with one bar would otherwise retry on every return to the foreground.
    private static let retryFloor: TimeInterval = 10 * 60

    // MARK: - Storage

    private enum Key {
        static let note = "update.note.v1"
        static let lastCheck = "update.lastCheck.v1"
        static let dismissed = "update.dismissedMinBuild.v1"
    }

    private let defaults = UserDefaults.standard
    private var note: ChannelNote?
    private var dismissedMinBuild: Int?
    private var lastAttempt: Date?
    private var foregroundObserver: (any NSObjectProtocol)?

    /// **The last answer is kept, and it is what the first frame draws.** Without it a rider
    /// would see the banner for one launch out of every dozen — the one that happened to fall
    /// after the 24 hours — which is exactly the pattern that teaches a tester the app is
    /// unreliable rather than that his build is old.
    private init() {
        note = (defaults.data(forKey: Key.note)).flatMap {
            try? JSONDecoder().decode(ChannelNote.self, from: $0)
        }
        let stamp = defaults.double(forKey: Key.lastCheck)
        lastCheck = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        dismissedMinBuild = defaults.object(forKey: Key.dismissed) as? Int
        recompute()

        // Every return to the foreground, not only a cold start: a phone that has held the
        // app in memory for three days would otherwise never ask again. The closure captures
        // nothing — it goes back through `shared` — which is what keeps it Sendable.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await UpdateReminder.shared.checkIfDue() }
        }
        Task { [weak self] in await self?.checkIfDue() }
    }

    // MARK: - Asking

    /// The ordinary route: the launch, and every return to the foreground. Does nothing at
    /// all if the last successful read was less than a day ago.
    func checkIfDue() async {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.interval { return }
        await check(force: false)
    }

    /// Settings → Beta → *Check for a newer build now*. Ignores both clocks, because the
    /// rider asking is the whole point of the row.
    func checkNow() async {
        await check(force: true)
    }

    private func check(force: Bool) async {
        guard !isChecking, Self.isWanted else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.retryFloor {
            return
        }
        isChecking = true
        lastAttempt = Date()
        defer { isChecking = false }

        do {
            let request = URLRequest(url: Self.url,
                                     cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                     timeoutInterval: 15)
            let (data, response) = try await Self.session.data(for: request)
            // A bad status is a failure and therefore silence. A response that is not HTTP at
            // all is not: `UI_VERSION_URL` may be a `file://` URL, which is the cheapest test
            // rig there is (docs/testing.md), and in the shipped build this cannot happen.
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return }
            let feed = try JSONDecoder().decode(VersionFeed.self, from: data)
            // A channel the file does not mention is a reminder withdrawn, not a failure:
            // deleting the entry is how Jan takes the banner back off every phone.
            adopt(feed.channels[Self.channelKey])
        } catch {
            // Offline, a 404, a half-written file, a typo in the JSON: silence, the last
            // answer kept, and another attempt in ten minutes at the earliest. Nothing here
            // is worth a word to the rider — he did not ask a question.
        }
    }

    /// A good read: keep it, stamp the clock, decide again.
    private func adopt(_ fresh: ChannelNote?) {
        note = fresh
        if let fresh, let data = try? JSONEncoder().encode(fresh) {
            defaults.set(data, forKey: Key.note)
        } else {
            defaults.removeObject(forKey: Key.note)
        }
        let now = Date()
        lastCheck = now
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastCheck)
        recompute()
    }

    // MARK: - Answering

    /// **The rider closed the line.** Remembered against the number rather than as a flag, so
    /// the next raise of `minBuild` asks again by itself (`UpdateVerdict.decide`). There is
    /// no matching call for the screen: `insist` is not dismissable, which is the only thing
    /// that makes it different from the line.
    func dismiss() {
        guard let note else { return }
        dismissedMinBuild = note.minBuild
        defaults.set(note.minBuild, forKey: Key.dismissed)
        recompute()
    }

    private func recompute() {
        // `isWanted` is asked here as well as before a fetch: a note left in defaults by an
        // ordinary run must not put a banner on a screenshot taken half an hour later.
        guard let note, Self.isWanted else {
            verdict = .current
            message = nil
            updateURL = nil
            return
        }
        verdict = UpdateVerdict.decide(minBuild: note.minBuild,
                                       level: note.level,
                                       runningBuild: runningBuild,
                                       dismissedMinBuild: dismissedMinBuild)
        message = note.message
        updateURL = note.url ?? AppChannel.testFlight
    }

    // MARK: - The file

    /// One channel's entry. Everything is optional in practice — a file Jan edits by hand at
    /// a kitchen table has to be able to be half-right — so only `minBuild` is required, and
    /// a level nobody recognises reminds rather than insists (`UpdateLevel`).
    private struct ChannelNote: Codable, Equatable {
        var minBuild: Int
        var message: String
        var level: UpdateLevel
        var url: URL?

        enum CodingKeys: String, CodingKey { case minBuild, message, level, url }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            minBuild = try container.decode(Int.self, forKey: .minBuild)
            message = (try? container.decode(String.self, forKey: .message)) ?? ""
            let raw = (try? container.decode(String.self, forKey: .level)) ?? ""
            level = UpdateLevel(rawValue: raw) ?? .remind
            url = (try? container.decode(String.self, forKey: .url)).flatMap(URL.init(string:))
        }
    }

    private struct VersionFeed: Decodable {
        var channels: [String: ChannelNote]
    }

    /// Ephemeral, and that is the point: no cookie store, no credential store, no disk cache
    /// and no HTTP cache of ours. Nothing about this request is remembered on either side of
    /// it beyond the answer itself, which lands in `UserDefaults` as four fields.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.allowsConstrainedNetworkAccess = true
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - The simulator's two hooks

    /// `UI_VERSION_URL` points the app at a file of your own — a `python3 -m http.server` in
    /// a folder with one JSON in it is the whole test rig (docs/testing.md, "The beta's
    /// update reminder"). DEBUG only; the shipped build reads one URL and cannot be told
    /// otherwise.
    private static var url: URL {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["UI_VERSION_URL"],
           let override = URL(string: raw) {
            return override
        }
        #endif
        return feed
    }

    /// **Never under the screenshot hooks**, unless the hook being used is this feature's
    /// own. A banner at the top of the library would change every existing shot, and the
    /// store screenshots are taken from the dev build — the same rule, and the same reason,
    /// as `Usage.askIsDue`.
    private static var isWanted: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["UI_VERSION_URL"] != nil { return true }
        if environment.keys.contains(where: { $0.hasPrefix("UI_") }) { return false }
        #endif
        return true
    }
}
#endif
