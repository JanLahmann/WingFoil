# Security — the threat model, and what is open

**Scope.** The iPhone app and its watch app, `WingFoilKit`, the static site and its Pyodide
engine, the Connect IQ watch app, the Python lab, and the public repository itself. Written
20 September 2026, against the tree at that date.

**The one fact that shapes everything below: there is no CleanJibe server.** No account, no
login, no database anybody else can reach, no API of ours for anybody to attack. Nothing can
be breached at CleanJibe because there is nothing at CleanJibe. That is not a slogan — it is
the reason this document is short, and the reason the risks that remain are all of one kind:
**something arrives on the rider's own device and behaves badly there.** A file, a message
from a watch, a page in a browser, a library update, a card handed to a friend.

The second fact is that the repository is **public**. Every threshold, every parser, every
byte of the wire format is readable by whoever wants to write a hostile file. That is a
deliberate trade and this document does not relitigate it; it means only that nothing here
may rest on an attacker not knowing how something works.

---

## Assets — what is actually worth protecting

Ranked by what it would cost the rider to lose.

| Asset | Where it lives | What loss looks like |
|---|---|---|
| **The intervals.icu API key** | iOS keychain (`Keychain.icuApiKey`); **browser `localStorage`** on the web (`wingfoil.icu.key`) | A full-account bearer credential: read and **write** every activity and wellness record the rider has. Not scoped, not expiring, not revocable per app |
| **The Strava refresh token** | iOS keychain (`Keychain.stravaTokens`), one JSON blob | Read access to every Strava activity including "Only you" ones, for as long as it is not revoked |
| **The session library** | on-device SQLite + `original.fit` archive; OPFS/IndexedDB in the browser; the iCloud Drive container in beta/dev | Every place the rider has ridden, at one-second resolution, with the times. The **home spot** is the most sensitive single fact in the app: it is a house |
| **The Strava client secret** | inside the shipped binary's `Info.plist` | Impersonation of the CleanJibe Strava application (see F-04) |
| **The rider's phone staying up** | — | Not confidentiality but availability: a file that kills the app on open is a file the rider cannot get past |
| **The repo's own integrity** | GitHub | A supply-chain change that ships to everyone who installs |

Deliberately *not* on this list: the analysis numbers. They are a hobby's arithmetic, they are
published in `docs/algorithms.md`, and nobody is attacking a jibe count.

---

## Trust boundaries

Six places where data crosses from somebody else's control into ours. Every finding below
sits on one of them.

1. **File → app.** A `.fit`, `.gpx`, `.tcx`, `.cjw`, `.zip` or `.gz` arriving by share sheet,
   Files, AirDrop, a GDPR export, or dropped on the web page. *The largest attack surface in
   the project*, because the parsers are hand-written and the files are adversary-shaped.
2. **Watch → phone.** Connect IQ messages and direct-transfer pages; watchOS `.cjw`
   containers. The phone trusts bytes a wrist sent it.
3. **Cloud → app.** intervals.icu JSON and original files, Strava activity JSON, Nominatim
   place names. All attacker-influenced in the weak sense that a rider's *own* Strava title
   can contain anything, and in the strong sense that a hostile network sits between.
4. **Browser page → everything in its origin.** Any script on `cleanjibe.org` can read the
   icu key in `localStorage` and the whole library in OPFS. This is the boundary the web app
   is thinnest on.
5. **CDN → browser.** Pyodide from jsdelivr, a wheel from PyPI, analytics from umami — three
   third parties whose code runs *inside* boundary 4.
6. **Contributor / CI → shipped artifact.** The repo, the Actions workflows, the pinned
   dependencies, FitFileParser among them — pinned to a commit rather than to a tag.

---

## Who the adversaries are

Honest ones, for a hobby app with a public repo and no server. Named because a threat model
whose adversary is "a hacker" produces findings nobody can rank.

- **A malicious file.** Somebody on a forum posts "here's my session, open it in CleanJibe".
  The file is built from the parsers in this repo. This is the *only* adversary who needs no
  access to anything, and it is therefore the one the findings below are mostly about.
- **A malicious watch or phone message.** Requires a Connect IQ app on the rider's own watch
  or a process able to talk to the companion link — so it is mostly a **self-inflicted**
  boundary. It matters anyway, because a crash here looks to the rider exactly like a bug and
  because the `.cjw` container is also a *file* format (boundary 1) and arrives from strangers
  through the share sheet.
