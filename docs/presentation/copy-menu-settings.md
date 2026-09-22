> Part of `docs/presentation.md`. Engine 0.23.0.

## One copy, many surfaces — `docs/copy/`

**The same wording, wherever it is said, pinned from both sides** (15 September 2026).

The website, the App Store description and the app said the same things in different words,
and they had already drifted apart in fourteen places: the web's beta list still promised a
feature that had shipped seven hours earlier, the phone's own clean-jibe definition was a
version behind the engine it shipped with, and the dry streak had four spellings across five
surfaces. Nothing was wrong with any single sentence. What was missing was a mechanism.

`docs/copy/` is seven small JSON files — `channels`, `recording-classes`, `glossary`,
`feedback`, `icu-setup`, `phrases`, `verdicts`, plus the generated `garmin-devices` — each
holding one piece of wording that more than one surface says. Its README carries the schemas
and who authors each key; the rule is short:

* **The kit is the author** for anything the app says, `docs/channels.md` for the channels,
  the manifests for the devices. The JSON is the artefact, never a second draft.
* **Both sides are pinned.** `CopyContractTests` asserts every kit constant equals its JSON,
  so a kit edit that moves a fact **fails the kit tests** until `docs/copy` moves with it.
  The web verifier asserts the pages carry the same strings, so the website has to catch up
  before the check goes green. `docs/copy/check_release_copy.py` asserts the release copy
  names no door the release lacks, keeps the Strava rule and uses none of the banned
  vocabulary (*carried*, *no-fall streak*, *clean-jibe percentage*, *swim rate*,
  *success rate* — CLAUDE.md).
* **Regenerating** after a deliberate rewording, from `ios/WingFoilKit`:

  ```sh
  COPY_WRITE=1 swift test --filter CopyContractTests
  ```

  which rewrites the kit-owned keys in place and leaves the hand-authored ones — the
  forbidden lists, the lexicon, the two store names, and each glossary entry's `short` and
  `sentence` — exactly as they were.

**A glossary entry grew to six fields and a scope** (15 September 2026), because `{ id, term,
line }` serves two surfaces and the product has four and two stores:
`{ id, term, short, expansion, line, sentence, surfaces }`. `term` is the label the phone and
the web print; **`short` is the same word at the watch's width** — at most seven characters
wherever `surfaces` names `watch`, which is what a MIP cell holds and what three shipped
watch labels already exceed. The watch is not given an exemption, it is held to the contract
at its own width, and `CopyContractTests` asserts the budget, so it fails a test instead of
failing a rider. `expansion` is the half the phone and the web append after `" · "` —
`KeyMetrics` built `"CPH · clean jibes per hour"` out of two halves that existed nowhere as
data, and now reads both from the entry. `sentence` is the clause the two store descriptions
print instead of the label (*"how much of it you spent on the foil"*, hand-copied into four
files until now). `surfaces` says who may demand the word, so a watch scan never asks for
`alpha500`, which the watch does not compute. `short` and `sentence` are hand-authored beside
the kit-owned keys, the way `lexicon` and `ciqListingTitle` already are.

**Three entries were added in the same pass**, each a label the app prints on every session
and no surface defined: `tph` (CLAUDE.md — *rates are additive: keep JPH and TPH beside CPH*;
the number was additive, the glossary was not), `best5x10s` and `alpha500`. Eleven entries
now, and `/learn`'s definition list carries all of them.

