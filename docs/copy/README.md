# One copy, many surfaces

Ten JSON files. Each holds rider-facing wording that more than one surface says, so that it
is written **once** and the places that say it are held to it from **both sides**. Nine are
small. The tenth, `help.json`, is the whole of the app's help catalogue, exported so that
cleanjibe.org/help can render the reference work the phone renders rather than writing its
own.

The problem this folder exists for has a date and a time. Everything decided after
14 September 2026 12:30 landed in `docs/`, in the kit and in the app, and never reached the
marketing pages: the website still listed the Garmin export ZIP as a beta feature seven hours
after it became a release door, the phone's clean-jibe definition was a version behind its own
engine, and one metric had four spellings across five surfaces. None of it was a mistake
anybody made twice. It was one mechanism that did not exist.

## The contract

**These files are the single source. They are pinned from both sides.**

| side | what it does | where |
|---|---|---|
| **the kit** | `CopyContractTests` asserts every kit constant equals its JSON. A kit edit that moves a fact **fails the kit tests** until the JSON moves with it. `HelpExportTests` does the same for the help catalogue, which is too large to pin sentence by sentence and is exported whole instead. | `ios/WingFoilKit/Tests/WingFoilKitTests/CopyContractTests.swift`, `HelpExportTests.swift` |
| **the web** | the web verifier asserts the pages carry the same strings. The website then has to catch up before the check goes green. | `web/tools/` |
| **the stores** | `check_release_copy.py` asserts the release copy names no door the release lacks, breaks no Strava rule and uses none of the banned vocabulary. | `docs/copy/check_release_copy.py` |

The JSON is the **artefact**, not the author. The author is:

* **the kit** for anything the app says — `ChannelFeatures`, `RecordingClass`,
  `MetricGlossary`, `FeedbackReport`, `IcuSetupGuide`, `Branding`, `ShareCaption`,
  `WelcomeGuide`, `NotASessionNote`;
* **`docs/channels.md`** for which feature is in which channel;
* **hand, in this folder**, for the short facts that have no code behind them — the Strava
  sentence, the two store names, the forbidden lists and the lexicon.

## Regenerating

After a deliberate wording change in the kit:

```sh
cd ios/WingFoilKit && COPY_WRITE=1 swift test --filter CopyContractTests
```

That rewrites the kit-owned keys of every file in place and **leaves the hand-authored ones
exactly as they were** (`forbiddenInRelease`, `strava`, `stravaForbidden`, `ciqListingTitle`,
`appStoreName`, `appStoreSubtitle`, `lexicon`, every `_readme`, and the row `id`s in
`channels.json`, which are matched by position). Output is deterministic — sorted keys, two
spaces, unescaped slashes — so a regeneration that changes nothing produces no diff.

Then check:

```sh
cd ios/WingFoilKit && swift test --filter CopyContractTests   # the kit side
python3 docs/copy/check_release_copy.py                        # the release-copy side
```

The files stay hand-editable. The assertions compare **values**, never bytes, so formatting
and key order are nobody's contract; `_readme` is a comment and is ignored everywhere.

## The files

### `channels.json`

| key | shape | authored by |
|---|---|---|
| `sectionTitle` | string | kit `ChannelFeatures.sectionTitle` |
| `beta` | `[{ "id", "text" }]` | kit `ChannelFeatures.beta`, written from docs/channels.md |
| `dev` | `[{ "id", "text" }]` | kit `ChannelFeatures.dev`, written from docs/channels.md |
| `forbiddenInRelease` | `[string]` | hand |

`id` is a slug that outlives a rewording, so the web can pin one row while its sentence
changes. The rows are docs/channels.md's beta and dev tables and **nothing else**: a row that
is not in that table is a promise nobody made. (The Garmin export ZIP left the beta list on
14 September 2026; the website kept promising it.)

`forbiddenInRelease` is the guard, not a list of rows: no release copy may contain any of
these, case-insensitively, as a substring. It is **tuned** so that the live App Store text
passes while every door above the release is still caught:

* `"Health"` alone would fire on the *Health & Fitness* App Store category, so the entries are
  `"Apple Health"` and `"HealthKit"`.
* `"watch app"` alone would fire on the **CleanJibe Connect IQ watch app**, which is a
  release feature and one of the description's selling points, so the entry is
  `"Apple Watch app"`.
