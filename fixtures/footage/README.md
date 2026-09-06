# Footage fixtures

Video and photos of a session, for the highlight reel's alignment work (CleanJibe Pro §2.5,
GitHub issue #3). **The files are not in git** — a single afternoon is gigabytes — only this
README, the hashes and the ground truth are. Everything under `fixtures/footage/<session>/`
except `README.md` and `truth.json` is ignored.

## Layout

```
fixtures/footage/<fit-stem>/          e.g. 2026-08-05-0827_nago-torbole-windsurfen_native/
    README.md        camera(s), who filmed, where the slate is, anything odd
    truth.json       per file: sha256, camera, hand-verified offset_s, and for a few clips
                     the session-relative second of a visible event ("splash at 00:14 ↔ fell_in #7")
    *.mov *.mp4      the originals (ignored by git)
    *.heic *.jpg     stills (ignored by git)
```

Getting originals off an iPhone **without losing the clock**: Photos → select → Share →
AirDrop to the Mac (the Mac receives originals with `com.apple.quicktime.creationdate`
and its UTC offset intact), or Share → Options → "All Photos Data". Anything that went
through WhatsApp, Telegram or Mail has no usable clock; note it as such in `truth.json`.

## The protocol for a filmed afternoon

1. **Slate.** Before launching, film the watch's start screen for two seconds — the Garmin's
   clock page or the Apple Watch's seconds. That frame is the exact offset for that camera.
2. Film normally. GoPro HiLight tags (the button) are welcome; they become beats.
3. Afterwards, the rider notes two or three moments they remember: "the fall after the
   long run", "the clean jibe in front of the harbour" — the human labels for `truth.json`.

## Running the study

```
cd lab && uv run python tools/align_footage.py \
    ../fixtures/sessions/<class>/<fit-stem>.fit ../fixtures/footage/<fit-stem> \
    --offset-s 0 --json ../fixtures/footage/<fit-stem>/align.json
```

The tool places every clip on the session clock and prints the events the engine found in
its window. Verify three of them against the picture; if a splash in the video is at +14 s
and `fell_in` is at +9 s, the camera is five seconds fast — pass `--offset-s -5` and record
it in `truth.json`. Accept: iPhone originals within 1 s with no offset; a GoPro within 0.5 s
once the GPMF path (H3) exists; motion-only within 2 s.

Raw September 2026 recordings (Jan, intervals.icu originals, unscrubbed) live in
`_raw-2026-09/` here rather than under `fixtures/sessions/`, because `verify_library.py`
scans that folder and pins its counts to the tracked corpus. Ignored by git like the footage.
