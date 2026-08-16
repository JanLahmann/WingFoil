/* The interactive session view: the track map and the speed strip, and the one playhead
 * they share.
 *
 * Modelled on the iOS app's Session Detail (ios/WingFoil/Features/SessionDetail):
 *
 *   - ONE playhead. Dragging the speed strip moves a marker along the track and vice
 *     versa, because the two figures are two readings of the same session and a position
 *     that exists in one but not the other is a lie (iOS: ReplayScrubber + TrackMapView).
 *   - Legend chips are the filter. Tapping a chip hides that category on the map *and* in
 *     the chart (iOS: MapLegendView). A category this session has none of is drawn
 *     subdued and inert rather than removed, so the vocabulary is always visible.
 *   - Event layers over the outcome markers the figures already had: pumping runs,
 *     takeoff attempts (both halves — the arrow that flew and the red u-turn that did
 *     not), and the barometer's submersion evidence.
 *   - Time-axis zoom on the strip (wheel/trackpad, or a two-finger pinch), with the
 *     markers and the shading following the visible window.
 *
 * **Nothing here computes a metric.** Every number drawn or shown comes out of the
 * analysis document verbatim; the only arithmetic is SVG coordinate placement, the
 * binary search that maps a time to the sample nearest it, and the linear interpolation
 * that keeps the playhead dot moving smoothly between two samples. If the UI needs a
 * number the document does not carry, it goes into lab_bundle/, not into this file.
 */

import {
  C, OUTCOME_LABEL, bandSwatch, clockAt, endStyle, esc, figureWidth, glyphSwatch, hideTip,
  hms, isNarrow, label, lineSwatch, marker, nf, showTip, svg, tipTarget, turnStyle,
} from "./viz.js";
import { TOKENS } from "./tokens.js";

const el = (id) => document.getElementById(id);

/* ------------------------------------------------------------------- the layers */

/** Draw order on the map and in the chart: context first, verdicts over it, the two
 *  glyph layers last so a busy stretch still reads. */
const MARK_ORDER = ["courseChange", "glideOut", "flewThrough", "touchdown", "fellIn",
                    "splash", "takeoff"];

const LAYERS = [
  { id: "flying",       label: "foiling",              swatch: () => lineSwatch(C.foil) },
  { id: "offFoil",      label: "off foil",             swatch: () => lineSwatch(C.track) },
  { id: "pumping",      label: "pumping",              swatch: () => lineSwatch(C.pump, 4.5) },
  { id: "effort",       label: "record window",        swatch: () => lineSwatch(C.ink, 2.8) },
  { id: "flewThrough",  label: "flew through",         swatch: () => glyphSwatch("disc", C.good) },
  { id: "touchdown",    label: "touched down",         swatch: () => glyphSwatch("triangle", C.warn) },
  { id: "fellIn",       label: "fell in",              swatch: () => glyphSwatch("cross", C.bad) },
  { id: "glideOut",     label: "glided out",           swatch: () => glyphSwatch("square", C.ink2) },
  { id: "courseChange", label: "bear-away / round-up", swatch: () => glyphSwatch("hairline", C.reject) },
  { id: "takeoff",      label: "takeoff",              swatch: () => glyphSwatch("arrow-up", C.takeoff) },
  { id: "splash",       label: "wrist under",          swatch: () => glyphSwatch("drop", C.splash) },
];

const OUTCOME_LAYER = { flew_through: "flewThrough", touchdown: "touchdown",
                        fell_in: "fellIn", glide_out: "glideOut" };

/* --------------------------------------------------------------------- the state */

const state = {
  result: null,        // the document on screen; a new one resets everything below
  highlight: null,     // the record window, when one is marked
  model: null,         // marks + spans, derived once per document
  playhead: null,      // session-clock seconds, or null
  zoom: null,          // {t0, t1} visible window on the strip, or null for "all of it"
  hidden: new Set(),   // layer ids the chips have switched off (transient, not persisted)
  live: null,          // handles into the drawn figures, so a scrub is not a redraw
};

/* ------------------------------------------------------------------ time lookups */

/** Index of the sample nearest `t` (binary search over the ascending time array). */
function indexAt(v, t) {
  let lo = 0, hi = v.count - 1;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (v.t[mid] < t) lo = mid + 1; else hi = mid; }
  if (lo > 0 && Math.abs(v.t[lo - 1] - t) < Math.abs(v.t[lo] - t)) lo -= 1;
  return lo;
}

/** The speed the blue trace shows at `t` — Doppler where there is one, positional else. */
function traceKn(v, t) {
  const i = indexAt(v, t);
  return v.dopplerKn[i] ?? v.speedKn[i] ?? 0;
}

const inFlight = (v, t) => v.flights.some((f) => t >= f.startTs && t <= f.endTs);

/** Windows overlap-test helper: is sample time `t` inside any highlighted window? */
function inWindows(windows, t) {
  for (const w of windows) if (t >= w.startTs && t <= w.startTs + w.durS) return true;
  return false;
}

const highlightWindows = (h) => (h && Array.isArray(h.windows) ? h.windows : []);

/* --------------------------------------------------------------------- the model */

/**
 * Everything the two figures draw, resolved once per document: each event's time, its
 * position on the track, the speed it sits at, and the facts its popover shows. All of it
 * is a lookup into `view` and `golden` — see the module header.
 */
