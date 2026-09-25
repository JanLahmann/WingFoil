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
import { keyMetricEntries } from "./cardstats.js";
import { hm, text } from "./presentation.js";
import { GLOSSARY, NOT_A_SESSION } from "./copy.js";
import { EXPERIMENTAL_NOTE, lexicon } from "./lexicon.js";
import { applyTurnFilter, flightFacts, renderFigures } from "./session.js";
/* r3-w3: the turn page and the flight-end page. One hook, one line below: the page reads
   the document it is handed and wires itself to the two tables. js/turnpage.js. */
import { setSessionDocument } from "./turnpage.js";
/* The Turns tab's cards and its tally, the phone's two blocks over this tab's list. */
import { renderTurnCards } from "./turncards.js";
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
  renderFlights(el("flights-table"), el("flights-caption"), g, meta);
  renderTurnCards(el("turn-cards"), result, meta);
  renderTurns(el("turns-table"), el("turns-caption"), result, meta);
  renderEnds(el("ends-table"), el("ends-caption"), g, meta);
  // Last, and after the table exists: the legend chips filter the turn rows as well as the
  // two figures, and this is the one call that applies the state they are already in to a
  // table that has just been rebuilt (js/session.js, "the turns table rows").
  applyTurnFilter();
}

/* --------------------------------------------------------------- key metrics */

/**
 * The KEY METRICS block, and the JavaScript half of `KeyMetrics.swift`.
 *
 * Four rows, numbers big and labels small, before the tiles and the figures:
 *
 *   1  duration (h:mm) · distance · average speed
 *   2  the best 2 s record, labelled with the window it is
 *   3  the outcome ladder's three counts on the ladder's own inks — the jibes, and since
 *      22 September 2026 the tacks beside them where the session had any — then every fall
 *      of the afternoon and the two turn streaks the engine has computed since 0.4.0 and
 *      neither app ever drew
 *   4  CPH, then ONE dry-turn rate — JPH on a jibes-only session, TPH once tacks exist —
 *      then WPH (Jan, 25 Sep 2026). JPH counts *dry* jibes since 0.7.0, CPH the *clean*
 *      ones since 0.10.0; row 3 leads with the clean jibes' own cell
 *
 * **This function is now layout only.** Every rule the two platforms have to agree on —
 * which entries exist, in what order, with which labels and which strings — is in the
 * presentation document (ADR-033), which `keyMetricEntries` in js/cardstats.js draws. The
 * card has to print *this* list, and a second implementation of it would be a second answer
 * to "was that a good session" travelling in a picture.
 */
