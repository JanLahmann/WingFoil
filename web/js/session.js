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
 *   - A camera on the map with the same vocabulary — pinch/wheel to zoom about the
 *     gesture, drag to pan once there is somewhere to pan to — plus buttons and a
 *     double-tap for the same, because a pinch is awkward one-handed on a beach.
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
const MARK_ORDER = ["cleanJibe", "courseChange", "flewThrough", "touchdown", "fellIn",
                    "splash", "takeoff"];

/** Chip text, from the generated token catalogue — the same strings the iOS `MapLayer.label`
 *  is checked against, so a chip cannot be renamed on one platform only. */
const LABEL = Object.fromEntries(TOKENS.layers.map((l) => [l.id, l.label]));

/**
 * The legend, in chip order. `id` is the layer, `swatch` draws the thing it toggles.
 *
 * There is no "glided out" chip: a straight-line flight end is a mark on the *same* ladder
 * drawn hollow — fill carries the channel — so it belongs to `flewThrough` (or to touchdown
 * / fell in, when that is how the flight ended). A chip of its own said the same thing
 * twice and made this app count flew-throughs differently from the iOS one.
 */
const LAYERS = [
  { id: "flying",       group: "route",  swatch: () => lineSwatch(C.foil) },
  { id: "offFoil",      group: "route",  swatch: () => lineSwatch(C.track) },
  { id: "pumping",      group: "route",  swatch: () => lineSwatch(C.pump, 4.5) },
  { id: "direction",    group: "route",  swatch: () => chevronSwatch() },
  { id: "effort",       group: "route",  swatch: () => lineSwatch(C.effort, 2.8) },
  // The events. Clean jibe leads: it is the mark a rider opens the map to find, and it is
  // the one here that is not a rung of the ladder — filing it after "fell in" would read as
  // the ladder's fourth outcome, which is exactly what it is not.
  { id: "cleanJibe",    group: "marker", swatch: () => glyphSwatch("star", C.clean) },
  { id: "flewThrough",  group: "marker", swatch: () => glyphSwatch("disc", C.good) },
  { id: "touchdown",    group: "marker", swatch: () => glyphSwatch("triangle", C.warn) },
  { id: "fellIn",       group: "marker", swatch: () => glyphSwatch("cross", C.bad) },
  { id: "courseChange", group: "marker", swatch: () => glyphSwatch("hairline", C.reject) },
  { id: "takeoff",      group: "marker", swatch: () => glyphSwatch("arrow-up", C.takeoff) },
  { id: "splash",       group: "marker", swatch: () => glyphSwatch("drop", C.splash) },
];

const OUTCOME_LAYER = { flew_through: "flewThrough", touchdown: "touchdown",
                        fell_in: "fellIn", glide_out: "flewThrough" };

/* --------------------------------------------------------------------- pairing
 *
 * docs/presentation.md, "Pairing": a takeoff, the flight it started and the end that
 * stopped it are three marks on one event, and the link between them is drawn *only* on a
 * tap. Every fact below is read verbatim from the analysis document — the flight's own
 * startTs/endTs/distM, its end's outcome, its takeoff's strokes; the only arithmetic is
 * `endTs - startTs`. The iOS app writes the same four lines from
 * `WingFoilKit/Presentation/FlightPairing.swift`, word for word, which is what stops the
 * two apps wording the same fact differently.
 */

/** What stopped a flight, in the words the callout uses. A recording that stopped is not a
 *  verdict, so a truncated (or `unknown`) end says so instead of borrowing the ladder. */
function endedWith(end) {
  if (!end || end.truncated || end.outcome === "unknown") return "recording ended";
  if (end.outcome === "fell_in") return "fell in";
  if (end.outcome === "touchdown") return "touchdown";
  return "glided out";                      // glide_out | flew_through
}

/** Whole metres below a kilometre, then two decimals of one. */
const metres = (m) => (m >= 1000 ? `${(m / 1000).toFixed(2)} km` : `${m.toFixed(0)} m`);

const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

/** Every flight with the end that stopped it and the strokes that started it. */
function flightFacts(g) {
  const ends = new Map((g.flightEnds || []).map((e) => [e.flightIndex, e]));
  const count = (g.flights || []).length;
  return (g.flights || []).map((f, index) => ({
    index,
    count,
    startTs: f.startTs,
    endTs: f.endTs,
    distM: f.distM > 0 ? f.distM : null,
    pumps: f.takeoffPumps === undefined ? null : f.takeoffPumps,
    outcome: endedWith(ends.get(index)),
  }));
}

const pairTakeoff = (f) =>
  `starts flight ${f.index + 1} · ${hms(f.endTs - f.startTs)} · ended: ${f.outcome}`;

const pairFailed = (strokes) => `no flight · ${plural(strokes, "stroke")}`;

const pairEnd = (f) =>
  `ends flight ${f.index + 1} · started ${hms(f.startTs)}`
  + (f.pumps === null ? "" : ` · ${plural(f.pumps, "pump")}`);

const pairFlight = (f) =>
  `flight ${f.index + 1} of ${f.count} · ${hms(f.endTs - f.startTs)}`
  + (f.distM === null ? "" : ` · ${metres(f.distM)}`)
  + ` · ended: ${f.outcome}`;

/** The flight a takeoff started: the one whose `startTs` is the takeoff's own. Matched on
 *  the instant rather than on a shared array index, so a mark that cannot resolve a flight
 *  gets no pairing line at all rather than a wrong number. */
const flightStartingAt = (flights, t) =>
  flights.find((f) => f.startTs === t)
  ?? flights.find((f) => t >= f.startTs && t <= f.endTs) ?? null;

const flightCovering = (flights, t) =>
  flights.find((f) => t >= f.startTs && t <= f.endTs) ?? null;

/** The direction chip's swatch: the chevron itself, at chip size and in its own ink. */
const chevronSwatch = () =>
  `<svg viewBox="-8 -8 16 16"><path d="M-3.4,-3.4 L1.8,0 L-3.4,3.4" fill="none"
    stroke="${TOKENS.direction.ink.hex}" stroke-width="1.8" stroke-linecap="round"
    stroke-linejoin="round"/></svg>`;

/* --------------------------------------------------------------------- the state */

const state = {
  result: null,        // the document on screen; a new one resets everything below
  highlight: null,     // the record window, when one is marked
  model: null,         // marks + spans, derived once per document
  playhead: null,      // session-clock seconds, or null
  zoom: null,          // {t0, t1} visible window on the strip, or null for "all of it"
  camera: null,        // {k, tx, ty} on the map, or null for "the whole track, fitted"
  hidden: new Set(),   // layer ids the chips have switched off (transient, not persisted)
  live: null,          // handles into the drawn figures, so a scrub is not a redraw
};

