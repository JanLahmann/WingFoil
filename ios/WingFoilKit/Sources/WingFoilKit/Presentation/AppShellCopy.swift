import Foundation

/// **The app's screen sentences, written once for both shells** (Jan, 28 September 2026:
/// *"the iPhone app is the golden master for layout and wording"*).
///
/// Until this file, the sentences below were SwiftUI literals inside the app target, and the
/// browser app had retyped each of them in `web/js`. A retyped sentence is a second author,
/// and the second author drifted: the web's turn footnote still explained the score after
/// the phone had moved it to the help, and its spots screen said one thing while the
/// phone's said another. Each sentence now lives here, the app reads it from here, and
/// `AppShellCopyExportTests` writes the whole file to `docs/copy/app-words.json`, which
/// `web/tools/make_app_copy.py` turns into `WORDS` in `web/js/appcopy.js`. The browser says
/// `say("turnPage.tapTheDrawing")` and never types the words.
///
/// **A sentence with a number in it is a template.** `{name}` marks each value the screen
/// fills in, and `fill(_:_:)` fills it; the browser's `say(key, args)` does the same thing
/// with the same names. A template is written as one literal, so both shells cut the
/// sentence in the same place.
///
/// Wording is not decided here. A change to any of these is a change to the phone first,
/// then `COPY_WRITE=1 swift test --filter AppShellCopyExportTests`, then
/// `python3 web/tools/make_app_copy.py`.
public enum AppShellCopy {

    /// Fills `{name}` placeholders. A value is inserted as it is given; the caller formats
    /// its numbers the way the screen already prints them.
    public static func fill(_ template: String, _ args: [String: String]) -> String {
        var out = template
        for (name, value) in args {
            out = out.replacingOccurrences(of: "{" + name + "}", with: value)
        }
        return out
    }

    // MARK: - The turn page

    /// `TurnDetailView`: the controls, the empty map and the footnote under the strips.
    public enum TurnPage {
        public static let noGeometry = "No GPS fixes through this turn. Numbers only."
        public static let drawnNorthUp = "The turn is drawn north up."
        public static let compareWithBest = "Compare with best clean jibe"
        public static let nothingToCompare =
            "Nothing to compare with. "
            + "This session has no other jibe that flew through the same way round."
        public static let footDrawn = "The drawing is {before} s before the sweep and {after} s after it."
        public static let footTicks = "Ticks are one second apart."
        public static let footRamp =
            "The line is coloured by speed on the ramp at the foot of the picture. "
            + "Cold is a standstill, teal is the speed you came in at, hot is above it."
        public static let footTap =
            "Tap the drawing for the reading at that sample. The strips follow it."
        public static let footEntryBand = "The bands under the strip are the engine's windows. \"Entry\" is the {seconds} s before the sweep, where the entry speed is the maximum."
        public static let footSweepBand = "\"Sweep\" is where the heading turned. The low point is searched to {seconds} s past the sweep, so it can sit after \"out\"."
        public static let footLighterBand =
            "The lighter band inside it ends where you were flying again."
        public static let footQuiet = "A clean jibe also needs {seconds} s after the sweep with no touchdown, fall or wrist under."
        public static let footAxis =
            "The tick marked \"axis\" is the moment the board went through the wind axis. "
            + "That is dead downwind on a jibe, head to wind on a tack. "
            + "The turn is named after that crossing."
        /// `TurnHeadingStripView`, when the window has too few usable bearings.
        public static let noBearings =
            "No usable bearings through this window. "
            + "The steps were shorter than the receiver's own scatter."

        static let all: [String: String] = [
            "noGeometry": noGeometry, "drawnNorthUp": drawnNorthUp,
            "compareWithBest": compareWithBest, "nothingToCompare": nothingToCompare,
            "footDrawn": footDrawn, "footTicks": footTicks, "footRamp": footRamp,
            "footTap": footTap, "footEntryBand": footEntryBand, "footSweepBand": footSweepBand,
            "footLighterBand": footLighterBand, "footQuiet": footQuiet, "footAxis": footAxis,
            "noBearings": noBearings,
        ]
    }

