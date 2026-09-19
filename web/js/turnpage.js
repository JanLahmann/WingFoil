/* **The turn page and the flight-end page** — one maneuver at its own scale, as the iPhone
 * app draws it.
 *
 * Until this file existed a row in the Turns table was as deep as the browser went. The
 * phone has had the page since the Turns tab was built: the drawing, the strips, the
 * numbers, why it ended that way, and a swipe to the next one. Jan's rule for the port is
 * that iOS is the prime member, so every word below is the phone's word and every number is
 * the engine's, read and never re-derived.
 *
 *   ios/WingFoil/Features/SessionDetail/TurnDetailView.swift       the page
 *   ios/WingFoil/Features/SessionDetail/TurnDetailMapView.swift    the drawing
 *   ios/WingFoil/Features/SessionDetail/TurnDetailStripView.swift  the speed strip
 *   ios/WingFoil/Features/SessionDetail/FlightEndDetailView.swift  the same page for a loss
 *
 * **The flight-end page is the same page.** A gust that dies, a ventilation on a reach, a tip
 * that catches: the engine has classified every one of those since it started carrying
 * `flightEnds`, and every question a rider asks of a jibe he asks of those too. The phone
 * builds both pages out of one figure and so does this, which is what keeps them honestly
 * identical rather than accidentally similar.
 *
 * The geometry is js/maneuverfigure.js and nothing here re-implements any of it.
 */

import {
  MIN_REFERENCE_KN, MIN_SPAN_M, angleDomain, bestCleanTurn, cfg, deltaDeg, figureBounds,
  figurePoints, flightEndFigure, foilSpans, hasGeometry, legendBottomKn, legendTopKn,
  pathLabels, pointAtRelative, pointNear, rampColor, rampColorFor, rampPosition, scaleBarM,
  sliceAngles, turnFigure, typeLabel,
} from "./maneuverfigure.js";
import { lexicon } from "./lexicon.js";
import {
  C, OUTCOME_COLOR, OUTCOME_LABEL, clockAt, esc, figureWidth, nf, outcomeText, svg,
} from "./viz.js";

/* ------------------------------------------------------------------- the state */

/** The document on screen, set by js/render.js every time one is drawn. */
let doc = null;
/** Which event is open: `{kind: "turn"|"end", index}`, or null when the page is closed. */
let open = null;
let playheadRt = null;
let wired = false;

/** Both remembered, because both are a way of *reading* turns rather than a fact about one:
 *  a rider who thinks in wind angles thinks in them on every jibe. The phone's keys, with
 *  the phone's defaults. */
const PREF_WIND_UP = "turnDetail.orientation.v1";
const PREF_GHOST = "turnDetail.ghost.v1";

function pref(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw === null ? fallback : raw === "1";
  } catch { return fallback; }
}

function setPref(key, value) {
  try { localStorage.setItem(key, value ? "1" : "0"); } catch { /* private window */ }
}

const el = (id) => document.getElementById(id);

/* ------------------------------------------------------------------- the sets */

/** Every counted turn, in time order. The engine emits turns in time order, so this is the
 *  array's own order with the course changes taken out: a bear-away has no verdict, no
 *  score, no entry tack and no outcome word, and its numbers row would be five dashes. */
function turnIndices(g) {
  return g.turns.map((t, i) => (t.counted ? i : -1)).filter((i) => i >= 0);
}

/** Every **drawn** flight end: the ones no turn owns and the recording did not truncate. A
 *  turn-owned end is the same swim already counted at its jibe, and a truncated one is a
 *  recording that stopped. Neither has anything for a page to say. */
function endIndices(g) {
  return g.flightEnds
    .map((e, i) => ((e.ownedByTurn === null || e.ownedByTurn === undefined)
                    && !e.truncated ? i : -1))
    .filter((i) => i >= 0);
}

const setFor = (kind) => (kind === "turn" ? turnIndices(doc.golden) : endIndices(doc.golden));

/** "Jibe 7" — the ordinal counts turns of the same *kind*, because that is what a rider
 *  means: his seventh jibe, not the seventh thing the detector saw. */
function ordinalOf(index, g) {
  const turn = g.turns[index];
  const same = turnIndices(g).filter((i) => g.turns[i].type === turn.type);
  const at = same.indexOf(index);
  return at < 0 ? null : at + 1;
}

/* --------------------------------------------------------------------- wiring */

/**
 * Remember the document, and wire the two tables once.
 *
 * The rows are delegated rather than rebuilt: js/render.js owns the two tables, and a page
 * that reached in to add a button per row would have to be re-run every time they were
 * redrawn. A table row's position IS its record's index — both tables map their whole array
 * — so a click needs nothing from the renderer.
 */
export function setSessionDocument(result) {
  doc = result;
  closePage();
  // After the tables are drawn, not before: `render()` calls this at the top and fills the
  // two tables below it. A course change has no page — no verdict, no score, no entry tack
  // — so its row must not wear the pointer that promises one.
  setTimeout(markOpenableRows, 0);
  if (wired) return;
  wired = true;
  delegate("turns-table", "turn");
  delegate("ends-table", "end");
  const dialog = el("turn-page");
  if (!dialog) return;
  el("turn-page-close")?.addEventListener("click", closePage);
  el("turn-page-prev")?.addEventListener("click", () => step(-1));
  el("turn-page-next")?.addEventListener("click", () => step(1));
  dialog.addEventListener("close", () => { open = null; });
  dialog.addEventListener("keydown", (ev) => {
    if (ev.key === "ArrowLeft") { step(-1); ev.preventDefault(); }
    if (ev.key === "ArrowRight") { step(1); ev.preventDefault(); }
  });
  wireSwipe(dialog);
}

/** Mark the rows that have a page behind them. */
function markOpenableRows() {
  if (!doc) return;
  for (const [tableId, kind] of [["turns-table", "turn"], ["ends-table", "end"]]) {
    const table = el(tableId);
    if (!table) continue;
    const open = new Set(setFor(kind));
    const rows = table.querySelectorAll("tbody tr");
    rows.forEach((row, index) => { row.classList.toggle("opens", open.has(index)); });
  }
}

function delegate(tableId, kind) {
  const table = el(tableId);
  if (!table) return;
  table.addEventListener("click", (ev) => {
    const row = ev.target.closest("tbody tr");
    if (!row || !doc) return;
    const index = Array.prototype.indexOf.call(row.parentNode.children, row);
    if (index < 0) return;
    if (!setFor(kind).includes(index)) return;
    openPage(kind, index);
  });
}

/** A flick between two turns, on a touch screen. Horizontal only, and past a threshold, so
 *  a scroll down the page never counts as one. */
function wireSwipe(dialog) {
  let from = null;
  dialog.addEventListener("pointerdown", (ev) => {
    from = ev.pointerType === "touch" ? { x: ev.clientX, y: ev.clientY } : null;
  });
  dialog.addEventListener("pointerup", (ev) => {
    if (!from) return;
    const dx = ev.clientX - from.x;
    const dy = ev.clientY - from.y;
    from = null;
    if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 2) step(dx < 0 ? 1 : -1);
  });
}

function step(by) {
  if (!open || !doc) return;
  const set = setFor(open.kind);
  const at = set.indexOf(open.index);
  const next = set[at + by];
  if (next === undefined) return;
  openPage(open.kind, next);
}

export function openPage(kind, index) {
  if (!doc) return;
  open = { kind, index };
  playheadRt = null;
  const dialog = el("turn-page");
  if (!dialog) return;
  if (!dialog.open) dialog.showModal();
  draw();
}

export function closePage() {
  const dialog = el("turn-page");
  if (dialog && dialog.open) dialog.close();
  open = null;
}

/* ------------------------------------------------------------------ the figure */