/* ------------------------------------------------------------------ the camera
 *
 * The map used to be a fixed plot. It is now a camera over the same fitted projection:
 * `k` magnifies about the figure's own top-left, `tx`/`ty` slide it, and the drawing
 * composes them onto the base scale — `screen = k · base + t`.
 *
 * Everything else follows for free, which is why it is done this way rather than with an
 * SVG transform on a group:
 *
 *   - the polylines are re-emitted at the new scale, so the *geometry* grows;
 *   - the markers are still drawn at their own fixed size around a moved centre, so a
 *     glyph is the same number of pixels at 4× as at 1× (a group transform would blow them
 *     up into blobs, and the number labels with them);
 *   - `chevrons()` decimates by *screen* distance, so zooming in re-spaces them instead of
 *     stretching the gaps — the arrows keep the rhythm they were tuned for;
 *   - the scale bar is handed `s · k` and re-picks its rounded distance.
 *
 * `null` means 1× — the state the figure had before any of this, so a session that is
 * never zoomed draws exactly what it always drew.
 */
const MAP_ZOOM_MAX = 8;

const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

/** Keep the camera legal: never below 1×, never panned past the edge of the plot. */
function clampCamera(cam, W, H) {
  const k = clamp(cam.k, 1, MAP_ZOOM_MAX);
  return { k, tx: clamp(cam.tx, W - k * W, 0), ty: clamp(cam.ty, H - k * H, 0) };
}

const camera = () => state.camera || { k: 1, tx: 0, ty: 0 };

/** Zoom by `factor` about the figure-local point (sx, sy), which stays put under it. */
function zoomMap(sx, sy, factor, from = null) {
  const live = state.live?.map;
  if (!live) return;
  const base = from || camera();
  const k = clamp(base.k * factor, 1, MAP_ZOOM_MAX);
  // the *unzoomed* coordinate currently under the gesture — the thing that must not move
  const bx = (sx - base.tx) / base.k, by = (sy - base.ty) / base.k;
  const next = clampCamera({ k, tx: sx - bx * k, ty: sy - by * k }, live.W, live.H);
  setCamera(next);
}

function panMap(dx, dy, from = null) {
  const live = state.live?.map;
  if (!live) return;
  const base = from || camera();
  setCamera(clampCamera({ k: base.k, tx: base.tx + dx, ty: base.ty + dy }, live.W, live.H));
}

function setCamera(next) {
  const now = camera();
  const settled = next.k <= 1.0001 ? null : next;
  const was = state.camera;
  if (!settled && !was) return;                         // already all the way out
  if (settled && was && Math.abs(now.k - next.k) < 1e-4
      && Math.abs(now.tx - next.tx) < 0.04 && Math.abs(now.ty - next.ty) < 0.04) return;
  state.camera = settled;
  drawMap();
  // The legend only has to be rebuilt when it would *say* something different: a pan moves
  // the camera many times a second and none of those change "showing 3.3×", so redrawing
  // the chips with it would throw eleven buttons away under the reader's finger.
  if (Math.abs(now.k - camera().k) > 0.005 || !was !== !settled) drawChips();
  applyPlayhead();
}

const resetCamera = () => setCamera({ k: 1, tx: 0, ty: 0 });

/* ------------------------------------------------------------------ time lookups */

/** Index of the sample nearest `t` (binary search over the ascending time array).
 *  Exported for js/sharecard.js: the share card places its splash marks by the same
 *  "nearest sample" rule the map does, and two binary searches would be one too many. */
