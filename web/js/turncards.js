/* The Turns tab's cards and its tally — the phone's own two blocks, ported.
 *
 * The iPhone's Turns tab reads top to bottom: **a card per turn**, then the tally over the
 * turns the filter left, then the map, then the list (docs/screens.md, Sessions · Turns).
 * The browser had the list alone, as a seventeen-column table, so the one thing a rider
 * actually scrolls a Turns tab for — "which jibe was that, and how did it end" — was the
 * narrowest cell on the widest table on the page.
 *
 * **Every fact on a card is the presentation document's** (`turns.strip`, ADR-033): the
 * ordinal, the outcome, the entry tack, the score, the clean flag and the reason a turn
 * ended the way it did. Nothing here derives one. The four columns the strip does not
 * carry — the arc, the radius, the two workbench flags — stay in the table below, which is
 * where the workbench numbers live.
 *
 * A card opens the turn page, the same dialog a table row opens (js/turnpage.js). The
 * chips on Track filter the cards and the tally exactly as they filter the rows
 * (js/session.js, `applyTurnFilter`), because a chip that hid a row and left a card is two
 * answers to one question.
 */

import { OUTCOME_COLOR, OUTCOME_LABEL, SVGNS, clockAt, esc, marker, nf, outcomeText, pct }
  from "./viz.js";

/** What the engine calls a sweep, and what a rider calls it. A course change keeps the
 *  detector's own two words: it is the thing the summary excluded, and saying "turn" over
 *  it would be the taxonomy fault pattern L is about. */
const TYPE_LABEL = {
  jibe: "Jibe", tack: "Tack", bear_away: "Bear-away", round_up: "Round-up",
};

const typeLabel = (type) => TYPE_LABEL[type] || String(type || "Turn");

/** The outcome shape and its word, the ladder's own — the same `marker()` the map draws,
 *  so a card and a dot cannot wear two encodings of one verdict. */
function outcomePill(outcome) {
  const holder = document.createElementNS(SVGNS, "svg");
  holder.setAttribute("viewBox", "-6 -6 12 12");
  const shape = { flew_through: "disc", touchdown: "triangle",
                  fell_in: "cross" }[outcome] || "square";
  marker(holder, { shape, color: OUTCOME_COLOR[outcome] || "currentColor" }, 0, 0, 0.85);
  return `<span class="pill ${esc(outcome)}">${holder.outerHTML}${
    esc(OUTCOME_LABEL[outcome] || outcome)}</span>`;
}

/**
 * One card per detected sweep, in the document's order.
 *
 * `hidden` is set by `applyTurnFilter` afterwards rather than here, for the reason the
 * table rows are hidden rather than removed: a card's `data-turn` is the turn's index and
 * the page behind it is read off that index.
 */
export function renderTurnCards(host, result, meta) {
  if (!host) return;
  const g = result.golden;
  const strip = result.presentation?.turns?.strip || [];
  const cfg = g.config || {};
  host.innerHTML = strip.map((e) => {
    const t = g.turns[e.index];
    if (!t) return "";
    const name = e.ordinal === null || e.ordinal === undefined
      ? typeLabel(t.type)
      : `${typeLabel(t.type)} ${e.ordinal}`;
    const why = outcomeText(t, cfg.turnPumpedMarginalSpeed, cfg.discipline) || "";
    // voice: skip — a strip of values, one per cell, in the spec register of docs/voice.md.
    const facts = [
      e.sideId ? `${e.sideId} entry` : null,
      // The score says what it is (F9f): the share of the entry speed the turn held.
      `${nf(e.score * 100, 0)} % held`,
      `min ${nf(e.minKn, 1)} of ${nf(e.entryKn, 1)}`,
    ].filter(Boolean).join(" · ");
    return `
      <button type="button" class="turn-card" data-turn="${e.index}">
        <span class="tc-head">
          <span class="tc-name">${esc(name)}</span>
          <span class="tc-time">${esc(clockAt(meta, e.ts))}</span>
        </span>
        <span class="tc-verdict">${outcomePill(t.outcome)}${
          e.clean ? '<span class="pill clean">clean</span>' : ""}${
          e.counted ? "" : '<span class="pill">not counted</span>'}${
          e.borderline ? '<span class="pill">borderline</span>' : ""}</span>
        <span class="tc-facts">${esc(facts)}</span>
        ${why ? `<span class="tc-why">${esc(why)}</span>` : ""}
      </button>`;
  }).join("");
}

/**
 * The tally over the turns the chips left, in the phone's own shape
 * (`TurnsAnalysisView.tallyStrip`): the flew-through share, what it is out of, the clean
 * count beside it, and one chip per rung of the ladder.
 *
 * **Counted turns only**, as on the phone: the `counted` gate is unconditional there, so a
 * bear-away the detector rejected is not in the denominator here either.
 *
 * `visible(index)` is `js/session.js`'s own question, handed in rather than re-derived —
 * the chips decide once, and the map, the strip, the cards, this block and the table all
 * read that one decision.
 */
export function renderTurnTally(host, result, visible) {
  if (!host) return;
  const g = result.golden;
  const strip = result.presentation?.turns?.strip || [];
  const kept = strip.filter((e) => e.counted && visible(e.index));
  const total = kept.length;
  const all = strip.filter((e) => e.counted).length;
  if (!all) { host.innerHTML = ""; host.hidden = true; return; }
  host.hidden = false;

  const count = (id) => kept.filter((e) => e.outcomeId === id).length;
  const jibes = kept.filter((e) => (g.turns[e.index] || {}).type === "jibe").length;
  const clean = kept.filter((e) => e.clean).length;
  const flew = count("flewThrough");
  const share = total ? pct(100 * flew / total) : "—";
  const of = total === all
    ? `${flew} of ${total} counted turns`
    : `${flew} of ${total} turns, ${all - total} hidden by the chips`;
  // voice: skip — the tally is a row of counts with its word beside each, the spec register.
  const chips = [["flewThrough", "flew_through"], ["touchdown", "touchdown"],
                 ["fellIn", "fell_in"]]
    .map(([id, outcome]) => `<span class="tt-chip">${outcomePill(outcome)}
      <span class="tt-n">${count(id)}</span></span>`).join("");
  host.innerHTML = `
    <div class="tt-head">
      <span class="tt-pct">${esc(share)}</span>
      <span class="tt-words">
        <span class="tt-label">flew through</span>
        <span class="tt-sub">${esc(total ? of : "nothing matches these chips")}</span>
        ${jibes ? `<span class="tt-clean">${clean} of ${jibes} clean</span>` : ""}
      </span>
    </div>
    <div class="tt-chips">${chips}</div>`;
}