    /// `FlightEndDetailView`: the same page for a flight that ended on a straight line.
    public enum FlightEndPage {
        public static let noGeometry = "No GPS fixes through this flight end. Numbers only."
        public static let drawnNorthUp = "The track is drawn north up."
        public static let neverBack = "Never back up to flying speed inside the window."
        public static let backAfter = "Back to flying speed {time} after the end."
        public static let footDrawn = "The drawing is {before} s before the end and {after} s after it."
        public static let footMarks =
            "The thick, coloured part is the flight. "
            + "Everything past the dot is already off the foil. "
            + "Ticks are one second apart."
        public static let footEntryBand = "The bands are the engine's windows. \"Entry\" is the {seconds} s the flight was ending at."
        public static let footEvidence =
            "\"Evidence\" is how much gap-free recording there actually was."
        public static let footLow =
            "Only \"low\" is the engine's. "
            + "It is the slowest sample of the off-foil run, placed where this window "
            + "comes nearest it."
        public static let footInOut =
            "\"In\" is the fastest sample of the entry window. "
            + "\"Out\" is where the speed came back to the engine's flying-again threshold."
        public static let footNoRecord =
            "Both are read off the drawn line. "
            + "A flight end record holds no entry or exit speed of its own."
        public static let footChannel =
            "Speed here is the manoeuvre channel, derived from position. "
            + "The GPS Doppler speed the records use is smoothed. "
            + "It would read differently."
        public static let footBorderline =
            "\"Borderline\" means the stop ran past the touchdown limit without "
            + "reaching the fall one."

        static let all: [String: String] = [
            "noGeometry": noGeometry, "drawnNorthUp": drawnNorthUp, "neverBack": neverBack,
            "backAfter": backAfter, "footDrawn": footDrawn, "footMarks": footMarks,
            "footEntryBand": footEntryBand, "footEvidence": footEvidence, "footLow": footLow,
            "footInOut": footInOut, "footNoRecord": footNoRecord, "footChannel": footChannel,
            "footBorderline": footBorderline,
        ]
    }

    // MARK: - The session page

    /// `SessionLogView`'s divergence card: the advice under the watch-versus-phone table.
    public enum SessionLog {
        public static let trustThePhone =
            "Trust the phone's numbers. It reads the whole session back afterwards. "
            + "The watch has to work these out live on your wrist, as you ride. "
            + "Nothing is wrong with your session."
        public static let takeoffsDiffer =
            "Takeoff and pump counting is where the two differ most. "
            + "Keep the watch app up to date to narrow the gap."

        static let all: [String: String] = [
            "trustThePhone": trustThePhone, "takeoffsDiffer": takeoffsDiffer,
        ]
    }

    /// `ShareComposerView`: the row that sends a session to the developer.
    public enum Share {
        public static let sendToUs = "Send this session to us"
        public static let sendToUsLine =
            "A number looks wrong? Send the recording with your notes."

        /// The card's background, on the session card and the period card alike
        /// (`ShareCardDesignControls`): the dark card, the map under the track, a photo.
        public static let background = "Background"
        public static let dark = "Dark"
        public static let map = "Map"
        public static let photo = "Photo"
        /// The period card's artwork (Jan, 28 Sep 2026): every track on one another, one
        /// session drawn big, or each session's own small track in a grid.
        public static let tracks = "Tracks"
        public static let allSessions = "All sessions"
        public static let oneSession = "One session"
        public static let collage = "Collage"
        public static let collageNote =
            "The last {limit} sessions, each on its own, in the order you rode them."

        static let all: [String: String] = [
            "sendToUs": sendToUs, "sendToUsLine": sendToUsLine,
            "background": background, "dark": dark, "map": map, "photo": photo,
            "tracks": tracks, "allSessions": allSessions, "oneSession": oneSession,
            "collage": collage, "collageNote": collageNote,
        ]
    }

    /// `RiderPromptView`: whose session a new import is.
    public enum Rider {
        public static let question = "Whose session is this?"
        public static let friendShown =
            "A friend's session is shown in full. You get the map, the chart, the replay, "
            + "everything."
        /// The release's list. The beta names Apple Health too, which is a beta door
        /// (docs/channels.md), so the release and the web never say it.
        public static let friendKeptOut =
            "It stays out of your records, your trends and your gear totals."
        public static let friendKeptOutBeta =
            "It stays out of your records, trends, gear totals and Apple Health."

        static let all: [String: String] = [
            "question": question, "friendShown": friendShown, "friendKeptOut": friendKeptOut,
            "friendKeptOutBeta": friendKeptOutBeta,
        ]
    }

    // MARK: - Sessions

