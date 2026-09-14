import Foundation

/// Everything a beta feedback mail says about the phone it was written on.
///
/// WHY A STRUCT AND NOT A STRING BUILT IN THE VIEW. A bug report is only worth the facts
/// that come with it — "it said 3 jibes" is unanswerable, "it said 3 jibes, build 17 dev,
/// engine 0.19.0, three tuned thresholds, a class (c) Strava import" is a morning's work
/// saved. Those facts are gathered from eight different places in the app (the bundle, the
/// device, the companion link, the library, the open session), and the *wording* that turns
/// them into a mail is the part that can be wrong without anyone noticing until a mail
/// arrives with a blank line where the engine version should be. So the gathering stays in
/// the app, where the frameworks are, and the wording lives here, where the test suite can
/// read every line of it.
///
/// **Nothing here is sent by anything.** `FeedbackReport` produces a subject and a body;
/// the mail composer shows them to the rider, and iOS sends them only when he taps Send.
/// There is no CleanJibe server to send them to in any case.
public struct FeedbackFacts: Sendable, Equatable {

    /// Which build is talking, and what it was told to think.
    public struct App: Sendable, Equatable {
        /// `CFBundleShortVersionString` — "1.0".
        public let version: String
        /// `CFBundleVersion` — the build number, which is the one thing that identifies a
        /// TestFlight build uniquely (both variants share the marketing version).
        public let build: String
        /// The `TUNING` variant. Named in the subject as well as the body: the dev build is
        /// the one that can be running thresholds nobody else has.
        public let isDev: Bool
        public let engineVersion: String
        /// How many analysis thresholds this phone has moved off their published defaults
        /// (`TuningOverrides.changedCount`). Zero on every public build, and on a dev build
        /// that has not been touched; the line is left out when it is zero rather than
        /// printing a reassuring "0", because an absent line is read as "nothing unusual"
        /// and a present one as "look here".
        public let tunedThresholds: Int

        public init(version: String, build: String, isDev: Bool,
                    engineVersion: String, tunedThresholds: Int = 0) {
            self.version = version
            self.build = build
            self.isDev = isDev
            self.engineVersion = engineVersion
            self.tunedThresholds = tunedThresholds
        }
    }

    /// The hardware and the language it is set to. Locale is here because half the
    /// formatting bugs a beta finds are somebody's decimal comma.
    public struct Phone: Sendable, Equatable {
        /// The raw `hw.machine` identifier — "iPhone18,2". Always printed, even when the
        /// friendly name below is known: a name this table gets wrong is still recoverable
        /// from the identifier beside it.
        public let model: String
        /// "iOS 26.0", as the system gives it.
        public let system: String
        /// `Locale.current.identifier` — "en_DE".
        public let locale: String

        public init(model: String, system: String, locale: String) {
            self.model = model
            self.system = system
            self.locale = locale
        }

        /// "iPhone 17 Pro Max (iPhone18,2)", or just the identifier when the table below
        /// has never heard of it.
        public var described: String {
            guard let name = Self.marketingName(model) else { return model }
            return "\(name) (\(model))"
        }