function buildModel(result) {
  const v = result.view, g = result.golden, meta = result.meta;
  const marks = [];
  const positioned = v.count && v.hasPositions !== false && v.x.length === v.count;
  const at = (t) => {
    const i = indexAt(v, t);
    return { i, x: positioned ? v.x[i] : null, y: positioned ? v.y[i] : null };
  };
  const time = (t) => `${clockAt(meta.startUtc, t)} · ${hms(t)}`;

  // --- turn outcomes (solid shapes) --------------------------------------------
  for (const m of v.turnMarkers) {
    const turn = g.turns[m.i];
    const layer = m.counted && m.maneuver ? (OUTCOME_LAYER[m.outcome] || "courseChange")
                                          : "courseChange";
    marks.push({
      layer, t: m.t, x: m.x, y: m.y, kn: m.kn, style: turnStyle(m), n: m.n,
      title: `#${m.n} ${m.kind}${m.counted ? "" : " (not counted)"}`,
      tip: `<b>#${m.n} ${clockAt(meta.startUtc, m.t)}</b> — ${esc(m.kind)}<br>` +
           `${OUTCOME_LABEL[m.outcome] || m.outcome} · ${nf(turn.entryKn, 1)} → ` +
           `${nf(turn.minKn, 1)} kn (${nf(turn.score * 100, 0)} %)`,
      rows: [
        ["time", time(m.t)],
        ["type", `${turn.type}${turn.counted ? "" : " · not counted"}`],
        ["entry tack", `${turn.side} · turns to ${turn.direction}`],
        ["outcome", `${OUTCOME_LABEL[turn.outcome] || turn.outcome}` +
                    (turn.borderline ? " (borderline)" : "")],
        ["speed", `${nf(turn.entryKn, 2)} → ${nf(turn.minKn, 2)} kn`],
        ["score", `${nf(turn.score * 100, 0)} % · ${turn.success ? "held" : "lost"}`],
        ["stopped", `${nf(turn.stoppedS, 1)} s · off foil ${nf(turn.offFoilS, 1)} s`],
        ["arc", `${nf(turn.arcM, 0)} m · R ${nf(turn.radiusM, 0)} m`],
      ],
    });
  }

  // --- straight-line flight ends (hollow squares) -------------------------------
  for (const e of v.endMarkers.filter((x) => x.drawOnMap)) {
    const end = g.flightEnds[e.i];
    marks.push({
      layer: OUTCOME_LAYER[e.outcome] || "glideOut", t: e.t, x: e.x, y: e.y,
      kn: e.kn ?? traceKn(v, e.t), style: endStyle(e), n: null,
      title: `Flight ${e.flightIndex + 1} ends · straight line`,
      tip: `<b>${clockAt(meta.startUtc, e.t)}</b> — flight ${e.flightIndex + 1} ends<br>` +
           `${OUTCOME_LABEL[e.outcome]} · straight line (no manoeuvre)`,
      rows: [
        ["time", time(e.t)],
        ["outcome", `${OUTCOME_LABEL[e.outcome] || e.outcome}` +
                    (end?.borderline ? " (borderline)" : "")],
        ["channel", "straight-line — no turn explains it"],
        ["stopped", `${nf(end?.stoppedS, 1)} s · off foil ${nf(end?.offFoilS, 1)} s`],
        ["min speed", end?.minKn === null || end?.minKn === undefined ? "—" : `${nf(end.minKn, 2)} kn`],
      ],
    });
  }

  // --- takeoff attempts: both halves -------------------------------------------
  // Every entry in `takeoffs` succeeded (the engine only writes one for a flight that
  // happened), so the failures come from the pumping episodes the classifier called
  // `failed` — engine 0.3.0 serializes them, so they carry a time and therefore a place.
  for (const k of g.takeoffs) {
    const p = at(k.startTs);
    const rows = [
      ["time", time(k.startTs)],
      ["up at", `${nf(k.entryKn, 2)} kn`],
      ["pumps", k.pumps === null ? "— (no wrist accelerometer)" : `${k.pumps}`],
      ["time to foil", k.truncated ? "— (truncated)" : `${nf(k.timeToFoilS, 1)} s`],
    ];
    if (k.cadenceSpm !== null && k.cadenceSpm !== undefined) {
      rows.push(["cadence", `${nf(k.cadenceSpm, 0)} strokes/min`]);
    }
    marks.push({
      layer: "takeoff", t: k.startTs, x: p.x, y: p.y, kn: traceKn(v, k.startTs),
      style: { shape: (k.free ? TOKENS.glyphs.takeoffFree : TOKENS.glyphs.takeoffPumped)
                        .webShape,
               color: C.takeoff }, n: null,
      title: k.free ? "Free takeoff" : "Takeoff",
      tip: `<b>${clockAt(meta.startUtc, k.startTs)}</b> — ${k.free ? "free takeoff" : "takeoff"}<br>` +
           `up at ${nf(k.entryKn, 1)} kn` +
           (k.pumps === null ? "" : ` · ${k.pumps} stroke${k.pumps === 1 ? "" : "s"}`) +
           (k.truncated ? "" : ` · ${nf(k.timeToFoilS, 0)} s run`),
      rows,
    });
  }
  for (const ep of g.pumpEpisodes) {
    if (ep.outcome !== "failed") continue;
    const p = at(ep.startTs);
    marks.push({
      layer: "takeoff", t: ep.startTs, x: p.x, y: p.y, kn: traceKn(v, ep.startTs),
      style: { shape: TOKENS.glyphs.takeoffFailed.webShape, color: C.failedTakeoff }, n: null,
      title: "Failed attempt",
      tip: `<b>${clockAt(meta.startUtc, ep.startTs)}</b> — failed attempt<br>` +
           `${ep.strokes} stroke${ep.strokes === 1 ? "" : "s"}, no flight`,
      rows: [
        ["time", time(ep.startTs)],
        ["outcome", `failed attempt, ${ep.strokes} stroke${ep.strokes === 1 ? "" : "s"}`],
        ["duration", `${nf(ep.endTs - ep.startTs, 1)} s`],
        ["bursts", `${ep.bursts}`],
      ],
    });
  }

  // --- submersion evidence ------------------------------------------------------
  // The barometer has to see the pressure step, so this layer is evidence, not a census.
  for (let i = 0; i < g.turns.length; i++) {
    const turn = g.turns[i];
    if (!turn.submerged || !turn.counted) continue;
    const p = at(turn.ts);
    marks.push({
      layer: "splash", t: turn.ts, x: p.x, y: p.y, kn: traceKn(v, turn.ts),
      style: { shape: TOKENS.glyphs.splash.webShape, color: C.splash }, n: null,
      title: `${turn.type} · wrist under`,
      tip: `<b>${clockAt(meta.startUtc, turn.ts)}</b> — wrist under<br>` +
           `${esc(turn.type)} · ${nf(turn.entryKn, 1)} → ${nf(turn.minKn, 1)} kn`,
      rows: [["time", time(turn.ts)], ["evidence", "barometer saw the wrist go under"],
             ["turn", `${turn.type} · ${OUTCOME_LABEL[turn.outcome] || turn.outcome}`],
             ["speed", `${nf(turn.entryKn, 2)} → ${nf(turn.minKn, 2)} kn`]],
    });
  }
  for (const end of g.flightEnds) {
    if (!end.submerged || end.ownedByTurn !== null || end.truncated) continue;
    const p = at(end.ts);
    marks.push({
      layer: "splash", t: end.ts, x: p.x, y: p.y, kn: traceKn(v, end.ts),
      style: { shape: TOKENS.glyphs.splash.webShape, color: C.splash }, n: null,
      title: "Wrist under",
      tip: `<b>${clockAt(meta.startUtc, end.ts)}</b> — wrist under<br>straight-line flight end`,
      rows: [["time", time(end.ts)], ["evidence", "barometer saw the wrist go under"],
             ["channel", "straight-line flight end"],
             ["stopped", `${nf(end.stoppedS, 1)} s`]],
    });
  }

  marks.sort((a, b) => MARK_ORDER.indexOf(a.layer) - MARK_ORDER.indexOf(b.layer) || a.t - b.t);

  // --- pumping runs -------------------------------------------------------------
  // The attempts only: `success` is the ramp into the takeoff drawn beside it, `failed` is
  // the burst that produced nothing. In-flight pumping is a different act (holding a
  // glide, not trying to get up) and tinting it would read as one.
  const pumpSpans = g.pumpEpisodes
    .filter((ep) => ep.outcome === "success" || ep.outcome === "failed")
    .map((ep) => ({ t0: ep.startTs, t1: ep.endTs, strokes: ep.strokes, outcome: ep.outcome,
                    bursts: ep.bursts }));

  return { v, g, meta, marks, pumpSpans, positioned };
}

/** How many marks/spans a layer has in this document — the input to "is this chip a
 *  control or just a caption?" (iOS: `layerTally`). */
