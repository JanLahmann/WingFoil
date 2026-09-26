import Foundation

/// Plain-language explanations of every number the app shows.
///
/// The content lives here, in the kit, rather than in the SwiftUI layer for two reasons:
/// it is pure data (so the test suite can assert every topic is actually written), and the
/// detail cards deep-link into it by *identifier* — `HelpTopicID` is an enum, so a card
/// can never point at a topic that does not exist, and a new topic can never ship empty.
///
/// The wording is derived from docs/algorithms.md; where a threshold is quoted it is the
/// documented default, and the topic says so rather than pretending the number is a law.
public struct HelpTopic: Sendable, Identifiable, Equatable {

    /// Term/detail pairs — the outcome ladders read far better as a list than as prose.
    public struct Item: Sendable, Equatable {
        public let term: String
        public let detail: String
        /// The topic this item is the signpost for, drawn as a link on its term. Getting
        /// started's ways in carry one each, which is why that topic needs no "see also":
        /// every row already goes where a chevron would (26 September 2026).
        public let link: HelpTopicID?

        public init(term: String, detail: String, link: HelpTopicID? = nil) {
            self.term = term
            self.detail = detail
            self.link = link
        }
    }

    public let id: HelpTopicID
    public let section: HelpSection
    /// The sub-heading inside "Read the numbers" the topic sits under; nil elsewhere, and
    /// nil for the two topics that open the section (the glossary and the map).
    public let subsection: HelpSubsection?
    /// **The lowest channel that actually has the door this topic describes**
    /// (docs/channels.md). `.release` — the default, and almost every topic — means the
    /// App Store build can do the thing being explained; `.beta` and `.dev` mean it cannot,
    /// and the topic is off the index, out of the search and out of every "see also" in
    /// the channels below it.
    ///
    /// It lives on the topic rather than in the app because the catalogue is the place the
    /// sentence is written, and a channel-bound sentence that is filed anywhere else is a
    /// sentence that will be edited without its gate. The kit cannot see `#if BETA`, so the
    /// app hands its own channel in (`HelpCatalog.indexTopics(channel:)`).
    public let channel: HelpChannel
    public let title: String
    /// One line, shown in the index and under the card's `?`.
    public let summary: String
    public let body: [String]
    public let items: [Item]
    /// A screenshot of the screen this topic describes, shown between the summary and the
    /// prose. Nil on every definitional topic on purpose — see `HelpImage`.
    public let image: HelpImage?
    /// Outbound links the topic offers (intervals.icu, so far).
    public let links: [HelpLink]
    /// An in-app destination the topic can send the reader to. Data rather than a
    /// hard-coded `if id == …` in the sheet, so the test suite can assert the setup
    /// topic actually offers its shortcut.
    public let action: HelpAction?
    /// Topics worth reading next; every id here must resolve (asserted in the tests).
    public let related: [HelpTopicID]

    /// The same topic with another set of items.
    ///
    /// **The one seam a channel-dependent topic needs.** A body cannot branch by channel
    /// and neither can a `let` in a static array, so the topic whose *items are the routes*
    /// — Getting started — is declared once with the release's routes and rebuilt through
    /// here by `HelpCatalog.topic(_:channel:)` when a beta or dev build asks. Nothing else
    /// about the topic moves, which is the point: the title, the summary, the body and the
    /// `related` list are the same sentences in every build.
    public func withItems(_ items: [Item]) -> HelpTopic {
        HelpTopic(id: id, section: section, subsection: subsection, channel: channel,
                  title: title, summary: summary, body: body, items: items, image: image,
                  links: links, action: action, related: related)
    }

    public init(id: HelpTopicID, section: HelpSection, subsection: HelpSubsection? = nil,
                channel: HelpChannel = .release,
                title: String, summary: String,
                body: [String], items: [Item] = [], image: HelpImage? = nil,
                links: [HelpLink] = [], action: HelpAction? = nil,
                related: [HelpTopicID] = []) {
        self.id = id
        self.section = section
        self.subsection = subsection
        self.channel = channel
        self.title = title
        self.summary = summary
        self.body = body
        self.items = items
        self.image = image
        self.links = links
        self.action = action
        self.related = related
    }
}

/// A picture of the screen a topic describes, and the one line that says what to look at.
///
/// Only the **asset name** lives here. The kit has no bundle of images of its own and the
/// catalogue is deliberately pure data, so the picture is looked up by name in the app's
/// asset catalogue (`ios/WingFoil/Resources/Assets.xcassets/Help/`) at render time. A
/// misspelt name would therefore draw nothing at all and nobody would notice, which is why
/// `PresentationTests` asserts every name in this file against the image sets actually
/// checked in.
///
/// Only topics that describe a **screen** carry one. A definition — what a flight is, what
/// a dry streak is — gets no picture, because a screenshot of a number does not explain
/// what the number means, and a decorative image in a reference work is a tax on every
/// reader who came for the sentence.
public struct HelpImage: Sendable, Equatable {
    /// The image set's name in the app's asset catalogue, without an extension.
    public let asset: String
    /// One line under the picture. Says what to look at, not what the picture is of.
    public let caption: String

    public init(asset: String, caption: String) {
        self.asset = asset
        self.caption = caption
    }
}

/// A labelled outbound URL. Shared by the help topics and the onboarding card so a link
/// is written once and rendered by both.
public struct HelpLink: Sendable, Equatable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

/// An in-app destination a help topic can offer as a button.
public enum HelpAction: String, Sendable, Equatable {
    /// Opens CleanJibe's own Settings screen, scrolled to the intervals.icu section.
    case openIcuSettings
    /// Imports the bundled example session (`ExampleSession`) — the same button the
    /// empty-library setup card offers, so Help is not a dead end for a first-time reader.
    case loadExampleSession
    /// Opens the feedback mail — the same composer as Menu → Support & ideas
    /// (`FeedbackDoors.app`), from the page that explains it.
    ///
    /// Jan, dev 65: a page about sending feedback that only *describes* three doors is a
    /// page the reader has to leave to use. The topic names the doors because they are what
    /// he will use next time; the button is the door he is standing in front of now.
    case sendFeedback
    /// Opens the **What's new** screen — the release notes the kit carries in `WhatsNew`,
    /// filtered by the channel the app is running.
    ///
    /// An action rather than a list of `items:`, because a release note is a paragraph of
    /// its own shape — a version, a day, and the lines of that build — and a help item is a
    /// term and a detail inside a 30-word budget. The topic says what the screen is; the
    /// screen is the notes.
    case openWhatsNew
}

/// **Which build is reading the catalogue** — the kit's half of docs/channels.md.
///
/// The kit compiles everything in every channel, so it cannot see `#if BETA` and must not
/// try: the app knows which build it is and hands this value in. The order is the order the
/// channels nest in — dev has everything the beta has, the beta everything the release has —
/// so "this channel may read that topic" is one comparison and not a table.
public enum HelpChannel: Int, Sendable, Comparable, CaseIterable, Identifiable {
    /// The App Store build: no compile flags. The strictest reader.
    case release = 0
    /// TestFlight, `BETA` defined.
    case beta = 1
    /// `BETA DEV TUNING`, a handful of hand-picked testers.
    case dev = 2

    public var id: Int { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Whether a build on this channel has the door a topic on `required` describes.
    public func has(_ required: HelpChannel) -> Bool { self >= required }
}

/// Where a topic sits in the Help index.
///
/// **Seven sections, in the order a rider meets them** (Jan, 26 September 2026, approving
/// docs/proposals/2026-09-25-help-structure.md): install, ride, bring it in, read the
/// numbers, share, keep the library, fix a problem. There were ten until then, one of them
/// holding a third of the catalogue under a title that mixed four jobs, and two holding one
/// topic each.
public enum HelpSection: String, CaseIterable, Sendable, Identifiable {
    /// *Start here*, first on purpose: it is what "I just installed this" is looking for.
    case start
    case record, bringIn, readNumbers, share, library, somethingWrong

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .start: "Start here"
        case .record: "Record a session"
        case .bringIn: "Bring it in"
        case .readNumbers: "Read the numbers"
        case .share: "Share"
        case .library: "Your library"
        case .somethingWrong: "Something wrong?"
        }
    }

    public var symbol: String {
        switch self {
        case .start: "book"
        case .record: "record.circle"
        case .bringIn: "square.and.arrow.down"
        case .readNumbers: "chart.bar"
        case .share: "square.and.arrow.up"
        case .library: "books.vertical"
        case .somethingWrong: "wrench.and.screwdriver"
        }
    }
}

/// **The sub-headings inside "Read the numbers"**, the one section over eight topics.
///
/// The old sections survive as the headings a reader scans (On the foil, Records, Turns,
/// Takeoff, Effort & wind), so "Effort" and "Conditions" stop being one-topic sections and
/// the long section still reads in parts. A topic outside "Read the numbers" has none.
public enum HelpSubsection: String, CaseIterable, Sendable, Identifiable {
    case foil, records, turns, takeoff, effortWind

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .foil: "On the foil"
        case .records: "Records"
        case .turns: "Turns"
        case .takeoff: "Takeoff"
        case .effortWind: "Effort & wind"
        }
    }

    public var symbol: String {
        switch self {
        case .foil: RowMetric.foilShare.icon
        case .records: "speedometer"
        case .turns: "arrow.triangle.turn.up.right.diamond"
        case .takeoff: "arrow.up.right"
        case .effortWind: "wind"
        }
    }
}

