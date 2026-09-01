/* Rendering: the summary tiles and the tables, plus the one call that draws the two
 * interactive figures.
 *
 * The figures (track map + speed strip, the shared playhead, the legend chips, the zoom
 * and the popovers) live in js/session.js; the drawing primitives they and the trend
 * charts share live in js/viz.js. This file owns the report around them: identity, tiles,
 * takeoffs, turns, flight ends.
 *
 * The shared encoding, which the figures and the tables all obey:
 *
 *   line colour   off-foil = recessive grey, foiling = series-1 blue
 *   marker SHAPE  carries the outcome (disc / triangle / heavy X / hairline x / hollow square)
 *   marker colour only reinforces it — the status ramp fails a CVD check on its own
 *   marker number is the turn's row number in the Turns table
 */

import { keyMetricEntries } from "./cardstats.js";
import { renderFigures } from "./session.js";
import { C, OUTCOME_COLOR, OUTCOME_LABEL, SVGNS, clockAt, esc, hms, int, marker, nf,
         sessionDate } from "./viz.js";

// Re-exported so the rest of the app keeps one import site for the shared helpers; the
// split into viz.js is an internal arrangement of the rendering layer.
export { C, clockAt, esc, figureWidth, hideTip, hms, int, isNarrow, nf, sessionDate,
         showTip, svg, zonedFormat } from "./viz.js";
// `renderFigures` travels with them because js/sections.js needs the figures redrawn on
// their own, without the two long tables being rebuilt for nothing (see wireSections).
export { clearPlayhead, closePopover, renderFigures, resetSession } from "./session.js";

const el = (id) => document.getElementById(id);

/* ---------------------------------------------------------------- the report */

/**
 * Draw the whole report.
 *
 * `highlight` (optional) is a record's own provenance, straight out of the analysis
 * document's `records.windows` — `{label, value, unit, windows: [{startTs, durS}, …]}`.
 * When it is present the map and the speed strip mark exactly those windows. It is an
 * annotation on data already in the document: nothing about it is recomputed here.
 */
export function render(result, { highlight = null, isExample = false } = {}) {
  const g = result.golden, v = result.view, meta = result.meta;
  renderSummary(result, isExample);
  renderFigures(result, highlight);
  renderTakeoffs(el("takeoff-body"), g, meta);
  renderTurns(el("turns-table"), el("turns-caption"), g, v, meta);
  renderEnds(el("ends-table"), el("ends-caption"), g, meta);
}

/* --------------------------------------------------------------- key metrics */

/**
 * The KEY METRICS block, and the JavaScript half of `KeyMetrics.swift`.
 *
 * Four rows, numbers big and labels small, before the tiles and the figures:
 *
 *   1  duration (h:mm) · distance · average speed
 *   2  the best 2 s record, labelled with the window it is
 *   3  the outcome ladder's three counts on the ladder's own inks, plus the two turn
 *      streaks the engine has computed since 0.4.0 and neither app ever drew
 *   4  JPH (or TPH) and WPH — the per-hour rates, JPH over *dry* jibes since 0.7.0
 *
 * **This function is now layout only.** Every rule the two platforms have to agree on —
 * which entries exist, in what order, with which labels and which strings — moved to
 * `keyMetricEntries` in js/cardstats.js when the share card arrived, because the card has
 * to print *this* list and a second implementation of it would be a second answer to "was
 * that a good session" travelling in a picture. The Swift twin is pinned by
 * `PresentationTests.keyMetrics*`; the block-against-card equality is pinned by
 * `web/tools/verify_presentation.py` §5. A difference anywhere in that triangle is a bug.
 */