**`feedback.json` gained `doors`.** One door had five names — `Support & ideas`,
`Menu → Support`, `Settings → Send feedback`, `Something off? Send feedback`,
`Send feedback` — across the app's Help, four website pages and the two store texts, and one
of them named the Settings row **deleted in build 58**, inside the app's own instructions.
`FeedbackDoors` is the list: `app` (`Menu → Support & ideas`), `footer`
(`Something off, or an idea? Send feedback`), `share`
(`Report a problem with this session…`), `testflight` (Apple's `Send Beta Feedback`) and
`web` (the address). The app target's three labels and the Help topic's sentence are all
built from it, so a renamed door renames its own instructions.

**What it deliberately does not pin.** The `HelpCatalog` bodies against `/learn`: the app's
help is reference material behind a `?` and the web's glossary is eleven one-liners for a
stranger — same terms, different depth, so the terms and the one-liners are pinned and the
bodies are left alone. The privacy page against the app: a GDPR document does not belong in a
Settings footer, so the app *links* it (Settings → About → Privacy, and the help topic *What
leaves your phone*) rather than mirroring it. The feedback `mailto:`'s two extra questions:
a browser cannot fill in the watch and the build, and the app can. And the store texts' voice
and length, which are marketing prose — what they must not do is name a door the release
lacks, and that is a check rather than a single source.

## The library menu — one menu, in the order a new rider needs it

The Sessions tab's top-left button (`line.3.horizontal`, "Menu") is the app's one menu. It
used to be a gear with two rows; it is a menu now because a gear promises switches and the
first thing a new rider needs is not a switch. Five items, two dividers, one line of small
print, in this order and for this reason:

1. **What CleanJibe does** — the welcome screen again (`SessionStore.replayWelcome`). First
   since dev 65 (Jan): *what is this* is the question that comes before *how do I start it*,
   and the row that answers it had been sitting below the door to the feedback mail.
2. **Getting started** — the first-session guide as a help topic (`HelpTopicID.gettingStarted`,
   its own first help section, every channel). Second, under the screen that says what the
   app is, because it is what "I just installed this" is looking for next. Since
   15 September 2026 the instructions live IN the app (Jan: never send a rider to the
   website for them): one sentence on the real test — one session on the
   water, read the turn verdicts against what you remember — then the routes as items,
   Garmin with the CleanJibe watch app first, any .fit second, Strava third, the
   three-to-five-minute walk as "if you cannot wait for wind", where to send what you find,
   and the web page named last as the same guide. The two Apple routes are beta topics it
   links to, so the release never names them. Word budgets are enforced by `HelpBudgetTests`.

   **The guide has one source, and it is `docs/guide/getting-started.json`** (Jan, 15 Sep
   2026). The topic and cleanjibe.org/start had been written separately, so the app's last
   item — *"the same guide, on the web"* — named a page that said different things. That file
   now holds the framing, the routes in order with their channel and their steps, the two
   closing notes, the two Settings captions, and the web-only troubleshooting and report
   lists; `web/tools/make_start.py` writes both copies from it — the kit's
   `Help/GettingStartedGuide.swift`, which this topic's `summary`, `body` and `items:` are,
   and the block of `web/start/index.html` between its `<!-- guide:begin -->` and
   `<!-- guide:end -->` markers. The app shows a route's **title and summary**; the web shows
   **title, summary and the numbered steps**, which is why the last item reads *"The same
   guide, with every step, on the web"*. `make_start.py --check` fails while either copy is
   stale and `web/tools/verify_links.py` runs it; `GettingStartedGuideTests` fails if the
   topic stops being the guide, so a route typed straight into `HelpCatalog` is caught too.
   **Channel filtering is the source's `channels` list through `items(for:)`, and since
   dev 65 the app's own channel decides.** The two Apple routes are `.beta`. The catalogue
   is a static array and cannot ask which build is reading it, so it is declared with the
   *release's* list — and until dev 65 that was the answer in every channel, which meant the
   beta's two Apple routes (its watch app, and Apple's Workout app) were named on no page a
   rider would look for them on. `HelpCatalog.topic(_:channel:)` rebuilds a topic's **items**
   for the asking channel (`resolved(_:channel:)`, the one topic that needs it), the sheet
   passes `AppChannel.channel`, and `indexTopics`, `relatedTopics` and `search` resolve the
   same way. The release still names three routes and reaches the two Apple topics through
   nothing at all — `relatedTopics(of:channel:)` drops them — the beta and the dev name five.
   `GettingStartedGuideTests` counts the items per channel.
3. **Settings** — the switches, the watch, the accounts.
4. **Help** — the Help index. It read *What the numbers mean* until 15 September 2026, and
   that was a name for one of its ten sections rather than for the screen: the index opens
   with *Getting started* and *Getting set up*, and closes on *Sharing* and *Quality* — a
   rider looking for how to connect Strava or what a share card carries had no reason to
   open a row that promised arithmetic (Jan, build 63: *"Help is good"*). The icon is
   unchanged (`questionmark.circle`), and so is everything behind the row; *the numbers*
   keep their own headings inside, where they are a section and not the whole screen.
