/* The share card's stat list, and the key-metrics block it has to equal — dumped as JSON
 * for `verify_presentation.py` §5 to assert against.
 *
 * The card is the one artefact of this project that leaves the device and is read next to
 * nothing, so it is the last place the app may name a different number for the same
 * session than the block at the top of the page does. `js/cardstats.js` makes that
 * structurally true (one list, two readers), and this is what proves it stayed true:
 *
 *   block      the rendered `keyMetrics` HTML, parsed back into {label, value} pairs —
 *              the actual markup the page puts on screen, not the array behind it
 *   complete   `cardStats(g, "complete")`
 *   lean       `cardStats(g, "lean")`
 *
 * Run from the repo root, with the analysis goldens as arguments:
 *
 *     node web/tools/card_parity.mjs fixtures/goldens/*.expected.json
 *
 * The browser modules are ES modules written for a page; two of them touch `window` at
 * import time (js/session.js installs the map's pointer-move listener), so the driver
 * stubs the one method that is called. Nothing below draws anything: `keyMetrics` returns
 * a string and `cardStats` returns an array, which is exactly why the *content* half of a
 * card is testable while the drawing half is not.
 */

import { readFileSync } from "node:fs";

globalThis.window = { addEventListener() {} };

const JS = new URL("../js/", import.meta.url);
const { keyMetrics } = await import(new URL("render.js", JS).href);
const { LEAN_KEYS, PERIOD_LEAN_KEYS, cardStats, keyMetricEntries, periodCardStats,
        periodMapAvailable } = await import(new URL("cardstats.js", JS).href);
const { stackPlacer } = await import(new URL("sharecard.js", JS).href);
const { submersionDuring, submersionTitle } = await import(new URL("session.js", JS).href);

/**
 * The block's cells, in order, as the page actually prints them.
 *
 * The tally cell's three counts are separate elements with the separators drawn by CSS
 * margins (`.tally i { margin: 0 5px }`), so its text content has no spaces in it where
 * the reader sees spaces. Normalizing both sides around the middot compares what is on
 * screen rather than what is in the markup — the only whitespace either side of it is
 * presentation.
 */
function parseBlock(html) {
  const cells = [];
  const re = /<div class="key(?: hero)?"><div class="v">([\s\S]*?)<\/div>\s*<div class="k">([\s\S]*?)<\/div><\/div>/g;
  for (const m of html.matchAll(re)) {
    cells.push({ value: normalize(strip(m[1])), label: normalize(strip(m[2])) });
  }
  return cells;
}

const strip = (s) => s.replace(/<[^>]*>/g, "");
const normalize = (s) => s.replace(/\s*·\s*/g, " · ").trim();

/* The **period** card, from the shared fixture rather than from an analysis golden: a
 * period is a set of afternoons, so the thing to dump is what `library.periods` made of ten
 * of them and what the card does with each one's block. Same two questions as above —
 * complete is the block, lean is a strict subset of it — asked of the second card kind. */
const periodsPath = new URL("../../fixtures/periods/periods.expected.json", import.meta.url);
const fixture = JSON.parse(readFileSync(periodsPath, "utf8"));
const periods = [];
for (const group of ["trips", "months", "seasons", "custom"]) {
  for (const period of fixture[group]) {
    periods.push({
      group,
      key: period.key,
      title: period.title,
      dateLine: period.dateLine,
      block: period.block.map((e) => ({ key: e.key, label: e.label, value: e.value })),
      complete: periodCardStats(period, "complete"),
      lean: periodCardStats(period, "lean"),
      // Whether the composer offers a ground under this period at all. The rule itself is
      // `library._map_ground`'s; what is dumped here is that the browser reads it and does
      // not invent a second one.
      mapOffered: periodMapAvailable(period),
      mapGround: period.mapGround ?? null,
    });
  }
}

/* The **artwork**, from a second shared fixture: a set of outlines in metres, a box, and where
 * `stackPlacer` puts every vertex. The one thing that makes a stack a picture rather than a
 * scribble is that all of them share a metres scale, and the one thing that makes it the *same*
 * picture on both platforms is that `TrackStack.placement` in the kit agrees with this. */
const outlinesPath = new URL("../../fixtures/periods/outlines.expected.json",
                             import.meta.url);