function buildFigure() {
  const g = doc.golden;
  const view = doc.view;
  const windDirDeg = g.wind ? g.wind.dirDeg : null;
  if (open.kind === "turn") {
    const turn = g.turns[open.index];
    const figure = turnFigure(view, turn, windDirDeg, g.config);
    const model = bestCleanTurn(turn, g.turns);
    const ghost = model ? turnFigure(view, model, windDirDeg, g.config) : null;
    return { figure, ghost, turn, end: null };
  }
  const end = g.flightEnds[open.index];
  return { figure: flightEndFigure(view, end, windDirDeg, g.config), ghost: null,
           turn: null, end };
}

const windKnown = () => !!(doc && doc.golden.wind && doc.golden.wind.dirDeg !== null);
const windUpOn = () => pref(PREF_WIND_UP, true) && windKnown();
const ghostOn = () => pref(PREF_GHOST, true);

/* -------------------------------------------------------------------- the page */

function draw() {
  const dialog = el("turn-page");
  const body = el("turn-page-body");
  if (!dialog || !body || !open || !doc) return;
  const { figure, ghost, turn, end } = buildFigure();
  const g = doc.golden;
  const set = setFor(open.kind);
  const at = set.indexOf(open.index) + 1;

  el("turn-page-title").textContent = pageTitle(turn, end, g);
  el("turn-page-count").textContent = `${at} of ${set.length}`;
  el("turn-page-prev").disabled = at <= 1;
  el("turn-page-next").disabled = at >= set.length;

  body.innerHTML = controlsMarkup(figure, ghost)
    + `<div class="figure tp-figure" id="turn-figure"></div>`
    + (hasGeometry(figure) ? "" : `<p class="note">${esc(noGeometryLine())}</p>`)
    + `<div class="figure tp-strip" id="turn-strip-speed"></div>`
    + `<div class="figure tp-strip" id="turn-strip-heading"></div>`
    + `<div class="figure tp-strip" id="turn-strip-foil"></div>`
    + (turn ? turnNumbers(turn, figure) : endNumbers(end, figure))
    + (turn ? `<p class="tp-coach">${esc(coachLine(turn, figure))}</p>` : "")
    + footnote(turn, end, figure);

  wireControls();
  redraw(figure, ghost, turn, end);
  body.scrollTop = 0;
}

function pageTitle(turn, end, g) {
  if (end) return "Flight " + (end.flightIndex + 1) + " · " + endOutcomeLabel(end.outcome);
  const ordinal = ordinalOf(open.index, g);
  const kind = typeLabel(turn.type);
  const head = ordinal === null ? kind : `${kind} ${ordinal}`;
  return `${head} · ${OUTCOME_LABEL[turn.outcome] || turn.outcome}`;
}

const noGeometryLine = () => (open.kind === "turn"
  ? "No GPS fixes through this turn. Numbers only."
  : "No GPS fixes through this flight end. Numbers only.");

/** "Glided out", "touchdown", "fell in" — and never the turn ladder's "flew through", which
 *  is a verdict a flight end cannot earn. */
function endOutcomeLabel(outcome) {
  switch (outcome) {
    case "fell_in": return "fell in";
    case "touchdown": return "touchdown";
    case "glide_out": return "glided out";
    default: return "unknown";
  }
}

/* ------------------------------------------------------------------- controls */

const NO_WIND_FOR_ORIENTATION =
  "Wind up needs a wind direction. This session has none the engine trusts, and none set on "
  + "the watch.";

function controlsMarkup(figure, ghost) {
  const known = windKnown();
  const up = windUpOn();
  const tail = open.kind === "turn"
    ? " The turn is drawn north up." : " The track is drawn north up.";
  const ghostRow = open.kind !== "turn" ? ""
    : (ghost && hasGeometry(ghost)
        ? `<label class="tp-switch"><input type="checkbox" id="turn-ghost"${
            ghostOn() ? " checked" : ""}> <span>Compare with best clean jibe</span></label>`
        : `<p class="muted small">Nothing to compare with. This session has no other jibe
             that flew through the same way round.</p>`);
  return `<div class="tp-controls">
    <div class="seg" role="group" aria-label="Map orientation">
      <button type="button" class="seg-btn" data-orient="north"
        aria-pressed="${!up}"${known ? "" : " disabled"}>North up</button>
      <button type="button" class="seg-btn" data-orient="wind"
        aria-pressed="${up}"${known ? "" : " disabled"}>Wind up</button>
    </div>
    ${known ? "" : `<p class="muted small">${esc(NO_WIND_FOR_ORIENTATION + tail)}</p>`}
    ${ghostRow}
  </div>`;
}

function wireControls() {
  for (const button of document.querySelectorAll("#turn-page-body [data-orient]")) {
    button.addEventListener("click", () => {
      setPref(PREF_WIND_UP, button.dataset.orient === "wind");
      draw();
    });
  }
  el("turn-ghost")?.addEventListener("change", (ev) => {
    setPref(PREF_GHOST, ev.target.checked);
    draw();
  });
}

/* -------------------------------------------------------------------- redraw */

let live = null;

function redraw(figure, ghost, turn, end) {
  live = { figure, ghost: ghostOn() ? ghost : null, turn, end };
  drawFigure();
  drawSpeedStrip();
  drawHeadingStrip();
  drawFoilStrip();
}

function setPlayhead(rt) {
  playheadRt = rt;
  drawFigure();
  drawSpeedStrip();
  drawHeadingStrip();
  drawFoilStrip();
}

/* ------------------------------------------------------------------ the drawing */

/** Layout points reserved on every edge, so a mark centred on the outermost vertex is not
 *  clipped in half against the frame. */
const INSET = 14;
/** The tap radius, in layout points rather than metres: a fingertip is a fingertip whatever
 *  the drawing is scaled to. */
const TAP_TOLERANCE_P = 26;
const LABEL_EVERY_S = 5;
const LABEL_OFFSET_P = 13;

function placer(bounds, w, h) {
  const scale = Math.min((Math.max(w - INSET * 2, 1))
                           / Math.max(bounds.maxX - bounds.minX, MIN_SPAN_M),
                         (Math.max(h - INSET * 2, 1))
                           / Math.max(bounds.maxY - bounds.minY, MIN_SPAN_M));
  return {
    scale,
    offsetX: w / 2 - ((bounds.minX + bounds.maxX) / 2) * scale,
    offsetY: h / 2 + ((bounds.minY + bounds.maxY) / 2) * scale,
    at(p) {
      // Screen y grows downward, the frame's grows north.
      return [this.offsetX + p.x * this.scale, this.offsetY - p.y * this.scale];
    },
  };
}

const path = (points, place) =>
  points.map((p) => place.at(p).map((v) => v.toFixed(2)).join(",")).join(" ");

function drawFigure() {
  const host = el("turn-figure");
  if (!host || !live) return;
  const { figure, ghost } = live;
  host.innerHTML = "";
  if (!hasGeometry(figure)) return;
  const windUp = windUpOn();
  const w = figureWidth(host);
  const h = Math.round(Math.min(Math.max(w * 0.6, 200), 340));
  const frame = ghost && hasGeometry(ghost)
    ? unite(figureBounds(figure, windUp), figureBounds(ghost, windUp))
    : figureBounds(figure, windUp);
  if (!frame) return;
  const place = placer(frame, w, h);
  const root = svg("svg", {
    viewBox: `0 0 ${w} ${h}`, class: "tp-canvas", role: "img",
    "aria-label": spokenFigure(),
  }, host);
  svg("rect", { x: 0, y: 0, width: w, height: h, rx: 14, fill: C.surface }, root);

  drawGhost(root, ghost, place, windUp);
  drawContextTrack(root, figure, place, windUp);
  drawTurnLine(root, figure, place, windUp);
  drawSecondTicks(root, figure, place, windUp);
  drawTimeLabels(root, figure, place, windUp, w, h);
  drawAxisTick(root, figure, place, windUp);
  drawMarks(root, figure, place, windUp);
  drawPlayheadDot(root, figure, place, windUp);
  drawScaleBar(root, place, w, h);
  drawSpeedLegend(root, figure, windUp, w, h);
  drawOrientationMarks(root, figure, windUp, w);
  drawCallout(host, figure);

  root.addEventListener("click", (ev) => {
    const rect = root.getBoundingClientRect();
    const sx = ((ev.clientX - rect.left) / rect.width) * w;
    const sy = ((ev.clientY - rect.top) / rect.height) * h;
    if (!(place.scale > 0)) return;
    const x = (sx - place.offsetX) / place.scale;
    const y = (place.offsetY - sy) / place.scale;
    const point = pointNear(figure, x, y, windUp, TAP_TOLERANCE_P / place.scale);
    if (point) setPlayhead(point.rt);
  });
}

