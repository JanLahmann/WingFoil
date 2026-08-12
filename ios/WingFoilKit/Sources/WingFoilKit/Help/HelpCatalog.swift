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
    /// Outbound links the topic offers (intervals.icu, so far).
    public let links: [HelpLink]
    /// An in-app destination the topic can send the reader to. Data rather than a
    /// hard-coded `if id == …` in the sheet, so the test suite can assert the setup
    /// topic actually offers its shortcut.
    public let action: HelpAction?
    /// Topics worth reading next; every id here must resolve (asserted in the tests).
    public let related: [HelpTopicID]

    public init(id: HelpTopicID, section: HelpSection, title: String, summary: String,
                body: [String], items: [Item] = [], links: [HelpLink] = [],
                action: HelpAction? = nil, related: [HelpTopicID] = []) {
        self.id = id
        self.section = section
        self.title = title
        self.summary = summary
        self.body = body
        self.items = items
        self.links = links
        self.action = action
        self.related = related
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
    /// Opens WingFoil's own Settings screen, scrolled to the intervals.icu section.
    case openIcuSettings
    /// Imports the bundled example session (`ExampleSession`) — the same button the
    /// empty-library setup card offers, so Help is not a dead end for a first-time reader.
    case loadExampleSession
}

/// Where a topic sits in the Help index.
public enum HelpSection: String, CaseIterable, Sendable, Identifiable {
    case setup, foil, records, turns, takeoff, effort, conditions, quality

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
        case .quality: "checkmark.seal"
        }
    }
}

/// Every explainable metric, as an enum so a `?` button cannot point at a missing topic.
public enum HelpTopicID: String, CaseIterable, Sendable, Identifiable {
    case icuSetup, exampleSession, icuTroubleshooting, icuPrivacy
    case foilPct, flights, longestFlight, distance
    case recordSet, best2s, best10s, best5x10s, best500m, bestNm, alpha500, uncertified
    case turnTypes, turnOutcomes, turnSuccess, portStarboard, falls, touchdowns, glideOuts
    case takeoffAttempts, pumpsToTakeoff, pumpStrokes
    case heartRate
    case windAxis
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
                "Nothing is uploaded and nothing is changed on either side: WingFoil lists "
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
                "Nothing in WingFoil makes sense on an empty library, and the first thing a "
                + "new install has is an empty library. So one real recording travels inside "
                + "the app: \(ExampleSession.blurb)",
                "It comes from \(ExampleSession.place) and was recorded with the WingFoil "
                + "Connect IQ app on a fenix, which makes it a class-(a) source — every "
                + "screen has something to show, including the ones that need the "
                + "accelerometer, the developer fields and the heart-rate stream.",
                "It is not your data, and WingFoil treats it that way: an example session "
                + "is badged EXAMPLE in the list and at the top of its own page, and it is "
                + "left out of Records, Trends and the gear rollups so it can never inflate "
                + "a personal best or bend a trend line. Delete it with a swipe whenever you "
                + "like — this screen and the setup card will both offer it again.",
                "Every identifier was removed before it was bundled: the watch serial "
                + "number is zeroed, and the rider profile, the paired-accessory record and "
                + "the watch's lifetime totals are gone. What is left is the ride — track, "
                + "speed, heart rate, laps and all of the app's own recorded fields.",
            ],
            action: .loadExampleSession,
            related: [.icuSetup, .sourceClass, .uncertified]),

        HelpTopic(
            id: .icuTroubleshooting, section: .setup, title: "When the sync does not work",
            summary: "The four things that actually go wrong, and the fix for each.",
            body: [
                "Every failure WingFoil can see is reported as a cause rather than as a "
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
                + "you swam), and the accelerometer on our own recordings (a pump burst can turn "
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
            related: [.turnSuccess, .falls, .glideOuts]),

        HelpTopic(
            id: .turnSuccess, section: .turns, title: "Carried through (turn success)",
            summary: "Speed kept through the turn — the continuous score behind the outcome.",
            body: [
                "A turn is scored successful when your minimum speed through it stays at or "
                + "above 70 % of the speed you entered with, and you never dropped below the "
                + "foil exit speed during the sweep.",
                "Outcome says what happened; success says what it cost. They can disagree on "
                + "purpose: a turn carved cleanly through the sweep stays successful even if "
                + "the foil is lost afterwards in the recovery — the outcome is what records "
                + "that.",
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
                "It needs the wrist accelerometer, which only our own watch recordings carry. "
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
                "This analysis currently lives in the lab tooling while its definitions settle; "
                + "the app records whether a session carries a usable heart-rate channel so the "
                + "sessions it can be run on are known.",
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

        // MARK: Where the numbers come from

        HelpTopic(
            id: .sourceClass, section: .quality, title: "Source classes a, b and c",
            summary: "What your recording could carry decides what can be measured.",
            body: [
                "Every metric degrades gracefully with the source rather than failing or "
                + "guessing. What a session can report depends on which channels its file has:",
            ],
            items: [
                .init(term: "Class a",
                      detail: "A recording from the WingFoil watch app. Doppler speed, "
                          + "positions, the wrist accelerometer, the barometer and the watch's "
                          + "own live summary. Everything in the app is available."),
                .init(term: "Class b",
                      detail: "A normal device recording with Doppler speed and positions. "
                          + "Records are certified; pump strokes, failed takeoff attempts and "
                          + "accelerometer-corroborated touchdowns are not available."),
                .init(term: "Class c",
                      detail: "A degraded source with no speed channel. Everything still "
                          + "computes, but speed records are marked uncertified."),
            ],
            related: [.uncertified, .divergence, .engineVersion]),

        HelpTopic(
            id: .divergence, section: .quality, title: "\"Watch and phone disagree\"",
            summary: "The banner comparing the live watch numbers with the phone's recompute.",
            body: [
                "When a session comes from the WingFoil watch app it carries the summary the "
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