export function keyMetrics(doc) {
  const cell = (e) => {
    // A tally is the one kind of cell that is not a string: its three counts are drawn on
    // the verdict ladder's own inks. `e.value` spells the same three numbers, so a renderer
    // that ignores `e.tally` still prints the truth — it just prints it in one colour.
    // The clean jibes wear the star and the clean ink (25 Sep 2026, F8e); a pair cell — the
    // streaks — draws each half in its own ink, flew in the ladder's green (F8f).
    const ink = (role) => ({ "outcome.flew": "flew", "outcome.touchdown": "touchdown",
                             "outcome.fellIn": "fell", "clean.jibe": "clean" }[role] || "");
    const v = e.tally
      ? `<span class="tally"><span class="flew">${int(e.tally.flewThrough)}</span>` +
        `<i>·</i><span class="touchdown">${int(e.tally.touchdown)}</span>` +
        `<i>·</i><span class="fell">${int(e.tally.fellIn)}</span></span>`
      : e.parts
        ? `<span class="tally">${e.parts.map((p) =>
            `<span class="${ink(p.colourRole)}">${int(p.value)} <small>${esc(p.label)}</small></span>`)
            .join("<i>·</i>")}</span>`
        : e.colourRole === "clean.jibe"
          // The star is drawn by CSS (`.star::before`), so the cell's text stays the
          // card's own value and the parity check reads one number.
          ? `<span class="tally"><span class="clean star">${esc(e.value)}</span></span>`
          : esc(e.value);
    // `extra` marks a block-only cell (5×10 s, alpha 500): the card parity check parses
    // `class="key"` / `class="key hero"` and skips these, which is exactly the contract —
    // the card is the block *minus* its block-only cells (docs/presentation.md).
    return `<div class="key${e.hero ? " hero" : ""}${e.blockOnly ? " extra" : ""}"><div class="v">${v}</div>
       <div class="k">${esc(e.label)}</div></div>`;
  };

  const rows = [];
  for (const e of keyMetricEntries(doc)) {
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
 * `meta.utcOffsetSource` (docs/presentation/session-time-video.md "Session time") names the rung that
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


/**
 * One of the nine record kinds, off the document's `records` section.
 *
 * The tiles used to read `golden.records.<key>Kn` straight, which is a second reading of a
 * set the document already resolves once — value, window provenance, whether the recording
 * measured its own speed and whether the rider's policy lets it stand
 * (docs/presentation/document.md, "`records` — the nine kinds"). The *words* come from the
 * same place the legend chip and the Records page take them, `tokens.recordWindow.<id>`,
 * so `Best 2 s` has one spelling in the product.
 */
const recordKn = (doc, key) =>
  (doc?.records?.kinds || []).find((k) => k.key === key)?.value ?? null;

const recordLabel = (key) => text(`tokens.recordWindow.${key}`) ?? key;

function renderSummary(result, isExample = false) {
  const g = result.golden, meta = result.meta, caps = g.capabilities;
  const doc = result.presentation;
  const s = g.summary, w = g.wind;
  // The words this session is read in (docs/presentation/labels.md, "Discipline lexicon"). The
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
  // (docs/algorithms/disciplines.md "Disciplines"). The web has no override — the preset is whatever the
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

  el("key-metrics").innerHTML = keyMetrics(result.presentation);
  renderNotASession(g);

  // **Confidence only when it is low** (Jan, 25 Sep 2026, F8b) — the engine's own bar,
  // `windMinConfidence` (0.5): below it the axis is too weak to name tacks and jibes, the
  // one case where the number changes what the page says. The phone's wind line, twinned.
  const windLow = Boolean(w) && w.usable === false;
  const windTile = w
    ? { k: "Wind axis", v: `${nf(w.dirDeg, 0)}°`, unit: "from",
        n: (windLow ? `${pct(100 * w.confidence)} confident, too weak to name turns` : "") +
           // What the watch had to go on. The rider's own bearing is stated flat; an axis the
           // watch ESTIMATED (session field 44, app >= 0.9.0) carries the same leading "~" it
           // wears on the watch, because an estimate that reads like a measurement is worse
           // than no estimate at all.
           (meta.windDirUserDeg !== null && meta.windDirUserDeg !== undefined
              ? `${windLow ? " · " : ""}watch says ${nf(meta.windDirUserDeg, 0)}°` : "") +
           (meta.windDirAutoDeg !== null && meta.windDirAutoDeg !== undefined
              ? ` · watch estimated ~${nf(meta.windDirAutoDeg, 0)}°` : "") }
    : { k: "Wind axis", v: "—", n: "no usable axis in the COG distribution" };

  // **Each kind of turn with its whole breakdown, as numbers in their inks** (Jan, F9a/b):
  // the clean jibes first with the star, then the ladder. The phone's Jibes and Tacks
  // cards, twinned; the "flew through %" and "Turn verdicts" tiles said the same thing
  // again and are gone.
  const t = s.turns, sp = s.outcomeSplit;
  const fig = (cls, n, word, mark = "") =>
    `<span class="${cls}">${mark}${int(n)} <small>${esc(word)}</small></span>`;
  const ladder = (o) => [fig("flew", o.flewThrough, "flew"), fig("touchdown", o.touchdown, "touch"),
                         fig("fell", o.fellIn, "fell")];
  const breakdown = (parts) => `<span class="tally">${parts.join("<i>·</i>")}</span>`;
  const tiles = [
    // **One clock.** The engine's cleaned span (`summary.durationS`), in the block's own
    // spelling — the same number and the same string the "duration" cell prints a few
    // pixels above. This tile used to read the FIT's `total_elapsed_time` through `hms`,
    // so the page carried `1:57 h` over `1:57:12` of a *different* clock. The "moving"
    // note stays the file's own timer time, which is what that word means here.
    { k: "Duration", v: hm(s.durationS), n: `moving ${hms(meta.timerTimeS)}` },
    { k: "Distance", v: nf(s.distanceKm, 1), unit: "km",
      n: `best 500 m ${speed(recordKn(doc, "best500m"), 1)}` },
    { k: words.onFoil, v: pct(s.foilPct),
      n: `${hms(s.foilTimeS)} ${words.foilTimeLower}` },
    // No "Flights" tile (Jan, F8k): the count is the head of the flight list on Flights.
    // The longest flight stays, because it is a number a rider quotes.
    { k: "Longest flight", v: hms(s.longestFlightS), n: `max ${int(s.maxFlightM)} m in one flight` },
    // The tiles carry their unit in a `<small>` of their own, so the number comes through
    // `speedNumber` and the word through `speedUnit` — one formatter, whichever half of it
    // a cell needs (js/appsettings.js; `Speed` in the kit).
    { k: recordLabel("best2s"), v: speedNumber(recordKn(doc, "best2s")), unit: speedUnit(),
      n: `10 s ${speed(recordKn(doc, "best10s"))}` },
    { k: recordLabel("best5x10s"), v: speedNumber(recordKn(doc, "best5x10s")),
      unit: speedUnit(), n: `1 NM ${speed(recordKn(doc, "bestNm"))}` },
    { k: recordLabel("alpha500"), v: speedNumber(recordKn(doc, "alpha500")),
      unit: speedUnit(), n: `250 m ${speed(recordKn(doc, "best250m"))}` },
    { k: "Jibes", v: int(t.jibes),
      html: t.jibes ? breakdown([fig("clean star", t.jibesSuccessful, "clean")]
                                .concat(ladder(t.jibeOutcomes))) : "",
      n: t.jibes ? "" : "none detected" },
    { k: "Tacks", v: int(t.tacks),
      html: t.tacks ? breakdown(ladder(t.tackOutcomes)) : "",
      n: t.tacks ? "" : "none detected" },
    // **Touchdowns and glide-outs on one tile** (Jan, F9e): both a flight that ended
    // without a swim. The glide-out wears its own neutral ring, never the flew colour.
    { k: "Touchdowns · glide-outs", v: "",
      html: breakdown([fig("touchdown", sp.turnTouchdowns + sp.straightTouchdowns, "touch"),
                       fig("glide ring", sp.glideOuts, "glide-out")]),
      n: `${int(sp.turnTouchdowns)} in turns · ${int(sp.straightTouchdowns)} straight-line` +
         (sp.unknownEnds ? ` · ${int(sp.unknownEnds)} ${sp.unknownEnds === 1 ? "end" : "ends"} cut by the recording` : "") },
    windTile,
  ];
  el("tiles").innerHTML = tiles.map((t) => `
    <div class="tile">
      <div class="k">${esc(t.k)}</div>
      <div class="v">${esc(t.v)}${t.unit ? `<small>${esc(t.unit)}</small>` : ""}</div>
      ${t.html ? `<div class="b">${t.html}</div>` : ""}
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
 * Engine 0.19.0 decides (docs/algorithms/not-a-session.md, "Not a session"): no foil time at all, AND
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
  // **One row for takeoffs and attempts** (Jan, 25 Sep 2026, F12b; the phone's
  // `SessionTakeoffSection`). "Takeoffs 19 of 19 attempts", "Attempts 19" and "Got up —
  // failures invisible without accel" were one fact three times, the last a claim the
  // recording could not make. With an accelerometer the row names the attempts and the
  // share that got up; without one every row that needs it is left out, and one note says
  // why (F12a) — a column of dashes reads as a measurement that failed.
  //
  // "Got up", never "Successful": `success` is engine vocabulary (CLAUDE.md).
  const rows = [
    ["Takeoffs", accel
      ? `${int(k.takeoffSuccesses)} of ${int(k.takeoffAttempts)} attempts` +
        (k.successPct === null || k.successPct === undefined ? "" : ` · ${pct(k.successPct)} got up`)
      : `${int(k.takeoffSuccesses)} · one starts every flight`],
  ];
  if (accel) rows.push(["Failed attempts", int(k.failedAttempts)]);
  rows.push(["Avg time to foil", k.avgTakeoffS === null ? "—" : `${nf(k.avgTakeoffS, 1)} s`]);
  rows.push(["Median time to foil", k.medianTakeoffS === null ? "—" : `${nf(k.medianTakeoffS, 1)} s`]);
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
    ${accel ? "" : `<p class="muted small" style="margin-top:10px">No accelerometer in this
      recording, so pumps and failed attempts are not counted.</p>`}`;
}

/**
 * **Every flight, one row each: when it got up, how long it lasted, how it ended** — the
 * phone's `FlightsListView` (Jan, 25 Sep 2026, F12c). A flight is a takeoff and an end, and
 * the two halves sat on two tabs while the summary printed a bare "Flights" count. The rows
 * are `flightFacts`, the same pairing the map's flight popover reads, so a flight is
 * numbered and timed one way on the page. A glide-out wears its own neutral ring, never the
 * flew-through colour (F9e).
 */
function renderFlights(table, caption, g, meta) {
  if (!table) return;
  const flights = flightFacts(g);
  if (caption) caption.textContent = flights.length
    ? `${plural(flights.length, "flight")}. The flight ends the map marks are listed below.`
    : "No flight in this recording.";
  const MARK = { "glided out": "○", touchdown: "▲", "fell in": "✕", "recording ended": "■" };
  const CLS = { "glided out": "glide", touchdown: "touchdown", "fell in": "fell",
                "recording ended": "glide" };
  const accel = g.capabilities.hasAccel;
  const head = ["flight", "up at", "time", ...(accel ? ["pumps"] : []), "ended"];
  table.innerHTML = `<thead><tr>${head
    .map((h, i) => `<th${i <= 1 || i === head.length - 1 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${flights.map((f) => `
      <tr>
        <td class="l">${f.index + 1}</td>
        <td class="l">${clockAt(meta, f.startTs)}</td>
        <td>${hms(f.endTs - f.startTs)}</td>
        ${accel ? `<td>${f.pumps === null ? "—" : f.pumps === 0 ? "free" : int(f.pumps)}</td>` : ""}
        <td class="l"><span class="tally"><span class="${CLS[f.outcome]}">${MARK[f.outcome]}</span></span> ${esc(f.outcome)}</td>
      </tr>`).join("")}</tbody>`;
}

const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

/* -------------------------------------------------------------------- tables */

function outcomePill(outcome) {
  const holder = document.createElementNS(SVGNS, "svg");
  holder.setAttribute("viewBox", "-6 -6 12 12");
  const shape = { flew_through: "disc", touchdown: "triangle", fell_in: "cross" }[outcome] || "square";
  // A glide-out is no verdict on a turn: its own neutral mark, never the flew colour (F9e).
  const color = outcome === "glide_out" ? C.ink3 : OUTCOME_COLOR[outcome] || C.ink3;
  marker(holder, { shape, color }, 0, 0, 0.85);
  return `<span class="pill ${outcome}">${holder.outerHTML}${OUTCOME_LABEL[outcome] || outcome}</span>`;
}

const yn = (b) => (b ? "yes" : "–");

function renderTurns(table, caption, result, meta) {
  const g = result.golden;
  // **The rows are the document's strip**, one entry per detected sweep in time order,
  // counted and uncounted together — the same list the map's marks and the turn page's
  // "3 of 14" read (docs/presentation/document.md, "`turns` — the legend and the strip").
  const strip = result.presentation?.turns?.strip || [];
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
  // (docs/algorithms/turns.md, "Turn success").
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
                `min ${speedUnit()}`, "held",
                "clean", "outcome", "why", "stop s", "off foil s", "pump", "wet",
                "arc m", "R m"];
  table.innerHTML = `<thead><tr>${head
    .map((h, i) => `<th${i <= 4 || i === 9 || i === 10 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${strip.map((e) => {
      // **The row is the document's strip entry**, joined to the golden for the columns the
      // strip does not carry — the arc, the radius and the two flags are workbench numbers
      // the rider's surfaces never print, so they stay out of the document (ADR-033).
      const t = g.turns[e.index];
      return `
      <tr>
        <td class="l">${e.index + 1}</td>
        <td class="l">${clockAt(meta, e.ts)}</td>
        <td class="l">${esc(t.type)}${e.counted ? "" : ' <span class="pill">not counted</span>'}</td>
        <td class="l dim">${esc(t.direction)}</td>
        <td class="l dim">${esc(e.sideId ?? "")}</td>
        <td>${speedNumber(e.entryKn)}</td>
        <td>${speedNumber(e.minKn)}</td>
        <td>${nf(e.score * 100, 0)} %</td>
        <td>${yn(e.clean)}</td>
        <td class="l">${outcomePill(t.outcome)}${e.borderline ? ' <span class="pill">borderline</span>' : ""}</td>
        <td class="l dim">${esc(outcomeText(t, cfg.turnPumpedMarginalSpeed,
                                          g.config?.discipline) ?? "")}</td>
        <td>${nf(t.stoppedS, 1)}</td>
        <td>${nf(t.offFoilS, 1)}</td>
        <td class="dim">${yn(t.pumped)}</td>
        <td class="dim">${yn(t.submerged)}</td>
        <td class="dim">${nf(t.arcM, 0)}</td>
        <td class="dim">${nf(t.radiusM, 0)}</td>
      </tr>`;
    }).join("")}</tbody>`;
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