* `"windsurf"` stays, because the windsurf *discipline* is a dev door — but Garmin's own
  **Windsurf** activity profile is a legitimate class B recording source and an App Store
  keyword, so `appstore.md` carries a named exemption for it.

### `recording-classes.json`

`classes`: `[{ "id", "name", "line", "footerLine" }]` — all four cases of `RecordingClass`, in
order, wholly kit-owned. `footerLine` is `name + ". " + line`.

### `glossary.json`

`entries`: `[{ "id", "term", "short", "expansion", "line", "sentence", "surfaces" }]` — the
**eleven** words the product is made of (foil share, flights & touchdowns, turn verdicts, dry
streak, JPH, CPH, TPH, WPH, speed records, best 5×10 s, alpha 500), from `MetricGlossary`. The
welcome screen selects four of them; `web/help`'s definition list carries all eleven, under
*What the numbers mean*, which is what `/learn/` opened with until 19 September 2026.

| field | what it is | authored by |
|---|---|---|
| `id` | a slug that outlives a rewording | kit |
| `term` | **the label** — the iPhone card, the web tile, `/help`'s `<dt>` | kit |
| `short` | the same word at the watch's width: **≤ 7 characters** wherever `surfaces` names `watch` | hand |
| `expansion` | what the phone and the web append after `" · "` — `"clean jibes per hour"`. Empty where the term is the whole of it | kit |
| `line` | the one sentence | kit |
| `sentence` | the clause the two store descriptions print instead of the label | hand |
| `surfaces` | who may demand this word: `ios` · `watch` · `web` · `appstore` · `ciq` | kit |

Three entries were added on 15 September 2026 because the app printed them on every session
and no surface defined them: `tph` (CLAUDE.md — *rates are additive: keep JPH and TPH beside
CPH*; the number was additive, the glossary was not), `best5x10s` and `alpha500`. In the same
pass `foilShare.term` became **`On foil`** — the spelling `docs/presentation.md`'s label table
already decided and every screen already prints, against a glossary that still taught
`Foil %` — and `turnVerdicts.line` became a list of nouns (`touchdown`, not *touched down*).

**`short` and `sentence` are hand-authored**, exactly the way `lexicon` and `ciqListingTitle`
are: a `COPY_WRITE=1` regeneration carries them forward and seeds only a brand-new entry from
the kit. The watch is not excused from the contract, it is held to it **at its own width** —
a MIP cell is about seven characters, three watch labels ship over that today, and
`CopyContractTests` asserts the budget so it fails a test instead of failing a rider.

The long explanations — the 12 / 8 km/h foil gates, the outcome ladder, the 70 % score — are
**not** here. They stay in `HelpCatalog`, which is reference material behind a `?`, and they
reach the site through `help.json` rather than through this file: same terms, different
depth. Pin the terms and the one-liners here, export the bodies there, and write neither
twice.

### `feedback.json`

`prompts` (the three `FeedbackReport.Prompt` strings), `invitation`
(`FeedbackInvitation.sentence`), `subjectPrefix` (`"CleanJibe feedback"`) and `doors`
(`FeedbackDoors`). Wholly kit-owned.

`doors` is **the name of each door to that mail, exactly as a rider finds it** —
`app` (`Menu → Support & ideas`), `footer` (`Something off, or an idea? Send feedback`),
`share` (`Report a problem with this session…`), `testflight` (Apple's own
`Send Beta Feedback`) and `web` (the address). There were five spellings of one door on
15 September 2026, and one of them — `Settings → Send feedback`, quoted inside the app's own
Help — named a row **deleted in build 58**. The file pinned the prompts, the invitation and
the subject prefix and no door name, so neither side of the contract could notice. A rider
who follows a door name finds a screen or he does not; there is no third outcome.

The web's `mailto:` templates legitimately ask two questions the app does not — the watch and
phone, and the app version — because a browser cannot fill them in and the app can. Only these
four strings are pinned.

### `icu-setup.json`

`steps`: `[{ "title", "detail" }]`, `saveButton`, `privacyNote` — wholly kit-owned from
`IcuSetupGuide`. `saveButton` is the label on the button itself (`IcuKeyEntry`) as well as the
one step 4 names.

