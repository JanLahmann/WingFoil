# The browser app's words, string by string

Step 1 of "web = app" (Jan, 28 September 2026: *the iPhone app is the golden master for
layout and wording; the web is generated from it or mostly identical*). This is the
inventory: every rider-visible string in `web/app/index.html` and `web/js/*.js`, and where
its words come from.

**How the words flow.** The kit authors them (`AppShellCopy` and the constants its export
test names); `AppShellCopyExportTests` writes `docs/copy/app-words.json`;
`web/tools/make_app_copy.py` turns it into `WORDS` and `say()` in `web/js/appcopy.js`, and
writes the text of every `data-w="group.key"` element in `web/app/index.html`.
`web/tools/check_web_literals.py` (in `make web-verify` and CI) fails a rider sentence typed
into web code that `docs/web-parity/web-only.json` does not keep with a reason, a `say()`
key the kit did not write, and an allow-list entry that no longer matches.

What the check calls a sentence is `check_voice.py`'s bar: four words closed by `.`, `?` or
`!`, or eight words. Labels under that bar (a tab, a button, a column head) are listed in
section 3 and move in step 2, with the layouts.

## 1. Said through the app's words — 151 strings

The browser reads each of these from `WORDS`; none is typed in web code. "Twin" is where the
phone authors it. `*` marks a key the file picks at run time (`say(`turnCoach.${rule}`)`).