const unite = (a, b) => (a && b
  ? { minX: Math.min(a.minX, b.minX), minY: Math.min(a.minY, b.minY),
      maxX: Math.max(a.maxX, b.maxX), maxY: Math.max(a.maxY, b.maxY) }
  : (a || b));

/** The comparison turn, underneath everything, dashed, in the clean-jibe ink. A reference,
 *  not a second measurement. */
function drawGhost(root, ghost, place, windUp) {
  if (!ghost || !hasGeometry(ghost)) return;
  svg("polyline", { points: path(figurePoints(ghost, windUp), place), fill: "none",
                    stroke: C.clean, "stroke-opacity": 0.45, "stroke-width": 2,
                    "stroke-dasharray": "5 4", "stroke-linecap": "round",
                    "stroke-linejoin": "round" }, root);
}

/** The padded window, in neutral grey: where he came from and where he went. */
function drawContextTrack(root, figure, place, windUp) {
  svg("polyline", { points: path(figurePoints(figure, windUp), place), fill: "none",
                    stroke: C.track, "stroke-opacity": 0.45, "stroke-width": 2,
                    "stroke-linecap": "round", "stroke-linejoin": "round" }, root);
}

/**
 * The turn itself, thick, one short segment at a time so the speed can be read off the line.
 *
 * The ink is the speed ramp: five stops anchored so a standstill is the cold end, this
 * turn's entry speed is the middle stop, and 1.3 times the entry speed is the hot end. The
 * width ramps with it, so the line reads without colour too.
 */
function drawTurnLine(root, figure, place, windUp) {
  const points = figurePoints(figure, windUp).filter((p) => p.inTurn);
  if (points.length < 2) return;
  for (let i = 0; i < points.length - 1; i++) {
    const kn = (points[i].kn + points[i + 1].kn) / 2;
    const position = rampPosition(kn, figure.entryKn);
    svg("line", {
      x1: place.at(points[i])[0], y1: place.at(points[i])[1],
      x2: place.at(points[i + 1])[0], y2: place.at(points[i + 1])[1],
      stroke: rampColor(position), "stroke-width": 3 + 3 * Math.min(position * 2, 1),
      "stroke-linecap": "round",
    }, root);
  }
}

/** A tick across the line every whole second: evenly spaced ticks are a rider holding his
 *  speed, bunched ones are a rider who stopped. */
function drawSecondTicks(root, figure, place, windUp) {
  const points = figurePoints(figure, windUp).filter((p) => p.inTurn);
  if (points.length < 2) return;
  let next = Math.ceil(points[0].rt);
  for (const point of points) {
    if (point.rt < next) continue;
    next = Math.floor(point.rt) + 1;
    if (point.headingDeg === null || point.headingDeg === undefined) continue;
    const radians = ((point.headingDeg + 90) * Math.PI) / 180;
    const dx = Math.sin(radians) * 4;
    const dy = -Math.cos(radians) * 4;
    const [cx, cy] = place.at(point);
    svg("line", { x1: cx - dx, y1: cy - dy, x2: cx + dx, y2: cy + dy,
                  stroke: C.ink, "stroke-opacity": 0.45, "stroke-width": 1.2,
                  "stroke-linecap": "round" }, root);
  }
}

/** The clock, written on the path: a small number every five seconds, on the outside of the
 *  curve, across the whole drawn span. The pads are where the approach and the run-out are,
 *  and −5 is as much of an answer as +5. */
function drawTimeLabels(root, figure, place, windUp, w, h) {
  const points = figurePoints(figure, windUp);
  if (points.length < 2) return;
  const axisPoint = figure.axisRt === null || figure.axisRt === undefined
    ? null : pointAtRelative(figure, figure.axisRt, windUp);
  const axisAt = axisPoint ? place.at(axisPoint) : null;
  const reserved = [
    { x: w - 74, y: 0, w: 74, h: 34 },
    { x: 0, y: h - 28, w, h: 28 },
  ];
  for (const { rt, at } of pathLabels(figure, LABEL_EVERY_S, windUp)) {
    if (at.headingDeg === null || at.headingDeg === undefined) continue;
    const [cx, cy] = place.at(at);
    if (axisAt && Math.hypot(axisAt[0] - cx, axisAt[1] - cy) < 26) continue;
    const outward = ((at.headingDeg + 90 * outwardSign(at, points)) * Math.PI) / 180;
    const x = cx + Math.sin(outward) * LABEL_OFFSET_P;
    const y = cy - Math.cos(outward) * LABEL_OFFSET_P;
    if (reserved.some((r) => x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h)) {
      continue;
    }
    const text = svg("text", { x: x.toFixed(2), y: (y + 3).toFixed(2),
                               "text-anchor": "middle", "font-size": 9, "font-weight": 500,
                               fill: C.ink, "fill-opacity": 0.5 }, root);
    text.textContent = String(Math.round(rt));
  }
}

/** +1 when the outside of the curve is to the right of the heading, −1 when it is to the
 *  left. A board turning clockwise has its centre of rotation to the right. */
function outwardSign(point, points) {
  const index = points.findIndex((p) => p.rt === point.rt);
  if (index < 0) return 1;
  const ahead = Math.min(index + 2, points.length - 1);
  const behind = Math.max(index - 2, 0);
  const from = points[behind].headingDeg;
  const to = points[ahead].headingDeg;
  if (ahead === behind || from === null || from === undefined
      || to === null || to === undefined) return 1;
  const swept = deltaDeg(from, to);
  return swept > 0.5 ? -1 : 1;
}

/** Where the board went through the wind: a longer tick across the line, with the word
 *  `axis` beside it. A tick and not a third dot: the crossing is not a verdict, it is the
 *  instant the maneuver is named by. */
function drawAxisTick(root, figure, place, windUp) {
  if (figure.axisRt === null || figure.axisRt === undefined) return;
  const point = pointAtRelative(figure, figure.axisRt, windUp);
  if (!point || point.headingDeg === null || point.headingDeg === undefined) return;
  const radians = ((point.headingDeg + 90) * Math.PI) / 180;
  const dx = Math.sin(radians) * 9;
  const dy = -Math.cos(radians) * 9;
  const [cx, cy] = place.at(point);
  svg("line", { x1: cx - dx, y1: cy - dy, x2: cx + dx, y2: cy + dy, stroke: C.ink,
                "stroke-opacity": 0.55, "stroke-width": 1.8,
                "stroke-linecap": "round" }, root);
  const text = svg("text", { x: (cx + dx * 1.7).toFixed(2), y: (cy + dy * 1.7 + 3).toFixed(2),
                             "text-anchor": "middle", "font-size": 9, "font-weight": 600,
                             fill: C.ink, "fill-opacity": 0.55 }, root);
  text.textContent = "axis";
}