/// Every explainable metric, as an enum so a `?` button cannot point at a missing topic.
///
/// **Six ids went in the merge of 26 September 2026**, and each one still answers as a
/// string (`HelpCatalog.redirects`): *foilPct*, *longestFlight* and *distance* open
/// Flights and foil time, *touchdowns* opens Turn outcomes, *icuPrivacy* opens What leaves
/// your phone, *sourceClass* opens Which watches work. The Swift cases are gone rather than
/// kept as aliases, for the reason the speed windows gave: a `?` that still compiles
/// against a merged id is a `?` nobody re-reads. A written-down link — a URL, a web anchor,
/// a `UI_HELP_TOPIC` — keeps working.
public enum HelpTopicID: String, CaseIterable, Sendable, Identifiable {
    case gettingStarted
    /// **What the numbers mean** — the glossary, rendered rather than written.
    case numbers
    /// New sessions announcing themselves while the phone is idle.
    case notifications
    /// The release notes, in the app at last. Off the index since 26 September 2026: the
    /// menu opens the screen itself, and the topic is only a button onto it.
    case whatsNew
    case icuSetup, exampleSession, sendingFeedback, appleWatchApp, appleWorkoutApp
    case icuTroubleshooting
    case privacy, libraryBackup
    case stravaImport, shareFromWatchApp, whichWatch, phoneOnly
    /// The Connect IQ store queues an update and never installs it — the one Garmin
    /// failure the phone cannot see and cannot fix, so it is written down instead.
    case watchUpdateStuck
    /// The browser app, and the answer to "is there an Android app".
    case browserApp
    case flights, mapLegend
    // **One page for the whole set** (Jan, dev 65: *"do we really need separate pages to
    // describe each distance?"*). It was eight ids — the set, six windows and the
    // uncertified mark — each a topic of two sentences, which is a table of contents
    // wearing chevrons. The windows are items on one topic now; the ids are gone rather
    // than kept as aliases, because a `?` that still compiles against `.best2s` is a `?`
    // nobody notices is pointing at a page that no longer exists.
    case speedRecords
    /// Settings → Speed records: which records a track with no speed channel may hold.
    case verifiedRecords
    case turnTypes, turnOutcomes, turnSuccess, portStarboard, falls, glideOuts
    case takeoffAttempts, pumpsToTakeoff, pumpStrokes
    case heartRate
    case windAxis
    case shareCard, replayClip, shareFit, riderAttribution
    /// The Share page's beta door: this session's recording, to the developer, by mail.
    case sendSessionToDeveloper
    case divergence, engineVersion, windsurf

    public var id: String { rawValue }
}

public enum HelpCatalog {