**The two getting-started Settings captions are not here.** They live in
`docs/guide/getting-started.json` (`settings.intervalsIcu`, `settings.strava`) and reach the
app through the generated `GettingStartedGuide`. One guide, one home — do not copy them.

### `phrases.json`

| key | authored by |
|---|---|
| `promise` | kit `WelcomeGuide.promise` |
| `headline` | kit `WelcomeGuide.headline` |
| `callToAction` | kit `Branding.callToAction` |
| `captionOffer` | kit `ShareCaption.offer` |
| `strava`, `stravaForbidden` | hand — docs/channels.md's rule |
| `ciqListingTitle`, `appStoreName`, `appStoreSubtitle` | hand — what the two stores show |
| `lexicon` | hand |

**`ciqListingTitle` is what the Connect IQ store shows today**, which is
*CleanJibe Wingfoil Tracker (Beta)*. docs/channels.md has decided the rename to
**CleanJibe Wingfoil Watch App Beta**; this value flips on the day Garmin's store shows it and
not before, because every page that prints the link text is checked against what a rider
actually sees. `ios/store/appstore.md` no longer claims the iPhone app and the watch app share
a name — they never did.

`lexicon` is `{ "banned": [string], "preferred": { term: meaning }, "exemptions": [...] }`.
The banned words are checked as **whole words**, case-insensitively, against the **string
literals** of the kit's `Presentation/` and `Help/` sources and against `ios/store/*.md` —
by `CopyContractTests` and by `check_release_copy.py`, so a kit author fails before a release
engineer does. Doc comments are not read: they are written for the next author and describe
the engine on purpose.

An **exemption** is `{ "word", "path", "why" }` — a path prefix where a banned word is
ordinary English or a pinned cross-platform string. Three exist today and each says why. They
are printed on every run of the checker, because an exemption that is not read becomes the
rule.

### `verdicts.json`

`notASession`: `{ "tag", "lines": [string, string] }` — wholly kit-owned from
`NotASessionNote`. `lines[0]` is the no-recording case; `lines[1]` is the short /
went-nowhere case and carries two placeholders:

* `{duration}` — the session clock, `m:ss` under an hour and `h:mm:ss` over it;
* `{distance}` — metres under a kilometre, otherwise one decimal of km.

Both are the library row's own displayed numbers, so the line reads against the key metrics
directly above it rather than quoting a third figure.

### `presentation.json`

**The words the presentation document points at** (ADR-033,
`docs/presentation/document.md`). The document carries no rider sentence: every label and
caption in it is an *id* plus the arguments the sentence interpolates, and this is where the
ids that no other artefact already owns are resolved. Four groups, all **hand-authored**
here, like the Strava sentence and the lexicon:

| group | holds |
|---|---|
| `label` | the key-metrics block's own labels — `duration`, `max 2 s`, `flew · touchdown · fell` |
| `rowMetric` | the library row's short spelling of each metric, deliberately shorter than the glossary term because it sits under a value in caption type beside two others |
| `turnKind` | the rider's word for a kind of sweep, interpolated *into* a caption rather than named by a `labelId` |
| `caption` | the small line under a cell. A caption with a `one` key has a singular form, used when its first argument is 1 |
| `wristUnder` | the "wrist under" callout, title and `during` clause |

The other three namespaces a `labelId` may use are `glossary.<id>` (below),
`verdicts.notASession.*` (below) and `tokens.recordWindow.<id>` / `tokens.layer.<id>` in
`design/tokens.json`, which is copy for the record and layer names. The lab's
`test_every_label_and_caption_is_an_id_that_exists_in_copy` fails on an id with no home, and
its twin fails on a line here that no document can reach.

### `help.json`

**The app's whole help catalogue, and the one file here that is rendered rather than
quoted.** Written by `HelpExportTests` (`COPY_WRITE=1 swift test --filter HelpExportTests`)
out of `HelpCatalog`; read by `web/tools/make_help.py`, which renders
`web/help/index.html`.

```
sections: [{ id, title, topics: [{ id, title, summary, body[], items[{term, detail,
             channels[]}], related[], channels[] }] }]
```

Ten sections, 42 topics, 94 items today. `channels` is **the list of channels that may read
that row** (docs/channels.md) — `["release","beta","dev"]` for almost everything, `["beta",
"dev"]` for the two Apple doors, `["dev"]` for windsurf. An item's channels are *derived*
rather than declared: the exporter asks each channel what `HelpCatalog.topic(_:channel:)`
gives it and takes the lowest that sees the item, so the one topic whose items branch
(Getting started, whose routes are the two Apple doors) needs no special case, and neither
will the next one.