export function indexAt(v, t) {
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
  const flights = flightFacts(g);
  const marks = [];
  const positioned = v.count && v.hasPositions !== false && v.x.length === v.count;
  const at = (t) => {
    const i = indexAt(v, t);
    return { i, x: positioned ? v.x[i] : null, y: positioned ? v.y[i] : null };
  };
  const time = (t) => `${clockAt(meta, t)} · ${hms(t)}`;

  // --- turn outcomes (solid shapes) --------------------------------------------
  for (const m of v.turnMarkers) {
    const turn = g.turns[m.i];
    const layer = m.counted && m.maneuver ? (OUTCOME_LAYER[m.outcome] || "courseChange")
                                          : "courseChange";
    // A CLEAN jibe (the engine's own `success` flag on a counted jibe) is drawn as a star
    // and answers to TWO chips: its outcome, because it is still a turn that ended some
    // way, and `cleanJibe`, because that is the question the star answers. Clean cuts
    // across the ladder rather than sitting on it, so hiding either chip hides the mark —
    // the same rule as the iOS `EventMarker.layers`.
    const clean = !!(m.counted && turn.type === "jibe" && turn.success);
    marks.push({
      layer, layers: clean ? [layer, "cleanJibe"] : [layer],
      t: m.t, x: m.x, y: m.y, kn: m.kn, style: turnStyle({ ...m, clean }), n: m.n,
      title: `#${m.n} ${m.kind}${m.counted ? "" : " (not counted)"}`,
      tip: `<b>#${m.n} ${clockAt(meta, m.t)}</b> — ${esc(m.kind)}<br>` +
           `${OUTCOME_LABEL[m.outcome] || m.outcome} · ${nf(turn.entryKn, 1)} → ` +
           `${nf(turn.minKn, 1)} kn (${nf(turn.score * 100, 0)} %)`,
      rows: [
        ["time", time(m.t)],
        ["type", `${turn.type}${turn.counted ? "" : " · not counted"}`],
        ["entry tack", `${turn.side} · turns to ${turn.direction}`],
        ["outcome", `${OUTCOME_LABEL[turn.outcome] || turn.outcome}` +
                    (turn.borderline ? " (borderline)" : "")],
        // entry → min → exit, all three on the maneuver channel (engine 0.11.0): the
        // bottom of the turn says what it cost, the exit says whether he carried it out.
        ["speed", `${nf(turn.entryKn, 2)} → ${nf(turn.minKn, 2)} → ` +
                  `${nf(turn.exitKn, 2)} kn`],
        ["score", `${nf(turn.score * 100, 0)} % · ${turn.success ? "clean" : "not clean"}`],
        ["stopped", `${nf(turn.stoppedS, 1)} s · off foil ${nf(turn.offFoilS, 1)} s`],
        ["arc", `${nf(turn.arcM, 0)} m · R ${nf(turn.radiusM, 0)} m`],
      ],
    });
  }

  // --- straight-line flight ends (hollow squares) -------------------------------
  // Same ladder as the turns, hollow instead of solid: the fill is the channel, so these
  // answer to the outcome chips rather than to one of their own.
  for (const e of v.endMarkers.filter((x) => x.drawOnMap)) {
    const end = g.flightEnds[e.i];
    const flight = flights[e.flightIndex];
    marks.push({
      layer: OUTCOME_LAYER[e.outcome] || "flewThrough", t: e.t, x: e.x, y: e.y,
      kn: e.kn ?? traceKn(v, e.t), style: endStyle(e), n: null,
      pairing: flight ? pairEnd(flight) : null,
      title: `Flight ${e.flightIndex + 1} ends · straight line`,
      tip: `<b>${clockAt(meta, e.t)}</b> — flight ${e.flightIndex + 1} ends<br>` +
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
    const flight = flightStartingAt(flights, k.startTs);
    marks.push({
      layer: "takeoff", t: k.startTs, x: p.x, y: p.y, kn: traceKn(v, k.startTs),
      style: { shape: (k.free ? TOKENS.glyphs.takeoffFree : TOKENS.glyphs.takeoffPumped)
                        .webShape,
               color: C.takeoff }, n: null,
      pairing: flight ? pairTakeoff(flight) : null,
      title: k.free ? "Free takeoff" : "Takeoff",
      tip: `<b>${clockAt(meta, k.startTs)}</b> — ${k.free ? "free takeoff" : "takeoff"}<br>` +
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
      pairing: pairFailed(ep.strokes),
      title: "Failed attempt",
      tip: `<b>${clockAt(meta, ep.startTs)}</b> — failed attempt<br>` +
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
      tip: `<b>${clockAt(meta, turn.ts)}</b> — wrist under<br>` +
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
      tip: `<b>${clockAt(meta, end.ts)}</b> — wrist under<br>straight-line flight end`,
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

  return { v, g, meta, marks, pumpSpans, positioned, flights,
           phase: positioned ? phaseRuns(v, v.flights) : [] };
}

/** How many marks/spans a layer has in this document — the input to "is this chip a
 *  control or just a caption?" (iOS: `layerTally`). */
function tally(model, highlight) {
  const counts = {};
  for (const id of MARK_ORDER) counts[id] = 0;
  // Counted per *chip*, not per mark: a clean jibe answers to two, so it is one on the
  // ladder's chip and one on the star's — which is what makes both chips live toggles.
  for (const mk of model.marks) {
    for (const id of mk.layers || [mk.layer]) counts[id] = (counts[id] || 0) + 1;
  }
  counts.flying = model.v.flights.length;
  counts.offFoil = model.v.count ? 1 : 0;
  counts.pumping = model.pumpSpans.length;
  counts.effort = highlightWindows(highlight).length;
  // Counted as "is there a track to point along", not as chevrons drawn: how many arrows
  // fit is a question about the camera, and the chip has to be live or inert before
  // anything is laid out (the iOS legend counts track runs for the same reason).
  counts.direction = model.positioned ? 1 : 0;
  return counts;
}

const visible = (id) => !state.hidden.has(id);

/** Whether a mark survives the chips. Every layer it answers to has to be on: a clean jibe
 *  carries two (its outcome and `cleanJibe`), everything else exactly one. */
const markVisible = (mk) => (mk.layers || [mk.layer]).every(visible);

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
    state.camera = null;
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
  state.camera = null;
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
  // The camera rides on top of the fit: at 1× it is the identity and this is the figure
  // that was here before. Everything downstream draws in *screen* units, so markers and
  // chevrons stay the size they were tuned at whatever `k` is (see "the camera" above).
  const cam = camera();
  const X = (x) => (ox + x * s) * cam.k + cam.tx;
  const Y = (y) => (oy - y * s) * cam.k + cam.ty;

  const zoomed = cam.k > 1.0001;
  host.classList.toggle("panning", zoomed);
  const root = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", class: "scrubbable",
                            "data-zoom": cam.k.toFixed(3),
                            "aria-label": "GPS track with event markers; drag to move the "
                                          + "replay playhead, pinch or scroll to zoom"
                                          + (zoomed ? ", drag to pan" : "") }, host);
  svg("rect", { width: W, height: H, fill: C.surface }, root);

  // The chevrons ride the *whole* route rather than the phase runs: spacing has to be
  // continuous across a takeoff, or every short off-foil run would collect its own cluster
  // of arrows (the iOS map flattens its segments for the same reason).
  const runs = polylineRuns(v, () => true);

  // The track, one run per phase, cut at the engine's exact flight boundaries. A hidden
  // line category keeps its route as a dimmer line: the chips filter what the colours
  // claim, not where the rider went.
  for (const run of model.phase) {
    const on = visible(run.flying ? "flying" : "offFoil");
    const stroke = on ? (run.flying ? C.foil : C.track) : "#2c2c2a";
    svg("polyline", { points: screenPoints(run.pts, X, Y), fill: "none", stroke,
                      "stroke-width": run.flying && on ? 2.1 : 1.4,
                      opacity: run.flying && on ? 0.9 : 1,
                      "stroke-linecap": "round", "stroke-linejoin": "round",
                      "data-phase": run.flying ? "flying" : "offFoil" }, root);
  }
  // A flying run is also the handle on its flight: tapping it says which flight this was
  // and frames it in the chart (docs/presentation.md, "Pairing"). The hit line is a wide
  // transparent twin, because a 2-unit stroke is not a tap target — and it is drawn under
  // everything that follows, so a marker on top of it still wins the tap.
  for (const run of model.phase) {
    if (!run.flying) continue;
    const flight = flightCovering(model.flights, run.pts[0][2]);
    if (!flight) continue;
    const hit = svg("polyline", { points: screenPoints(run.pts, X, Y), fill: "none",
                                  stroke: "transparent", "stroke-width": 14,
                                  "stroke-linecap": "round", "stroke-linejoin": "round",
                                  "data-flight": flight.index }, root);
    hit.style.cursor = "pointer";
    hit.addEventListener("click", (ev) => {
      if (dragged) return;                   // a scrub that crossed this run, not a tap
      ev.stopPropagation();
      openFlight(ev, flight);
    });
  }
  // Under the effort glow and under the markers: a pumping attempt is context for the
  // takeoff (or the failure) that ends it, not a thing to read on its own.
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
  // into a solid bar of chevrons. Drawn over the track and under everything else, and
  // hidden by its own chip — the arrows are not the route, so removing them leaves the
  // track exactly as it was.
  if (visible("direction")) chevrons(root, runs, X, Y, narrow ? 34 : 46);

  // The highlighted record window, on top of the track but under the markers: a dark halo
  // so the glow separates from whatever it is drawn over, then the effort ink itself — the
  // same orange the iOS map glows in, and one of the two marks the `effort` token owns.
  const hw = highlightWindows(state.highlight);
  if (hw.length && visible("effort")) {
    for (const pts of polylineRuns(v, (t) => inWindows(hw, t))) {
      const points = screenPoints(pts, X, Y);
      svg("polyline", { points, fill: "none", stroke: C.surface, "stroke-width": 6.5,
                        opacity: 0.85, "stroke-linecap": "round",
                        "stroke-linejoin": "round" }, root);
      svg("polyline", { points, fill: "none", stroke: C.effort, "stroke-width": 3.0,
                        "stroke-linecap": "round", "stroke-linejoin": "round",
                        "data-span": "effort" }, root);
    }
  }

  for (const mk of model.marks) {
    if (!markVisible(mk) || mk.x === null || mk.x === undefined) continue;
    const node = marker(root, mk.style, X(mk.x), Y(mk.y));
    annotate(node, mk, "map");
    // The number is the mark's row in the Turns table, so it rides with the mark and
    // disappears with it — a numbered label over no marker would point at nothing.
    if (mk.n !== null) label(root, X(mk.x), Y(mk.y), mk.n, mk.style.color, mk.n % 2 === 1);
  }

  if (model.g.wind) windArrow(root, model.g.wind, W, narrow);
  // The bar is a screen ruler, so it reads the *effective* scale and re-picks its rounded
  // distance — at 4× it says 100 m where it said 500 m.
  scaleBar(root, s * cam.k, PAD, H - 14);

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
  // (its fill follows the phase under it — see applyPlayhead)

  state.live.map = { root, X, Y, head, halo, dot, W, H, cam };
  wireMapInput(root);
}

/**
 * The track as runs of one phase each, **cut at the engine's exact flight boundaries**
 * (docs/presentation.md, "Phase tints").
 *
 * Asking the question per sample — "is this fix inside a flight?" — is wrong on a coarse
 * source, and wrong in the direction that flatters the rider. The 2026-08-06
 * "Wingfoiling"-app session records at 2 s with a 5 s p95, and 24 of its 54 flight
 * boundaries have an off-foil span of 5–7 s containing no positioned sample at all: the fix
 * before the landing is inside flight *n*, the fix after the next takeoff is inside flight
 * *n+1*, and the landing has nowhere to be drawn. Every 0.5 Hz native fixture in the corpus
 * has the same shape, up to 74 boundaries in one session.
 *
 * So the cut is made at the boundary *time*: the coordinate is interpolated between the two
 * fixes that straddle it, which puts the cut point exactly on the line this figure already
 * draws between them — the colour changes, the geometry does not. Consecutive runs share
 * that vertex, so there is no hole at a phase change, and every off-foil span renders as at
 * least a short grey stub.
 *
 * A recording gap still breaks the line, *except* across a boundary cut: there the two
 * straddling fixes are the only evidence there is of where the phase changed, and a hole
 * reads as the flight simply carrying on. (Corpus-wide the longest such bridge is 8 s /
 * 44 m — it is the app's sloppy cadence, not a pause on the beach.)
 */
export function phaseRuns(v, flights) {
  const cuts = [];
  for (const f of flights) {
    cuts.push({ t: f.startTs, flying: true });
    cuts.push({ t: f.endTs, flying: false });
  }
  cuts.sort((a, b) => a.t - b.t);

  const at = (i) => (v.x[i] == null || v.y[i] == null ? null : [v.x[i], v.y[i], v.t[i]]);
  const lerp = (a, b, t) => {
    const span = b[2] - a[2];
    const k = span > 0 ? Math.min(Math.max((t - a[2]) / span, 0), 1) : 1;
    return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, t];
  };

  const runs = [];
  let cur = [], flying = false, next = 0, prev = null;
  const flush = () => { if (cur.length > 1) runs.push({ flying, pts: cur }); cur = []; };

  for (let i = 0; i < v.count; i++) {
    const p = at(i);
    if (p === null) { flush(); prev = null; continue; }
    if (prev === null) {
      // The first drawable fix of a run: everything before it only decides the phase.
      while (next < cuts.length && cuts[next].t <= p[2]) flying = cuts[next++].flying;
      cur.push(p);
      prev = p;
      continue;
    }
    let cutHere = false;
    while (next < cuts.length && cuts[next].t <= p[2]) {
      const point = lerp(prev, p, cuts[next].t);
      cur.push(point);
      flush();
      flying = cuts[next].flying;
      cur.push(point);                       // shared vertex: no hole at the change
      next += 1;
      cutHere = true;
    }
    if (!cutHere && v.segment[i] !== v.segment[i - 1]) {
      flush();
      cur.push(p);
    } else if (cur.length === 0 || cur[cur.length - 1][2] !== p[2]) {
      cur.push(p);
    }
    prev = p;
  }
  flush();
  return runs;
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

/* ------------------------------------------------- map: scrubbing, pan and zoom */

/**
 * Every gesture on the map.
 *
 * The map is still the second handle on the playhead — press near the track and the
 * playhead jumps there — and it is now also a camera. The two never fight, because the
 * *shape* of the gesture decides, not where it started:
 *
 *   - a **tap** scrubs (or opens a mark's popover), whether or not it landed on the track;
 *   - a **drag** pans, once the camera is zoomed in. At 1× there is nowhere to pan to, so
 *     a drag keeps its old meaning and scrubs along the track;
 *   - **two fingers** pinch about their own midpoint, and a **wheel** zooms about the
 *     pointer.
 *
 * The moves and the releases are heard on `window`, not on the SVG: a zoom step redraws
 * the figure, which throws away the element the gesture began on, and a finger that leaves
 * the box mid-drag would otherwise take the gesture with it.
 */

const mapPointers = new Map();      // pointerId -> {x, y, onMark}
let mapPinch = null;                // {dist, cam, sx, sy} — the pinch's starting state
let mapPan = null;                  // {x, y, cam} — the drag's starting state
let mapGestured = false;            // a pan or pinch happened: this is no longer a tap
let mapFingers = 0;                 // most fingers seen in the gesture (for the two-finger tap)
let mapTap = { at: 0, x: 0, y: 0, fingers: 0 };

const endMapGesture = () => {
  mapPointers.clear();
  mapPinch = null;
  mapPan = null;
  mapGestured = false;
  mapFingers = 0;
};

/** Figure-local coordinates, in the viewBox's units (which are CSS pixels here). */
function mapLocal(clientX, clientY) {
  const live = state.live?.map;
  if (!live) return null;
  const r = live.root.getBoundingClientRect();
  if (!r.width || !r.height) return null;
  return { ux: ((clientX - r.left) / r.width) * live.W,
           uy: ((clientY - r.top) / r.height) * live.H };
}

/** The time of the fix nearest a figure-local point, or null if none is within a
 *  fingertip. The tolerance is in *screen* units, so it stays a fingertip at every zoom. */
function nearestOnTrack(ux, uy) {
  const live = state.live?.map;
  if (!live) return null;
  const v = state.model.v;
  const tolerance = 34;
  let bestT = null, bestD = Infinity;
  for (let i = 0; i < v.count; i++) {
    if (v.x[i] == null || v.y[i] == null) continue;
    const dx = live.X(v.x[i]) - ux, dy = live.Y(v.y[i]) - uy;
    const d = dx * dx + dy * dy;
    if (d < bestD) { bestD = d; bestT = v.t[i]; }
  }
  return bestD <= tolerance * tolerance ? bestT : null;
}

function wireMapInput(root) {
  root.addEventListener("pointerdown", (ev) => {
    // Before any early return: a new press is never the drag the last one was, and a mark
    // whose press is ignored here still has to be tappable (its click handler asks).
    dragged = false;
    if (ev.pointerType !== "mouse") lastTouchAt = performance.now();
    const onMark = !!ev.target.closest("[data-mark]");
    // A gesture that starts with nothing down starts clean, whatever the last one left
    // behind (a release swallowed by a redraw would otherwise make the next single tap
    // look like a two-finger one).
    if (mapPointers.size === 0) { mapFingers = 0; mapGestured = false; }
    mapPointers.set(ev.pointerId,
                    { x: ev.clientX, y: ev.clientY, x0: ev.clientX, y0: ev.clientY, onMark });
    mapFingers = Math.max(mapFingers, mapPointers.size);

    if (mapPointers.size === 2) {
      const [a, b] = [...mapPointers.values()];
      const mid = mapLocal((a.x + b.x) / 2, (a.y + b.y) / 2);
      const dist = Math.hypot(a.x - b.x, a.y - b.y);
      mapPinch = { dist, smooth: dist, seeded: dist >= PINCH_MIN, cam: camera(),
                   sx: mid?.ux ?? 0, sy: mid?.uy ?? 0 };
      mapPan = null;
      hideTip();
      ev.preventDefault();
      return;
    }
    if (mapPointers.size !== 1) return;
    if (onMark) return;                                // a marker tap opens its popover
    if (state.camera) {
      mapPan = { x: ev.clientX, y: ev.clientY, cam: camera() };
      ev.preventDefault();
      return;
    }
    // 1×: a drag has nowhere to pan to, so it keeps its old job of walking the playhead
    // along the track. A press well away from the track still does nothing at all.
    const p = mapLocal(ev.clientX, ev.clientY);
    const t = p && nearestOnTrack(p.ux, p.uy);
    if (t === null || t === undefined) return;
    setPlayhead(t);
    ev.preventDefault();
  });

  // Two fingers on the figure are a pinch, never a page scroll. `touch-action` cannot say
  // that (it is latched when the first finger lands, and one finger still has to scroll
  // the page over a map this tall), so the second finger's own events say it instead.
  lockTwoFingerScroll(root);

  root.addEventListener("wheel", (ev) => {
    const p = mapLocal(ev.clientX, ev.clientY);
    if (!p) return;
    ev.preventDefault();
    // A trackpad pinch arrives as a wheel with ctrlKey and much bigger deltas; the two
    // share one exponent so a mouse notch and a trackpad pinch feel like the same control.
    zoomMap(p.ux, p.uy, Math.exp(-ev.deltaY * (ev.ctrlKey ? 0.01 : 0.0025)));
  }, { passive: false });

  root.addEventListener("dblclick", (ev) => {
    if (fromTouch()) return;                   // the touch double-tap already zoomed in
    ev.preventDefault();
    resetCamera();
  });
}

function onMapPointerMove(ev) {
  const p = mapPointers.get(ev.pointerId);
  if (!p) return;
  p.x = ev.clientX;
  p.y = ev.clientY;

  if (mapPointers.size >= 2 && mapPinch) {
    const [a, b] = [...mapPointers.values()];
    const dist = Math.hypot(a.x - b.x, a.y - b.y);
    // Same floor and the same smoothing as the strip: two fingertips a few pixels apart
    // measure noise rather than intent, and a pinch that begins that close is re-seated
    // when the fingers part instead of being dead for the rest of the gesture.
    if (!mapPinch.seeded) {
      if (dist < PINCH_MIN) return;
      mapPinch = { dist, smooth: dist, seeded: true, cam: camera(),
                   sx: mapPinch.sx, sy: mapPinch.sy };
      return;
    }
    // Only now is this a gesture rather than two fingers resting: a two-finger *tap* has to
    // survive as a tap, because that is the way back out of the zoom.
    dragged = true;
    mapGestured = true;
    mapPinch.smooth += (dist - mapPinch.smooth) * PINCH_SMOOTH;
    zoomMap(mapPinch.sx, mapPinch.sy,
            Math.max(mapPinch.smooth, PINCH_MIN) / mapPinch.dist, mapPinch.cam);
    return;
  }
  if (mapPan) {
    const live = state.live?.map;
    if (!live) return;
    const r = live.root.getBoundingClientRect();
    const dx = (ev.clientX - mapPan.x) * (r.width ? live.W / r.width : 1);
    const dy = (ev.clientY - mapPan.y) * (r.height ? live.H / r.height : 1);
    // A few pixels of slop, so a tap that trembles is still a tap and still scrubs.
    if (!mapGestured && Math.hypot(dx, dy) <= 4) return;
    dragged = true;
    mapGestured = true;
    panMap(dx, dy, mapPan.cam);
    return;
  }
  if (state.camera) return;                    // zoomed: a one-finger drag pans, never scrubs
  if (p.onMark) return;
  const local = mapLocal(ev.clientX, ev.clientY);
  if (!local) return;
  if (Math.hypot(ev.clientX - p.x0, ev.clientY - p.y0) > 4) dragged = true;
  const t = nearestOnTrack(local.ux, local.uy);
  if (t !== null) setPlayhead(t);
}

function onMapPointerUp(ev) {
  if (!mapPointers.has(ev.pointerId)) return;
  const was = mapPointers.get(ev.pointerId);
  mapPointers.delete(ev.pointerId);
  if (mapPointers.size < 2) mapPinch = null;
  if (mapPointers.size !== 0) return;

  const fingers = mapFingers;
  const gestured = mapGestured;
  mapPan = null;
  mapGestured = false;
  mapFingers = 0;

  if (ev.type === "pointercancel") return;
  // While zoomed the press started a pan rather than a scrub, because it could not know
  // yet which it would become. It turned out to be a tap, so it scrubs after all.
  if (!gestured && fingers === 1 && state.camera && !was?.onMark) {
    const p = mapLocal(ev.clientX, ev.clientY);
    const t = p && nearestOnTrack(p.ux, p.uy);
    if (t !== null && t !== undefined) setPlayhead(t);
  }

  if (gestured || ev.pointerType === "mouse") return;
  // A clean tap, on touch. One finger twice zooms in about it; two fingers twice go back —
  // the same pair the strip offers, and the reset chip is the way out of either.
  const now = performance.now();
  const near = now - mapTap.at < 340
    && Math.hypot(ev.clientX - mapTap.x, ev.clientY - mapTap.y) < 44
    && mapTap.fingers === fingers;
  if (!near) { mapTap = { at: now, x: ev.clientX, y: ev.clientY, fingers }; return; }
  mapTap = { at: 0, x: 0, y: 0, fingers: 0 };
  if (fingers >= 2) { resetCamera(); return; }
  if (was?.onMark) return;                     // a double-tap on a mark is two mark taps
  const p = mapLocal(ev.clientX, ev.clientY);
  if (p) zoomMap(p.ux, p.uy, 2);
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
      tipTarget(band, `<b>${clockAt(model.meta, span.t0)}</b> — pumping<br>` +
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
                               fill: C.effort, opacity: 0.18, "data-band": "effort" }, plot);
    for (const x of [x0, x1]) {
      svg("line", { x1: x, x2: x, y1: T, y2: H - B, stroke: C.effort, "stroke-width": 1.1,
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
                              "font-weight": 700, fill: C.effort, stroke: C.surface,
                              "stroke-width": 3, "paint-order": "stroke" }, plot);
      t.textContent = state.highlight.label;
    }
  });

  // The two speed channels are *series*, not phases: they keep the app's own blue, and
  // the teal above them is the flight shading — the same split the iOS chart makes.
  series(plot, v, v.speedKn, X, Y, C.tint, 1.0, 0.85, t0, t1);
  series(plot, v, v.dopplerKn, X, Y, C.series, 1.5, 1, t0, t1);

  for (const mk of state.model.marks) {
    if (!markVisible(mk) || !inView(mk.t)) continue;
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
  const cdot = svg("circle", { r: 3.4, fill: C.series, stroke: C.surface,
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
  const timeAt = (clientX) => stripTimeAt(clientX);

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
    showTip(ev, `<b>${clockAt(state.model.meta, v.t[i])}</b> · ${hms(v.t[i])}<br>` +
                `Doppler <b>${nf(v.dopplerKn[i], 2)}</b> kn · positional ` +
                `<b>${nf(v.speedKn[i], 2)}</b> kn`);
  });
  root.addEventListener("pointerleave", () => {
    cross.cross.setAttribute("visibility", "hidden");
    hideTip();
  });

  /* --- drag to scrub, two fingers to zoom.
     Only the press is heard here. The moves and the releases are on `window` (see below):
     a zoom step redraws the strip, which deletes the element this listener belongs to. */
  root.addEventListener("pointerdown", (ev) => {
    dragged = false;                                   // see the map's handler
    if (ev.pointerType !== "mouse") lastTouchAt = performance.now();
    if (!inPlot(ev)) return;
    // A press on a mark is registered like any other finger — it is only barred from
    // *scrubbing*, because the mark's own click opens the popover. It used to be dropped
    // outright, which meant a pinch whose first finger happened to land on one of the ~100
    // glyphs never became a pinch at all: the second finger arrived as "the first", and the
    // gesture scrubbed instead of zooming. On a busy strip that is most of them.
    const onMark = !!ev.target.closest("[data-mark]");
    if (stripPointers.size === 0) { stripFingers = 0; stripPinched = false; }
    stripPointers.set(ev.pointerId,
                      { x: ev.clientX, y: ev.clientY, x0: ev.clientX, onMark });
    stripFingers = Math.max(stripFingers, stripPointers.size);
    if (stripPointers.size === 2) {
      beginStripPinch();
      cross.cross.setAttribute("visibility", "hidden");
      hideTip();
      ev.preventDefault();
      return;
    }
    if (stripPointers.size !== 1 || onMark) return;
    setPlayhead(timeAt(ev.clientX));
    ev.preventDefault();
  });

  // Two fingers on the figure are a pinch, never a page scroll or a page zoom.
  lockTwoFingerScroll(root);

  /* --- wheel / trackpad zoom around the pointer. Only over the plot: a wheel on the axes
     or beside the figure is someone scrolling the page, and stealing that would be rude. */
  root.addEventListener("wheel", (ev) => {
    if (!inPlot(ev)) return;
    ev.preventDefault();
    zoomTo(timeAt(ev.clientX), Math.exp(ev.deltaY * (ev.ctrlKey ? 0.009 : 0.0022)));
  }, { passive: false });

  root.addEventListener("dblclick", (ev) => {
    if (fromTouch()) return;                   // the touch double-tap already zoomed in
    ev.preventDefault();
    resetZoom();
  });
}