5. **Support & ideas** — the feedback mail (`feedbackMail(on:)`, the same composer as the
   page footers' *Something off, or an idea? Send feedback*, the share sheet's "Report a
   problem with this session…" and, since dev 65, the *Sending feedback* help topic's own
   **Send feedback…** button; `FeedbackDoors.menuRow` is the label). Last of the five since
   dev 65: the two screens above it answer a question on their own, and the rider still
   asking after them is the one this row is for. It said **Support** until 14 September 2026,
   which a rider reads as *the place you go when something is broken*: Jan's point is that a
   wish is as welcome as a fault and nothing in the app had ever said so, and the name of the
   door is the cheapest place to say it.
6. The build line, not tappable: *CleanJibe 0.15.0 (45)* with " · beta" or " · dev" after it
   on those channels — the same string as Settings → About, and the first question of every
   support mail.

**Two dividers, and they group the five.** The first separates the two an arriving rider
reads once — *What CleanJibe does* and *Getting started* — from the three he comes back to:
where the switches are, what the numbers mean, and who to write to. The second holds the
build line under the menu proper, because it is small print and not a row.

**Six rows, and no seventh.** The release channel carried *What is being tested* straight
under **What CleanJibe does** until 15 September 2026, and it is gone from here (Jan, build
58): the menu answers what a rider needs *now* — what the app is, how to start, where the
switches are, what its numbers mean, who to write to — and a list of what this build does not
have is none of those. It has one home, Settings → **Coming in a future release**, described
under "Settings" below.

**The welcome screen closes.** Replayed from the menu it has a circular ✕ at the top right,
because its three buttons are *ways in* and a rider who came back to read it is not choosing
one; a page whose only exits are labelled "Try the example", "Connect" and "Later" reads as a
gate (Jan, 13 Sep 2026). ✕ does what "Later" does: nothing is armed or loaded.

**Every door on this screen is one sheet.** The Sessions tab used to hang seven
`.sheet(isPresented:)` modifiers off one view — Settings, Import, Help, a named help topic,
the release channel's page of what is coming, the beta's date-range editor, the dev build's
tuning hook. SwiftUI resolves sibling presentations on one view in order and drops the ones
that arrive while another is still settling, so the tap that set the *last* flag in the
chain — the help topic, which is what **Getting started** sets — landed on the floor whenever
the menu's own dismissal was still animating, and the row simply did nothing (Jan, build 58).
There is now one `@State` of one enum (`LibrarySheet`) and one `.sheet(item:)` over it: two
writes to one property cannot race, the second replaces the first, and every entry point —
the menu, the toolbar's Import, the empty-library card, the actions Help hands back
(`openIcuSettings`, `loadExampleSession`) and every `UI_SHEET` screenshot hook — writes that
one property. The `UI_SHEET=help|settings|import|tuning|discipline` and `UI_HELP_TOPIC` hooks
are unchanged from the outside.

**The browser's copy of it, and of the tab bar** (19 September 2026). The web app is the
port, so `/app/` wears one bar and it is the app's: the mark, the name and the same **Menu**
button in the same corner (`web/app/index.html`, between `<!-- appheader:begin -->` and
`<!-- appheader:end -->`). The marketing site nav — *Get started · Help · Open the app · Get
the beta* — is on the six reader pages and on none of the app, because two navigations
stacked over the app's own tab bar is what Jan photographed that morning, and because *Open
the app* was a loud door to the page it was on. The two links it took away are menu rows
already, as *Getting started* and *Help*. `web/tools/verify_links.py` byte-pins the nav
across the six and holds `/app/` to the app header instead. The menu sheet itself is the
phone's: the five rows of `AppMenuRow.ordered` with the phone's symbols drawn as line icons,
the one divider above *Settings*, the build line as a footer under a hairline, and *Close*.
The **tab bar** carries the phone's four glyphs over its four words — `water.waves`,
`trophy`, `chart.xyaxis.line`, `bag` — the chosen tab is marked by ink rather than by a box,
and the bar's height is its content plus `env(safe-area-inset-bottom)`, paid once.

## Settings — switches and accounts, and nothing that is already in the menu

Settings opened with three rows — *What CleanJibe does*, *Help* (then still called *What
the numbers mean*) and *Send feedback* — under two paragraphs of footer, and all three are
rows of the library menu one
tap away. Two homes for one door is two wordings to keep in step and one more screen for a
rider to search, so the block is gone (Jan, build 58) and the menu keeps them. What is left
is what only Settings has: **intervals.icu**, **Strava**, deleted sessions, notifications,
analysis, storage, backup, about — switches and accounts.

