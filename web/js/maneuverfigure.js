/* **One maneuver, in its own little frame** — the JavaScript twin of the kit's
 * `ManeuverFigure`, `TurnSlice`, `FlightEndSlice`, `SliceAngles` and `TurnSpeedRamp`.
 *
 * The session map answers "where did I ride". A single jibe is thirty metres of water inside
 * two kilometres of it, and at session scale it is four pixels. Reading one turn means
 * throwing the session away and drawing the turn: local metres around its own entry point,
 * its own time zero, and — where the wind is known — its own rotation.
 *
 * The iPhone app is the reference and this file is the port, so every constant, every
 * rounding and every fallback below is the Swift's:
 *
 *   ios/WingFoilKit/Sources/WingFoilKit/Presentation/ManeuverFigure.swift
 *   ios/WingFoilKit/Sources/WingFoilKit/Presentation/TurnSlice.swift
 *   ios/WingFoilKit/Sources/WingFoilKit/Presentation/FlightEndSlice.swift
 *   ios/WingFoilKit/Sources/WingFoilKit/Presentation/SliceAngles.swift
 *   ios/WingFoilKit/Sources/WingFoilKit/Presentation/TurnSpeedRamp.swift
 *
 * **The one deliberate simplification, and why it is not a divergence.** The phone projects
 * the window itself: equirectangular around the turn's entry point, `cos(entry latitude)`
 * for the east metres. The browser never sees the degrees. What it has is `view.x` and
 * `view.y` — the same east/north metres the engine itself computed
 * (`web/lab_bundle/web_entry.py`, `_view`), equirectangular around the *track's* centre. So
 * the port translates rather than projects: subtract the anchor sample's metres and the
 * origin is the entry point, which is what the projection was for. The two frames differ
 * only in which latitude fed `cos`, and a session spans hundredths of a degree, so the
 * scale error over a forty-metre turn is far under a millimetre. The `y` axis and both
 * constants are already identical, because the engine wrote them.
 *
 * The second simplification is `view.stride`: a very long recording is decimated before it
 * reaches the browser, so a turn drawn from it has every `stride`-th sample rather than
 * every sample. The drawing says so in its own words rather than pretending otherwise.
 *
 * Nothing here touches the DOM. That is js/turnpage.js, and it is split this way so
 * web/tools/verify_turn_figure.py can run the arithmetic under node and compare it with the
 * same rules written out again in Python.
 */

import { TOKENS } from "./tokens.js";

/* ------------------------------------------------------------------ constants */

/** A step shorter than this has no usable bearing: at 1 Hz a rider who has stopped produces
 *  a metre of GPS noise per sample, and the bearing of a metre of noise is a random number. */
export const MIN_STEP_M = 0.5;
/** Framing margin, as a fraction of the drawn turn's larger side. */
export const PAD_FRACTION = 0.14;
/** No frame is ever narrower than this. */
export const MIN_SPAN_M = 20;
/** Default lead-in and run-out either side of the event, in seconds. */
export const DEFAULT_PAD_S = 8;

/** The engine defaults, for a document whose config echo predates a key. Every one of them
 *  is read from `g.config` first and only falls back to these. */
const FALLBACK = {
  entrySpeedWindow: 3,
  minSpeedLag: 2,
  turnOutcomeLookahead: 12,
  turnRecoverPct: 80,
  foilEntrySpeed: 12,
  turnCleanQuietS: 10,
};

const KMH_TO_KN = 1 / 1.852;

/* -------------------------------------------------------------------- helpers */