function tally(model, highlight) {
  const counts = {};
  for (const id of MARK_ORDER) counts[id] = 0;
  for (const mk of model.marks) counts[mk.layer] = (counts[mk.layer] || 0) + 1;
  counts.flying = model.v.flights.length;
  counts.offFoil = model.v.count ? 1 : 0;
  counts.pumping = model.pumpSpans.length;
  counts.effort = highlightWindows(highlight).length;
  return counts;
}

const visible = (id) => !state.hidden.has(id);

/* ------------------------------------------------------------------ the entry point */

/**
 * Draw both figures for `result`, with `highlight` (a record's own `records.windows`
 * provenance) marked when there is one. Called by render(), which also calls it again on
 * a resize — the same document keeps its playhead, its zoom and its chip states.
 */
export function renderFigures(result, highlight = null) {
  if (state.result !== result) {
    state.result = result;
    state.model = buildModel(result);
    state.playhead = null;
    state.zoom = null;
    state.hidden.clear();
    endStripGesture();
    closePopover();
  }
  state.highlight = highlight;
  state.live = { map: null, strip: null };
  drawMap();
  drawStrip();
  drawChips();
  applyPlayhead();
}

/** Forget the on-screen session (used when the view is torn down). */
export function resetSession() {
  state.result = null;
  state.model = null;
  state.playhead = null;
  state.zoom = null;
  state.hidden.clear();
  endStripGesture();
  closePopover();
}

/* -------------------------------------------------------------------------- map */

function drawMap() {
  const host = el("map-figure");
  host.innerHTML = "";
  const model = state.model, v = model.v;
  // `hasPositions` is false for Doppler-only sources: the analysis (speed strip, records,
  // flights, outcomes) is all still there, there is simply no track to plot.
  if (!v.count || !v.bounds || v.hasPositions === false || v.bounds.x0 === null) {
    host.innerHTML = `<p class="note">No GPS positions in this file — no track to draw. ` +
                     `The speed strip and the tables below are unaffected.</p>`;
    return;
  }

  const b = v.bounds;
  const W = figureWidth(host);
  const narrow = isNarrow(W);
  const PAD = narrow ? 20 : 34;
  const dw = Math.max(b.x1 - b.x0, 1), dh = Math.max(b.y1 - b.y0, 1);
  const inner = W - 2 * PAD;
  let H = Math.round(inner * (dh / dw)) + 2 * PAD;
  // The clamp is a fraction of the width, not a pixel count, so the map keeps a sane
  // aspect at every column width. A phone gets a taller box: vertical space is what it has.
  H = Math.min(Math.max(H, Math.round(W * (narrow ? 0.85 : 0.31))),
               Math.round(W * (narrow ? 1.45 : 0.69)));
  const s = Math.min(inner / dw, (H - 2 * PAD) / dh);
  const ox = PAD + (inner - dw * s) / 2 - b.x0 * s;
  const oy = PAD + (H - 2 * PAD - dh * s) / 2 + b.y1 * s;   // y flipped: north up
  const X = (x) => ox + x * s;
  const Y = (y) => oy - y * s;

  const root = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", class: "scrubbable",
                            "aria-label": "GPS track with event markers; drag to move the "
                                          + "replay playhead" }, host);
  svg("rect", { width: W, height: H, fill: C.surface }, root);

  // Off-foil track, broken at recording gaps. A hidden line category keeps its route as a
  // dimmer line: the chips filter what the colours claim, not where the rider went.
  const runs = polylineRuns(v, () => true);
  for (const pts of runs) {
    svg("polyline", { points: screenPoints(pts, X, Y), fill: "none",
                      stroke: visible("offFoil") ? C.track : "#2c2c2a", "stroke-width": 1.4,
                      "stroke-linecap": "round", "stroke-linejoin": "round" }, root);
  }
  if (visible("flying")) {
    for (const f of v.flights) {
      for (const pts of polylineRuns(v, (t) => t >= f.startTs && t <= f.endTs)) {
        svg("polyline", { points: screenPoints(pts, X, Y), fill: "none", stroke: C.foil,
                          "stroke-width": 2.1, opacity: 0.9, "stroke-linecap": "round",
                          "stroke-linejoin": "round" }, root);
      }
    }
  }
  // Under the effort glow and under the markers: a pump run is context for the takeoff
  // that ends it, not a thing to read on its own.
  if (visible("pumping")) {
    for (const span of model.pumpSpans) {
      for (const pts of polylineRuns(v, (t) => t >= span.t0 && t <= span.t1)) {
        svg("polyline", { points: screenPoints(pts, X, Y), fill: "none", stroke: C.pump,
                          "stroke-width": 4.5, opacity: 0.8, "stroke-linecap": "round",
                          "stroke-linejoin": "round", "data-span": "pumping" }, root);
      }
    }
  }

  // Direction of travel, decimated by on-screen spacing so a slow stretch does not turn
  // into a solid bar of chevrons. Drawn over the track and under everything else.
  chevrons(root, runs, X, Y, narrow ? 34 : 46);

  // The highlighted record window, on top of the track but under the markers: a white halo
  // plus a white line. White is not in the outcome ramp, so it cannot be mistaken for one.
  const hw = highlightWindows(state.highlight);
  if (hw.length && visible("effort")) {
    for (const pts of polylineRuns(v, (t) => inWindows(hw, t))) {
      const points = screenPoints(pts, X, Y);
      svg("polyline", { points, fill: "none", stroke: C.surface, "stroke-width": 6.5,
                        opacity: 0.85, "stroke-linecap": "round",
                        "stroke-linejoin": "round" }, root);
      svg("polyline", { points, fill: "none", stroke: C.ink, "stroke-width": 3.0,
                        "stroke-linecap": "round", "stroke-linejoin": "round",
                        "data-span": "effort" }, root);
    }
  }

  for (const mk of model.marks) {
    if (!visible(mk.layer) || mk.x === null || mk.x === undefined) continue;
    const node = marker(root, mk.style, X(mk.x), Y(mk.y));
    annotate(node, mk, "map");
    if (mk.n !== null && visible(mk.layer)) label(root, X(mk.x), Y(mk.y), mk.n, mk.style.color,
                                                  mk.n % 2 === 1);
  }

  if (model.g.wind) windArrow(root, model.g.wind, W, narrow);
  scaleBar(root, s, PAD, H - 14);

  // The playhead, drawn last so it sits above the outcome markers — it is the thing being
  // moved. Deliberately unlike them (bigger, white-ringed, with a halo) so it reads as
  // "where you are now" rather than "something happened here".
  //
  // It must not take the pointer, though (the strip's playhead is the same): tapping a
  // marker parks the playhead exactly on that marker, and a solid 11-unit halo there would
  // swallow the next tap on the very mark the reader just opened.
  const head = svg("g", { id: "playhead-map", visibility: "hidden",
                          "pointer-events": "none" }, root);
  const halo = svg("circle", { r: 11, fill: C.foil, opacity: 0.26 }, head);
  const dot = svg("circle", { r: 5.2, fill: C.foil, stroke: C.ink, "stroke-width": 2 }, head);

  state.live.map = { root, X, Y, head, halo, dot, W, H };
  wireMapScrub(root, W, H, X, Y);
}

