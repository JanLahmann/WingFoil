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

        public init(term: String, detail: String) {
            self.term = term
            self.detail = detail
        }
    }

    public let id: HelpTopicID
    public let section: HelpSection
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

    public init(id: HelpTopicID, section: HelpSection, channel: HelpChannel = .release,
                title: String, summary: String,
                body: [String], items: [Item] = [], image: HelpImage? = nil,
                links: [HelpLink] = [], action: HelpAction? = nil,
                related: [HelpTopicID] = []) {
        self.id = id
        self.section = section
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
public enum HelpSection: String, CaseIterable, Sendable, Identifiable {
    /// *Getting started*, first on purpose: it is not a metric and belongs under none of
    /// the nine sections below, and it is what "I just installed this" is looking for.
    /// The steps live **here**, in the app; cleanjibe.org/start is the mirror, named on
    /// the last line so it can be sent to somebody who has not installed anything yet.
    case gettingStarted
    case setup, foil, records, turns, takeoff, effort, conditions, sharing, quality

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gettingStarted: "Getting started"
        case .setup: "Getting set up"
        case .foil: "On the foil"
        case .records: "Speed records"
        case .turns: "Turns & losses"
        case .takeoff: "Takeoff & pumping"
        case .effort: "Effort"
        case .conditions: "Conditions"
        case .sharing: "Sharing"
        case .quality: "Where the numbers come from"
        }
    }

    public var symbol: String {
        switch self {
        case .gettingStarted: "book"
        case .setup: "link"
        case .foil: "figure.wave"
        case .records: "speedometer"
        case .turns: "arrow.triangle.turn.up.right.diamond"
        case .takeoff: "arrow.up.right"
        case .effort: "heart"
        case .conditions: "wind"
        case .sharing: "square.and.arrow.up"
        case .quality: "checkmark.seal"
        }
    }
}

/// Every explainable metric, as an enum so a `?` button cannot point at a missing topic.
public enum HelpTopicID: String, CaseIterable, Sendable, Identifiable {
    case gettingStarted
    case icuSetup, exampleSession, sendingFeedback, appleWatchApp, appleWorkoutApp
    case icuTroubleshooting
    case icuPrivacy, libraryBackup
    case stravaImport, shareFromWatchApp, whichWatch, phoneOnly
    case foilPct, flights, longestFlight, distance, mapLegend
    case recordSet, best2s, best10s, best5x10s, best500m, bestNm, alpha500, uncertified
    case turnTypes, turnOutcomes, turnSuccess, portStarboard, falls, touchdowns, glideOuts
    case takeoffAttempts, pumpsToTakeoff, pumpStrokes
    case heartRate
    case windAxis
    case shareCard, replayClip, shareFit, riderAttribution
    case sourceClass, divergence, engineVersion, windsurf

    public var id: String { rawValue }
}

public enum HelpCatalog {