        /// A small, deliberately incomplete table of iPhone identifiers.
        ///
        /// Apple publishes no API for this — `UIDevice.model` says "iPhone" and nothing
        /// more — so the only way to a readable name is a hard-coded list, and a hard-coded
        /// list goes stale the week a new phone ships. That is survivable here and only
        /// here, because the identifier is printed alongside: an unknown phone reports
        /// "iPhone19,4" rather than a wrong name, and nothing downstream depends on the
        /// name at all. iPads and everything else fall through on purpose.
        static func marketingName(_ identifier: String) -> String? {
            switch identifier {
            case "iPhone14,4": "iPhone 13 mini"
            case "iPhone14,5": "iPhone 13"
            case "iPhone14,2": "iPhone 13 Pro"
            case "iPhone14,3": "iPhone 13 Pro Max"
            case "iPhone14,6": "iPhone SE (3rd generation)"
            case "iPhone14,7": "iPhone 14"
            case "iPhone14,8": "iPhone 14 Plus"
            case "iPhone15,2": "iPhone 14 Pro"
            case "iPhone15,3": "iPhone 14 Pro Max"
            case "iPhone15,4": "iPhone 15"
            case "iPhone15,5": "iPhone 15 Plus"
            case "iPhone16,1": "iPhone 15 Pro"
            case "iPhone16,2": "iPhone 15 Pro Max"
            case "iPhone17,1": "iPhone 16 Pro"
            case "iPhone17,2": "iPhone 16 Pro Max"
            case "iPhone17,3": "iPhone 16"
            case "iPhone17,4": "iPhone 16 Plus"
            case "iPhone17,5": "iPhone 16e"
            case "iPhone18,1": "iPhone 17 Pro"
            case "iPhone18,2": "iPhone 17 Pro Max"
            case "iPhone18,3": "iPhone 17"
            default: nil
            }
        }
    }

    /// What is on the rider's wrist, as far as this phone can tell.
    ///
    /// All three are questions the app can answer without asking anybody: the Garmin comes
    /// from the companion link's own state, the watch app version from the last summary
    /// card that arrived over it, and the Apple Watch from `WCSession`.
    public struct Watch: Sendable, Equatable {
        /// The paired Garmin's name — "fenix 8" — or nil when no device has been chosen.
        public let garminModel: String?
        /// The CleanJibe watch app's version, as the last BLE card reported it ("2.2").
        /// Nil when no card has ever arrived: the link knows the watch, not what is
        /// installed on it.
        public let garminAppVersion: String?
        /// nil when the question could not be asked at all (`WCSession` unsupported).
        public let appleWatchPaired: Bool?
        /// Settings → Apple Health → "Import new Health workouts automatically".
        public let healthImport: Bool

        public init(garminModel: String?, garminAppVersion: String?,
                    appleWatchPaired: Bool?, healthImport: Bool) {
            self.garminModel = garminModel
            self.garminAppVersion = garminAppVersion
            self.appleWatchPaired = appleWatchPaired
            self.healthImport = healthImport
        }

        /// The watch component of the subject line: the Garmin, because that is the half a
        /// reporter is most often reporting about.
        var subjectName: String { garminModel ?? "no watch" }
    }

    /// How much is in the library, and which doors it came in by.
    public struct Library: Sendable, Equatable {

        public struct Source: Sendable, Equatable {
            public let label: String
            public let count: Int

            public init(label: String, count: Int) {
                self.label = label
                self.count = count
            }
        }

        public let sessionCount: Int
        /// Non-empty sources only, in the fixed order below.
        public let sources: [Source]

        public init(sessionCount: Int, sources: [Source]) {
            self.sessionCount = sessionCount
            self.sources = sources
        }

        /// Counts one `session.importSource` column per source that names it.
        ///
        /// The column is a `+`-joined set (`"applewatch+icu"` once a sync has seen the same
        /// session), so a session imported twice is counted under both doors and the counts
        /// can sum to more than `sessionCount`. That is the honest answer — "this one
        /// arrived both ways" is exactly the kind of thing a duplicate-session report needs
        /// — and it is why the body prints the total separately rather than implying the
        /// breakdown adds up to it.
        public static func sources(importSources: [String?]) -> [Source] {
            Self.order.compactMap { source in
                let count = importSources.filter { source.key.isNamed(in: $0) }.count
                return count > 0 ? Source(label: source.label, count: count) : nil
            }
        }

        /// The doors, in the order a reader wants them: the two that carry a real recording
        /// off a watch first, then the clouds, then the hand-made ones.
        private static let order: [(key: ImportSource, label: String)] = [
            (.watch, "Garmin card"),
            (.appleWatch, "CleanJibe watch app"),
            (.icu, "intervals.icu"),
            (.strava, "Strava"),
            (.appleHealth, "Apple Health"),
            (.file, "files"),
            (.airdrop, "AirDrop"),
            (.gdpr, "Garmin export"),
            (.example, "example"),
            (.fixtures, "fixtures"),
        ]
    }

