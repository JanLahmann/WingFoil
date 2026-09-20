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
        /// nil when the question could not be asked at all (`WCSession` unsupported), and
        /// in a channel that has no door for the answer — see `healthImport`.
        public let appleWatchPaired: Bool?
        /// Settings → Apple Health → "Import new Health workouts automatically".
        ///
        /// **nil where the door does not exist.** Health and the Apple Watch app are beta
        /// doors (docs/channels.md), so an App Store report that printed "Health import
        /// off" and "No Apple Watch paired" would be answering two questions the app it
        /// came from never asks. A nil fact is left out of the report entirely.
        public let healthImport: Bool?
        /// How many runs of the Garmin watch app never reached `onStop`, as the newest
        /// summary card reported it (`SessionRow.watchCrashes`). nil when no card has ever
        /// carried the number: a watch older than 0.9.14-dev6, or none at all.
        ///
        /// **It is printed with the crashes, not with the watch**, because that is where a
        /// reader is already asking the question. Connect IQ has no crash reporting, so
        /// until this line existed the count was readable on the wrist and nowhere else.
        public let garminCrashRuns: Int?

        public init(garminModel: String?, garminAppVersion: String?,
                    appleWatchPaired: Bool?, healthImport: Bool?,
                    garminCrashRuns: Int? = nil) {
            self.garminModel = garminModel
            self.garminAppVersion = garminAppVersion
            self.appleWatchPaired = appleWatchPaired
            self.healthImport = healthImport
            self.garminCrashRuns = garminCrashRuns
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
    /// What iOS reported to this app since it was installed (`CrashDigest`), newest first.
    ///
    /// **Every channel, the App Store one included.** A crash is the one failure a rider
    /// cannot describe and cannot route: TestFlight's own beta feedback does not carry the
    /// log, and an App Store rider has no route at all except a mail. Nothing here is
    /// personal — a binary name, an offset, a signal and a build number — and it is printed
    /// under the same rule as everything else, which says it may be deleted.
    public let crashes: [CrashDigest]

    public init(app: App, phone: Phone, watch: Watch, library: Library,
                session: Session? = nil, crashes: [CrashDigest] = []) {
        self.app = app
        self.phone = phone
        self.watch = watch
        self.library = library
        self.session = session
        self.crashes = crashes
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

/// **The doors to that mail, each named exactly as the rider finds it.**
///
/// There were five spellings of one door on 15 September 2026 — *Support & ideas*,
/// *Menu → Support*, *Settings → Send feedback*, *Something off? Send feedback*,
/// *Send feedback* — across the app's own Help, four website pages and the two store
/// texts. One of them, `Settings → Send feedback`, named a row **deleted in build 58**
/// (`SettingsView`'s own comment records the deletion), and the app's Help told the rider
/// to go there. A rider who follows a door name finds a screen or he does not; there is no
/// third outcome, so the names are written once here and every surface quotes them.
///
/// `docs/copy/feedback.json → doors` is this list, and `CopyContractTests` pins it, so the
/// website and the store texts are held to the same five names from the other side.
///
/// **These are names of doors that exist.** A door this build does not have is not in the
/// list; `feature` and `testflight` are beta doors and the App Store description names
/// neither (docs/channels.md).
public enum FeedbackDoors {

    /// The label on the library menu's row itself. "& ideas" is not decoration: the row
    /// said "Support", which a rider reads as *the place you go when something is broken*.
    public static let menuRow = "Support & ideas"

    /// The way there, which is how every other surface has to name it — the app's Help,
    /// the website's footers and the App Store description all say the route, not the row.
    public static let app = "Menu → " + menuRow

    /// The offer under every page (`FeedbackMailRow`). It says *or an idea* for the reason
    /// the menu row says *& ideas*: a door named only for faults collects only faults.
    public static let footer = "Something off, or an idea? Send feedback"

    /// The share sheet's own row, which is the only one that already knows which afternoon
    /// the report is about and attaches that session's card.
    public static let share = "Report a problem with this session…"

    /// Apple's label, not CleanJibe's: a screenshot taken inside a TestFlight build offers
    /// it, and it carries the screenshot and the device logs — the route for a crash.
    public static let testflight = "Send Beta Feedback"

    /// The address itself, for a reader who has no app in front of him — the website's
    /// footers and the two store listings.
    public static let web = FeedbackReport.recipient

    /// Every door, in the order a rider meets them. `id` is the key in
    /// `docs/copy/feedback.json → doors`.
    public static let all: [(id: String, name: String)] = [
        ("app", app), ("footer", footer), ("share", share),
        ("testflight", testflight), ("web", web),
    ]
}

/// The feedback mail, as text.
///
/// Pure: a subject, a body and a `mailto:` URL out of a `FeedbackFacts`, with no framework
/// and no side effect. The app hands the first two to `MFMailComposeViewController` and
/// falls back to the third when the phone has no mail account set up.
public enum FeedbackReport {

    /// Where feedback goes. One address, not a GitHub issue: the repository is public
    /// and a bug report carries a build number, a phone model and sometimes a session's
    /// spot, which is a map pin to where the reporter rides.
    public static let recipient = "info@cleanjibe.org"

    /// "CleanJibe feedback · build 17 dev · fenix 8".
    ///
    /// The build number rather than the marketing version, because the two TestFlight
    /// variants of a release share a marketing version and differ only here; the watch
    /// because a mailbox sorted by subject then groups the reports that are about one.
    ///
    /// **It does not say "beta".** The same kit builds the App Store app, and a rider who
    /// bought nothing and joined nothing must not find his own mail calling the app he is
    /// holding a test (docs/channels.md). The build number says which channel it is to
    /// anybody who needs to know, and the facts block under the rule says it in words.
    public static func subject(_ facts: FeedbackFacts) -> String {
        let build = facts.app.build + (facts.app.isDev ? " dev" : "")
        return Branding.appName + " feedback · build " + build + " · "
            + facts.watch.subjectName
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
        public static let session = "Which session, its date and spot, if it is "
            + "about one:"
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
            + "It helps analysis. " + Copy.deleteAnyLine
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
        // The heading appears for either half: a phone that has crashed, a watch that has
        // said how often it has. A dev phone that never crashed is the common case for the
        // watch line, and a block that only opened for the phone would have hidden it.
        if !facts.crashes.isEmpty || facts.watch.garminCrashRuns != nil {
            out += section(crashHeading,
                           lines: crashLines(facts.crashes,
                                             watchRuns: facts.watch.garminCrashRuns,
                                             build: facts.app.build))
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
                + (app.isDev ? " · dev build, TUNING on" : " · public build"),
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
                lines.append("Garmin " + model + " · " + Branding.appName
                             + " watch app " + version)
            } else {
                lines.append("Garmin " + model + " · watch app version unknown, "
                             + "no summary card has arrived yet")
            }
        } else {
            lines.append("No Garmin watch chosen")
        }
        switch watch.appleWatchPaired {
        case true: lines.append("Apple Watch paired")
        case false: lines.append("No Apple Watch paired")
        case nil: break
        }
        // nil is a fact the channel has no door for, so it is left out rather than
        // answered — see `FeedbackFacts.Watch.healthImport`.
        if let health = watch.healthImport {
            lines.append("Health import " + (health ? "on" : "off"))
        }
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

    // MARK: - Recent crashes

    /// The heading a reader scans for. Named for what happened rather than for the
    /// framework that reported it: nobody is looking for "MetricKit diagnostics".
    static let crashHeading = "Recent crashes"

    /// Where the block came from, said at the top of it. A rider who finds a list of
    /// crashes in his own mail is owed the fact that no reporting SDK put it there.
    static let crashNote = "iOS collected these on this phone."

    /// The block: where it came from, how many of each, then the newest few by name — and
    /// the watch's own tally under them, when a card has carried one.
    ///
    /// **Capped at `CrashLog.listCount` lines of crash**, so the block is at most eleven
    /// lines however bad a fortnight the phone has had. The mail is a rider's report with a
    /// fact sheet under it, and a fact sheet that runs longer than the report stops being
    /// read at all.
    ///
    /// - Parameters:
    ///   - watchRuns: the Garmin watch app's own count of runs that never reached `onStop`,
    ///     or nil for "no card has ever said". Last, and one line: the phone's crashes carry
    ///     a stamp and a frame each, the watch's carry a number and nothing else.
    ///   - build: the build the mail is being written from, so a crash on an older one can
    ///     say so. A tester who has updated since is often reporting something already fixed.
    ///   - zone: the phone's, in every real call. A crash stamp is a machine fact, printed
    ///     in a fixed format for the same reason the engine version is.
    static func crashLines(_ crashes: [CrashDigest], watchRuns: Int? = nil, build: String,
                           zone: TimeZone = .current) -> [String] {
        var lines: [String] = []
        if !crashes.isEmpty {
            lines = [crashNote, crashCounts(crashes)]
            lines += crashes.prefix(CrashLog.listCount).map {
                crashLine($0, build: build, zone: zone)
            }
            let rest = crashes.count - CrashLog.listCount
            if rest > 0 { lines.append(String(rest) + " older, not listed") }
        }
        if let watchRuns { lines.append(watchCrashLine(watchRuns)) }
        return lines
    }

    /// "Watch app: 3 runs ended without a save", and "Watch app: no crashes reported" for a
    /// watch that has lost none.
    ///
    /// **A zero is printed here**, against the rule the rest of this block follows, because
    /// the watch is the one thing in the report that can only answer through a card: a
    /// missing line already means "no card said", and it would be read as "no crashes" the
    /// moment both looked the same. What it counts is said in the rider's own terms — a run
    /// of the watch app that ended without saving a session — rather than as an exception.
    private static func watchCrashLine(_ runs: Int) -> String {
        guard runs > 0 else { return "Watch app: no crashes reported" }
        return "Watch app: " + String(runs) + (runs == 1 ? " run" : " runs")
            + " ended without a save"
    }

    /// "Crashes 2 · Hangs 1" — the same shape the Library block counts its doors in, and a
    /// kind with none is left out for the same reason a zero is: an absent line reads as
    /// nothing unusual.
    private static func crashCounts(_ crashes: [CrashDigest]) -> String {
        CrashDigest.Kind.allCases
            .compactMap { kind -> String? in
                let count = crashes.filter { $0.kind == kind }.count
                return count > 0 ? kind.plural + " " + String(count) : nil
            }
            .joined(separator: " · ")
    }

    /// "2026-09-14 15:05 · Crash · Namespace SIGNAL, Code 11 · WingFoil +0x1b2c3".
    private static func crashLine(_ crash: CrashDigest, build: String,
                                  zone: TimeZone) -> String {
        var parts = [stamp(crash.date, zone: zone), crash.kind.label]
        if let reason = crash.reason, !reason.isEmpty { parts.append(reason) }
        if let frame = crash.topFrame, !frame.isEmpty { parts.append(frame) }
        if let was = crash.build, was != build { parts.append("build " + was) }
        return parts.joined(separator: " · ")
    }

    /// A fixed format in a fixed locale, in the phone's own zone: the crash happened on
    /// this phone, and the reader is looking for an ordering rather than for an afternoon.
    private static func stamp(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
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
            lines.append("Analysed by engine " + stamp)
        }
        lines.append("Session id \(session.id)")
        return lines
    }
}
