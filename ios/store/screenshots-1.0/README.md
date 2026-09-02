# App Store screenshots — 1.0

Eight screenshots for the **6.9-inch iPhone** display size, `1320 × 2868`, unframed. Apple
accepts an unframed capture, and accepts the 6.9-inch set on its own — it scales the same
images down for every smaller iPhone — so this is the only size that has to exist.

Upload them to ASC in the numbered order. The first three are the ones almost everybody
sees, so they carry the map, the verdicts and the speed.

| # | File | What it shows |
|---|---|---|
| 1 | `01-session-detail.png` | The session page: the whole track on the map with the flown stretches, the pumping and every turn marked, above the key-metrics block — duration, distance, average and best 2 s speed, the flew/touched-down/fell-in tally, best streaks, dry jibes and swims per hour. The one shot that says what the app is. |
| 2 | `02-turn-verdicts.png` | The Turns section: jibes and tacks counted, clean-jibe percentage, the port/starboard split, falls and touchdowns broken out. The forensics behind the verdicts. |
| 3 | `03-speed-and-replay.png` | The speed chart with the flights shaded and the best-10 s window highlighted, the replay scrubber showing live speed, heart rate and "flying", and the foil facts underneath. |
| 4 | `04-replay-commentary.png` | The full-screen replay mid-run, with the commentary caption ("New streak — 3 dry jibes") that plays as the track draws. This is what a recorded clip looks like. |
| 5 | `05-share-card.png` | The share-card composer with the map background switched on: the track over the ground it happened on, the complete stat block, and the card's own footer with the QR back to cleanjibe.org. |
| 6 | `06-all-time-records.png` | The Records tab: best 2 s, 10 s, 5 × 10 s, 100 m, 250 m, 500 m, 1 NM and Alpha 500 across every session, each with its delta to the previous best and where it was set. |
| 7 | `07-season-trends.png` | The Trends tab over a season: sessions, hours, distance and flights, then foil time, longest flight and jibes-flown-through as curves. |
| 8 | `08-welcome.png` | The welcome screen — what the app is in one paragraph, "Try the example session" as the primary action, and the honest note about why Garmin sessions come via intervals.icu. The proof that nothing has to be connected first. |

`alt-library.png` is **not** part of the submission set. It is the Sessions list with the
whole fixture corpus in it, kept here as a ready alternate in case a listing revision wants
"your whole season in one list" instead of one of the eight above.

## No watch imagery

Nothing in this set shows an Apple Watch or a Garmin watch. The Apple Watch recorder in the
bundle is not being announced in this release, and the Garmin watch app has its own store.

## How they were made

All eight come from **one build of 0.13.0 (build 15)** on the `iPhone 17 Pro Max` simulator
(iOS 26.5), which is pixel-identical to the iPhone 16 Pro Max at 1320 × 2868 and is the
simulator the Help pictures already use (`docs/testing.md`, ADR-010). No iPhone 16 Pro Max
runtime is installed on this machine; none is needed.

The data is real. Shots 1–5 are the **bundled example session** — ten real minutes at
Nago-Torbole on Lake Garda, scrubbed of every identifier, the same file any user can open
from the welcome screen. Shots 6 and 7 need more than one session to have anything to draw,
so they were taken with the repo's fixture corpus imported (`UI_IMPORT_FIXTURES=1`, the
developer's own sessions from `fixtures/sessions/`).

Nothing is retouched, composited or mocked up. Every pixel is the app rendering.

### Reproducing them

Build and install:

```sh
cd ios
xcodebuild -project WingFoil.xcodeproj -scheme WingFoil -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath build/dd build
xcrun simctl install booted build/dd/Build/Products/Debug-iphonesimulator/WingFoil.app
```

Set the status bar to Apple's conventional 9:41 with full bars, once per boot — otherwise
every shot carries whatever time the machine happened to be at:

```sh
xcrun simctl status_bar booted override --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
```

Then stage each screen with the `UI_*` hooks (DEBUG + simulator only; they must be prefixed
`SIMCTL_CHILD_`, and the app must be terminated between launches because the environment is
read once at process start). The full hook reference is `docs/testing.md`, "iOS screenshot
hooks".

| # | Launch environment |
|---|---|
| — | first, once: `UI_RESET=1 UI_IMPORT_FIXTURES=1 UI_LOAD_EXAMPLE=1` (this also raises the welcome screen, which is shot 8) |
| 1 | `UI_OPEN_SESSION=latest` |
| 2 | `UI_OPEN_SESSION=latest UI_OPEN_TURNS=1` |
| 3 | `UI_OPEN_SESSION=latest UI_SCROLL_TO=chart UI_PLAYHEAD=0.45 UI_RECORD=best10s` |
| 4 | `UI_OPEN_SESSION=latest UI_REPLAY_LENGTH=25` |
| 5 | `UI_OPEN_SESSION=latest UI_SHEET=share UI_MAP=1 UI_STATS=complete` |
| 6 | `UI_TAB=records` |
| 7 | `UI_TAB=trends` |
| 8 | `UI_WELCOME=1` |

Capture with `xcrun simctl io booted screenshot <file>`.

Two things that bite:

* **Give the app 10–20 s before shooting.** A scroll hook animates, and a shot taken early
  catches the sticky header blurring over content that is still moving. Shot 3 was retaken
  for exactly this.
* **Shot 4 has to be caught.** The replay runs on its own and cannot be paused by `simctl`,
  so the captioned frame comes from a burst — a screenshot every 3 s through a
  `UI_REPLAY_LENGTH=25` run — and the best frame is picked afterwards. `UI_OPEN_SESSION` also
  wants `latest` rather than `example` once fixtures are imported, since the archived
  filename no longer matches.