    /// The session the report is about, when it was started from one.
    ///
    /// Every field is already a string: the app formats dates and durations in the rider's
    /// own zone and units, and a mail that said "1970-01-01T00:00:00Z" next to a screen
    /// that said "30 Aug 2026" would be describing a different session as far as the reader
    /// is concerned.
    public struct Session: Sendable, Equatable {
        /// The stable row id — the one thing that lets a reply say "open that session again
        /// and tell me what the footer says".
        public let id: String
        public let date: String
        public let spot: String?
        public let discipline: String?
        public let duration: String
        /// The engine's own letter (`a`, `b`, `c`) — the fixtures and the goldens speak it,
        /// so a report about a wrong number is answered in it.
        public let sourceClass: String
        /// `SessionRow.engineVersion`, which carries the tuning stamp when one was in force
        /// ("0.19.0+t3.a41f"). Nil on a row analysed before the column existed.
        public let engineStamp: String?

        public init(id: String, date: String, spot: String?, discipline: String?,
                    duration: String, sourceClass: String, engineStamp: String?) {
            self.id = id
            self.date = date
            self.spot = spot
            self.discipline = discipline
            self.duration = duration
            self.sourceClass = sourceClass
            self.engineStamp = engineStamp
        }
    }

    public let app: App
    public let phone: Phone
    public let watch: Watch
    public let library: Library
    /// Nil when the mail was started from Settings rather than from a session.
    public let session: Session?

    public init(app: App, phone: Phone, watch: Watch, library: Library,
                session: Session? = nil) {
        self.app = app
        self.phone = phone
        self.watch = watch
        self.library = library
        self.session = session
    }
}

/// One sentence, said in five places: *a wish is as welcome as a fault.*
///
/// Jan, 14 September 2026: nothing in the app ever invited an idea. Every door to the mail
/// was named and worded for something being **wrong** — "Support", "Something off? Send
/// feedback" — and a beta whose only invitation is to report faults gets faults reported and
/// nothing else. So the invitation is written once, here, and the five surfaces that can
/// carry it say the same words: the library menu's row (*Support & ideas*), the footer under
/// every page, the welcome screen, Settings → Help, and the mail's own template.
///
/// It lives in the kit rather than in the app for the ordinary reason: it is wording, the
/// test suite reads it, and five literals in five views is five chances to drift.
public enum FeedbackInvitation {

    /// The plain sentence, for prose that already has a paragraph around it (Settings, the
    /// help topic, the mail).
    public static let sentence = "Ideas and wishes are as welcome as bugs."

    /// The same sentence with the way in on the end of it, for a surface that is not next to
    /// the door — the welcome screen, which a rider reads before he has seen the menu.
    /// "·" rather than a dash, like every other separator the app draws.
    public static let welcomeSentence =
        "Ideas and wishes are as welcome as bugs · Menu → Support & ideas"
}

/// The beta feedback mail, as text.
///
/// Pure: a subject, a body and a `mailto:` URL out of a `FeedbackFacts`, with no framework
/// and no side effect. The app hands the first two to `MFMailComposeViewController` and
/// falls back to the third when the phone has no mail account set up.
public enum FeedbackReport {

    /// Where beta feedback goes. One address, not a GitHub issue: the repository is public
    /// and a bug report carries a build number, a phone model and sometimes a session's
    /// spot, which is a map pin to where the reporter rides.
    public static let recipient = "info@cleanjibe.org"

