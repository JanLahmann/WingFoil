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
const { LEAN_KEYS, PERIOD_LEAN_KEYS, cardStats, periodCardStats } =
  await import(new URL("cardstats.js", JS).href);

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
    });
  }
}

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
  });
}
process.stdout.write(JSON.stringify({
  cards: out,
  periods,
  periodLeanKeys: [...PERIOD_LEAN_KEYS],
}));