/** Contiguous runs of samples matching `keep`, split at gaps (segment id changes). */
function polylineRuns(v, keep) {
  const runs = [];
  let cur = [];
  const flush = () => { if (cur.length > 1) runs.push(cur); cur = []; };
  for (let i = 0; i < v.count; i++) {
    const gap = i > 0 && v.segment[i] !== v.segment[i - 1];
    const ok = v.x[i] != null && v.y[i] != null && keep(v.t[i]);   // null or missing
    if (gap || !ok) flush();
    if (ok) cur.push([v.x[i], v.y[i]]);
  }
  flush();
  return runs;
}

const screenPoints = (pts, X, Y) =>
  pts.map(([x, y]) => `${X(x).toFixed(1)},${Y(y).toFixed(1)}`).join(" ");

/**
 * Little chevrons along the track, pointing the way he went.
 *
 * Placed by *screen* distance rather than by sample index: at 1 Hz a slow stretch has ten
 * times the samples of a fast one, and index-decimated chevrons would pile up exactly
 * where the track is already most crowded.
 */
function chevrons(root, runs, X, Y, spacing) {
  // Ink and opacity from design/tokens.json: the chevrons indicate, never compete, and
  // "how subordinate" is a value the two apps have to agree on (docs/presentation.md).
  const g = svg("g", { id: "track-chevrons", fill: "none", stroke: TOKENS.direction.ink.hex,
                       opacity: TOKENS.opacity.directionWeb,
                       "stroke-width": 1.3, "stroke-linecap": "round",
                       "stroke-linejoin": "round", "pointer-events": "none" }, root);
  for (const pts of runs) {
    let due = spacing * 0.5;                 // distance still to travel before the next one
    for (let i = 1; i < pts.length; i++) {
      const x0 = X(pts[i - 1][0]), y0 = Y(pts[i - 1][1]);
      const dx = X(pts[i][0]) - x0, dy = Y(pts[i][1]) - y0;
      const len = Math.hypot(dx, dy);
      if (len < 0.01) continue;
      const deg = (Math.atan2(dy, dx) * 180) / Math.PI;
      while (due <= len) {
        const f = due / len;
        svg("path", { d: "M-2.6,-2.6 L1.4,0 L-2.6,2.6",
                      transform: `translate(${(x0 + dx * f).toFixed(1)} ` +
                                 `${(y0 + dy * f).toFixed(1)}) rotate(${deg.toFixed(1)})` }, g);
        due += spacing;
      }
      due -= len;
    }
  }
  return g;
}

function windArrow(root, wind, W, narrow) {
  const span = narrow ? 40 : 62;
  const cx = W - (narrow ? 46 : 92), cy = narrow ? 42 : 62;
  const to = ((wind.dirDeg + 180) * Math.PI) / 180;      // where the air travels
  const dx = Math.sin(to) * span, dy = -Math.cos(to) * span;
  const g = svg("g", { "pointer-events": "none" }, root);
  svg("defs", {}, g).innerHTML =
    `<marker id="windhead" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6"
             orient="auto"><path d="M0,1 L9,5 L0,9 z" fill="${C.ink2}"/></marker>`;
  svg("line", { x1: cx - dx / 2, y1: cy - dy / 2, x2: cx + dx / 2, y2: cy + dy / 2,
                stroke: C.ink2, "stroke-width": 2.2, "stroke-linecap": "round",
                "marker-end": "url(#windhead)" }, g);
  // On a phone the full caption is wider than the arrow's own corner, so it right-aligns
  // to the figure edge and drops the confidence (which is also in the Wind axis tile).
  const t = svg("text", {
    x: narrow ? W - 8 : cx, y: cy + span / 2 + (narrow ? 15 : 18),
    "text-anchor": narrow ? "end" : "middle",
    "font-size": narrow ? 10.5 : 11, "font-weight": 600, fill: C.ink2,
    stroke: C.surface, "stroke-width": 2.6, "paint-order": "stroke",
  }, g);
  t.textContent = narrow
    ? `wind ${wind.dirDeg.toFixed(0)}°`
    : `wind ${wind.dirDeg.toFixed(0)}° (conf ${wind.confidence.toFixed(2)})`;
}

function scaleBar(root, s, x, y) {
  const targets = [100, 200, 500, 1000, 2000];
  const meters = targets.find((m) => m * s > 70) ?? 100;
  const w = meters * s;
  const g = svg("g", { "pointer-events": "none" }, root);
  svg("path", { d: `M${x},${y - 5} v5 h${w.toFixed(1)} v-5`, fill: "none",
                stroke: C.ink3, "stroke-width": 1.2 }, g);
  const t = svg("text", { x: x + w / 2, y: y + 12, "text-anchor": "middle",
                          "font-size": 10.5, fill: C.ink3 }, g);
  t.textContent = meters >= 1000 ? `${meters / 1000} km` : `${meters} m`;
}

/* ------------------------------------------------------------- map: scrubbing */

/**
 * The map is the second handle on the playhead: press near the track and the playhead
 * jumps there, drag and it follows. A press that lands nowhere near the track is ignored
 * rather than yanking the playhead to some unrelated corner of the session — the
 * tolerance is in *screen* units, so it is roughly a fingertip whatever the scale is.
 */
function wireMapScrub(root, W, H, X, Y) {
  const v = state.model.v;
  const tolerance = 34;                       // user units == CSS px at this viewBox
  let dragging = false;

  const toUser = (ev) => {
    const r = root.getBoundingClientRect();
    return { ux: ((ev.clientX - r.left) / r.width) * W,
             uy: ((ev.clientY - r.top) / r.height) * H };
  };

  const nearest = (ux, uy) => {
    let bestT = null, bestD = Infinity;
    for (let i = 0; i < v.count; i++) {
      if (v.x[i] == null || v.y[i] == null) continue;
      const dx = X(v.x[i]) - ux, dy = Y(v.y[i]) - uy;
      const d = dx * dx + dy * dy;
      if (d < bestD) { bestD = d; bestT = v.t[i]; }
    }
    return bestD <= tolerance * tolerance ? bestT : null;
  };

  let from = 0;
  root.addEventListener("pointerdown", (ev) => {
    // Before any early return: a new press is never the drag the last one was, and a mark
    // whose press is ignored here still has to be tappable (its click handler asks).
    dragged = false;
    if (ev.target.closest("[data-mark]")) return;      // a marker tap opens its popover
    const { ux, uy } = toUser(ev);
    const t = nearest(ux, uy);
    if (t === null) return;
    dragging = true;
    from = ev.clientX + ev.clientY;
    root.setPointerCapture(ev.pointerId);
    setPlayhead(t);
    ev.preventDefault();
  });
  root.addEventListener("pointermove", (ev) => {
    if (!dragging) return;
    if (Math.abs(ev.clientX + ev.clientY - from) > 4) dragged = true;
    const { ux, uy } = toUser(ev);
    const t = nearest(ux, uy);
    if (t !== null) setPlayhead(t);
  });
  for (const type of ["pointerup", "pointercancel", "pointerleave"]) {
    root.addEventListener(type, (ev) => {
      if (!dragging) return;
      dragging = false;
      if (root.hasPointerCapture?.(ev.pointerId)) root.releasePointerCapture(ev.pointerId);
    });
  }
}