/** 0…360. */
export function normalizeDeg(degrees) {
  const wrapped = degrees % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

/** Signed shortest turn from one bearing to another, −180…180. */
export function deltaDeg(from, to) {
  let d = (to - from) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

const finite = (v) => v !== null && v !== undefined && Number.isFinite(v);

/** The config value in force for this document, never a literal. */
export function cfg(config, key) {
  const v = config ? config[key] : null;
  return finite(v) ? v : FALLBACK[key];
}

/* ------------------------------------------------------------------- the frame */

/**
 * The bearing from each vertex to the next, written onto the vertex it leaves.
 *
 * The last vertex inherits the one before it rather than being left null: it is the end of
 * the run-out, and a tick that vanished at the edge of the frame would read as a gap in the
 * recording.
 */
export function applyHeadings(points) {
  if (points.length < 2) return points;
  for (let i = 0; i < points.length - 1; i++) {
    const dx = points[i + 1].x - points[i].x;
    const dy = points[i + 1].y - points[i].y;
    if (Math.sqrt(dx * dx + dy * dy) < MIN_STEP_M) continue;
    points[i].headingDeg = normalizeDeg((Math.atan2(dx, dy) * 180) / Math.PI);
  }
  points[points.length - 1].headingDeg = points[points.length - 2].headingDeg;
  return points;
}

/**
 * Rotate the frame so the direction the wind blows **from** points at the top.
 *
 * `windFromDeg` is a compass bearing, so the "from" direction is the unit vector
 * `(sin W, cos W)` and this is the rotation that takes it to `(0, 1)`. A rider running
 * downwind therefore travels toward the bottom of the frame, which is the whole of the
 * reason for wind up: the track comes down the page, sweeps across, and goes back up.
 */
export function rotate(points, windFromDeg) {
  const radians = (windFromDeg * Math.PI) / 180;
  const sinW = Math.sin(radians);
  const cosW = Math.cos(radians);
  return points.map((p) => ({
    ...p,
    x: p.x * cosW - p.y * sinW,
    y: p.x * sinW + p.y * cosW,
    headingDeg: p.headingDeg === null || p.headingDeg === undefined
      ? null : normalizeDeg(p.headingDeg - windFromDeg),
  }));
}

export function boundsAround(points) {
  if (!points.length) return null;
  let b = { minX: points[0].x, minY: points[0].y, maxX: points[0].x, maxY: points[0].y };
  for (const p of points.slice(1)) {
    b = { minX: Math.min(b.minX, p.x), minY: Math.min(b.minY, p.y),
          maxX: Math.max(b.maxX, p.x), maxY: Math.max(b.maxY, p.y) };
  }
  return b;
}

export const boundsWidth = (b) => b.maxX - b.minX;
export const boundsHeight = (b) => b.maxY - b.minY;
export const boundsCenterX = (b) => (b.minX + b.maxX) / 2;
export const boundsCenterY = (b) => (b.minY + b.maxY) / 2;

/** Grow by `fraction` of the larger side on every edge, and never come out narrower than
 *  `MIN_SPAN_M`. A fraction of the *larger* side, so a turn sailed along one line does not
 *  get a fat margin across its width and a thin one along its length. */
export function padBounds(b, fraction = PAD_FRACTION) {
  if (!b) return null;
  const pad = Math.max(boundsWidth(b), boundsHeight(b), MIN_SPAN_M) * fraction;
  return { minX: b.minX - pad, minY: b.minY - pad, maxX: b.maxX + pad, maxY: b.maxY + pad };
}

export function unionBounds(a, b) {
  if (!a) return b;
  if (!b) return a;
  return { minX: Math.min(a.minX, b.minX), minY: Math.min(a.minY, b.minY),
           maxX: Math.max(a.maxX, b.maxX), maxY: Math.max(a.maxY, b.maxY) };
}

/** A scale bar the frame has room for: 50 m, 25 m or 10 m, whichever is the largest that
 *  fits comfortably inside the drawn width, and 10 m as the floor. */
export function scaleBarM(spanM) {
  for (const candidate of [50, 25, 10]) if (candidate <= spanM * 0.45) return candidate;
  return 10;
}

/* --------------------------------------------------------------- the speed ramp */

/** Where the hot end of the ramp sits, as a multiple of the turn's entry speed. */
export const OVERSPEED_CAP = 1.3;
/** A turn entered under this is not a turn with a reference speed. */
export const MIN_REFERENCE_KN = 0.5;
/** Where the cold end sits, as a fraction of the entry speed. Not zero: a jibe is ridden
 *  between roughly two thirds of its entry speed and the entry speed, and a ramp that
 *  started at 0 kn spent its cold half on speeds nobody foils at. */
export const COLD_FRACTION = 0.5;

const hexToRgb = (hex) => ({
  red: parseInt(hex.slice(1, 3), 16) / 255,
  green: parseInt(hex.slice(3, 5), 16) / 255,
  blue: parseInt(hex.slice(5, 7), 16) / 255,
});

/** The five stops, generated from design/tokens.json by way of js/tokens.js — the same
 *  five `DesignTokens.Speed.rampRGB` gives the phone. */
export const RAMP_RGB = ["stopped", "slow", "entry", "fast", "fastest"]
  .map((name) => hexToRgb(TOKENS.speed[name].hex));

/** Where `kn` sits on the ramp, 0…1, against **this turn's entry speed**. The anchor is the
 *  whole design: a fraction of the fastest vertex would make every turn its own scale. */
export function rampPosition(kn, entryKn) {
  if (!(entryKn >= MIN_REFERENCE_KN) || !(kn > 0)) return 0;
  if (kn <= entryKn) {
    const cold = entryKn * COLD_FRACTION;
    return 0.5 * Math.min(Math.max((kn - cold) / (entryKn - cold), 0), 1);
  }
  const over = (kn - entryKn) / (entryKn * (OVERSPEED_CAP - 1));
  return 0.5 + 0.5 * Math.min(over, 1);
}

/** Which two stops a position falls between, and how far it is from the first. */
export function rampStop(position) {
  const stops = RAMP_RGB.length;
  const scaled = Math.min(Math.max(position, 0), 1) * (stops - 1);
  const lower = Math.min(Math.floor(scaled), stops - 2);
  return { lower, upper: lower + 1, blend: scaled - lower };
}

/** The ink for a position on the ramp, as a CSS colour. */
export function rampColor(position) {
  const { lower, upper, blend } = rampStop(position);
  const from = RAMP_RGB[lower];
  const to = RAMP_RGB[upper];
  const mix = (a, b) => Math.round((a + (b - a) * blend) * 255);
  return `rgb(${mix(from.red, to.red)}, ${mix(from.green, to.green)}, `
    + `${mix(from.blue, to.blue)})`;
}

export const rampColorFor = (kn, entryKn) => rampColor(rampPosition(kn, entryKn));

/** The bottom of the legend's bar — the cold end, in knots. */
export const legendBottomKn = (entryKn) => entryKn * COLD_FRACTION;

/** The top: the entry speed, or the turn's own maximum where it went faster, never past the
 *  cap. A turn that never beat its entry speed gets two labels instead of three. */
export const legendTopKn = (entryKn, maxKn) =>
  Math.max(entryKn, Math.min(maxKn, entryKn * OVERSPEED_CAP));

/* ------------------------------------------------------------------- the window */

/**
 * The positioned samples of `[from, to]`, on the **maneuver channel**.
 *
 * `view.speedKn` is the engine's hybrid speed, which is what the verdict was scored on; the
 * Doppler channel beside it is smoothed through a turn and would draw the marks a knot and a
 * half off the line they name. The phone makes the same choice in
 * `SessionDetail.buildTurnSamples`.
 */
export function windowSamples(view, from, to) {
  const out = [];
  if (!view || !view.count || view.hasPositions === false) return out;
  for (let i = 0; i < view.count; i++) {
    const t = view.t[i];
    if (!finite(t) || t < from || t > to) continue;
    const x = view.x[i];
    const y = view.y[i];
    const kn = view.speedKn[i];
    if (!finite(x) || !finite(y) || !finite(kn)) continue;
    out.push({ t, x, y, kn });
  }
  return out;
}

/** The sample closest in time to `t`. */
export function nearestSample(samples, t) {
  if (!samples.length) return null;
  let best = samples[0];
  let bestDelta = Infinity;
  for (const s of samples) {
    const d = Math.abs(s.t - t);
    if (d < bestDelta) {
      bestDelta = d;
      best = s;
    }
  }
  return best;
}

/** Project a window into metres around `anchor`, in time order. See the header for why this
 *  is a translation and not a projection. */
function project(samples, anchor, zeroT, inEvent) {
  return samples.map((s) => ({
    x: s.x - anchor.x,
    y: s.y - anchor.y,
    rt: s.t - zeroT,
    kn: s.kn,
    headingDeg: null,
    inTurn: inEvent(s.t),
  }));
}

/* ------------------------------------------------------------------- the figure */

function figureFrom({ points, windDirDeg, entryKn, lowRt, endRt, outcome, axisRt,
                      timeDomain, durationS, title }) {
  const windUpPoints = finite(windDirDeg) ? rotate(points, windDirDeg) : null;
  return {
    points,
    windUpPoints,
    bounds: padBounds(boundsAround(points)),
    windUpBounds: windUpPoints ? padBounds(boundsAround(windUpPoints)) : null,
    windDirDeg: finite(windDirDeg) ? windDirDeg : null,
    entryKn, lowRt, endRt, outcome, axisRt, timeDomain, durationS, title,
  };
}

export const hasGeometry = (figure) => !!figure && figure.points.length >= 2;

export const figurePoints = (figure, windUp) =>
  (windUp && figure.windUpPoints ? figure.windUpPoints : figure.points);

export const figureBounds = (figure, windUp) =>
  (windUp && figure.windUpBounds ? figure.windUpBounds : figure.bounds);

/** The vertex nearest a relative time — what a strip's scrub drives the playhead through. */
export function pointAtRelative(figure, rt, windUp) {
  const all = figurePoints(figure, windUp);
  if (!all.length) return null;
  let best = all[0];
  let bestDelta = Infinity;
  for (const p of all) {
    const d = Math.abs(p.rt - rt);
    if (d < bestDelta) {
      bestDelta = d;
      best = p;
    }
  }
  return best;
}

/** The vertex nearest a point on the water — what a tap on the drawing picks. Nearest
 *  *vertex*, never a point interpolated along the line: the callout names one recorded
 *  sample and reads its speed and its heading. */
export function pointNear(figure, x, y, windUp, withinM = Infinity) {
  let best = null;
  let bestSq = withinM * withinM;
  for (const p of figurePoints(figure, windUp)) {
    const dx = p.x - x;
    const dy = p.y - y;
    const sq = dx * dx + dy * dy;
    if (sq <= bestSq) {
      bestSq = sq;
      best = p;
    }
  }
  return best;
}

/** The whole seconds a number is printed at along the path, and the vertex each belongs to.
 *  Every five seconds of the event's own clock, negative side included. Zero is skipped. */
export function pathLabels(figure, everyS, windUp) {
  if (!(everyS > 0) || !hasGeometry(figure)) return [];
  const all = figurePoints(figure, windUp);
  const first = all[0].rt;
  const last = all[all.length - 1].rt;
  if (!(last > first)) return [];
  const out = [];
  let rt = Math.ceil(first / everyS) * everyS;
  for (; rt <= last; rt += everyS) {
    if (Math.abs(rt) <= 0.001) continue;
    const at = pointAtRelative(figure, rt, windUp);
    if (!at || Math.abs(at.rt - rt) > everyS / 2) continue;
    out.push({ rt, at });
  }
  return out;
}

/* --------------------------------------------------------------------- one turn */

/** The rider's word for the turn. */
export function typeLabel(type) {
  switch (type) {
    case "jibe": return "Jibe";
    case "tack": return "Tack";
    case "bear_away": return "Bear-away";
    case "round_up": return "Round-up";
    default: return "Turn";
  }
}

/**
 * Cut `turn` out of the session's view.
 *
 * The window is `[ts − padBefore, endTs + padAfter]`: a jibe drawn from its first frame to
 * its last is an arc with no approach and no exit, and what the rider is asking is what the
 * speed did on either side of it.
 */
export function turnFigure(view, turn, windDirDeg, config,
                           padBeforeS = DEFAULT_PAD_S, padAfterS = DEFAULT_PAD_S) {
  const before = Math.max(padBeforeS, 0);
  const after = Math.max(padAfterS, 0);
  const window = windowSamples(view, turn.ts - before, turn.endTs + after);
  const durationS = Math.max(turn.endTs - turn.ts, 0);
  const speed = turnMarks(window, turn, config, durationS);
  const timeDomain = [-before, Math.max(durationS + after, -before + 1)];

  const anchor = nearestSample(window, turn.ts)
    ?? nearestSample(windowSamples(view, -Infinity, Infinity), turn.ts);
  let points = [];
  if (anchor) {
    points = project(window, anchor, turn.ts,
                     (t) => t >= turn.ts && t <= turn.endTs);
    applyHeadings(points);
  }

  const geometry = points.length >= 2;
  const figure = figureFrom({
    points,
    windDirDeg,
    entryKn: speed.entryKn,
    lowRt: geometry ? speed.minRt : null,
    endRt: geometry ? speed.exitRt : null,
    outcome: turn.outcome,
    axisRt: axisRt(turn, timeDomain),
    timeDomain,
    durationS,
    title: typeLabel(turn.type),
  });
  figure.speed = speed;
  figure.midRotationRt = midRotation(points);
  figure.kind = "turn";
  figure.padBeforeS = before;
  figure.padAfterS = after;
  return figure;
}

/** The wind-axis crossing, on the turn's own clock. Absent where the engine recorded none,
 *  and absent where a rounded record would put the tick outside the drawn frame. */
function axisRt(turn, timeDomain) {
  if (!finite(turn.axisTs)) return null;
  const rt = turn.axisTs - turn.ts;
  if (rt < timeDomain[0] || rt > timeDomain[1]) return null;
  return rt;
}

/**
 * Speed at the entry, at the low point and at the exit — **the engine's own three numbers**,
 * at the engine's own times, so they sit on the drawn line by construction and print the
 * same digits as the numbers row.
 */
function turnMarks(window, turn, config, durationS) {
  const minLagS = cfg(config, "minSpeedLag");
  const entryS = cfg(config, "entrySpeedWindow");
  const recoverPct = cfg(config, "turnRecoverPct");
  // The engine searches the minimum to `minSpeedLag` PAST the sweep, so the low point may
  // legitimately sit after "out".
  const minRt = Math.min(Math.max(turn.minTs - turn.ts, 0), durationS + minLagS);
  const entryWindow = window.filter((s) => s.t >= turn.ts - entryS && s.t <= turn.ts);
  const entryAt = minBy(entryWindow, (s) => Math.abs(s.kn - turn.entryKn));
  const threshold = (recoverPct / 100) * turn.entryKn;
  const recoverAt = window.find((s) => s.t > turn.endTs && s.kn >= threshold) ?? null;
  return {
    entryKn: turn.entryKn,
    entryRt: entryAt ? entryAt.t - turn.ts : 0,
    minKn: turn.minKn,
    minRt,
    exitKn: turn.exitKn,
    exitRt: durationS,
    recoverRt: recoverAt ? recoverAt.t - turn.ts : null,
  };
}

/** First minimum wins, which is Swift's `min(by:)`. */
function minBy(items, score) {
  let best = null;
  let bestScore = Infinity;
  for (const item of items) {
    const s = score(item);
    if (s < bestScore) {
      bestScore = s;
      best = item;
    }
  }
  return best;
}

/** Last maximum wins, which is Swift's `max(by:)`. */
function maxBy(items, score) {
  let best = null;
  let bestScore = -Infinity;
  for (const item of items) {
    const s = score(item);
    if (s >= bestScore) {
      bestScore = s;
      best = item;
    }
  }
  return best;
}

/** Where the turn is halfway round, by cumulative absolute heading change. The coach line
 *  asks "had he got round yet", and a sweep that overshoots and comes back has swept more
 *  than its net. */
export function midRotation(points) {
  const arc = points.filter((p) => p.inTurn && finite(p.headingDeg));
  if (arc.length < 3) return null;
  const steps = [];
  let total = 0;
  for (let i = 1; i < arc.length; i++) {
    total += Math.abs(deltaDeg(arc[i - 1].headingDeg, arc[i].headingDeg));
    steps.push({ rt: arc[i].rt, swept: total });
  }
  if (!(total > 0)) return null;
  const half = steps.find((s) => s.swept >= total / 2);
  return half ? half.rt : steps[steps.length - 1].rt;
}

/**
 * The session's best clean jibe of the same rotation — the dashed outline laid under the
 * drawn turn.
 *
 * Same session, because a comparison against an afternoon in different wind is not a
 * comparison. Same rotation, because a jibe spun to starboard and one spun to port are
 * mirror images. Clean, because the model has to be a turn that worked. Highest score among
 * those, because that is the one he carried most speed through. Ties go to the earlier turn.
 */
export function bestCleanTurn(turn, turns) {
  let best = null;
  for (const other of turns) {
    if (other.ts === turn.ts || !other.clean || other.direction !== turn.direction) continue;
    if (!best || other.score > best.score) best = other;
  }
  return best;
}

/* ---------------------------------------------------------------- one flight end */

/**
 * Cut a straight-line flight end out of the session's view.
 *
 * A flight end is an *instant*, not a sweep: there is no arc, no entry tack, no rotation, no
 * score and no wind-axis crossing. So `t = 0` is the end itself, `durationS` is zero and the
 * thick, speed-coloured part of the line is the run-in.
 */
export function flightEndFigure(view, end, windDirDeg, config,
                                padBeforeS = DEFAULT_PAD_S, padAfterS = DEFAULT_PAD_S) {
  const before = Math.max(padBeforeS, 0);
  const after = Math.max(padAfterS, 0);
  const window = windowSamples(view, end.ts - before, end.ts + after);
  const speed = endMarks(window, end, config);
  const timeDomain = [-before, Math.max(after, -before + 1)];

  const anchor = nearestSample(window, end.ts)
    ?? nearestSample(windowSamples(view, -Infinity, Infinity), end.ts);
  let points = [];
  if (anchor) {
    points = project(window, anchor, end.ts, (t) => t <= end.ts);
    applyHeadings(points);
  }

  const geometry = points.length >= 2;
  const figure = figureFrom({
    points,
    windDirDeg,
    entryKn: speed.entryKn,
    lowRt: geometry ? speed.lowRt : null,
    // The filled outcome dot goes on the end itself, which is the origin.
    endRt: geometry ? 0 : null,
    outcome: end.outcome,
    // A flight end crosses no wind axis. Absent, never zeroed.
    axisRt: null,
    timeDomain,
    durationS: 0,
    title: "Flight end",
  });
  figure.speed = speed;
  figure.midRotationRt = null;
  figure.kind = "end";
  figure.padBeforeS = before;
  figure.padAfterS = after;
  figure.windows = {
    entryS: cfg(config, "entrySpeedWindow"),
    outcomeS: cfg(config, "turnOutcomeLookahead"),
    evidenceS: end.windowS,
  };
  return figure;
}

/** The three marks. Only `lowKn` is the engine's, and the footnote says so. */
function endMarks(window, end, config) {
  const entryS = cfg(config, "entrySpeedWindow");
  const recoverPct = cfg(config, "turnRecoverPct");
  const foilEntryKmh = cfg(config, "foilEntrySpeed");
  const entryWindow = window.filter((s) => s.t >= end.ts - entryS && s.t <= end.ts);
  const entryAt = maxBy(entryWindow, (s) => s.kn);
  const entryKn = entryAt ? entryAt.kn : 0;
  const lowAt = finite(end.minKn)
    ? minBy(window.filter((s) => s.t >= end.ts), (s) => Math.abs(s.kn - end.minKn))
    : null;
  const threshold = Math.max((recoverPct / 100) * entryKn, foilEntryKmh * KMH_TO_KN);
  const recoverAt = window.find((s) => s.t > end.ts && s.kn >= threshold) ?? null;
  return {
    entryKn,
    entryRt: entryAt ? entryAt.t - end.ts : 0,
    lowKn: finite(end.minKn) ? end.minKn : null,
    lowRt: lowAt ? lowAt.t - end.ts : null,
    outKn: recoverAt ? recoverAt.kn : null,
    recoverRt: recoverAt ? recoverAt.t - end.ts : null,
  };
}

/* ------------------------------------------------------------------ the angles */

/**
 * The heading series, from a figure's **north-up** points: true wind angle where the wind is
 * known, compass heading where it is not.
 *
 * North up always, even when the drawing is rotated: the wind-up rotation subtracts the wind
 * from every heading, so on those points the heading already is the TWA.
 *
 * The unwrap moves consecutive angles by whole turns so each step is the shortest one, which
 * is what keeps a jibe running 350°, 010°, 030° from being drawn as a cliff and a climb.
 */
export function sliceAngles(points, windDirDeg) {
  const isTwa = finite(windDirDeg);
  const raw = [];
  for (const p of points) {
    if (!finite(p.headingDeg)) continue;
    raw.push({ rt: p.rt, deg: isTwa ? deltaDeg(windDirDeg, p.headingDeg) : p.headingDeg });
  }
  if (raw.length < 2) {
    return { points: raw.map((r) => ({ ...r, rateDegS: null })), isTwa, peakRateDegS: 0 };
  }
  const unwrapped = [raw[0].deg];
  for (let i = 1; i < raw.length; i++) {
    unwrapped.push(unwrapped[i - 1] + deltaDeg(raw[i - 1].deg, raw[i].deg));
  }
  const out = [];
  let peak = 0;
  for (let i = 0; i < raw.length; i++) {
    let rate = null;
    if (i + 1 < raw.length) {
      const dt = raw[i + 1].rt - raw[i].rt;
      if (dt > 0.001) {
        rate = (unwrapped[i + 1] - unwrapped[i]) / dt;
        if (Math.abs(rate) > Math.abs(peak)) peak = rate;
      }
    }
    out.push({ rt: raw[i].rt, deg: unwrapped[i], rateDegS: rate });
  }
  return { points: out, isTwa, peakRateDegS: peak };
}

/** The angle axis's own domain: the drawn values with a little air, never narrower than
 *  30°, so a rider who held a straight line does not get two degrees of noise magnified
 *  into a mountain range. */
export const MIN_ANGLE_SPAN_DEG = 30;

export function angleDomain(angles) {
  const values = angles.points.map((p) => p.deg);
  if (!values.length) return [-180, 180];
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const pad = Math.max((hi - lo) * 0.12, (MIN_ANGLE_SPAN_DEG - (hi - lo)) / 2, 2);
  return [lo - pad, hi + pad];
}

/* ------------------------------------------------------------------ foil state */

/**
 * Whether the foil was carrying, sample by sample, as spans on the event's own clock.
 *
 * The engine's flights are the answer and the only answer: a flight is where the rider was
 * flying, so everything between two of them is off the foil. Read from `view.flights`
 * rather than re-derived from a speed threshold, which would be the engine's decision taken
 * a second time by a drawing.
 */
export function foilSpans(view, zeroT, timeDomain) {
  const from = zeroT + timeDomain[0];
  const to = zeroT + timeDomain[1];
  const spans = [];
  for (const f of (view && view.flights) || []) {
    if (f.endTs < from || f.startTs > to) continue;
    spans.push({ startRt: Math.max(f.startTs, from) - zeroT,
                 endRt: Math.min(f.endTs, to) - zeroT,
                 flying: true });
  }
  spans.sort((a, b) => a.startRt - b.startRt);
  const out = [];
  let cursor = timeDomain[0];
  for (const span of spans) {
    if (span.startRt > cursor) {
      out.push({ startRt: cursor, endRt: span.startRt, flying: false });
    }
    out.push(span);
    cursor = Math.max(cursor, span.endRt);
  }
  if (cursor < timeDomain[1]) {
    out.push({ startRt: cursor, endRt: timeDomain[1], flying: false });
  }
  return out;
}
