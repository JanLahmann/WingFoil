> Part of `docs/presentation.md`. Engine 0.25.0.

## Session time — the clock a session is drawn on

**Every time either app prints for a session is the time the rider saw**, not the time the
reader's device would make of the same instant.

A FIT timestamp is UTC. Until engine 0.8.2 that instant was formatted in whatever zone the
*viewer* was currently in, which is correct only while the viewer and the recording share
one — a coincidence that ends at every DST boundary (on 25 October 2026 every session in
the library shifts by an hour, and stays shifted) and on the first session ridden abroad. A
session's time is a fact about the session, so it is stored with the session.

- **What is stored** is a UTC offset in **seconds**, not a zone name: what a source can
  tell us is an offset, and a name we had to guess would be inventing a fact.
  `session.startUtcOffsetS` (GRDB schema v7), `meta.utcOffsetS` in the web digest.
- **Where it comes from**, best answer first — and, since engine **0.9.1**, *which of these
  answered* is stored beside it (`session.startUtcOffsetSource`, schema v8;
  `meta.utcOffsetSource`; `RawTrack.start_utc_offset_source`; digest schema 4):
  1. `activity` — the recording said so itself: the FIT's own `activity` message,
     `local_timestamp − timestamp`, the offset the watch was wearing at save time (exact,
     DST included, present on every file in the corpus), or a GPX timestamp written with a
     numeric offset, which is the exporter stating the same fact;
  2. `icu` — intervals.icu's `timezone` for the activity, resolved at the session's own
     instant. Also exact; second only because it is a fact about the athlete's account
     rather than about this recording. Set on the sync path, the only caller with an
     account to ask;
  3. `longitude` — a coarse guess from the first GPS longitude, `round(lon / 15°)` hours.
     This is the *solar* offset, not the civil one — an hour out under DST, up to two inside
     a wide zone, blind to the half-hour zones — and it exists only for a source that
     carries position and nothing else;
  4. `device` — nothing could say. The offset column stays NULL, the display falls back to
     the device's zone, and the surface is allowed to say so (`SessionRow.hasKnownZone`;
     the web page's header note).

  A **NULL source** is a fifth state and means *unrecorded*: a row written before schema v8,
  or one the v8 backfill could not resolve. It reads as neither exact nor estimated and
  keeps the pre-0.9.1 wording — inventing a caveat is as wrong as inventing a certainty.

- **Why the rung had to be stored** (the 0.9.1 change). `+7200` because the watch wrote it
  down and `+7200` because the first fix was at 11° E are the same number and different
  facts, and only the first licenses a page to say *times as recorded on the water*. Engine
  0.9.0's GPX door made the difference routine rather than exotic: a GPX usually carries no
  zone at all, so rung 3 is the *normal* answer for the whole of that input class — and rung
  3 is an hour wrong in Torbole every summer, which is when people wingfoil there. The
  ladder itself did not change; what was missing was the qualification.
- **What each rung is allowed to say.** Wherever a time is shown **in the session's own
  zone**, the wording follows the source, and there are exactly two:

  | source | wording |
  |---|---|
  | `activity`, `icu`, or unrecorded | **times as recorded on the water** (web header note); no caption on iOS |
  | `longitude` | **times estimated from the track's position** (web header note; iOS `SessionDetailView.estimatedClockNote`, "Times estimated from the track's position — this recording carries no time zone.") |
  | `device` / offset NULL | the existing **no timezone in this file, times shown on your own clock**, which is already the honest sentence: this is not the session's zone at all |

  A **library row or a trend tick is not annotated** either, and for a different reason
  again: they print a *date*, and a whole-hour guess moves a date only for a session that
  starts within an hour of midnight. A caveat on every row of a list is noise on all of them
  to be right about one.

  The soft caption appears **only** on the `longitude` rung. A reassurance printed on every
  page is noise, and noise is what a reader learns to skip past on the one page where it
  says something — which is why iOS shows nothing for an exact source rather than a
  "recorded" badge, and why the web keeps its one-line note either way.
- **The replay clip's title card carries no caveat**, deliberately. The rule above is about
  a surface that makes a *data claim*: a report page states the session's facts and is read
  as a record of them. A clip is presentation — a 30-second video with a date on its opening
  frame, watched once, usually without sound, by somebody who was not there. There is no
  room for a qualifier that would be on screen for a second and a half, no reader in a
  position to act on it, and no claim being made beyond "this was that afternoon", which the
  guess supports to within an hour. The same reasoning is why the share card's date line is
  uncaptioned: both are the *picture*, and the page behind them is where the qualification
  lives. (`ReplayTitleCard` and `ShareCardStats.dateLine` still take the session's zone, and
  still get it from `row.displayZone` — the estimate is used, it is simply not annotated.)
- **One accessor, no defaults.** `SessionRow.displayZone` is the only answer, and the
  `timeZone:` parameters on `ReplayCommentary.make`, `ReplayStoryboard.make`,
  `ReplayTitleCard.make`, `ShareCardStats.make`/`outro`, `ShareText.*` and
  `FitShareFilter.filename` have **no default**. A default is a decision made silently at
  every call site, and the silent decision was wrong at all of them; with the defaults gone
  the compiler names each one and it has to answer out loud.