/** The two moments worth a mark: where the speed bottomed out, and how it ended. */
function drawMarks(root, figure, place, windUp) {
  if (figure.lowRt !== null && figure.lowRt !== undefined) {
    const low = pointAtRelative(figure, figure.lowRt, windUp);
    if (low) {
      const [cx, cy] = place.at(low);
      svg("circle", { cx, cy, r: 5, fill: "none", stroke: C.ink, "stroke-opacity": 0.75,
                      "stroke-width": 2 }, root);
    }
  }
  if (figure.endRt !== null && figure.endRt !== undefined) {
    const end = pointAtRelative(figure, figure.endRt, windUp);
    if (end) {
      const [cx, cy] = place.at(end);
      svg("circle", { cx, cy, r: 5.5, fill: OUTCOME_COLOR[figure.outcome] || C.ink3,
                      stroke: C.surface, "stroke-width": 1.5 }, root);
    }
  }
}

/** Where the strip's finger is: a ring rather than a dot, so it cannot be misread as an
 *  outcome. */
function drawPlayheadDot(root, figure, place, windUp) {
  if (playheadRt === null) return;
  const point = pointAtRelative(figure, playheadRt, windUp);
  if (!point) return;
  const [cx, cy] = place.at(point);
  svg("circle", { cx, cy, r: 11, fill: C.foil, "fill-opacity": 0.25 }, root);
  svg("circle", { cx, cy, r: 5, fill: C.foil, stroke: "#ffffff", "stroke-width": 2 }, root);
}

/** A bar and its number, bottom left. Without it the drawing has no size at all: the frame
 *  is fitted to the turn, so a tight pivot and a wide arc come out the same width. */
function drawScaleBar(root, place, w, h) {
  const metres = scaleBarM((w - INSET * 2) / place.scale);
  const length = metres * place.scale;
  if (!Number.isFinite(length) || length <= 8 || length >= w - INSET * 2) return;
  const y = h - INSET;
  svg("line", { x1: INSET, y1: y, x2: INSET + length, y2: y, stroke: C.ink,
                "stroke-opacity": 0.55, "stroke-width": 1.5 }, root);
  const text = svg("text", { x: INSET + length / 2, y: y - 4, "text-anchor": "middle",
                             "font-size": 10, fill: C.ink, "fill-opacity": 0.6 }, root);
  text.textContent = `${Math.round(metres)} m`;
}

/**
 * The ramp, with knots on it — bottom right, beside the scale bar.
 *
 * Two numbers make the whole line readable: the entry speed, which is the anchor and the
 * number the score is a ratio of, and the top of the bar, which is the fastest the rider
 * actually went. A turn that never beat its entry speed gets two labels instead of three.
 */
function drawSpeedLegend(root, figure, windUp, w, h) {
  const entryKn = figure.entryKn;
  if (!(entryKn >= MIN_REFERENCE_KN)) return;
  const drawn = figurePoints(figure, windUp).filter((p) => p.inTurn).map((p) => p.kn);
  const topKn = legendTopKn(entryKn, drawn.length ? Math.max(...drawn) : entryKn);
  const bottomKn = legendBottomKn(entryKn);
  const barWidth = 104;
  const barHeight = 5;
  const right = w - INSET;
  const left = right - barWidth;
  if (left <= INSET + 60) return;
  const y = h - INSET - barHeight;

  const id = "tp-ramp";
  const defs = svg("defs", {}, root);
  const grad = svg("linearGradient", { id, x1: "0", y1: "0", x2: "1", y2: "0" }, defs);
  for (let i = 0; i <= 8; i++) {
    const fraction = i / 8;
    svg("stop", { offset: fraction,
                  "stop-color": rampColorFor(bottomKn + (topKn - bottomKn) * fraction,
                                             entryKn) }, grad);
  }
  svg("rect", { x: left, y, width: barWidth, height: barHeight, rx: barHeight / 2,
                fill: `url(#${id})` }, root);

  const label = (value, x, anchor) => {
    const text = svg("text", { x, y: y - 3, "text-anchor": anchor, "font-size": 9,
                               fill: C.ink, "fill-opacity": 0.6 }, root);
    text.textContent = value;
    return text;
  };
  label(nf(bottomKn, 1), left, "start");
  label(`${nf(topKn, 1)} kn`, right, "end");
  const entryFraction = (entryKn - bottomKn) / Math.max(topKn - bottomKn, 0.001);
  if (entryFraction < 0.88) {
    const x = left + barWidth * entryFraction;
    svg("line", { x1: x, y1: y - 1, x2: x, y2: y + barHeight + 1, stroke: C.ink,
                  "stroke-opacity": 0.45, "stroke-width": 1 }, root);
    label(nf(entryKn, 1), x, "middle");
  }
}

/**
 * Both references, always: a needle to north labelled `N`, and an arrow labelled `wind`
 * blowing from its tail toward its head.
 *
 * A jibe is read against both, which way the water was going and which way home is. In wind
 * up the wind arrow points straight down the frame and `N` swings with the rotation; in
 * north up `N` points up the frame and the wind arrow swings.
 */
function drawOrientationMarks(root, figure, windUp, w) {
  const y = INSET + 10;
  const wind = figure.windDirDeg;
  arrow(root, w - INSET - 10, y, windUp ? -(wind ?? 0) : 0, "N");
  if (wind !== null && wind !== undefined) {
    // The heading the wind blows *toward*: the tail is where it comes from.
    arrow(root, w - INSET - 44, y, windUp ? 180 : wind + 180, "wind");
  }
}

function arrow(root, cx, cy, rotationDeg, text) {
  const g = svg("g", { transform: `rotate(${rotationDeg.toFixed(2)} ${cx} ${cy})` }, root);
  svg("path", { d: `M${cx},${cy - 9} L${cx - 4.5},${cy + 5} L${cx},${cy + 1.5} `
                   + `L${cx + 4.5},${cy + 5} Z`,
                fill: C.ink, "fill-opacity": 0.5 }, g);
  const node = svg("text", { x: cx, y: cy + 16, "text-anchor": "middle", "font-size": 9,
                             "font-weight": 600, fill: C.ink, "fill-opacity": 0.55 }, root);
  node.textContent = text;
}

/** What the rider was doing at the instant under the playhead: four readings, top left.
 *  Absent until something is scrubbed — the drawing's own marks are the resting state. */
function drawCallout(host, figure) {
  if (playheadRt === null) return;
  const point = pointAtRelative(figure, playheadRt, false);
  if (!point) return;
  const parts = [`${point.rt >= 0 ? "+" : ""}${nf(point.rt, 1)} s`, `${nf(point.kn, 1)} kn`];
  if (point.headingDeg !== null && point.headingDeg !== undefined) {
    parts.push(`${nf(point.headingDeg, 0)}° hdg`);
  }
  if (figure.windDirDeg !== null && figure.windDirDeg !== undefined
      && point.headingDeg !== null && point.headingDeg !== undefined) {
    parts.push(`${nf(Math.abs(deltaDeg(figure.windDirDeg, point.headingDeg)), 0)}° TWA`);
  }
  const box = document.createElement("div");
  box.className = "tp-callout";
  box.textContent = parts.join(" · ");
  host.appendChild(box);
}

function spokenFigure() {
  if (!live) return "";
  const { figure, turn, ghost } = live;
  const windUp = windUpOn();
  const parts = [];
  if (turn) {
    parts.push(typeLabel(turn.type) + " drawn " + (windUp ? "wind up" : "north up"));
    parts.push(`${nf(turn.entryKn, 1)} knots in, ${nf(turn.minKn, 1)} at the low point `
               + `after ${nf(figure.speed.minRt, 0)} seconds, ${nf(turn.exitKn, 1)} out`);
    parts.push(`${nf(figure.durationS, 0)} seconds long, ${nf(turn.radiusM, 0)} metre radius`);
    parts.push(OUTCOME_LABEL[turn.outcome] || turn.outcome);
  } else {
    parts.push("Flight ending, drawn " + (windUp ? "wind up" : "north up"));
  }
  if (figure.windDirDeg !== null && figure.windDirDeg !== undefined) {
    parts.push(`wind from ${nf(figure.windDirDeg, 0)} degrees`);
  }
  if (figure.axisRt !== null && figure.axisRt !== undefined) {
    parts.push(`through the wind axis ${nf(figure.axisRt, 0)} seconds in`);
  }
  if (ghost && ghostOn()) parts.push("compared with your best clean jibe, dashed");
  return parts.join(", ");
}