- **A hostile web page.** Can navigate the browser to `cleanjibe.org` or open `cleanjibe://`.
  Cannot read the app's storage (same-origin), cannot read the keychain. Its real lever is
  getting a script into our origin — which is why the CSP gap and the CDN dependencies are
  the two web findings that matter.
- **A supply-chain change.** Somebody who can alter what a build pulls in: a hijacked Action
  tag, a compromised CDN, an upstream package. Low likelihood, total impact.
- **A leaked secret.** The intervals.icu key, the Strava secret, the App Store Connect `.p8`,
  the unlock pepper. The git history is clean (see F-12) so this is about what ships, not
  about what was committed.
- **A curious co-rider with a shared card.** The one adversary who is not an attacker at all:
  somebody the rider knows, looking at a share card or a `.cjw` that was handed over on
  purpose, and learning more from it than the rider meant to give. Low severity, real
  embarrassment.

---

## Findings

Severity is *for this project*: what it costs this rider, on this phone, with no server
behind it. `S` ≈ under an hour, `M` ≈ an afternoon, `L` ≈ a project.

| # | Sev | Surface | Where | Exploit | Fix | Eff | State |
|---|---|---|---|---|---|---|---|
| **F-01** | High | file → app | `WatchImport/WatchSessionContainer.swift`, `decode` | A `.cjw` whose header says `offset: Int.max`, `length: -1` or `recordBytes: 1` on a `track.v1` stream. Swift traps on the overflow, on the inverted range and on the out-of-bounds read — the app dies on **every** open of that file, with no crash the rider can act on | Check the four header numbers before forming an index: non-negative, `addingReportingOverflow`, and a known tag must state the width this build reads | S | **fixed** |
| **F-02** | High | CDN → browser | `web/js/worker.js:41,49` | `import()` of `pyodide.mjs` from jsdelivr (no SRI — a dynamic import cannot carry one) and `micropip.install("fitdecode==0.11.0")` from PyPI, on every cold boot. A compromise of either runs attacker code **inside the origin that holds the icu key and the whole library** | Self-host the pinned Pyodide build and vendor the wheel — `FITDECODE_LOCAL_WHEEL` at `worker.js:29` is the hook, already written and set to `null` | M | backlog |
| **F-03** | High | CDN → browser | `web/sw.js:207-212, 314-323` | The service worker is cache-**first** over `cdn.jsdelivr.net`, `pypi.org` and `files.pythonhosted.org`. One poisoned response on a café network is stored and replayed *forever* — `activate` prunes only other versions, so nothing expires it | Never cache-first third-party executable code. Dissolves entirely if F-02 is done | M | backlog |
| **F-04** | Med | shipped binary | `ios/project.yml` (`STRAVA_CLIENT_SECRET`) | **Strava has no PKCE.** The token exchange requires the client secret, so the secret must be in the app, so it is in the `Info.plist` of every IPA, in plain text, for anyone who unzips one. The xcconfig being gitignored protects the repo and not the product. Impact is bounded: with the secret alone an attacker can build an app that *looks* like CleanJibe to Strava and burn its athlete cap (currently 10) — he cannot read anybody's activities without also getting that rider through a consent screen | There is no fix that keeps the design. A code-exchange endpoint on a server of ours is the real one, and buying a server to hold one secret is a bad trade at this size. **Name it instead**: say so in `/privacy/`, and rotate the secret if abuse appears | L | documented |
| **F-05** | Med | file → app | `IcuClient/IcuPayload.swift`, `Gzip.rawInflate`; `Import/ZipWalker.swift` | A gzip or zip bomb: a few hundred kilobytes that inflate to gigabytes, arriving as an intervals.icu original or a ZIP member. The inflate loop appended without a cap until iOS killed the app | `ZipSizes.maxInflatedBytes` (512 MB): the declared size gates a ZIP member before inflation, and the gzip loop stops and throws `tooLarge` | S | **fixed** |
| **F-06** | Med | file → app | `GpxImport/GpxSessionParser.swift`, `TcxImport/TcxSessionParser.swift`, `lab/src/wingfoil_lab/{gpx,tcx}.py` | XML entity expansion — the billion laughs. Three kilobytes of GPX, a gigabyte of string, on a phone or in a browser tab. Foundation happened to refuse *external* entities by default; nothing refused internal ones, and Python's `ElementTree` refused neither | A `<!DOCTYPE>` subset is refused outright in all four parsers (`SafeXML.swift`, `gpx.safe_parser`). No recording schema has one | S | **fixed** |
| **F-07** | Med | browser origin |  `web/js/icu.js:17,61` | The intervals.icu API key sits in `localStorage` in clear. Any script in the origin reads it — the umami script, a future escaping slip, anything that gets in through F-02/F-03. It is a **full-account, non-expiring, read-write** credential | There is no browser storage a script in the origin cannot read, so the honest fixes are (a) keep the key out of the browser and make icu import iOS-only, or (b) keep it and say plainly in `/privacy/` that it is stored in the browser. Not a code fix | M | backlog |
| **F-08** | Med | browser origin | all of `web/**/*.html` | No Content-Security-Policy anywhere — no meta tag, no `_headers`, and GitHub Pages sets none. Nothing constrains a script that gets in | A meta CSP. The blocker is inline script: 9 blocks, but only **3 unique bodies** (a topbar-measure snippet repeated seven times, the install banner, the Strava forwarder). Extract the first two to modules and no hashes are needed. A draft is at the foot of this file | M | backlog |
| **F-09** | Med | CI → artifact | `.github/workflows/pages.yml` | `pages: write` and `id-token: write` sat at the **top level**, so the `check` and `gate` jobs held them — and those run on `pull_request`, executing scripts out of the proposed branch. A PR could have run code with a token that publishes the live site | Top level is `contents: read`; the write moved onto `deploy`, which runs only on a push to main | S | **fixed** |
| **F-10** | Med | CI → artifact | `.github/workflows/*` | Every action is pinned by mutable tag (`actions/checkout@v4`, `astral-sh/setup-uv@v5`, …) and there is no `dependabot.yml`. A hijacked tag runs in the job that deploys | Pin to commit SHAs; add `.github/dependabot.yml` for `github-actions` and `swift`. Jan's call — Dependabot opens PRs on his repo | S | backlog |
| **F-11** | Med | file → app | `WatchImport/WatchSessionContainer.swift`, `decodeTrack` | `t`, `lat` and `lon` were raw `Double` bit patterns with no finiteness check — the three *optional* channels had one and the three required ones did not. A NaN latitude is well-formed on the wire and survives every comparison downstream: a pin at no place, a distance of NaN, a card with a hole in it | A sample whose clock or place is not a number is dropped, exactly as a `trkpt` with no time is | S | **fixed** |
| **F-12** | Info | repo | git history | **Clean.** `git log --all --diff-filter=A` and pickaxe searches find no `lab/.env`, no `garmin/gen/UnlockPepper.mc`, no `.p8`, no `.der`, no `ios/Strava.xcconfig` ever added. The only `STRAVA_CLIENT_SECRET` hits are the empty template and a `$(VAR)` reference. **No rotation is required.** `garmin/screenshots/source/ShotsApp.mc` was tracked until 19 Sep 2026 and stays reachable in history — a screenshot harness, no credential, leave it | — | — | verified |
| **F-13** | Low | keychain | `ios/WingFoil/App/Keychain.swift:36` | Items are `kSecAttrAccessibleAfterFirstUnlock` **without** `ThisDeviceOnly`, so the icu key and the Strava refresh token travel in an encrypted iPhone backup and restore onto another device. Also, the accessibility class is set only on *insert*: an item written by an older build keeps whatever class it had | Decide deliberately. `…AfterFirstUnlockThisDeviceOnly` is the safer class and costs the rider a re-connect after a phone migration; the current class is the friendlier one. Whichever wins, set it on update too | S | backlog |
| **F-14** | Low | phone ↔ watch (dev) | `ios/WingFoil/Companion/DirectTransferInbox.swift:104-111` | Pages arrive under an attacker-chosen `sid` and are written to Application Support with no cap on session count or total bytes — thousands of ids × 8 KB pages fills the disk. **Dev channel only**, and the sender must already be a Connect IQ app on the rider's own watch | Cap concurrent sessions and total inbox bytes; sweep harder | M | backlog |
| **F-15** | Low | cloud → app | `web/js/spots.js:218,244` and the iOS `SpotNamer` | Reverse geocoding sends the spot to Nominatim rounded to **3 decimals ≈ 110 m** — good, and the two implementations agree. **Tile requests do not**: the map layer sends the exact viewport to the tile server, so opening a session at home tells that server where home is | Nothing to fix in the rounding; `/privacy/` should name the **tile layer** beside Nominatim, because it is the request that carries more | S | backlog |
| **F-16** | Low | web | `web/js/viz.js`, `web/js/icu.js` | Two independent copies of `esc()`, neither escaping `'`. No single-quoted attribute exists today, so it was latent rather than live — but "safe because of where the value came from" is the reasoning that has to be re-checked on every edit | Both copies now escape `'`; `app.js`'s one unescaped engine-supplied label is wrapped too | S | **fixed** |
| **F-17** | Low | repo | `.gitignore`, `lab/tools/scrub_fit.py` | `scrub_fit.py` is what makes a recording committable, and **nothing asserts it ran**. The 14 files under `fixtures/sessions/` rest on discipline. (`docs/engineering.md` recorded a real instance: a device serial and body metrics in the public repo.) `.gitignore` also has no pattern for raw recordings — only `fixtures/footage/**` | A lab test that walks every tracked `.fit` and asserts serial 0 and no globals 3 / 79 / 140 / 147; wire it into `checks.yml` | S | backlog |
| **F-18** | Low | repo | `ios/tools/testflight_publish.py:36-37` | The App Store Connect issuer id and the absolute path to the `.p8` (whose filename carries the Key ID) are hardcoded in a public file. Two of three factors, and a good phishing hook; the key itself has never been in the repo | Read both from the environment | S | backlog |
| **F-19** | Low | web | `web/lab_bundle/MANIFEST.json`, `worker.js` `mountLab` | The manifest holds truncated (16 hex) hashes of `wingfoil_lab/*` only — `library.py` and `web_entry.py`, the largest shipped engine files, are hashed by nothing — and **nothing verifies any of it at load**. `bundle_lab.py --check` is a build-time guard, not a runtime one | Hash everything in `FILES.json`, full SHA-256, and verify in `mountLab()` before `writeFile` | M | backlog |
| **F-20** | Low | OAuth | `web/strava/callback/index.html` | The authorization code transits a **GitHub Pages** URL as a query parameter, so it appears in logs Jan does not control. Mitigations are real: the code is single-use and expires in seconds, the page forwards an allowlist of five parameters and nothing else, carries no third-party script, and `ASWebAuthenticationSession` intercepts the `cleanjibe://` hop in-process so another app cannot claim it. Strava's single-callback-domain rule leaves no alternative | None available. Recorded so nobody "fixes" the bounce page into something that logs more | — | accepted |
| **F-21** | Info | watch | `garmin/source/lock/LockGate.mc`, `lab/tools/make_unlock.py` | The invite pepper ships inside the `.prg` on every watch, so **it is extractable by anyone with the binary** — and the gate is FNV-1a, which is not a MAC: two issued pairs recover the state and let anyone mint codes without extracting anything. What it protects is access to a *free public beta listing*. It is also **dormant**: all three device jungles build against `source-nopepper/`, so no pepper ships today | Nothing, while it is dormant. If it is ever re-armed, HMAC-SHA-256 truncated — and even then it gates a free download | — | accepted |
| **F-22** | Info | files on disk | app container | No explicit `NSFileProtection` class is set on the library database or the session archive, so both take the iOS default (`CompleteUntilFirstUserAuthentication`). Reasonable; worth a deliberate decision rather than a default, since the archive is every place the rider has been | Consider `.completeUnlessOpen` on the archive | S | backlog |