    /// "CleanJibe feedback · build 17 dev · fenix 8".
    ///
    /// The build number rather than the marketing version, because the two TestFlight
    /// variants of a release share a marketing version and differ only here; the watch
    /// because a mailbox sorted by subject then groups the reports that are about one.
    ///
    /// It said *beta feedback* until the release channel was cut. The same composer is the
    /// App Store build's Support & ideas mail, and a subject line that calls that build a
    /// beta is the app telling a rider he is holding a test version (docs/channels.md).
    /// The build number already tells the channels apart, which is what the word was doing.
    public static func subject(_ facts: FeedbackFacts) -> String {
        let build = facts.app.build + (facts.app.isDev ? " dev" : "")
        return "\(Branding.appName) feedback · build \(build) · \(facts.watch.subjectName)"
    }

    /// The three questions a report has to answer, in the order a reporter thinks them.
    ///
    /// The mail used to open with the single word **What happened** and one blank line,
    /// which is a prompt for a paragraph rather than for a report — and what arrived was a
    /// paragraph: one sentence, no expectation, no session. The three labels below are the
    /// three follow-up mails that sentence always cost, asked once, in advance
    /// (Jan, 14 Sep 2026).
    ///
    /// The first one is deliberately **two questions in one line**: a rider with a feature
    /// wish must not have to decide whether the form is for him. See `FeedbackInvitation`.
    public enum Prompt {
        public static let what = "What happened, or what you would like:"
        public static let expected = "What you expected instead:"
        public static let session = "Which session (date, spot), if it is about one:"
    }

    /// The rule for the line between the rider's half of the mail and the phone's.
    ///
    /// **It exists to be readable, and to be deletable.** The facts under it are a phone
    /// model, an iOS version, a locale, a library shape and sometimes a spot — which is a
    /// map pin to where somebody rides. Nothing is sent until Send is tapped and every line
    /// is editable, but a rider only knows that if the mail says so, in the mail, at the
    /// point where the facts start.
    public enum Separator {
        /// Long enough to read as a rule at a mail client's default width, short enough not
        /// to wrap on a phone.
        public static let rule = String(repeating: "-", count: 40)
        public static let note =
            "Below is what the app knows about this phone and build. "
            + "It helps analysis; delete any line you would rather not send."
    }

    /// The prefilled body: three labelled blanks for the rider, then everything the phone
    /// knows, behind a rule that says what it is and that it may be deleted.
    ///
    /// **The rider's half is first and the facts are below it**, which is the opposite of
    /// how a machine would write it. A mail that opens with twenty lines of diagnostics
    /// makes the reporter scroll past his own report to write it, and half of them will
    /// give up and write one sentence into the subject instead.
    ///
    /// Each label is followed by **two lines** — one for the answer and one of air, so the
    /// three questions read as three fields rather than as a paragraph with colons in it.
    /// The session label is the one that can be answered for him: from the share sheet's
    /// "Report a problem with this session…" the app already knows which afternoon, so the
    /// date and the spot are written into the first of those two lines and the rider is
    /// asked one question fewer.
    public static func body(_ facts: FeedbackFacts) -> String {
        var out: [String] = []
        out += prompt(Prompt.what)
        out += prompt(Prompt.expected)
        out += prompt(Prompt.session, answer: facts.session.map(sessionAnswer))
        out.append(FeedbackInvitation.sentence)
        out.append("")
        out.append(Separator.rule)
        out.append(Separator.note)
        out.append("")
        out += section("App", lines: appLines(facts.app))
        out += section("Phone", lines: phoneLines(facts.phone))
        out += section("Watch", lines: watchLines(facts.watch))
        out += section("Library", lines: libraryLines(facts.library))
        if let session = facts.session {
            out += section("Session", lines: sessionLines(session))
        }
        out.append("sent from \(Branding.appName)")
        return out.joined(separator: "\n")
    }

