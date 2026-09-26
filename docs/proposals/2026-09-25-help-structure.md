# Help structure — proposal (F14c, 25 September 2026)

Status: **approved by Jan on 26 September 2026 and built on `fb/help-settings-2`.** Built
as written, with the counts as they came out: 47 topics before (45 on the web), 41 after,
40 on the dev index (What's new is off it), 38 on the public web page. The merged ids
redirect (`HelpCatalog.redirects`), and Getting started's ways in became links on their
own rows instead of a "see also". The "What CleanJibe does" link from Getting started is
not built: the framing sentence went, and the menu row sits one below.

## Today

Ten sections, 45 topics (43 on the web, the two dev topics left out). One section holds a
third of the catalogue:

| section | topics |
|---|---|
| Getting started | Getting started, What the numbers mean, What's new |
| Getting set up | **16**: intervals.icu, notifications, example session, Apple Watch app, Apple Workout app, Strava, share from a watch app, phone only, browser app, which watches, watch update stuck, sync trouble, where the key is kept, what leaves your phone, library backup, sending feedback |
| On the foil | foil %, flights, longest flight, distance, reading the map |
| Speed records | speed records, verified records |
| Turns & losses | turn types, outcomes, clean jibes, port/starboard, fell in, touchdowns, glide-outs |
| Takeoff & pumping | attempts, pumps to takeoff, pump strokes |
| Effort | heart rate (1 topic) |
| Conditions | wind axis (1 topic) |
| Sharing | share card, replay clip, send to a friend, send to us, someone else's session |
| Where the numbers come from | recording classes, watch vs phone, engine version, windsurf (dev) |

"Getting set up" mixes four jobs: recording, bringing sessions in, privacy and fixing
problems. Two sections hold one topic each.

## Proposed: seven sections, in the rider's order

**Install → ride → read the numbers → share → your library → fix a problem.**

1. **Start here**: Getting started · Which watches work *(merged with "What your recording
   can show", see below)* · Look around with the example session.
2. **Record a session**: CleanJibe Apple Watch app · Apple Workout app · Recording with a
   phone only.
3. **Bring it in**: intervals.icu · Strava · Share from your watch app · CleanJibe in a
   browser · Notifications for new sessions.
4. **Read the numbers**: What the numbers mean *(first, it is the glossary)* · Reading the
   map · Flights and foil time *(foil %, flights, longest flight, distance merged)* · Speed
   records · Verified records · Turn types · Turn outcomes *(touchdowns merged in)* · Clean
   jibes · Port/starboard · Fell in · Glide-outs · Attempts · Pumps to takeoff · Pump
   strokes · Heart rate · Wind axis · Windsurf *(dev)*.
   Sub-headed on the page as today (On the foil / Records / Turns / Takeoff / Effort & wind),
   so "Effort" and "Conditions" stop being one-topic sections.
5. **Share**: Share cards · Replay clips · Sending a session to a friend.
6. **Your library**: Backing up your library · Sessions someone else rode · What leaves your
   phone *(the key-in-the-Keychain topic merged in as an item)* · Analysis engine version.
7. **Something wrong?**: When the sync does not work · The watch update does not arrive ·
   When the watch and the phone disagree · Sending feedback · Send a session to us *(beta)*.

What's new moves off the index: the menu already opens it, and the topic is a button onto
that screen.

Net: 45 → 39 topics, 10 → 7 sections, no section over 8 topics except "Read the numbers",
which is sub-headed.

## Duplicates to remove

| where | what repeats | proposal |
|---|---|---|
| Getting started items, Which watches, What your recording can show, Share from a watch app, Phone only | the ways in, four times in four shapes | Getting started keeps one line per way in, each a link. **Which watches + What your recording can show become one topic** (rows by watch, the class name in each row). |
| What the numbers mean ↔ Clean jibes | Flew through, Clean, Speed kept, Dry: the same four glossary lines, twice | Clean jibes keeps its body and the Score item; the four lines go, "See the glossary" stays. |
| What the numbers mean ↔ Speed records, Attempts | Best 5×10 s, Alpha 500, Takeoffs, Attempts | Same: the topic keeps what the glossary does not say. |
| Apple Watch app ↔ Apple Workout app | "The wrist may go under", word for word | Keep it in the Apple Watch app topic; Workout app links to it. |
| Where your API key is kept ↔ What leaves your phone | the key goes only to intervals.icu | one topic, the key as an item. |
| Flights ↔ Touchdowns ↔ Turn outcomes | a short touchdown does not split a flight | Touchdowns (one paragraph) merges into Turn outcomes. |
| Getting started framing ↔ What CleanJibe does *(menu screen, r4-welcome's)* | what a verdict is | Getting started drops its framing sentence and links to What CleanJibe does, once r4-welcome has merged the family page there. |

## "See also" lists that do not earn their place

Rule proposed: **three at most, never a topic the body already names row by row.**

- Getting started: 8 links, every one already an item above → none.
- Which watches: 8 → 3 (Share from a watch app, Apple Watch app, Strava).
- Share from a watch app: 6 → 3. What your recording can show: 6 → 3. Phone only: 5 → 3.
  Strava: 5 → 3.
- What's new → Getting started, Sending feedback: neither is a next step → none.
- Example session → Speed records, Someone else's session: not a next step → intervals.icu only.

## Link-outs (self-contained rule)

| topic | link | proposal |
|---|---|---|
| What's new | cleanjibe.org/whats-new | **remove**: the topic's button opens the notes in the app |
| Getting started | cleanjibe.org/start | keep only as "send this to a friend" (r4-welcome's call) |
| Share from your watch app | four vendor support pages | **remove**: the items carry each path, dated in the source; the links go stale and leave the app |
| Sending a session to a friend | Open the browser app | **remove**, link the "CleanJibe in a browser" topic instead |
| intervals.icu, sync trouble | Open intervals.icu | keep: the step happens there |
| What leaves your phone | cleanjibe.org/privacy | keep: a legal text has one home |
| CleanJibe in a browser | Open the browser app | keep: it is the subject |

## Left for the setup-card owner

`IcuSetupGuide` step 4 says "Paste it into the field below. In the app that field is
Settings → intervals.icu." In Help there is no field below. The guide is shared with the
setup card and /start/, so the fix is a per-surface line, not a rewrite here.
