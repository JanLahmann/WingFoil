import Foundation

/// **One basis for two front doors** (Jan, 28 September 2026): the iPhone app's *What
/// CleanJibe does* and the cleanjibe.org homepage are rendered from this one ordered list,
/// so the parts they share cannot drift apart.
///
/// Each section carries its own words and says where it is drawn:
///
/// - `.both` — the app and the homepage print the same words. The app reads them here; the
///   homepage reads `docs/copy/welcome.json`, which `WelcomeSectionsExportTests` writes from
///   this file and holds equal to it.
/// - `.app` — only the welcome screen draws it (the identity, *Get started*, the footer's
///   menu path).
/// - `.web` — only the homepage draws it (the hero, what each verdict means, the chooser,
///   old sessions, the watch app, trust). Its words live here anyway, so one file says
///   everything the two doors say, and one voice check reads them.
///
/// **The order is the order on both.** Each shell draws the sections it has, top to bottom
/// as listed. `web/tools/make_home.py` renders the homepage's blocks from the export and
/// writes `docs/web-parity/welcome-vs-homepage.md`, the list of differences, from
/// `surfaces`; its `--check` fails when either is stale, and when WelcomeView types a word a
/// shared section owns instead of reading it here.
///
/// **What stays out:** links. A section names its actions by id (`example`, `iphone`,
/// `garmin`…); each shell knows where its own ids go, because an App Store sheet and a web
/// address are not the same kind of thing.
///
/// Register 2 in the hero and the welcome's identity, register 1 everywhere else
/// (docs/voice.md). No dashes, no brackets, one thought a sentence.
public enum WelcomeSections {

    /// The sections, top to bottom.
    ///
    /// **Get started sits straight under the example** (rider review I10, 9 Oct 2026): the
    /// two ways on are one decision, *show me* or *bring mine in*, and with the glossary
    /// between them the second was a screen further down than the first.
    public static let all: [WelcomeSection] = [
        hero, identity, legend, example, getStarted, measures, verdicts,
        family, chooser, oldSessions, watchApp, trust, community, footerLinks,
    ]

    /// What the welcome screen draws, in order.
    public static var app: [WelcomeSection] { all.filter { $0.surfaces.app } }
    /// What the homepage draws, in order.
    public static var web: [WelcomeSection] { all.filter { $0.surfaces.web } }

    public static func section(_ id: WelcomeSection.ID) -> WelcomeSection {
        all.first { $0.id == id }!
    }

    // MARK: - The promise

    /// The homepage's hero: the promise, split where it asks its question, so the question
    /// is the headline and the answer is the paragraph under it. The promise itself is
    /// `WelcomeGuide.promise`, pinned to `docs/copy/phrases.json`; the page wraps both halves
    /// in one element so the pin still reads the whole sentence.
    static let hero = WelcomeSection(
        id: .hero, surfaces: .web,
        kicker: Branding.tagline,
        title: promiseHalves.question,
        lede: promiseHalves.answer,
        note: "It is free and needs no account. The example opens right here in your browser.",
        actions: [WelcomeAction(id: "chooser", title: "Which way in is yours?")])

    static var promiseHalves: (question: String, answer: String) {
        let promise = WelcomeGuide.promise
        guard let mark = promise.firstIndex(of: "?") else { return (promise, "") }
        let question = String(promise[...mark])
        let answer = promise[promise.index(after: mark)...]
            .trimmingCharacters(in: .whitespaces)
        return (question, answer)
    }

    /// The welcome's opening: the mark, the name, the tagline and one paragraph. The
    /// homepage opens on its hero instead, because a stranger arrives with a question.
    static let identity = WelcomeSection(
        id: .identity, surfaces: .app,
        title: Branding.tagline,
        lede: "CleanJibe shows your time on the foil, every flight and every touchdown. Each jibe "
            + "gets a verdict: flew through, touchdown, or fell in. You see your dry streak "
            + "and your fastest seconds. The replay comes with a commentary.")

    // MARK: - What you get

    /// The turn ladder's three marks, in the ladder's own words and order. The app draws them
    /// under its track motif, the homepage under the promise.
    static let legend = WelcomeSection(
        id: .legend, surfaces: .both,
        items: [
            WelcomeItem(id: "flew", term: "Flew through"),
            WelcomeItem(id: "touchdown", term: "Touchdown"),
            WelcomeItem(id: "fellIn", term: "Fell in"),
        ])

    /// The demo, and the card it makes. The title is the button: one tap fills every screen
    /// with a real session on the phone, and opens it in the browser app from the homepage.
    static let example = WelcomeSection(
        id: .example, surfaces: .both,
        title: "Try the example session",
        lede: "A real 10-minute session on Lake Garda.",
        note: "Every session gives you a card like this to share.")