export function keyMetrics(g) {
  const cell = (e) => {
    // The tally is the one cell that is not a string: its three counts are drawn on the
    // verdict ladder's own inks. `e.value` spells the same three numbers, so a renderer
    // that ignores `e.tally` still prints the truth — it just prints it in one colour.
    const v = e.tally
      ? `<span class="tally"><span class="flew">${int(e.tally.flewThrough)}</span>` +
        `<i>·</i><span class="touchdown">${int(e.tally.touchdown)}</span>` +
        `<i>·</i><span class="fell">${int(e.tally.fellIn)}</span></span>`
      : esc(e.value);
    return `<div class="key${e.hero ? " hero" : ""}"><div class="v">${v}</div>
       <div class="k">${esc(e.label)}</div></div>`;
  };

  const rows = [];
  for (const e of keyMetricEntries(g)) {
    (rows[e.row] || (rows[e.row] = [])).push(e);
  }
  return rows.filter(Boolean)
    .map((cells) => `<div class="key-row">${cells.map(cell).join("")}</div>`).join("");
}

/* -------------------------------------------------------------------- header */

function renderSummary(result, isExample = false) {
  const g = result.golden, meta = result.meta, caps = g.capabilities;
  const s = g.summary, rec = g.records, w = g.wind;

  el("session-title").textContent = sessionDate(meta);
  // What clock the times on this page are on. Since engine 0.8.2 that is the *session's*
  // own — the offset its watch was wearing — so the note states the fact rather than the
  // old apology, and only falls back to naming the reader's zone when the file could not
  // say (`utcOffsetS` null), which is the one case where the reader has to know.
  const clockNote = meta.utcOffsetS === null || meta.utcOffsetS === undefined
    ? " · no timezone in this file — times shown on your own clock"
    : " · times as recorded on the water";
  el("session-sub").innerHTML =
    `${esc(result.file.name)} · ${int(meta.samples)} samples @ ${nf(caps.sampleRateHz, 0)} Hz` +
    (meta.startUtc ? clockNote : "");

  const badges = [];
  // First badge, and a disclaimer rather than a category: the bundled session is somebody
  // else's ride, and a first-time visitor reading these numbers has to know that before
  // reading anything else. Plain ink, like the library list's own EXAMPLE tag — the accent
  // is reserved for what the *file* is, not for what it is not.
  if (isExample) {
    badges.push(["Example session", false,
                 "The bundled demonstration session — not your own data"]);
  }
  if (meta.discipline) badges.push([meta.discipline, true]);
  badges.push([{ a: "CIQ dev fields", b: "native FIT", c: "degraded source" }[meta.sourceClass],
               meta.sourceClass === "a"]);
  if (meta.sport) badges.push([meta.sport, false]);
  if (caps.hasAccel) badges.push(["accel", false]);
  if (caps.hasWatchLaps) badges.push([`${meta.laps} laps`, false]);
  if (caps.hasHR) badges.push(["HR", false]);
  el("session-badges").innerHTML = badges
    .map(([t, accent, title]) => `<span class="badge${accent ? " accent" : ""}"` +
         (title ? ` title="${esc(title)}"` : "") + `>${esc(t)}</span>`).join("");

  el("key-metrics").innerHTML = keyMetrics(g);

  const windTile = w
    ? { k: "Wind axis", v: `${nf(w.dirDeg, 0)}°`, unit: "from",
        n: `confidence ${nf(w.confidence, 2)} · lobes ${nf(w.lobesDeg?.[0], 0)}/${nf(w.lobesDeg?.[1], 0)}°` +
           // What the watch had to go on. The rider's own bearing is stated flat; an axis the
           // watch ESTIMATED (session field 44, app >= 0.9.0) carries the same leading "~" it
           // wears on the watch, because an estimate that reads like a measurement is worse
           // than no estimate at all.
           (meta.windDirUserDeg !== null && meta.windDirUserDeg !== undefined
              ? ` · watch says ${nf(meta.windDirUserDeg, 0)}°` : "") +
           (meta.windDirAutoDeg !== null && meta.windDirAutoDeg !== undefined
              ? ` · watch estimated ~${nf(meta.windDirAutoDeg, 0)}°` : "") }
    : { k: "Wind axis", v: "—", n: "no usable axis in the COG distribution" };

  const tiles = [
    { k: "Duration", v: hms(meta.durationS), n: `moving ${hms(meta.timerTimeS)}` },
    { k: "Distance", v: nf(s.distanceKm, 2), unit: "km", n: `best 500 m ${nf(rec.best500mKn, 1)} kn` },
    { k: "On foil", v: `${nf(s.foilPct, 0)}%`, n: `${hms(s.foilTimeS)} flying` },
    { k: "Flights", v: int(s.flightCount),
      n: `longest ${hms(s.longestFlightS)} · ${int(s.longestFlightM)} m` },
    { k: "Best 2 s", v: nf(rec.best2sKn, 2), unit: "kn", n: `10 s ${nf(rec.best10sKn, 2)} kn` },
    { k: "Best 5×10 s", v: nf(rec.best5x10sKn, 2), unit: "kn", n: `1 NM ${nf(rec.bestNmKn, 2)} kn` },
    { k: "Alpha 500", v: nf(rec.alpha500Kn, 2), unit: "kn", n: `250 m ${nf(rec.best250mKn, 2)} kn` },
    { k: "Turns", v: int(s.turns.turnsCounted),
      n: `${s.turns.jibes} jibes · ${s.turns.tacks} tacks · ${nf(s.turns.successPct, 0)}% clean` },
    { k: "Outcomes", v: `${s.turns.outcomes.flewThrough}/${s.turns.outcomes.touchdown}/${s.turns.outcomes.fellIn}`,
      n: "flew through / touchdown / fell in" },
    windTile,
  ];
  el("tiles").innerHTML = tiles.map((t) => `
    <div class="tile">
      <div class="k">${esc(t.k)}</div>
      <div class="v">${esc(t.v)}${t.unit ? `<small>${esc(t.unit)}</small>` : ""}</div>
      <div class="n">${esc(t.n || "")}</div>
    </div>`).join("");
}