    /// `TurnsAnalysisView`: the footnote under the turns list.
    public enum Turns {
        public static let outcomeAndHeld =
            "Flew through / touchdown / fell in is the outcome. It says how the turn ended. "
            + "Held is how much of your entry speed you kept through it, 0 to 100 %."
        /// The three gates, with the analysis' own two numbers.
        public static let cleanRule = "Clean: you flew through, held at least {pct} % of your entry speed, then {quiet} quiet seconds on the foil."

        static let all: [String: String] = [
            "outcomeAndHeld": outcomeAndHeld, "cleanRule": cleanRule,
        ]
    }

    /// `LibraryView`: a filter that leaves nothing.
    public enum Library {
        public static let noMatch = "No session matches these filters"
        public static let noMatchLine = "Nothing in the library answers to all of them at once."

        static let all: [String: String] = ["noMatch": noMatch, "noMatchLine": noMatchLine]
    }

    // MARK: - Records, Trends, Periods

    /// `RecordsView`: the footers and the empty table.
    public enum Records {
        public static let speedHead = "Doppler speed, GP3S windows. {certified} of {count} have measured speed."
        public static let speedMeasured =
            "Measured speed comes from the watch's own speed channel. "
            + "Speed estimated from positions is marked."
        public static let speedFreshness =
            "The dot on a record's name says how fresh it is. "
            + "Filled within a month. Hollow within the season. "
            + "Faint when it is older than 6 months."
        public static let sessionRecordsFooter =
            "These are your best afternoons rather than your best windows, so nothing here "
            + "is marked estimated. A poor recording can get a speed wrong, but the jibe "
            + "count and the minutes are not about speed."
        public static let emptyLibrary =
            "Import or sync a session and its speed records appear here."
        public static let noMeasured =
            "No measured speed record yet. These recordings worked their speed out "
            + "from positions. Settings has the other two answers."
        public static let noQualifying = "No qualifying speed window under this filter."
        public static let noRecords = "No records yet"

        static let all: [String: String] = [
            "speedHead": speedHead, "speedMeasured": speedMeasured,
            "speedFreshness": speedFreshness, "sessionRecordsFooter": sessionRecordsFooter,
            "emptyLibrary": emptyLibrary, "noMeasured": noMeasured,
            "noQualifying": noQualifying, "noRecords": noRecords,
        ]
    }

    /// `TrendsView`: the chart titles, their notes and the empty range. The titles spell
    /// the rate codes out (pattern H); the code stays beside the words.
    public enum Trends {
        public static let nothingInRange = "Nothing in this range"
        public static let widenTheRange =
            "Widen the range or clear the spot and gear filters."
        public static let onFoil = "On foil"
        public static let cleanJibes = "Clean jibes"
        public static let cleanJibesNote =
            "Jibes that flew through, held at least 70 % of their entry speed, then 10 quiet "
            + "seconds on the foil."
        public static let best2s = "Best 2 s"
        public static let best2sNote = "Your quickest two seconds of the session."
        public static let longestFlight = "Longest flight"
        public static let flewThrough = "Flew-through rate"
        public static let flewThroughNote =
            "Turns that never lost the foil. Every counted turn, not jibes alone."
        public static let cph = "Clean jibes an hour (CPH)"
        public static let jph = "Dry jibes an hour (JPH)"
        public static let jphNote = "Jibes you sailed out of without falling in."
        public static let tph = "Dry turns an hour (TPH)"
        public static let tphNote = "Every counted turn you stayed dry through."
        public static let pumps = "Pumps to takeoff"
        public static let pumpsNote =
            "Only sessions recorded with the CleanJibe watch app count your pumps."
        public static let portShare = "Port / starboard"
        public static let portShareNote = "50 % is even. The gap is the side you avoid."
        public static let bySide = "Flew through by entry tack"
        public static let bySideEmpty =
            "No session in this range has turns with a usable entry tack. "
            + "That needs a wind direction the app can trust."
        public static let bySideNote =
            "Each line splits your turns by the tack you came in on. Course changes do not "
            + "count."
        public static let perWeek = "Sessions per week"
        public static let weeksOnTheWater = "{ridden} of {weeks} weeks on the water."
        public static let weekRuns = "A week runs Monday to Sunday, on your phone's clock."
        /// The button beside Periods that makes a card of the range on screen.
        public static let share = "Share card"