/* --------------------------------------------------------------------- strips */

const STRIP_PAD = { left: 44, right: 14, top: 18, bottom: 26 };

/** The shared frame every strip is drawn in: one x domain, one scrub surface, one playhead
 *  rule. Three plots that did not share them would be three clocks. */
function stripFrame(hostId, domain, height, label) {
  const host = el(hostId);
  if (!host) return null;
  host.innerHTML = "";
  const w = figureWidth(host);
  const h = height;
  const root = svg("svg", { viewBox: `0 0 ${w} ${h}`, class: "tp-canvas", role: "img",
                            "aria-label": label }, host);
  svg("rect", { x: 0, y: 0, width: w, height: h, rx: 10, fill: C.surface }, root);
  const plot = { x0: STRIP_PAD.left, x1: w - STRIP_PAD.right,
                 y0: STRIP_PAD.top, y1: h - STRIP_PAD.bottom };
  const X = (t) => plot.x0 + ((t - domain[0]) / (domain[1] - domain[0]))
    * (plot.x1 - plot.x0);
  root.addEventListener("pointerdown", (ev) => scrub(ev, root, w, plot, domain));
  root.addEventListener("pointermove", (ev) => {
    if (ev.buttons) scrub(ev, root, w, plot, domain);
  });
  return { root, w, h, plot, X };
}

function scrub(ev, root, w, plot, domain) {
  const rect = root.getBoundingClientRect();
  const sx = ((ev.clientX - rect.left) / rect.width) * w;
  const fraction = (sx - plot.x0) / (plot.x1 - plot.x0);
  const rt = domain[0] + Math.min(Math.max(fraction, 0), 1) * (domain[1] - domain[0]);
  setPlayhead(rt);
}

function stripAxis(frame, domain, yLabel, xLabel) {
  const { root, plot, X } = frame;
  svg("line", { x1: plot.x0, y1: plot.y1, x2: plot.x1, y2: plot.y1, stroke: C.grid,
                "stroke-width": 1 }, root);
  for (let t = Math.ceil(domain[0] / 5) * 5; t <= domain[1]; t += 5) {
    const x = X(t);
    svg("line", { x1: x, y1: plot.y1, x2: x, y2: plot.y1 + 3, stroke: C.grid,
                  "stroke-width": 1 }, root);
    const text = svg("text", { x, y: plot.y1 + 14, "text-anchor": "middle", "font-size": 9,
                               fill: C.ink3 }, root);
    text.textContent = String(Math.round(t));
  }
  const xt = svg("text", { x: plot.x1, y: frame.h - 3, "text-anchor": "end", "font-size": 9,
                           fill: C.ink3 }, root);
  xt.textContent = xLabel;
  const yt = svg("text", { x: 4, y: plot.y0 - 6, "text-anchor": "start", "font-size": 9,
                           fill: C.ink3 }, root);
  yt.textContent = yLabel;
}

function stripPlayhead(frame) {
  if (playheadRt === null) return;
  const { root, plot, X } = frame;
  svg("line", { x1: X(playheadRt), y1: plot.y0, x2: X(playheadRt), y2: plot.y1,
                stroke: C.foil, "stroke-width": 1.5 }, root);
}

function band(frame, from, to, tint, opacity, caption) {
  const { root, plot, X } = frame;
  const x0 = X(from);
  const x1 = X(to);
  if (!(x1 > x0)) return;
  svg("rect", { x: x0, y: plot.y0, width: x1 - x0, height: plot.y1 - plot.y0, fill: tint,
                "fill-opacity": opacity }, root);
  if (!caption) return;
  const text = svg("text", { x: (x0 + x1) / 2, y: plot.y1 - 3, "text-anchor": "middle",
                             "font-size": 9, fill: C.ink3 }, root);
  text.textContent = caption;
}

/**
 * The turn's speed, on the turn's own clock, with the sweep shaded and the three speeds the
 * score is made of labelled on it.
 *
 * The session's speed chart cannot answer this: it is thinned over the whole afternoon, so
 * the dip that IS the turn is exactly what the thinning removes.
 */
function drawSpeedStrip() {
  if (!live) return;
  const { figure, ghost, turn, end } = live;
  const domain = figure.timeDomain;
  const config = doc.golden.config;
  const frame = stripFrame("turn-strip-speed", domain, 170, spokenSpeed());
  if (!frame) return;
  const { root, plot, X } = frame;
  const points = figure.points;
  const ceiling = Math.max((points.length ? Math.max(...points.map((p) => p.kn))
                                          : figure.entryKn) * 1.15, 5);
  const Y = (kn) => plot.y1 - (kn / ceiling) * (plot.y1 - plot.y0);

  const entryS = cfg(config, "entrySpeedWindow");
  const outcomeS = cfg(config, "turnOutcomeLookahead");
  const exitRt = turn ? figure.speed.exitRt : 0;

  // Every window the engine reads, drawn and named.
  band(frame, -entryS, 0, C.ink2, 0.10, "entry");
  if (turn) band(frame, 0, exitRt, C.foil, 0.14, "sweep");
  band(frame, exitRt, exitRt + outcomeS, C.warn, 0.08, "outcome");
  if (figure.speed.recoverRt !== null && figure.speed.recoverRt > exitRt) {
    band(frame, exitRt, figure.speed.recoverRt, C.good, 0.10, null);
  }
  if (end) band(frame, 0, figure.windows.evidenceS, C.ink2, 0.06, "evidence");

  if (ghost && hasGeometry(ghost)) {
    svg("polyline", { points: ghost.points.map((p) => `${X(p.rt)},${Y(p.kn)}`).join(" "),
                      fill: "none", stroke: C.clean, "stroke-opacity": 0.7,
                      "stroke-width": 1.2, "stroke-dasharray": "4 3" }, root);
  }
  svg("polyline", { points: points.map((p) => `${X(p.rt)},${Y(p.kn)}`).join(" "),
                    fill: "none", stroke: C.series, "stroke-width": 1.8,
                    "stroke-linejoin": "round" }, root);

  const marks = turn
    ? [["in", figure.speed.entryRt, figure.speed.entryKn],
       ["low", figure.speed.minRt, figure.speed.minKn],
       ["out", figure.speed.exitRt, figure.speed.exitKn]]
    : [["in", figure.speed.entryRt, figure.speed.entryKn],
       ["low", figure.speed.lowRt, figure.speed.lowKn],
       ["out", figure.speed.recoverRt, figure.speed.outKn]];
  const gap = Math.max(1.6, (domain[1] - domain[0]) / 8);
  const lowNearIn = marks[1][1] !== null && Math.abs(marks[1][1] - marks[0][1]) < gap;
  for (const [name, rt, kn] of marks) {
    if (rt === null || rt === undefined || kn === null || kn === undefined) continue;
    const below = name === "out"
      ? (marks[1][1] !== null && Math.abs(rt - marks[1][1]) < gap && !lowNearIn)
      : (name === "low" ? lowNearIn : false);
    svg("line", { x1: X(rt), y1: plot.y0, x2: X(rt), y2: plot.y1, stroke: C.ink2,
                  "stroke-opacity": 0.5, "stroke-width": 1,
                  "stroke-dasharray": "2 3" }, root);
    const text = svg("text", { x: X(rt), y: below ? plot.y1 - 3 : plot.y0 - 5,
                               "text-anchor": "middle", "font-size": 9, fill: C.ink2 }, root);
    text.textContent = `${name} ${nf(kn, 1)}`;
    svg("circle", { cx: X(rt), cy: Y(kn), r: 3, fill: C.series }, root);
  }

  if (figure.axisRt !== null && figure.axisRt !== undefined) {
    svg("line", { x1: X(figure.axisRt), y1: plot.y0, x2: X(figure.axisRt), y2: plot.y1,
                  stroke: C.ink, "stroke-opacity": 0.35, "stroke-width": 1,
                  "stroke-dasharray": "3 3" }, root);
    const text = svg("text", { x: X(figure.axisRt), y: plot.y0 - 5, "text-anchor": "middle",
                               "font-size": 9, fill: C.ink, "fill-opacity": 0.55 }, root);
    text.textContent = "axis";
  }

  // Where the quiet tail closes: the last instant a touchdown or a fall still costs this
  // jibe its star. Drawn only where it fits inside the run-out.
  const quietS = turn ? cfg(config, "turnCleanQuietS") : null;
  if (quietS && exitRt + quietS <= domain[1]) {
    const rt = exitRt + quietS;
    svg("line", { x1: X(rt), y1: plot.y0, x2: X(rt), y2: plot.y1, stroke: C.clean,
                  "stroke-opacity": 0.55, "stroke-width": 1,
                  "stroke-dasharray": "2 4" }, root);
    const text = svg("text", { x: X(rt), y: plot.y1 - 3, "text-anchor": "middle",
                               "font-size": 9, fill: C.clean }, root);
    text.textContent = "quiet";
  }

  // The strokes, along the floor of the plot. A span, not a point: the engine stores the
  // first stroke, the last and how many, never the individual times.
  for (const tick of pumpTicks()) {
    const x0 = X(tick.startRt);
    const x1 = Math.max(X(tick.endRt), x0 + 2);
    svg("rect", { x: x0, y: plot.y1 - 6, width: x1 - x0, height: 6, fill: C.pump,
                  "fill-opacity": 0.75 }, root);
    const text = svg("text", { x: (x0 + x1) / 2, y: plot.y1 - 9, "text-anchor": "middle",
                               "font-size": 9, fill: C.pump }, root);
    text.textContent = strokesText(tick.strokes);
  }

  stripAxis(frame, domain, "kn", open.kind === "turn" ? "s from the turn" : "s from the end");
  stripPlayhead(frame);
}