/* ------------------------------------------------------------------ speed strip */

/** The visible time window: the whole session, or whatever the zoom has been set to. */
function window0(v) { return state.zoom ? state.zoom.t0 : v.bounds.t0; }
function window1(v) {
  return state.zoom ? state.zoom.t1 : Math.max(v.bounds.t1, v.bounds.t0 + 1);
}

function drawStrip() {
  const host = el("strip-figure");
  host.innerHTML = "";
  const model = state.model, v = model.v;
  if (!v.count) { host.innerHTML = `<p class="note">No speed samples.</p>`; return; }

  const W = figureWidth(host);
  const narrow = isNarrow(W);
  const H = narrow ? Math.round(Math.max(200, W * 0.62)) : 320;
  const L = narrow ? 34 : 46, R = narrow ? 10 : 16, T = 18, B = narrow ? 32 : 34;
  const b = v.bounds;
  const t0 = window0(v), t1 = window1(v);
  const knMax = Math.max(2, Math.ceil((b.knMax * 1.12) / 2) * 2);
  const X = (t) => L + ((t - t0) / (t1 - t0)) * (W - L - R);
  const Y = (kn) => H - B - (kn / knMax) * (H - T - B);
  const inView = (t) => t >= t0 && t <= t1;
  const plotW = W - L - R, plotH = H - T - B;

  // The window is on the element itself: the drawing reads from it, and so does anyone
  // asking the page what it is currently showing.
  const root = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", class: "scrubbable",
                            "data-t0": t0.toFixed(2), "data-t1": t1.toFixed(2),
                            "aria-label": "Speed over time; drag to scrub, wheel or pinch "
                                          + "to zoom the time axis" }, host);
  svg("rect", { width: W, height: H, fill: C.surface }, root);

  // Everything time-dependent is clipped to the plot box so a zoomed-in window cannot
  // spill a polyline over the axes.
  const clipId = "strip-clip";
  const clip = svg("clipPath", { id: clipId }, svg("defs", {}, root));
  svg("rect", { x: L, y: T, width: plotW, height: plotH }, clip);
  const plot = svg("g", { "clip-path": `url(#${clipId})` }, root);

  if (visible("flying")) {
    for (const f of v.flights) {
      if (f.endTs < t0 || f.startTs > t1) continue;
      svg("rect", { x: X(f.startTs), y: T, width: Math.max(1, X(f.endTs) - X(f.startTs)),
                    height: plotH, fill: C.foil, opacity: 0.10, "data-band": "flying" }, plot);
    }
  }
  // Pumping is a span, so the chart draws it the way it draws flights: a band, not a dot.
  // On the speed trace it is the ramp into every takeoff, which is where the reader wants it.
  if (visible("pumping")) {
    for (const span of model.pumpSpans) {
      if (span.t1 < t0 || span.t0 > t1) continue;
      const x0 = X(span.t0), x1 = Math.max(X(span.t1), x0 + 1.5);
      const band = svg("rect", { x: x0, y: T, width: x1 - x0, height: plotH, fill: C.pump,
                                 opacity: 0.3, "data-band": "pumping" }, plot);
      tipTarget(band, `<b>${clockAt(model.meta.startUtc, span.t0)}</b> — pumping<br>` +
                      `${span.strokes} stroke${span.strokes === 1 ? "" : "s"} · ` +
                      `${nf(span.t1 - span.t0, 1)} s · ${esc(span.outcome)}`);
    }
  }

  // Gridline spacing follows the space available, so the labels never collide.
  const knStep = plotH / Math.max(1, knMax / 2) < 18 ? 4 : 2;
  for (let kn = 0; kn <= knMax; kn += knStep) {
    svg("line", { x1: L, x2: W - R, y1: Y(kn), y2: Y(kn), stroke: C.grid, "stroke-width": 1,
                  opacity: kn === 0 ? 0.9 : 0.45 }, root);
    const t = svg("text", { x: L - 8, y: Y(kn) + 3.5, "text-anchor": "end",
                            "font-size": 10.5, fill: C.ink3 }, root);
    t.textContent = String(kn);
  }
  // The axis title has to name the unit the ticks were actually written in, so it comes
  // back from the tick pass rather than being guessed from "is this zoomed at all".
  const timeUnit = timeAxis(root, { X, t0, t1, L, R, W, H, B, narrow }) ? "m:ss" : "min";

  if (narrow) {
    // No room for a rotated axis title beside a 34-unit gutter — it would sit at x≈0 and be
    // clipped. Bare units instead; the panel heading already says what the figure is.
    axisUnit(root, L - 8, T - 4, "kn", "end");
    axisUnit(root, W - R, H - 3, timeUnit, "end");
  } else {
    axisLabel(root, L - 34, T + plotH / 2, "speed (kn)", true);
    axisLabel(root, L + plotW / 2, H - 4, `session time (${timeUnit})`, false);
  }

  // Record windows: a bracketed band, drawn before the traces so the speed line stays
  // readable through it. Narrow windows (a 2 s record is ~1 px wide) get a minimum width
  // so they are still findable.
  const hw = visible("effort") ? highlightWindows(state.highlight) : [];
  hw.forEach((w, i) => {
    if (w.startTs + w.durS < t0 || w.startTs > t1) return;
    const x0 = X(w.startTs), x1 = Math.max(X(w.startTs + w.durS), x0 + 2.5);
    const band = svg("rect", { x: x0, y: T, width: x1 - x0, height: plotH,
                               fill: C.ink, opacity: 0.14, "data-band": "effort" }, plot);
    for (const x of [x0, x1]) {
      svg("line", { x1: x, x2: x, y1: T, y2: H - B, stroke: C.ink, "stroke-width": 1.1,
                    opacity: 0.75, "stroke-dasharray": "4 3" }, plot);
    }
    const facts = {
      title: state.highlight?.label || "record window",
      rows: [["window", `${hms(w.startTs)} → ${hms(w.startTs + w.durS)}`],
             ["duration", `${nf(w.durS, 2)} s`],
             ["value", `${state.highlight?.value ?? "—"} ${state.highlight?.unit ?? ""}`.trim()],
             ["windows", `${i + 1} of ${hw.length}`]],
    };
    band.style.cursor = "pointer";
    band.addEventListener("click", (ev) => {
      if (dragged) return;
      ev.stopPropagation();
      openPopover(ev, facts);
    });
    if (i === 0 && state.highlight?.label) {
      // A record set late in the session would push its label off the right edge, so the
      // label flips to the other side of the band rather than being clipped.
      const flip = x1 > W * 0.62;
      const t = svg("text", { x: flip ? x0 - 6 : x1 + 6, y: T + 12,
                              "text-anchor": flip ? "end" : "start", "font-size": 11,
                              "font-weight": 700, fill: C.ink, stroke: C.surface,
                              "stroke-width": 3, "paint-order": "stroke" }, plot);
      t.textContent = state.highlight.label;
    }
  });

  series(plot, v, v.speedKn, X, Y, C.tint, 1.0, 0.85, t0, t1);
  series(plot, v, v.dopplerKn, X, Y, C.foil, 1.5, 1, t0, t1);

  for (const mk of state.model.marks) {
    if (!visible(mk.layer) || !inView(mk.t)) continue;
    const node = marker(plot, mk.style, X(mk.t), Y(mk.kn), 0.85);
    annotate(node, mk, "strip");
    if (mk.n !== null) label(plot, X(mk.t), Y(mk.kn), mk.n, mk.style.color, mk.n % 2 === 1);
  }

  // Crosshair (hover) and the playhead (scrub) are two different things and look it: the
  // crosshair is a hairline that follows the pointer, the playhead is a dashed rule that
  // stays where it was put and has a twin on the map.
  const cross = svg("g", { visibility: "hidden", "pointer-events": "none" }, root);
  const cline = svg("line", { y1: T, y2: H - B, stroke: C.ink3, "stroke-width": 1,
                              "stroke-dasharray": "3 3" }, cross);
  const cdot = svg("circle", { r: 3.4, fill: C.foil, stroke: C.surface,
                               "stroke-width": 1.4 }, cross);

  const head = svg("g", { id: "playhead-strip", visibility: "hidden",
                          "pointer-events": "none" }, root);
  const hline = svg("line", { y1: T, y2: H - B, stroke: C.ink, "stroke-width": 1.8,
                              "stroke-dasharray": "5 3" }, head);
  const hdot = svg("circle", { r: 5, fill: C.ink, stroke: C.surface, "stroke-width": 2 }, head);

  state.live.strip = { root, X, Y, head, hline, hdot, box: { W, H, L, R, T, B, t0, t1 } };
  wireStripInput(root, { cross, cline, cdot }, { W, H, L, R, T, B, t0, t1, X, Y });
  drawStripLegend();
}