- **`.current` is still right in three places**, and is commented as such where it is used:
  Settings' "Last sync" and the watch link's "Last summary from the watch" (events on the reader's clock),
  the trend ranges and week buckets (the reader's calendar), and the spot/gear "last used"
  aggregates (which span sessions and have no one zone). A tombstone also keeps `.current`,
  because a deleted session's recording is gone and nothing is left that knows its zone.
- **On the web** every clock goes through `zonedFormat` (web/js/viz.js): shift the instant
  by `meta.utcOffsetS`, then format in UTC. `clockAt` and `sessionDate` take the whole
  `meta` rather than a bare `startUtc`, so a caller cannot pair the two up wrongly. The
  header note is written by `clockNoteFor` in `web/js/render.js` from the table above, and
  only names the reader's own zone when the file could not say.
- **Calendar dates too.** A session that starts at 00:30 in Torbole is a 22:30 UTC session
  on the *previous* day, so a library row, a trend x-axis tick and a share card dated on
  the UTC day would name a day the rider did not have. The digest carries `dateLocal`
  beside `dateUtc` for exactly this.
- **Pinned by** `SessionTimeZoneTests` (iOS), which ingests the bundled example through the
  real ingest path with the process default zone forced away from the session's and asserts
  the bookend, title card, share-card date line and shared filename all still read `14:07` /
  `30 August 2026`; and by `verify_presentation.py` §4, which does the same arithmetic on
  the web's `meta`. `TZ=UTC swift test` is the stronger form and is what CI runs.

  The **rungs** are pinned separately, one assertion per rung on each side, because the bug
  0.9.1 fixed was not a wrong number but a missing qualification and a ladder that quietly
  reordered would otherwise still pass: `SessionTimeZoneTests.theLadderFallsThroughInOrder`
  and `onlyAnExactRungLetsARowClaimTheSessionsClock` (iOS), `GpxParseTests` for the
  GPX-shaped cases, `test_parse.test_the_ladder_records_which_rung_answered` and
  `test_gpx` (lab), and `verify_presentation.py` §4, which asserts the two note wordings
  come out of the same `meta` the browser reads.

Implemented once per platform: `KeyMetrics` in `ios/WingFoilKit/…/Presentation/`, whose
strings `PresentationTests.keyMetrics*` pin, and `keyMetrics` in `web/js/render.js`. The
Swift half resolves every display string so the SwiftUI view is pure layout; the two are
twins, and a difference between them is a bug.

### The share card carries the same block

*(There is a second card kind — the **period card** — which is this card describing a week
rather than an afternoon. Everything below holds for it unchanged; what differs is set out
under "Periods".)*

The exported card shows **this block and nothing else**, re-laid-out as cells: same keys,
same order, same labels, same strings, and the tally's three counts kept as counts so they
can wear the ladder there too. A card is the one artefact that leaves the device and is read
next to nothing, so it is the last place either app may name a different number for the same
session — `ShareCardStats.make` takes the rendered `KeyMetrics` rather than rebuilding
anything from the index row.

**Both platforms compose one now.** The web's composer is `web/js/sharecard.js` (a canvas at
the same three pixel sizes, with a live preview, Download PNG, and a Share… button wherever
`navigator.canShare({files})` is true); its content comes from `web/js/cardstats.js`, which
is the same move the Swift side makes and for the same reason — `keyMetricEntries` is the one
list, `keyMetrics` in `web/js/render.js` renders its HTML from it, and `cardStats` can only
filter it. `web/tools/verify_presentation.py` §5 asserts, per fixture, that the card's stat
list *is* the rendered block.

**The picture travels with one sentence** (`shareCaption` in web/js/sharecard.js and its twin
`ShareCaption.line` in the kit, 14 September 2026 — **both platforms**): the card's own title,
its date line, the foil share and the clean-jibe count, then “— analysed with CleanJibe, free
at cleanjibe.org”. That is the one em dash either platform is allowed in a shared string; it
separates the report from the offer, and everything inside the report is separated by “·”. It
is passed as `text` and `url` beside the file on the web and as `ShareLink`'s `message:` on
iOS, so a forwarded card carries what it is and where it came from in quotable words rather
than only in 9.5 pt type in its footer — and so a notification, a reply quote or a screen
reader, none of which has the picture yet, still says the afternoon. Built from what the card
is already holding, so it can never describe a different session than the picture; the two
numbers are read off the session row rather than off the card's cells, so a `lean` card and a
`complete` one of the same afternoon carry the same sentence. The clean count is gated exactly
as the tally's caption is (no named jibes, no clean clause), and an absent number drops its
clause rather than printing a zero. `ShareLink`'s `subject:` is the same sentence **without**
the offer — a subject line is a name for the thing, and an invitation in one reads as an
advertisement. Where the browser will not carry text beside a file
(`navigator.canShare({files, text})` false), the file still goes and the sentence goes on the
clipboard instead, with *Caption copied* under the dialog's buttons.

**Layout B v2 — the jibe story** (Jan, 26 Sep 2026; proposal
`docs/proposals/2026-09-25-share-card.md`). The session card is no longer a grid of tiles.
Top to bottom (portrait): the title; the date **and start time** on the session's clock
("29 August 2026 · 14:40"); the track, which takes every point the words do not need; the
**hero number**; the jibe outcome bar (flew through · touchdown · fell in in the ladder's
colours, a zero dimmed rather than dropped); a **tack bar** on the same ladder whenever the
session had a tack, even one; the best-streak line with the session's falls; one **ribbon**
— the rates in words, then max 2 s, duration and distance; the footer. The square moves the
track beside the title when that draws the ride larger, and drops the streak line; the
landscape puts the track left and everything else in a 43 % column on the right.

| slot | what it prints |
|---|---|
| hero (the rider's choice, per device; clean jibes by default) | **★ 25 clean jibes / of 56 jibes**, or **13.21 kn / top speed · best 2 s**, or **3 tacks / 0 dry · beside 58 jibes** (offered only when the session has tacks) |
| jibe bar caption | nothing beside the clean hero; "of 56 jibes · 25 clean ★" beside any other hero |
| ribbon | "clean jibes / h" (CPH, in the clean ink) · "dry jibes / h" (JPH) on a jibes-only session or "dry turns / h" (TPH) once tacks exist · max 2 s (unless it is the hero) · duration · distance. No bare acronym, and WPH is not on the card |
| speed note | "speed estimated from GPS positions" on a positions-only (class c) recording, next to the speed: under the hero, or under the ribbon from the max 2 s cell on |

**With 0 clean jibes the clean number is left out everywhere** (Jan, 26 Sep 2026): the hero
falls back to the best 2 s (then the tacks), the bar carries no clean clause and the ribbon no
clean jibes / h. The fallback order for any hero a session cannot carry is clean → max 2 s →
tacks → none, and the composer offers only the heroes the session can carry.

Every number is still a tile of `card.tiles`, which §5 holds to the block; what the story
adds is the choice and the card's own words (`presentation.card.*`, authored by
`PresentationCopy.card`). `ShareCardStats.Story.make` (kit) and `cardStory`
(web/js/cardstats.js) are pinned against one fixture, `fixtures/cards/stories.expected.json`
— `web/tools/card_parity.mjs` dumps the browser's for every corpus document and every hero,
`verify_presentation.py` §5a re-derives the rule and asserts the words-to-footer gap on every
shape, and `DocumentRendererTests.theCardStoryIsTheSharedFixture` holds the kit's.

The **period card** keeps its grid and its two presets (`complete` / `lean`): a period has no
jibe ladder to tell a story with.

**The rider gets a title and one caption, and neither is a cell** (schema v9). The card's
header is the session's name, its date, and — when he wrote one — a single line of his own
under the date. Everything else on the card is a measurement or the footer's offer; the
caption is the only thing on it addressed by the *sender* to the reader, which is why it sits
in the header rather than joining a grid whose whole contract is that it is the app's own
block. It is capped at **80 characters** (`SessionNaming.noteLimit`, `NOTE_LIMIT`), folded to
one line, and it shrinks rather than truncating — an ellipsis in a PNG is permanent, three
points of type size are only small. Absent, the header is exactly the two lines it always was:
42 layout points, unchanged, and the caption's 14 come out of the track's remainder.

The two platforms differ in *what is being named*, and only there. On iOS the title field is a
**rename of the session**: it writes `SessionRow.customTitle`, and every surface follows —
library row, detail header, card, clip title card, share messages, and the name the scrubbed
FIT and the clip arrive under (`SessionNaming.title`, which `SessionDisplay.title` applies
once). The caption is `SessionRow.shareNote`, shown on the card and on the clip's *opening*
frame — not on the closing one, where the same sentence would be printed twice in forty
seconds, and never in a library row or on the detail page, because it is a message to an
audience rather than metadata. The analyzer has no session record to rename, so both fields
are transient there: they feed one render and are remembered per session digest id in
`localStorage`.

**The title field opens filled in, on both platforms.** It carries the session's current name
as editable text — the rider's own if he has given one, the derived one otherwise, resolved
exactly the way the card's headline resolves (`SessionNaming.titleDraft`, `cardTitleDraft`).
It used to open empty with the derived name greyed out behind it, and a placeholder is not a
prefill: it vanishes on the first keystroke, so every rename started from nothing even though
renaming is nearly always *editing* the name — adding "— first 20 kn" to the spot. The
placeholder stays on for the one moment it is now visible, after a select-all and delete. Two
consequences follow and both are load-bearing: the prefill is never blank, and a draft still
equal to the derived name is **not** a rename — it is written through as empty on iOS and
remembered as nothing on the web, so a sheet that is opened, captioned and closed leaves the
session derived. Only a keystroke in that field names a session.

**The derived name says Wingfoil, whatever the watch called it.** Garmin has no wingfoil
profile, so a session is recorded under the windsurf one and the watch names the activity
after that profile in the watch's own locale — "Nago-Torbole Windsurfen" on a German Fenix.
The word rides the filename into the app (and into `<id>_<slug>_icu.fit` when the session
comes back through intervals.icu), so both platforms swap it on the way to the screen: a
**standalone** `Windsurfen` / `Windsurfing` / `Windsurf` becomes `Wingfoil`, keeping the case
of the position it lands in (`SessionNaming.sportCorrected`, `sportCorrected` in
`js/cardstats.js`). On iOS that is one call site — `SessionDisplay.derivedTitle`, which every
surface already asks. On the analyzer it is applied to the card's headline and to the three
places that print the Python digest's filename-derived `spot`: the library list, the records
table and the trends tooltip. The digest itself is not rewritten (`library.py` is engine-side
and its goldens stand); the swap happens in the view. Three limits, all deliberate: it is
applied to the **derived** title only,
so a rider who types "Windsurfen mit Tobi" keeps it; it never touches a stored name, a
filename or the FIT's sport code, which are records of what the watch actually did; and the
word has to stand alone, so "Windsurfschule Torbole" is left as it is. The discipline **badge**
is not covered by it either — `SessionDisplay.sportLabel` still reports what the file says,
because a badge that renamed the sport code would be reporting something the recording does
not contain.

**An imported name keeps its own capitalisation.** A derived title is read back out of the
middle `_`-part of the archived filename, which is where the importers put the source's own
activity name — Strava's and intervals.icu's alike. That part used to be lower-cased on the
way in and then given a capital per word on the way out, so Strava's "Wingfoil am Nachmittag"
reached the library as "Wingfoil **A**m Nachmittag" and "Hallbergmoos Surfen" was a rewrite of
a name a person chose. The slug now keeps the source's case
(`SessionNaming.activityNameSlug`), and the title rule reads it: **if the stem carries any
capital at all, that capitalisation is the source's and is left alone**; a stem that is
entirely lower-case carries no information to preserve — the watch's `nago-torbole-windsurfen`,
the app's own slug of a bare spot name — and is the one case that gets a capital per word.
That is the whole of "title-case only a name the app built itself". A workout imported from
Apple Health has no name from anywhere, so its filename carries `_wingfoil_` and it derives as
"Wingfoil"; before that its stem had no `_` at all and the date was read as the name, which
printed **"08 30 Health"**.

**The Recording card's `sport` is the source's word, unbent** (`SessionNaming.sportLabel`).
Five spellings are translated because their raw form is not a word a rider would recognise
(`43` → Windsurf, `44` → Kitesurf, `32` → Sailing, `stand_up_paddleboarding` → SUP, `walking`
→ CIQ app); everything else keeps the source's own capitalisation, with underscores and
run-together `CamelCase` split into words — Apple Health's `surfingSports` reads
"surfing Sports", where `.capitalized` used to make it "Surfingsports". A source that said
nothing at all reads **Unknown**, which is the honest answer and was, until engine 0.19.0,
also the answer for every Strava import: `StravaImport` wrote the activity's sport into the
GPX's `<trk><type>` and the GPX parser never read it back. It does now (`caps.sport`), and it
is still provenance and never a discipline — ADR-004 files a wingfoil afternoon under sport
43, and `Discipline.resolve` does not take a sport code as an argument.

The card's outline carries three semantics and no more (`TrackThumbnail.Mark`): the track
tinted by foil state, a dot per **counted** turn on the verdict ladder's inks, and the
barometer's submersion evidence as a cyan **diamond**, one per episode — shape as well as
colour, because a submersion usually sits on the fell-in verdict it belongs to. Course changes get no dot, by the
same rule the map draws by. Nothing else from the map's eleven layers survives the shrink.
**The ground under it is optional, and off.** A switch on both composers — "Map background",
remembered per device (`ShareCardMapStore`, `wingfoil.shareCard.map.v1`) — puts a map behind
the whole card: `MKMapSnapshotter` on iOS, OpenStreetMap raster tiles composited on a canvas
on the web (`ios/WingFoil/Features/Share/ShareCardMap.swift`, `web/js/cardmap.js`). Five rules
hold it together, and the first is the one everything else serves.

- **Default off, byte for byte.** A rider who never touches the switch gets exactly the card
  described above — same pixels, and, on the web, not one request to anybody. The map is the
  only part of making a card that reaches a third party, so any stored value that is not the
  switch's own is read as off.
- **The ride does not move.** The snapshot (or the tile grid) is *framed* so the track fills
  precisely the box the layout already gave it, and the card's own margins are what become
  map. Flipping the switch shows one card with and without ground under it, never two cards.
- **The breadcrumb is placed through the map's projection**, not the card's. The plain card
  fits a normalized outline to a box — a projection about the session, which does not know
  where the water is. With a map behind it every vertex goes through
  `MKMapSnapshot.point(for:)` / Web Mercator instead, or the line would sit near the water
  rather than on it.
- **A scrim, and dark stat plates.** A navy wash plus a vertical gradient heavy at both ends
  (and, on the wide shape, a panel under the word column), and the stat cells invert from
  white-at-a-tenth to black-at-a-third: a translucent white plate over a town's building fill
  is not a plate. Tuned against the busiest ground either platform produces, not against open
  water.
- **Attribution is printed on the card.** `© OpenStreetMap contributors` on the web (ODbL
  requires it) and `Maps © Apple` on iOS, at 6.5 pt in the corner opposite the title on the
  tall shapes and bottom-leading on the wide one — never in the QR's corner, and never under
  the footer. `MKMapSnapshotter` burns its own badge into the bottom-left of the image, which
  on this card lands under the brand mark; the snapshot is taken a band taller than the card
  and cropped so that half-covered badge never ships.

Everything about it degrades to the plain card, silently: no fixes in the recording, a
document analysed before the geographic anchor existed (`view.geo`, added by
`web/lab_bundle/web_entry.py`), no network, a tile server that will not answer, a tainted
canvas. A rider on a beach still gets a card.

**The footer is a contract of its own, and both platforms print it identically**: the app's
mark at 30 pt, **CleanJibe · cleanjibe.org** at 16 pt (the name in paper, the address in brand
green) **above** the tagline `Your WingFoil session, measured.` (layout B v2, 26 Sep 2026),
and a **QR code to `https://cleanjibe.org`** in the trailing corner. The card
is the declared promotion channel — it leaves the phone as a PNG and is read in somebody
else's chat by a rider who has never heard of the app — so the footer is the only part of it
addressed to the receiver rather than to the sender, and it may not differ between the card
the phone exports and the card the web composes. The strings come from `Branding` in the kit
(`appName`, `site`, `tagline`, `siteURL`), pinned by test, and from `BRANDING` in
`web/js/cardstats.js` on the other side — one constant per platform, never a literal at a
draw site.

Three details of the QR are load-bearing rather than cosmetic and are the same on both
platforms: it is **dark-on-light with its own light plate**, because the card's background is
navy or somebody's photo and a decoder needs the light half to be light; it is drawn at
**~144 px at 1080 width** from a **nearest-neighbour** upscale with a four-module quiet zone,
because the generator emits one pixel per module and any smoothing turns every module edge
into a grey ramp for a decoder to guess at after a chat app has recompressed the picture; and
it carries the **brand mark in its centre**, below. iOS renders it with `CIQRCodeGenerator`
(`BrandQRImage` in the kit, drawn by `ios/WingFoil/Features/Share/BrandQRCode.swift`) at
correction level M — a short URL, a clean digital image, and bigger modules matter more here
than damage tolerance. The web draws the same symbol from a committed 33 × 33 PNG
(`web/icons/qr-cleanjibe.png`, one pixel per module, quiet zone included) with
`imageSmoothingEnabled = false`: the URL is fixed, so a QR library in the bundle would be a
dependency to draw a constant.

**It grew from 99 px to 144 px** (`QR_SIZE` on the web, `ShareCardView.qrSide` on iOS —
33 → 48 layout points on the web, 32 → 48 on iOS; both changed 14 September 2026). 96 px was
iOS's old export and the floor `BrandQRTests` was calibrated against; it stays in that suite's
`exportSizes` even though nothing exports at it any more, because every card already sitting in
somebody's chat thread was drawn at it. 99 px was three whole pixels a module and read
perfectly at 1:1 — and too small where a card is actually met, as a thumbnail on somebody
else's phone at arm's length. Angular size beats crisp module edges for a camera, so the whole
upscale is no longer an integer: 144 over 33 modules is 4.36 px a module, most of them four
pixels wide and every twelfth five, hard-edged throughout, with level M's parity absorbing the
edges that land a pixel out of true. The footer's height derives from `QR_SIZE`, so the tall
shapes give the track 15 pt and the wide one gives the wordmark 15 pt of width.

**The mark in the middle, and why it is exactly five modules.** An unbranded code in the
corner of a picture is an anonymous grey square; the app's own icon on a small rounded white
plate at its centre makes it visibly *this* app's link, which is the entire job of a footer
that exists to be followed. The plate is **5 modules** across the centre of the 25-module
version-2 symbol — 25 of its 625 cells, **4 % of the symbol's area**, against the ~15 % of
codewords level M's parity can rebuild — and the mark itself is three quarters of that, so a
white rim keeps the artwork's dark edge off the dark modules it abuts. Three constraints fix
the number, and all three were measured rather than assumed:

- **Parity.** 4 % is a quarter of the budget, and the rest is left for the real enemy, which
  is a chat app's recompression of a photograph of a phone screen.
- **The alignment pattern.** Version 2 puts its 5 × 5 alignment block at module 16, and
  parity cannot substitute for it: a decoder that cannot find that landmark never reaches
  error correction. Five modules stops a clear module short of it, which is why decoding
  fails *abruptly* at six modules rather than degrading — the measured cliff is 5.75 (every
  export size decodes) to 6.0 (a fifth of them stop).
- **Odd.** The symbol's centre is the middle of a module, so only an odd-width plate lands on
  module boundaries; an even one would leave a rim of half-covered cells for a decoder to
  threshold.

The number lives in `BrandQRImage.markModules` and `QR_MARK_MODULES` in
`web/js/sharecard.js`, and the two must agree. The **committed PNG stays unmarked**: at one
pixel per module a baked-in mark would be a five-pixel square, so the web composites the
plate at draw time and it scales with the render. What makes this safe is not the arithmetic
but the decode: `BrandQRTests` renders the code at every size the app exports it — as PNG and
through JPEG q50/q35 — and reads it back with `CIDetector`, each marked case paired with the
unmarked control and with an oversized-mark case that must *fail*; the web's six card renders
(3 shapes × 2 presets) are decoded the same way with OpenCV, PNG and JPEG q50.

Note the case, which is deliberate: **CleanJibe** is the brand, *wingfoil* in the call to
action is the sport. The word WingFoil survives only as the Xcode target, the module and the
bundle ids (`de.lahmann.wingfoil.*`, unchanged — renaming them would orphan the TestFlight
build, the BGTask registration and the keychain), and as the name of the **Garmin watch app**,
which the phone app still refers to by that name where it means that app.

The same footer closes a replay clip (`ReplayClipCards`), which is the frame a viewer is left
staring at while the clip loops — the one frame worth pointing a camera at.

### Uncertified speed — the one mark a degraded source always wears

A speed record is only trustworthy when it came off the receiver's Doppler channel. A source
that carries positions but no speed channel — **every GPX** (engine 0.9.0), a **TCX without
`Extensions/TPX/Speed`**, and the occasional converted export — has its speed differentiated
from positions instead, which is noisier and biased upward on a bad fix. Those records are
still shown, because they are still the rider's session; they are shown **marked**, because an
all-time best is exactly where a number nobody can verify does the most damage.

A TCX *with* that element is class (b) and certifies like any FIT, which is also why the
class-(b) badge says **"measured speed channel"** rather than "standard Garmin recording": a
Polar, Suunto or Coros session arriving through intervals.icu never came off a Garmin, and the
thing the class asserts is that the file measured its own speed.
that carries positions but no speed channel — **every GPX** (engine 0.9.0), **every session
imported from Strava** (ADR-023, which is a GPX by the time the app sees it), and the occasional
converted export — has its speed differentiated from positions instead, which is noisier and
biased upward on a bad fix. Those records are still shown, because they are still the rider's
session; they are shown **marked**, because an all-time best is exactly where a number nobody
can verify does the most damage.

Since engine 0.20.0 the shortest of them is *also* checked against the same track's best 10 s
before it is reported at all (docs/algorithms/records.md, "The plausibility gate"): a best 2 s more
than 1.2× the best 10 s is one bad fix rather than a run, and the record falls back to the
fastest 2 s that the 10 s can account for. Nothing on the page changes — the number is simply
one the engine can stand behind, and it still wears the mark, because the source is still a
source that could not prove it measured anything.

The rule is read from one field, `sourceClass == "c"`, and nothing downstream of the parser
knows the word GPX:

| surface | mark |
|---|---|
| session badge | `limited data` (web `render.js`), `SessionDisplay.sourceClassNote` (iOS) — the title/subtitle names both absences: estimated speed, no pump data |
| records table | an `uncertified` chip beside the **value** (web `trends.js`, iOS `RecordsView`) — beside the claim, not beside the session |
| personal bests | the celebration reads the same rule the table does (`PersonalBestDetector.improvements(previous:current:policy:)`). The clean-jibe records are exempt: a jibe count is not a speed and a bad fix cannot inflate it |
| share card | "speed estimated from GPS positions" (`ShareCardStats.speedEstimated`, `cardDisclaimer`), next to the speed it qualifies — the card leaves the device, so it cannot be read as a speed claim |

The same source class also has no accelerometer, so the pump and takeoff-effort figures are
absent rather than zero, by the never-a-flattering-zero rule the goldens already follow
(docs/testing.md).

### Whether an uncertified record counts at all — Settings → Speed records

Jan, 22 September 2026. Marking a record is one answer to "this speed came from positions";
it is not the only reasonable one. A rider whose library is all Garmin FITs wants the one
Strava import kept out of his all-time table; a rider whose library is all Strava wants a
table at all. So the mark stays, and **whether the record enters the aggregate is a
setting**, right under Units on both shells, with three choices and one wording:

| choice | what stands |
|---|---|
| **Only verified** | an unverified record never enters the all-time table, the personal bests, the trends' best-2 s series, a card, the celebration or the watch snapshot. Its own session's page still shows it, marked |
| **Prefer verified** — the default | per record kind, a verified record wins whenever one exists; an unverified record fills a row no verified record of that kind has reached, and it carries the mark |
| **Include unverified** | every record stands, marked. What the app did before the setting |

**One rule, one function** (docs/review-checklist.md, pattern L). `SpeedRecordRule.eligible`
in the kit takes the candidates of **one record kind** and returns the subset the policy lets
stand, and every surface that can show an all-time record calls it: `LibraryStore.records`
(before the maximum is taken, which is what makes "a verified record wins" true),
`PersonalBestDetector.improvements`, the Trends best-2 s series, `ShareCardStats.make` and
`WidgetSnapshot.make`. `library.eligible` in `web/lab_bundle/library.py` is the browser's
twin, read by `_records` and by the best-2 s series in `_points`, and the three values are
spelled the same on both platforms — `onlyVerified`, `preferVerified`, `includeUnverified`.

**It is applied when the aggregate is read, never written into it.** The `record_effort`
table on the phone and the stored digests in the browser keep every record they ever held;
the setting decides what is read back out of them. Moving the picker therefore re-runs the
query (`RecordsView.reloadKey` carries it on iOS, the aggregate's memo signature carries it
in the browser) and re-imports nothing, and a library saved under one setting is not a
library that has to be saved again under another. A stored digest that had the decision
baked into it would go stale the moment the rider changed his mind.

The phone draws it as a wheel with the chosen mode's line under it, because three two-word
labels cannot say *when* an unverified record counts and that is the whole difference
between them; the browser draws the same three as a segmented group with the same line
(`SpeedRecordPolicy.summary`, `SPEED_RECORD_SUMMARY` in `web/js/appshell.js`). Under **Only
verified** a table that empties says why rather than going blank (pattern G).

### Send this session to the developer — the Share page's third thing (beta)

Jan, 21 September 2026. The Card and FIT file segments answer one request, *send this to
someone*; this answers another, *this number is wrong*, and the only way to chase that is on
the recording that produced it. It is a full-width row **under** the switcher rather than a
third segment: a third segment would make a rider choose between sharing and reporting before
he has decided he wants either, and the row carries the same afternoon whichever segment is
showing.

The sheet is a comment field with two prompts as its placeholder — *"What looks wrong? Which
turns or times?"* — a paperclip line naming what is going with it, and the consent sentence
in register 1: *"The file holds your track, your heart rate and your times. It is used only
to improve the detection. It is never published."* Then the ordinary feedback-mail path
(`MFMailComposeViewController`, `FeedbackMailPresenter`'s own fallback ladder), with:

* the **archived original, unscrubbed**. The share sheet's FIT tab runs `FitShareFilter`
  because a copy going to a friend has no business carrying a watch serial; this copy is
  going to the one reader who is being asked to reproduce the analysis, and a scrub drops the
  developer fields, the laps and the rider profile — the half most likely to hold the reason
  a number came out wrong. A session that arrived as positions rather than as a recording
  (Strava, Apple Health) sends the track CleanJibe built from them, and the mail says which
  of the two it is;
* the rider's comment, above the rule, where his half of every prefilled mail goes;
* the diagnostics block the feedback mail already builds (`FeedbackReport.blocks`: the
  channel and build, the engine, the phone, the watch, the library, the session's source
  class), plus this session's headline numbers — duration, distance, the jibe tally, the wind
  source — and the watch-vs-phone rows where a summary card disagrees (`DivergenceCheck`).

Subject: *CleanJibe session <date> — for analysis*, so a mailbox sorted by subject groups the
mails about one afternoon. **Nothing is sent by the app**: the rider sees the whole mail,
edits or deletes any line, and iOS sends it from his own account or not at all.

BETA (docs/channels.md): `#if BETA` on the row, the sheet and the attachment path, and the
help topic is bound to `.beta` so it never reaches the release Help index.

**The browser does the same thing with the platform it has.** The fold sits in the Details
tab's export panel, under *Download analysis JSON*, which is where a reader who doubts a
number already is. `navigator.canShare({files})` decides the route, because file sharing is
per browser *and* per file type: Safari on iOS and macOS and Chrome on Android and Windows
hand the recording to the system share sheet with the note as its text; Firefox and Chrome on
Linux have no file sharing, so the recording downloads and a `mailto:` opens with the same
body, which then says to attach it — no mail URL scheme can carry an attachment. The status
line always names which of the three happened, including *cancelled*.

### A clip can carry the rider's own music, and only his own

The replay clip is muxed after recording, never during (iOS: `ReplayClipSoundtrack`,
`ReplayClipCropper.export`): the microphone is off and stays off, the recording's own audio
track is dropped by construction rather than by a setting, and the track the rider chose is laid
under the finished video — trimmed if it is longer than the clip, repeated from the top if it is
shorter, with a 0.8 s fade in and a 1.5 s fade out. The setup sheet's Music row defaults to
**None** on every clip (unlike the length and the shape, which open where the last one left
them) and carries one line: *"Use music you have the rights to share."*

**The seam for bundled tracks is deliberate and unfilled.** Everything below the sheet takes a
file URL and asks nothing about where it came from, so a "pick one of ours" row would be a
second way of producing that URL and no other code would change. What is missing is not code
but licensed audio: a track shipped inside an app whose riders then post the results to social
networks needs a licence written for exactly that use, and nothing from a commercial streaming
service can ever be one — those files are DRM'd, the APIs hand out stream handles rather than
samples, and the terms forbid redistribution outright. Hence the rider's own file, and the
caption saying whose responsibility the rights are.

## Session video — the reel, and the clock it is drawn on

A second thing that leaves the phone, beside the card and the shared FIT: **a 9:16 video of
one session**, 1080 × 1920 at 30 fps, H.264, in which the breadcrumb draws itself over a
still map while the afternoon's highlights are called out as they pass, and which ends on the
key-metrics card. "Export video" sits under the share card in the share sheet
(`ShareComposerView`), and it is a **rider feature on both builds** — a card, a FIT and a
video are the same kind of thing, something a rider makes to show somebody, and none of them
is a threshold.

**It is not the cinema clip, and the two do not merge.** The clip (`ReplayCinemaView`,
`ReplayRecorder`) records the live glass with ReplayKit, at whatever the phone's screen is,
with the rider free to pan and zoom the map while it runs — it is *his* replay, captured. The
reel is rendered offscreen frame by frame (`ReelRenderer`: `AVAssetWriter` +
`AVAssetWriterInputPixelBufferAdaptor`, Core Graphics into the pixel buffer) and is the same
video from every phone: one fixed size, one fixed type scale, no Dynamic Type, no notification
banner in frame, no camera moves, faster than real time. That also makes it the only one of
the two a Mac can check, since `RPScreenRecorder` writes a zero-byte file in the Simulator
(docs/testing.md).

### The cut

Default **20 s**, settable 15 / 20 / 30 in the export sheet. The last **3 s** are the end
card; the rest is map.

**The whole session draws over the cut, and the clock is not linear.** `ReelPlan` (kit, pure,
tested) lays an *attention density* over the session's span: 1 everywhere, rising to **5×** in
a raised-cosine bump of half-width `halfWidthS` around every moment worth stopping for. Reel
time is that density's integral, normalised to the length of the map section:

```
reelTime(t) = mapS · ∫ d / ∫ d          (from the span's start to t, over the whole span)
```

so the clock **slows around the highlights and speeds up between them**, the whole track
draws (nothing is ever skipped), and both ends land exactly. The plan answers in both
directions — `sessionTime(atReelTime:)` for "where is frame 317", `reelTime(ofSessionTime:)`
for "which frame is this jibe on" — which is the one thing `ReplayDriver` cannot do: the
cinema replay's warp is a rate field ticked forward one frame at a time, right for a live view
and useless to a renderer that wants random access.

**The moments** are read off one analysis, all of them:

| moment | where | slows the clock |
|---|---|---|
| the **longest flight's takeoff** | `flights`, longest by time, ties to the earlier | yes |
| **every counted jibe** | `turns` where `counted && type == "jibe"`, with its outcome and its `clean` flag | yes |
| **each record window** — 2 s, 5×10 s, alpha 500 | `records.windows`, at the window's own start | yes |
| **every submersion** | `submersions` | **no** |

Every counted jibe, not a selection: a jibe drawn at 200× is a smear and at 20× it is a
maneuver, which is a statement about drawing rather than about narration — and it is why the
reel's list is a third list beside `ReplayBeats` ("where can I scrub to") and
`ReplayCommentary` ("what would a friend say"). A submersion gets its callout but no bump: it
is evidence rather than an event, it usually already belongs to a turn
(`SubmersionRecord.turnIndex`), and slowing twice for one moment is slowing wrong.

**The bump shrinks.** Forty jibes at three seconds each is two minutes of premium inside a
twenty-second cut, and the dips would merge into one flat slow reel that never gets anywhere.
`halfWidthS` starts at `span / 8` and halves until the extra density mass is at most **60 %**
of the whole — the same move `ReplayPacing.budget` makes, for the same reason — with a floor
of 0.75 s, below which the warp is near-linear, which is the right answer for a session where
nothing is special because everything is.

### The ground and the track

**One `MKMapSnapshotter` snapshot**, taken once at the region the whole track fits in, and
every frame draws over the same pixels: a reel is a breadcrumb drawing itself over a
photograph of the water, not a moving map. The framing arithmetic is the share card's
(`ShareCardMapper.frame`, and the same attribution band asked for and cropped away), and the
**rider's own `MapStyleChoice` is honoured** — a reel of a session is a reel of his map.
Taken in points at 2× rather than pixels at 1×, so MapKit draws labels and coastlines at the
weight a phone shows them at.

The track is drawn in **the map's own phase colours**, through the map's own code path:
`MapLayerVisibility.lineStyle(flying:)` → `TrackContent.color(_:on:)`, so a rider who has
hidden a phase on his map gets the same neutral line here, and `TrackHalo` puts the dark outer
edge under everything on imagery, in one pass under the whole track. Marks are the same
vocabulary every map draws — the outcome ladder as dots, a clean jibe as a **star**, a
submersion as the **cyan diamond** — popping to size over their first half-second on the
session clock, so an outcome lands as it happens.

### The overlays

- **The live strip**, along the bottom: *elapsed* (`FlightPairing.clock`), *speed* in knots,
  and the **on-foil flag** — a filled foil-teal pill while he is flying, an outline while he
  is not, the same ink as the track under it. Under them the counters that only go up:
  `"5 flew · 11 dry"`, and `"· 3 ★ clean"` when there are clean jibes to count. *Dry* is
  flew-through plus touchdown, the same set JPH counts, so the strip and the end card's rates
  are about the same turns.
- **Callouts**, one at a time, popping for **1.5 s of reel time** on a dark plate with the
  moment's own ink down its leading edge — `ReplayCommentaryBubble`'s shape, so a rider who
  has watched the replay has already learned to read it. `takeoff` · `jibe · flew through` /
  `jibe · touchdown` / `jibe · fell in` · `clean jibe` · `best 2 s 13.47 kn` · `wrist under`.
  Every word is borrowed — `TurnOutcomeKind.label` for the verdicts, `RecordKind.windowLabel`
  for the records, `KeyMetrics.knots` for the number — so the reel cannot invent a second
  vocabulary on the one surface that leaves the phone. The window opens at the moment's own
  instant and never before it: a callout that appears before the thing it names is a spoiler.
  When two are open the latest wins, because two labels over a moving map is two things to
  read and time for neither.
- **The header**, top left: the session's title and date line, from the same `ShareCardStats`
  the card's header uses.
- **A progress hairline** across the very bottom.
- The **uncertified mark** rides on the strip on a class-(c) source, exactly as it rides on
  the card: the video leaves the device, so it cannot be read as a speed claim.

### The end card

The last three seconds are **`ReplayOutroCardView`** — the cinema clip's own closing card,
which is drawn against a 390 × 700 reference and therefore lands at 9:16 without a layout
change — rendered once through `ImageRenderer` and cross-faded in over the finished track.
Using the clip's card rather than drawing a new one is what guarantees the footer is *the
share card's*: the mark, the wordmark, **the call to action and the QR**, in that order and
character for character (`Branding.callToAction`, `BrandQRImage`). Its numbers are
`ShareCardStats.outro` — duration, distance, avg speed, max 2 s, the flew · touchdown · fell
tally with its clean caption, the longest flight, and JPH / CPH / WPH.

### Where the file goes

The caches directory, under `Reel/`, named the way the shared FIT and the cinema clip are
(`FitShareFilter.filename`), so a rider's three exports of one afternoon sort together. The
sheet plays it back, hands it to the system share sheet, and **clears the directory when it
closes** — the share sheet has already taken its copy by then, and a video nobody asked to
keep is ten megabytes of somebody's phone. The render runs off the main actor, reports
progress, and cancels at whatever frame it is on.

