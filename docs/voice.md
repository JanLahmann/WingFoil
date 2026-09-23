# Voice — how CleanJibe talks to a rider

Jan, 15 September 2026: *"knapp, klar, begeisternd"*, and intuitive to operate. Jan, 23
September 2026, reading the app and the site as a rider: the sentences had become a manual.
This file is the voice every rider-facing sentence is written in — the iPhone app, the watch,
the website, the store texts, the tester notes. Every agent that writes or edits rider text
reads it first; a prompt then needs one line: *"voice per docs/voice.md, beach test"*.
`docs/copy/` holds the sentences that appear on more than one surface; this file says how any
sentence sounds.

## Who is talking

**The team that builds CleanJibe, wingfoilers themselves, telling you how it works.** Not a
manual, not a marketing page, not a datasheet. We know the app inside out and we know what
you were doing out there, so we talk about *your session, your turns, your afternoon*, and
about how the app can support you and your passion for wingfoiling. For the interested
rider we also explain the app's mechanics: how a verdict is reached, what comes from the
watch and what from the phone, how it fits with Garmin, Strava, intervals.icu and the other
tools you already use. That understanding helps you use the app well. It comes after the
part about you, never instead of it. Friendly and natural, never clever.

Three traits, and what each one rules out:

| we want | we do not want |
|---|---|
| **about you first.** "You flew through eight of them." "Your best 2 s all season." Then, for the interested rider, how the app did it. | **mechanics with no rider in the sentence.** "It proves the route from the watch to the phone." "Opens a mail with the facts filled in." |
| **natural rhythm.** A short sentence, then a longer one that carries a thought, the way you would say it. | **fragments and staccato.** "Settings → intervals.icu, 4 steps, once." "Free." |
| **wingfoiler words**, including the insider ones: *flew through, touchdown, dry streak, best 2 s, alpha 500, uncertified record, upwind, foil up, pump*. | **IT words.** *route, door, class (b), pipeline, re-derive, digest, ingest, sync target, payload.* |

**The beach test.** Read the sentence aloud to a mate at the van. If you would not say it
that way, rewrite it. This test beats every rule below; the rules exist so that a lint can
catch the mechanics before a person has to.

## Three registers, and where each one is allowed

| register | sounds like | where |
|---|---|---|
| **1 · Plain** — the ground tone | short imperatives, one thought per sentence, a verb in every sentence, no dashes | everywhere not named below: pages, help bodies, import, empty states, errors, release notes |
| **2 · Coach** — rider to rider | warm, second person, a question is allowed, one line of energy | exactly four places: the website hero, the welcome screen, the share card, the end of a session |
| **3 · Spec** — the datasheet | facts first, few verbs, path notation, no persuasion | Settings footers, help *items* (term + line), glossary lines, watch captions, FIT field names |

Never a fourth. The editorial register the texts had until 15 September — long sentences with
em-dashes, an aside in the middle, the *why* before the *what*, a pointe at the end — is
retired for rider text. It lives on in code comments and in `docs/`, where it belongs.

## Eleven rules

1. **One thought per sentence.** About 12 words; never more than 20. Two "and"s or a pair of
   dashes is two sentences.
2. **The rider first, the mechanics after.** *Your session shows up in CleanJibe by
   itself.* Then, where it helps: *intervals.icu carries it over, because Garmin has no open
   API.* A sentence about the mechanics is allowed when a rider can do something with it:
   choose a tool, fix a setup, understand a verdict. It is cut when it only describes what
   the software did.
3. **What, then why — and the why only if it changes what the rider does.** "Restart the
   watch once after installing." needs no reason. "Sessions arrive by themselves" needs one
   clause: "Garmin has no open API, so intervals.icu is the bridge."
4. **No em-dash, no semicolon, no parenthesis in rider text.** A dash is a second sentence
   hiding. A parenthesis is either needed (then a sentence) or not (then gone).
5. **No framing, no pointe, no fragment.** Banned shapes: *the one thing…*, *the half only
   you can do*, *exactly as…*, *which is the whole point*, *not X, but Y* as a flourish, *and
   that is why…*, *…, nothing else.*, and a verbless fragment as a sentence (*Free.* *Once.*
   *Once.*). A fragment is allowed as a heading or as the tagline under the wordmark only; the tagline is *Your WingFoil session, measured.* (Jan, 23 September 2026). Say the thing.
6. **Rider vocabulary, exactly.** *flew through*, *touchdown*, *fell in*, *clean*, *dry
   streak*, *on foil*. Never *carried*, *success*, *no-fall*, *swim rate*
   (`docs/copy/phrases.json` → `lexicon`). Path notation for the app: *Settings → intervals.icu*.
7. **Second person, present tense.** *You*, not *the rider*; *opens*, not *will open*. The app
   is *CleanJibe* or *the app*. *We* is the team that builds it, used sparingly and where a
   person is meant: *tell us what you saw*, *we read every mail*. Never *I*.
8. **Numbers stay numbers.** *2 s*, *500 m*, *10 riders*, *42 watches*. No "a handful", no
   "about ten" where the number is known.
9. **Register 2 gets one line of energy, not a paragraph.** A question, an image, a promise
   — then back to plain. Excitement is a single sentence that earns the next tap.
10. **Every cut fact keeps a home.** If a sentence goes, its fact goes to `docs/`, the help,
    or a store text, or it was not a fact.

11. **Wingfoiler words yes, IT words no.** A wingfoiler's insider word is welcome and is
    taught once in the glossary: *uncertified record*, *alpha 500*, *dry streak*, *foil up*.
    An IT word never reaches a rider: *route*, *door*, *class (b)*, *pipeline*, *re-derive*,
    *digest*, *payload* stay in `docs/`. When in doubt: would another wingfoiler use the
    word on the beach?