function series(root, v, arr, X, Y, color, width, opacity, t0, t1) {
  let cur = [];
  const flush = () => {
    if (cur.length > 1) {
      svg("polyline", { points: cur.join(" "), fill: "none", stroke: color,
                        "stroke-width": width, opacity, "stroke-linejoin": "round",
                        "stroke-linecap": "round" }, root);
    }
    cur = [];
  };
  for (let i = 0; i < v.count; i++) {
    // One sample of margin on each side so a zoomed window's line reaches the edge.
    const near = v.t[i] >= t0 - 5 && v.t[i] <= t1 + 5;
    if (arr[i] === null || !near || (i > 0 && v.segment[i] !== v.segment[i - 1])) flush();
    if (arr[i] !== null && near) cur.push(`${X(v.t[i]).toFixed(1)},${Y(arr[i]).toFixed(1)}`);
  }
  flush();
}

/** Time ticks for the visible window: whole minutes while the whole session is on screen,
 *  m:ss once the window is short enough that minutes would give one tick. Returns true when
 *  it wrote clock times, so the axis title can name the same unit. */
function timeAxis(root, { X, t0, t1, L, R, W, H, B, narrow }) {
  const span = t1 - t0;
  const maxTicks = narrow ? 6 : 12;
  const steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600];
  const step = steps.find((s) => span / s <= maxTicks) ?? 7200;
  const asClock = step < 60;
  const first = Math.ceil(t0 / step) * step;
  for (let t = first; t <= t1; t += step) {
    const x = X(t);
    svg("line", { x1: x, x2: x, y1: H - B, y2: H - B + 4, stroke: C.grid, "stroke-width": 1 }, root);
    const node = svg("text", { x, y: H - B + 16, "text-anchor": "middle", "font-size": 10.5,
                               fill: C.ink3 }, root);
    node.textContent = asClock ? hms(t) : `${Math.round(t / 60)}`;
  }
  return asClock;
}

function axisLabel(root, x, y, text, rotate) {
  const t = svg("text", { x, y, "text-anchor": "middle", "font-size": 11, fill: C.ink3,
                          transform: rotate ? `rotate(-90 ${x} ${y})` : null }, root);
  t.textContent = text;
}

/** The compact form of an axis title: just the unit, tucked against the axis end. */
function axisUnit(root, x, y, text, anchor) {
  const t = svg("text", { x, y, "text-anchor": anchor, "font-size": 10,
                          "font-weight": 600, fill: C.ink3 }, root);
  t.textContent = text;
}

/* --------------------------------------------------- strip: scrubbing and zoom */

/**
 * Every gesture on the strip, wired to the SVG root rather than to a transparent hit
 * rectangle over the plot.
 *
 * A hit rectangle would have to sit either above the marks (and swallow their clicks) or
 * below the bands (and lose the drag wherever a flight band is painted). Listening on the
 * root gets both: the event bubbles up from whatever it landed on, and the handler only
 * has to ask whether it landed on a mark.
 */
function wireStripInput(root, cross, box) {
  const v = state.model.v;

  const local = (ev) => {
    const r = root.getBoundingClientRect();
    return { ux: ((ev.clientX - r.left) / r.width) * box.W,
             uy: ((ev.clientY - r.top) / r.height) * box.H };
  };
  const inPlot = (ev) => {
    const { ux, uy } = local(ev);
    return ux >= box.L && ux <= box.W - box.R && uy >= box.T && uy <= box.H - box.B;
  };
  const timeAt = (clientX) => {
    const r = root.getBoundingClientRect();
    const ux = ((clientX - r.left) / r.width) * box.W;
    const t = box.t0 + ((ux - box.L) / (box.W - box.L - box.R)) * (box.t1 - box.t0);
    return Math.min(Math.max(t, box.t0), box.t1);
  };

  /* --- hover crosshair: the reading-without-committing gesture (mouse only) */
  root.addEventListener("pointermove", (ev) => {
    if (ev.pointerType !== "mouse" || stripPointers.size) return;
    if (!inPlot(ev)) {
      cross.cross.setAttribute("visibility", "hidden");
      return;
    }
    if (ev.target.closest("[data-mark]")) return;         // the mark's own tooltip wins
    const i = indexAt(v, timeAt(ev.clientX));
    const kn = v.dopplerKn[i] ?? v.speedKn[i] ?? 0;
    cross.cross.setAttribute("visibility", "visible");
    cross.cline.setAttribute("x1", box.X(v.t[i]));
    cross.cline.setAttribute("x2", box.X(v.t[i]));
    cross.cdot.setAttribute("cx", box.X(v.t[i]));
    cross.cdot.setAttribute("cy", box.Y(kn));
    showTip(ev, `<b>${clockAt(state.model.meta.startUtc, v.t[i])}</b> · ${hms(v.t[i])}<br>` +
                `Doppler <b>${nf(v.dopplerKn[i], 2)}</b> kn · positional ` +
                `<b>${nf(v.speedKn[i], 2)}</b> kn`);
  });
  root.addEventListener("pointerleave", () => {
    cross.cross.setAttribute("visibility", "hidden");
    hideTip();
  });

  /* --- drag to scrub, two fingers to zoom */
  root.addEventListener("pointerdown", (ev) => {
    dragged = false;                                   // see the map's handler
    if (!inPlot(ev)) return;
    if (ev.target.closest("[data-mark]") && stripPointers.size === 0) return;  // mark → popover
    stripPointers.set(ev.pointerId, ev.clientX);
    root.setPointerCapture(ev.pointerId);
    if (stripPointers.size === 2) {
      const [a, b] = [...stripPointers.values()];
      stripPinch = { span: Math.abs(a - b), t0: box.t0, t1: box.t1,
                     centre: timeAt((a + b) / 2) };
      cross.cross.setAttribute("visibility", "hidden");
      hideTip();
    } else {
      setPlayhead(timeAt(ev.clientX));
    }
    ev.preventDefault();
  });

  root.addEventListener("pointermove", (ev) => {
    if (!stripPointers.has(ev.pointerId)) return;
    if (Math.abs(stripPointers.get(ev.pointerId) - ev.clientX) > 3) dragged = true;
    stripPointers.set(ev.pointerId, ev.clientX);
    if (stripPointers.size >= 2 && stripPinch) {
      const [a, b] = [...stripPointers.values()];
      const span = Math.abs(a - b);
      if (span > 8 && stripPinch.span > 8) zoomTo(stripPinch.centre, stripPinch.span / span,
                                                  stripPinch);
      return;
    }
    setPlayhead(timeAt(ev.clientX));
  });

  /* --- wheel / trackpad zoom around the pointer. Only over the plot: a wheel on the axes
     or beside the figure is someone scrolling the page, and stealing that would be rude. */
  root.addEventListener("wheel", (ev) => {
    if (!inPlot(ev)) return;
    ev.preventDefault();
    zoomTo(timeAt(ev.clientX), Math.exp(ev.deltaY * 0.0022));
  }, { passive: false });

  root.addEventListener("dblclick", (ev) => { ev.preventDefault(); resetZoom(); });
}

