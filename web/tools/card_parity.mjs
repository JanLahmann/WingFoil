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
 *   complete   `cardStats(document, "complete")`
 *   lean       `cardStats(document, "lean")`
 *
 * Run from the repo root, with the PRESENTATION goldens as arguments — the browser
 * draws the document they carry and derives nothing:
 *
 *     node web/tools/card_parity.mjs fixtures/presentation/*.expected.json
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
const { HERO_ORDER, PERIOD_LEAN_KEYS, cardStats, cardStory, periodCardStats,
        periodMapAvailable } = await import(new URL("cardstats.js", JS).href);
const { stackPlacer, storyBoxes } = await import(new URL("sharecard.js", JS).href);
const { captionText } = await import(new URL("presentation.js", JS).href);

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

/* The **session card**, from the presentation goldens: the browser draws the document and
 * nothing else now, so what is dumped is what it made of one. `file` is still the analysis
 * golden beside it, because that is what the verifier's own re-derivation reads. */
const out = [];
for (const path of process.argv.slice(2)) {
  const facts = JSON.parse(readFileSync(path, "utf8"));
  const document = facts.document;
  const pair = (e) => ({ key: e.key, label: normalize(e.label), value: normalize(e.value),
                         tally: e.tally ?? null });
  out.push({
    file: `fixtures/goldens/${path.split("/").pop()}`,
    block: parseBlock(keyMetrics(document)),
    complete: cardStats(document, "complete").map(pair),
    lean: cardStats(document, "lean").map(pair),
    leanKeys: [...document.card.leanKeys].sort(),
    // Layout B v2 (26 Sep 2026): the story for every hero the rider can pick — the fixture
    // fixtures/cards/stories.expected.json pins it, and the kit's DocumentRendererTests hold
    // `ShareCardStats.Story.make` to the same file — and the gap between the words and the
    // footer on every shape, which the old tile grid ran past on the landscape.
    stories: Object.fromEntries(HERO_ORDER.map((hero) => [hero, cardStory(document, hero)])),
    footerGaps: Object.fromEntries(["portrait", "square", "landscape"].map((shape) => {
      const story = cardStory(document, "clean", { speedNote: "x" });
      const size = { portrait: [360, 450], square: [360, 360], landscape: [640, 360] }[shape];
      const boxes = storyBoxes({ story, track: null, note: null }, shape, size[0], size[1]);
      return [shape, Math.round(boxes.gap * 100) / 100];
    })),
    // The "wrist under" callout, in the words the web puts on screen. Both halves are copy
    // **ids with arguments** in the document now, so this dumps the resolver's answer —
    // the one sentence, printed by the one renderer (docs/presentation/layers-map-colour-type.md, "Wrist under").
    wristUnder: document.splash.marks.map((mark) => ({
      ts: mark.ts,
      title: captionText(mark.title),
      during: captionText(mark.during),
    })),
  });
}
process.stdout.write(JSON.stringify({
  cards: out,
  periods,
  periodLeanKeys: [...PERIOD_LEAN_KEYS],
  stacks,
}));