    /// Every topic, in reading order. `topics` is the single source; the lookups below
    /// are derived from it, so a topic cannot exist in one and not the other.
    public static let topics: [HelpTopic] = [

        // MARK: Start here
        //
        // First in the catalogue because it is first on the index, and first on the index
        // because it is what "I just installed this" is looking for — the library menu's own
        // first row opens it by name.
        //
        // **The steps live here, not on the web.** They used to be handed to
        // cleanjibe.org/start; Jan, 15 September 2026: a rider who has just installed the
        // app must not be sent to a browser for the instructions. The site is the mirror,
        // and since 25 September 2026 the topic no longer names it.
        //
        // **And it really is the same guide, since 15 September 2026.** Both are cut from
        // `docs/guide/getting-started.json` by `web/tools/make_start.py`, through the
        // generated `GettingStartedGuide`: the items are its routes and notes, and the web
        // page adds the numbered steps the app has no room for. `GettingStartedGuideTests`
        // fails if this topic stops matching it.
        //
        // **One line per way in, each a link** (26 September 2026, the approved help
        // structure). The routes are the items, and each item's term opens the topic that
        // owns the steps (`gettingStartedItems(for:)`), so the "see also" list that named the
        // same eight topics again is gone. The guide's framing sentence went with it: *what
        // a verdict is* is What CleanJibe does, one row below this one in the menu.
        //
        // **The items below are the release's list, and every other channel's is built from
        // it** (`HelpCatalog.topic(_:channel:)` → `resolved(_:channel:)`). The two Apple
        // routes are beta doors (docs/channels.md); a `let` in a static array cannot ask
        // which build is reading it, so the declaration takes the strictest reader's list
        // and the lookup rebuilds it for the channel the app hands in.
        HelpTopic(
            id: .gettingStarted, section: .start,
            title: "Getting started",
            summary: GettingStartedGuide.topicSummary,
            // Which watches, how a Garmin session gets in, the file way. The four
            // intervals.icu steps live in Settings; the button under the routes goes there.
            body: GettingStartedGuide.appParagraphs,
            items: gettingStartedItems(for: .release),
            // No link to cleanjibe.org/start any more (F5d, 25 September 2026): the app is
            // self-contained, and the page a rider is reading *is* the guide.
            action: .openIcuSettings),

        // **One table, so "will my watch work" has one place to be answered** — and since
        // 26 September 2026 it is also *what your recording can show*: the two topics
        // answered the same question in two shapes, one by brand and one by class. The rows
        // are by watch, because that is what a rider knows about his own setup, and each
        // row names its class in the spelling the Import screen and the session log print.
        // The letters a/b/c survive in the code (`SessionRow.sourceClass`); on screen they
        // are always the letter *and* the thing (`RecordingClass.name`).
        HelpTopic(
            id: .whichWatch, section: .start, title: "Which watches work with CleanJibe",
            summary: "Every watch works, one way or another. Each row says what yours "
                + "can show.",
            body: [
                "CleanJibe reads a recording, not a brand. Anything that records a GPS track "
                + "works. A number your file cannot support is left blank, never guessed.",
                "Two things separate the rows. **Certified speed** means the file holds your "
                + "watch's own speed. Without it, speed is worked out from positions, and "
                + "every record is marked uncertified.",
                "**Pump strokes and takeoff attempts** need a wrist accelerometer recorded "
                + "during the session. Only the CleanJibe watch apps record one.",
                "Each row names its class, the way the Import screen and the session log "
                + "print it.",
            ],
            items: [
                .init(term: "Garmin, with the CleanJibe watch app",
                      detail: RecordingClass.a.footerLine),
                .init(term: "Garmin, with Garmin's own profile or another app",
                      detail: RecordingClass.b.footerLine
                          + " Sessions come in through intervals.icu."),
                .init(term: "Apple Watch, with Apple's Workout app",
                      detail: "Bring it in through Strava or intervals.icu. In the beta, "
                          + "Apple Health hands it over as " + RecordingClass.b.name + "."),
                .init(term: "Apple Watch, with the CleanJibe watch app",
                      detail: RecordingClass.bPlus.name + ", in the beta. Everything "
                          + "Class B gets, plus pump strokes and takeoff attempts from your "
                          + "wrist."),
                .init(term: "Polar, Suunto, COROS and the rest",
                      detail: "Connect the watch to intervals.icu, or share one session in "
                          + "as a FIT, which certifies its records. A .gpx is "
                          + RecordingClass.c.name + "."),
                .init(term: "Anything that ends up on Strava",
                      detail: "Connect Strava and pick the sessions. Strava hands over "
                          + "positions, altitude and heart rate but no speed channel. That "
                          + "makes it " + RecordingClass.c.name + "."),
                .init(term: "A phone in a pouch, or no watch at all",
                      detail: "Any GPS-logging app works. Record, then bring it in through "
                          + "Strava or share the file. It is " + RecordingClass.c.name
                          + ", and the flights, turns and map are there."),
            ],
            related: [.shareFromWatchApp, .appleWatchApp, .stravaImport]),

        HelpTopic(
            id: .exampleSession, section: .start, title: "Look around with the example session",
            summary: "One real session ships with the app. Load it before you connect anything.",
            body: [
                ExampleSession.blurb,
                "It is not your data. CleanJibe marks it EXAMPLE in the list and on its "
                + "own page. It stays out of Records, Trends and your gear totals.",
                "Delete it with a swipe. You can load it again from here.",
                "We recorded it at " + ExampleSession.place + " with the CleanJibe watch "
                + "app and removed everything that identifies the rider. We left the "
                + "accelerometer out, because it is bigger than the whole app.",
                "So pump strokes and takeoff effort show as unavailable.",
            ],
            image: HelpImage(asset: "help-session-detail",
                             caption: "The four rows at the top answer \"was that a good "
                                 + "session\"."),
            action: .loadExampleSession,
            // One next step, not four (26 September 2026): after the example, the rider's
            // own sessions.
            related: [.icuSetup]),

        // MARK: Record a session
        //
        // The two Apple doors, in the channel that has them (docs/channels.md), and the
        // phone in a pouch. For a rider with no Garmin they are the whole way in.
        HelpTopic(
            id: .appleWatchApp, section: .record, channel: .beta,
            title: "Recording with the CleanJibe Apple Watch app",
            summary: "Record on your Apple Watch. " + Copy.watchSessionArrives,
            body: [
                "The watch app records the GPS track, your heart rate and the wrist "
                + "accelerometer at 50 Hz. Start it on the watch, ride, and end the workout. "
                + "The session moves to the phone while both are in range.",
                "Because the wrist is recorded, pump strokes and failed takeoff attempts "
                + "are analysed on the phone. The speed is the watch's own, so the records "
                + "certify.",
            ],
            items: [
                // Jan, 15 Sep 2026: it said "keep the wrist above water" — wrong, a wrist
                // under water IS the swim evidence (docs/algorithms.md, `turnBaroDrop`).
                .init(term: "The wrist may go under",
                      detail: "When your wrist goes under, the watch's pressure sensor "
                          + "notices, and that counts as a fall. The gap in the GPS track is "
                          + "marked, not filled in."),
                .init(term: "Let the workout finish",
                      detail: "The watch sends the session once you end the workout. If it is "
                          + "not in the list yet, look again in a minute."),
            ],
            related: [.appleWorkoutApp, .whichWatch]),

        HelpTopic(
            id: .appleWorkoutApp, section: .record, channel: .beta,
            title: "Recording with the Apple Workout app",
            summary: "No Garmin, no extra app: record on your Apple Watch and import from "
                + "Health.",
            body: [
                "Record a session with Apple's own Workout app and analyse it here. You "
                + "need no Garmin, no account and no cable.",
                "Health has no wingfoil workout type. CleanJibe reads the one you picked "
                + "as a wingfoil session, because you asked it to.",
                // Three sentences since 19 September 2026: the last one ran to 22 words,
                // and the arrow at the head of the block is what kept check_voice.py from
                // ever reading it. /help/ renders this on the web, where there is no arrow
                // rule, and it failed on the first run.
                "Open Import → Apple Health, allow CleanJibe to read workouts, and pick the "
                + "ones you want. After the first one, switch on \"Import new Health "
                + "workouts automatically\". The next session is then waiting when you open "
                + "the app.",
                "Speed comes off the watch's own GPS receiver, so these speed records are "
                + "certified. Nothing records your wrist accelerometer, so there are no pump "
                + "strokes and no failed takeoff attempts.",
            ],
            items: [
                .init(term: "Pick Surfing or Water Sports",
                      detail: "Both are on by default, and Surfing is what CleanJibe's own "
                          + "watch app writes. Sailing works too. Switch it on in "
                          + "Import → Apple Health."),
                // "The wrist may go under" lives once, in the CleanJibe watch app's topic,
                // which is first on `related` (26 September 2026: it was word for word here
                // too).
                .init(term: "Let the workout finish saving",
                      detail: "The route is written to Health when you end the workout. "
                          + "The watch may take a minute to hand it over."),
                .init(term: "Nothing is uploaded",
                      detail: "CleanJibe reads the route and the heart rate of the "
                          + "workouts you pick, and analyses them on your phone. It never "
                          + "reads anything else in Health."),
            ],
            related: [.appleWatchApp, .whichWatch]),

        // The rider who owns no watch at all. **It names no app and no other platform** —
        // App Store guideline 2.3.10 — so the answer is the *kind* of app and the file it
        // writes. Strava stays, because it is a door in this app rather than a
        // recommendation.
        HelpTopic(
            id: .phoneOnly, section: .record, title: "Recording with a phone only",
            summary: "Ride with a tracker app on a phone in a pouch. It comes in "
                + "through Strava or as a file.",
            body: [
                "A phone records a GPS track as well as most watches do. CleanJibe reads it "
                + "the same way.",
                "The Import screen calls it " + RecordingClass.c.name + ", because the "
                + "speed is worked out from the positions.",
                RecordingClass.c.line,
                "Keep the phone dry, still and facing the sky. A waterproof "
                + "pouch on the upper arm or high on the chest works.",
                "A pocket at hip height spends half the session underwater. Start the "
                + "recording on the beach.",
            ],
            items: [
                .init(term: "Strava, the way in that needs no file",
                      detail: "Record in the Strava app and connect Strava here. Strava's "
                          + "phone app cannot export a file, so the import reads the "
                          + "activity out of your account instead."),
                .init(term: "Any GPS-logging app that writes a file",
                      detail: "Anything on your phone that records a track and writes a "
                          + ".fit or a .gpx works. Save the track, tap Share, pick "
                          + "CleanJibe. Or open it from Files."),
                .init(term: "Which format, if you are offered a choice",
                      detail: "Pick FIT. CleanJibe reads a .fit in every build, and a file "
                          + "with the watch's own speed certifies its records. A .gpx or a "
                          + ".tcx opens in the CleanJibe beta."),
            ],
            related: [.stravaImport, .shareFromWatchApp, .whichWatch]),

        // MARK: Bring it in
        //
        // The steps are not written here: they come from `IcuSetupGuide`, which the
        // empty-library setup card renders too. One wording, two screens — and the Getting
        // started item above references them rather than repeating them.

        HelpTopic(
            id: .icuSetup, section: .bringIn, title: "Get set up with intervals.icu",
            summary: "Set it up once, in 4 steps and about 5 minutes.",
            body: [
                IcuSetupGuide.rationale,
                "Nothing is uploaded, and nothing changes in either account. CleanJibe "
                + "downloads the original recording of each watersport session and analyses "
                + "it on your phone.",
                // The one sentence that turns "a Garmin bridge" into "the way in for every
                // other brand", and what the recording those brands leave there is worth.
                "Polar, Suunto and COROS work this way too. Their own apps sync to "
                + "intervals.icu, and CleanJibe syncs from there.",
                "The file your watch left there decides how much you get. A FIT gives you "
                + "the full analysis. A GPX, or a TCX without speed, gives uncertified speed "
                + "records.",
            ],
            items: IcuSetupGuide.steps.map {
                .init(term: "\($0.number). \($0.title)", detail: $0.detail)
            } + [
                // Alfred, 18 September 2026: *"why does Garmin call it Windsurfen?"* — the
                // first thing a Garmin rider sees after his first session, and the app said
                // nothing about it. The guide's Garmin route carries the same three
                // sentences on the web (docs/guide/getting-started.json).
                .init(term: "Why Garmin says Windsurf",
                      detail: "Garmin has no wingfoil profile. Garmin and Strava call the "
                          + "session Windsurf. CleanJibe calls it Wingfoil."),
                // Alfred's next two screenshots, same day: Garmin Connect's activity page
                // showed "-- Runs" and he looked for the jibes. The watch app writes its
                // numbers as Connect IQ fields, which Garmin Connect lists under its own
                // heading; the Runs card is the windsurf profile's and no app can fill it.
                .init(term: "Where Garmin Connect shows the jibes",
                      detail: "Under Connect IQ on the activity page: jibes, tacks, foil "
                          + "time, flights and the best 2 seconds. They appear once "
                          + "you have set a wind direction on the watch."),
                .init(term: "Why the Runs card stays empty",
                      detail: "Runs belong to Garmin's own windsurf profile. No Connect IQ "
                          + "app can fill that card. CleanJibe's flights are the runs."),
            ],
            links: [HelpLink(title: "Open intervals.icu", url: IcuSetupGuide.intervalsURL)],
            action: .openIcuSettings,
            related: [.icuTroubleshooting, .notifications, .privacy]),

        // The second cloud source (ADR-023). What it costs is said early, because a rider
        // who finds out afterwards that his speed records are uncertified has been told
        // too late.
        HelpTopic(
            id: .stravaImport, section: .bringIn, title: "Import from Strava",
            summary: "Connect once, then pick the sessions you want. Strava keeps your "
                + "track but not your watch's speed.",
            body: [
                "CleanJibe lists your Strava sessions and imports the ones you pick. It only "
                + "reads. It never writes, renames or posts to your account.",
                "A Strava session still shows foil time, flights, every turn verdict, the "
                + "wind axis and the map.",
                "Strava keeps your track but not your watch's own speed, so the speed "
                + "records are marked uncertified. " + Copy.stravaFall + " Your wrist was "
                + "not recorded, so there are no pump strokes.",
                "If the same afternoon is also on intervals.icu, import it from there "
                + "instead. That is the original file off your watch, so those records "
                + "certify. Importing both is harmless, because the same session is never "
                + "added twice.",
            ],
            items: [
                // **One connect, and it is in Settings** (Jan, build 63: Import does,
                // Settings configures). The item named both screens; Import now lists what
                // a connected account holds and otherwise points here in one line.
                .init(term: "Connect",
                      detail: "Settings → Strava → Connect with Strava. Leave the "
                          + "private-activities box ticked or your \"Only you\" sessions "
                          + "will be missing."),
                .init(term: "Pick, or take everything new",
                      detail: "Tap the sessions you want, or use Import all new. Anything "
                          + "already in your library is marked and cannot be picked twice."),
                .init(term: "Which activities are offered",
                      detail: "Windsurf, Kitesurf, Surf, Workout and Stand-up paddling by "
                          + "default. Sail can be switched on. Anything named wing, foil, "
                          + "kite, surf or SUP is offered too."),
                .init(term: "Keep it automatic",
                      detail: "Once one session has come in this way, a switch appears. "
                          + "With it on, CleanJibe checks Strava whenever you open the app."),
                .init(term: "A long history takes its time",
                      detail: "Strava lets an app ask 200 times every 15 minutes. A first "
                          + "import of many seasons may ask you to come back later."),
                .init(term: "If connecting is refused",
                      detail: "Strava lets a new app connect a limited number of riders. "
                          + "That says nothing about your account. "
                          + "Tell us through Menu → Support & ideas."),
                .init(term: "Disconnecting",
                      detail: "Settings → Strava → Disconnect Strava. The sessions you "
                          + "already imported stay in your library. They are yours now, "
                          + "analysed on this phone."),
            ],
            related: [.whichWatch, .speedRecords, .icuSetup]),

        // The rider whose watch is neither a Garmin nor an Apple Watch. Every vendor path
        // was checked against that vendor's own help page on the date in the comment above
        // the items, and the one app that cannot do it says so in its first three words
        // rather than being quietly left out.
        HelpTopic(
            id: .shareFromWatchApp, section: .bringIn,
            title: "Share from your watch app straight into CleanJibe",
            summary: "Polar, Suunto and COROS can hand a session to CleanJibe as a file. "
                + "Garmin's phone app cannot.",
            body: [
                "Every watch app can export a recording as a file, and CleanJibe reads .fit "
                + "files. Export the session as a FIT and pick CleanJibe from the share "
                + "sheet.",
                "If it is not in the row, Save to Files and open it from there.",
                "If you are asked for a format, pick FIT. A FIT carries the watch's own "
                + "speed, so its records certify.",
                "A .gpx or a .tcx carries positions only, so its records are marked "
                + "uncertified. Those two formats open in the CleanJibe beta.",
                "Garmin Connect's phone app has no export at all. Garmin owners have two "
                + "better ways in: intervals.icu, or connect.garmin.com on a computer.",
            ],
            // **Every path below was walked against that vendor's own help page on
            // 13 September 2026.** The dates used to be part of the terms — "Suunto,
            // verified 13 Sep 2026" — which is a fact about the author printed where the
            // reader is looking for a brand (Jan, dev 70). The term is the brand now, the
            // caveat opens the detail, and the date lives here. Re-walk the four paths
            // before touching them and move this date with them.
            items: [
                // Garmin first: it is the popular watch and the one answer a rider does
                // not expect, so it goes above the three that work from the phone.
                .init(term: "Garmin",
                      detail: "No phone export. On a computer: connect.garmin.com → "
                          + "Activities → the activity → gear icon → Export File."),
                .init(term: "Suunto",
                      detail: "On the phone: Calendar → tap the workout → ⋯ top right → "
                          + "FIT. Then Save to Files, or pick CleanJibe from the share "
                          + "sheet."),
                .init(term: "COROS",
                      detail: "On the phone: Activities → tap the activity → ⋯ top right → "
                          + "Export → FIT. Older versions call it Export Data. Then use "
                          + "the share sheet."),
                .init(term: "Polar",
                      detail: "Not on the phone. On flow.polar.com: Diary → click the "
                          + "session → Export → FIT. A computer is the reliable way."),
                .init(term: "Anything else",
                      detail: "If an app can produce a FIT, CleanJibe reads it. Take it "
                          + "from AirDrop, Mail or Files. A ZIP of recordings works too: "
                          + "Import → FIT or ZIP…."),
            ],
            // **No vendor links any more** (26 September 2026). The four support pages
            // the paths were walked against went stale on their own schedule and sent the
            // rider out of the app for a path the item already spells out. They were:
            // support.garmin.com faq W1TvTPW8JZ6LfJSfK512Q8, suunto.com faq "how do I
            // download a .fit file from suunto app for ios", support.coros.com article
            // 360043975752, support.polar.com "export-training-sessions-flow".
            related: [.whichWatch, .icuSetup, .phoneOnly]),

        // **The browser app.** One of the four questions on cleanjibe.org/learn until
        // 19 September 2026 was "is there an app for the other phone", and /help/ is built
        // from this catalogue now, so the answer lives where every other answer lives. It
        // is a fair topic for the phone too: the reader who asks it is usually asking on
        // behalf of a friend, or wants to hand somebody an analysis without an install.
        //
        // **It names no other platform** — App Store guideline 2.3.10, the rule that
        // rewrote the phone-only topic on 14 September 2026 and that
        // `PresentationTests.noHelpTopicNamesAnotherPlatform` holds. The browser is the
        // subject here, which is a truthful and sufficient answer; the sentence that names
        // the platform lives on /start/#watches, where it is the website speaking rather
        // than the app.
        //
        // The browser app is a DIFFERENT PRODUCT: no channels, and it reads .gpx and .tcx
        // in the tab the reader already has open (docs/copy/check_release_copy.py says so
        // at its own target). That is why the formats are named here and the iPhone's own
        // GPX door is not.
        HelpTopic(
            id: .browserApp, section: .bringIn, title: "CleanJibe in a browser",
            summary: "The same analysis in any browser. Nothing to install, no account.",
            body: [
                "Open " + Branding.site + "/app and drop a recording in. You get the "
                + "session back with its flights, its turns and its speed records.",
                "It keeps a library, records and trends of its own. Any phone with a "
                + "browser can read a session this way.",
                "The file is read inside the tab. Nothing is uploaded and no account is "
                + "asked for.",
            ],
            items: [
                .init(term: "What it reads",
                      detail: "It reads a .fit, a .gpx or a .tcx from any watch. It has no "
                          + "beta, so every rider gets the same version."),
                .init(term: "Install it from the browser",
                      detail: "If your browser offers it, install the page. It gets an "
                          + "icon on your home screen, opens like an app and works with no "
                          + "signal."),
                .init(term: "Into the share sheet",
                      detail: "Once it is installed, hold a file on the phone and pick "
                          + "Share, then CleanJibe. The analysis opens on it."),
            ],
            links: [HelpLink(title: "Open the browser app",
                             url: URL(string: Branding.siteURL + "/app")!)],
            related: [.shareFit, .phoneOnly, .privacy]),

        // **Where the notification switch's seven paragraphs went** (20 September 2026,
        // pattern K: a footer says what you get in one line and the how is a help link).
        // Settings → Notifications now reads one line and links here.
        HelpTopic(
            id: .notifications, section: .bringIn,
            title: "Notifications for new sessions",
            summary: "Hear about a session while the phone is idle, and what decides whether "
                + "you do.",
            body: [
                "While the phone is idle, CleanJibe asks intervals.icu for new activity. It "
                + "looks for windsurf, wing, kite, surf and SUP, from any watch that syncs "
                + "there.",
                "You hear about the ones that are not in your library yet. The session is "
                + "downloaded and analysed in the background, so tapping the notification "
                + "usually opens a finished analysis.",
                "iOS decides when a background app may run. It learns your habits and may "
                + "hold a check back for hours. It never runs in Low Power Mode.",
                "It never runs while Background App Refresh is off, under Settings → "
                + "General → Background App Refresh. Pull down on Sessions to sync now.",
            ],
            items: [
                .init(term: "It needs a key",
                      detail: "CleanJibe looks in your intervals.icu account, so add the "
                          + "API key first, in Settings → intervals.icu."),
                .init(term: "Off by default",
                      detail: "Turning it on is what asks iOS for permission. CleanJibe "
                          + "offers it once by itself, right after your key works."),
            ],
            action: .openIcuSettings,
            related: [.icuSetup, .icuTroubleshooting]),

        // MARK: Read the numbers
        //
        // One section of seventeen topics, sub-headed (`HelpSubsection`) so it still reads
        // in the parts the old sections were. The glossary opens it, then the map.
        //
        // **The glossary, rendered.** Every term, its one-line rule, and where it shows.
        // Nothing here is written: `MetricGlossary` is the source, `docs/copy/glossary.json`
        // is its artefact, and `web/tools/make_help.py` renders the same nineteen rows into
        // /help/#numbers. A second spelling of a rule in this file would be exactly the
        // drift the glossary exists to stop.
        //
        // **Why it is a topic and not just the index it used to be** (docs/review-checklist.md,
        // pattern A): "What the numbers mean" was the title over the whole ten-section Help,
        // which is a title wider than its content. It is a title exactly the right width over
        // nineteen definitions.
        //
        // Jan, 20 September 2026: *"the definitions of the numbers are important to clarify,
        // make transparent, and consistent across all surfaces"*. A tester had read
        // *Turn success 29 %* in Garmin Connect, *93 % flew through* on the site and 44 % on
        // the phone, about one afternoon. The three are three measurements; this page is where
        // a rider learns that, and the `where it shows` line is what points him at the screen
        // he was comparing.
        HelpTopic(
            id: .numbers, section: .readNumbers,
            title: "What the numbers mean",
            summary: "Every word CleanJibe counts with, and where each one shows.",
            body: [
                "Each number has one word, on the watch, the phone, the card and the site. "
                + "If you see one number called two things, tell us.",
            ],
            // Term and rule, and the one surface worth naming: the watch and the row
            // Garmin Connect prints, which is where the three numbers disagreed. The full
            // "where it shows" list is `places` in docs/copy/glossary.json, and the site
            // renders it from there.
            items: MetricGlossary.entries.map {
                let also = MetricGlossary.alsoOn($0)
                return .init(term: $0.term,
                             detail: also.isEmpty ? $0.line : $0.line + " " + also)
            },
            related: [.turnSuccess, .speedRecords, .divergence]),

        // The legend used to be printed under the chips on every visit to every session —
        // three grey paragraphs of reference material (app-ui-review.md §1.2). Reference
        // material belongs behind the `?` the rest of the page already uses.
        HelpTopic(
            id: .mapLegend, section: .readNumbers, subsection: .foil, title: "Reading the map",
            summary: "What the chips, the colours, the arrows and the dots mean.",
            body: [
                "Every chip under the map is a switch. Tap one to hide that kind of mark "
                + "on the map and in the speed chart at once.",
                "A hidden chip stays in place, struck through, and \"show all\" brings "
                + "everything back. A chip this session has nothing for cannot "
                + "be switched. The three rows are the track, the marks on it, and the "
                + "map's own controls.",
                "Tap the track to move the replay playhead. Tap a mark, or a flown "
                + "stretch, for its own facts.",
            ],
            items: [
                .init(term: "The track",
                      detail: "Tinted by phase: teal where you were flying, grey where you "
                          + "were not. Small chevrons along it point the way you were "
                          + "riding."),
                .init(term: "The dots",
                      detail: "Verdicts on one ladder: green flew through, orange touched "
                          + "down, red fell in. Grey is a course change and no verdict at "
                          + "all."),
                .init(term: "Solid or hollow",
                      detail: "The fill tells two kinds of mark apart without a second "
                          + "colour. Solid is a turn's outcome. Hollow is a flight that ended "
                          + "on a straight line, outside any turn."),
                .init(term: "A star",
                      detail: "A clean jibe, in a green of its own, taking the place of that "
                          + "jibe's dot. It needs both its chips: hide the outcome and the "
                          + "star goes with it."),
                .init(term: "Arrows, not dots",
                      detail: "Takeoffs: an up-arrow got you up, a red u-turn is an attempt "
                          + "that did not. One chip hides both halves."),
                .init(term: "Bands and drops",
                      detail: "The indigo bands are pump bursts. The cyan drop is the "
                          + "barometer seeing your wrist go under."),
            ],
            image: HelpImage(asset: "help-map-layers",
                             caption: "The chips above the map turn each layer on and "
                                 + "off. Here the fell-in marks are hidden."),
            related: [.flights, .turnOutcomes, .takeoffAttempts]),

        // **Four topics, one page** (26 September 2026). Foil time, flights, the longest
        // flight and distance were four topics of two or three paragraphs each, all about
        // the same flights and each explaining the thresholds again. The mechanism is said
        // once in the body; each number the session page prints is an item. The old ids
        // still open this page (`HelpCatalog.redirects`).
        HelpTopic(
            id: .flights, section: .readNumbers, subsection: .foil,
            title: "Flights and foil time",
            summary: "How often you got up, how long you stayed up, and how far you went.",
            body: [
                "A flight starts when your speed holds above 12 km/h for 2 s. It ends when "
                + "your speed stays under 8 km/h for 3 s. Both are the default thresholds.",
                "A flight is dated back to the first moment that counted, at both ends. "
                + "Anything under 5 s is not a flight.",
                "A brief touchdown does not split a flight. A one- or two-second tap of the "
                + "water stays inside it.",
                "Taxiing, swimming and the drift upwind count against your time on foil. A "
                + "gap in the recording does not.",
            ],
            items: [
                .init(term: "Foil time and On foil",
                      detail: "Foil time is the minutes you flew. On foil is their share of "
                          + "timer time, which leaves out any stretch where the recording "
                          + "stopped or lost GPS."),
                .init(term: "Flights",
                      detail: "How many separate times you got up and stayed up. It answers "
                          + "\"how many times did I have to get up again\"."),
                .init(term: "Longest flight",
                      detail: "Your longest flight by time, with its distance underneath. "
                          + "Many short flights and one long one can give the same On foil."),
                .init(term: "Distance",
                      detail: "Added up from the watch's Doppler speed, not from positions, "
                          + "because position noise inflates a distance at low speed. It "
                          + "covers flying, taxiing and drifting."),
            ],
            related: [.turnOutcomes, .takeoffAttempts, .whichWatch]),

        // MARK: Speed records
        //
        // **One topic, and its items are the windows** (Jan, dev 65: *"do we really need
        // separate pages to describe each distance?"*). There were eight: the set, six
        // windows and the uncertified mark, each two sentences long, each a row on an index
        // and a sheet to open. A rider asking "what is alpha 500" wants one line, in the
        // list of the others, so he can see what he did not ask about too.
        //
        // **What the glossary says is not said here** (26 September 2026). The summary is
        // the glossary's line, and 5×10 s and alpha 500 were items copied out of it, so the
        // same two definitions sat on two pages. They live on What the numbers mean, which
        // is first on `related`, and the body names them so a search for "alpha" still
        // lands here.
        HelpTopic(
            id: .speedRecords, section: .readNumbers, subsection: .records,
            title: "Speed records",
            summary: MetricGlossary.entry("speedRecords").line,
            body: [
                "The set is fixed, so your numbers compare with anyone's. It holds the four "
                + "windows below, 100 m, 250 m and your best hour.",
                "Best 5×10 s and Alpha 500 are defined in What the numbers mean.",
                "All of them use the watch's Doppler speed, measured to the exact edge of "
                + "each window. So a watch that records once a second scores the same as "
                + "one that records four times. No slow stretch is thrown away.",
                "A window never spans a recording gap. Tap a record card to see where on the "
                + "track and on the speed trace it happened.",
                "A record certifies only when the recording holds the receiver's own speed "
                + "channel. The rest are marked uncertified.",
            ],
            items: [
                .init(term: "Best 2 s",
                      detail: "Your peak speed, averaged over 2 seconds. A single-sample "
                          + "maximum is noise. 2 seconds is a real burst, and the number "
                          + "most riders compare."),
                .init(term: "Best 10 s",
                      detail: "The fastest 10-second run, a burst you had to hold. Luck "
                          + "and a single gust cannot carry it, so it usually sits 1 to 3 "
                          + "knots below your 2 s."),
                .init(term: "Best 500 m",
                      detail: "Your fastest half-kilometre, measured along the line you "
                          + "actually rode. A curved run still counts, and cutting the "
                          + "corner flatters nothing."),
                .init(term: "Best 1 NM",
                      detail: "Your fastest nautical mile, 1852 m. On most spots it needs "
                          + "more than one leg, so it measures how well you keep speed "
                          + "through your turns."),
                // Alfred, 18 September 2026: three apps show his speed and two of them
                // disagree with the third. Each one has its own unit, so the answer is a
                // list of where each switch is rather than a rule.
                // Four readers, four settings — so the item names each one and where it is
                // set. The phone's own switch arrived on 20 September 2026 (Settings →
                // Units); before it, "CleanJibe shows knots" was the whole answer.
                .init(term: "Knots or km/h",
                      detail: "Knots by default. Settings \u{2192} Units switches every speed "
                          + "on the phone to km/h."),
                .init(term: "The other three readers",
                      detail: "The watch app has its own switch, under Garmin Connect → "
                          + "CleanJibe → Settings. Garmin Connect follows its own. Strava "
                          + "shows windsurf in knots."),
                // Last, because it is the one line that is about the recording rather than
                // about a window — and the one a rider needs before he posts a number.
                .init(term: "\"Uncertified\"",
                      detail: "A recording with positions but no speed channel has its "
                          + "speed worked out from them, which reads high. Every GPX is "
                          + "one, and some converted exports. It is marked everywhere."),
            ],
            related: [.numbers, .verifiedRecords, .whichWatch]),

        // Settings → Speed records (Jan, 22 September 2026). The topic the `?` on that
        // section opens, and the one place the three modes are spelled out for a rider.
        // Four sentences, because the question is small and the answer is a choice: what
        // the two words mean, what each mode does, and where the setting is.
        HelpTopic(
            id: .verifiedRecords, section: .readNumbers, subsection: .records,
            title: "Verified and unverified speed records",
            summary: "Choose whether a record from a track without measured speed counts.",
            body: [
                "A verified record comes off a recording that carries your watch's own "
                + "Doppler speed. An unverified one is worked out from positions, which "
                + "reads high.",
                "Only verified keeps unverified records out of your all-time table, your "
                + "trends and your cards. The session that set one still shows it, marked.",
                "Prefer verified is the default. A verified record wins its row, and an "
                + "unverified one fills a row no verified record has reached.",
                "Include unverified counts every record and marks the ones it could not "
                + "verify. Settings \u{2192} Speed records is where you choose.",
            ],
            related: [.speedRecords, .whichWatch, .stravaImport]),

        HelpTopic(
            id: .turnTypes, section: .readNumbers, subsection: .turns,
            title: "Tacks, jibes and course changes",
            summary: "What counts as a turn, and what is just a change of direction.",
            body: [
                "A turn is detected from your course. It needs at least 60° of net heading "
                + "change within 8 seconds, with a peak rate of 25°/s. You must be on the "
                + "foil, or within 3 s of it.",
                "It must also carve a real arc. That means at least 12 m of path, at an "
                + "effective radius of at least 6 m. A rider spinning around beside the "
                + "board carves no arc.",
                "What kind of turn it was depends on the wind axis:",
            ],
            items: [
                .init(term: "Jibe", detail: "Your course crosses the wind axis through downwind."),
                .init(term: "Tack", detail: "Your course crosses the wind axis through upwind."),
                .init(term: "Bear-away / round-up",
                      detail: "A real course change that never crosses the axis. Counted "
                          + "separately and left out of the tack and jibe tallies. It is not "
                          + "a manoeuvre you either made or blew."),
                .init(term: "Turn",
                      detail: "A turn on a session where the wind axis was too uncertain to "
                          + "name it. It is still counted, just unnamed."),
                // Where Settings → Analysis's footer went (pattern K, 20 September 2026).
                .init(term: "Most of my turns are",
                      detail: "Your track gives the wind axis as a line. When a session "
                          + "cannot say which end the wind blew from, your habit does."),
                .init(term: "Changing it later",
                      detail: "Sessions already in your library change only when you re-run "
                          + "the analysis, from Settings \u{2192} Storage."),
            ],
            related: [.windAxis, .turnOutcomes, .portStarboard]),

        HelpTopic(
            id: .turnOutcomes, section: .readNumbers, subsection: .turns,
            title: "Turn outcomes: flew through, touchdown, fell in",
            summary: "What actually happened to the foil in the turn.",
            body: [
                "Every turn gets one of three outcomes. The judgement runs from the turn "
                + "start until you are flying again. That means speed back above 70 % of "
                + "your entry speed for 2 seconds. The window is capped at 12 seconds.",
                "A jibe exited at marginal speed can bleed off for 6 to 12 seconds before "
                + "the foil stalls. That mush-out is the jibe's fault. A jibe you power out "
                + "of closes its window in a second or two.",
                "CleanJibe reads three things inside it. Your speed is always read. So is "
                + "the barometer, because a wrist under water looks like a huge drop in "
                + "altitude. On a CleanJibe watch recording, the accelerometer is read too.",
            ],
            items: [
                .init(term: "Flew through",
                      detail: "You never left the foil. No sample in the window is off-foil."),
                .init(term: "Touchdown",
                      detail: "You lost the foil but not the session: you stopped for 3 s or "
                          + "less, or pumped it back up. Borderline between 3 s and 5 s."),
                .init(term: "Fell in",
                      detail: "You stopped for more than 5 s, or the barometer says your wrist "
                          + "went under."),
                // What the Touchdowns topic said, before it was merged in here
                // (26 September 2026): a touchdown is counted outside turns too, and a
                // short one does not end a flight.
                .init(term: "Touchdowns on a straight line",
                      detail: "A touchdown outside any turn is counted for the session. A "
                          + "short one inside a flight does not split the flight."),
            ],
            image: HelpImage(asset: "help-turn-list",
                             caption: "Every turn, with the verdict and the evidence behind "
                                 + "it."),
            related: [.turnSuccess, .falls, .glideOuts]),

        // **Three requirements, not two** (engine 0.17.0). This topic was a version behind
        // its own engine until 15 September 2026: it still framed clean as 0.12.0's "flew
        // through + 70 %" while the web, the watch listing and /whats-new all described the
        // quiet tail. docs/algorithms/turns.md ("The quiet tail") is the contract and the three
        // tests below are its three, in its order.
        HelpTopic(
            id: .turnSuccess, section: .readNumbers, subsection: .turns, title: "Clean jibes",
            summary: "A jibe you fly all the way through without losing much speed. The "
                + "10 seconds after it stay quiet too.",
            body: [
                "A turn that **flew through** never lost the foil, from its start until you "
                + "were flying again. A **clean** jibe flew through, held its speed, and "
                + "stayed quiet after.",
                "Holding the speed: your minimum speed through the turn stays at or above "
                + "70 % of your entry speed. You never drop below the foil exit speed.",
                "Staying quiet means the 10 seconds after the turn. They hold no touchdown "
                + "or fall, no second or more off the foil, and no wrist under water.",
                "So clean is a strict subset of flew through. A jibe that held its speed "
                + "and then lost the foil coming out is not clean.",
            ],
            // **The four glossary lines went on 26 September 2026.** Flew through, Clean,
            // Speed kept and Dry were items here, copied out of `MetricGlossary`, so the
            // same four definitions sat one tap apart. They are on What the numbers mean,
            // first on `related`; this page keeps what the glossary does not say.
            items: [
                .init(term: "Jibes only",
                      detail: "A tack has no clean reading to carry, so the Tacks card "
                          + "reports only how its tacks ended."),
                .init(term: "Score",
                      detail: "The share of your entry speed you held through the turn, "
                          + "0 to 100. It is the evidence behind \"clean\", printed beside "
                          + "every turn."),
            ],
            related: [.numbers, .turnOutcomes]),

        HelpTopic(
            id: .portStarboard, section: .readNumbers, subsection: .turns,
            title: "Port / starboard",
            summary: "Which tack you were on going in, and which side you avoid.",
            body: [
                "The side is read from your wind angle before the turn. A 50/50 split "
                + "means you work both sides equally. A lopsided split is the tack you "
                + "quietly stop choosing, and usually the one worth practising.",
                "The Trends screen plots this over time as \"% port\", with 50 % marked.",
            ],
            related: [.turnTypes, .windAxis]),

        HelpTopic(
            id: .falls, section: .readNumbers, subsection: .turns,
            title: MetricGlossary.entry("fellIn").term,
            summary: MetricGlossary.entry("fellIn").line,
            body: [
                "A fall means you stopped for more than 5 seconds, or the barometer caught "
                + "your wrist going under.",
                "The split matters. Falls in a turn are a turning problem. Falls in a "
                + "straight line are a gust, a ventilation or a tip catching. Each fall is "
                + "counted once. A fall inside a turn's window belongs to that turn.",
                // The correction of 20 September 2026, said to the rider it happened to.
                "The jibe tally is a different question. Its three counts are out of your "
                + "jibes, so a fall in a straight line is not in them. This number counts the "
                + "whole session.",
            ],
            related: [.turnOutcomes, .glideOuts]),

        HelpTopic(
            id: .glideOuts, section: .readNumbers, subsection: .turns, title: "Glide-outs",
            summary: "Flights that ended without ever stopping.",
            body: [
                "The flight ended and you kept moving. You settled onto the board and "
                + "taxied on, or you chose to stop riding. No stop was ever measured, so "
                + "this is not counted as a loss.",
                "When a flight ends because the recording stopped, CleanJibe calls it "
                + "unknown. There is nothing there to judge, so it stays out of every "
                + "tally.",
            ],
            related: [.falls, .turnOutcomes]),

        HelpTopic(
            // **"Getting up", not "success rate"** (20 September 2026). The word is
            // engine vocabulary and may not be printed to a rider (CLAUDE.md) — and on the
            // same afternoon it named a takeoff rate here and a turn speed verdict in
            // Garmin Connect. Two measurements, one word.
            id: .takeoffAttempts, section: .readNumbers, subsection: .takeoff,
            title: "Attempts & getting up",
            summary: MetricGlossary.entry("takeoffAttempts").sentence.prefix(1).uppercased()
                + MetricGlossary.entry("takeoffAttempts").sentence.dropFirst() + ".",
            body: [
                "Attempts are takeoffs plus failed attempts. A pumping burst is a failed "
                + "attempt when no flight starts within 10 seconds of your last stroke. "
                + "Bursts closer together than that are chained into one attempt.",
                "Takeoffs alone cannot show this. Getting up 20 times out of 22 looks like "
                + "getting up 20 out of 40.",
                "It needs the wrist accelerometer, which only the CleanJibe watch app "
                + "records. Without it your failures are invisible, so the share is shown "
                + "as unknown rather than a flattering 100 %.",
            ],
            // Takeoffs and Attempts were items copied out of the glossary; they are on
            // What the numbers mean, first on `related` (26 September 2026).
            related: [.numbers, .pumpsToTakeoff, .whichWatch]),

        HelpTopic(
            id: .pumpsToTakeoff, section: .readNumbers, subsection: .takeoff,
            title: "Pumps to takeoff",
            summary: "How many strokes each flight cost you.",
            body: [
                "The takeoff run starts at the rising speed before the flight. It starts "
                + "at the pump burst that led into it, if that came first. So the count is "
                + "the strokes of the effort that produced the flight.",
                "Takeoffs under 3 strokes are counted as free: you got up on the wind alone. "
                + "That is a fact about the conditions, so free takeoffs are kept out of the "
                + "averages and reported separately.",
                "Runs the recording cut short are left out of the averages. They still "
                + "count as takeoffs that worked: the flight happened, only its cost is "
                + "unknown.",
            ],
            related: [.takeoffAttempts, .pumpStrokes, .heartRate]),

        HelpTopic(
            id: .pumpStrokes, section: .readNumbers, subsection: .takeoff,
            title: "Pump strokes",
            summary: "Every stroke in the session, and the ones you did in flight.",
            body: [
                "Strokes are counted from the wrist accelerometer. Only the strength of "
                + "each movement counts, so how your wrist was turned does not matter.",
                "In-flight strokes hold or extend a glide rather than get you up. That is "
                + "different work, so they are counted separately.",
            ],
            related: [.pumpsToTakeoff, .whichWatch]),

        HelpTopic(
            id: .heartRate, section: .readNumbers, subsection: .effortWind,
            title: "Heart rate: cost and coverage",
            summary: "What an attempt costs in heartbeats, and when that can be trusted.",
            body: [
                "Heart-rate cost is the rise from your baseline just before an effort to the peak "
                + "that follows. The baseline is the median of the 10 seconds ending at the "
                + "start of the takeoff run.",
                "The peak is searched 30 seconds forward, because an optical wrist sensor "
                + "trails effort by 10 to 20 seconds. Negative values are reported rather than "
                + "hidden: \"still recovering when you started\" is a different fact from "
                + "\"this cost nothing\".",
                "The card does not appear on a session whose recording has no usable heart "
                + "rate. Nothing here is estimated when the sensor was silent.",
            ],
            items: [
                .init(term: "Coverage",
                      detail: "The share of a window with good readings, between 30 and "
                          + "220 bpm and no more than 10 seconds apart. Below 60 % no number "
                          + "is shown."),
                .init(term: "Why it drops out",
                      detail: "A wrist sensor under a wetsuit sleeve in cold water drops out "
                          + "and sticks. A made-up average is worse than a missing one."),
                .init(term: "The fatigue chart",
                      detail: "Your session in 20-minute blocks, each showing what its "
                          + "takeoffs cost, with the share of attempts that got up underneath. "
                          + "An empty block is shaded, not drawn as zero."),
                .init(term: "Read the cost bars with the baseline note",
                      detail: "A rise measured against a baseline that has drifted upward "
                          + "gets smaller as you tire. A shrinking late cost is not evidence "
                          + "that the takeoffs got easier."),
            ],
            related: [.takeoffAttempts, .pumpsToTakeoff, .whichWatch]),

        HelpTopic(
            id: .windAxis, section: .readNumbers, subsection: .effortWind,
            title: "Wind axis & confidence",
            summary: "The wind direction worked out from how you actually rode.",
            body: [
                "No weather station is involved. The estimate comes from your own track. "
                + "CleanJibe looks at the headings you flew and finds your two main "
                + "reaching directions. The wind axis is the line halfway between them.",
                "That gives an axis but not a side. The no-go zone breaks the tie. Of the "
                + "two ends, the wind came from the one you rode almost nothing within "
                + "±45° of.",
                "Confidence combines how cleanly the two reaches separate with how decisive "
                + "the no-go zone was. Below 50 % the axis is still shown, but your turns "
                + "stay unnamed \"turns\" rather than tacks and jibes.",
                "A wind direction you set on the watch always wins.",
            ],
            related: [.turnTypes, .portStarboard]),

        HelpTopic(
            id: .windsurf, section: .readNumbers, subsection: .effortWind, channel: .dev,
            title: "Windsurf (experimental)",
            summary: "The same engine without the wing. The planing speeds are a guess.",
            body: [
                "A session can be analysed as **Wingfoil**, **Windsurf foil** or **Windsurf "
                + "fin**. The row is on the session's Details tab, under \"Analyse as\". "
                + "Changing it works that one session out again, and nothing else.",
                "None of Garmin, Strava, intervals.icu and Apple Health has a wingfoil "
                + "sport. Most riders record under the windsurf profile. A new session "
                + "cannot say which rig it was ridden on.",
                "So CleanJibe reads it as whatever you set under Settings → \"I mostly "
                + "ride\". It is marked with a **?** until you have looked, and listed "
                + "after each import. Sessions from the CleanJibe watch app are never "
                + "asked about.",
            ],
            items: [
                .init(term: "What works",
                      detail: "Jibes and tacks are the same detector, the same thresholds and "
                          + "the same three verdicts. So are the speed records, the wind "
                          + "axis, the wrist-under marks and the map."),
                .init(term: "What is off",
                      detail: "Pumping. With no wing to load, pump chips, stroke counts, "
                          + "pumps-to-takeoff and the heart-rate cost are **absent rather "
                          + "than zero**. A takeoff becomes a planing start."),
                .init(term: "Windsurf foil",
                      detail: "The wingfoil reading with pumping switched off. Every speed "
                          + "and every threshold is the same, because a foil flies the same "
                          + "way under either rig."),
                .init(term: "Windsurf fin",
                      detail: "Also moves the two speeds that decide when you are going. "
                          + "20 km/h starts planing and 15 km/h stops it, against 12 and 8 "
                          + "on a foil."),
                .init(term: "Those two speeds are provisional",
                      detail: "They are a first guess, because we have no real fin "
                          + "sessions yet. If your planing time looks wrong, tell us that "
                          + "number."),
                .init(term: "In the library",
                      detail: "\"Foil time\" means planing time here, and \"lost the "
                          + "foil\" means stopped planing. Windsurf sessions count towards "
                          + "your trends. There is no separate record set."),
            ],
            related: [.flights, .turnOutcomes, .pumpsToTakeoff]),

        // MARK: Share
        //
        // The rest of this catalogue explains *numbers*. This section explains three things
        // a rider will never find by tapping around, because each of them is one button on
        // one sheet. What leaves the phone is the half somebody is deciding about.

        HelpTopic(
            id: .shareCard, section: .share, title: "Share cards",
            summary: "One picture of a session, made to post.",
            body: [
                "Any session becomes a card. It holds the track, the numbers that matter, "
                + "and where the analysis came from. Pick portrait, square or "
                + "landscape, and Complete or Lean. A photo from your library can go behind "
                + "it.",
                "Or turn on the map background and the track is drawn over the water you "
                + "rode. That one needs a connection. Without one the card comes out "
                + "plain.",
                "The card is made on your phone and goes nowhere until you send it.",
            ],
            image: HelpImage(asset: "help-share-composer",
                             caption: "Pick a shape, pick how much detail, send it."),
            related: [.replayClip, .shareFit]),

        HelpTopic(
            id: .replayClip, section: .share, title: "Replay clips",
            summary: "Record the replay as a video.",
            body: [
                "The replay plays a session back on its own track, with a commentary that "
                + "follows what is happening. Scrub to the part worth watching, then record "
                + "it as a video.",
                "Ask for a 10, 25 or 60-second clip. The app sets the playback speed to "
                + "fit it. Or take \"full detail\" and let the session run as long as it "
                + "runs.",
                "The frame is yours too. Take 9:16 for a story, 1:1 for a post, 16:9 for a "
                + "chat, or the whole screen. Photos from that afternoon can be spliced in.",
                "You can lay your own music under it, trimmed or looped and faded at both "
                + "ends. Nothing is uploaded: the video is rendered on the phone.",
            ],
            image: HelpImage(asset: "help-replay",
                             caption: "The replay running: the marker on the track, the "
                                 + "clock, and the commentary calling what just happened."),
            related: [.shareCard, .mapLegend]),

        HelpTopic(
            id: .shareFit, section: .share, title: "Sending a session to a friend",
            summary: "Share the original recording, stripped of anything identifying.",
            body: [
                "You can share the original .fit file of any session. The watch serial, "
                + "your rider profile and your lifetime totals are removed first. The ride "
                + "itself is untouched, so the analysis your friend gets is identical to "
                + "yours.",
                "They can open it in CleanJibe, or drop it into the free browser app at "
                + Branding.site + " without installing anything.",
            ],
            // No "Open the browser app" link since 26 September 2026: the friend is the one
            // who needs the browser, and the topic that explains it is first on `related`.
            related: [.browserApp, .riderAttribution, .shareCard]),

        // MARK: Your library
        //
        // The topic that exists because of the one thing this app cannot get back for you.
        // The recordings are recoverable — intervals.icu still has them — but what you
        // *called* a session, whose it was, which wing it was on and which sessions you
        // deliberately threw away live in one database on one phone and nowhere else.
        //
        // The Settings footer (`LibraryBackupSection`) and this topic say the same thing
        // once each: the footer short, this one complete. Neither repeats the other's
        // paragraph.
        HelpTopic(
            id: .libraryBackup, section: .library, title: "Backing up your library",
            summary: "A new phone carries everything by itself. A fresh start needs a file.",
            body: [
                "Setting up a new iPhone from this one carries your library across, and so "
                + "does an iCloud backup.",
                // Two sentences since 19 September 2026: at 23 words this was over the
                // 20-word rule, and it only ever passed docs/copy/check_voice.py because a
                // literal with an arrow in it is skipped as path notation. /help/ renders
                // the catalogue on the web, where there is no arrow rule, and the page said
                // so on the first run.
                "Settings → Library backup is for the case neither covers. That is a phone "
                + "set up as new, or the app deleted and installed again.",
                "The file holds every recording you imported, and what nothing else can "
                + "bring back. That is each session's name and caption, whose it was, its "
                + "gear. Your spot names and the sessions you deleted on purpose are there "
                + "too.",
                "Restoring never overwrites. Sessions already in your library keep "
                + "their own analysis. Details you changed since are left alone. Restoring "
                + "the same file twice does nothing the second time. Sessions you deleted "
                + "after the backup stay deleted.",
            ],
            items: [
                .init(term: "Save the file yourself",
                      detail: "Back up library makes the file, and Save… puts it in "
                          + "Files, iCloud Drive or on a Mac. CleanJibe keeps no copy."),
                .init(term: "Your own recordings, nothing stripped",
                      detail: "The .fit and .gpx files inside are the originals. Nothing "
                          + "is removed. A session you send a friend is stripped first. "
                          + "This file is for you, not for sharing."),
                .init(term: "How big it will be",
                      detail: "A session recorded with the CleanJibe watch app carries a "
                          + "100 Hz accelerometer recording, about 95 % of its size. The app "
                          + "estimates the total before it starts."),
                .init(term: "A newer backup",
                      detail: "CleanJibe will not open a backup from a newer version of "
                          + "itself. Update the app and try again. An older backup is "
                          + "brought up to date."),
            ],
            related: [.riderAttribution, .shareFit, .privacy]),

        HelpTopic(
            id: .riderAttribution, section: .library, title: "Sessions someone else rode",
            summary: "A friend's session is shown in full but kept out of your records.",
            body: [
                "When you import a file, CleanJibe asks whose session it is. A friend's "
                + "session is saved and shown in full: map, replay, every turn. It stays out "
                + "of your records, trends and gear totals.",
                "Their fast run never becomes your personal best. The name you give is stored "
                + "on your phone only.",
            ],
            related: [.shareFit, .exampleSession]),

        // **The app's own link to the privacy policy** (15 September 2026). There was none:
        // docs/channels.md makes "covered by the privacy page" one of the four rules a
        // feature meets before it moves up a channel, and the App Store record carries the
        // URL — but a rider inside the app had no way to reach it, and the page describes
        // *the app's* behaviour.
        //
        // It is a summary and a link, deliberately not a mirror: a GDPR document is a legal
        // text with its own shape and its own update cycle, and a second copy of it in a
        // help catalogue is a second copy to keep true. Three sentences that answer the
        // question, then the page. Settings → About carries the same link for the rider who
        // never opens Help.
        //
        // **Where your API key is kept is an item here since 26 September 2026.** It was a
        // topic of its own that said, in two paragraphs, the one thing this page already
        // says of everything: it goes to intervals.icu and nowhere else. `icuPrivacy` still
        // opens this page (`HelpCatalog.redirects`).
        HelpTopic(
            id: .privacy, section: .library, title: "What leaves your phone",
            summary: "There is no account and no server, and nothing is uploaded. The "
                + "whole policy is on the web.",
            body: [
                "There is no CleanJibe account and no CleanJibe server. A session you "
                + "import is analysed on this phone and stays on it. There is no advertising, "
                + "no analytics and no tracking of any kind.",
                "The app talks to four places, each only when you use it. Your own "
                + "login goes to intervals.icu and Strava. Apple Maps loads while a "
                + "map is on screen. To name a new spot, it sends one rounded position.",
                // Release-only, deliberately: the beta and dev builds ship a watch app and
                // a Garmin link this body cannot name (only `items`, not `body`, is allowed
                // to branch by channel — see `HelpTopic.withItems`), and each of those does
                // ask for a location once, in one place (docs/release/privacy-labels.md
                // audit, 26 September 2026: this line used to say "never", full stop, which
                // was true on the App Store and false on both other channels).
                "On the App Store release, CleanJibe never asks for your location. Every "
                + "coordinate it draws was already inside a file you imported. The beta "
                + "and dev builds ask for one, in one place each. The privacy page says "
                + "where.",
            ],
            items: [
                .init(term: "Your intervals.icu key",
                      detail: "Kept in this iPhone's Keychain, never copied to iCloud and "
                          + "never written to a log. It goes to intervals.icu itself, "
                          + "encrypted, and nowhere else."),
                .init(term: "Treat it like a password",
                      detail: "It opens your intervals.icu account. Clear the field in "
                          + "Settings to remove it, or regenerate it in Developer Settings. "
                          + "The old key stops working at once."),
            ],
            links: [HelpLink(title: "Open \(Branding.site)/privacy",
                             url: URL(string: Branding.siteURL + "/privacy/")!)],
            related: [.shareFit, .libraryBackup]),

        HelpTopic(
            id: .engineVersion, section: .library, title: "Analysis engine version",
            summary: "When the analysis improves, your old sessions are worked out again.",
            body: [
                "The footer of a session shows which version of the analysis engine "
                + "produced its numbers.",
                "When a new version would give a session different numbers, CleanJibe works "
                + "it out again. It reads that session's own archived recording, the next "
                + "time you open it.",
                "Your original recording is never changed. Only the numbers are. Settings "
                + "→ Storage → Re-run analysis works them all out again at any time.",
            ],
            related: [.divergence]),

        // MARK: Something wrong?
        //
        // What to do when a way in, the watch or a number did not work — and, last, the
        // two ways to tell us.

        HelpTopic(
            id: .icuTroubleshooting, section: .somethingWrong, title: "When the sync does not work",
            summary: "The four things that actually go wrong, and the fix for each.",
            body: [
                "CleanJibe tells you what went wrong, because each problem has its own "
                + "fix. A rejected key means your key. An empty list usually means Garmin "
                + "is not connected yet. A network error is neither.",
            ],
            items: IcuSetupGuide.troubleshooting,
            links: [HelpLink(title: "Open intervals.icu", url: IcuSetupGuide.intervalsURL)],
            action: .openIcuSettings,
            related: [.icuSetup, .notifications]),

        // **The Connect IQ store queues an update and does not install it.** Jan's own
        // watches have done it, the fenix 5 Plus family does it most, and CleanJibe ships
        // often enough that a rider meets it here before he meets it anywhere else — so the
        // answer belongs beside "which watches work" rather than in a mail. Two fixes, in
        // the order that costs least: a restart and a sync, then the cable.
        HelpTopic(
            id: .watchUpdateStuck, section: .somethingWrong,
            title: "The watch update does not arrive",
            summary: "The store queued it without installing it. Restart the watch, "
                + "then sync.",
            body: [
                "Garmin's Connect IQ store sometimes queues an update without installing "
                + "it, most often on the fenix 5 Plus family.",
                "Restart the watch, then sync in Garmin Connect.",
                "If it still shows the old version, install it through Garmin Express over "
                + "the cable.",
                "We update CleanJibe often, so you may meet this more than with other apps.",
            ],
            related: [.whichWatch, .icuTroubleshooting, .engineVersion]),

        HelpTopic(
            id: .divergence, section: .somethingWrong,
            title: "When the watch and the phone show different numbers",
            summary: "This is normal, and the phone's number is the one to trust.",
            body: [
                "A session from the CleanJibe watch app brings the summary the watch worked "
                + "out while you rode. The watch does that in one pass, with very little "
                + "memory. The phone does the whole job again, and compares the two.",
                "The banner appears when foil time differs by more than 5 %. It appears for "
                + "a speed record off by more than 0.3 knots. It appears for a flight, turn "
                + "or attempt count off by more than one.",
                "The phone's number is the one to go by. Nothing is wrong with your "
                + "session. It only means the watch's live guess needs more work from us.",
            ],
            related: [.whichWatch, .engineVersion]),

        HelpTopic(
            id: .sendingFeedback, section: .somethingWrong, title: "Sending feedback",
            summary: "The app fills in build, phone and session. You write the "
                + "sentence. " + FeedbackInvitation.sentence,
            body: [
                // **The invitation is said once, and the summary is where it is said**
                // (Jan, dev 65). It opened the summary *and* this paragraph, one line
                // under the other, which reads as a slogan rather than as an answer. The
                // summary keeps it because that is the line the index shows.
                "One mail carries all of it. Name a missing column, a word that reads "
                + "wrong, or something you would rather the app did differently.",
                // **Three doors that exist** (15 Sep 2026). This sentence used to name
                // "Settings → Send feedback", a row deleted in build 58 — the app's own
                // Help sending the rider to a screen that no longer has it. The names come
                // from `FeedbackDoors` now, so a renamed door renames its instructions.
                FeedbackDoors.app + " opens the mail. So do \"" + FeedbackDoors.footer
                + "\" at the foot of every page and \"" + FeedbackDoors.share
                + "\" in the share sheet.",
                "The mail asks three questions, with a blank line under each.",
                "Nothing leaves the phone until you tap Send. It is Apple's own composer, "
                + "and it comes to us at " + FeedbackReport.recipient + ". We read every "
                + "mail. No part of CleanJibe sends anything by itself.",
            ],
            items: [
                .init(term: "What is already in the mail",
                      detail: "Under a line of dashes: app and engine version, tuned "
                          + "thresholds, your phone, iOS and locale. The paired watch is "
                          + "there, with how many sessions came in each way."),
                .init(term: "From a session",
                      detail: "It also carries that session's date, spot, discipline, "
                          + "duration, source class, engine stamp and identifier, with its "
                          + "share card attached."),
                .init(term: "Read it before you send",
                      detail: "Every line is there to read and to edit. If this phone has no "
                          + "mail account, the app hands the same text to whatever you do "
                          + "use."),
                .init(term: "If you are on the beta",
                      detail: "A screenshot taken inside the app offers "
                          + FeedbackDoors.testflight + ". That attaches the screenshot and "
                          + "the device logs. Take it for a crash."),
                .init(term: "About the watch app itself",
                      detail: "Anything about the watch app can go through its Connect IQ "
                          + "store listing. For a number that looks wrong, the mail here is "
                          + "the one worth sending."),
            ],
            // **The page offers the mail it describes** (Jan, dev 65). The three doors are
            // named because they are where the rider will start next time; the button is the
            // one he is standing in front of now, and it opens the same composer
            // (`FeedbackDoors.app`) rather than being a fourth door.
            action: .sendFeedback,
            related: [.divergence, .engineVersion, .sendSessionToDeveloper]),

        // The Share page's beta door (Jan, 21 September 2026). BETA in the app, so the
        // topic is bound to the beta channel and never reaches the release index
        // (docs/channels.md).
        HelpTopic(
            id: .sendSessionToDeveloper, section: .somethingWrong, channel: .beta,
            title: "Send a session to us",
            summary: "Mail us one session and your notes, so we can chase a wrong number.",
            body: [
                "We can only chase a wrong number on the recording that produced it. This "
                + "puts the recording, your notes and the app's details into one mail.",
                "The file holds your track, your heart rate and your times. We use it only "
                + "to improve the analysis, and we never publish it.",
                "You see the whole mail before it goes. Edit any line, delete any line, or "
                + "close it and nothing is sent.",
                "Open a session, tap Share, then Send this session to the developer.",
            ],
            related: [.shareFit, .divergence]),

        // MARK: What's new
        //
        // **The release notes, in the app.** Until 18 September 2026 they had three homes
        // and no source — two hand-typed strings in `ios/tools/testflight_publish.py`, a
        // stack of hand-written cards on cleanjibe.org/whats-new, and nothing at all on the
        // phone. A rider whose app changed under him on Tuesday had to go and find a
        // website to learn what it now did.
        //
        // The notes themselves are `WhatsNew`, generated from `docs/copy/whats-new.json` by
        // `web/tools/make_whats_new.py`, which writes the website's cards from the same
        // file; `testflight_publish.py` reads it for the *What to Test* of the build it
        // attaches. The topic carries an **action** rather than `items:` because a note is
        // a version, a day and the lines of that build, which is not a term and a detail.
        //
        // `.release`, and the *entries* are what the channel filters: a release build reads
        // the release notes, a beta build reads beta and release, the dev build reads the
        // lot (`WhatsNew.entries(for:)`). So the topic never names a build the reader could
        // not have.
        //
        // **Off the index since 26 September 2026** (`offIndex`). The menu opens the notes
        // itself, and the topic was a button onto that screen; it stays in the catalogue so
        // a deep link still opens it, and it no longer links out to the website's copy.
        HelpTopic(
            id: .whatsNew, section: .start,
            title: "What's new",
            summary: "What changed in the build you are holding, newest first.",
            body: [
                "Here is every release, with the day it shipped. The iPhone app and the "
                + "Garmin watch app number their versions differently. They also update on "
                + "different days.",
            ],
            action: .openWhatsNew),
    ]