| key | twin (kit) | web | words |
|---|---|---|---|
| `backup.restoreDeleted` | AppShellCopy.Backup (LibraryBackupSection) | backup.js | Sessions you deleted after this backup stay deleted. |
| `backup.restoreKeeps` | AppShellCopy.Backup (LibraryBackupSection) | backup.js | Nothing is deleted or overwritten. Sessions you already have keep their own analysis. |
| `copy.axisSweep` | Copy | turnpage.js | Through the axis · {before}° before, {after}° after |
| `copy.northAndWind` | Copy | turnpage.js | North and the wind are marked top right. |
| `copy.noWindForOrientation` | Copy | turnpage.js | Wind up needs a wind direction. This session has none the engine trusts, and none set on the watch. |
| `copy.outcomeWindow` | Copy | turnpage.js | "Outcome" is the {seconds} s the verdict is read from. |
| `copy.pathNumbers` | Copy | turnpage.js | The numbers along the path are every five. |
| `discipline.experimentalNote` | DisciplineLexicon.experimentalNote | lexicon.js | Experimental. Windsurf analysis is untested. Jibes and tacks work. Pumping is off and planing thresholds ar… |
| `exampleOnly.records` | ExampleOnlyNote | trends.js* | The example session is on loan, not ridden, so it is kept out of your personal records on purpose. Import a… |
| `exampleOnly.recordsTitle` | ExampleOnlyNote | trends.js, trends.js* | Your records start with your first session |
| `exampleOnly.trends` | ExampleOnlyNote | trends.js* | The example session is on loan, not ridden, so it is kept out of your trends on purpose. Import a .fit file… |
| `exampleOnly.trendsTitle` | ExampleOnlyNote | trends.js, trends.js* | Your trends start with your first session |
| `flightEndPage.backAfter` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | Back to flying speed {time} after the end. |
| `flightEndPage.drawnNorthUp` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | The track is drawn north up. |
| `flightEndPage.footBorderline` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | "Borderline" means the stop ran past the touchdown limit without reaching the fall one. |
| `flightEndPage.footChannel` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | Speed here is the manoeuvre channel, derived from position. The GPS Doppler speed the records use is smooth… |
| `flightEndPage.footDrawn` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | The drawing is {before} s before the end and {after} s after it. |
| `flightEndPage.footEntryBand` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | The bands are the engine's windows. "Entry" is the {seconds} s the flight was ending at. |
| `flightEndPage.footEvidence` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | "Evidence" is how much gap-free recording there actually was. |
| `flightEndPage.footInOut` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | "In" is the fastest sample of the entry window. "Out" is where the speed came back to the engine's flying-a… |
| `flightEndPage.footLow` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | Only "low" is the engine's. It is the slowest sample of the off-foil run, placed where this window comes ne… |
| `flightEndPage.footMarks` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | The thick, coloured part is the flight. Everything past the dot is already off the foil. Ticks are one seco… |
| `flightEndPage.footNoRecord` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | Both are read off the drawn line. A flight end record holds no entry or exit speed of its own. |
| `flightEndPage.neverBack` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | Never back up to flying speed inside the window. |
| `flightEndPage.noGeometry` | AppShellCopy.FlightEndPage (FlightEndDetailView) | turnpage.js | No GPS fixes through this flight end. Numbers only. |
| `gear.inTheQuiver` | AppShellCopy.Gear (GearView, SpotsView) | app/index.html | In the quiver |
| `gear.nameExample` | AppShellCopy.Gear (GearView, SpotsView) | app/index.html | e.g. "Duotone Unit 5 m", "Armstrong HA 925". |
| `gear.noSpots` | AppShellCopy.Gear (GearView, SpotsView) | appshell.js, spots.js | No spots yet |
| `gear.noSpotsLine` | AppShellCopy.Gear (GearView, SpotsView) | appshell.js, spots.js | Spots appear once sessions with GPS are in the library. |
| `gear.retire` | AppShellCopy.Gear (GearView, SpotsView) | app/index.html | Turn off to retire it without losing its sessions. |
| `gear.spotsFooter` | AppShellCopy.Gear (GearView, SpotsView) | spots.js | Tap a spot to rename it. A name you type sticks through a re-cluster. Sessions starting within {radius} m o… |
| `icu.emptyFix` | IcuProblem (title / message / fix) | icu.js | Connect Garmin in intervals.icu (Settings → device connections) — the back-fill takes a few minutes. If it … |
| `icu.emptyMessage` | IcuProblem (title / message / fix) | icu.js | intervals.icu accepted the key but has no watersport activities to hand over yet. |
| `icu.noKeyFix` | IcuProblem (title / message / fix) | icu.js | Paste your personal API key: intervals.icu → Settings → Developer Settings. |
| `icu.serverFix` | IcuProblem (title / message / fix) | icu.js | This is usually temporary. Try again in a few minutes. |
| `icu.serverMessageDetail` | IcuProblem (title / message / fix) | icu.js | intervals.icu answered with an error ({detail}). That is its end, not yours. |
| `icu.unauthorizedFix` | IcuProblem (title / message / fix) | icu.js | Copy the key again from intervals.icu → Settings → Developer Settings and paste it fresh — a stray space at… |
| `icu.unauthorizedMessage` | IcuProblem (title / message / fix) | icu.js | The key is wrong, or it was regenerated in intervals.icu after you pasted it here. |
| `library.noMatch` | AppShellCopy.Library (LibraryView) | trends.js | No session matches these filters |
| `library.noMatchLine` | AppShellCopy.Library (LibraryView) | trends.js | Nothing in the library answers to all of them at once. |
| `periods.empty` | AppShellCopy.Periods (PeriodsView) | trends.js | No periods yet |
| `periods.emptyLine` | AppShellCopy.Periods (PeriodsView) | trends.js | A session needs a recorded start before it can belong to a month. Import one and the months, seasons and tr… |
| `periods.months` | AppShellCopy.Periods (PeriodsView) | trends.js | Months |
| `periods.monthsNote` | AppShellCopy.Periods (PeriodsView) | trends.js | Calendar months, by the day you rode. |
| `periods.noSessionInRange` | AppShellCopy.Periods (PeriodsView) | trends.js | No session in that range. |
| `periods.rangeRates` | AppShellCopy.Periods (PeriodsView) | trends.js | A rate over your range divides the range's own totals. It never averages the sessions' rates. |
| `periods.seasons` | AppShellCopy.Periods (PeriodsView) | trends.js | Seasons |
| `periods.seasonsNote` | AppShellCopy.Periods (PeriodsView) | trends.js | 1 April to 31 March, so a February session counts towards the winter it belongs to. |
| `periods.trips` | AppShellCopy.Periods (PeriodsView) | trends.js | Trips |
| `periods.tripsNote` | AppShellCopy.Periods (PeriodsView) | trends.js | Spells at one spot. A holiday the library noticed. No gap wider than {days} days, at least {sessions} sessi… |
| `records.noMeasured` | AppShellCopy.Records (RecordsView) | trends.js | No measured speed record yet. These recordings worked their speed out from positions. Settings has the othe… |
| `records.noQualifying` | AppShellCopy.Records (RecordsView) | trends.js | No qualifying speed window under this filter. |
| `records.sessionRecordsFooter` | AppShellCopy.Records (RecordsView) | trends.js | These are your best afternoons rather than your best windows, so nothing here is marked estimated. A poor r… |
| `records.speedHead` | AppShellCopy.Records (RecordsView) | trends.js | Doppler speed, GP3S windows. {certified} of {count} have measured speed. |
| `records.speedMeasured` | AppShellCopy.Records (RecordsView) | trends.js | Measured speed comes from the watch's own speed channel. Speed estimated from positions is marked. |
| `rider.friendKeptOut` | AppShellCopy.Rider (RiderPromptView) | app/index.html | It stays out of your records, your trends and your gear totals. |
| `rider.friendShown` | AppShellCopy.Rider (RiderPromptView) | app/index.html | A friend's session is shown in full. You get the map, the chart, the replay, everything. |
| `rider.question` | AppShellCopy.Rider (RiderPromptView) | app/index.html | Whose session is this? |
| `sessionLog.takeoffsDiffer` | AppShellCopy.SessionLog (SessionLogView) | log.js | Takeoff and pump counting is where the two differ most. Keep the watch app up to date to narrow the gap. |
| `sessionLog.trustThePhone` | AppShellCopy.SessionLog (SessionLogView) | log.js | Trust the phone's numbers. It reads the whole session back afterwards. The watch has to work these out live… |
| `sessionMail.commentLabel` | SessionAnalysisMail | senddev.js | What looks wrong: |
| `sessionMail.consentHolds` | SessionAnalysisMail | senddev.js | The file holds your track, your heart rate and your times. |
| `sessionMail.consentUse` | SessionAnalysisMail | senddev.js | It is used only to improve the detection. It is never published. |
| `sessionMail.originalAttached` | SessionAnalysisMail | senddev.js | The original recording, as it was imported. |
| `sessionMail.prompt` | SessionAnalysisMail | senddev.js | What looks wrong? Which turns or times? |
| `sessionMail.subject` | SessionAnalysisMail | senddev.js | CleanJibe session {date} · for analysis |
| `settings.detailCaption` | SettingsCopy.detail* | app/index.html | Concise keeps one line under every section. Extensive prints its help page under it. |
| `settings.detailConcise` | SettingsCopy.detail* | app/index.html | Concise |
| `settings.detailExtensive` | SettingsCopy.detail* | app/index.html | Extensive |
| `settings.detailTitle` | SettingsCopy.detail* | app/index.html | How much to say |
| `share.sendToUs` | AppShellCopy.Share (ShareComposerView, SendToDeveloperSheet) | app/index.html | Send this session to us |
| `share.sendToUsLine` | AppShellCopy.Share (ShareComposerView, SendToDeveloperSheet) | app/index.html | A number looks wrong? Send the recording with your notes. |
| `speedRecords.includeUnverified` | SpeedRecordPolicy.label / .summary | app/index.html | Include estimated |
| `speedRecords.includeUnverifiedSummary` | SpeedRecordPolicy.label / .summary | appshell.js | Every record counts. Estimated ones are marked. |
| `speedRecords.onlyVerified` | SpeedRecordPolicy.label / .summary | app/index.html | Only measured |
| `speedRecords.onlyVerifiedSummary` | SpeedRecordPolicy.label / .summary | appshell.js | Only records your watch measured. Nothing else counts. |
| `speedRecords.preferVerified` | SpeedRecordPolicy.label / .summary | app/index.html | Prefer measured |
| `speedRecords.preferVerifiedSummary` | SpeedRecordPolicy.label / .summary | appshell.js | A measured record wins. An estimated one fills an empty row, marked. |
| `trends.best2s` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | Best 2 s |
| `trends.best2sNote` | AppShellCopy.Trends (TrendsView) | trends.js* | Your quickest two seconds of the session. |
| `trends.bySide` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | Flew through by entry tack |
| `trends.bySideEmpty` | AppShellCopy.Trends (TrendsView) | trends.js* | No session in this range has turns with a usable entry tack. That needs a wind direction the app can trust. |
| `trends.bySideNote` | AppShellCopy.Trends (TrendsView) | trends.js* | Each line splits your turns by the tack you came in on. Course changes do not count. |
| `trends.cleanJibes` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | Clean jibes |
| `trends.cleanJibesNote` | AppShellCopy.Trends (TrendsView) | trends.js* | Jibes that flew through, held at least 70 % of their entry speed, then 10 quiet seconds on the foil. |
| `trends.cph` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | Clean jibes an hour (CPH) |
| `trends.flewThrough` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | Flew-through rate |
| `trends.flewThroughNote` | AppShellCopy.Trends (TrendsView) | trends.js* | Turns that never lost the foil. Every counted turn, not jibes alone. |
| `trends.jph` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | Dry jibes an hour (JPH) |
| `trends.jphNote` | AppShellCopy.Trends (TrendsView) | trends.js* | Jibes you sailed out of without falling in. |
| `trends.longestFlight` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | Longest flight |
| `trends.nothingInRange` | AppShellCopy.Trends (TrendsView) | trends.js* | Nothing in this range |
| `trends.onFoil` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | On foil |
| `trends.perWeek` | AppShellCopy.Trends (TrendsView) | trends.js, trends.js* | Sessions per week |
| `trends.portShare` | AppShellCopy.Trends (TrendsView) | trends.js* | Port / starboard |
| `trends.portShareNote` | AppShellCopy.Trends (TrendsView) | trends.js* | 50 % is even. The gap is the side you avoid. |
| `trends.pumps` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | Pumps to takeoff |
| `trends.pumpsNote` | AppShellCopy.Trends (TrendsView) | trends.js* | Only sessions recorded with the CleanJibe watch app count your pumps. |
| `trends.tph` | AppShellCopy.Trends (TrendsView) | trends.js (CHART_TITLE), trends.js* | Dry turns an hour (TPH) |
| `trends.tphNote` | AppShellCopy.Trends (TrendsView) | trends.js* | Every counted turn you stayed dry through. |
| `trends.weekRuns` | AppShellCopy.Trends (TrendsView) | trends.js* | A week runs Monday to Sunday, on your phone's clock. |
| `trends.weeksOnTheWater` | AppShellCopy.Trends (TrendsView) | trends.js, trends.js* | {ridden} of {weeks} weeks on the water. |
| `trends.widenTheRange` | AppShellCopy.Trends (TrendsView) | trends.js, trends.js* | Widen the range or clear the spot and gear filters. |
| `turnCoach.axisAfter` | TurnCoach.lines | turnpage.js* | You held {score} of your entry speed. The board did not come far enough past the wind axis. This one is not… |
| `turnCoach.cleanAndFast` | TurnCoach.lines | turnpage.js* | Clean, and you barely slowed. You held {score} of your entry speed all the way round. |
| `turnCoach.cleanButSlow` | TurnCoach.lines | turnpage.js* | You flew all the way through, and it cost you speed. {entry} in, {low} at the low point. |
| `turnCoach.fellIn` | TurnCoach.lines | turnpage.js* | This one ended in the water. {entry} coming in, {low} at the low point. |
| `turnCoach.fellInFast` | TurnCoach.lines | turnpage.js* | You held {score} of your entry speed right round. It still ended in the water. |
| `turnCoach.flewAndFast` | TurnCoach.lines | turnpage.js* | You flew through and barely slowed. You held {score} of your entry speed all the way round. |
| `turnCoach.flewStraightAway` | TurnCoach.lines | turnpage.js, turnpage.js* | It was flying again straight away. |
| `turnCoach.midJibe` | TurnCoach.lines | turnpage.js, turnpage.js* | downwind point |
| `turnCoach.midOther` | TurnCoach.lines | turnpage.js, turnpage.js* | middle of the turn |
| `turnCoach.midTack` | TurnCoach.lines | turnpage.js, turnpage.js* | head-to-wind |
| `turnCoach.offFoilThenFlew` | TurnCoach.lines | turnpage.js, turnpage.js* | {seconds} off the foil before it flew again. |
| `turnCoach.plain` | TurnCoach.lines | turnpage.js* | {entry} in, {low} at the low point. You held {score} of your entry speed. |
| `turnCoach.pumpedOut` | TurnCoach.lines | turnpage.js, turnpage.js* | You pumped this one back out. |
| `turnCoach.pumpedOutIn` | TurnCoach.lines | turnpage.js, turnpage.js* | You pumped this one back out in {strokes}. |
| `turnCoach.quietFlightEnd` | TurnCoach.lines | turnpage.js* | You rode the turn itself and held {score} of your entry speed. The foil went a few seconds later, so this o… |
| `turnCoach.quietOffFoil` | TurnCoach.lines | turnpage.js* | You rode the turn, then the foil dropped again on the way out. This one does not count as clean. |
| `turnCoach.quietSubmerged` | TurnCoach.lines | turnpage.js* | You held {score} of your entry speed through the turn. The barometer then saw your wrist go under. This one… |
| `turnCoach.slowedEarly` | TurnCoach.lines | turnpage.js* | The speed went before the {mid}. You were down to {low} with the turn still to come. |
| `turnCoach.slowedLate` | TurnCoach.lines | turnpage.js* | You held it into the {mid}. The speed went on the way out, down to {low}. |
| `turnCoach.touchdownComingIn` | TurnCoach.lines | turnpage.js* | The foil touched down before the {mid}. The speed was already at {low} going in. |
| `turnCoach.touchdownOnExit` | TurnCoach.lines | turnpage.js* | The foil touched down on the way out. You held {entry} into the {mid} and lost it after. |
| `turnCoach.wristUnder` | TurnCoach.lines | turnpage.js* | The barometer saw your wrist go under here. The foil was gone for a moment. {entry} in, {low} at the low po… |
| `turnCoachTips.carryFurther` | TurnCoach.tipLines | turnpage.js* | Next time, carry the turn further past the wind axis before you settle. |
| `turnCoachTips.comeInFaster` | TurnCoach.tipLines | turnpage.js* | Next time, come in with more speed. |
| `turnCoachTips.comeInFasterJibe` | TurnCoach.tipLines | turnpage.js, turnpage.js* | Next time, come in faster, or keep the wing powered through the downwind point. |
| `turnCoachTips.powerUpOnExit` | TurnCoach.tipLines | turnpage.js* | Next time, power the wing up as soon as you are on the new tack. |
| `turnCoachTips.rideItOut` | TurnCoach.tipLines | turnpage.js, turnpage.js* | Next time, stay on the foil for {hold} after the turn, and it counts as clean. |
| `turnCoachTips.rideItOutHold` | TurnCoach.tipLines | turnpage.js, turnpage.js* | a few seconds |
| `turnCoachTips.steadyExit` | TurnCoach.tipLines | turnpage.js* | Next time, stay low and steady on the way out. |
| `turnPage.compareWithBest` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | Compare with best clean jibe |
| `turnPage.drawnNorthUp` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | The turn is drawn north up. |
| `turnPage.footAxis` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | The tick marked "axis" is the moment the board went through the wind axis. That is dead downwind on a jibe,… |
| `turnPage.footDrawn` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | The drawing is {before} s before the sweep and {after} s after it. |
| `turnPage.footEntryBand` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | The bands under the strip are the engine's windows. "Entry" is the {seconds} s before the sweep, where the … |
| `turnPage.footLighterBand` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | The lighter band inside it ends where you were flying again. |
| `turnPage.footQuiet` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | A clean jibe also needs {seconds} s after the sweep with no touchdown, fall or wrist under. |
| `turnPage.footRamp` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | The line is coloured by speed on the ramp at the foot of the picture. Cold is a standstill, teal is the spe… |
| `turnPage.footSweepBand` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | "Sweep" is where the heading turned. The low point is searched to {seconds} s past the sweep, so it can sit… |
| `turnPage.footTap` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | Tap the drawing for the reading at that sample. The strips follow it. |
| `turnPage.footTicks` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | Ticks are one second apart. |
| `turnPage.noBearings` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | No usable bearings through this window. The steps were shorter than the receiver's own scatter. |
| `turnPage.noGeometry` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | No GPS fixes through this turn. Numbers only. |
| `turnPage.nothingToCompare` | AppShellCopy.TurnPage (TurnDetailView, TurnHeadingStripView) | turnpage.js | Nothing to compare with. This session has no other jibe that flew through the same way round. |
| `turns.cleanRule` | AppShellCopy.Turns (TurnsAnalysisView) | render.js | Clean: you flew through, held at least {pct} % of your entry speed, then {quiet} quiet seconds on the foil. |
| `recordingClass.a` | RecordingClass.line (recording-classes.json) | render.js* | Everything. Foil time, flights, every turn verdict and clean jibe, measured speed records, the wind axis. P… |
| `recordingClass.b` | RecordingClass.line (recording-classes.json) | render.js* | Everything except pump strokes and takeoff attempts, which need a wrist accelerometer nothing else records. |
| `recordingClass.bPlus` | RecordingClass.line (recording-classes.json) | render.js* | Everything class B gets, plus pump strokes and takeoff attempts. The watch app records the wrist at 50 Hz. … |
| `recordingClass.c` | RecordingClass.line (recording-classes.json) | render.js* | Foil time, flights, every turn verdict and clean jibe, the wind axis. Speed records are estimated from posi… |

