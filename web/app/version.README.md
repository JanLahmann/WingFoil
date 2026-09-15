# `version.json` — the beta's update switch

One static file, edited by hand, that tells a CleanJibe beta or dev build whether it is old.
**Jan edits it, and nobody else** — it is the only file on the site that changes what an
installed app puts on a rider's screen, so it is a two-minute job with a two-line diff and no
build step anywhere near it.

It is JSON and therefore carries no comments. This file is the comment.

## What the app does with it

Beta and dev builds only (`#if BETA`, docs/channels.md). At launch and on every return to the
foreground, at most **once every 24 hours**, the app fetches this file, looks up its own
channel, and compares `minBuild` with its own `CFBundleVersion`. The comparison happens on
the phone (`UpdateVerdict` in `ios/WingFoilKit`, `UpdateReminder` in the app); the request is
a plain GET with no query string, no header of ours and no cookie store, and it does not say
which build is asking. **Every failure is silence** — offline, a 404, a typo in the JSON: the
app keeps whatever it last read and tries again tomorrow.

The App Store build never reads it. The whole feature compiles out of the release binary, and
`strings` on it finds no `version.json` (docs/testing.md, "Three channels").

## The fields

| field | what it means |
|---|---|
| `minBuild` | The **oldest build still worth a report**, not the newest that exists. A rider at or above it sees nothing; a rider above it — a dev build cut this morning — is never told to go back. |
| `message` | One sentence, in Jan's words, shown on the line and on the screen. Say what the newer build fixes, not that a newer build exists: the rider can see that. |
| `level` | `remind` or `insist`, below. Anything else is read as `remind` — a typo must not be able to put a full screen in front of every tester. |
| `url` | Where *Update* goes. The public TestFlight link for the beta; `itms-beta://` for dev, whose builds are internal and have no public page. Missing or unparsable falls back to the public link. |

A channel key that is **absent** means "say nothing to that channel", and deleting an entry is
how a reminder is taken back off every phone. There is no `release` entry and there is no
point in one.

## `remind` vs `insist`

* **`remind`** — one dismissable line at the top of the library, with the message, an *Update*
  link and a ✕. Closing it is remembered against that `minBuild`, so the next time the number
  goes up the line comes back by itself; Settings → Beta still says a newer build is out.
  **This is the normal setting.** Use it for every ordinary build.
* **`insist`** — one full screen with the message and an *Update* button, in front of the
  whole app, and it cannot be dismissed. It says "reports from this build are no longer worth
  reading", so it is for the rare build that is actually broken: one that loses sessions,
  reports numbers that are wrong, or has been superseded by a fix for something that bit a
  tester. Nothing on the screen touches the library — the sessions stay exactly where they
  are, and the newer build opens them there.

Raising `minBuild` with `insist` locks out every tester who cannot update at that moment, on a
beach, with the session they just rode still on their watch. Think about that before you type
the word.

## Editing it

1. Change `minBuild` to the build you have just published to that channel's TestFlight group,
   and rewrite the `message` to say what it fixes.
2. Leave `level` at `remind` unless the previous build is genuinely not worth reports.
3. Commit with the rest of the web change. GitHub Pages serves it within a minute or two, and
   `web/sw.js` never caches it — the service worker passes this one path straight to the
   network, so an installed web app cannot hand back a stale copy either.

To check what a build will do with an edit before it is live, point a build at a copy of this
file on your own machine: `UI_VERSION_URL` in the scheme's environment, docs/testing.md,
"The beta's update reminder".