    /// Fast lookup by identifier. Total by construction — see `topic(_:)`.
    private static let byID: [HelpTopicID: HelpTopic] =
        Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })

    /// **A topic whose items depend on the channel, resolved.**
    ///
    /// The catalogue is declared once, for the strictest reader, and every topic but one is
    /// the same sentences in every build. The exception is *Getting started*, whose items
    /// are the ways in: two of the five routes are beta doors (docs/channels.md), and a
    /// release build that listed them would be naming a door it does not have — while a
    /// beta build that left them out would be hiding the two doors its rider most needs
    /// (Jan, dev 65: the Apple routes never appeared, in any channel, because the kit was
    /// asked for the release's list and the kit cannot see `#if BETA`).
    ///
    /// So the *items* are rebuilt for the asking channel here, in one place, and every
    /// reading path below goes through it. The channel still comes from the app.
    private static func resolved(_ topic: HelpTopic, channel: HelpChannel) -> HelpTopic {
        switch topic.id {
        case .gettingStarted: topic.withItems(gettingStartedItems(for: channel))
        default: topic
        }
    }

    /// **The topic each way in is the signpost for.** `GettingStartedGuide` is generated
    /// from docs/guide/getting-started.json and knows nothing about topic ids, so the map is
    /// here, keyed by the route's id; a route with no entry gets no link.
    static let routeTopics: [String: HelpTopicID] = [
        "garmin": .icuSetup,
        "appleWatchApp": .appleWatchApp,
        "appleWorkoutApp": .appleWorkoutApp,
        "fit": .shareFromWatchApp,
        "strava": .stravaImport,
        "dryRun": .exampleSession,
        "sayHowItRead": .sendingFeedback,
    ]

    /// Getting started's items for one channel: the guide's routes and notes, each linked to
    /// the topic that owns its steps.
    static func gettingStartedItems(for channel: HelpChannel) -> [HelpTopic.Item] {
        (GettingStartedGuide.routes + GettingStartedGuide.notes)
            .filter { channel.has($0.channel) }
            .map { HelpTopic.Item(term: $0.title, detail: $0.summary,
                                  link: routeTopics[$0.id]) }
    }

    /// **The ids the merge of 26 September 2026 retired, and where each one lands now.**
    ///
    /// A `?` in the app names a `HelpTopicID` and cannot compile against a retired one; a
    /// written-down link cannot be recompiled, so `topic(id:)` reads this first. The web's
    /// help pages get the same map through docs/copy/help.json (`aliases` on each topic),
    /// so `/help/#help-foilPct` and `#/help/sourceClass` still arrive.
    public static let redirects: [String: HelpTopicID] = [
        "foilPct": .flights,
        "longestFlight": .flights,
        "distance": .flights,
        "touchdowns": .turnOutcomes,
        "icuPrivacy": .privacy,
        "sourceClass": .whichWatch,
    ]

    /// The retired ids that now open `id`, in a stable order (for the web export).
    public static func aliases(of id: HelpTopicID) -> [String] {
        redirects.filter { $0.value == id }.map(\.key).sorted()
    }

    /// The topic for a metric. Non-optional: the tests assert every `HelpTopicID` case is
    /// present, so a `?` button on a card can link without unwrapping.
    ///
    /// **Total in every channel** (docs/channels.md): `channel` decides what a topic's items
    /// *say*, never whether it resolves — a `?` on a card the build actually draws always
    /// opens, and so does a deep link written down in docs or in a mail. What a channel may
    /// browse to and search for is `indexTopics(channel:)`, which is a different question.
    ///
    /// `.release` is the default because it is the strictest reader: a caller that has not
    /// been told which build it is in gets the list that names no door. The app passes
    /// `ChannelFeatures.channel` (`AppChannel.channel`) in.
    public static func topic(_ id: HelpTopicID, channel: HelpChannel = .release) -> HelpTopic {
        guard let topic = byID[id] else {
            preconditionFailure("no help topic for " + id.rawValue
                                + ". HelpCatalog is incomplete")
        }
        return resolved(topic, channel: channel)
    }

    /// A topic by its written-down name, which may be one the merge retired.
    public static func topic(id: String, channel: HelpChannel = .release) -> HelpTopic? {
        (HelpTopicID(rawValue: id) ?? redirects[id]).map { topic($0, channel: channel) }
    }

    /// Every topic, resolved for one channel — the catalogue as that build reads it.
    public static func topics(channel: HelpChannel) -> [HelpTopic] {
        topics.map { resolved($0, channel: channel) }
    }

    /// Topics of one section, in catalogue order.
    public static func topics(in section: HelpSection) -> [HelpTopic] {
        topics.filter { $0.section == section }
    }

    /// Topics that are **in the catalogue but off the index** while the windsurf switch is off
    /// (Settings → Analysis → "Windsurf (experimental)").
    ///
    /// In the catalogue, deliberately: `topic(_:)` stays total, the `?` on a session that *is*
    /// analysed as windsurf still opens the page that explains it, and a deep link written
    /// down in docs or in a mail keeps working. Off the index because a browsable list is a
    /// menu — a topic on it is an offer, and this is a feature the rider has not accepted yet.
    static let behindWindsurfSwitch: Set<HelpTopicID> = [.windsurf]

    /// Topics that are in the catalogue but on **no** index, in any channel: What's new,
    /// whose screen the menu opens directly (26 September 2026). `topic(_:)` still
    /// resolves it; nothing lists, searches or links it.
    public static let offIndex: Set<HelpTopicID> = [.whatsNew]

    /// **Whether this build may show that topic at all** — the two filters, in one place.
    ///
    /// The channel is the hard one: a topic about a door the running build does not have is
    /// not a topic that is merely uninteresting, it is the app describing a screen the rider
    /// cannot reach (docs/channels.md). The windsurf switch is the soft one: the feature is
    /// compiled in, the rider has simply not accepted it yet.
    ///
    /// Deliberately *not* applied by `topic(_:)`, which stays total: a `?` on a card that the
    /// build does draw must always open, and a deep link written down in docs or in a mail
    /// must keep working. What this rules is what can be **browsed to, searched for and
    /// linked on** — the surfaces where a topic is an offer.
    public static func isListed(_ topic: HelpTopic, channel: HelpChannel,
                                windsurfEnabled: Bool = true) -> Bool {
        guard channel.has(topic.channel), !offIndex.contains(topic.id) else { return false }
        return windsurfEnabled || !behindWindsurfSwitch.contains(topic.id)
    }

    /// **What the Help index lists**, which is not quite what the catalogue holds.
    ///
    /// The filters the index applies, in one place, so the list and its search agree: a topic
    /// that cannot be browsed to must not be searchable either, or "windsurf" typed into the
    /// search field would advertise the switch the list is hiding — and "Health" typed into
    /// the App Store build would advertise a door that build does not have.
    ///
    /// `channel` defaults to `.dev` — everything — because the kit's own tests and the lab
    /// read the whole catalogue; the app always passes its own channel in.
    public static func indexTopics(channel: HelpChannel = .dev,
                                   windsurfEnabled: Bool = true) -> [HelpTopic] {
        topics.filter { isListed($0, channel: channel, windsurfEnabled: windsurfEnabled) }
            .map { resolved($0, channel: channel) }
    }

    /// **The "see also" list a topic may actually render.**
    ///
    /// A related link is a button, and a button onto a topic this build hides would be a
    /// dead end dressed as a next step — so the list is filtered by the same rule the index
    /// is, rather than by a second one that could drift away from it.
    public static func relatedTopics(of topic: HelpTopic, channel: HelpChannel,
                                     windsurfEnabled: Bool = true) -> [HelpTopic] {
        topic.related
            .map { Self.topic($0, channel: channel) }
            .filter { isListed($0, channel: channel, windsurfEnabled: windsurfEnabled) }
    }

    /// Sections that actually have topics, in declaration order.
    public static var sections: [HelpSection] {
        HelpSection.allCases.filter { !topics(in: $0).isEmpty }
    }

    /// Case-insensitive search over title, summary, body and items.
    ///
    /// Item **terms** are matched as well as details, which is what keeps "2 s", "500 m",
    /// "alpha" and "uncertified" finding the one *Speed records* page now that the windows
    /// are its items rather than seven topics of their own.
    ///
    /// `channel` resolves the topics the same way the index does, so a channel's search
    /// reads exactly the words that channel's pages say. It defaults to `.dev` —
    /// everything — because the kit's own tests read the whole catalogue; the app passes
    /// its own channel in and filters the result by `indexTopics` as before.
    public static func search(_ query: String, channel: HelpChannel = .dev) -> [HelpTopic] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let catalogue = topics(channel: channel)
        guard !needle.isEmpty else { return catalogue }
        return catalogue.filter { topic in
            if topic.title.lowercased().contains(needle) { return true }
            if topic.summary.lowercased().contains(needle) { return true }
            if topic.body.contains(where: { $0.lowercased().contains(needle) }) { return true }
            return topic.items.contains {
                $0.term.lowercased().contains(needle) || $0.detail.lowercased().contains(needle)
            }
        }
    }
}