/** True while the last press on a figure turned into a drag — a scrub that happens to
 *  cross a mark must not also fire that mark's popover. */
let dragged = false;

/**
 * The fingers currently on the strip, and the pinch they started.
 *
 * Module level rather than closure state on purpose: a pinch zooms, a zoom redraws the
 * strip, and the redraw throws away the SVG the gesture began on. Held in the element's
 * closure, the second move would arrive at a freshly wired figure that had never heard of
 * these fingers and the pinch would die after one step — exactly the gesture a phone uses
 * most. Held here, the new figure adopts the gesture in progress and it runs to the end.
 *
 * `stripPinch` keeps the window the pinch *started* in, so every move scales that rather
 * than compounding the last result.
 */
const stripPointers = new Map();
let stripPinch = null;

// The finger can leave the figure before it is lifted — the strip is redrawn under it on
// every pinch move, and a pointer released over the legend never reaches the figure at all.
// The window hears the release either way, so the bookkeeping cannot get stuck holding a
// phantom finger down (which would read as a pinch on the next single-finger drag).
for (const type of ["pointerup", "pointercancel"]) {
  window.addEventListener(type, (ev) => {
    stripPointers.delete(ev.pointerId);
    if (stripPointers.size < 2) stripPinch = null;
  });
}

const endStripGesture = () => { stripPointers.clear(); stripPinch = null; };

/**
 * Zoom the time axis by `factor` (>1 zooms out) about `centre`, which stays under the
 * gesture. `from` is the window the gesture started in, for a pinch — a pinch has to
 * scale the *initial* window, or each move would compound the last.
 */
function zoomTo(centre, factor, from = null) {
  const v = state.model.v;
  const full0 = v.bounds.t0, full1 = Math.max(v.bounds.t1, full0 + 1);
  const base0 = from ? from.t0 : window0(v), base1 = from ? from.t1 : window1(v);
  const span = Math.min(Math.max((base1 - base0) * factor, 4), full1 - full0);
  let t0 = centre - (centre - base0) * (span / (base1 - base0));
  let t1 = t0 + span;
  if (t0 < full0) { t0 = full0; t1 = t0 + span; }
  if (t1 > full1) { t1 = full1; t0 = t1 - span; }
  const whole = span >= (full1 - full0) - 0.5;
  state.zoom = whole ? null : { t0, t1 };
  drawStrip();
  applyPlayhead();
}

function resetZoom() {
  if (!state.zoom) return;
  state.zoom = null;
  drawStrip();
  applyPlayhead();
}

/* -------------------------------------------------------------------- the playhead */

/** Move the shared playhead. One setter, so the map dot, the chart rule and the readout
 *  can never point at different moments. */
function setPlayhead(t) {
  state.playhead = t;
  applyPlayhead();
}

export function clearPlayhead() {
  state.playhead = null;
  applyPlayhead();
}

/**
 * Put the playhead where `state.playhead` says, in both figures and in the readout.
 *
 * The map dot is interpolated between the two samples that bracket the time so it glides
 * instead of hopping from fix to fix; the numbers in the readout are the values of the
 * nearest sample, never an interpolation — the readout says what the recording says at an
 * instant, and an averaged speed would read as a measurement that was never taken.
 */
function applyPlayhead() {
  const t = state.playhead;
  const model = state.model;
  const live = state.live || {};
  const readout = el("strip-readout");

  if (t === null || t === undefined || !model) {
    live.map?.head.setAttribute("visibility", "hidden");
    live.strip?.head.setAttribute("visibility", "hidden");
    if (readout) { readout.hidden = true; readout.removeAttribute("data-t"); }
    return;
  }
  const v = model.v;
  const i = indexAt(v, t);
  const flying = inFlight(v, t);
  const tint = flying ? C.foil : C.ink2;

  if (live.map) {
    const p = interpolate(v, t);
    if (p) {
      live.map.head.setAttribute("visibility", "visible");
      live.map.head.setAttribute("data-t", t.toFixed(2));
      live.map.head.setAttribute("transform",
        `translate(${live.map.X(p.x).toFixed(2)} ${live.map.Y(p.y).toFixed(2)})`);
      live.map.halo.setAttribute("fill", tint);
      live.map.dot.setAttribute("fill", tint);
    } else {
      live.map.head.setAttribute("visibility", "hidden");
    }
  }
  if (live.strip) {
    const { X, Y, box } = live.strip;
    const inWindow = t >= box.t0 && t <= box.t1;
    live.strip.head.setAttribute("visibility", inWindow ? "visible" : "hidden");
    live.strip.head.setAttribute("data-t", t.toFixed(2));
    if (inWindow) {
      const x = X(t);
      live.strip.hline.setAttribute("x1", x.toFixed(2));
      live.strip.hline.setAttribute("x2", x.toFixed(2));
      live.strip.hdot.setAttribute("cx", x.toFixed(2));
      live.strip.hdot.setAttribute("cy", Y(v.dopplerKn[i] ?? v.speedKn[i] ?? 0).toFixed(2));
    }
  }
  if (readout) {
    readout.hidden = false;
    readout.setAttribute("data-t", t.toFixed(2));
    readout.innerHTML =
      field(clockAt(model.meta.startUtc, v.t[i]), "clock") +
      field(hms(v.t[i]), "elapsed") +
      field(nf(v.dopplerKn[i], 2), "kn Doppler") +
      field(nf(v.speedKn[i], 2), "kn positional") +
      `<span class="phase${flying ? " flying" : ""}">${flying ? "flying" : "off foil"}</span>` +
      `<button class="ghost small-btn" id="clear-playhead" type="button">Clear</button>`;
    el("clear-playhead").addEventListener("click", clearPlayhead);
  }
}

