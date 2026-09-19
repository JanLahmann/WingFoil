# Voice — how CleanJibe talks to a rider

Jan, 15 September 2026: *"knapp, klar, begeisternd"*, and intuitive to operate. This file is
the voice every rider-facing sentence is written in — the iPhone app, the watch, the website,
the store texts, the tester notes. Every agent that writes or edits rider text reads it first;
a prompt then needs one line: *"voice per docs/voice.md"*. `docs/copy/` holds the sentences
that appear on more than one surface; this file says how any sentence sounds.

## Three registers, and where each one is allowed

| register | sounds like | where |
|---|---|---|
| **1 · Plain** — the ground tone | short imperatives, one thought per sentence, a verb in every sentence, no dashes | everywhere not named below: pages, help bodies, import, empty states, errors, release notes |
| **2 · Coach** — rider to rider | warm, second person, a question is allowed, one line of energy | exactly four places: the website hero, the welcome screen, the share card, the end of a session |
| **3 · Spec** — the datasheet | facts first, few verbs, path notation, no persuasion | Settings footers, help *items* (term + line), glossary lines, watch captions, FIT field names |

Never a fourth. The editorial register the texts had until 15 September — long sentences with
em-dashes, an aside in the middle, the *why* before the *what*, a pointe at the end — is
retired for rider text. It lives on in code comments and in `docs/`, where it belongs.

## Ten rules

1. **One thought per sentence.** About 12 words; never more than 20. Two "and"s or a pair of
   dashes is two sentences.
2. **Verb first, then the thing.** *Ride one session.* *Open it.* *Check each turn.* Not
   "The real test is one session on the water: record it…".
3. **What, then why — and the why only if it changes what the rider does.** "Restart the
   watch once after installing." needs no reason. "Sessions arrive by themselves" needs one
   clause: "Garmin has no open API, so intervals.icu is the bridge."
4. **No em-dash, no semicolon, no parenthesis in rider text.** A dash is a second sentence
   hiding. A parenthesis is either needed (then a sentence) or not (then gone).
5. **No framing, no pointe.** Banned shapes: *the one thing…*, *the half only you can do*,
   *exactly as…*, *which is the whole point*, *not X, but Y* as a flourish, *and that is why…*.
   Say the thing.
6. **Rider vocabulary, exactly.** *flew through*, *touchdown*, *fell in*, *clean*, *dry
   streak*, *on foil*. Never *carried*, *success*, *no-fall*, *swim rate*
   (`docs/copy/phrases.json` → `lexicon`). Path notation for the app: *Settings → intervals.icu*.
7. **Second person, present tense.** *You*, not *the rider*; *opens*, not *will open*. The app
   is *CleanJibe* or *the app*, never *we* in register 1 and 3. *We* is allowed in register 2.
8. **Numbers stay numbers.** *2 s*, *500 m*, *10 riders*, *42 watches*. No "a handful", no
   "about ten" where the number is known.
9. **Register 2 gets one line of energy, not a paragraph.** A question, an image, a promise
   — then back to plain. Excitement is a single sentence that earns the next tap.
10. **Every cut fact keeps a home.** If a sentence goes, its fact goes to `docs/`, the help,
    or a store text, or it was not a fact.

## Before and after, from our own texts

**Getting started, framing (register 1)**
> Before: *The real test is one session on the water: record it the way you always do, bring it
> in, and read the turn verdicts against what you remember — which jibes you flew through,
> where you touched down, where you fell in.*
>
> After: *Ride one session as you always do. Open it in CleanJibe. Check each turn: flew
> through, touchdown, fell in. Only you know which it really was.*

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
> After: *Garmin has no open API, so intervals.icu is the bridge. Connect Garmin there once.
> Every session then arrives here by itself. Free.*

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
> After: *A wrist under water counts as a fall. The pressure sensor sees it. The GPS gap is
> marked, not filled.*

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

One line in the prompt: *"Rider text in the voice of docs/voice.md, register N."* Name the
register when it is not 1. Quote this file's before/after pair that is closest to the surface
being written. Then let the voice lint and the budgets say no before Jan has to.