    /// The last resort, and the fallback when Mail is not set up: the same subject and the
    /// same body, handed to whatever the system opens for `mailto:`.
    ///
    /// The escaping is done by hand rather than through `URLComponents.queryItems`, which
    /// percent-encodes with `urlQueryAllowed` — a set that contains `&`, `=`, `+` and `?`.
    /// A body carrying any of them (and a rider typing "3 jibes & 2 tacks" carries one)
    /// would be cut short at that character, or arrive with a `+` read back as a space.
    public static func mailtoURL(_ facts: FeedbackFacts) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed
            .subtracting(CharacterSet(charactersIn: "&=+?"))
        guard let subject = subject(facts).addingPercentEncoding(withAllowedCharacters: allowed),
              let body = body(facts).addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.percentEncodedQuery = "subject=\(subject)&body=\(body)"
        return components.url
    }

    // MARK: - Sections

    /// One labelled blank: the question, the line the answer goes on, and a line of air.
    ///
    /// `answer` fills the first of the two rather than adding a third line, so a prefilled
    /// field and an empty one are the same shape and the mail does not grow a ragged edge
    /// depending on where it was opened from.
    private static func prompt(_ label: String, answer: String? = nil) -> [String] {
        [label, answer ?? "", ""]
    }

    /// "30 August 2026 · Torbole" — the session line, written for him.
    ///
    /// Deliberately only the two facts the *question* asks for. Everything else about the
    /// session (duration, source class, engine stamp, the row id) is under the rule, in the
    /// Session block, where the rest of the diagnostics are — repeating it up here would put
    /// the machine's half back on top of the rider's.
    private static func sessionAnswer(_ session: FeedbackFacts.Session) -> String {
        guard let spot = session.spot, !spot.isEmpty else { return session.date }
        return session.date + " · " + spot
    }

    /// A heading, its facts indented two spaces, and a blank line after. Empty sections
    /// cannot happen — every one of the four always has at least one line.
    private static func section(_ title: String, lines: [String]) -> [String] {
        [title] + lines.map { "  " + $0 } + [""]
    }

    private static func appLines(_ app: FeedbackFacts.App) -> [String] {
        var lines = [
            "\(Branding.appName) \(app.version) (\(app.build))"
                + (app.isDev ? " · dev build (TUNING)" : " · public build"),
            "Analysis engine \(app.engineVersion)",
        ]
        if app.tunedThresholds > 0 {
            lines.append("Tuned thresholds: \(app.tunedThresholds) "
                         + "changed from the published defaults")
        }
        return lines
    }

    private static func phoneLines(_ phone: FeedbackFacts.Phone) -> [String] {
        [phone.described, phone.system, "Locale \(phone.locale)"]
    }

    private static func watchLines(_ watch: FeedbackFacts.Watch) -> [String] {
        var lines: [String] = []
        if let model = watch.garminModel {
            if let version = watch.garminAppVersion {
                lines.append("Garmin \(model) · \(Branding.appName) watch app \(version)")
            } else {
                lines.append("Garmin \(model) · watch app version unknown "
                             + "(no summary card has arrived yet)")
            }
        } else {
            lines.append("No Garmin watch chosen")
        }
        switch watch.appleWatchPaired {
        case true: lines.append("Apple Watch paired")
        case false: lines.append("No Apple Watch paired")
        case nil: break
        }
        lines.append("Health import " + (watch.healthImport ? "on" : "off"))
        return lines
    }

    private static func libraryLines(_ library: FeedbackFacts.Library) -> [String] {
        var lines = ["\(library.sessionCount) session"
                     + (library.sessionCount == 1 ? "" : "s")]
        if !library.sources.isEmpty {
            lines.append(library.sources
                .map { "\($0.label) \($0.count)" }
                .joined(separator: " · "))
        }
        return lines
    }

    private static func sessionLines(_ session: FeedbackFacts.Session) -> [String] {
        var first = session.date
        if let spot = session.spot, !spot.isEmpty { first += " · " + spot }
        var lines = [first]
        var second = "Source class \(session.sourceClass)"
        if let discipline = session.discipline, !discipline.isEmpty {
            second += " · " + discipline
        }
        second += " · " + session.duration
        lines.append(second)
        if let stamp = session.engineStamp {
            lines.append("Analysed by engine \(stamp)")
        }
        lines.append("Session id \(session.id)")
        return lines
    }
}