    /// The four glossary lines a first-time reader needs before he has seen a session.
    /// **Selected from `MetricGlossary`, never retyped.** "GP3S" and "alpha 500" stay out:
    /// the Records topic teaches them to somebody who asked.
    static let measures = WelcomeSection(
        id: .measures, surfaces: .both,
        title: "What CleanJibe measures",
        items: glossary(["foilShare", "flights", "dryStreak", "speedRecords"]))

    /// What each verdict means, and the clean star. The welcome says the verdicts in its
    /// paragraph; the homepage has no paragraph, so it gives each one its line.
    static let verdicts = WelcomeSection(
        id: .verdicts, surfaces: .web,
        title: "Every turn, judged",
        items: glossary(["flewThrough", "touchdown", "fellIn", "clean"]))

    // MARK: - The ways in

    /// The welcome's way on: the title is the button that opens Getting started. The
    /// homepage has the chooser instead.
    static let getStarted = WelcomeSection(
        id: .getStarted, surfaces: .app,
        title: "Get started")

    /// The apps on one engine, each honest about what it does. `CleanJibeFamily` is the
    /// author (the browser app's copy of it is `docs/copy/app-shell.json`); this section
    /// reads it. The homepage draws these lines inside the chooser's cards.
    static let family = WelcomeSection(
        id: .family, surfaces: .both,
        title: CleanJibeFamily.title,
        lede: CleanJibeFamily.intro,
        items: CleanJibeFamily.apps.map {
            WelcomeItem(id: $0.id, term: $0.title, detail: $0.line, beta: $0.beta)
        })

    /// **Which way in is yours?** One card per rider's kit, each naming its apps (by the
    /// family's ids, so the card prints the family's own line for each) and its buttons.
    static let chooser = WelcomeSection(
        id: .chooser, surfaces: .web,
        title: "Which way in is yours?",
        note: "The iPhone app installs through Apple's TestFlight app. It is free, and there is "
            + "no invite to wait for.",
        items: [
            WelcomeItem(
                id: "garminIphone", term: "A Garmin and an iPhone",
                detail: "You get everything. Add the watch app for a verdict on your wrist "
                    + "after every jibe.",
                apps: ["iphone", "garmin"],
                actions: [WelcomeAction(id: "iphone", title: "Get the iPhone app"),
                          WelcomeAction(id: "garmin", title: "Put it on your watch")]),
            WelcomeItem(
                id: "garminOnly", term: "A Garmin, no iPhone",
                detail: "The browser app works on Android and on any computer. Your "
                    + "sessions stay in that browser.",
                apps: ["browser", "garmin"],
                actions: [WelcomeAction(id: "browser", title: "Try it in your browser"),
                          WelcomeAction(id: "garmin", title: "Put it on your watch")]),
            WelcomeItem(
                id: "appleWatch", term: "An Apple Watch",
                detail: "The watch app comes with the iPhone app. Apple's own Workout app "
                    + "works too, through Apple Health.",
                beta: true,
                apps: ["appleWatch"],
                actions: [WelcomeAction(id: "iphone", title: "Get the iPhone app")]),
            WelcomeItem(
                id: "otherWatch", term: "Another watch, or Strava",
                detail: "Strava comes in on the iPhone. A .fit file works in both apps.",
                apps: ["iphone", "browser"],
                actions: [WelcomeAction(id: "iphone", title: "Get the iPhone app"),
                          WelcomeAction(id: "browser", title: "Try it in your browser")]),
        ])

    /// The sessions a rider already has. Most arrive with years of them on Garmin Connect.
    static let oldSessions = WelcomeSection(
        id: .oldSessions, surfaces: .web,
        title: "Bring in the sessions you already have",
        lede: "Your last season is already on your watch account. Connect it once and "
            + "CleanJibe reads every session you rode.",
        items: [
            WelcomeItem(
                id: "profile", term: "Any Garmin profile",
                detail: "Windsurf, SUP, Kitesurf or Surfing all count. So does any activity "
                    + "you named wing or foil."),
            WelcomeItem(
                id: "icu", term: "Through intervals.icu",
                detail: "Garmin has no open API, so the free intervals.icu is the bridge. "
                    + "Two years of sessions come across."),
            WelcomeItem(
                id: "file", term: "Or one file at a time",
                detail: "Drop a .fit, .gpx or .tcx into the browser app. It is read on your "
                    + "device and never uploaded."),
        ],
        actions: [WelcomeAction(id: "guideGarmin", title: "Show me how")])

