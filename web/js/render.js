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

import { speed, speedNumber, speedUnit } from "./appsettings.js";
import { hm, keyMetricEntries } from "./cardstats.js";
import { GLOSSARY, NOT_A_SESSION } from "./copy.js";
import { EXPERIMENTAL_NOTE, lexicon } from "./lexicon.js";
import { renderFigures } from "./session.js";
/* r3-w3: the turn page and the flight-end page. One hook, one line below: the page reads
   the document it is handed and wires itself to the two tables. js/turnpage.js. */
import { setSessionDocument } from "./turnpage.js";
import { C, OUTCOME_COLOR, OUTCOME_LABEL, SVGNS, clockAt, esc, hms, int, marker, nf,
         outcomeText, pct, pctDigits, sessionDate } from "./viz.js";

// Re-exported so the rest of the app keeps one import site for the shared helpers; the
// split into viz.js is an internal arrangement of the rendering layer.
export { C, clockAt, esc, figureWidth, hideTip, hms, int, isNarrow, nf, pct, pctDigits,
         sessionDate, showTip, svg, zonedFormat } from "./viz.js";
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
  setSessionDocument(result);                                     // r3-w3
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
 *   4  JPH + CPH (or TPH alone) and WPH — the per-hour rates: JPH over *dry* jibes since
 *      0.7.0, CPH over the *clean* ones since 0.10.0
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
    // `extra` marks a block-only cell (5×10 s, alpha 500): the card parity check parses
    // `class="key"` / `class="key hero"` and skips these, which is exactly the contract —
    // the card is the block *minus* its block-only cells (docs/presentation.md).
    return `<div class="key${e.hero ? " hero" : ""}${e.blockOnly ? " extra" : ""}"><div class="v">${v}</div>
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

/**
 * What clock the times on this page are on — and, since engine 0.9.1, how well we know it.
 *
 * Engine 0.8.2 gave the page the *session's* own offset instead of the reader's, and the
 * note changed from an apology to a statement: "times as recorded on the water". The
 * statement was true whenever the recording had said so itself — and it was also printed
 * over an offset **guessed from longitude**, which is the solar offset, an hour out under
 * DST and up to two inside a wide zone. For a GPX that guess is the normal case, not the
 * exception, so the over-claim was the common one: a July session in Torbole read an hour
 * early with the page insisting it was as recorded.
 *
 * `meta.utcOffsetSource` (docs/presentation.md "Session time") names the rung that
 * answered, and the note is written from it:
 *
 *   activity | icu   exact — the recording or the athlete's account said so
 *   longitude        a guess from where the track is, and the note says so
 *   device | null    nothing could say; the reader's own clock, which they must be told
 *
 * A document with no `utcOffsetSource` at all predates 0.9.1 and keeps the old wording:
 * every analysis this page shows is produced by the bundled engine milliseconds earlier,
 * so the case exists only for a hand-made fixture.
 */
export function clockNoteFor(meta) {
  if (meta.utcOffsetS === null || meta.utcOffsetS === undefined
      || meta.utcOffsetSource === "device") {
    return " · no timezone in this file, times shown on your own clock";
  }
  return meta.utcOffsetSource === "longitude"
    ? " · times estimated from the track's position"
    : " · times as recorded on the water";
}


function renderSummary(result, isExample = false) {
  const g = result.golden, meta = result.meta, caps = g.capabilities;
  const s = g.summary, rec = g.records, w = g.wind;
  // The words this session is read in (docs/presentation.md, "Discipline lexicon"). The
  // config echo is the engine's own statement about which preset produced this document —
  // absent on a wingfoil run, which is the default this resolves to.
  const words = lexicon(g.config?.discipline);

  el("session-date").textContent = sessionDate(meta);
  const clockNote = clockNoteFor(meta);
  // The file's name and what clock its times are on. The sample count and the sample rate
  // used to sit between them; neither changes anything a rider would do next, and "9 214
  // samples @ 1 Hz" as the second line of your own session report reads like a log entry.
  // Both are still in the JSON, under `meta`.
  el("session-sub").innerHTML =
    `${esc(result.file.name)}` + (meta.startUtc ? clockNote : "");

  const badges = [];
  // First badge, and a disclaimer rather than a category: the bundled session is somebody
  // else's ride, and a first-time visitor reading these numbers has to know that before
  // reading anything else. Plain ink, like the library list's own EXAMPLE tag — the accent
  // is reserved for what the *file* is, not for what it is not.
  if (isExample) {
    badges.push(["Example session", false,
                 "The bundled demonstration session. Not your own data."]);
  }
  if (meta.discipline) badges.push([meta.discipline, true]);
  // Beside the discipline badge and never instead of it: the badge says what the *recording*
  // is, this says how it was read and that the reading is not one anybody has checked yet
  // (docs/algorithms.md "Disciplines"). The web has no override — the preset is whatever the
  // recording's own developer field asked for.
  if (words.chip) badges.push([words.chip, false, EXPERIMENTAL_NOTE]);
  // What the recording is, said in the words the rider owns. The three source classes are
  // parse.py's (`a` our watch app's developer fields, `b` a standard FIT with speed, `c`
  // something degraded) and their internal names were on the page verbatim — "CIQ dev
  // fields" names a Garmin SDK concept, and "degraded source" sounds like an accusation
  // about the rider rather than a note about the file. The title carries the detail.
  badges.push([{ a: "CleanJibe recording", b: "measured speed", c: "limited data" }[meta.sourceClass],
               meta.sourceClass === "a",
               { a: "Recorded by the CleanJibe watch app. Every metric available.",
                 b: "The recording carries its own speed channel. Everything but pump and "
                    + "takeoff effort.",
                 c: "A GPX, a TCX without a speed channel, or another source with none. "
                    + "Speed records are estimated from positions and uncertified. "
                    + "There is no pump data."
               }[meta.sourceClass]]);
  if (meta.sport) badges.push([meta.sport, false]);
  if (caps.hasAccel) badges.push(["accelerometer", false]);
  if (caps.hasWatchLaps) badges.push([`${meta.laps} laps`, false]);
  if (caps.hasHR) badges.push(["HR", false]);
  el("session-badges").innerHTML = badges
    .map(([t, accent, title]) => `<span class="badge${accent ? " accent" : ""}"` +
         (title ? ` title="${esc(title)}"` : "") + `>${esc(t)}</span>`).join("");

  el("key-metrics").innerHTML = keyMetrics(g);
  renderNotASession(g);

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
    // **One clock.** The engine's cleaned span (`summary.durationS`), in the block's own
    // spelling — the same number and the same string the "duration" cell prints a few
    // pixels above. This tile used to read the FIT's `total_elapsed_time` through `hms`,
    // so the page carried `1:57 h` over `1:57:12` of a *different* clock. The "moving"
    // note stays the file's own timer time, which is what that word means here.
    { k: "Duration", v: hm(s.durationS), n: `moving ${hms(meta.timerTimeS)}` },
    { k: "Distance", v: nf(s.distanceKm, 1), unit: "km",
      n: `best 500 m ${speed(rec.best500mKn, 1)}` },
    { k: words.onFoil, v: pct(s.foilPct),
      n: `${hms(s.foilTimeS)} ${words.foilTimeLower}` },
    // engine 0.13.0: `longestFlightM` becomes `maxFlightM` — the maximum flight distance,
    // which is this flight's own only by coincidence. The note follows the field.
    { k: "Flights", v: int(s.flightCount),
      n: `longest ${hms(s.longestFlightS)} · max ${int(s.maxFlightM)} m` },
    // The tiles carry their unit in a `<small>` of their own, so the number comes through
    // `speedNumber` and the word through `speedUnit` — one formatter, whichever half of it
    // a cell needs (js/appsettings.js; `Speed` in the kit).
    { k: "Best 2 s", v: speedNumber(rec.best2sKn), unit: speedUnit(),
      n: `10 s ${speed(rec.best10sKn)}` },
    { k: "Best 5×10 s", v: speedNumber(rec.best5x10sKn), unit: speedUnit(),
      n: `1 NM ${speed(rec.bestNmKn)}` },
    { k: "Alpha 500", v: speedNumber(rec.alpha500Kn), unit: speedUnit(),
      n: `250 m ${speed(rec.best250mKn)}` },
    { k: "Turns", v: int(s.turns.turnsCounted),
      // The **outcome** share over every counted turn. It used to print `successPct`, the
      // engine's score verdict, which is not one of the rider's two tiers (flew through,
      // and clean) and had no business on a tile under any name.
      n: `${s.turns.jibes} jibes · ${s.turns.tacks} tacks · `
         + `${pct(100 * s.turns.outcomes.flewThrough / (s.turns.turnsCounted || 1))} flew through` },
    // **"Turn verdicts", the glossary's own word** (20 September 2026). The tile was called
    // "Outcomes", which is a second name for the thing the block, the card, the watch and
    // /help/ all call the turn verdicts — and the round that started this one began with a
    // rider reading three names for one number on three screens.
    { k: "Turn verdicts",
      v: `${s.turns.outcomes.flewThrough}/${s.turns.outcomes.touchdown}/${s.turns.outcomes.fellIn}`,
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

/* ------------------------------------------------------------------ glossary */

/**
 * Fill the `?` beside the key-metrics block — **once**, at boot, not per session.
 *
 * The analyzer had no definition of anything anywhere in it (ux-audit A3.2): it prints
 * `On foil`, `JPH`, `CPH`, `WPH` and the three turn verdicts, and the only route out was a
 * footer link to /learn/ that does not say the word "glossary". These are the same eight
 * lines the welcome screen selects from and /learn/'s definition list carries, out of
 * `docs/copy/glossary.json` through js/copy.js — nothing is retyped here, so a wording the
 * kit changes arrives on this page with the next `make_copy_js.py`.
 *
 * The block is a closed `<details>` inside `#results`, so it costs a reader who already
 * knows the words one line and a reader who does not one tap. Called from js/app.js.
 */