/** True while the last press on a figure turned into a drag — a scrub that happens to
 *  cross a mark must not also fire that mark's popover. */
let dragged = false;

/**
 * When a finger last touched a figure.
 *
 * A touch double-tap also synthesises a `dblclick`, and the two handlers disagree on
 * purpose: on a mouse a double-click *resets* the zoom (there is a wheel for going in), on
 * a finger a double-tap zooms *in* (there is no wheel). Left alone the compatibility event
 * arrives second and undoes the tap. So `dblclick` only listens when no finger has been
 * near the figure recently.
 */
let lastTouchAt = 0;
const fromTouch = () => performance.now() - lastTouchAt < 700;

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
let stripPinched = false;    // a pinch happened in this gesture (see the lift guard)
let stripFingers = 0;        // most fingers seen in it, for the double-tap
let stripTap = { at: 0, x: 0, y: 0, fingers: 0 };

/** Below this many pixels apart, two fingertips measure noise rather than intent. */
const PINCH_MIN = 28;
/** How much of a new span reading to believe per move — the rest is the previous one. */
const PINCH_SMOOTH = 0.45;

/** The strip's live geometry, whichever redraw produced it. */
function stripTimeAt(clientX) {
  const live = state.live?.strip;
  if (!live) return 0;
  const b = live.box;
  const r = live.root.getBoundingClientRect();
  const ux = r.width ? ((clientX - r.left) / r.width) * b.W : 0;
  const t = b.t0 + ((ux - b.L) / (b.W - b.L - b.R)) * (b.t1 - b.t0);
  return clamp(t, b.t0, b.t1);
}