**The two account sections open by saying why the account is there** (Jan, 15 Sep 2026). The
intervals.icu section opened on an empty field asking for something called an API key, and
the Strava section on a button; neither told a rider what the account was *for*, or whether
he could skip it. Each now has one footnote-sized line as its first row —
`GettingStartedGuide.settingsIcu`, *"Garmin has no open API for a personal app, so
intervals.icu is the free bridge: connect your Garmin there once and every session arrives
here by itself."*, and `GettingStartedGuide.settingsStrava`, *"The route that needs no file:
any watch that syncs to Strava. Positions only, so speed records are uncertified."* Both come
from `docs/guide/getting-started.json`, so the switches and the Getting started guide say one
thing; the longer intervals.icu version, which the help topic prints, is still
`IcuSetupGuide.rationale`. The footers under each section are unchanged and carry the detail —
what is downloaded, what is never written, the connection cap.

**Accounts, not actions** (build 63, "Import does, Settings configures" under Import). The
intervals.icu section is the caption, the key field with *Save & check*, the last sync date
and the two help rows — *Sync now* left it, because fetching sessions is an import and Import
has that button. The Strava section is the caption, *Connect with Strava* or the connected
athlete with *Disconnect*, and the footer. Everything either section offers is about the
account; everything either account is *for* happens one sheet away.

**Notifications say intervals.icu, because that is what is asked.** The switch read *Notify
on new Garmin activities* and the check behind it has never been a Garmin one: it is a call
to the rider's intervals.icu account, and every watch that syncs there — a Garmin, a Polar, a
Suunto, a COROS, an Apple Watch through Health — is announced by it. It is **Notify on new
sessions from intervals.icu** now, and the footer says the same in full. The app also makes
the offer **once by itself, the moment a key has been proved** — not the moment it is typed:
"Save & check" stores the key and *then* asks intervals.icu, and the alert used to fire on
the store, over the spinner and sometimes over a key the answer rejected a second later. The
alert's title is the switch's own label and its message is the switch's own explanation, word
for word (`SettingsCopy`), because it is the same feature; "Notify me" runs the same code
path the switch does, which is what puts the iOS permission sheet under the finger that asked
for it. `NewActivityPrompt.shouldAsk(… keyIsProven:)` holds the rule.

**"Coming in a future release"** — the channel list (docs/channels.md), read the way a rider
asks it. It was *Curious about what is coming* until 14 September 2026 (an App Store app that
opens by being curious about itself reads as an apology) and *What is being tested* until the
15th, which names the room rather than answering the question. What he is asking is when he
gets these things, so the row says it: **these functions come in a future release, and can be
previewed now in the public beta**. On the page, **How to join the beta is the first section
and a step, not a footnote** — *One tap. Your library is kept.*, a prominent **Open
TestFlight** button and `cleanjibe.org/invite` under it, with the footer explaining that
TestFlight is Apple's own app, that the beta reads and writes the same library, and that
going back is allowed. The **dev** doors are not on it in the release channel (`#if BETA`):
tuning, iPad, the Garmin link and windsurf are on a handful of hand-picked phones and are
promised to nobody. The beta shows the same list with the dev rows under it, as *Further
out*, and no join section — the reader is already through the door it offers.

**The list has one home, and this page is it** (Jan, dev 68). The beta and dev channels
printed the beta rows twice on one screen: checked off at the top of the **Beta** section,
and again one row below under *In the public beta*. The Beta section is **actions only**
now — *Request a feature*, *Send usage report*, *Check for a newer build* with its status
line, *Start over* — under one short footer: what the page below lists, what the two mails
do and that neither sends anything until Send is tapped, and what Start over takes, in two
sentences. The four paragraphs it carried are gone; what they said lives on that page, on the
usage report's own card, and in the Start over alert, which names every item.

**One test ask lives in that footer, between the two mails and Start over** (Jan, dev 70):
*"Testing the session video: keep the 20 s preset, wait for the bar, then share the clip."*
The session video is a beta door (docs/channels.md), and the ask used to be a step on
`/start`, which was cut. A beta door's ask belongs beside the beta's own feedback doors, so it
is one line here and not a section anywhere: the preset, the wait, the share.

