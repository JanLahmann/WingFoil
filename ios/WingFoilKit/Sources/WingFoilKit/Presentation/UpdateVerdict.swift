import Foundation

/// **How loudly the switch asks** — the one word `web/app/version.json` carries per channel
/// (docs/presentation/status-feedback-start-widgets-ipad.md, "The beta's update reminder").
///
/// Two levels and no third, because there are only two honest answers to "you are behind":
/// *say so once and let him get on with it*, and *this build is not worth a report any more*.
/// A rider on a beach with a session to import is never served by a third shade in between.
///
/// An unknown word in the file decodes as `remind` and never as `insist`: a typo must not be
/// able to put a full screen in front of every tester, and the app that reads the file is
/// already installed by the time anybody notices.
public enum UpdateLevel: String, Sendable, Codable, CaseIterable {
    /// One dismissable line at the top of the library.
    case remind
    /// The whole of the app until the newer build is installed.
    case insist
}

/// **Is the build in this rider's hand still one we want reports about?** — the pure half of
/// the beta's update reminder, and the only half with a test.
///
/// The app does everything this type cannot: it fetches `version.json` once a day, keeps the
/// last answer and the rider's dismissal in `UserDefaults`, and draws the banner or the
/// screen (`UpdateReminder`, `UpdateReminderViews`). What is left over is one comparison of
/// four numbers and words, which is exactly the part that can be got wrong quietly — an
/// off-by-one on `minBuild` nags every tester who is already current, a dismissal read the
/// wrong way round silences the one screen that was meant to be unmissable — so it lives
/// here, in the kit, where the suite can hold it.
///
/// **Beta and dev only** (docs/channels.md). Nothing in the release build ever calls this;
/// the kit compiles it in every channel the way it compiles everything else, and the app's
/// whole half of the feature is behind `#if BETA`, so the App Store binary carries no URL,
/// no key and no screen.
public enum UpdateVerdict: String, Sendable, Equatable, CaseIterable {
    /// This build is at or above what the file asks for — or the file says nothing about
    /// this channel at all, which is the same thing and is how a reminder is withdrawn.
    case current
    /// A newer build is out and the rider has not said "yes, I know": one line, dismissable.
    case remind
    /// The same fact, already acknowledged. Not silence for the *app* — Settings still says
    /// it out loud — silence for the library, which is what the rider asked for.
    case dismissed
    /// A newer build is out and this one is not worth a report any more: the whole screen.
    case insist

    /// **The comparison.** `runningBuild` is `CFBundleVersion`; `minBuild` and `level` are
    /// this channel's entry in `version.json`; `dismissedMinBuild` is the highest `minBuild`
    /// the rider has waved away, or `nil` if he never has.
    ///
    /// Three rules, in this order, and the order is the point:
    ///
    /// 1. **A number we cannot read says nothing.** A zero or negative build on either side
    ///    is a missing plist key or a file with a typo in it, and the answer to both is
    ///    `current` — the feature's failure mode is silence, everywhere, including here.
    /// 2. **At or above the floor is current.** `minBuild` is the oldest build still worth a
    ///    report, not the newest build that exists, so the tester who is *ahead* of the file
    ///    (a dev build cut this morning) is never told to go back.
    /// 3. **`insist` outranks the dismissal.** A dismissal is the rider saying "not now" to a
    ///    line; it cannot answer a screen that exists because his build's reports are no
    ///    longer worth reading. Only `remind` is dismissable, and the dismissal is kept
    ///    against the *number*, so the next raise of `minBuild` asks again by itself.
    public static func decide(minBuild: Int,
                              level: UpdateLevel,
                              runningBuild: Int,
                              dismissedMinBuild: Int?) -> UpdateVerdict {
        guard minBuild > 0, runningBuild > 0 else { return .current }
        guard runningBuild < minBuild else { return .current }
        if level == .insist { return .insist }
        if let dismissedMinBuild, dismissedMinBuild >= minBuild { return .dismissed }
        return .remind
    }

    /// Whether the library is allowed to go on looking like the library.
    public var isSilent: Bool { self == .current || self == .dismissed }

    /// **What Settings → Beta prints beside "Check for a newer build now".** The one place
    /// all four verdicts are named to a rider, because it is the one place he asked.
    ///
    /// No version number in any of them: the row draws the build it is running beside this,
    /// and a sentence that repeated it would read as two different facts.
    public var label: String {
        switch self {
        case .current: "This is the current build."
        case .remind: "A newer build is out."
        case .dismissed: "A newer build is out. You closed the reminder."
        case .insist: "A newer build is needed."
        }
    }
}
