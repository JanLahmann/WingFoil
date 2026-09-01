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

    public init(id: HelpTopicID, section: HelpSection, title: String, summary: String,
                body: [String], items: [Item] = [], image: HelpImage? = nil,
                links: [HelpLink] = [], action: HelpAction? = nil,
                related: [HelpTopicID] = []) {
        self.id = id
        self.section = section
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

/// Where a topic sits in the Help index.
public enum HelpSection: String, CaseIterable, Sendable, Identifiable {
    case setup, foil, records, turns, takeoff, effort, conditions, sharing, quality

    public var id: String { rawValue }

    public var title: String {
        switch self {
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
    case icuSetup, exampleSession, icuTroubleshooting, icuPrivacy
    case foilPct, flights, longestFlight, distance, mapLegend
    case recordSet, best2s, best10s, best5x10s, best500m, bestNm, alpha500, uncertified
    case turnTypes, turnOutcomes, turnSuccess, portStarboard, falls, touchdowns, glideOuts
    case takeoffAttempts, pumpsToTakeoff, pumpStrokes
    case heartRate
    case windAxis
    case shareCard, replayClip, shareFit, riderAttribution
    case sourceClass, divergence, engineVersion

    public var id: String { rawValue }
}

public enum HelpCatalog {

    /// Every topic, in reading order. `topics` is the single source; the lookups below
    /// are derived from it, so a topic cannot exist in one and not the other.
    public static let topics: [HelpTopic] = [

        // MARK: Getting set up
        //
        // The steps are not written here: they come from `IcuSetupGuide`, which the
        // empty-library setup card renders too. One wording, two screens.

        HelpTopic(
            id: .icuSetup, section: .setup, title: "Get set up with intervals.icu",
            summary: "Four steps, about five minutes, once.",
            body: [
                IcuSetupGuide.rationale,
                "Nothing is uploaded and nothing is changed on either side: CleanJibe lists "
                + "your activities, downloads the original FIT of the watersport ones, and "
                + "analyses them on the phone.",
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
                "Nothing in CleanJibe makes sense on an empty library, and the first thing a "
                + "new install has is an empty library. So one real recording travels inside "
                + "the app: \(ExampleSession.blurb)",
                "It is not your data, and CleanJibe treats it that way: an example session "
                + "is badged EXAMPLE in the list and at the top of its own page, and it is "
                + "left out of Records, Trends and the gear rollups so it can never inflate "
                + "a personal best or bend a trend line. Delete it with a swipe whenever you "
                + "like — this screen and the setup card will both offer it again.",
                "It was recorded at \(ExampleSession.place) with the CleanJibe watch app, "
                + "with every identifier removed before it was bundled. The one thing left "
                + "out is the accelerometer stream, which alone was larger than the rest of "
                + "the app — so pump strokes and takeoff effort show as unavailable on this "
                + "one session.",
            ],
            image: HelpImage(asset: "help-session-detail",
                             caption: "The four rows at the top answer \"was that a good "
                                 + "session\"."),
            action: .loadExampleSession,
            related: [.icuSetup, .sourceClass, .uncertified, .riderAttribution]),

        HelpTopic(
            id: .icuTroubleshooting, section: .setup, title: "When the sync does not work",
            summary: "The four things that actually go wrong, and the fix for each.",
            body: [
                "Every failure CleanJibe can see is reported as a cause rather than as a "
                + "stack trace, because the fix is different in each case — a rejected key "
                + "is your key, an empty list is usually Garmin not being connected yet, and "
                + "a network error is neither.",
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
                + "treat it like a password: do not paste it into a screenshot or a chat. "
                + "If you ever do, regenerate it in Developer Settings and paste the new one "
                + "here — the old key stops working the moment you regenerate.",
            ],
            related: [.icuSetup, .icuTroubleshooting]),

        // MARK: On the foil

        HelpTopic(
            id: .foilPct, section: .foil, title: "Foil time / foil %",
            summary: "How much of the session you spent actually flying.",
            body: [
                "A flight starts when your speed stays above the entry threshold "
                + "(12 km/h by default) for 2 seconds, and ends when it stays below the exit "
                + "threshold (8 km/h) for 3 seconds. The start and end are backdated to the "
                + "first qualifying sample, so the flight covers the whole time you were up.",
                "Foil % is that flying time divided by the elapsed session time — taxiing, "
                + "swimming, and the drift back upwind all count against it. Anything under "
                + "5 seconds is not counted as a flight at all.",
            ],
            related: [.flights, .longestFlight, .sourceClass]),

        HelpTopic(
            id: .flights, section: .foil, title: "Flights",
            summary: "How many separate times you got up and stayed up.",
            body: [
                "One flight = one continuous stretch above the entry threshold, lasting at "
                + "least 5 seconds. A brief touchdown does not split a flight: the exit needs "
                + "3 seconds below the exit speed, so a one- or two-second tap of the water "
                + "stays inside the flight and shows up as a touchdown instead.",
                "That is deliberate — the flight count answers \"how many times did I have to "
                + "get up again\", and the touchdown count answers \"how clean was it\".",
            ],
            related: [.foilPct, .touchdowns, .takeoffAttempts]),

        HelpTopic(
            id: .longestFlight, section: .foil, title: "Longest flight",
            summary: "Your best single stretch, in time and in distance.",
            body: [
                "The longest flight by duration, with the distance covered during it shown "
                + "underneath. On a choppy day the longest flight is usually the one where you "
                + "found a lane; on a gusty day it is the one where you got lucky.",
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

        // The legend documentation used to be printed under the chips on every visit to
        // every session — three grey paragraphs, ~115 pt of a 956 pt phone screen, to a
        // rider who learned it once (app-ui-review.md §1.2). It is reference material, and
        // reference material belongs behind the `?` the rest of the page already uses.
        HelpTopic(
            id: .mapLegend, section: .foil, title: "Reading the map",
            summary: "What the chips, the colours, the arrows and the dots mean.",
            body: [
                "Every chip under the map is a switch. Tapping one hides that category on "
                + "the map and in the speed chart at the same time — the two are one reading "
                + "of the same session, so a marker in one and not the other would be a lie. "
                + "A hidden chip stays in place, struck through, and \"show all\" brings "
                + "everything back. A category this session has none of is not a switch.",
                "The track is tinted by phase: teal where you were flying, grey where you "
                + "were not. Small chevrons along it point the way you were riding.",
                "The dots are verdicts, on one ladder: green flew through, orange touched "
                + "down, red fell in, grey a course change that is no verdict at all. Fill "
                + "carries the channel rather than a second colour — solid is a maneuver's "
                + "outcome, hollow is a straight-line flight end that no turn explains.",
                "Takeoffs are arrows, not dots, so a busy track cannot confuse them with "
                + "outcomes: an up-arrow got you up, and a red u-turn is an attempt that did "
                + "not. One chip hides both halves, because they are two ends of the same "
                + "thing. The indigo bands are pump bursts and the cyan drop is the "
                + "barometer seeing your wrist go under.",
                "Tap the track to move the replay playhead; tap a mark, or a flown stretch, "
                + "for its own facts.",
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
                + "comparable with the ones people post: 2 s and 10 s peaks, the mean of the "
                + "best five separate 10 s runs, 100 m / 250 m / 500 m / 1 nautical mile, one "
                + "hour, and alpha 500.",
                "All of them are computed on the device's Doppler speed, with fractional "
                + "samples interpolated at the window edges, so the result does not depend on "
                + "whether your watch recorded at 1 Hz or 4 Hz. No minimum-speed filter is ever "
                + "applied — those distort results.",
                "A window never spans a recording gap. Tap a record card to see exactly where "
                + "on the track and on the speed trace it happened.",
            ],
            related: [.best2s, .best5x10s, .alpha500, .uncertified]),

        HelpTopic(
            id: .best2s, section: .records, title: "Best 2 s",
            summary: "Your peak speed, averaged over 2 seconds.",
            body: [
                "The fastest 2-second stretch of the session. It is the closest thing to a "
                + "\"top speed\" that is not just a GPS spike — a single-sample maximum is "
                + "noise, two seconds is a real burst.",
                "This is the number most riders compare, and the one the Records screen tracks "
                + "as a personal best over time.",
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
                "The five 10-second windows must not overlap, so this cannot be one long "
                + "run counted five times. It rewards consistency across the session rather "
                + "than a single lucky reach — which is exactly why the speedsurfing world "
                + "uses it as the headline number for a session.",
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
                "It is the one record that measures your turns as well as your speed, which "
                + "is why it is worth chasing on a wing.",
            ],
            related: [.recordSet, .best500m, .turnOutcomes]),

        HelpTopic(
            id: .uncertified, section: .records, title: "\"Uncertified\"",
            summary: "The recording could not prove the speed was Doppler.",
            body: [
                "Speed records are only trustworthy when they come from the receiver's Doppler "
                + "speed channel. A recording that carries positions but no speed channel — a "
                + "GPX-grade source, or a converted file — gets its speed differentiated from "
                + "positions instead, and that is systematically noisier and can read high.",
                "Those records are still shown, because they are still your session, but they "
                + "are labelled uncertified so you never post one as a personal best by "
                + "accident. Nothing recorded by your watch directly is affected.",
            ],
            related: [.sourceClass, .recordSet]),

        // MARK: Turns & losses

        HelpTopic(
            id: .turnTypes, section: .turns, title: "Tacks, jibes and course changes",
            summary: "What counts as a maneuver, and what is just a change of direction.",
            body: [
                "A turn is detected from your course: at least 60° of net heading change "
                + "within 8 seconds, containing a peak rate of 25°/s, while you are on the foil "
                + "(or within 3 s of it). It must also have carved a real arc — at least 12 m "
                + "of path at an effective radius of at least 6 m — which is what separates a "
                + "maneuver from a rider spinning around beside the board.",
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
                "Every turn gets one of three outcomes. The judgement runs from the turn start "
                + "until you are demonstrably flying again — speed back above 70 % of your entry "
                + "speed for 2 seconds — capped at 12 seconds. That matters: a jibe exited at "
                + "marginal speed can keep bleeding off for 6–12 seconds before the foil finally "
                + "stalls, and that mush-out is the jibe's fault. A jibe you power straight out "
                + "of closes its window in a second or two and cannot absorb an unrelated "
                + "touchdown later on.",
                "Inside that window three channels are read: speed (always), the barometer "
                + "(a wrist that goes under water reads as a huge altitude drop, which is proof "
                + "you swam), and, on a CleanJibe watch recording, the accelerometer (a pump "
                + "burst can turn "
                + "a fly-through into a touchdown, but only when the speed also went marginal — "
                + "you pump for many reasons).",
            ],
            items: [
                .init(term: "Flew through",
                      detail: "You never left the foil. No sample in the window is off-foil."),
                .init(term: "Touchdown",
                      detail: "You lost the foil but not the session: you stopped for 3 s or "
                          + "less, or you had to pump it back up. Marked borderline between "
                          + "3 s and 5 s."),
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
            summary: "A jibe you fly all the way through, carrying your speed.",
            body: [
                "A clean jibe is one you fly all the way through, carrying your speed — no "
                + "touchdown, no swim, and at or above the success threshold of the speed "
                + "you entered with. That threshold is a published, configurable parameter "
                + "(`turnSuccessPct`), 70 % by default.",
                "Both halves have to hold: your minimum speed through the turn stays at or "
                + "above that share of your entry speed, and you never drop below the foil "
                + "exit speed during the sweep. The score under each turn in the list is the "
                + "first half of that as a number, 0–100.",
                "Outcome says what happened; clean says what it cost. They can disagree on "
                + "purpose: a jibe carved cleanly through the sweep stays clean even if the "
                + "foil is lost afterwards in the recovery — the outcome is what records "
                + "that. So the clean count is always the stricter of the two, and it is "
                + "normally the smaller number.",
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
                "A fall means you stopped for more than 5 seconds, or the barometer caught your "
                + "wrist going under.",
                "The split matters: falls in turns are a maneuver problem, falls in a straight "
                + "line are a gust, a ventilation or a tip catching. Each fall is counted "
                + "exactly once — a fall inside a turn's window belongs to that turn and is "
                + "not double-counted as a straight-line loss.",
            ],
            related: [.turnOutcomes, .touchdowns, .glideOuts]),

        HelpTopic(
            id: .touchdowns, section: .turns, title: "Touchdowns",
            summary: "Brief losses of the foil, in turns and in a straight line.",
            body: [
                "You came off the foil but were making way again within a few seconds, or you "
                + "pumped straight back up. Short touchdowns inside a flight do not break the "
                + "flight — that is why the touchdown count and the flight count tell you "
                + "different things.",
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
                + "excluded from every tally: there is no evidence there, and calling them "
                + "glide-outs would invent a clean session out of missing data.",
            ],
            related: [.falls, .touchdowns, .sourceClass]),

        // MARK: Takeoff & pumping

        HelpTopic(
            id: .takeoffAttempts, section: .takeoff, title: "Attempts & success rate",
            summary: "How often you pumped — including the times you did not get up.",
            body: [
                "Attempts = flights + failed attempts. A pumping burst counts as a failed "
                + "attempt when no flight starts within 10 seconds of your last stroke; bursts "
                + "closer together than that are chained into one attempt, so four bursts "
                + "inside a minute of thrashing are one failure, not four.",
                "This is the number no summary built from flights alone can contain — a "
                + "session where you got up 20 times out of 22 and one where you got up 20 "
                + "times out of 40 look identical otherwise.",
                "It needs the wrist accelerometer, which only the CleanJibe watch app "
                + "records. "
                + "Without it your failures are invisible, so the success rate is shown as "
                + "unknown rather than a flattering 100 %.",
            ],
            related: [.pumpsToTakeoff, .sourceClass, .heartRate]),

        HelpTopic(
            id: .pumpsToTakeoff, section: .takeoff, title: "Pumps to takeoff",
            summary: "How many strokes each flight cost you.",
            body: [
                "The takeoff run is the stretch of rising speed before the flight plus the "
                + "pump burst that led into it, whichever started earlier — so the count is the "
                + "strokes of the effort that actually produced the flight.",
                "Takeoffs under 3 strokes are counted as free: you got up on the wind alone. "
                + "That is a fact about the conditions rather than about your pumping, so free "
                + "takeoffs are kept out of the averages and reported separately.",
                "Runs the recording cut short are excluded from the averages but still count "
                + "as successes — the flight demonstrably happened, only its cost is unknown.",
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
                "HR cost is the rise from your baseline just before an effort to the peak that "
                + "follows it. The baseline is the median of the 10 seconds ending at the start "
                + "of the takeoff run, and the peak is searched 30 seconds forward, because an "
                + "optical wrist sensor trails effort by 10–20 seconds.",
                "Negative values are reported rather than hidden: \"you were still recovering "
                + "when you started\" is a different fact from \"this cost nothing\".",
                "Coverage is the share of a window carried by heart-rate samples that are "
                + "plausible (30–220 bpm), not stuck, and not separated by a hole longer than "
                + "10 seconds. Below 60 % coverage no number is produced at all. A wrist sensor "
                + "under a wetsuit sleeve in cold water drops out and sticks, and a made-up "
                + "average is worse than a missing one.",
                "The fatigue chart slices the session into 20-minute bins and shows what each "
                + "one's takeoffs cost, with the share of attempts that got up underneath. "
                + "Bins where the sensor gave nothing usable are shaded rather than drawn as "
                + "a zero-height bar.",
                "Read the cost bars together with the baseline note under the chart. A rise "
                + "measured against a baseline that has drifted upward gets smaller as you "
                + "tire, because there is less headroom left to rise into — a shrinking late "
                + "cost is not evidence that the takeoffs got easier.",
                "The card does not appear at all on a session whose recording has no usable "
                + "heart rate. Nothing here is estimated when the sensor was silent.",
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
                "That gives an axis but not a side — upwind and downwind look the same to a "
                + "bisector. The tie is broken by the no-go zone: of the two ends of the axis, "
                + "the one you sailed almost nothing within ±45° of is where the wind came from.",
                "Confidence combines how cleanly the two reaches separate with how decisive the "
                + "no-go zone was. Below 50 % the axis is still shown but your turns stay "
                + "unnamed \"turns\" rather than being called tacks and jibes — naming them on "
                + "a bad axis would be worse than not naming them. A wind direction you set on "
                + "the watch yourself always wins over the estimate.",
            ],
            related: [.turnTypes, .portStarboard]),

        // MARK: Sharing
        //
        // The rest of this catalogue explains *numbers*. This section explains *doors* —
        // four things the app can do that a rider will never find by tapping around,
        // because each of them is one button on one sheet. They are written the same way
        // as the metric topics (what it is, then what leaves the phone) because the second
        // half is the part somebody is actually deciding about.

        HelpTopic(
            id: .shareCard, section: .sharing, title: "Share cards",
            summary: "One picture of a session, made to post.",
            body: [
                "Any session can become a card: the track, the numbers that matter, and a "
                + "line saying where the analysis came from. Pick portrait, square or "
                + "landscape to suit where it is going, and Complete or Lean depending on "
                + "how much detail you want on it. A photo from your library can go behind "
                + "it.",
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
                + "follows what is happening — a takeoff, a jibe carried through, a swim. "
                + "Scrub to the part worth watching, then record it as a video and save it "
                + "to your photo library or send it straight on.",
                "Ask for a 10, 25 or 60-second clip and the app solves the playback rate to "
                + "land on it, or take \"full detail\" and let the session run as long as it "
                + "runs. The frame is yours too: 9:16 for a story, 1:1 for a post, 16:9 for "
                + "a chat, or the whole screen uncropped. Photos you took that afternoon can "
                + "be spliced in where they were taken.",
                "You can lay your own music under it — any audio file the phone can read, "
                + "trimmed or looped to the clip's length and faded at both ends. Nothing is "
                + "uploaded: the video is rendered on the phone.",
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
                + "out of your records, your trends and your gear totals, so their fast run "
                + "never becomes your personal best.",
                "The name you give is stored on your phone only.",
            ],
            related: [.shareFit, .exampleSession]),

        // MARK: Where the numbers come from

        // The topic that answers the question a rider actually arrives with — *do I need
        // the watch app?* — so it is written around that question rather than around the
        // engine's own vocabulary. The letters a/b/c survive in the code (`SessionRow
        // .sourceClass`, `SessionDisplay.sourceClassNote`'s doc comment) because the engine
        // and the fixtures are full of them; they no longer survive on screen, because
        // "class b" tells a rider nothing he could act on.
        HelpTopic(
            id: .sourceClass, section: .quality,
            title: "What your recording can and cannot show",
            summary: "Everything works from any Garmin recording. Two things need the "
                + "CleanJibe watch app.",
            body: [
                "CleanJibe reads whatever your watch put in the file, and every metric "
                + "degrades gracefully rather than failing or guessing. In practice there "
                + "are three cases:",
            ],
            items: [
                .init(term: "Recorded with the CleanJibe watch app",
                      detail: "Everything in the app is available: the track, the flights, "
                          + "the turn verdicts, the speed records, the wind axis, and — "
                          + "because this app also records the wrist accelerometer — pump "
                          + "strokes, failed takeoff attempts and accelerometer-confirmed "
                          + "touchdowns."),
                .init(term: "Recorded with Garmin's own profile, or another Connect IQ app",
                      detail: "Almost everything: the track, the flights and touchdowns, "
                          + "every turn with its verdict, certified speed records, the wind "
                          + "axis. Only pump strokes, failed takeoff attempts and "
                          + "accelerometer-confirmed touchdowns are missing, because nothing "
                          + "recorded the accelerometer."),
                .init(term: "A file with no speed channel",
                      detail: "Rare, and usually a converted export rather than the original "
                          + "recording. Everything still computes from positions, but the "
                          + "speed records are marked uncertified."),
            ],
            related: [.uncertified, .divergence, .engineVersion]),

        HelpTopic(
            id: .divergence, section: .quality,
            title: "When the watch and the phone show different numbers",
            summary: "Normal, expected, and the phone's number is the right one.",
            body: [
                "When a session comes from the CleanJibe watch app it carries the summary the "
                + "watch computed live, on a wrist, in one forward pass with no memory to spare. "
                + "The phone then recomputes the same session properly, and the two are compared.",
                "The banner appears when foil time differs by more than 5 %, any speed record by "
                + "more than 0.3 knots, or a flight / turn / attempt count by more than one.",
                "The phone's number is the authoritative one, so nothing is wrong with your "
                + "session — the banner is a signal that the watch's live approximation needs "
                + "tuning, and it is there so the disagreement gets noticed rather than "
                + "silently averaged away.",
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