The web prints a release row plainly, a beta row with the `beta` pill, and a dev row **not
at all** — the same rule `make_whats_new.py` applies to a dev release note, and for the same
reason: a public page that names a dev door promises a stranger a door nobody can have.

Jan, 19 September 2026: *"/help is built from the app's help catalog"*. Before it,
`/learn/` answered four of the catalogue's questions in its own words, written in the
website's own pass; three of the four had been answered differently in the app for a month.
`/learn/` is a redirect to `/help/#numbers` now.

### `garmin-devices.json`

Generated from `garmin/manifest*.xml` — the product count, the version and the families. Not
kit-owned and not checked by `CopyContractTests`; the app names no count and no model on
purpose (`HelpCatalog.whichWatch`: "CleanJibe analyses a recording, not a brand"). See the
web tooling for its schema.

### `whats-new.json`

**The release notes, and the one file here that no code authors.** Hand-written, newest
first, one entry per shipped build:

| key | shape | what it decides |
|---|---|---|
| `version` | string | the app's marketing version, or the watch app's Connect IQ version |
| `build` | int, or `null` | the TestFlight build number. `null` means the **Garmin watch app**, which has no build number — that one field says which of the two products the entry is about |
| `channel` | `release` \| `beta` \| `dev` | where the build went (docs/channels.md). The app filters on it; the website prints no `dev` entry at all |
| `date` | `yyyy-mm-dd` | the day it shipped. Rendered into words by the generator, never typed |
| `title` | string, ≤ 8 words | the card's one line |
| `lines` | [string], ≤ 20 words each | register 1 of docs/voice.md, one thought per line |

Three renderings, one source: `web/tools/make_whats_new.py` writes the cards on
`web/invite/index.html` (`/whats-new/` until 19 September 2026, and a redirect to
`/invite/#whats-new` since) and the kit's `Help/WhatsNew.swift` (the app's *What's new*
screen), and `ios/tools/testflight_publish.py` reads the newest entry of the channel it is
publishing to as that build's *What to Test*. `make_whats_new.py --check` runs inside
`web/tools/verify_links.py` and fails while either generated output is stale. The word
rules are enforced on the source, so a long or dashed line fails at the generator.

**Dates are allowed in these sentences and nowhere else in the app.** A release note that
does not say when it shipped is not a release note; the condition is that a generator
writes them, which is why `/invite/` and `WhatsNew.swift` are the two `dated` targets of
`check_voice.py` rather than a list of exemptions. On the page the generated block is
wrapped in `data-copy="whats-new"` and stripped the way a generated `garmin-count` span is,
so only the release notes are excused and the rest of the beta page is still held to the
rule.

## The process rule

A kit change that moves a fact **fails the kit tests** until `docs/copy` catches up. That is
half the pin; the web verifier is the other half. Run both in the same pass:

```sh
cd ios/WingFoilKit && swift test --filter CopyContractTests
python3 docs/copy/check_release_copy.py
```

The root cause this guards against is not a missing mechanism. `RecordingClass.swift` was
written *specifically* to stop this drift, and the web copy it was meant to govern had been
authored eighteen minutes earlier in a different worktree. The root cause is that the website
is edited in a separate pass from the app, and the app's pass is the one that keeps running.
So the check has to run **where the kit's tests run** — otherwise the next 14 September
19:37 produces the next fourteen bugs.

## The watch is inside the contract too (15 Sep 2026)

`check_release_copy.py` scans the watch as it scans the kit: every `"…"` literal in
`garmin/source/ui` and `garmin/source/alerts` and every line of `garmin/resources/strings`
for the lexicon, the two live blocks of `garmin/store/listing.md` (Description, What's New)
for the Strava rule and the lexicon, and the listing's title line against
`phrases.json → ciqListingTitle`. Exemptions live in the target's `allow` map as everywhere
else and are printed on every run. The watch's *labels* are held by `glossary.json → short`
(seven characters or fewer for every entry whose `surfaces` name the watch, asserted by
`CopyContractTests`); wiring `PageModel`'s captions to those shorts is the next step.