/** The pumping efforts this event owns, as spans on its own clock. */
function pumpTicks() {
  const g = doc.golden;
  const episodes = g.pumpEpisodes || [];
  if (open.kind === "turn") {
    const turn = g.turns[open.index];
    const to = turn.endTs + turn.outcomeWindowS;
    return episodes
      .filter((e) => e.turnIndex === open.index || (e.endTs >= turn.ts && e.startTs <= to))
      .map((e) => ({ startRt: e.startTs - turn.ts, endRt: e.endTs - turn.ts,
                     strokes: e.strokes }));
  }
  const end = g.flightEnds[open.index];
  const to = end.ts + cfg(g.config, "turnOutcomeLookahead");
  return episodes
    .filter((e) => e.endTs >= end.ts && e.startTs <= to)
    .map((e) => ({ startRt: e.startTs - end.ts, endRt: e.endTs - end.ts,
                   strokes: e.strokes }));
}

const strokesText = (n) => `${n} ${n === 1 ? "stroke" : "strokes"}`;

/**
 * The heading, unwrapped, on the same clock: true wind angle where the wind is known, a
 * compass heading where it is not.
 *
 * It is the second half of what a turn is. The speed strip says what the turn cost; this
 * says what the board was actually doing, and the axis rule lands where the two agree.
 */
function drawHeadingStrip() {
  if (!live) return;
  const { figure } = live;
  const angles = sliceAngles(figure.points, figure.windDirDeg);
  const host = el("turn-strip-heading");
  if (!host) return;
  const title = angles.isTwa ? "Wind angle" : "Heading";
  if (angles.points.length < 2) {
    host.innerHTML = `<p class="muted small">${esc(title)}. No usable bearings through this
      window. The steps were shorter than the receiver's own scatter.</p>`;
    return;
  }
  const domain = figure.timeDomain;
  const frame = stripFrame("turn-strip-heading", domain, 130,
                           `${title} through the window`);
  if (!frame) return;
  const { root, plot, X } = frame;
  const [lo, hi] = angleDomain(angles);
  const Y = (deg) => plot.y1 - ((deg - lo) / (hi - lo)) * (plot.y1 - plot.y0);

  if (live.turn) band(frame, 0, figure.speed.exitRt, C.foil, 0.14, "sweep");
  svg("polyline", { points: angles.points.map((p) => `${X(p.rt)},${Y(p.deg)}`).join(" "),
                    fill: "none", stroke: C.ink2, "stroke-width": 1.6,
                    "stroke-linejoin": "round" }, root);
  if (figure.axisRt !== null && figure.axisRt !== undefined) {
    svg("line", { x1: X(figure.axisRt), y1: plot.y0, x2: X(figure.axisRt), y2: plot.y1,
                  stroke: C.ink, "stroke-opacity": 0.35, "stroke-width": 1,
                  "stroke-dasharray": "3 3" }, root);
    const text = svg("text", { x: X(figure.axisRt), y: plot.y0 - 5, "text-anchor": "middle",
                               "font-size": 9, fill: C.ink, "fill-opacity": 0.55 }, root);
    text.textContent = "axis";
  }
  stripAxis(frame, domain, angles.isTwa ? "TWA °" : "heading °",
            open.kind === "turn" ? "s from the turn" : "s from the end");
  stripPlayhead(frame);
}

/**
 * Whether the foil was carrying, through the window.
 *
 * The engine's flights are the answer and the only answer, so this reads `view.flights` and
 * re-derives nothing. It is the one strip the phone does not draw: on the phone the same
 * fact is the colour of the session map's track, which a page this size has no room for.
 */
function drawFoilStrip() {
  if (!live) return;
  const { figure } = live;
  const zeroT = open.kind === "turn"
    ? doc.golden.turns[open.index].ts : doc.golden.flightEnds[open.index].ts;
  const domain = figure.timeDomain;
  const spans = foilSpans(doc.view, zeroT, domain);
  const words = lexicon(doc.golden.config?.discipline);
  const frame = stripFrame("turn-strip-foil", domain, 58, "Foil state through the window");
  if (!frame) return;
  const { root, plot, X } = frame;
  for (const span of spans) {
    const x0 = X(span.startRt);
    const x1 = X(span.endRt);
    if (!(x1 > x0)) continue;
    svg("rect", { x: x0, y: plot.y0, width: x1 - x0, height: Math.max(plot.y1 - plot.y0, 8),
                  fill: span.flying ? C.foil : C.track, "fill-opacity": span.flying ? 0.85 : 0.35,
                  rx: 2 }, root);
  }
  stripAxis(frame, domain, "on the foil",
            open.kind === "turn" ? "s from the turn" : "s from the end");
  stripPlayhead(frame);
  const legend = document.createElement("p");
  legend.className = "muted small";
  legend.textContent = `Solid is flying. Pale is ${words.offTheFoil}.`;
  el("turn-strip-foil").appendChild(legend);
}

function spokenSpeed() {
  if (!live) return "";
  const { figure, turn } = live;
  if (!turn) {
    return `Speed through the flight end. ${nf(figure.speed.entryKn, 1)} knots coming in.`;
  }
  return `Speed through the turn. ${nf(turn.entryKn, 1)} knots coming in. Down to `
    + `${nf(turn.minKn, 1)} after ${nf(figure.speed.minRt, 0)} seconds. `
    + `${nf(turn.exitKn, 1)} knots at the exit.`;
}

/* -------------------------------------------------------------------- numbers */

const scoreText = (score) => String(Math.round(score * 100));

/** The entry tack, always spelled out as an entry. Never left or right. */
function sideLabel(side) {
  switch (side) {
    case "port": return "port entry";
    case "starboard": return "starboard entry";
    default: return "entry tack unknown";
  }
}

/** The direction the **board rotated**, never the tack it was entered on. */
function rotationLabel(direction) {
  switch (direction) {
    case "starboard": return "clockwise";
    case "port": return "counter-clockwise";
    default: return "unknown";
  }
}