### What was checked and found sound

Recorded because a threat model that lists only problems reads as if nothing was examined.

- **The Connect IQ inbound path.** `ConnectIQCompanionLink.receivedMessage` is the only entry
  point; `CompanionSummary.init(payload:)` range-checks all 22 fields, `DirectPage.init`
  caps the payload at 8000 B, and `DirectStreamDecoder.decode` bounds every read and uses
  `&+`/`&*` for its accumulators. No `as!`, no force-unwrap, no attacker-sized allocation.
- **Outbound phone → watch** carries no credential: a wind integer, a map snapshot of the
  rider's own spot, and ACK integers — and only to a UUID from the app's own three app-ids.
- **The Garmin app** makes **no** `makeWebRequest`; there is no URL anywhere under `garmin/`.
  It type-checks every phone message and clamps every settings property.
- **FIT developer fields** already close both traps: `Int(clamped:)` and a finiteness
  rejection, with field offsets bounded by `FitStreamWalker`'s own invariant.
- **Strava OAuth** checks `state` before accepting a code (`StravaOAuth.parseCallback`), asks
  for one scope, checks it got it, and writes back a rotated refresh token.
- **Web DOM XSS**: 83 `innerHTML` sites traced. Every untrusted source — Strava and icu
  titles, Nominatim names, typed spot and gear names, filenames, FIT string fields, restored
  backups, engine errors — reaches HTML through `esc()`. SVG text goes through `textContent`.
  No `eval`, no `new Function`, no `document.write`, no `srcdoc`, no `javascript:`, no
  `target="_blank"` without `rel`, no origin-less `postMessage` handler.