/**
 * Start (or re-seat) the pinch.
 *
 * The span is the fingers' full distance, not their horizontal separation: only the time
 * axis moves, but a pinch held at an angle is still a pinch and measuring one component of
 * it turns a steady gesture into a jittery one.
 *
 * A pinch that *starts* with the fingers closer than `PINCH_MIN` is not thrown away — it
 * is left un-seeded and seeded on the first move that clears the floor, so it scales from
 * there. The old code compared the starting span with the floor and, if it failed, the
 * whole gesture was dead however far the fingers then travelled.
 */
function beginStripPinch() {
  const live = state.live?.strip;
  if (!live) return;
  const [a, b] = [...stripPointers.values()];
  const dist = Math.hypot(a.x - b.x, a.y - b.y);
  stripPinch = { span: dist, smooth: dist, seeded: dist >= PINCH_MIN,
                 t0: live.box.t0, t1: live.box.t1,
                 centre: stripTimeAt((a.x + b.x) / 2) };
  stripPinched = true;
}

function onStripPointerMove(ev) {
  const p = stripPointers.get(ev.pointerId);
  if (!p) return;
  if (Math.abs(p.x0 - ev.clientX) > 3) dragged = true;
  p.x = ev.clientX;
  p.y = ev.clientY;

  if (stripPointers.size >= 2 && stripPinch) {
    const [a, b] = [...stripPointers.values()];
    const dist = Math.hypot(a.x - b.x, a.y - b.y);
    if (!stripPinch.seeded) {
      if (dist < PINCH_MIN) return;
      beginStripPinch();                       // the fingers have parted: scale from here
      return;
    }
    stripPinch.smooth += (dist - stripPinch.smooth) * PINCH_SMOOTH;
    zoomTo(stripPinch.centre, stripPinch.span / Math.max(stripPinch.smooth, PINCH_MIN),
           stripPinch);
    return;
  }
  // The lift guard. A pinch ends one finger at a time, and the finger still down is not
  // suddenly a scrub — it is the tail of the gesture that was just zooming. Without this
  // the playhead jumps to wherever that finger happens to be, in *either* lift order,
  // which is how a careful zoom ended somewhere else entirely.
  if (stripPinched || p.onMark) return;
  setPlayhead(stripTimeAt(ev.clientX));
}

