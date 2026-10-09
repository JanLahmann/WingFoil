# TestFlight metadata — CleanJibe for iPhone

Source of truth for the App Store Connect beta metadata. This file **mirrors** what is set in
ASC (app `6800401377`, bundle `de.lahmann.wingfoil`); edit here first, then push the same text
to ASC so the two never drift.

Last synced to ASC: 2026-10-09 — beta app description (en-US), pushed through the API and read back identical. "What to Test" is per build (below).

> **This file is the TestFlight half only.** Since 2026-09-02 the public App Store listing
> has its own source of truth in **`ios/store/appstore.md`** — app name, subtitle,
> promotional text, description, keywords, URLs, category, age rating, review notes and the
> App Privacy nutrition-label answers — with the screenshots in
> `ios/store/screenshots-1.0/`. The two do not overlap: beta app description, "What to Test"
> and the beta review contact stay here; everything a public listing needs lives there. If
> you are about to edit App Store copy, you are in the wrong file.

---

## Beta app description

Shown to a tester before they install. ASC field: `betaAppLocalizations.description` (en-US).
4000-character limit.

```
Did you fly through that jibe? CleanJibe reads your session off the watch. It tells you your time on the foil, every flight, your speed records, and a verdict on every turn. Flew through, touchdown, or fell in.

Nail a jibe and it gets a star. Your clean jibes, your dry streak and your best 2 s sit side by side. The share card shows them off.

BRING THE WATCH YOU ALREADY HAVE

On a Garmin, connect intervals.icu once and your history comes in. New sessions then arrive by themselves. On an Apple Watch, record with the CleanJibe Apple Watch app, which comes with this beta. Or record a Surfing workout in Apple's Workout app and import it from Apple Health.

Any watch that syncs to Strava works through Strava. Strava keeps your track but not your watch's speed, so those records are estimated. Any other watch works through its FIT file, opened from Files, Mail or AirDrop. An example session is built in, so you can try every page first.

GET MORE WITH THE WATCH APPS

The free CleanJibe watch app for Garmin buzzes each verdict on your wrist while you ride. The CleanJibe Apple Watch app records your wrist and hands the session to the phone. Both count your pump strokes and takeoff attempts.

WHAT TO TEST

Ride one ordinary session. Open it, go to Turns, and read each verdict against what you remember. Where it disagrees with you, tell us in Menu → Support & ideas. cleanjibe.org/beta says what to look for.

YOUR SESSIONS STAY ON YOUR PHONE

There is no account, no CleanJibe server and no tracking. The engine is open source. No iPhone at hand? The same analysis runs free in any browser at cleanjibe.org.

BUILT WITH ITS RIDERS

CleanJibe is built with its riders. New features land in the beta first, and move to the App Store once testers have proven them.
```

**The App Store description's voice, on purpose** (9 October 2026). The first two paragraphs
are `ios/store/appstore.md`'s, word for word: a tester who later meets the store listing
reads the same promise. What differs is what the beta has. The Apple Watch app and Apple
Health are beta doors (docs/channels.md), so they are named here and not on the store, and
the ways in follow the one order (pattern J): Garmin, Apple Watch, Strava, any FIT. The
Strava sentence says what a Strava session costs, because the rider who asked the question
above is the one who will read it. The *What to test* section is cleanjibe.org/beta's hero
in four sentences, and the last section is `BetaGuide.community`, word for word. No other
platform is named (App Store guideline 2.3.10): the browser is "any browser".

## What to Test

Per-build text. ASC field: `betaBuildLocalizations.whatsNew` (en-US).

**Not written here any more.** `ios/tools/testflight_publish.py` composes it for every build
it attaches: `BetaGuide.community` and a line pointing a new tester at cleanjibe.org/start,
then the newest entry of the build's channel in `docs/copy/whats-new.json`, then
`BetaGuide.whatsNewBeta` and the mail address. The same JSON writes cleanjibe.org/whats-new
and the app's own What's new screen, so the three cannot disagree about one build.
`testflight_publish.py --print-notes` shows the text without sending it. The build 12 text
that stood here until 9 October 2026 promised things that stopped being true (no .gpx, iPhone
only, a personal mail address), which is why a hand-kept copy of a per-build field is gone.

## App Store subtitle candidates

**Decided — see `ios/store/appstore.md`.** The public listing takes
`Foil time, jibes, GPS speed` (27), because the subtitle is indexed for search and the two
candidates below spend their words on terms the app name already carries. They are kept
here as the alternates: `Wingfoil sessions, measured` (27) is the one to reach for if the
listing is ever rewritten to lead with tone rather than search.

- `Wingfoil sessions, measured` (27)
- `Foil time, flights, jibes` (25)

## Other ASC beta fields

| Field | Value |
| --- | --- |
| Feedback email | `jan@lahmann-online.de` (pre-existing, left as is) |
| Marketing URL | `https://cleanjibe.org` |
| Privacy policy URL | `https://cleanjibe.org` — **stale, change to `https://cleanjibe.org/privacy/`.** There was no privacy page when this was set, so it pointed at the homepage; there is one now, and the App Store listing requires the real URL anyway. |
| Beta review contact | Jan-Rainer Lahmann, `jan@lahmann-online.de` (pre-existing, left as is) |
| Demo account | not required — the bundled example session covers review |