- **The PWA share target** parks the shared file in a cache, redirects, and never sends it
  anywhere.
- **Dependency pinning** is good: `Package.resolved` committed with exact revisions,
  `uv.lock` with 1294 hashes and CI running `--locked`, and Pyodide pinned. FitFileParser was
  a vendored copy from 20 to 22 September 2026, for the one-word fix that stops a valid FIT
  trapping inside the decoder; the fix is upstream now (roznet/FitFileParser#15) and the
  dependency is a `.revision(…)` on the merge commit, because the newest release predates it
  by three years. A revision pin is a pin: `Package.resolved` records the same forty hex
  digits the manifest asks for.
- **No token is logged** anywhere — not in `FeedbackReport`, not in `CrashDigest`, not in the
  iCloud sync payload (recordings, `meta.json`, `tombstones.json`, and nothing else).

---

## What the rider gives away on purpose

Not vulnerabilities. The *curious co-rider* column of the threat model, so that each one is a
decision somebody made rather than a surprise.

- **The share card** draws the track and names the spot. Handing one to a WhatsApp group
  hands over where the rider rides and when he was there. That is the card's job; it is worth
  knowing that the picture is the disclosure, not the caption.
- **A `.cjw` or a library backup** handed to somebody is the whole recording at 1 Hz, times
  included.
- **The feedback mail** carries the phone model, the iOS version, the locale, the library
  shape and — where a session is attached — its date and spot. The file says so in its own
  header; it is rider-initiated and iOS sends nothing until he taps Send.
- **Apple Health writes** and the **iCloud container** (beta/dev) stay inside the rider's own
  Apple account.

---

## The proposed CSP

Drafted against the origins the pages genuinely use. **Not applied** — it needs the two
inline scripts extracted first, and `'wasm-unsafe-eval'` verified against Pyodide on a real
device. `frame-ancestors` is ignored in a meta tag and GitHub Pages cannot set a header, so
clickjacking stays unaddressed by this route.

```
default-src 'none';
script-src 'self' 'wasm-unsafe-eval' https://cdn.jsdelivr.net https://cloud.umami.is;
worker-src 'self' blob:;
style-src 'self' 'unsafe-inline';
img-src 'self' data: blob: https://tile.openstreetmap.org;
font-src 'self';
connect-src 'self' blob: https://cdn.jsdelivr.net https://pypi.org
            https://files.pythonhosted.org https://intervals.icu
            https://nominatim.openstreetmap.org https://cloud.umami.is;
manifest-src 'self'; base-uri 'none'; form-action 'none';
object-src 'none'; frame-src 'none'
```

`style-src 'unsafe-inline'` is forced by JS-generated `style="…"` attributes in `render.js`,
`icu.js` and `turnpage.js`. If F-02 lands, drop `pypi.org` and `files.pythonhosted.org`; if
Pyodide is self-hosted too, drop `cdn.jsdelivr.net` and `script-src` becomes `'self'`.

---

## The three things only Jan can do

Everything else in the backlog is code. These are not.

1. **Decide what the intervals.icu key is worth in a browser** (F-07). It is a full-account,
   non-expiring, read-write credential sitting in `localStorage`, and *no* browser storage
   keeps it from a script in the origin. Either the web app stops asking for it, or
   `/privacy/` says plainly where it is kept. He holds the key and the decision.
2. **Own the Strava client secret** (F-04). It ships in every IPA and always will, because
   Strava offers no PKCE. He is the one who can rotate it in the Strava dashboard, watch the
   athlete cap for abuse, and decide whether that is acceptable — it probably is, at this
   size, once it is written down rather than assumed.
3. **Turn on the repository settings that code cannot** — branch protection on `main` (the
   engineering audit already notes it is unprotected), the Dependabot config if he wants the
   PRs (F-10), and a `SECURITY.md` with a contact address, because a public repo with no
   reporting route gets its bugs reported in public.