function onStripPointerUp(ev) {
  if (!stripPointers.has(ev.pointerId)) return;
  const was = stripPointers.get(ev.pointerId);
  stripPointers.delete(ev.pointerId);
  if (stripPointers.size < 2) stripPinch = null;
  if (stripPointers.size !== 0) return;

  const fingers = stripFingers;
  const moved = dragged;                       // a two-finger *tap* never moved anything
  stripPinched = false;
  stripFingers = 0;
  if (ev.type === "pointercancel" || moved || ev.pointerType === "mouse") return;

  // A clean tap, on touch: one finger twice zooms in about it, two fingers twice go back.
  // (The mouse keeps its documented double-click-to-reset — a mouse has a wheel.)
  const now = performance.now();
  const near = now - stripTap.at < 340
    && Math.hypot(ev.clientX - stripTap.x, ev.clientY - stripTap.y) < 44
    && stripTap.fingers === fingers;
  if (!near) { stripTap = { at: now, x: ev.clientX, y: ev.clientY, fingers }; return; }
  stripTap = { at: 0, x: 0, y: 0, fingers: 0 };
  if (fingers >= 2) resetZoom();
  else if (!was?.onMark) zoomTo(stripTimeAt(ev.clientX), 0.5);
}

// The finger can leave the figure before it is lifted — the strip is redrawn under it on
// every pinch move, and a pointer released over the legend never reaches the figure at all.
// The window hears both the moves and the release, so a fast gesture that outruns the
// figure keeps working and the bookkeeping cannot get stuck holding a phantom finger down.
window.addEventListener("pointermove", (ev) => {
  onStripPointerMove(ev);
  onMapPointerMove(ev);
}, { passive: true });
for (const type of ["pointerup", "pointercancel"]) {
  window.addEventListener(type, (ev) => {
    onStripPointerUp(ev);
    onMapPointerUp(ev);
  });
}

