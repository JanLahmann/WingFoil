# Logo audit — every surface, every channel

**Status:** audit run 25 September 2026 (Jan, 24 Sep: "release = the normal logo, beta = the
logo with the red strip, dev = the MIRRORED logo"). The rule itself is `docs/channels.md`,
"Telling the channels apart" — this file is the verification pass over every surface that
rule touches, plus the surfaces it deliberately does not.

**Method:** every asset below was opened and read pixel-for-pixel (not just its file name).
Where a channel's assets are machine-generated from a master, they were also **regenerated**
from `brand/tools/make_channel_marks.py` and `garmin/tools/make_brand_mark.py` into a scratch
copy and diffed byte-for-byte against the committed files — `diff -rq` came back empty on
every one of `brand/`, `ios/WingFoil/Resources/Assets.xcassets`,
`ios/WingFoilWatch/Resources/Assets.xcassets`, and all six `garmin/resources*` trees. **No
mismatch was found anywhere in the repo.** Nothing was changed; there was nothing to fix.

## The table

| surface | channel | expected | actual | verdict |
|---|---|---|---|---|
| iOS `AppIcon.appiconset` | release | mark as drawn | mark as drawn | match |
| iOS `AppIcon-Beta.appiconset` | beta | red BETA label, upper right | red BETA label, upper right | match |
| iOS `AppIcon-Dev.appiconset` | dev | mirrored, wing upper right | mirrored, wing upper right | match |
| iOS `SplashMark.imageset` (@1x/2x/3x) | release | mark as drawn | mark as drawn | match |
| iOS `SplashMark-Beta.imageset` | beta | red BETA label | red BETA label | match |
| iOS `SplashMark-Dev.imageset` | dev | mirrored | mirrored | match |
| iOS `LaunchMark.imageset` | release | mark as drawn | mark as drawn | match |
| iOS `LaunchMark-Beta.imageset` | beta | red BETA label | red BETA label | match |
| iOS `LaunchMark-Dev.imageset` | dev | mirrored | mirrored | match |
| iOS welcome page + splash (`ChannelArt.swift` → `splashMark`) | all three | picks `SplashMark[-Beta/-Dev]` under `#if DEV` / `#if BETA` | wired correctly, matches `project.yml`'s `ASSETCATALOG_COMPILER_APPICON_NAME` / `CJ_SPLASH_MARK` per scheme | match |
| watchOS `AppIcon.appiconset` (WingFoilWatch) | release | mark as drawn | mark as drawn | match |
| watchOS `AppIcon-Beta.appiconset` | beta | red BETA label (moved inward for the circular mask) | red BETA label, inset | match |
| watchOS `AppIcon-Dev.appiconset` | dev | mirrored | mirrored | match |
| watchOS `BrandMark.imageset` (start page) | release | mark as drawn | mark as drawn | match |
| watchOS `BrandMark-Beta.imageset` | beta | red BETA label | red BETA label | match |
| watchOS `BrandMark-Dev.imageset` | dev | mirrored | mirrored | match |
| watchOS `ChannelArt.swift` (start page) | all three | same flags as the phone's | matches | match |
| watch complication `ComplicationMark.imageset` | all three | **not** in `docs/channels.md`'s list of places the treatment reaches; template-rendering (tinted by the watch face), one asset, no `-Beta`/`-Dev` variant, no channel compile flag on the `WingFoilWatchWidgets` target in `project.yml` | single asset, un-mirrored, un-badged, used by every channel | **not a mismatch — by design.** A red badge would be discarded by template tinting anyway; mirroring the shape *would* survive tinting and isn't done, but the contract doesn't ask for it here. Flagged for Jan's call, not changed. |
| Garmin launcher icon, all 4 native sizes (40/54/60/65) | release | mark as drawn | mark as drawn | match |
| Garmin launcher icon, all 4 sizes | beta | red BETA label (plain red block below 14 px label height, per `docs/channels.md`) | red BETA label / block | match |
| Garmin launcher icon, all 4 sizes | dev | mirrored | mirrored | match |
| Garmin `brand_mark` / `brand_hero` / `brand_badge`, all 4 sizes | release/beta/dev | same three treatments | same three treatments | match |
| `brand/icon-square-1024.png`, `icon-tile-1024.png` (release masters) | release | mark as drawn | mark as drawn | match |
| `brand/icon-square-beta-1024.png`, `icon-tile-beta-1024.png`, `icon-square-beta.svg` | beta | red BETA label | red BETA label | match |
| `brand/icon-square-dev-1024.png`, `icon-tile-dev-1024.png`, `icon-square-dev.svg` | dev | mirrored | mirrored | match |
| `web/icons/icon.svg`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`, `icon-maskable-512.png` | web has one channel only | release mark everywhere | release mark everywhere, every page (`web/index.html`, `/help`, `/learn`, `/whats-new`, `/privacy`, `/start`, `/invite`, `/impressum`, `/watches`, `/app`) links the same `icons/` set | match |
| `web/app/index.html` inline favicon (base64 PNG, `brand/icon-tile-64.png`) | web | release mark | release mark | match |
| Share card, its QR centre, replay clip cards | all three | release mark always, per `docs/channels.md` ("does not change with the channel") | not touched by this audit (no card-rendering code carries a channel flag) | match by design |
| `garmin/store/cover-500.png` (public "Beta" listing cover, live today) | — | not one of `docs/channels.md`'s listed places; archival/transcribed store asset | release-style mark, no BETA label | **not a mismatch** — the store cover isn't in the channel-mark contract, and `garmin/store/listing.md` says this file is a transcription of the live store, edited only when the store itself is edited. Not changed. |
| `garmin/store/cover-500-beta.png` (cut 26 Sep 2026, not yet uploaded) | — | the public listing *is* the beta stream, so its cover should carry the same red-strip BETA mark the beta app icon wears | `brand/icon-tile-beta-1024.png` (`brand/tools/make_channel_marks.py`'s output, already the beta app icon's own mark) resized to 500×500, no new art | **added, matches the beta app icon exactly.** `cover-500.png` is kept alongside, unchanged, since uploading is a separate step (`garmin/store/listing.md`, "Listing images") and not part of this pass. |
| `brand/cover-500-private.png` (dev-beta / private CIQ listings cover) | — | documented divergence: "the current mark with the red PRIVATE ribbon" (`garmin/store/listing.md`) | mark with a diagonal red PRIVATE ribbon | match to its own (separate) rule |
| App Store Connect icon (release/beta build) | release / beta | pulled from the uploaded build's `AppIcon`/`AppIcon-Beta` | — | **check in the store** — not visible from the repo |
| TestFlight listing icon (dev build) | dev | pulled from `AppIcon-Dev` | — | **check in the store** — not visible from the repo |
| Connect IQ live store page — public beta listing (`apps.garmin.com/apps/e77867b5-…`) | beta | per `docs/channels.md` | — | **check in the store** |
| Connect IQ live store page — dev-beta private listing (`apps.garmin.com/apps/8f4efc35-…`) | dev-private | red PRIVATE ribbon per `garmin/store/listing.md` | — | **check in the store** |
| Connect IQ release public listing | release | none exists yet (`b1ef484c…` "has no store listing yet") | — | n/a |

## What this confirms

- Every generated asset in the repo — iOS (phone + watch + app icons + splash/launch marks),
  Garmin (launcher icons and the three ink-only cuts, at all four native sizes), and the
  `brand/` reference masters — is bit-identical to what
  `brand/tools/make_channel_marks.py` and `garmin/tools/make_brand_mark.py` produce from the
  current release artwork today. There is no drift between the masters and any committed cut.
- The web site is single-channel and carries only the release mark, consistently, on every
  page.
- Two things look like they *could* be mismatches and are not, because they sit outside
  `docs/channels.md`'s list on purpose: the watch complication (tinted, un-mirrored,
  un-badged — no channel compile flag wired for it at all) and the two Garmin store-listing
  cover images (their own, separately documented, ribbon/plain treatment).
- Nothing was fixed because nothing was broken. No iOS asset changed, so no iOS build was run
  for this audit.
