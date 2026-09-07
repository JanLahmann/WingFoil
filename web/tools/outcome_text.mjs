/* The "why" line under a turn's outcome, dumped as JSON for `verify_presentation.py` §6.
 *
 * Every touchdown and every fall on a session page says which rung of the ladder decided it
 * (engine 0.18.0, `outcomeReason`), and the sentence is the same one the phone prints under
 * the turn's chips (`TurnAnalytics.outcomeText` in WingFoilKit). Two apps wording the same
 * fact differently is how a rider learns to trust one of them, so the string is asserted from
 * the outside rather than trusted to a comment — and it comes out of `js/viz.js` itself, so
 * this cannot pass against a copy of the rule that the browser does not run. Same spirit as
 * `clock_note.mjs` and `card_parity.mjs`.
 *
 * Run from the repo root, with the analysis goldens as arguments:
 *
 *     node web/tools/outcome_text.mjs fixtures/goldens/*.expected.json
 *
 * Prints `{ fixtures: [{file, texts: [string|null, …]}, …], cases: {name: string|null} }` —
 * one entry per turn in document order, plus the hand-made cases the corpus cannot supply
 * (the pump rung is unreachable at the published defaults, and a document from before 0.18.0
 * carries no reason at all).
 *
 * `js/session.js` installs a pointer-move listener at import time and `js/viz.js` is imported
 * by it, so `window` is stubbed the way the other harnesses stub it.
 */

import { readFileSync } from "node:fs";

globalThis.window = { addEventListener() {} };

const { outcomeText } = await import(new URL("../js/viz.js", import.meta.url).href);

const fixtures = process.argv.slice(2).map((file) => {
  const doc = JSON.parse(readFileSync(file, "utf-8"));
  const exit = (doc.config || {}).foilExitSpeed ?? null;
  return {
    file,
    texts: (doc.turns || []).map((t) => outcomeText(t, exit) ?? null),
  };
});

/** The shapes the seventeen fixtures cannot produce, written out by hand. */
const CASES = {
  // The pump rung, which no published-default run can reach any more — the wording has to
  // survive anyway, because a stored document written by an older engine still carries it.
  pumpedMarginal: [{ outcome: "touchdown", outcomeReason: "pumped_marginal",
                     borderline: false, offFoilS: 0, stoppedS: 0 }, 8],
  // …and the same turn out of a document whose config echo has no exit speed in it.
  pumpedMarginalNoConfig: [{ outcome: "touchdown", outcomeReason: "pumped_marginal",
                             borderline: false, offFoilS: 0, stoppedS: 0 }, null],
  // A touchdown whose stop rounds to zero: "no stop", never "stopped 0 s".
  offFoilNoStop: [{ outcome: "touchdown", outcomeReason: "off_foil",
                    borderline: false, offFoilS: 2, stoppedS: 0.4 }, 8],
  offFoilWithStop: [{ outcome: "touchdown", outcomeReason: "off_foil",
                      borderline: false, offFoilS: 2, stoppedS: 1.2 }, 8],
  borderline: [{ outcome: "touchdown", outcomeReason: "stop",
                 borderline: true, offFoilS: 6, stoppedS: 4 }, 8],
  fellInStopped: [{ outcome: "fell_in", outcomeReason: "stop",
                    borderline: false, offFoilS: 20, stoppedS: 7 }, 8],
  fellInSubmerged: [{ outcome: "fell_in", outcomeReason: "submerged",
                      borderline: false, offFoilS: 30, stoppedS: 12 }, 8],
  // A fly-through says nothing, and neither does a document from before the reason existed.
  flewThrough: [{ outcome: "flew_through", outcomeReason: null,
                  borderline: false, offFoilS: 0, stoppedS: 0 }, 8],
  preReason: [{ outcome: "touchdown", borderline: false, offFoilS: 2, stoppedS: 1 }, 8],
  // Half a second, on the rule both sides round by: away from zero, so 4.5 s is "5 s".
  halfSecond: [{ outcome: "fell_in", outcomeReason: "stop",
                 borderline: false, offFoilS: 9, stoppedS: 6.5 }, 8],
};

const cases = {};
for (const [name, [turn, exit]] of Object.entries(CASES)) {
  cases[name] = outcomeText(turn, exit) ?? null;
}

process.stdout.write(JSON.stringify({ fixtures, cases }));