/**
 * Hold the page still while two fingers are working a figure.
 *
 * `touch-action` cannot express this: it is latched when the *first* finger lands, and one
 * finger over a figure this tall still has to scroll the page. So the touch events say it
 * instead — as soon as there are two of them on the figure, the browser's own pan and
 * page-zoom are cancelled and the gesture belongs to the figure until a finger comes off.
 */
function lockTwoFingerScroll(node) {
  for (const type of ["touchstart", "touchmove"]) {
    node.addEventListener(type, (ev) => {
      if (ev.touches.length >= 2 && ev.cancelable) ev.preventDefault();
    }, { passive: false });
  }
}

const endStripGesture = () => {
  stripPointers.clear();
  stripPinch = null;
  stripPinched = false;
  stripFingers = 0;
  endMapGesture();
};

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
  const tint = flying ? C.foil : C.track;          // the phase tints, same as the track

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
      field(clockAt(model.meta, v.t[i]), "clock") +
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

/* --------------------------------------------------------------- zoom affordances
 *
 * A gesture nobody can find is not an affordance, and a pinch is hard on a phone held in
 * one hand on a beach. So each figure carries the same three buttons beside its caption —
 * out, in, and (only while it is zoomed) the way back — at a real touch size. They do
 * exactly what the gestures do, about the middle of the figure, so nothing here is a
 * second way of thinking about the zoom.
 */
function zoomBar(kind, caption, zoomed) {
  return `<span class="item zoom-state">${esc(caption)}` +
    `<span class="zoom-btns">` +
    `<button type="button" class="ghost small-btn zoom-btn" data-zoom="${kind}:out" ` +
    `aria-label="Zoom out">&minus;</button>` +
    `<button type="button" class="ghost small-btn zoom-btn" data-zoom="${kind}:in" ` +
    `aria-label="Zoom in">+</button>` +
    (zoomed ? `<button type="button" class="ghost small-btn" data-zoom="${kind}:reset">` +
              `Reset zoom</button>` : "") +
    `</span></span>`;
}

/** Handle a click on any of those buttons. Returns true when it was one. */
function onZoomButton(ev) {
  const button = ev.target.closest("[data-zoom]");
  if (!button) return false;
  const [kind, action] = button.dataset.zoom.split(":");
  if (kind === "map") {
    const live = state.live?.map;
    if (!live) return true;
    if (action === "reset") resetCamera();
    else zoomMap(live.W / 2, live.H / 2, action === "in" ? 1.8 : 1 / 1.8);
    return true;
  }
  if (action === "reset") resetZoom();
  else {
    const v = state.model.v;
    const centre = (window0(v) + window1(v)) / 2;
    zoomTo(centre, action === "in" ? 0.55 : 1 / 0.55);
  }
  return true;
}