/* ------------------------------------------------------------------ takeoffs */

function renderTakeoffs(host, g, meta) {
  const k = g.summary.takeoff;
  const accel = g.capabilities.hasAccel;
  const rows = [
    ["Attempts", int(k.takeoffAttempts)],
    ["Successful", `${int(k.takeoffSuccesses)} (${nf(k.successPct, 0)} %)`],
    ["Failed", int(k.failedAttempts)],
    ["Avg time to foil", k.avgTakeoffS === null ? "—" : `${nf(k.avgTakeoffS, 1)} s`],
    ["Median time to foil", k.medianTakeoffS === null ? "—" : `${nf(k.medianTakeoffS, 1)} s`],
  ];
  const pumpRows = [
    ["Avg pumps to takeoff", nf(k.avgPumpsToTakeoff, 1)],
    ["Median pumps to takeoff", nf(k.medianPumpsToTakeoff, 1)],
    ["Total pump strokes", int(k.totalPumpStrokes)],
    ["In-flight pump strokes", `${int(k.inFlightPumpStrokes)} in ${int(k.inFlightEpisodes)} episodes`],
    ["Free takeoffs (no pumping)", int(k.freeTakeoffs)],
  ];
  host.innerHTML = `
    <div class="kv">${(accel ? rows.concat(pumpRows) : rows)
      .map(([a, b]) => `<div class="row"><span>${esc(a)}</span><span>${esc(b)}</span></div>`).join("")}</div>
    ${accel ? "" : `<p class="note" style="margin-top:14px">
      No wrist accelerometer stream in this file, so pump-stroke detection could not run:
      pumps-to-takeoff and stroke counts are unavailable. Attempts and timings above come from
      the speed trace alone.</p>`}`;
}

/* -------------------------------------------------------------------- tables */