    /// Every topic, in reading order. `topics` is the single source; the lookups below
    /// are derived from it, so a topic cannot exist in one and not the other.
    public static let topics: [HelpTopic] = [

        // MARK: Getting started
        //
        // First in the catalogue because it is first on the index, and first on the index
        // because it is what "I just installed this" is looking for — the library menu's own
        // first row opens it by name.
        //
        // **The steps live here, not on the web.** They used to be handed to
        // cleanjibe.org/start; Jan, 15 September 2026: a rider who has just installed the
        // app must not be sent to a browser for the instructions. The site is the mirror,
        // named on the last line so the same guide can be sent to somebody who has installed
        // nothing yet.
        //
        // **And it really is the same guide, since 15 September 2026.** The topic and the web
        // page were written separately, so "the same guide, on the web" was a claim rather
        // than a fact. Both are now cut from `docs/guide/getting-started.json` by
        // `web/tools/make_start.py`, through the generated `GettingStartedGuide`: the framing
        // below is its `framing`, the items are its routes and notes, and the web page adds
        // the numbered steps the app has no room for — which is what the last item now
        // promises. `GettingStartedGuideTests` fails if this topic stops matching it.
        //
        // One route per item, because a body cannot branch by channel and the routes do: the
        // two Apple doors are beta doors (docs/channels.md), so `items(for: .release)` leaves
        // them out here and they are topics of their own on `related`, which
        // `relatedTopics(of:channel:)` drops in the release. Nothing here says which build
        // the reader is holding.
        HelpTopic(
            id: .gettingStarted, section: .gettingStarted,
            title: "Getting started",
            summary: GettingStartedGuide.topicSummary,
            body: [GettingStartedGuide.framing],
            items: GettingStartedGuide.items(for: .release),
            // Built from `Branding.site` rather than typed out: the hostname is one constant
            // on this platform and a second copy of it is a second thing to forget.
            links: [HelpLink(title: "Open \(Branding.site)/start",
                             url: URL(string: Branding.siteURL + "/start")!)],
            related: [.icuSetup, .shareFromWatchApp, .stravaImport, .appleWatchApp,
                      .appleWorkoutApp, .exampleSession, .whichWatch, .sendingFeedback]),

        // MARK: Getting set up
        //
        // The steps are not written here: they come from `IcuSetupGuide`, which the
        // empty-library setup card renders too. One wording, two screens — and the Getting
        // started item above references them rather than repeating them.

        HelpTopic(
            id: .icuSetup, section: .setup, title: "Get set up with intervals.icu",
            summary: "Four steps, about five minutes, once.",
            body: [
                IcuSetupGuide.rationale,
                "Nothing is uploaded and nothing is changed on either side: CleanJibe lists "
                + "your activities, downloads the original recording of the watersport ones, "
                + "and analyses them on the phone.",
                // The one sentence that turns "a Garmin bridge" into "the way in for every
                // other brand", and what the recording those brands leave there is worth.
                "Polar, Suunto and Coros work this way too: their own apps sync to "
                + "intervals.icu, and CleanJibe syncs from there. What comes back decides how "
                + "much you get: a FIT gives the full analysis, a GPX or a speedless TCX "
                + "gives estimated, uncertified speed records.",
            ],
            items: IcuSetupGuide.steps.map {
                .init(term: "\($0.number). \($0.title)", detail: $0.detail)
            },
            links: [HelpLink(title: "Open intervals.icu", url: IcuSetupGuide.intervalsURL)],
            action: .openIcuSettings,
            related: [.exampleSession, .icuTroubleshooting, .icuPrivacy, .sourceClass]),

        HelpTopic(
            id: .exampleSession, section: .setup, title: "Look around with the example session",
            summary: "One real session ships with the app — load it before you connect anything.",
            body: [
                ExampleSession.blurb,
                "It is not your data, and CleanJibe treats it that way: badged EXAMPLE in the "
                + "list and on its own page, and left out of Records, Trends and the gear "
                + "rollups. Delete it with a swipe — this screen offers it again.",
                "It was recorded at \(ExampleSession.place) with the CleanJibe watch app, "
                + "every identifier removed. The accelerometer stream was left out (larger "
                + "than the rest of the app), so pump strokes and takeoff effort show as "
                + "unavailable.",
            ],
            image: HelpImage(asset: "help-session-detail",
                             caption: "The four rows at the top answer \"was that a good "
                                 + "session\"."),
            action: .loadExampleSession,
            related: [.icuSetup, .sourceClass, .uncertified, .riderAttribution]),

        // The two Apple doors, in the channel that has them (docs/channels.md). They sit
        // here rather than under "Where the numbers come from" because for a rider with no
        // Garmin they are not a footnote about data quality — they are the whole way in.
        HelpTopic(
            id: .appleWatchApp, section: .setup, channel: .beta,
            title: "Recording with the CleanJibe Apple Watch app",
            summary: "Record on your Apple Watch; the session comes to the phone by itself.",
            body: [
                "The watch app records the GPS track, your heart rate and the wrist "
                + "accelerometer at 50 Hz. Start it on the watch, ride, end the workout; the "
                + "session transfers to the phone while both are in range.",
                "Because the wrist is recorded, pump strokes and failed takeoff attempts are "
                + "analysed on the phone. Speed comes off the watch's own receiver, so the "
                + "records certify.",
            ],
            items: [
                .init(term: "Keep the wrist above water",
                      detail: "Salt water stops GPS dead. A wrist held under during a "
                          + "waterstart loses its fix, and CleanJibe marks the gap rather "
                          + "than sailing through it."),
                .init(term: "Let the workout finish",
                      detail: "The session is handed over once you end the workout. If it is "
                          + "not in the list yet, look again in a minute."),
            ],
            related: [.appleWorkoutApp, .sourceClass, .whichWatch, .exampleSession]),

        HelpTopic(
            id: .appleWorkoutApp, section: .setup, channel: .beta,
            title: "Recording with the Apple Workout app",
            summary: "No Garmin, no extra app: record on your Apple Watch and import from "
                + "Health.",
            body: [
                "Record a session with Apple's own Workout app and analyse it here — no "
                + "Garmin, no account, no cable, not even CleanJibe's own watch app.",
                "Apple Health has no wingfoil activity, so pick the closest one. CleanJibe "
                + "reads the workout as a wingfoil session because you asked it to.",
                "Then Import → Apple Health, allow CleanJibe to read workouts, and pick the "
                + "ones you want. After the first one, switch on \"Import new Health workouts "
                + "automatically\" and the next session is waiting when you open the app.",
                "Speed comes off the watch's own GPS receiver, so these speed records are "
                + "certified. Nothing records your wrist accelerometer, so there are no pump "
                + "strokes and no failed takeoff attempts.",
            ],
            items: [
                .init(term: "Pick Surfing or Water Sports",
                      detail: "Both are on by default, and Surfing is what CleanJibe's own "
                          + "watch app writes. Sailing works too — switch it on in Import → "
                          + "Apple Health."),
                .init(term: "Keep the wrist above water",
                      detail: "Salt water stops GPS dead. A wrist held under during a "
                          + "waterstart loses its fix; CleanJibe marks the gap rather than "
                          + "sailing through it."),
                .init(term: "Let the workout finish saving",
                      detail: "The route is written to Health when you end the workout, and "
                          + "the watch may take a minute to hand it over."),
                .init(term: "Nothing is uploaded",
                      detail: "CleanJibe reads the workouts you pick — their route and heart "
                          + "rate — and analyses them on your phone. It never reads anything "
                          + "else in Health."),
            ],
            related: [.appleWatchApp, .sourceClass, .uncertified, .icuSetup]),

        // The second cloud source (ADR-023). What it costs is said early, because a rider
        // who finds out afterwards that his speed records are uncertified has been told
        // too late.
        HelpTopic(
            id: .stravaImport, section: .setup, title: "Import from Strava",
            summary: "Connect once, then pick the sessions you want. Positions only, so "
                + "speed records are uncertified.",
            body: [
                "If your sessions are already on Strava, CleanJibe can list them and import "
                + "the ones you pick. CleanJibe only ever reads: it never writes, renames or "
                + "posts anything to your account.",
                "A Strava session shows everything that comes from the track: foil time, "
                + "flights, every turn verdict, the wind axis, the map. Strava hands over no "
                + "speed channel, so the speed records are marked uncertified, and nothing "
                + "recorded your wrist, so there are no pump strokes.",
                "If the same afternoon is also on intervals.icu, import it from there "
                + "instead: that is the original file off your watch, and those records "
                + "certify. Importing both is harmless — the same session is never added "
                + "twice.",
            ],
            items: [
                .init(term: "Connect",
                      detail: "Settings → Strava → Connect with Strava, or Import → Import "
                          + "from Strava…. Leave the private-activities box ticked or your "
                          + "\"Only you\" sessions will be missing."),
                .init(term: "Pick, or take everything new",
                      detail: "Tap the sessions you want, or use Import all new. Anything "
                          + "already in your library is marked and cannot be picked twice."),
                .init(term: "Which activities are offered",
                      detail: "Windsurf, Kitesurf, Surf and Workout by default; Sail and "
                          + "Stand-up paddling can be switched on. Anything named wing, "
                          + "foil, kite, surf or SUP is offered too."),
                .init(term: "Keep it automatic",
                      detail: "Once one session has come in this way, a toggle appears: "
                          + "CleanJibe then checks Strava whenever you open the app."),
                .init(term: "A long history takes its time",
                      detail: "Strava answers two hundred requests every fifteen minutes, so "
                          + "a first import of many seasons may ask you to come back "
                          + "shortly."),
                .init(term: "If connecting is refused",
                      detail: "Strava lets a new app connect a limited number of riders; "
                          + "that is nothing to do with your account. Menu → Support & ideas "
                          + "is the way to say so."),
                .init(term: "Disconnecting",
                      detail: "Settings → Strava → Disconnect Strava. The sessions you "
                          + "already imported stay in your library — they are yours now, "
                          + "analysed on this phone."),
            ],
            related: [.sourceClass, .uncertified, .icuSetup, .shareFromWatchApp, .whichWatch]),

        // The rider whose watch is neither a Garmin nor an Apple Watch. Every vendor path
        // carries the date it was checked against that vendor's own help page, and the one
        // app that cannot do it says so rather than being quietly left out.
        HelpTopic(
            id: .shareFromWatchApp, section: .setup,
            title: "Share from your watch app straight into CleanJibe",
            summary: "Polar, Suunto and COROS can hand a session to CleanJibe as a file. "
                + "Garmin's phone app cannot.",
            body: [
                "Every watch app can export a recording as a file, and CleanJibe reads .fit "
                + "files. Export the session as a FIT and pick CleanJibe from the share "
                + "sheet. If it is not in the row, Save to Files and open it from there.",
                "Which format, if you are asked: FIT, every time. A FIT carries the "
                + "receiver's own speed, so its records certify; a .gpx or a .tcx carries "
                + "positions only and its records are marked uncertified. Those two formats "
                + "open in the CleanJibe beta.",
                "Garmin Connect's phone app has no export at all, so Garmin owners have two "
                + "better routes: intervals.icu, or connect.garmin.com on a computer.",
            ],
            items: [
                .init(term: "Suunto — verified 13 Sep 2026",
                      detail: "Calendar → tap the workout → ⋯ top right → FIT. Then Save to "
                          + "Files, or pick CleanJibe from the share sheet. GPX is offered "
                          + "too; take FIT."),
                .init(term: "COROS — verified 13 Sep 2026",
                      detail: "Activities → tap the activity → ⋯ top right → Export (older "
                          + "versions: Export Data) → FIT. Then choose how to send it, which "
                          + "is the share sheet."),
                .init(term: "Polar — verified 13 Sep 2026, but not on the phone",
                      detail: "The Polar Flow app cannot export a file. flow.polar.com can: "
                          + "Diary → click the session → Export → FIT. A computer is the "
                          + "reliable way."),
                .init(term: "Garmin — verified 13 Sep 2026: no phone export",
                      detail: "Garmin Connect on the phone cannot export an activity file. "
                          + "On a computer: connect.garmin.com → Activities → the activity → "
                          + "gear icon → Export File."),
                .init(term: "Anything else",
                      detail: "If an app can produce a FIT, CleanJibe reads it — from "
                          + "AirDrop, Mail or Files. A ZIP of recordings works too: Import → "
                          + "FIT or ZIP…."),
            ],
            links: [
                HelpLink(title: "Suunto: exporting a FIT from the phone app",
                         url: URL(string: "https://www.suunto.com/Support/faq-articles/suunto-app/how-do-i-download-a-.fit-file-from-suunto-app-for-ios")!),
                HelpLink(title: "COROS: exporting workout data",
                         url: URL(string: "https://support.coros.com/hc/en-us/articles/360043975752-Exporting-Workout-Data-and-Uploading-to-3rd-Party-Apps")!),
                HelpLink(title: "Polar: exporting a session from Flow",
                         url: URL(string: "https://support.polar.com/en/export-training-sessions-flow")!),
                HelpLink(title: "Garmin: exporting data out of Garmin Connect",
                         url: URL(string: "https://support.garmin.com/en-US/?faq=W1TvTPW8JZ6LfJSfK512Q8")!),
            ],
            related: [.whichWatch, .icuSetup, .stravaImport, .sourceClass, .phoneOnly,
                      .uncertified]),

        // The rider who owns no watch at all. **It names no app and no other platform** —
        // App Store guideline 2.3.10 — so the answer is the *kind* of app and the file it
        // writes. Strava stays, because it is a door in this app rather than a
        // recommendation.
        HelpTopic(
            id: .phoneOnly, section: .setup, title: "Recording with a phone only",
            summary: "No watch at all: a tracker app in a pouch, and the session comes in "
                + "through Strava or as a file.",
            body: [
                "A phone records a GPS track as well as most watches do, and CleanJibe reads "
                + "it the same way: foil time, flights, every turn verdict, clean jibes, the "
                + "wind axis and the map.",
                "It is \(RecordingClass.c.name): \(RecordingClass.c.line)",
                "Where to put the phone: dry, still and pointing at the sky. A waterproof "
                + "pouch on the upper arm or high on the chest works; a pocket at hip height "
                + "spends half the session underwater. Start the recording on the beach.",
            ],
            items: [
                .init(term: "Strava, the route that needs no file",
                      detail: "Record in the Strava app and connect Strava here. Strava's "
                          + "phone app cannot export a file, so the import reads the "
                          + "activity out of your account instead."),
                .init(term: "Any GPS-logging app that writes a file",
                      detail: "Anything on your phone that records a track and writes a "
                          + ".fit or a .gpx works. Save the track, tap Share, pick CleanJibe "
                          + "— or open it from Files."),
                .init(term: "Which format, if you are offered a choice",
                      detail: "FIT. CleanJibe reads a .fit in every build, and a file with "
                          + "the receiver's own speed certifies its records. A .gpx or a "
                          + ".tcx opens in the CleanJibe beta."),
            ],
            related: [.stravaImport, .shareFromWatchApp, .whichWatch, .sourceClass,
                      .uncertified]),

        // One table, so "will my watch work" has one place to be answered instead of being
        // spread across five topics that each answer a third of it.
        HelpTopic(
            id: .whichWatch, section: .setup, title: "Which watches work with CleanJibe",
            summary: "All of them, one way or another — and here is exactly what each one "
                + "costs you.",
            body: [
                "CleanJibe analyses a recording, not a brand. Anything that can produce a GPS "
                + "track can be read, and a source that cannot answer a question leaves that "
                + "number blank and says why.",
                "Two things separate the rows. **Certified speed** means the file carried the "
                + "receiver's own speed; without it, speed is worked out from positions and "
                + "every record is marked uncertified.",
                "**Pump strokes and takeoff effort** need a wrist accelerometer recorded "
                + "during the session, which only the CleanJibe watch apps do.",
            ],
            items: [
                .init(term: "Garmin, with the CleanJibe watch app",
                      detail: "Everything: flights, turns, certified speed records, the wind "
                          + "axis, pump strokes, failed takeoff attempts and "
                          + "accelerometer-confirmed touchdowns. Sessions arrive through "
                          + "intervals.icu."),
                .init(term: "Garmin, with Garmin's own profile or another app",
                      detail: "Everything except pump strokes and takeoff effort. Speed "
                          + "records certify. Sessions come in through intervals.icu, or as "
                          + "a FIT from connect.garmin.com on a computer."),
                .init(term: "Apple Watch",
                      detail: "Record with Apple's Workout app and import through Strava or "
                          + "intervals.icu. The beta adds two doors: Apple Health, and the "
                          + "CleanJibe watch app, which records the wrist too."),
                .init(term: "Polar, Suunto, COROS and the rest",
                      detail: "Connect the watch to intervals.icu, or export one session "
                          + "from the phone app as a FIT and share it in. A FIT certifies "
                          + "its records; a .gpx does not."),
                .init(term: "Anything that ends up on Strava",
                      detail: "Connect Strava and pick the sessions. Strava hands over "
                          + "positions, altitude and heart rate but no speed channel, so "
                          + "those records are uncertified."),
                .init(term: "A phone in a pocket, or no watch at all",
                      detail: "Any GPS-logging app works: record, then import through Strava "
                          + "or share the file in. Positions only, so uncertified records — "
                          + "the flights, turns and map are all there."),
            ],
            related: [.shareFromWatchApp, .icuSetup, .appleWatchApp, .appleWorkoutApp,
                      .stravaImport, .phoneOnly, .sourceClass, .uncertified]),

        HelpTopic(
            id: .icuTroubleshooting, section: .setup, title: "When the sync does not work",
            summary: "The four things that actually go wrong, and the fix for each.",
            body: [
                "Every failure CleanJibe can see is reported as a cause, because the fix "
                + "differs: a rejected key is your key, an empty list is usually Garmin not "
                + "connected yet, and a network error is neither.",
            ],
            items: IcuSetupGuide.troubleshooting,
            links: [HelpLink(title: "Open intervals.icu", url: IcuSetupGuide.intervalsURL)],
            action: .openIcuSettings,
            related: [.icuSetup, .icuPrivacy]),

        HelpTopic(
            id: .icuPrivacy, section: .setup, title: "Where your API key is kept",
            summary: "In the iOS Keychain, on this phone, and sent only to intervals.icu.",
            body: [
                IcuSetupGuide.privacyNote,
                "The key is a personal read/write token for your intervals.icu account, so "
                + "treat it like a password. Clear the field in Settings to remove it, or "
                + "regenerate it in Developer Settings — the old key stops working the "
                + "moment you do.",
            ],
            related: [.icuSetup, .icuTroubleshooting]),

        // The topic that exists because of the one thing this app cannot get back for you.
        // The recordings are recoverable — intervals.icu still has them — but what you
        // *called* a session, whose it was, which wing it was on and which sessions you
        // deliberately threw away live in one database on one phone and nowhere else.
        //
        // The Settings footer (`LibraryBackupSection`) and this topic say the same thing
        // once each: the footer short, this one complete. Neither repeats the other's
        // paragraph.
        HelpTopic(
            id: .libraryBackup, section: .setup, title: "Backing up your library",
            summary: "A new phone carries everything by itself. A fresh start needs a file.",
            body: [
                "Setting up a new iPhone from this one carries your library across, and so "
                + "does an iCloud backup. Settings → Library backup is for the case neither "
                + "covers: a phone set up as new, or the app deleted and installed again.",
                "The file holds every recording you have imported **and** the things nothing "
                + "else can bring back: what you called each session, its caption, whose it "
                + "was, the gear on it, your spot names, and the sessions you deleted on "
                + "purpose.",
                "Restoring is additive: sessions already in your library keep their own "
                + "analysis, details you changed since are left alone, and restoring the "
                + "same file twice does nothing the second time. Sessions you deleted after "
                + "the backup stay deleted.",
            ],
            items: [
                .init(term: "Save the file yourself",
                      detail: "Back up library writes a temporary file. Save… puts it in "
                          + "Files, iCloud Drive or on a Mac; CleanJibe does not keep a "
                          + "copy."),
                .init(term: "Your own recordings, nothing stripped",
                      detail: "The .fit and .gpx files inside are exactly as they arrived. "
                          + "Unlike a session you send a friend, nothing is removed: this "
                          + "file is for you, not for sharing."),
                .init(term: "How big it will be",
                      detail: "A session recorded with the CleanJibe watch app carries a "
                          + "100 Hz accelerometer stream, about 95 % of its size. The app "
                          + "estimates the total before it starts."),
                .init(term: "A newer backup",
                      detail: "A backup from a newer version of CleanJibe is refused rather "
                          + "than partly read: update the app and try again. An older one is "
                          + "brought up to date."),
            ],
            related: [.icuSetup, .riderAttribution, .shareFit, .icuPrivacy]),

        // Last in "Getting set up": the six topics above it are how a session gets in, and
        // this is what to do when one of them did not work.
        HelpTopic(
            id: .sendingFeedback, section: .setup, title: "Sending feedback",
            summary: "The app writes down which build, which phone and which session. "
                + "You write the sentence. \(FeedbackInvitation.sentence)",
            body: [
                "\(FeedbackInvitation.sentence) A missing column, a word that reads wrong, "
                + "something you would rather the app did differently: the same mail carries "
                + "all of it.",
                "Menu → Support & ideas, Settings → Send feedback and the share sheet's "
                + "\"Report a problem with this session…\" all open the same mail, with "
                + "three questions and a blank line under each.",
                "Nothing leaves the phone until you tap Send. It is Apple's own composer, "
                + "the address is \(FeedbackReport.recipient), and no part of CleanJibe "
                + "sends anything by itself — there is no CleanJibe server to send it to.",
            ],
            items: [
                .init(term: "What is already in the mail",
                      detail: "Under a line of dashes: app and engine version, any tuned "
                          + "thresholds, your phone, iOS and locale, the paired watch, and "
                          + "how many sessions came in by which door."),
                .init(term: "From a session",
                      detail: "It also carries that session's date, spot, discipline, "
                          + "duration, source class, engine stamp and identifier, with its "
                          + "share card attached."),
                .init(term: "Read it before you send",
                      detail: "Every line is there to read and to edit. If this phone has no "
                          + "mail account, the app hands the same text to whatever you do "
                          + "use."),
                .init(term: "If you are on the beta",
                      detail: "A screenshot taken inside the app offers Send Beta Feedback, "
                          + "which attaches the screenshot and the device logs — the route "
                          + "for a crash."),
                .init(term: "About the watch app itself",
                      detail: "Anything about the watch app can go through its Connect IQ "
                          + "store listing. For a number that looks wrong, the mail here is "
                          + "the one worth sending."),
            ],
            related: [.sourceClass, .engineVersion, .divergence]),

        // MARK: On the foil

        HelpTopic(
            id: .foilPct, section: .foil, title: "Foil time / foil %",
            summary: "How much of the session you spent actually flying.",
            body: [
                "A flight starts when your speed stays above the entry threshold "
                + "(12 km/h by default) for 2 seconds, and ends when it stays below the exit "
                + "threshold (8 km/h) for 3 seconds. Start and end are backdated to the "
                + "first qualifying sample.",
                "\"On foil\" is that flying time divided by timer time — the total minus any "
                + "stretch where the recording stopped or the GPS dropped out. Taxiing, "
                + "swimming and the drift back upwind count against it; a gap in the "
                + "recording does not.",
                "Anything under 5 seconds is not counted as a flight. \"Foil time\" is the "
                + "number of minutes; \"on foil\" is the share of the session they are.",
            ],
            related: [.flights, .longestFlight, .sourceClass]),

        HelpTopic(
            id: .flights, section: .foil, title: "Flights",
            summary: "How many separate times you got up and stayed up.",
            body: [
                "One flight is one continuous stretch above the entry threshold, lasting at "
                + "least 5 seconds. A brief touchdown does not split a flight: the exit needs "
                + "3 seconds below the exit speed, so a one- or two-second tap of the water "
                + "stays inside it.",
                "The flight count answers \"how many times did I have to get up again\"; the "
                + "touchdown count answers \"how clean was it\".",
            ],
            related: [.foilPct, .touchdowns, .takeoffAttempts]),

        HelpTopic(
            id: .longestFlight, section: .foil, title: "Longest flight",
            summary: "Your best single stretch, in time and in distance.",
            body: [
                "The longest flight by duration, with the distance covered during it shown "
                + "underneath.",
                "Both come from the same segmentation as foil %, so a session with a lot of "
                + "short flights and a session with one long one can share a foil %.",
            ],
            related: [.foilPct, .flights]),

        HelpTopic(
            id: .distance, section: .foil, title: "Distance",
            summary: "Distance over the water, integrated from the speed channel.",
            body: [
                "Distance is integrated from the device's Doppler speed rather than summed "
                + "from GPS positions: position noise inflates a distance total badly at low "
                + "speed, and Doppler does not.",
                "It covers the whole session — flying, taxiing and drifting.",
            ],
            related: [.sourceClass]),

        // The legend used to be printed under the chips on every visit to every session —
        // three grey paragraphs of reference material (app-ui-review.md §1.2). Reference
        // material belongs behind the `?` the rest of the page already uses.
        HelpTopic(
            id: .mapLegend, section: .foil, title: "Reading the map",
            summary: "What the chips, the colours, the arrows and the dots mean.",
            body: [
                "Every chip under the map is a switch. Tapping one hides that category on "
                + "the map and in the speed chart at the same time — the two are one reading "
                + "of the same session.",
                "A hidden chip stays in place, struck through, and \"show all\" brings "
                + "everything back. A category this session has none of is not a switch. The "
                + "three rows are the track, the events on it, and the map's own controls.",
                "Tap the track to move the replay playhead; tap a mark, or a flown stretch, "
                + "for its own facts.",
            ],
            items: [
                .init(term: "The track",
                      detail: "Tinted by phase: teal where you were flying, grey where you "
                          + "were not. Small chevrons along it point the way you were "
                          + "riding."),
                .init(term: "The dots",
                      detail: "Verdicts on one ladder: green flew through, orange touched "
                          + "down, red fell in, grey a course change that is no verdict at "
                          + "all."),
                .init(term: "Solid or hollow",
                      detail: "Fill carries the channel rather than a second colour: solid "
                          + "is a maneuver's outcome, hollow is a straight-line flight end "
                          + "that no turn explains."),
                .init(term: "A star",
                      detail: "A clean jibe, in a green of its own, taking the place of that "
                          + "jibe's dot. It needs both its chips: hide the outcome and the "
                          + "star goes with it."),
                .init(term: "Arrows, not dots",
                      detail: "Takeoffs: an up-arrow got you up, a red u-turn is an attempt "
                          + "that did not. One chip hides both halves."),
                .init(term: "Bands and drops",
                      detail: "The indigo bands are pump bursts; the cyan drop is the "
                          + "barometer seeing your wrist go under."),
            ],
            image: HelpImage(asset: "help-map-layers",
                             caption: "The chips above the map turn each layer on and off — "
                                 + "here with the fell-in marks hidden."),
            related: [.foilPct, .turnOutcomes, .takeoffAttempts]),

        // MARK: Speed records

        HelpTopic(
            id: .recordSet, section: .records, title: "The GP3S record set",
            summary: "The standard speedsurfing windows, computed the standard way.",
            body: [
                "These are the windows the GPS speedsurfing world uses, so your numbers are "
                + "comparable with the ones people post.",
                "2 s and 10 s peaks, the mean of the best five separate 10 s runs, 100 m / "
                + "250 m / 500 m / 1 nautical mile, one hour, and alpha 500.",
                "All are computed on the device's Doppler speed, with fractional samples "
                + "interpolated at the window edges, so the result does not depend on whether "
                + "your watch recorded at 1 Hz or 4 Hz. No minimum-speed filter is applied.",
                "A window never spans a recording gap. Tap a record card to see where on the "
                + "track and on the speed trace it happened.",
            ],
            related: [.best2s, .best5x10s, .alpha500, .uncertified]),

        HelpTopic(
            id: .best2s, section: .records, title: "Best 2 s",
            summary: "Your peak speed, averaged over 2 seconds.",
            body: [
                "The fastest 2-second stretch of the session. A single-sample maximum is "
                + "noise; two seconds is a real burst.",
                "This is the number most riders compare, and the one the Records screen "
                + "tracks as a personal best over time.",
            ],
            related: [.recordSet, .best10s, .uncertified]),

        HelpTopic(
            id: .best10s, section: .records, title: "Best 10 s",
            summary: "The fastest 10-second run — a burst you had to hold.",
            body: [
                "Ten seconds is long enough that luck and a single gust cannot carry it: you "
                + "have to be lit up and stay lit up. It is usually 1–3 knots below your 2 s.",
            ],
            related: [.recordSet, .best2s, .best5x10s]),

        HelpTopic(
            id: .best5x10s, section: .records, title: "5 × 10 s",
            summary: "The mean of your best five separate 10-second runs.",
            body: [
                "The five 10-second windows must not overlap, so this cannot be one long run "
                + "counted five times. It rewards consistency across the session rather than "
                + "a single lucky reach, which is why the speedsurfing world uses it as a "
                + "session's headline number.",
            ],
            related: [.recordSet, .best10s]),

        HelpTopic(
            id: .best500m, section: .records, title: "Best 500 m",
            summary: "Your fastest half-kilometre.",
            body: [
                "The fastest continuous 500 metres of track, measured on integrated Doppler "
                + "distance rather than straight-line distance — so a slightly curved run "
                + "still counts, and the number is not flattered by cutting the corner.",
            ],
            related: [.recordSet, .bestNm, .alpha500]),

        HelpTopic(
            id: .bestNm, section: .records, title: "Best 1 NM",
            summary: "Your fastest nautical mile (1852 m).",
            body: [
                "A long-distance window: on most spots it needs more than one leg, so it "
                + "measures how well you keep speed through your turns as much as your top end.",
            ],
            related: [.recordSet, .best500m, .turnSuccess]),

        HelpTopic(
            id: .alpha500, section: .records, title: "Alpha 500",
            summary: "500 m that comes back to where it started — speed plus a turn.",
            body: [
                "An alpha run is a 500-metre stretch whose end point is within 50 m of its "
                + "start point. You cannot do it in a straight line: it has to contain a "
                + "gybe, and you have to carry speed through it.",
                "It is the one record that measures your turns as well as your speed.",
            ],
            related: [.recordSet, .best500m, .turnOutcomes]),

        HelpTopic(
            id: .uncertified, section: .records, title: "\"Uncertified\"",
            summary: "The recording could not prove the speed was Doppler.",
            body: [
                "Speed records are only trustworthy when they come from the receiver's "
                + "Doppler speed channel. A recording that carries positions but no speed "
                + "channel — every GPX, and the occasional converted export — gets its speed "
                + "differentiated from positions, which is noisier and can read high.",
                "Those records are still shown — they are still your session — but labelled "
                + "uncertified so you never post one as a personal best by accident. Nothing "
                + "recorded by your watch directly is affected.",
            ],
            related: [.sourceClass, .recordSet]),

        // MARK: Turns & losses

        HelpTopic(
            id: .turnTypes, section: .turns, title: "Tacks, jibes and course changes",
            summary: "What counts as a maneuver, and what is just a change of direction.",
            body: [
                "A turn is detected from your course: at least 60° of net heading change "
                + "within 8 seconds, containing a peak rate of 25°/s, while you are on the "
                + "foil or within 3 s of it.",
                "It must also have carved a real arc — at least 12 m of path at an effective "
                + "radius of at least 6 m — which separates a maneuver from a rider spinning "
                + "around beside the board.",
                "What kind of turn it was depends on the wind axis:",
            ],
            items: [
                .init(term: "Jibe", detail: "Your course crosses the wind axis through downwind."),
                .init(term: "Tack", detail: "Your course crosses the wind axis through upwind."),
                .init(term: "Bear-away / round-up",
                      detail: "A real course change that never crosses the axis. Counted "
                          + "separately and excluded from the tack/jibe tallies — it is not a "
                          + "maneuver you either made or blew."),
                .init(term: "Turn",
                      detail: "A detected maneuver on a session where the wind axis was too "
                          + "uncertain to name it. Still counted, just unnamed."),
            ],
            related: [.windAxis, .turnOutcomes, .portStarboard]),

        HelpTopic(
            id: .turnOutcomes, section: .turns, title: "Turn outcomes — flew / touchdown / fell",
            summary: "What actually happened to the foil in the turn.",
            body: [
                "Every turn gets one of three outcomes. The judgement runs from the turn "
                + "start until you are demonstrably flying again — speed back above 70 % of "
                + "your entry speed for 2 seconds — capped at 12 seconds.",
                "That matters: a jibe exited at marginal speed can bleed off for 6–12 seconds "
                + "before the foil stalls, and that mush-out is the jibe's fault. A jibe you "
                + "power out of closes its window in a second or two.",
                "Three channels are read inside it: speed always, the barometer (a wrist "
                + "under water reads as a huge altitude drop), and, on a CleanJibe watch "
                + "recording, the accelerometer.",
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
            ],
            image: HelpImage(asset: "help-turn-list",
                             caption: "Every turn, with the verdict and the evidence behind "
                                 + "it."),
            related: [.turnSuccess, .falls, .glideOuts]),

        HelpTopic(
            id: .turnSuccess, section: .turns, title: "Clean jibes",
            summary: "A jibe you fly all the way through without losing much speed.",
            body: [
                "**Flew through** is how a turn ended: you never lost the foil, from the turn "
                + "start until you were flying again. **Clean** is a jibe that flew through "
                + "*and* held its speed.",
                "Holding the speed means two things: your minimum speed through the turn "
                + "stays at or above 70 % of your entry speed, and you never drop below the "
                + "foil exit speed.",
                "So clean is a strict subset of flew through: a jibe that held its speed "
                + "round the turn and then lost the foil coming out is not clean. (Before "
                + "engine 0.12.0 it counted.)",
                "Clean is a jibe word: a tack has no clean reading to carry, so the Tacks "
                + "card reports only how its tacks ended.",
            ],
            items: [
                .init(term: "Flew through",
                      detail: "The outcome: you kept the foil through the turn and through "
                          + "the recovery out of it. No touchdown, no swim."),
                .init(term: "Clean",
                      detail: "A jibe that flew through and held at least 70 % of its "
                          + "entry speed. The strict one, and the one CPH counts."),
                .init(term: "Dry",
                      detail: "You did not fall in. A touchdown still counts as dry, which "
                          + "is why JPH (dry jibes per hour) is never below CPH."),
                .init(term: "Score",
                      detail: "The share of your entry speed you held through the turn, "
                          + "0–100. The evidence behind \"clean\", printed beside every "
                          + "turn."),
            ],
            related: [.turnOutcomes, .alpha500]),

        HelpTopic(
            id: .portStarboard, section: .turns, title: "Port / starboard",
            summary: "Which tack you were on going in — and which side you avoid.",
            body: [
                "The side is read from your wind angle before the turn. A 50/50 split means "
                + "you work both sides equally; a lopsided split is the tack you quietly stop "
                + "choosing, which is usually the one worth practising.",
                "The Trends screen plots this over time as \"% port\", with 50 % marked.",
            ],
            related: [.turnTypes, .windAxis]),

        HelpTopic(
            id: .falls, section: .turns, title: "Falls",
            summary: "Every fall, split into the ones in turns and the ones in a straight line.",
            body: [
                "A fall means you stopped for more than 5 seconds, or the barometer caught "
                + "your wrist going under.",
                "The split matters: falls in turns are a maneuver problem, falls in a "
                + "straight line are a gust, a ventilation or a tip catching. Each fall is "
                + "counted once — a fall inside a turn's window belongs to that turn.",
            ],
            related: [.turnOutcomes, .touchdowns, .glideOuts]),

        HelpTopic(
            id: .touchdowns, section: .turns, title: "Touchdowns",
            summary: "Brief losses of the foil, in turns and in a straight line.",
            body: [
                "You came off the foil but were making way again within a few seconds, or you "
                + "pumped straight back up. A short touchdown inside a flight does not break "
                + "the flight.",
            ],
            related: [.turnOutcomes, .falls, .flights]),

        HelpTopic(
            id: .glideOuts, section: .turns, title: "Glide-outs",
            summary: "Flights that ended without ever stopping.",
            body: [
                "The flight ended and you kept moving — you settled onto the board and taxied "
                + "on, or you chose to stop riding. No stop was ever measured, so this is not "
                + "counted as a loss.",
                "Flight ends where the recording itself stopped are reported as unknown and "
                + "excluded from every tally: there is no evidence there.",
            ],
            related: [.falls, .touchdowns, .sourceClass]),

        // MARK: Takeoff & pumping

        HelpTopic(
            id: .takeoffAttempts, section: .takeoff, title: "Attempts & success rate",
            summary: "How often you pumped — including the times you did not get up.",
            body: [
                "Attempts = flights + failed attempts. A pumping burst counts as a failed "
                + "attempt when no flight starts within 10 seconds of your last stroke; "
                + "bursts closer together than that are chained into one attempt.",
                "No summary built from flights alone can contain this: a session where you "
                + "got up 20 times out of 22 and one where you got up 20 out of 40 look "
                + "identical otherwise.",
                "It needs the wrist accelerometer, which only the CleanJibe watch app "
                + "records. Without it your failures are invisible, so the success rate is "
                + "shown as unknown rather than a flattering 100 %.",
            ],
            related: [.pumpsToTakeoff, .sourceClass, .heartRate]),

        HelpTopic(
            id: .pumpsToTakeoff, section: .takeoff, title: "Pumps to takeoff",
            summary: "How many strokes each flight cost you.",
            body: [
                "The takeoff run is the stretch of rising speed before the flight plus the "
                + "pump burst that led into it, whichever started earlier — so the count is "
                + "the strokes of the effort that actually produced the flight.",
                "Takeoffs under 3 strokes are counted as free: you got up on the wind alone. "
                + "That is a fact about the conditions, so free takeoffs are kept out of the "
                + "averages and reported separately.",
                "Runs the recording cut short are excluded from the averages but still count "
                + "as successes — the flight happened, only its cost is unknown.",
            ],
            related: [.takeoffAttempts, .pumpStrokes, .heartRate]),

        HelpTopic(
            id: .pumpStrokes, section: .takeoff, title: "Pump strokes",
            summary: "Every stroke in the session, and the ones you did in flight.",
            body: [
                "Strokes are detected from the wrist accelerometer, using the magnitude only, "
                + "so it does not matter how your wrist was rotated.",
                "In-flight strokes are pumping to hold or extend a glide rather than to get up "
                + "— a different kind of work, so they are counted separately.",
            ],
            related: [.pumpsToTakeoff, .sourceClass]),

        // MARK: Effort

        HelpTopic(
            id: .heartRate, section: .effort, title: "Heart rate — cost and coverage",
            summary: "What an attempt costs in heartbeats, and when that can be trusted.",
            body: [
                "HR cost is the rise from your baseline just before an effort to the peak "
                + "that follows. The baseline is the median of the 10 seconds ending at the "
                + "start of the takeoff run.",
                "The peak is searched 30 seconds forward, because an optical wrist sensor "
                + "trails effort by 10–20 seconds. Negative values are reported rather than "
                + "hidden: \"still recovering when you started\" is a different fact from "
                + "\"this cost nothing\".",
                "The card does not appear on a session whose recording has no usable heart "
                + "rate. Nothing here is estimated when the sensor was silent.",
            ],
            items: [
                .init(term: "Coverage",
                      detail: "The share of a window carried by plausible (30–220 bpm), "
                          + "unstuck samples no more than 10 seconds apart. Below 60 % "
                          + "coverage no number is produced."),
                .init(term: "Why it drops out",
                      detail: "A wrist sensor under a wetsuit sleeve in cold water drops out "
                          + "and sticks, and a made-up average is worse than a missing one."),
                .init(term: "The fatigue chart",
                      detail: "Twenty-minute bins, each showing what its takeoffs cost, with "
                          + "the share of attempts that got up underneath. Bins with nothing "
                          + "usable are shaded, not drawn as zero."),
                .init(term: "Read the cost bars with the baseline note",
                      detail: "A rise measured against a baseline that has drifted upward "
                          + "gets smaller as you tire. A shrinking late cost is not evidence "
                          + "that the takeoffs got easier."),
            ],
            related: [.takeoffAttempts, .pumpsToTakeoff, .sourceClass]),

        // MARK: Conditions

        HelpTopic(
            id: .windAxis, section: .conditions, title: "Wind axis & confidence",
            summary: "The wind direction estimated from how you actually sailed.",
            body: [
                "No weather station is involved. The estimate comes from your own track: your "
                + "foiling course headings are collected into a weighted histogram, the two "
                + "dominant reaching directions are found, and the wind axis is the line that "
                + "bisects them.",
                "That gives an axis but not a side. The tie is broken by the no-go zone: of "
                + "the two ends, the one you sailed almost nothing within ±45° of is where "
                + "the wind came from.",
                "Confidence combines how cleanly the two reaches separate with how decisive "
                + "the no-go zone was. Below 50 % the axis is still shown, but your turns "
                + "stay unnamed \"turns\" rather than tacks and jibes. A wind direction you "
                + "set on the watch always wins.",
            ],
            related: [.turnTypes, .portStarboard]),

        // MARK: Sharing
        //
        // The rest of this catalogue explains *numbers*. This section explains *doors* —
        // four things a rider will never find by tapping around, because each of them is one
        // button on one sheet. What leaves the phone is the half somebody is deciding about.

        HelpTopic(
            id: .shareCard, section: .sharing, title: "Share cards",
            summary: "One picture of a session, made to post.",
            body: [
                "Any session can become a card: the track, the numbers that matter, and a "
                + "line saying where the analysis came from. Pick portrait, square or "
                + "landscape, and Complete or Lean. A photo from your library can go behind "
                + "it.",
                "Or turn on the map background and the track is drawn over the water you "
                + "sailed. That one needs a connection; without one the card comes out plain.",
                "The card is made on your phone and goes nowhere until you send it.",
            ],
            image: HelpImage(asset: "help-share-composer",
                             caption: "Pick a shape, pick how much detail, send it."),
            related: [.replayClip, .shareFit]),

        HelpTopic(
            id: .replayClip, section: .sharing, title: "Replay clips",
            summary: "Record the replay as a video.",
            body: [
                "The replay plays a session back on its own track, with a commentary that "
                + "follows what is happening. Scrub to the part worth watching, then record "
                + "it as a video.",
                "Ask for a 10, 25 or 60-second clip and the app solves the playback rate to "
                + "land on it, or take \"full detail\" and let the session run as long as it "
                + "runs.",
                "The frame is yours too: 9:16 for a story, 1:1 for a post, 16:9 for a chat, "
                + "or the whole screen. Photos from that afternoon can be spliced in.",
                "You can lay your own music under it, trimmed or looped and faded at both "
                + "ends. Nothing is uploaded: the video is rendered on the phone.",
            ],
            image: HelpImage(asset: "help-replay",
                             caption: "The replay running: the marker on the track, the "
                                 + "clock, and the commentary calling what just happened."),
            related: [.shareCard, .mapLegend]),

        HelpTopic(
            id: .shareFit, section: .sharing, title: "Sending a session to a friend",
            summary: "Share the original recording, stripped of anything identifying.",
            body: [
                "You can share the original .fit file of any session. Everything identifying "
                + "— the watch serial, your rider profile, your lifetime totals — is removed "
                + "first; the ride itself is untouched, so the analysis your friend gets is "
                + "identical to yours.",
                "They can open it in CleanJibe, or drop it into the free browser analyzer at "
                + "\(Branding.site) without installing anything.",
            ],
            links: [HelpLink(title: "Open the browser analyzer",
                             url: URL(string: Branding.siteURL)!)],
            related: [.riderAttribution, .shareCard]),

        HelpTopic(
            id: .riderAttribution, section: .sharing, title: "Sessions someone else rode",
            summary: "A friend's session is shown in full but kept out of your records.",
            body: [
                "When you import a file, CleanJibe asks whose session it is. A friend's "
                + "session is saved and shown in full — map, replay, every turn — but stays "
                + "out of your records, trends and gear totals.",
                "Their fast run never becomes your personal best. The name you give is stored "
                + "on your phone only.",
            ],
            related: [.shareFit, .exampleSession]),

        // MARK: Where the numbers come from

        // The question a rider actually arrives with — *do I need the watch app?* The
        // letters a/b/c survive in the code (`SessionRow.sourceClass`) because the engine
        // and the fixtures are full of them; on screen they are always the letter *and* the
        // thing, in the spelling cleanjibe.org and the Import screen use.
        HelpTopic(
            id: .sourceClass, section: .quality,
            title: "What your recording can and cannot show",
            summary: "Everything works from any Garmin recording. Two things need the "
                + "CleanJibe watch app.",
            body: [
                "CleanJibe reads whatever your watch put in the file, and every metric "
                + "degrades gracefully rather than failing or guessing. There are four cases, "
                + "with the names cleanjibe.org and the Import screen print.",
                "A GPX never carries a speed channel and a TCX sometimes does; Strava hands "
                + "over positions and no speed channel either, so a Strava import belongs in "
                + "the last row.",
            ],
            items: [
                .init(term: RecordingClass.a.name, detail: RecordingClass.a.line),
                .init(term: RecordingClass.b.name,
                      detail: RecordingClass.b.line + " Garmin's own profile, another "
                          + "Connect IQ app, Apple's Workout app."),
                .init(term: RecordingClass.bPlus.name, detail: RecordingClass.bPlus.line),
                .init(term: RecordingClass.c.name, detail: RecordingClass.c.line),
            ],
            related: [.uncertified, .divergence, .engineVersion, .whichWatch,
                      .stravaImport, .phoneOnly]),

        HelpTopic(
            id: .divergence, section: .quality,
            title: "When the watch and the phone show different numbers",
            summary: "Normal, expected, and the phone's number is the right one.",
            body: [
                "A session from the CleanJibe watch app carries the summary the watch "
                + "computed live, in one forward pass with no memory to spare. The phone "
                + "recomputes the same session properly, and the two are compared.",
                "The banner appears when foil time differs by more than 5 %, any speed record "
                + "by more than 0.3 knots, or a flight / turn / attempt count by more than one.",
                "The phone's number is the authoritative one, so nothing is wrong with your "
                + "session: the banner says the watch's live approximation needs tuning.",
            ],
            related: [.sourceClass, .engineVersion]),

        HelpTopic(
            id: .engineVersion, section: .quality, title: "Analysis engine version",
            summary: "Every session is re-derived when the engine changes.",
            body: [
                "The footer of a session shows which version of the analysis engine produced "
                + "its numbers. When the engine changes in a way that alters results, sessions "
                + "computed with an older version are recomputed from their archived original "
                + "file the next time they are opened.",
                "The original recording is never modified — only the derived analysis is, and "
                + "it can be dropped and rebuilt at any time from Settings.",
            ],
            related: [.sourceClass, .divergence]),

        HelpTopic(
            id: .windsurf, section: .quality, channel: .dev,
            title: "Windsurf (experimental)",
            summary: "The same engine, minus the wing — and the planing speeds are a guess.",
            body: [
                "A session can be analysed as **Wingfoil**, **Windsurf foil** or **Windsurf "
                + "fin**. The row is on the session's Log tab, under \"Analyse as\"; changing "
                + "it re-derives that session and nothing else.",
                "Wingfoil is not a sport in Garmin, Strava, intervals.icu or Apple Health, so "
                + "most riders record under the windsurf profile and a new session cannot say "
                + "which rig it was ridden on.",
                "So it is read as whatever you set under Settings → \"I mostly ride\", marked "
                + "with a **?** until you have looked, and listed after each import. Sessions "
                + "from the CleanJibe watch app are never asked about.",
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
                      detail: "The wingfoil reading with pumping switched off: every speed "
                          + "and every threshold is the same, because a foil flies the same "
                          + "way under either rig."),
                .init(term: "Windsurf fin",
                      detail: "Also moves the two speeds that decide when you are going: "
                          + "20 km/h to start planing, 15 km/h to stop, against 12 and 8 on "
                          + "a foil."),
                .init(term: "Those two speeds are provisional",
                      detail: "A first guess, not a reading off real fin sessions — there "
                          + "are none in the corpus yet. If your planing time looks wrong, "
                          + "report that number."),
                .init(term: "In the library",
                      detail: "\"Foil time\" reads as planing time and \"lost the foil\" as "
                          + "stopped planing. Windsurf sessions count towards your trends; "
                          + "there is no separate record set."),
            ],
            related: [.foilPct, .turnOutcomes, .pumpsToTakeoff, .engineVersion]),
    ]

    /// Fast lookup by identifier. Total by construction — see `topic(_:)`.
    private static let byID: [HelpTopicID: HelpTopic] =
        Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })

    /// The topic for a metric. Non-optional: the tests assert every `HelpTopicID` case is
    /// present, so a `?` button on a card can link without unwrapping.
    public static func topic(_ id: HelpTopicID) -> HelpTopic {
        guard let topic = byID[id] else {
            preconditionFailure("no help topic for \(id.rawValue) — HelpCatalog is incomplete")
        }
        return topic
    }

    public static func topic(id: String) -> HelpTopic? {
        HelpTopicID(rawValue: id).map(topic)
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
        guard channel.has(topic.channel) else { return false }
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
    }

    /// **The "see also" list a topic may actually render.**
    ///
    /// A related link is a button, and a button onto a topic this build hides would be a
    /// dead end dressed as a next step — so the list is filtered by the same rule the index
    /// is, rather than by a second one that could drift away from it.
    public static func relatedTopics(of topic: HelpTopic, channel: HelpChannel,
                                     windsurfEnabled: Bool = true) -> [HelpTopic] {
        topic.related
            .map(Self.topic)
            .filter { isListed($0, channel: channel, windsurfEnabled: windsurfEnabled) }
    }

    /// Sections that actually have topics, in declaration order.
    public static var sections: [HelpSection] {
        HelpSection.allCases.filter { !topics(in: $0).isEmpty }
    }

    /// Case-insensitive search over title, summary, body and items.
    public static func search(_ query: String) -> [HelpTopic] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return topics }
        return topics.filter { topic in
            if topic.title.lowercased().contains(needle) { return true }
            if topic.summary.lowercased().contains(needle) { return true }
            if topic.body.contains(where: { $0.lowercased().contains(needle) }) { return true }
            return topic.items.contains {
                $0.term.lowercased().contains(needle) || $0.detail.lowercased().contains(needle)
            }
        }
    }
}
