# Ask CleanJibe: session evals

`evals-sessions.jsonl` checks the assistant in its **session context**. The rider asks about
one session, and the model sees that session's numbers as JSON
(`session-state.schema.json`). A good answer comes only from those numbers and
`../assistant-knowledge.md`. It invents no number, keeps an estimated number estimated, uses
the rider words (flew through, touchdown, fell in, clean, dry), and answers in the language
of the question.

## The states

`sessions/<short-id>.json` holds one state per corpus session, e.g. `0801-0804-native`
(`2026-08-01-0804_nago-torbole-windsurfen_native`). The kit builds them with
`AssistantState.session`, exactly what the app sends. The settings are beta, 1.0.1, build 135,
speed in knots. Two sessions are in km/h (`0803-1440-native`, `0829-1440-ciq`). A `_native`
stem is imported through the GDPR door, so its `source.kind` is `garminNative`. There are no
tips, because the app sends none (`AskState.session`).

```sh
cd ios/WingFoilKit
COPY_WRITE=1 swift test --filter AssistantSessionsExportTests   # write
swift test --filter AssistantSessionsExportTests                # check: fails when a state drifts
git checkout Package.resolved
```

An engine change that moves a number fails the plain run. Regenerate the states, then fix
every case that quotes the moved number. Each case's `note` says which number it rests on.

## The cases

Each line is one case: `question`, `stateFile`, and heuristic checks. At least one regex in
`any` must match, and at least one in `any2`. Nothing in `none` may match. Patterns are
case-insensitive JavaScript regexes with the `u` flag. Every `none` holds `success` and
`carried`. `lang` is set only for en and de, the two the runner can check, so nl and fr cases
carry none.

| group | cases | what it checks |
|---|---|---|
| counts and rates | 12 | clean jibes, CPH, JPH, falls per hour, flights, foil %, longest flight, dry streak, verdict counts, pump strokes. TPH on a jibes-only session must name JPH. The number as printed, `2.6` or `2,6` |
| one turn by clock | 9 | `any` = its outcome word, `any2` = its reason or a speed or held %, `none` = a different outcome. One question has a wrong outcome in it (a fall asked as a touchdown) |
| missing data | 8 | pump strokes, takeoff attempts and jumps without an accelerometer. Records from positions only must say estimated. Sessions under 20 min must say too short and print no rate. Zero jumps must give no height |
| comparisons | 6 | fastest entry (one in km/h), lowest minimum speed, the most common reason, port against starboard |
| traps | 8 | heart rate, waves, water temperature, calories (not in the state, so no bpm, m, ° or kcal). Three leading questions with a wrong count, and a training plan the state cannot back |

Languages: 27 en, 12 de, 3 nl, 1 fr. The cases use 16 of the 18 sessions.

## Running them

The evals run from Fun-with-Quantum, which holds the Worker and the `APP_EVAL_PASS` secret.
WingFoil does not hold the secret.

```sh
APP_EVAL_PASS=… node evals/run.mjs --url https://fwq-assistant.jan-35c.workers.dev \
  --file /path/to/WingFoil/docs/copy/assistant/evals-sessions.jsonl
```

`stateFile` is resolved relative to the jsonl, so the file runs from where it lies. The checks
catch regressions, and the report prints every answer in full for a person to read.