function outcomePill(outcome) {
  const holder = document.createElementNS(SVGNS, "svg");
  holder.setAttribute("viewBox", "-6 -6 12 12");
  const shape = { flew_through: "disc", touchdown: "triangle", fell_in: "cross" }[outcome] || "square";
  marker(holder, { shape, color: OUTCOME_COLOR[outcome] || C.ink3 }, 0, 0, 0.85);
  return `<span class="pill ${outcome}">${holder.outerHTML}${OUTCOME_LABEL[outcome] || outcome}</span>`;
}

const yn = (b) => (b ? "yes" : "–");

function renderTurns(table, caption, g, v, meta) {
  const s = g.summary.turns;
  caption.textContent =
    `${s.turnsCounted} counted (${s.jibes} jibes, ${s.tacks} tacks), ${s.rejected} bear-aways rejected · ` +
    `${s.turnsSuccessful} clean — carried ≥ 70 % of entry speed (${nf(s.successPct, 0)} %) · ` +
    `port/starboard ${s.port}/${s.starboard}`;

  const head = ["#", "time", "type", "turn", "tack", "entry kn", "min kn", "score", "clean",
                "outcome", "stop s", "off foil s", "pump", "wet", "arc m", "R m"];
  table.innerHTML = `<thead><tr>${head
    .map((h, i) => `<th${i <= 4 || i === 9 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${g.turns.map((t, i) => `
      <tr>
        <td class="l">${i + 1}</td>
        <td class="l">${clockAt(meta, t.ts)}</td>
        <td class="l">${esc(t.type)}${t.counted ? "" : ' <span class="pill">not counted</span>'}</td>
        <td class="l dim">${esc(t.direction)}</td>
        <td class="l dim">${esc(t.side)}</td>
        <td>${nf(t.entryKn, 2)}</td>
        <td>${nf(t.minKn, 2)}</td>
        <td>${nf(t.score * 100, 0)} %</td>
        <td>${yn(t.success)}</td>
        <td class="l">${outcomePill(t.outcome)}${t.borderline ? ' <span class="pill">borderline</span>' : ""}</td>
        <td>${nf(t.stoppedS, 1)}</td>
        <td>${nf(t.offFoilS, 1)}</td>
        <td class="dim">${yn(t.pumped)}</td>
        <td class="dim">${yn(t.submerged)}</td>
        <td class="dim">${nf(t.arcM, 0)}</td>
        <td class="dim">${nf(t.radiusM, 0)}</td>
      </tr>`).join("")}</tbody>`;
}

function renderEnds(table, caption, g, meta) {
  const e = g.summary.flightEnds, sp = g.summary.outcomeSplit;
  caption.textContent =
    `${sp.turnFalls} falls in turns / ${sp.straightFalls} straight-line · ` +
    `${sp.turnTouchdowns} touchdowns in turns / ${sp.straightTouchdowns} straight-line · ` +
    `${sp.glideOuts} glide-outs` + (sp.unknownEnds ? ` · ${sp.unknownEnds} truncated by a gap` : "");

  const head = ["flight", "time", "outcome", "stop s", "off foil s", "min kn", "pump", "wet",
                "window s", "in turn"];
  table.innerHTML = `<thead><tr>${head
    .map((h, i) => `<th${i <= 2 || i === 9 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${g.flightEnds.map((x) => `
      <tr>
        <td class="l">${x.flightIndex + 1}</td>
        <td class="l">${clockAt(meta, x.ts)}</td>
        <td class="l">${outcomePill(x.outcome)}${x.borderline ? ' <span class="pill">borderline</span>' : ""}</td>
        <td>${nf(x.stoppedS, 1)}</td>
        <td>${nf(x.offFoilS, 1)}</td>
        <td>${x.minKn === null ? "—" : nf(x.minKn, 2)}</td>
        <td class="dim">${yn(x.pumped)}</td>
        <td class="dim">${yn(x.submerged)}</td>
        <td class="dim">${nf(x.windowS, 0)}</td>
        <td class="l dim">${x.ownedByTurn === null ? "–" : `turn ${x.ownedByTurn + 1}`}</td>
      </tr>`).join("")}</tbody>`;
}