export function renderGlossary() {
  const list = el("glossary-list");
  if (!list) return;
  // A wrapper per entry, so the <dl> can be a wrapping grid: a bare dt/dd pair would land
  // in two separate cells of it, with the term in one column and its sentence in the next.
  list.innerHTML = GLOSSARY.map((entry) => `
    <div class="g-entry">
      <dt>${esc(entry.term)}</dt>
      <dd>${esc(entry.line)}</dd>
    </div>`).join("");
}

/* ------------------------------------------------------------- not a session */

/**
 * Metres under a kilometre, otherwise one decimal of km — `NotASessionNote.distance` in
 * WingFoilKit, character for character, because this line prints beside the key-metrics
 * block and a third spelling of the same distance is a third number.
 *
 * This is formatting, not analysis: `summary.distanceKm` is the engine's own field and
 * nothing here recomputes it (web/README.md, "The one architectural rule").
 */
function distanceNote(km) {
  const value = km ?? 0;
  return value < 1 ? `${Math.round(value * 1000)} m` : `${value.toFixed(1)} km`;
}

/**
 * **This recording is not a session** — the tag on the title and the one line under it.
 *
 * Engine 0.19.0 decides (docs/algorithms.md, "Not a session"): no foil time at all, AND
 * either under two minutes or under two hundred metres. The analyzer has computed that
 * verdict since the bundle went to 0.19.0 and said nothing about it, so a thirty-second
 * beach recording was drawn here as a session and tagged on the phone. The engine's own
 * `summary.isSession` / `summary.notASessionReason` are read straight out of the document
 * — nothing is recomputed in JavaScript — and the words are the app's, from
 * docs/copy/verdicts.json through the generated js/copy.js.
 *
 * Three rules the wording keeps, and the reason the strings are not written here: nothing
 * is deleted, the line says what was looked at, and no engine vocabulary reaches the
 * rider. `NotASessionNote.swift` states them at length.
 *
 * A document from an engine before 0.19.0 carries neither field and says nothing: the
 * absence of a verdict is not a verdict.
 */