const cell = (label, value) =>
  `<div class="tp-cell"><span>${esc(label)}</span><b>${esc(value)}</b></div>`;

const chip = (text, tint) =>
  `<span class="tp-chip"><i style="background:${tint}"></i>${esc(text)}</span>`;

function turnNumbers(turn, figure) {
  const g = doc.golden;
  const chips = [chip(OUTCOME_LABEL[turn.outcome] || turn.outcome,
                      OUTCOME_COLOR[turn.outcome] || C.ink3)];
  if (turn.clean) chips.push(chip("clean", C.clean));
  else {
    const why = notCleanText(turn);
    if (why) chips.push(chip(why, C.ink3));
  }
  if (turn.pumped) {
    const strokes = pumpStrokes(turn);
    chips.push(chip(strokes === null ? "pumped out"
                                     : `pumped out · ${strokesText(strokes)}`, C.pump));
  }
  if (turn.submerged) {
    const seconds = submersionS(turn);
    chips.push(chip(seconds === null ? "wrist under"
                                     : `wrist under ${nf(seconds, 0)} s`, C.splash));
  }
  const why = outcomeText(turn, g.config?.turnPumpedMarginalSpeed, g.config?.discipline);
  const axis = axisLine(turn);
  return `<div class="tp-numbers">
    <p class="tp-speeds"><b>${nf(turn.entryKn, 1)}</b> <span>in</span> →
      <b>${nf(turn.minKn, 1)}</b> <span>low</span> →
      <b>${nf(turn.exitKn, 1)}</b> <span>out</span> <span>kn</span></p>
    <p class="tp-held">held ${scoreText(turn.score)} % of entry speed</p>
    <div class="tp-grid">
      ${cell("Stopped", `${nf(turn.stoppedS, 0)} s`)}
      ${cell("Off foil", `${nf(turn.offFoilS, 0)} s`)}
      ${cell("Radius", `${nf(turn.radiusM, 0)} m`)}
      ${cell("Heading change", `${nf(Math.abs(turn.netDeg), 0)}°`)}
      ${cell("Entry tack", sideLabel(turn.side))}
      ${cell("Rotation", rotationLabel(turn.direction))}
    </div>
    ${axis ? `<p class="muted small">${esc(axis)}</p>` : ""}
    <p class="tp-chips">${chips.join(" ")}</p>
    ${why ? `<p class="muted small">${esc(why)}</p>` : ""}
  </div>`;
}