const outlines = JSON.parse(readFileSync(outlinesPath, "utf8"));
const round6 = (v) => Number(v.toFixed(6));
const stacks = outlines.cases.map((c) => {
  // The shape `drawTrackStack` reads: one run per track, no marks — the stack draws none.
  const tracks = c.tracks.map((pts) => ({ runs: [{ flying: true, pts }], marks: [] }));
  const placer = stackPlacer(tracks, c.box);
  return {
    name: c.name,
    scale: placer === null ? null : Number(placer.scale.toFixed(9)),
    centreX: placer === null ? null : round6(placer.centreX),
    centreY: placer === null ? null : round6(placer.centreY),
    placed: placer === null ? null : c.tracks.map(
      (pts) => pts.map(([x, y]) => {
        const p = placer.place(x, y);
        return [round6(p.x), round6(p.y)];
      })),
  };
});

/* The **rate row**, over the three shapes of session the corpus does not happen to contain.
 *
 * Row 4 has one branch the goldens cannot exercise: an afternoon whose wind axis named
 * jibes and who swam out of every one of them. Its `jibesPerHour` is 0.0 beside a positive
 * TPH, which is what the old `jibesPerHour > 0` gate read as "no jibes were named" — so the
 * block dropped JPH *and* CPH and printed the TPH fallback, over a session that is nothing
 * but jibes. The contract says the opposite (docs/presentation.md, "Row 4": "Where jibes
 * were named, a `0.0` CPH is a measured verdict and is printed as one"), so the case is
 * written down here rather than waited for. `verify_presentation.py` §5a says which keys
 * each one must produce.
 *
 * Synthetic and minimal: only the fields `keyMetricEntries` reads, and only the ones the
 * rate row's branch turns on. Nothing here is a claim about a real recording.
 */
const rateCase = (name, { jibes, turnsCounted, jibesPerHour, turnsPerHour,
                          cleanJibesPerHour, wetPerHour }) => ({
  name,
  entries: keyMetricEntries({
    summary: {
      durationS: 3600, distanceKm: 12.0, avgSpeedKmh: 12.0,
      jibesPerHour, turnsPerHour, cleanJibesPerHour, wetPerHour,
      turns: {
        jibes, turnsCounted, jibesSuccessful: 0, turnsSuccessful: 0,
        longestFlewStreak: 0, longestDryStreak: 0,
        jibeOutcomes: { flewThrough: 0, touchdown: 0, fellIn: jibes },
        outcomes: { flewThrough: 0, touchdown: 0, fellIn: turnsCounted },
      },
    },
    records: { best2sKn: 14.0, best5x10sKn: 12.0, alpha500Kn: 0.0 },
  }).map((e) => ({ key: e.key, value: e.value })),
});

const rates = [
  // Fifteen jibes, every one of them swum. JPH 0.0 and CPH 0.0 are both measured.
  rateCase("allWetJibes", {
    jibes: 15, turnsCounted: 15, jibesPerHour: 0.0, turnsPerHour: 15.0,
    cleanJibesPerHour: 0.0, wetPerHour: 15.0,
  }),
  // No usable wind axis: turns, and none of them named. TPH, and no jibe rate at all.
  rateCase("noJibesNamed", {
    jibes: 0, turnsCounted: 15, jibesPerHour: 0.0, turnsPerHour: 15.0,
    cleanJibesPerHour: 0.0, wetPerHour: 2.0,
  }),
  // An hour on the water with no turns in it: measured zeroes, not a fallback.
  rateCase("noTurnsAtAll", {
    jibes: 0, turnsCounted: 0, jibesPerHour: 0.0, turnsPerHour: 0.0,
    cleanJibesPerHour: 0.0, wetPerHour: 0.0,
  }),
];

const out = [];
for (const path of process.argv.slice(2)) {
  const g = JSON.parse(readFileSync(path, "utf8"));
  const pair = (e) => ({ key: e.key, label: normalize(e.label), value: normalize(e.value),
                         tally: e.tally ?? null });
  out.push({
    file: path,
    block: parseBlock(keyMetrics(g)),
    complete: cardStats(g, "complete").map(pair),
    lean: cardStats(g, "lean").map(pair),
    leanKeys: [...LEAN_KEYS].sort(),
    // The "wrist under" callout, in the words the web puts on screen — the same
    // two-implementations-of-one-sentence check the pairing lines get, for the layer
    // Jan asked for on 7 Sep 2026 (docs/presentation.md, "Wrist under").
    wristUnder: (g.submersions || []).map((sub) => ({
      ts: sub.ts,
      title: submersionTitle(sub),
      during: submersionDuring(sub, g),
    })),
  });
}
process.stdout.write(JSON.stringify({
  cards: out,
  rates,
  periods,
  periodLeanKeys: [...PERIOD_LEAN_KEYS],
  stacks,
}));