/* ------------------------------------------------------------------- legend chips */

/**
 * The legend, which is also the filter. A chip with nothing to show is not a button at
 * all — it stays as a subdued caption, because the vocabulary is worth reading even when
 * this session has no instance of it (same rule as the iOS legend).
 *
 * **Three groups, one question each**, and the utilities are not one of the questions:
 *
 *   1. the **route** — how the track itself is drawn;
 *   2. the **events on it** — the clean-jibe star first, then the ladder, then the effort
 *      marks. A visible gap (`.chip-group + .chip-group`) separates it from the route, so
 *      the wrap reads as two sentences rather than eleven unrelated words;
 *   3. the **utilities** — Show all (only while something is hidden) and the zoom bar,
 *      trailing-aligned, because neither of them toggles a layer.
 *
 * The legend note stays last, under all three. iOS's `MapLegendView` groups the identical
 * three, in the same order.
 */
function drawChips() {
  const host = el("map-legend");
  const counts = tally(state.model, state.highlight);
  const chip = (layer) => {
    const n = counts[layer.id] || 0;
    const on = visible(layer.id);
    // The effort chip is labelled with the window it is currently highlighting ("best
    // 2 s"), which is what the iOS chip says; the catalogue's "best effort" is the
    // fallback. Every other chip is the catalogue's word, verbatim.
    const text = layer.id === "effort" && state.highlight?.label
      ? state.highlight.label.toLowerCase() : LABEL[layer.id];
    // Two chips are properties of the route rather than tallies of events, and "1" beside
    // them would read as "one off-foil thing" — they carry no number.
    const count = layer.id === "offFoil" || layer.id === "direction"
      ? "" : `<span class="n">${n}</span>`;
    if (!n) {
      return `<span class="item chip off-empty" data-layer="${layer.id}">` +
             `${layer.swatch()}<span>${esc(text)}</span></span>`;
    }
    return `<button type="button" class="item chip chip-btn${on ? "" : " off"}" ` +
           `data-layer="${layer.id}" aria-pressed="${on}" ` +
           `aria-label="${on ? "Hide" : "Show"} ${esc(text)}, ${n}">` +
           `${layer.swatch()}<span>${esc(text)}</span>${count}</button>`;
  };
  const group = (name) => {
    const inner = LAYERS
      .filter((layer) => layer.group === name)
      .filter((layer) => layer.id !== "effort" || counts.effort)
      .map(chip).join("");
    return inner ? `<span class="chip-group">${inner}</span>` : "";
  };

  const showAll = state.hidden.size
    ? `<button type="button" class="ghost small-btn" id="show-all-layers">Show all</button>` : "";
  const zoomed = !!state.camera;
  const utilities = showAll
    + (state.model.positioned
        ? zoomBar("map", zoomed
            ? `showing ${camera().k.toFixed(1)}×`
            : "pinch, scroll or double-tap to zoom", zoomed)
        : "");
  host.innerHTML = group("route") + group("marker")
    + (utilities ? `<span class="chip-group chip-utilities">${utilities}</span>` : "")
    + `<p class="legend-note">Tap a chip to hide or show it on the map <em>and</em> in the
      speed strip. Chevrons point the way you were riding. Star = a clean jibe, the ones you
      flew all the way through carrying your speed · solid shape = manoeuvre outcome ·
      hollow square = straight-line flight end, on the same colour ladder · arrow = takeoff,
      red u-turn = a failed attempt. A starred jibe needs both its chips: hide its outcome
      and the star goes with it. Tap either figure to move the playhead; tap a mark —
      or a flown stretch of track — for which flight it belongs to. Zoomed in, a drag on the
      map pans it.</p>`;

  host.onclick = (ev) => {
    if (onZoomButton(ev)) return;
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
    `<span class="item">${lineSwatch(C.series)}Doppler — drives the flight state</span>`,
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
    items.push(`<span class="item">${bandSwatch(C.effort, 0.3)}` +
               `${esc(state.highlight.label || "record window")}` +
               `${hw.length > 1 ? ` (${hw.length} windows)` : ""}</span>`);
  }
  items.push(zoomBar("strip", state.zoom
    ? `showing ${hms(state.zoom.t0)}–${hms(state.zoom.t1)} of ${hms(v.bounds.t1)}`
    : "wheel, pinch or double-tap to zoom the time axis · drag to scrub", !!state.zoom));
  host.innerHTML = items.join("");
  // One id kept for the manual checklist and for anything that reaches for "the reset chip".
  const reset = host.querySelector('[data-zoom="strip:reset"]');
  if (reset) reset.id = "strip-reset";
  host.onclick = onZoomButton;
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

/**
 * A tap on a flying stretch of track: its flight's facts, and the strip framed on it.
 *
 * The zoom is the flight plus a margin either side — the same window the pinch moves, so
 * the reset chip the strip already carries is the way out of it (docs/presentation.md,
 * "Pairing"). The playhead goes to the start of the run that was tapped, which is where the
 * reader's finger already is.
 */
function openFlight(ev, flight) {
  const v = state.model.v;
  const margin = Math.max((flight.endTs - flight.startTs) * 0.2, 2);
  const full1 = Math.max(v.bounds.t1, v.bounds.t0 + 1);
  const t0 = Math.max(v.bounds.t0, flight.startTs - margin);
  const t1 = Math.min(full1, flight.endTs + margin);
  state.zoom = (t1 - t0) >= (full1 - v.bounds.t0) - 0.5 ? null : { t0, t1 };
  openPopover(ev, {
    title: `Flight ${flight.index + 1}`,
    pairing: pairFlight(flight),
    rows: [
      ["time", `${clockAt(state.model.meta, flight.startTs)} · ${hms(flight.startTs)}`],
      ["duration", hms(flight.endTs - flight.startTs)],
      ["distance", flight.distM === null ? "—" : metres(flight.distM)],
      ["ended", flight.outcome],
      ["pumps", flight.pumps === null ? "— (no wrist accelerometer)" : `${flight.pumps}`],
    ],
  });
  setPlayhead(Math.min(Math.max(state.playhead ?? flight.startTs, flight.startTs),
                       flight.endTs));
  drawStrip();
  applyPlayhead();
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
    // The pairing line: which flight this mark belongs to, and what became of it. Present
    // only on a flight boundary, and only ever because something was tapped
    // (docs/presentation.md, "Pairing").
    (facts.pairing ? `<p class="pop-pair">${esc(facts.pairing)}</p>` : "") +
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