## Before and after, from our own texts

**Getting started, no wind (register 1) — the 23 September pair**
> Before: *If you cannot wait for wind. Record a 3 to 5 minute walk on the watch. It proves the
> route from the watch to the phone, nothing else.*
>
> After: *No wind today? Record a five-minute walk with the watch app. It shows up in CleanJibe
> like a session would, so you know the whole path works before your next day on the water.*

**Getting started, feedback (register 1)**
> Before: *Then say how it read. Menu → Support & ideas opens a mail with the facts filled in.*
>
> After: *Tell us what you saw. Menu → Support & ideas opens a mail to us, with your app and
> watch details already in it. Write what looked wrong. That is how the app gets better.*

**Import, Strava (register 1)**
> Before: *Positions only, records uncertified. Without the watch's own speed, a fall can read
> as a touchdown.*
>
> After: *Strava keeps the track but not the watch's speed measurement. Falls are harder to
> tell from touchdowns, and the speed records count as uncertified.*

**Getting started, framing (register 1)**
> Before: *The real test is one session on the water: record it the way you always do, bring it
> in, and read the turn verdicts against what you remember — which jibes you flew through,
> where you touched down, where you fell in.*
>
> After: *Ride one session as you always do, then open it in CleanJibe. Every turn gets a
> verdict: flew through, touchdown, or fell in. You were there, so you can tell us where it
> got one wrong.*

**Website hero (register 2, one of the four)**
> Before: *CleanJibe reads a wingfoil session off your watch and tells you what actually
> happened: how much of it you spent on the foil, how long each flight lasted, your speed
> records, and — for every turn — whether you flew through it, touched down, or fell in.*
>
> After: *Did you fly through that jibe? CleanJibe reads your session off the watch. It tells
> you your time on the foil, every flight, your speed records, and a verdict on every turn.
> Flew through, touchdown, or fell in.*

**Settings → intervals.icu caption (register 3)**
> Before: *Garmin has no open API for a personal app, so intervals.icu is the free bridge:
> connect your Garmin there once and every session arrives here by itself.*
>
> After: *Garmin has no open API, so intervals.icu is the bridge. Connect your Garmin there
> once, and every session arrives here by itself. It is free.*

**Glossary, CPH (register 3)**
> Before: *Clean jibes per hour: you flew through it, you held your speed, and the ten seconds
> after it stayed quiet.*
>
> After: *Clean jibes per hour. Clean: flew through, held your speed, and 10 quiet seconds
> after.*

**Help item, Apple Watch (register 3)**
> Before: *A wrist under water is how a fall is recognised: the pressure sensor sees it and the
> swim is scored. The GPS gap is marked, not sailed through.*
>
> After: *When your wrist goes under, the watch's pressure sensor notices, and that counts as a
> fall. The gap in the GPS track is marked, not filled in.*

**End of a session (register 2, one of the four)**
> *Eight jibes, six flew through, your best 2 s all season. Share the card.*

## What the checks hold

- `HelpBudgetTests` — words per help summary, body and item (the budgets stay).
- `docs/copy/check_release_copy.py` — the lexicon, on the kit, the watch, the site and the
  stores.
- `web/tools/verify_unique.py` — a page's word budget and no sentence twice. `/help/` is
  inside it because its ten sections are folds: a reference work is measured the way a
  reader meets it.
- **`docs/copy/check_voice.py`:** over the kit's `Help/` and `Presentation/` string literals, the
  watch strings, the site's five document pages and the two store texts: no em-dash, no semicolon, no
  parenthesis in a rider string; mean sentence length under 14 words, no sentence over 20;
  the banned shapes of rule 5 as a phrase list. Exemptions written down, printed on every run,
  like the lexicon's.
- **Paragraph budgets, strict:** 40 words a paragraph, 25 in a Settings or Import footer, 20
  a help summary. A paragraph over its budget is **split, never compressed** — rule 10 decides
  where each fact goes.
- **The web is under the same budget** since 19 September 2026 (Jan, reading the site on his
  phone: *"Is this text in our new style?"* — the sentences were, the paragraphs were not).
  The five pages used to be exempt because the extractor could only see a run of text between
  two blank lines of markup. It now reads the block the author typed: every `<p>`, `<li>`,
  `<dd>`, `<figcaption>`, `<summary>` and every table cell is one paragraph, inline tags and
  entities resolved, cut again at every `<br>` the way a Swift literal is cut at every `\n`.
  **The rider text a script writes is read too** — `web/js/*.js`, where a `+`-chain or a
  template literal is one authored string and a literal counts as text once it carries a
  sentence. A chain that builds markup is parsed as markup, so a `<p>` in a script and a `<p>`
  on a page sit under the same 40 words. Files with no rider prose are excluded by name in
  `check_voice.py`, each with its reason, and `// voice: skip` hands one string back to the
  code where no sentence rule fits it (a selector, a declaration, a strip of counts).
- **`docs/copy/check_duplicates.py`:** one sentence, one home inside the app. A line two
  screens both say lives in `WingFoilKit`'s `Copy` enum and is referenced from both.
- Both run from `web/tools/verify_links.py` and from the kit's `CopyLintTests`, so a drift
  fails a web check and `swift test` alike.

## How to ask for text

One line in the prompt: *"Rider text in the voice of docs/voice.md, register N, beach test."*
Name the register when it is not 1. Quote this file's before/after pair that is closest to the surface
being written. Then let the voice lint and the budgets say no before Jan has to.