        static let all: [String: String] = [
            "nothingInRange": nothingInRange, "widenTheRange": widenTheRange,
            "onFoil": onFoil, "cleanJibes": cleanJibes, "cleanJibesNote": cleanJibesNote,
            "best2s": best2s, "best2sNote": best2sNote, "longestFlight": longestFlight,
            "flewThrough": flewThrough, "flewThroughNote": flewThroughNote, "cph": cph,
            "jph": jph, "jphNote": jphNote, "tph": tph, "tphNote": tphNote, "pumps": pumps,
            "pumpsNote": pumpsNote, "portShare": portShare, "portShareNote": portShareNote,
            "bySide": bySide, "bySideEmpty": bySideEmpty, "bySideNote": bySideNote,
            "perWeek": perWeek, "weeksOnTheWater": weeksOnTheWater, "weekRuns": weekRuns,
            "share": share,
        ]
    }

    /// `PeriodsView`: the three groups, the empty page and the range of your own.
    public enum Periods {
        public static let empty = "No periods yet"
        public static let emptyLine =
            "A session needs a recorded start before it can belong to a month. "
            + "Import one and the months, seasons and trips fill in."
        public static let trips = "Trips"
        public static let tripsNote = "Spells at one spot. A holiday the library noticed. No gap wider than {days} days, at least {sessions} sessions."
        public static let months = "Months"
        public static let monthsNote = "Calendar months, by the day you rode."
        public static let seasons = "Seasons"
        public static let seasonsNote =
            "1 April to 31 March, so a February session counts towards the winter it "
            + "belongs to."
        public static let noSessionInRange = "No session in that range."
        public static let bothDatesCount = "Both dates count."
        public static let rangeRates =
            "A rate over your range divides the range's own totals. It never averages the "
            + "sessions' rates."
        public static let periodRates = "Every rate here is over these afternoons' own hours."
        public static let periodRatesMore =
            "Clean jibes an hour is every clean jibe of the period over all its hours on the "
            + "water."

        static let all: [String: String] = [
            "empty": empty, "emptyLine": emptyLine, "trips": trips, "tripsNote": tripsNote,
            "months": months, "monthsNote": monthsNote, "seasons": seasons,
            "seasonsNote": seasonsNote, "noSessionInRange": noSessionInRange,
            "bothDatesCount": bothDatesCount, "rangeRates": rangeRates,
            "periodRates": periodRates, "periodRatesMore": periodRatesMore,
        ]
    }

    // MARK: - Gear & spots

    /// `GearView` and `SpotsView`.
    public enum Gear {
        public static let noSpots = "No spots yet"
        public static let noSpotsLine = "Spots appear once sessions with GPS are in the library."
        public static let spotsFooter = "Tap a spot to rename it. A name you type sticks through a re-cluster. Sessions starting within {radius} m of each other are one spot. Names come from the map when the network allows."
        public static let nameExample = "e.g. \"Duotone Unit 5 m\", \"Armstrong HA 925\"."
        public static let notesPlaceholder = "Size, year, anything worth remembering"
        public static let inTheQuiver = "In the quiver"
        public static let retire = "Turn off to retire it without losing its sessions."

        static let all: [String: String] = [
            "noSpots": noSpots, "noSpotsLine": noSpotsLine, "spotsFooter": spotsFooter,
            "nameExample": nameExample, "notesPlaceholder": notesPlaceholder,
            "inTheQuiver": inTheQuiver, "retire": retire,
        ]
    }

    // MARK: - Settings

    /// `LibraryBackupSection`: what a restore does to the library it lands in.
    public enum Backup {
        public static let restoreKeeps =
            "Nothing is deleted or overwritten. Sessions you already have keep their own "
            + "analysis."
        public static let restoreFillsIn =
            "Only details you never filled in are taken from the backup."
        public static let restoreDeleted = "Sessions you deleted after this backup stay deleted."

        static let all: [String: String] = [
            "restoreKeeps": restoreKeeps, "restoreFillsIn": restoreFillsIn,
            "restoreDeleted": restoreDeleted,
        ]
    }

    // MARK: - The export

    /// Every group above, by the name the browser keys it on.
    public static let groups: [String: [String: String]] = [
        "turnPage": TurnPage.all,
        "flightEndPage": FlightEndPage.all,
        "sessionLog": SessionLog.all,
        "share": Share.all,
        "rider": Rider.all,
        "library": Library.all,
        "turns": Turns.all,
        "records": Records.all,
        "trends": Trends.all,
        "periods": Periods.all,
        "gear": Gear.all,
        "backup": Backup.all,
    ]
}
