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

import { renderFigures } from "./session.js";
import { C, OUTCOME_COLOR, OUTCOME_LABEL, SVGNS, clockAt, esc, hms, int, marker, nf,
         sessionDate } from "./viz.js";

// Re-exported so the rest of the app keeps one import site for the shared helpers; the
// split into viz.js is an internal arrangement of the rendering layer.
export { C, clockAt, esc, figureWidth, hideTip, hms, int, isNarrow, nf, sessionDate,
         showTip, svg } from "./viz.js";
export { clearPlayhead, closePopover, resetSession } from "./session.js";

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
export function render(result, { highlight = null } = {}) {
  const g = result.golden, v = result.view, meta = result.meta;
  renderSummary(result);
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
 * Every rule the two platforms have to agree on lives in this one function, and its Swift
 * twin is pinned by `PresentationTests.keyMetrics*`. A difference between the two is a bug.
 */
export function keyMetrics(g) {
  const s = g.summary, t = s.turns, rec = g.records;

  // Goldens serialize a non-qualifying record as 0.0 where the Swift model uses nil; both
  // mean "no window of that length exists", and neither may print as a speed.
  const best2s = rec.best2sKn >= 0.05 ? `${nf(rec.best2sKn, 2)} kn` : "—";
  // Every other speed in either app is knots, so the one summary number the engine reports
  // in km/h is converted rather than set beside a column of them.
  const avg = s.avgSpeedKmh === null || s.avgSpeedKmh === undefined
    ? "—" : `${nf(s.avgSpeedKmh / 1.852, 2)} kn`;

  // Jibes are what the rider asked for and what JPH counts a row below, so the tally has
  // to be about the same turns. A session whose wind axis never resolved has no jibes at
  // all, and an empty ladder over an afternoon of turns would read as "nothing happened" —
  // so it falls back to every counted turn, the same way the rate row falls back to TPH.
  // The caption says which, so the three numbers can never be read as the other set.
  const tally = t.jibes > 0 ? { o: t.jibeOutcomes, of: `of ${t.jibes} jibes` }
    : (t.turnsCounted > 0 ? { o: t.outcomes, of: `of ${t.turnsCounted} turns` } : null);

  // `durationS <= 0` makes the engine report all four rates as null: there is no hour to
  // divide by, which is an absence and never a flattering 0.0. The row disappears.
  const rates = [];
  if (s.wetPerHour !== null && s.wetPerHour !== undefined) {
    rates.push((s.jibesPerHour > 0 || !(s.turnsPerHour > 0))
      ? { v: nf(s.jibesPerHour, 1), k: "JPH · dry jibes per hour" }
      : { v: nf(s.turnsPerHour, 1), k: "TPH · turns per hour" });
    rates.push({ v: nf(s.wetPerHour, 1), k: "WPH · swims per hour" });
  }

  const cell = (v, k, cls = "") =>
    `<div class="key${cls ? ` ${cls}` : ""}"><div class="v">${v}</div>
       <div class="k">${esc(k)}</div></div>`;
  const row = (cells) => `<div class="key-row">${cells.join("")}</div>`;

  const rows = [
    row([cell(esc(hm(s.durationS)), "duration"),
         cell(`${nf(s.distanceKm, 1)} km`, "distance"),
         cell(esc(avg), "avg speed")]),
    // The session's fastest measured window, alone on its line and in the block's largest
    // type: it is the number a rider quotes, and the label names the window rather than
    // letting "max" imply a peak sample (docs/presentation.md, "Record windows").
    row([cell(esc(best2s), "max 2 s", "hero")]),
  ];

  if (tally || t.turnsCounted > 0) {
    const cells = [];
    if (tally) {
      const ladder = `<span class="flew">${int(tally.o.flewThrough)}</span>` +
        `<i>·</i><span class="touchdown">${int(tally.o.touchdown)}</span>` +
        `<i>·</i><span class="fell">${int(tally.o.fellIn)}</span>`;
      cells.push(cell(`<span class="tally">${ladder}</span>`,
                      `flew · touchdown · fell — ${tally.of}`));
    }
    if (t.turnsCounted > 0) {
      cells.push(cell(`${int(t.longestDryStreak)} dry · ${int(t.longestFlewStreak)} flew`,
                      "best streaks"));
    }
    rows.push(row(cells));
  }
  if (rates.length) rows.push(row(rates.map((r) => cell(esc(r.v), r.k))));
  return rows.join("");
}

/** `1:57` — hours and minutes, which is how long a session is talked about. Rounded to the
 *  nearest minute, not truncated: `0:00` over a recording that exists reads as a failure to
 *  measure. Twin of `KeyMetrics.hoursMinutes`. */
function hm(sec) {
  if (sec === null || sec === undefined) return "—";
  const m = Math.max(0, Math.round(sec / 60));
  return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")}`;
}

/* -------------------------------------------------------------------- header */

function renderSummary(result) {
  const g = result.golden, meta = result.meta, caps = g.capabilities;
  const s = g.summary, rec = g.records, w = g.wind;

  el("session-title").textContent = sessionDate(meta.startUtc);
  el("session-sub").innerHTML =
    `${esc(result.file.name)} · ${int(meta.samples)} samples @ ${nf(caps.sampleRateHz, 0)} Hz` +
    (meta.startUtc ? ` · times shown in your local timezone` : "");

  const badges = [];
  if (meta.discipline) badges.push([meta.discipline, true]);
  badges.push([{ a: "CIQ dev fields", b: "native FIT", c: "degraded source" }[meta.sourceClass],
               meta.sourceClass === "a"]);
  if (meta.sport) badges.push([meta.sport, false]);
  if (caps.hasAccel) badges.push(["accel", false]);
  if (caps.hasWatchLaps) badges.push([`${meta.laps} laps`, false]);
  if (caps.hasHR) badges.push(["HR", false]);
  el("session-badges").innerHTML = badges
    .map(([t, accent]) => `<span class="badge${accent ? " accent" : ""}">${esc(t)}</span>`).join("");

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
      n: `${s.turns.jibes} jibes · ${s.turns.tacks} tacks · ${nf(s.turns.successPct, 0)}% held speed` },
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
    `${s.turnsSuccessful} held ≥ 70 % of entry speed (${nf(s.successPct, 0)} %) · ` +
    `port/starboard ${s.port}/${s.starboard}`;

  const head = ["#", "time", "type", "turn", "tack", "entry kn", "min kn", "score", "held",
                "outcome", "stop s", "off foil s", "pump", "wet", "arc m", "R m"];
  table.innerHTML = `<thead><tr>${head
    .map((h, i) => `<th${i <= 4 || i === 9 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${g.turns.map((t, i) => `
      <tr>
        <td class="l">${i + 1}</td>
        <td class="l">${clockAt(meta.startUtc, t.ts)}</td>
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
        <td class="l">${clockAt(meta.startUtc, x.ts)}</td>
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
