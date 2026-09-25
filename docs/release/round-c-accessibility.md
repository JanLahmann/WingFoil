# Release round C — accessibility (1.0.1)

26 Sep 2026. Goal: CleanJibe works with Dynamic Type up to the accessibility sizes,
VoiceOver reads every number with its word, and colour is never the only signal.
The rules this round adds are in `docs/presentation/layers-map-colour-type.md`
("Differentiate Without Color swaps the dot for the rung's glyph", and "Text size and
theme"). No rider-visible wording changed; every new string is a VoiceOver label.

## What was already right

The app arrived in good shape: every string sits in a text style, the dense rows cap at
`.accessibility2` (`denseRowTypeSizeCap()`), columns grow with `scaledColumn`, the key-metrics
block goes two to a line at accessibility sizes, the all-time records row and the filter bar
give the table up past the threshold, and the readable inks (`ReadableInk`) hold 4.5 : 1.
The turn list, the turn tally chips, the flights list, the summary grid's breakdowns and
the turn page's verdict chip all carry a glyph and a word beside the ladder's ink. The
session map's marks already had VoiceOver labels.

## Findings and fixes

| # | surface | finding | fix |
|---|---|---|---|
| 1 | Outcome tally (library row, key-metrics block, provisional page) | VoiceOver said "… touchdowns, … falls" — "falls" is not the rider word, and "1 touchdowns" | `SpokenFigures.tally`: "42 flew through, 3 touchdowns, 5 fell in", singular/plural |
| 2 | Key-metrics tally cell | tally and its caption were two VoiceOver stops, each half a thing | one element: numbers with words, then "Jibes — of 50 jibes" |
| 3 | Key-metrics tally, provisional tally | **colour only**: "63 · 1 · 6" in three inks, no word, no glyph | with Differentiate Without Color on, the words come back (`OutcomeTally`) |
| 4 | Session map outcome dots | **colour only**: green/orange/red circles, identical shapes | with Differentiate Without Color on, the rung's glyph (check / triangle / cross), outlined for straight-line ends (`OutcomeDot`) |
| 5 | Turns map pins | **colour only**, and hidden from VoiceOver although they are buttons | glyph under Differentiate Without Color (`TurnPinDot`); label "Jibe at 14:03, flew through, clean", button trait, hint |
| 6 | Map legend chips | dot swatch must look like the mark it toggles | swatch follows the same setting |
| 7 | Trend charts (every `TrendChart`, entry-tack chart, sessions per week) | Swift Charts' default walks every mark, sixty dates in a row | one sentence each: "On foil, 12 sessions, latest 64 %, lowest 40 %, highest 72 %" (`SpokenFigures.series`) |
| 8 | Session speed chart | no summary | "Speed chart, 0:00 to 1:42:10, highest 27.3 kn" |
| 9 | Records → Session records rows | name and "when · where" were `lineLimit(1)` with a 0.8 shrink: an ellipsis at AX3 | past the threshold both wrap, and the value drops under the name when the two no longer share a line (`ViewThatFits`) |

Colour-only audit, the rest (no change needed): turn rows (glyph), turn tally chips
(glyph + word), flights list (glyph + word), summary-grid breakdowns (glyph + word), turn
page verdict chip (glyph + word), failed takeoff (u-turn shape + hollow), clean jibe (star
shape), entry-tack pair (dash), record delta (the "+" sign), library row tally (words
always on). The turn page's own map draws one end dot beside a verdict chip that says it
in words; the replay scrubber's beat ticks are chrome under a labelled play head and each
beat is announced by name.

## Screenshots

AX3 (`UI_TEXT_SIZE=ax3`), one per main screen, in the round's scratchpad folder `rel-c/`:
`list-ax3.png`, `session-ax3.png`, `records-ax3.png`, `trends-ax3.png` — see the round
report for which of them could be taken (the machine was under heavy load).

## What remains

- **Colour-only by default.** Items 3–6 are fixed under the system's Differentiate Without
  Color setting, which is the platform's contract. With it off, the key-metrics tally and
  the map dots still rely on ink (the caption says "of 57 jibes", the legend names each
  ink). Turning the words on in the block, or glyphs on the map, for everyone is a design
  decision for Jan, not an accessibility bug.
- **The web** has not had this pass: its tally, map dots and charts are the same shape.
- **VoiceOver on the turn page's strips** already speaks a summary per strip; not re-audited.
- **Settings and the Form screens** scale with the system and were not changed.