function endNumbers(end, figure) {
  const chips = [chip(endOutcomeLabel(end.outcome) + (end.borderline ? " (borderline)" : ""),
                      OUTCOME_COLOR[end.outcome] || C.ink3)];
  if (end.pumped) chips.push(chip("pumped out", C.pump));
  if (end.submerged) chips.push(chip("wrist under", C.splash));
  const back = figure.speed.outKn === null
    ? "Never back up to flying speed inside the window."
    : `Back to flying speed ${nf(figure.speed.recoverRt, 0)} s after the end.`;
  const dash = (v) => (v === null || v === undefined ? "—" : nf(v, 1));
  return `<div class="tp-numbers">
    <p class="tp-speeds"><b>${nf(figure.speed.entryKn, 1)}</b> <span>in</span> →
      <b>${dash(figure.speed.lowKn)}</b> <span>low</span> →
      <b>${dash(figure.speed.outKn)}</b> <span>out</span> <span>kn</span></p>
    <p class="tp-held">${esc(back)}</p>
    <div class="tp-grid">
      ${cell("Stopped", `${nf(end.stoppedS, 0)} s`)}
      ${cell("Off foil", `${nf(end.offFoilS, 0)} s`)}
      ${cell("Flight", `#${end.flightIndex + 1}`)}
      ${cell("Evidence", `${nf(end.windowS, 0)} s`)}
    </div>
    <p class="tp-chips">${chips.join(" ")}</p>
    <p class="muted small">${esc(endOutcomeText(end))}</p>
  </div>`;
}

/** The outcome, then the evidence that made it, in the order the ladder settles them. */
function endOutcomeText(end) {
  if (end.truncated || end.outcome === "unknown") {
    return "the recording ended, not the flight";
  }
  const parts = [endOutcomeLabel(end.outcome) + (end.borderline ? " (borderline)" : "")];
  if (Math.round(end.stoppedS) >= 1) parts.push(`stopped ${nf(end.stoppedS, 0)} s`);
  else if (Math.round(end.offFoilS) >= 1) {
    parts.push(`off the foil ${nf(end.offFoilS, 0)} s`);
  }
  if (end.submerged) parts.push("wrist under");
  if (end.pumped) parts.push("pumped out");
  return parts.join(" · ");
}

/** "Through the axis · 87° before, 72° after" — the crossing, in integers. */
function axisLine(turn) {
  if (!Number.isFinite(turn.axisBeforeDeg) || !Number.isFinite(turn.axisAfterDeg)) return null;
  return `Through the axis · ${nf(turn.axisBeforeDeg, 0)}° before, `
    + `${nf(turn.axisAfterDeg, 0)}° after`;
}

/** Why this jibe has no star, where the answer is not already on the page. */
function notCleanText(turn) {
  switch (turn.cleanBlockedBy) {
    case "quiet_flight_end": {
      const seconds = secondsToLoss(turn);
      return seconds === null ? "not clean · touched down after"
                              : `not clean · touched down ${seconds} s after`;
    }
    case "quiet_off_foil": return "not clean · off the foil after";
    case "quiet_submerged": return "not clean · wrist under after";
    case "axis_after":
      return Number.isFinite(turn.axisAfterDeg)
        ? `not clean · carried ${nf(turn.axisAfterDeg, 0)}° past the axis`
        : "not clean · short of the axis";
    default: return null;
  }
}

/** The first touchdown or fall inside the quiet tail, which is the end the engine's own rule
 *  would have found. Nothing found means the plainer wording, never a fabricated number. */
function secondsToLoss(turn) {
  const quietS = cfg(doc.golden.config, "turnCleanQuietS");
  const found = (doc.golden.flightEnds || []).find(
    (e) => e.ts > turn.endTs && e.ts <= turn.endTs + quietS
      && (e.outcome === "touchdown" || e.outcome === "fell_in"));
  return found ? Math.round(found.ts - turn.endTs) : null;
}

/** The strokes the rider put in to get out of one turn, or null where the analysis does not
 *  know. Never 0: an absence is not a count. */
function pumpStrokes(turn) {
  const episodes = doc.golden.pumpEpisodes || [];
  const claimed = episodes.filter((e) => e.turnIndex === open.index);
  const pool = claimed.length ? claimed
    : episodes.filter((e) => e.endTs >= turn.ts
                        && e.startTs <= turn.endTs + turn.outcomeWindowS);
  if (!pool.length) return null;
  const strokes = pool.reduce((t, e) => t + e.strokes, 0);
  return strokes > 0 ? strokes : null;
}

/** How long the wrist was under in this turn. Null under 1 s: at 1 Hz that is a single
 *  sample, and "0 s" would read as a measurement. */
function submersionS(turn) {
  const owned = (doc.golden.submersions || []).filter((s) => s.turnIndex === open.index);
  if (!owned.length) return null;
  const longest = Math.max(...owned.map((s) => s.durationS));
  return Math.round(longest) >= 1 ? longest : null;
}

/* ----------------------------------------------------------------- the sentence */

const FAST_SCORE = 0.85;
const SLOW_SCORE = 0.7;

/** What a rider calls the middle of this turn. */
function midPointWord(type) {
  switch (type) {
    case "jibe": return "downwind point";
    case "tack": return "head-to-wind";
    default: return "middle of the turn";
  }
}

const kn = (v) => `${nf(v, 1)} kn`;
const pctOf = (score) => `${scoreText(score)} %`;
const secs = (v) => `${nf(v, 0)} s`;

/**
 * One sentence under the numbers, in the coach's register: it says what happened, it never
 * invents a measurement, and it never blames.
 *
 * The ladder is the phone's, rung for rung (`TurnCoach.rule`): the outcome is asked first
 * and the score second, which is what keeps "clean and fast" honest.
 */
function coachLine(turn, figure) {
  const mid = midPointWord(turn.type);
  const fast = turn.success && turn.score >= FAST_SCORE;
  const lateMin = figure.midRotationRt === null || figure.midRotationRt === undefined
    ? null : figure.speed.minRt >= figure.midRotationRt;

  if (turn.outcome === "fell_in") {
    return fast
      ? `You held ${pctOf(turn.score)} of your entry speed right round. `
        + "It still ended in the water."
      : `This one ended in the water. ${kn(turn.entryKn)} coming in, `
        + `${kn(turn.minKn)} at the low point.`;
  }
  if (turn.submerged) {
    return "The barometer saw your wrist go under here. The foil was gone for a moment. "
      + `${kn(turn.entryKn)} in, ${kn(turn.minKn)} at the low point.`;
  }
  if (turn.pumped) {
    const strokes = pumpStrokes(turn);
    const opener = strokes === null
      ? "You pumped this one back out."
      : `You pumped this one back out in ${strokesText(strokes)}.`;
    return turn.offFoilS > 0
      ? `${opener} ${secs(turn.offFoilS)} off the foil before it flew again.`
      : `${opener} It was flying again straight away.`;
  }
  if (turn.outcome === "touchdown") {
    return lateMin === true
      ? `The foil touched down on the way out. You held ${kn(turn.entryKn)} into the `
        + `${mid} and lost it after.`
      : `The foil touched down before the ${mid}. The speed was already at `
        + `${kn(turn.minKn)} going in.`;
  }
  switch (turn.cleanBlockedBy) {
    case "quiet_flight_end":
      return `You rode the turn itself and held ${pctOf(turn.score)} of your entry speed. `
        + "The foil went a few seconds later, so this one is not clean.";
    case "quiet_off_foil":
      return "You rode the turn, then the foil dropped again on the way out. "
        + "This one does not count as clean.";
    case "quiet_submerged":
      return `You held ${pctOf(turn.score)} of your entry speed through the turn. `
        + "The barometer then saw your wrist go under. This one is not clean.";
    case "axis_after":
      return `You held ${pctOf(turn.score)} of your entry speed. `
        + "The board did not come far enough past the wind axis. This one is not clean.";
    default: break;
  }
  if (fast) {
    return `Clean, and you barely slowed. You held ${pctOf(turn.score)} of your entry speed `
      + "all the way round.";
  }
  if (turn.outcome === "flew_through" && turn.score < SLOW_SCORE) {
    return `You flew all the way through, and it cost you speed. ${kn(turn.entryKn)} in, `
      + `${kn(turn.minKn)} at the low point.`;
  }
  if (lateMin === false) {
    return `The speed went before the ${mid}. You were down to `
      + `${kn(figure.speed.minKn)} with the turn still to come.`;
  }
  if (lateMin === true) {
    return `You held it into the ${mid}. The speed went on the way out, down to `
      + `${kn(figure.speed.minKn)}.`;
  }
  return `${kn(turn.entryKn)} in, ${kn(turn.minKn)} at the low point. You held `
    + `${pctOf(turn.score)} of your entry speed.`;
}

/* ------------------------------------------------------------------- footnote */

const PATH_NUMBERS = "The numbers along the path are every five.";
const NORTH_AND_WIND = "North and the wind are marked top right.";
const outcomeWindowLine = (seconds) =>
  `"Outcome" is the ${seconds} s the verdict is read from.`;

function footnote(turn, end, figure) {
  const config = doc.golden.config;
  const lead = Math.round(figure.padBeforeS);
  const run = Math.round(figure.padAfterS);
  const entryS = Math.round(cfg(config, "entrySpeedWindow"));
  const outcomeS = Math.round(cfg(config, "turnOutcomeLookahead"));
  const minLagS = Math.round(cfg(config, "minSpeedLag"));
  const quietS = cfg(config, "turnCleanQuietS");
  const lines = [];

  if (turn) {
    lines.push(`The drawing is ${lead} s before the sweep and ${run} s after it. `
      + `Ticks are one second apart. ${PATH_NUMBERS}`);
    lines.push("The line is coloured by speed on the ramp at the foot of the picture. "
      + "Cold is a standstill, teal is the speed you came in at, hot is above it. "
      + NORTH_AND_WIND);
    lines.push("Tap the drawing for the reading at that sample. The strips follow it.");
    lines.push("Score is how much of your entry speed you held through the turn.");
    lines.push("Speed here is the manoeuvre channel the verdict was scored on, derived from "
      + "position. The GPS Doppler speed the records use is smoothed through a turn. "
      + "It would read lower at the low point.");
    lines.push(`The bands under the strip are the engine's windows. "Entry" is the ${entryS} `
      + `s before the sweep, where the entry speed is the maximum. "Sweep" is where the `
      + `heading turned. The low point is searched to ${minLagS} s past the sweep, so it can `
      + `sit after "out". ${outcomeWindowLine(outcomeS)} `
      + "The lighter band inside it ends where you were flying again.");
    if (quietS > 0) {
      lines.push(`A clean jibe also needs ${Math.round(quietS)} s after the sweep with no `
        + "touchdown, fall or wrist under.");
    }
    if (turn.axisTs !== null && turn.axisTs !== undefined) {
      lines.push('The tick marked "axis" is the moment the board went through the wind axis. '
        + "That is dead downwind on a jibe, head to wind on a tack. "
        + "The turn is named after that crossing.");
    }
  } else {
    lines.push(`The drawing is ${lead} s before the end and ${run} s after it. `
      + "The thick, coloured part is the flight. "
      + `Everything past the dot is already off the foil. Ticks are one second apart. `
      + `${PATH_NUMBERS} ${NORTH_AND_WIND}`);
    lines.push(`The bands are the engine's windows. "Entry" is the ${entryS} s the flight `
      + `was ending at. ${outcomeWindowLine(outcomeS)} `
      + '"Evidence" is how much gap-free recording there actually was.');
    lines.push('Only "low" is the engine\'s. It is the slowest sample of the off-foil run, '
      + "placed where this window comes nearest it.");
    lines.push('"In" is the fastest sample of the entry window. "Out" is where the speed came '
      + "back to the engine's flying-again threshold. Both are read off the drawn line. "
      + "A flight end record holds no entry or exit speed of its own.");
    lines.push("Speed here is the manoeuvre channel, derived from position. "
      + "The GPS Doppler speed the records use is smoothed. It would read differently.");
    if (end.borderline) {
      lines.push('"Borderline" means the stop ran past the touchdown limit without reaching '
        + "the fall one.");
    }
  }
  if (doc.view && doc.view.stride > 1) {
    lines.push(`This recording is long, so the browser holds every ${doc.view.stride}th `
      + "sample. The drawing and the strips are cut from those.");
  }
  const at = turn
    ? clockAt(doc.meta, turn.ts) : clockAt(doc.meta, doc.golden.flightEnds[open.index].ts);
  lines.push(`It happened at ${at}.`);
  return `<div class="tp-footnote">${lines.map((l) => `<p>${esc(l)}</p>`).join("")}</div>`;
}

/* ------------------------------------------------------------------- redrawing */

/** The figures are sized to their container, so a rotation or a resize has to lay them out
 *  again. Exported for js/app.js's debounced resize handler, and a no-op when closed. */
export function redrawTurnPage() {
  if (!open || !doc || !live) return;
  drawFigure();
  drawSpeedStrip();
  drawHeadingStrip();
  drawFoilStrip();
}

window.addEventListener("resize", () => {
  if (open) redrawTurnPage();
});