const field = (value, unit) =>
  `<span class="ro"><b>${esc(value)}</b><small>${esc(unit)}</small></span>`;

/**
 * The position at `t`, linearly interpolated between the two samples around it. Pure
 * geometry: it moves a dot along a line the document already draws, and it is never
 * reported as a number.
 */
function interpolate(v, t) {
  const i = indexAt(v, t);
  if (v.x[i] == null || v.y[i] == null) return null;
  const j = v.t[i] <= t ? i + 1 : i - 1;
  if (j < 0 || j >= v.count || v.x[j] == null || v.y[j] == null
      || v.segment[j] !== v.segment[i]) {
    return { x: v.x[i], y: v.y[i] };
  }
  const dt = v.t[j] - v.t[i];
  const f = dt === 0 ? 0 : Math.min(Math.max((t - v.t[i]) / dt, -1), 1);
  return { x: v.x[i] + (v.x[j] - v.x[i]) * f, y: v.y[i] + (v.y[j] - v.y[i]) * f };
}

/* ------------------------------------------------------------------- legend chips */

/**
 * The legend, which is also the filter. A chip with nothing to show is not a button at
 * all — it stays as a subdued caption, because the vocabulary is worth reading even when
 * this session has no instance of it (same rule as the iOS legend).
 */
function drawChips() {
  const host = el("map-legend");
  const counts = tally(state.model, state.highlight);
  const chips = LAYERS
    .filter((layer) => layer.id !== "effort" || counts.effort)
    .map((layer) => {
      const n = counts[layer.id] || 0;
      const on = visible(layer.id);
      const text = layer.id === "effort" && state.highlight?.label
        ? state.highlight.label.toLowerCase() : layer.label;
      const count = layer.id === "offFoil" ? "" : `<span class="n">${n}</span>`;
      if (!n) {
        return `<span class="item chip off-empty" data-layer="${layer.id}">` +
               `${layer.swatch()}<span>${esc(text)}</span></span>`;
      }
      return `<button type="button" class="item chip chip-btn${on ? "" : " off"}" ` +
             `data-layer="${layer.id}" aria-pressed="${on}" ` +
             `aria-label="${on ? "Hide" : "Show"} ${esc(text)}, ${n}">` +
             `${layer.swatch()}<span>${esc(text)}</span>${count}</button>`;
    }).join("");

  const showAll = state.hidden.size
    ? `<button type="button" class="ghost small-btn" id="show-all-layers">Show all</button>` : "";
  host.innerHTML = chips + showAll +
    `<p class="legend-note">Tap a chip to hide or show it on the map <em>and</em> in the
      speed strip. Solid shape = manoeuvre outcome · hollow square = straight-line flight
      end · arrow = takeoff, red u-turn = a failed attempt. Drag either figure to move the
      playhead.</p>`;

  host.onclick = (ev) => {
    const chip = ev.target.closest(".chip-btn");
    if (chip) {
      const id = chip.dataset.layer;
      if (state.hidden.has(id)) state.hidden.delete(id); else state.hidden.add(id);
      closePopover();
      drawMap();
      drawStrip();
      drawChips();
      applyPlayhead();
      return;
    }
    if (ev.target.closest("#show-all-layers")) {
      state.hidden.clear();
      drawMap();
      drawStrip();
      drawChips();
      applyPlayhead();
    }
  };
}

/** The strip's own key: the two speed channels, the bands, and the zoom escape hatch. */
function drawStripLegend() {
  const host = el("strip-legend");
  const v = state.model.v;
  const items = [
    `<span class="item">${lineSwatch(C.foil)}Doppler — drives the flight state</span>`,
    `<span class="item">${lineSwatch(C.tint)}positional — scores the turns</span>`,
  ];
  if (visible("flying")) {
    items.push(`<span class="item">${bandSwatch(C.foil)}flight (on foil)</span>`);
  }
  if (visible("pumping") && state.model.pumpSpans.length) {
    items.push(`<span class="item">${bandSwatch(C.pump, 0.35)}pumping</span>`);
  }
  const hw = visible("effort") ? highlightWindows(state.highlight) : [];
  if (hw.length) {
    items.push(`<span class="item">${bandSwatch(C.ink, 0.25)}` +
               `${esc(state.highlight.label || "record window")}` +
               `${hw.length > 1 ? ` (${hw.length} windows)` : ""}</span>`);
  }
  if (state.zoom) {
    items.push(`<span class="item zoom-state">showing ${hms(state.zoom.t0)}–` +
               `${hms(state.zoom.t1)} of ${hms(v.bounds.t1)}` +
               `<button type="button" class="ghost small-btn" id="strip-reset">Reset zoom</button></span>`);
  } else {
    items.push(`<span class="item muted-item">wheel or pinch to zoom the time axis · ` +
               `drag to scrub</span>`);
  }
  host.innerHTML = items.join("");
  const reset = el("strip-reset");
  if (reset) reset.addEventListener("click", resetZoom);
}

/* ---------------------------------------------------------------------- popovers */

/** Hover tooltip + click popover on one drawn mark. */
function annotate(node, mk, where) {
  node.setAttribute("data-mark", mk.layer);
  node.setAttribute("data-where", where);
  node.setAttribute("data-t", mk.t.toFixed(2));
  tipTarget(node, mk.tip);
  node.addEventListener("click", (ev) => {
    if (dragged) return;                 // a scrub that crossed this mark, not a tap on it
    ev.stopPropagation();
    openPopover(ev, mk);
    setPlayhead(mk.t);
  });
}

let popoverEl = null;

function openPopover(ev, facts) {
  closePopover();
  hideTip();
  const box = document.createElement("div");
  box.className = "popover";
  box.innerHTML =
    `<div class="pop-head"><b>${esc(facts.title)}</b>` +
    `<button type="button" class="pop-close" aria-label="Close">×</button></div>` +
    `<div class="pop-rows">${facts.rows.map(([k, val]) =>
      `<div><span>${esc(k)}</span><span>${esc(val)}</span></div>`).join("")}</div>`;
  document.body.appendChild(box);
  popoverEl = box;

  const pad = 12;
  const r = box.getBoundingClientRect();
  let x = ev.clientX + pad, y = ev.clientY + pad;
  if (x + r.width > window.innerWidth - 8) x = Math.max(8, ev.clientX - r.width - pad);
  if (y + r.height > window.innerHeight - 8) y = Math.max(8, ev.clientY - r.height - pad);
  box.style.left = `${x}px`;
  box.style.top = `${y}px`;

  box.querySelector(".pop-close").addEventListener("click", closePopover);
  setTimeout(() => {
    document.addEventListener("pointerdown", onOutside, true);
    document.addEventListener("keydown", onEscape, true);
  }, 0);
}

function onOutside(ev) {
  if (popoverEl && !popoverEl.contains(ev.target)) closePopover();
}

function onEscape(ev) {
  if (ev.key === "Escape") closePopover();
}

export function closePopover() {
  if (!popoverEl) return;
  popoverEl.remove();
  popoverEl = null;
  document.removeEventListener("pointerdown", onOutside, true);
  document.removeEventListener("keydown", onEscape, true);
}