**Exported, not yet shown by the browser — 24.** The phone says them; the browser's
layout has no place for them until step 2 (a chart note, the freshness dots, the beta's
consent clause the browser must not say because it sends the file unscrubbed):

`backup.restoreFillsIn`, `copy.deleteAnyLine`, `gear.notesPlaceholder`, `icu.emptyTitle`, `icu.networkFix`, `icu.networkMessage`, `icu.networkTitle`, `icu.noKeyMessage`, `icu.noKeyTitle`, `icu.serverMessage`, `icu.serverTitle`, `icu.unauthorizedTitle`, `icu.unknownFix`, `icu.unknownMessage`, `icu.unknownTitle`, `periods.bothDatesCount`, `periods.periodRates`, `periods.periodRatesMore`, `records.emptyLibrary`, `records.noRecords`, `records.speedFreshness`, `rider.friendKeptOutBeta`, `sessionMail.consentStripped`, `turns.outcomeAndHeld`

## 2. The browser's own — 140 allow-list entries

Kept in `docs/web-parity/web-only.json`, grouped by reason. Two kinds: a function the web has
and the phone does not (storage in the tab, the engine download, a mail link, a dropped
file), and a sentence another verifier already pins to the phone (`pinned:`).

| reason | file | sentence (substring) |
|---|---|---|
| the page's own meta description and share-card alt text: the website's, not a screen's | app/index.html | Drop a wingfoil .fit file and get the session back |
| 〃 | app/index.html | Drop a .fit file and get the whole session |
| 〃 | app/index.html | a wingfoil track with two flights drawn on the foil |
| the service worker's update bar: a browser tab updates itself, the App Store updates the phone | app/index.html | A new version is ready. |
| the web share target: the phone's share sheet hands the file over directly | app/index.html | That shared file did not arrive. |
| the drop zone: a browser takes a file by drag and drop | app/index.html | Or choose a file. It never leaves this tab. |
| pinned: verify_app_shell.py holds the ways-in rows to docs/copy/app-shell.json (waysIn, the web's half of t… | app/index.html | 10 real minutes on Lake Garda |
| 〃 | app/index.html | Paste your intervals.icu key in Settings. |
| 〃 | app/index.html | A browser cannot reach your watch. |
| 〃 | app/index.html | Apple Health is closed to a browser. |
| 〃 | app/index.html | Export the file. Then drop it here. |
| 〃 | app/index.html | Strava sign-in needs it. |
| the analyzer's own card: the formats a dropped file may take | app/index.html | .fit, .gpx and .tcx all work. |
| the analyzer's privacy line: the analysis runs in the tab | app/index.html | Your file never leaves this browser tab. |
| the Pyodide engine download, which the phone does not have | app/index.html | The engine downloads once, about 12 MB |
| 〃 | js/worker.js | Could not reach the Pyodide CDN |
| the Pyodide engine's progress, which the phone does not have | app/index.html | The tab is working, not stuck. |
| the analyzer's rejected-file help: the phone's pickers only offer files it reads | app/index.html | Most often the file is not a FIT recording. |
| 〃 | app/index.html | If the message below counts recordings |
| the browser's pointer to its Share button; the phone's Share is in the toolbar | app/index.html | Make a card of this. |
| the glossary fold's door to the Help page, a browser layout (step 2) | app/index.html | The rest of the reference is in |
| the browser's concise line beside a `?` (js/explain.js); the phone shows the `?` alone | app/index.html | The shape of the track carries the outcome. |
| 〃 | app/index.html | Every flight, over the session. Drag to scrub. |
| points at a phone-only card (docs/screens.md) | app/index.html | What the pumping cost in heartbeats is on the iPhone app. |
| pinned: verify_app_shell.py holds the data-empty sentence of a ported screen to the phone (PORTED_SCREENS) | app/index.html | Add your wings, boards and foils on the Gear tab. |
| 〃 | app/index.html | Watch and phone agree. |
| 〃 | app/index.html | No backup picked yet. |
| 〃 | app/index.html | No deleted sessions yet. |
| the browser's Log tab lede; the phone's Log carries the badges in place | app/index.html | The wind and the source of this recording are in the badges above. |
| the analysis JSON download, a browser door (docs/screens.md, deviation) | app/index.html | Every number on this page, as one JSON file. |
| a page lede under the title: the phone's tab has a large title and no lede (step 2 decides) | app/index.html | Your bests across the library |
| 〃 | app/index.html | Session by session, over the library. |
| 〃 | app/index.html | A trip, a month or a season |
| 〃 | app/index.html | Your spots and your gear. Both stay in this browser. |
| 〃 | app/index.html | Your accounts, your units and what this browser keeps. |
| where the key is kept: the phone keeps it in its keychain and says so in its own Settings | app/index.html | Your API key stays in this browser |
| a phone-only Settings section, said where it is (settings.json phoneOnly) | app/index.html | Strava is on the iPhone app. Signing in needs it. |
| 〃 | app/index.html | On the iPhone app. |
| site data only a browser can wipe (docs/screens.md, deviation 18) | app/index.html | Delete everything on this site? |
| the full-screen map's mouse and keyboard controls | app/index.html | Drag to pan. Scroll or pinch to zoom. Escape closes. |
| the browser's range narrows Trends' charts; the phone's range filter narrows its list | app/index.html | The range narrows these charts only. |
| the browser shares the original .fit unscrubbed; the phone's copy is scrubbed and says so | app/index.html | The file as it was recorded. |
| 〃 | app/index.html | It is the original from your watch |
| the browser card composer's own title field (step 2 ports the phone's composer) | app/index.html | Empty keeps the name read off the recording |
| the browser card's map tiles come from OpenStreetMap; the phone's from Apple Maps | app/index.html | Draws the track over OpenStreetMap. |
| the browser card's download line | app/index.html | nothing leaves this device until you send it. |
| the site footer every page of cleanjibe.org carries; verify_copy.py pins its feedback words to docs/copy/fe… | app/index.html | Free and open source. No server, no upload, no account. |
| 〃 | app/index.html | About CleanJibe · Get started |
| 〃 | app/index.html | Ideas and wishes are as welcome as bugs. |
| the website's analytics note (web/privacy) | app/index.html | We count page views and feature use with umami. |
| the record-window highlight bar, a browser control | js/app.js | is marked in orange on the track and on the speed strip. |
| a dropped file of the wrong type: the phone's pickers only offer files it reads | js/app.js | is not a .fit, .gpx, .tcx or .zip file. |
| 〃 | js/app.js | A .gpx or .tcx works too. |
| how the browser hands a recording over: the share sheet where there is one, else a mail link that cannot ca… | js/app.js | Handed to your share sheet. |
| 〃 | js/app.js | The recording was downloaded and a mail opened. |
| 〃 | js/app.js | Cancelled. Nothing left this browser. |
| 〃 | js/senddev.js | Attach the file CleanJibe just downloaded. |
| the fact sheet of the browser's mail, a strip of counts | js/app.js | flew through · … touchdown · … fell in |
| browser storage: the tab may hold the analysis without its file | js/app.js | This session has no recording in this browser. |
| browser storage (IndexedDB / OPFS), which the phone does not have | js/appdb.js | offers no IndexedDB |
| 〃 | js/gear.js | Your gear could not be read. |
| 〃 | js/library.js | Storage is unavailable in this browser context. |
| 〃 | js/library.js | Analysing files still works. Only saving does not. |
| 〃 | js/store.js | offers neither OPFS nor IndexedDB |
| 〃 | js/store.js | has an index entry but no stored analysis. |
| 〃 | js/store.js | has an index entry but no stored FIT. |
| a fallback for a help catalogue missing from the bundle | js/appshell.js | The guide is on the iPhone app and on the website. |
| the browser's feedback mail: the phone attaches its own facts | js/appshell.js | Attach a screenshot or the session's .fit file if you can. |
| shown only while the help export is a stub | js/appshell.js | The full reference is on the iPhone app. |
| the browser's gear is names only, kept in the tab (docs/screens.md, Gear & spots) | js/appshell.js | A name is yours and stays in this browser. |
| 〃 | js/gear.js | Your quiver stays in this browser. |
| the browser's own backup zip, read by the browser (the phone's backup is its own format) | js/backup.js | That file is not a zip archive this browser can read. |
| 〃 | js/backup.js | uses a compression this browser cannot read. |
| 〃 | js/backup.js | This browser cannot unpack a zip. |
| 〃 | js/backup.js | That zip holds no library index |
| 〃 | js/backup.js | That backup holds no sessions. |
| 〃 | js/backup.js | were already in your library. |
| 〃 | js/backup.js | could not be read. |
| the browser's Deleted sessions list reads a tombstoned recording back; the phone offers a re-add sheet on i… | js/deleted.js | The file for that session is gone |
| 〃 | js/deleted.js | That recording could not be read again |
| 〃 | js/deleted.js | That session is already in your library, so nothing was added. |
| 〃 | js/deleted.js | is back in your library. |
| 〃 | js/deleted.js | The recording is removed from this browser |
| 〃 | js/deleted.js | Clear … deleted session…? |
| 〃 | js/deleted.js | Their recordings are removed from this browser |
| a strip of counts under a gear name | js/gear.js | session… · … km · … on foil |
| the browser analyses a file without saving it; the phone always saves | js/gear.js | Save this session to the library to name its gear. |
| the browser's intervals.icu bridge: a key in the tab, a 120-day list, and the CORS wall the phone does not … | js/icu.js | Key removed from this browser. |
| 〃 | js/icu.js | watersport activities found. Everything below is fetched |
| 〃 | js/icu.js | Download failed: HTTP |
| 〃 | js/icu.js | intervals.icu could not be reached from the browser. |
| 〃 | js/icu.js | This is almost certainly CORS. |
| 〃 | js/icu.js | Open the activity on intervals.icu. |
| 〃 | js/icu.js | Drop that file onto the drop zone |
| 〃 | js/icu.js | The original is what this engine needs. |
| 〃 | js/icu.js | A Polar, Suunto or Coros original |
| the browser asks before it replaces a stored copy; the phone's ingest decides alone (one afternoon, one ses… | js/library.js | Your library already has your watch's recording of |
| 〃 | js/library.js | This copy has positions only |
| 〃 | js/library.js | Your library has a positions-only copy of |
| 〃 | js/library.js | Replace it with your watch's recording? |
| 〃 | js/library.js | This looks like a session you already have. |
| 〃 | js/library.js | Start differs by |
| 〃 | js/library.js | Both are inside the 60 s rule |
| 〃 | js/library.js | Replace the stored copy with this one? |
| the browser's library starts empty and saves on request (docs/screens.md, Sessions) | js/library.js | Nothing saved yet. Analyze a file and press Save to library. |
| the browser's badge legend under its library list; the phone's rows carry a tag | js/library.js | Example and a friend's name mean |
| the browser confirms a delete; the phone's swipe needs none | js/library.js | The session leaves your library, your records and your trends. |
| the browser's zip export and its per-row downloads | js/library.js | The .fit and .json buttons in each row always work. |
| pinned: web/tools/clock_note.mjs holds the clock note to the kit | js/render.js | no timezone in this file, times shown on your own clock |
| the example badge's title, a browser tooltip | js/render.js | The bundled demonstration session. Not your own data. |
| the browser's flights table caption (step 2 ports the phone's list) | js/render.js | The flight ends the map marks are listed below. |
| 〃 | js/render.js | No flight in this recording. |
| the browser's fact sheet: the phone's names the phone and the build | js/senddev.js | Below is what the browser knows about this session and run. |
| a strip of facts in the map popover | js/session.js | starts flight … · … · ended: … |
| a Doppler-only file on the browser's map; the phone's importers need positions | js/session.js | No GPS positions in this file, so there is no track to draw. |
| a screen-reader description of a browser figure; the phone's charts describe themselves | js/session.js | GPS track with event markers. |
| 〃 | js/session.js | Speed over time. Drag to scrub |
| 〃 | js/turnpage.js | knots in, … at the low point after |
| 〃 | js/turnpage.js | Speed through the flight end. … knots coming in. |
| 〃 | js/turnpage.js | Speed through the turn. … knots coming in. |
| the speed strip's mouse and wheel hint | js/session.js | wheel, pinch or double-tap to zoom the time axis |
| a CSS font stack, not a sentence | js/sharecard.js | -apple-system, BlinkMacSystemFont |
| pinned: verify_copy.py holds the caption to phrases.json captionOffer | js/sharecard.js | analysed with …, free at … |
| the browser copies the caption to the clipboard; the phone hands it to the share sheet | js/sharecard.js | Caption copied. Paste it with the picture. |
| the browser's name lookup status line | js/spots.js | No new names. The lookup needs a network. |
| the Pyodide engine, which the phone does not have | js/trends.js | Records and trends need the Python runtime. |
| a library of friends' sessions: the phone's ExampleOnlyNote covers the example alone | js/trends.js | Nothing here counts towards your records yet. |
| the browser's Periods door on Trends (step 2 ports the phone's row) | js/trends.js | Trips, months and seasons, each with one block of numbers. |
| the browser's chart hint | js/trends.js | Oldest first. Click a point to open that session. |
| a period deep link (#/period/…) that outlived its sessions | js/trends.js | That period is not in this library any more. |
| how the browser's weeks are cut, each session in its own local time; the phone's run on the phone's clock | js/trends.js | Weeks start on Monday, the ISO-8601 week. |
| a strip of counts over the turn cards | js/turncards.js | hidden by the chips |
| pinned: the notClean chip is TurnAnalytics.notCleanText's, word for word (short label, step 2 moves it) | js/turnpage.js | not clean · touched down … s after |
| 〃 | js/turnpage.js | not clean · carried …° past the axis |
| the browser's decimated view of a long recording | js/turnpage.js | so the browser holds every …th sample. |
| the browser's footnote lead; the phone prints the time in its title | js/turnpage.js | It happened at …. |
| 〃 | js/turnpage.js | How to read this drawing. |
| pinned: verify_presentation.py §6 (outcome_text.mjs) holds it to TurnAnalytics.outcomeText | js/viz.js | pumped out below min foil speed, no sample off the foil |
| 〃 | js/viz.js | pumped out below …, no sample off the foil |
| an SVG path, not a sentence | js/viz.js | M-2.4,2.6 L-2.4,-0.6 |

## 3. Labels in the page — 115 distinct

Under the sentence bar, so the check does not hold them yet. "app twin, same words" means a
Swift literal with exactly these words exists; step 2 gives each a kit key when it rebuilds
the screen. Counts: 50 app twin, same words, 45 web-only or reworded (step 2), 14 pinned (app-shell.json / settings.json), 6 said (data-w).

| line | label | status |
|---|---|---|
| 93 | CleanJibe | app twin, same words |
| 96 | engine | app twin, same words |
| 106 | Menu | app twin, same words |
| 123 | What CleanJibe does | pinned (app-shell.json / settings.json) |
| 127 | Getting started | pinned (app-shell.json / settings.json) |
| 128 | Settings | pinned (app-shell.json / settings.json) |
| 129 | Help | pinned (app-shell.json / settings.json) |
| 130 | Support & ideas | pinned (app-shell.json / settings.json) |
| 131 | Join the beta | pinned (app-shell.json / settings.json) |
| 141 | Concise | said (data-w) |
| 143 | Extensive | said (data-w) |
| 151 | Close | app twin, same words |
| 159 | Reload to update | web-only or reworded (step 2) |
| 160 | Later | app twin, same words |
| 176 | Install CleanJibe | web-only or reworded (step 2) |
| 177 | Share → CleanJibe | web-only or reworded (step 2) |
| 178 | on a | web-only or reworded (step 2) |
| 178 | .fit | app twin, same words |
| 178 | or | web-only or reworded (step 2) |
| 178 | .gpx | app twin, same words |
| 180 | Install | web-only or reworded (step 2) |
| 197 | Sessions | pinned (app-shell.json / settings.json) |
| 231 | Drop a | web-only or reworded (step 2) |
| 231 | .tcx | app twin, same words |
| 231 | here | pinned (app-shell.json / settings.json) |
| 239 | Choose a file… | web-only or reworded (step 2) |
| 268 | Open Settings | app twin, same words |
| 299 | Strava | pinned (app-shell.json / settings.json) |
| 313 | What you get | app twin, same words |
| 317 | The track | app twin, same words |
| 321 | Every flight | web-only or reworded (step 2) |
| 325 | Every turn, judged | web-only or reworded (step 2) |
| 343 | and | app twin, same words |
| 367 | Starting the analyzer | web-only or reworded (step 2) |
| 370 | Analysing | web-only or reworded (step 2) |
| 377 | Cancel | app twin, same words |
| 388 | Download original file | web-only or reworded (step 2) |
| 389 | .zip | web-only or reworded (step 2) |
| 409 | Back to Sessions | web-only or reworded (step 2) |
| 430 | Session | app twin, same words |
| 439 | Share | app twin, same words |
| 440 | Save to library | web-only or reworded (step 2) |
| 501 | Track | web-only or reworded (step 2) |
| 524 | Speed | app twin, same words |
| 549 | Takeoffs | app twin, same words |
| 560 | Flights | pinned (app-shell.json / settings.json) |
| 568 | Flight ends | web-only or reworded (step 2) |
| 578 | Turns | pinned (app-shell.json / settings.json) |
| 607 | Gear | app twin, same words |
| 613 | Watch vs phone | app twin, same words |
| 620 | The recording | web-only or reworded (step 2) |
| 626 | The full analysis | web-only or reworded (step 2) |
| 633 | Download analysis JSON | web-only or reworded (step 2) |
| 647 | Records | pinned (app-shell.json / settings.json) |
| 666 | Trends | pinned (app-shell.json / settings.json) |
| 688 | Back to Trends | web-only or reworded (step 2) |
| 693 | Periods | app twin, same words |
| 703 | Back to Periods | web-only or reworded (step 2) |
| 708 | Period | web-only or reworded (step 2) |
| 721 | Gear & spots | pinned (app-shell.json / settings.json) |
| 789 | Athlete ID | web-only or reworded (step 2) |
| 790 | API key | web-only or reworded (step 2) |
| 791 | List recent activities | web-only or reworded (step 2) |
| 792 | Forget key | web-only or reworded (step 2) |
| 800 | api.intervals.icu | web-only or reworded (step 2) |
| 828 | Knots | app twin, same words |
| 829 | km/h | app twin, same words |
| 841 | Only measured | said (data-w) |
| 843 | Prefer measured | said (data-w) |
| 845 | Include estimated | said (data-w) |
| 863 | Download all (.zip) | web-only or reworded (step 2) |
| 885 | Delete everything | web-only or reworded (step 2) |
| 900 | Privacy | app twin, same words |
| 954 | Back to Settings | web-only or reworded (step 2) |
| 958 | What’s new | web-only or reworded (step 2) |
| 989 | Filter the help | web-only or reworded (step 2) |
| 1009 | Back | web-only or reworded (step 2) |
| 1056 | Get started | app twin, same words |
| 1068 | New gear | app twin, same words |
| 1069 | Name | app twin, same words |
| 1072 | Wing | app twin, same words |
| 1073 | Board | app twin, same words |
| 1074 | Foil | app twin, same words |
| 1077 | Notes | app twin, same words |
| 1081 | In the quiver | said (data-w) |
| 1085 | Save | app twin, same words |
| 1096 | Custom range | app twin, same words |
| 1097 | From | app twin, same words |
| 1098 | To | app twin, same words |
| 1103 | Done | app twin, same words |
| 1124 | Mine | app twin, same words |
| 1125 | A friend's | app twin, same words |
| 1169 | Card | app twin, same words |
| 1170 | FIT file | app twin, same words |
| 1175 | Your notes | web-only or reworded (step 2) |
| 1193 | Download the .fit | web-only or reworded (step 2) |
| 1210 | Title | app twin, same words |
| 1213 | Caption (optional) | app twin, same words |
| 1222 | Portrait | app twin, same words |
| 1223 | Square | app twin, same words |
| 1224 | Landscape | app twin, same words |
| 1230 | Clean jibes | app twin, same words |
| 1231 | Top speed | app twin, same words |
| 1232 | Tacks | app twin, same words |
| 1241 | Map background | app twin, same words |
| 1247 | PNG · | web-only or reworded (step 2) |
| 1254 | Share… | web-only or reworded (step 2) |
| 1255 | Download PNG | web-only or reworded (step 2) |
| 1275 | Turn | app twin, same words |
| 1320 | About CleanJibe | web-only or reworded (step 2) |
| 1323 | Open the app | web-only or reworded (step 2) |
| 1324 | GitHub | web-only or reworded (step 2) |
| 1331 | info@cleanjibe.org | app twin, same words |
| 1336 | issue | web-only or reworded (step 2) |

**Labels in web/js.** 216 short strings of two or three words (column heads, chip words,
button labels, units) that the sentence bar does not reach; 92 of them are a Swift
literal word for word. They move with the screens in step 2 — `python3
web/tools/check_web_literals.py --list` prints what the allow-list keeps today.

