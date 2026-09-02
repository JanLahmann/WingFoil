# TestFlight metadata — CleanJibe for iPhone

Source of truth for the App Store Connect beta metadata. This file **mirrors** what is set in
ASC (app `6800401377`, bundle `de.lahmann.wingfoil`); edit here first, then push the same text
to ASC so the two never drift.

Last synced to ASC: 2026-09-01 — beta app description (en-US), build 12 / 0.10.0 "What to Test".

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

```
CleanJibe turns a wingfoil session into the numbers you actually argue about at the beach: how much of it you spent on the foil, how long each flight lasted, your speed records, and — for every turn — whether you flew through it, touched down, or fell in.

The app imports the .fit file your Garmin recorded, re-analyses it on the phone, and keeps every session in one library with your all-time records and season trends. You get the full track on a map, a replay you can scrub through with commentary as it plays (and record as a video to post), the turn-by-turn forensics behind every verdict, and a share card for the sessions worth showing.

It works with the CleanJibe Connect IQ watch app and with Garmin's own Windsurf profile. Pump strokes and takeoff effort need the CleanJibe watch app, because only it records the wrist accelerometer; everything else works from either. Sessions arrive on their own if you sync Garmin to intervals.icu, or you can open a .fit file a friend sent you — those are kept out of your own records.

An example session is bundled, so you can see the whole app before importing anything. Nothing is uploaded: the analysis runs on your phone.

No watch app and no iPhone? The same analysis runs free in any browser at cleanjibe.org.
```

## What to Test

Per-build text. ASC field: `betaBuildLocalizations.whatsNew` (en-US). Currently set on build 12.

```
Please try, in this order:

1. Open the app and look at the bundled example session first — everything works without importing anything.

2. Import one of your own sessions. Either connect intervals.icu in Settings (paste your personal API key) or share a .fit file into the app from Files or Mail.

3. Check the verdicts against what you remember: open a session, look at the turn list, and tell me where "flew through / touched down / fell in" disagrees with what actually happened. This is the single most useful feedback — the thresholds are tuned against real sessions and yours is one I do not have.

4. Scrub the replay and record a clip. Does the commentary match what the track is doing?

5. Make a share card and send it to yourself. Is anything on it wrong or missing?

6. Records and trends: after two or three sessions, do the all-time records look right?

Known limits: iPhone only; no Android app (use cleanjibe.org in a browser instead). .gpx files are not supported. Pump strokes and takeoff effort only appear for sessions recorded with the CleanJibe watch app.

Report anything to jan@lahmann-online.de or as a GitHub issue at github.com/JanLahmann/WingFoil.
```

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