    /// Then the watch app, for the rider who wants more than his profile records.
    static let watchApp = WelcomeSection(
        id: .watchApp, surfaces: .web,
        title: "Get much more with the watch app",
        lede: "The free CleanJibe app for Garmin records a wingfoil session the way we "
            + "read one.",
        note: "It runs on {garmin-count} Garmin watches, from the fenix 8 down to the vívoactive.",
        items: [
            WelcomeItem(
                id: "wrist", term: "Verdicts on your wrist",
                detail: "The watch buzzes after every jibe, so you know how it went before "
                    + "you look."),
            WelcomeItem(
                id: "pump", term: "Pump strokes and takeoffs",
                detail: "It records your wrist as well, so every pump stroke and every "
                    + "takeoff attempt is counted."),
            WelcomeItem(
                id: "live", term: "Live on the water",
                detail: "Foil time, flights and your dry streak while you ride. A summary "
                    + "comes up when you save."),
        ],
        actions: [WelcomeAction(id: "garmin", title: "Put it on your watch"),
                  WelcomeAction(id: "watches", title: "Which watches")])

    // MARK: - Who builds it

    /// Why a rider can trust a stranger's app with his sessions.
    static let trust = WelcomeSection(
        id: .trust, surfaces: .web,
        title: "We ride too",
        items: [
            WelcomeItem(
                id: "account", term: "No account",
                detail: "You sign up for nothing, here or in the apps."),
            WelcomeItem(
                id: "server", term: "No server",
                detail: "Your sessions stay on your phone or in your browser. We only see one "
                    + "if you send it to us."),
            WelcomeItem(
                id: "open", term: "Open source",
                detail: "The engine is on GitHub. Every threshold behind a verdict can be "
                    + "read there."),
            WelcomeItem(
                id: "mail", term: "We read every mail",
                detail: "We build CleanJibe and we wingfoil. Tell us which verdict looked "
                    + "wrong, or what you want next."),
        ],
        actions: [WelcomeAction(id: "mail", title: "Tell us what you want next"),
                  WelcomeAction(id: "github", title: "Read the code")])

    /// **Built with its riders** (F2j): the one sentence both doors close on.
    static let community = WelcomeSection(
        id: .community, surfaces: .both,
        lede: FeedbackInvitation.community)

    /// The welcome footer's second sentence, which names the app's own menu. `lede` is the
    /// release's, `note` the beta's and the dev build's, where the reader is in the beta.
    static let footerLinks = WelcomeSection(
        id: .footerLinks, surfaces: .app,
        lede: "Join the beta or send ideas via Menu → Support & ideas.",
        note: "Send ideas via Menu → Support & ideas.")

    /// Glossary rows as items, term and line, in the order given.
    static func glossary(_ ids: [String]) -> [WelcomeItem] {
        ids.map {
            let entry = MetricGlossary.entry($0)
            return WelcomeItem(id: $0, term: entry.term, detail: entry.line)
        }
    }
}

/// Where a section is drawn.
public enum WelcomeSurface: String, Sendable, Equatable {
    case app, web, both
    public var app: Bool { self != .web }
    public var web: Bool { self != .app }
}

/// One section of the two front doors.
public struct WelcomeSection: Sendable, Equatable, Identifiable {
    public enum ID: String, Sendable, CaseIterable {
        case hero, identity, legend, example, measures, verdicts, getStarted, family,
             chooser, oldSessions, watchApp, trust, community, footerLinks
    }
    public let id: ID
    public let surfaces: WelcomeSurface
    /// A short line over the title: the tagline, on the hero.
    public let kicker: String
    public let title: String
    public let lede: String
    /// A line under the section: a caption, a condition, a count.
    public let note: String
    public let items: [WelcomeItem]
    public let actions: [WelcomeAction]

    public init(id: ID, surfaces: WelcomeSurface, kicker: String = "", title: String = "",
                lede: String = "", note: String = "", items: [WelcomeItem] = [],
                actions: [WelcomeAction] = []) {
        self.id = id
        self.surfaces = surfaces
        self.kicker = kicker
        self.title = title
        self.lede = lede
        self.note = note
        self.items = items
        self.actions = actions
    }

    /// Every word the section carries, in reading order: what "the same words" means.
    public var words: [String] {
        ([kicker, title, lede]
         + items.flatMap { [$0.term, $0.detail] + $0.actions.map(\.title) }
         + [note] + actions.map(\.title))
            .filter { !$0.isEmpty }
    }
}

/// One line of a section: a term and what it means, or a chooser card.
public struct WelcomeItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let term: String
    public let detail: String
    /// In the beta, not yet in the App Store release (docs/channels.md).
    public let beta: Bool
    /// A chooser card's apps, by `CleanJibeFamily.App.id`.
    public let apps: [String]
    public let actions: [WelcomeAction]

    public init(id: String, term: String, detail: String = "", beta: Bool = false,
                apps: [String] = [], actions: [WelcomeAction] = []) {
        self.id = id
        self.term = term
        self.detail = detail
        self.beta = beta
        self.apps = apps
        self.actions = actions
    }
}

/// A button, named by what it does. Each shell maps the id to its own destination.
public struct WelcomeAction: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}