function renderNotASession(g) {
  const tag = el("not-a-session-tag"), note = el("not-a-session-note");
  const s = g.summary;
  if (s.isSession !== false) {
    tag.hidden = true;
    note.hidden = true;
    return;
  }
  tag.textContent = NOT_A_SESSION.tag;
  tag.hidden = false;
  // `no_recording` belongs to a library row with a card and no file yet, which this page
  // cannot reach — it only ever sees a file somebody handed it. The branch is here anyway
  // because the kit branches here, and a reason code the engine may send has to land
  // somewhere other than in the wrong sentence.
  note.textContent = s.notASessionReason === "no_recording"
    ? NOT_A_SESSION.lines[0]
    : NOT_A_SESSION.lines[1]
        .replace("{duration}", hms(s.durationS))
        .replace("{distance}", distanceNote(s.distanceKm));
  note.hidden = false;
}

/* ------------------------------------------------------------------ takeoffs */

function renderTakeoffs(host, g, meta) {
  const k = g.summary.takeoff;
  const accel = g.capabilities.hasAccel;
  const rows = [
    // **Takeoffs and attempts, each naming the other** (20 September 2026, the phone's
    // `SessionTakeoffSection`). The watch counted 15 tries on an afternoon this block
    // reported 9 takeoffs on, and nothing said both were right.
    //
    // **"Got up", not "Successful".** `success` is engine vocabulary and appears in no
    // rider-facing text (CLAUDE.md) — and on the same afternoon it was this block's word
    // for a takeoff rate while Garmin Connect used *Turn success* for a turn speed verdict.
    // One word, two measurements, three screens apart; the turn verdict is **Speed kept**
    // and this is the rider getting up.
    ["Takeoffs", `${int(k.takeoffSuccesses)} of ${int(k.takeoffAttempts)} attempts`],
    ["Attempts", int(k.takeoffAttempts)],
    ["Got up", k.successPct === null || k.successPct === undefined
      ? "— failures invisible without accel"
      : `${pct(k.successPct)} · ${int(k.takeoffSuccesses)} of ${int(k.takeoffAttempts)} attempts`],
    ["Failed attempts", int(k.failedAttempts)],
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
  // **Two tiers, and the score verdict is neither of them.** The rider reads *flew
  // through* — the outcome, no touchdown and no swim — and *clean*, which is a jibe that
  // flew through **and** held its speed. The caption used to lead with `turnsSuccessful`
  // and `tacksSuccessful`, the engine's score reading on its own, which is an internal
  // quantity no label should name; it is gone from here and from the table beside it.
  //
  // The threshold is the **document's own** (`config.turnSuccessPct`), never a literal: the
  // caption said "≥ 70 %" whatever the analysis had been run with, and it named only half
  // the rule. Both halves are stated now — the score against `turnSuccessPct` on the
  // maneuver channel, and a minimum that never dropped below the foil exit speed
  // (docs/algorithms.md, "Turn success").
  const cfg = g.config || {};
  const threshold = cfg.turnSuccessPct === null || cfg.turnSuccessPct === undefined
    ? null : `${nf(cfg.turnSuccessPct, 0)} %`;
  const floor = cfg.foilExitSpeed === null || cfg.foilExitSpeed === undefined
    ? "the foil exit speed" : `${nf(cfg.foilExitSpeed, 0)} km/h`;
  // The quiet tail (engine 0.17.0), and stated the same way: from the document's own config,
  // absent from a document written before it. A clean jibe is now three requirements, and a
  // caption that named two of them would be the same half-rule the threshold literal was.
  const quiet = cfg.turnCleanQuietS
    ? `, and had no touchdown or fall in the ${nf(cfg.turnCleanQuietS, 0)} s after` : "";
  const cleanRule = threshold === null
    ? `flew through and held their speed${quiet}`
    : `flew through, held ≥ ${threshold} of entry speed and never dropped below ${floor}${quiet}`;
  const o = s.outcomes;
  // voice: skip — a strip of counts, one value per segment, in the spec register of
  // docs/voice.md. It is read as a table of numbers rather than as a sentence, so the
  // sentence rules are handed back to the code here. The punctuation still obeys them:
  // no dash and no bracket, the middot separates and the comma groups.
  caption.textContent =
    `${s.turnsCounted} counted · ${s.jibes} jibes, ${s.tacks} tacks · ` +
    `${s.rejected} bear-aways rejected · ` +
    `${o.flewThrough} flew through, ` +
    `${pct(100 * o.flewThrough / (s.turnsCounted || 1))} of them · ` +
    `${o.touchdown} touchdown, ${o.fellIn} fell in · ` +
    `${s.jibesSuccessful} clean jibes · clean: ${cleanRule} · ` +
    `port/starboard ${s.port}/${s.starboard}`;

  // `score` is a *number* — the share of the entry speed the turn held — and stays: it is
  // the evidence behind the verdict, not a verdict itself. The `carried` column beside it
  // was the engine's score boolean, which is not a tier the rider has; `clean` is, and it
  // is the engine's own per-turn flag, read and never re-derived.
  // "why" (engine 0.18.0) is the one column that is a *sentence*, and it is the same sentence
  // the phone prints under the turn's chips — the outcome pill beside it says what happened,
  // this says which rung of the ladder decided. Empty on a fly-through, which needs no reason.
  // The two speed columns carry the unit in the head, so the cells are numbers — and the
  // head is the rider's unit rather than a literal (js/appsettings.js).
  const head = ["#", "time", "type", "turn", "tack", `entry ${speedUnit()}`,
                `min ${speedUnit()}`, "score",
                "clean", "outcome", "why", "stop s", "off foil s", "pump", "wet",
                "arc m", "R m"];
  table.innerHTML = `<thead><tr>${head
    .map((h, i) => `<th${i <= 4 || i === 9 || i === 10 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${g.turns.map((t, i) => `
      <tr>
        <td class="l">${i + 1}</td>
        <td class="l">${clockAt(meta, t.ts)}</td>
        <td class="l">${esc(t.type)}${t.counted ? "" : ' <span class="pill">not counted</span>'}</td>
        <td class="l dim">${esc(t.direction)}</td>
        <td class="l dim">${esc(t.side)}</td>
        <td>${speedNumber(t.entryKn)}</td>
        <td>${speedNumber(t.minKn)}</td>
        <td>${nf(t.score * 100, 0)} %</td>
        <td>${yn(t.clean)}</td>
        <td class="l">${outcomePill(t.outcome)}${t.borderline ? ' <span class="pill">borderline</span>' : ""}</td>
        <td class="l dim">${esc(outcomeText(t, cfg.turnPumpedMarginalSpeed,
                                          g.config?.discipline) ?? "")}</td>
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
  // **The falls line is the flight-end channel's own** (20 September 2026), the same three
  // numbers the key-metrics block's `fell in` cell prints: `all == inTurn + straight`, one
  // event per actual swim. It used to lead with `outcomeSplit.turnFalls`, which is the turn
  // ladder's count, so the line beside this very table could disagree with the table.
  // `touchdowns` and `glide-outs` stay on the split — they are the split's own question.
  //
  // voice: skip — a strip of counts, one value per segment, in the spec register of
  // docs/voice.md, exactly like the turns caption above it. It is read as a row of numbers
  // rather than as a sentence. The punctuation still obeys the rules: no dash and no
  // bracket, the middot separates and the slash pairs the two halves of one count.
  caption.textContent =
    `${e.all.fellIn} fell in · ${e.inTurn.fellIn} in a turn / ` +
    `${e.straight.fellIn} in a straight line · ` +
    `${sp.turnTouchdowns} touchdowns in turns / ${sp.straightTouchdowns} straight-line · ` +
    `${sp.glideOuts} glide-outs` + (sp.unknownEnds ? ` · ${sp.unknownEnds} truncated by a gap` : "");

  const head = ["flight", "time", "outcome", "stop s", "off foil s", `min ${speedUnit()}`,
                "pump", "wet", "window s", "in turn"];
  table.innerHTML = `<thead><tr>${head
    .map((h, i) => `<th${i <= 2 || i === 9 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${g.flightEnds.map((x) => `
      <tr>
        <td class="l">${x.flightIndex + 1}</td>
        <td class="l">${clockAt(meta, x.ts)}</td>
        <td class="l">${outcomePill(x.outcome)}${x.borderline ? ' <span class="pill">borderline</span>' : ""}</td>
        <td>${nf(x.stoppedS, 1)}</td>
        <td>${nf(x.offFoilS, 1)}</td>
        <td>${speedNumber(x.minKn)}</td>
        <td class="dim">${yn(x.pumped)}</td>
        <td class="dim">${yn(x.submerged)}</td>
        <td class="dim">${nf(x.windowS, 0)}</td>
        <td class="l dim">${x.ownedByTurn === null ? "–" : `turn ${x.ownedByTurn + 1}`}</td>
      </tr>`).join("")}</tbody>`;
}
