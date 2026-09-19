/* The turn drawing's geometry, dumped as JSON for `verify_turn_figure.py`.
 *
 * The turn page draws one maneuver at its own scale, and everything about that picture that
 * could be *wrong* is arithmetic: the projection into local metres, the bearing written onto
 * each vertex, the wind-up rotation, the padded frame, the scale bar, and where the speed
 * ramp puts a knot reading. None of it is visible in a screenshot until a jibe is drawn
 * backwards, which is exactly why the kit keeps the same rules in `TurnSliceTests`.
 *
 * So the battery below runs the browser's own module — `web/js/maneuverfigure.js`, the file
 * the tab actually imports — over a synthetic session whose right answers can be written
 * down by hand, and the Python re-derives every one of them from the Swift. Two spellings of
 * one rule agreeing is evidence; one spelling agreeing with itself is not. Same spirit as
 * `outcome_text.mjs` and `card_parity.mjs`.
 *
 *     node web/tools/turn_figure.mjs
 *
 * The session is synthetic on purpose. An analysis golden carries the turn records but not
 * the positional view the browser draws from (`web_entry._view` builds that at analysis
 * time and it is never written to fixtures/), so a real turn cannot be re-cut here. What the
 * corpus would add is coverage of real sample spacing, and what it cannot add is a known
 * right answer for a projection — which is what this file is for.
 */

globalThis.window = { addEventListener() {} };

const mf = await import(new URL("../js/maneuverfigure.js", import.meta.url).href);

/* ------------------------------------------------------------ the synthetic ride */

/** A quarter-circle to starboard at 20 m radius, 1 Hz, inside a straight lead-in and
 *  run-out. The session frame is offset from the turn on purpose: the projection's whole job
 *  is to put the entry at the origin. */
const RADIUS_M = 20;
const ORIGIN = { x: 1000, y: -500 };
const SWEEP_FROM = 16;
const SWEEP_TO = 24;

/** The view rounds every channel on its way out of Python (`web_entry._round_list`): one
 *  decimal on the metres, two on the knots. Rounding here too is what makes this a test of
 *  the numbers the browser actually receives rather than of numbers it never sees. */
const round1 = (v) => Math.round(v * 10) / 10;

function ride() {
  const t = [];
  const x = [];
  const y = [];
  const speedKn = [];
  for (let i = 0; i <= 40; i++) {
    t.push(i);
    if (i < SWEEP_FROM) {
      // Running due north into the turn.
      x.push(round1(ORIGIN.x));
      y.push(round1(ORIGIN.y + (i - SWEEP_FROM) * 5));
    } else if (i <= SWEEP_TO) {
      // A quarter circle, centre to the east of the entry: heading swings north to east.
      const a = ((i - SWEEP_FROM) / (SWEEP_TO - SWEEP_FROM)) * (Math.PI / 2);
      x.push(round1(ORIGIN.x + RADIUS_M * (1 - Math.cos(a))));
      y.push(round1(ORIGIN.y + RADIUS_M * Math.sin(a)));
    } else {
      // Away due east.
      x.push(round1(ORIGIN.x + RADIUS_M + (i - SWEEP_TO) * 5));
      y.push(round1(ORIGIN.y + RADIUS_M));
    }
    // 12 kn either side, sagging to 7 kn through the sweep.
    const sag = i >= SWEEP_FROM && i <= SWEEP_TO
      ? 5 * Math.sin(((i - SWEEP_FROM) / (SWEEP_TO - SWEEP_FROM)) * Math.PI) : 0;
    speedKn.push(Math.round((12 - sag) * 100) / 100);
  }
  return { count: t.length, hasPositions: true, stride: 1, t, x, y, speedKn,
           dopplerKn: speedKn, segment: t.map(() => 0),
           flights: [{ startTs: 2, endTs: 20 }, { startTs: 26, endTs: 39 }] };
}

const TURN = {
  ts: SWEEP_FROM, endTs: SWEEP_TO, minTs: 20, type: "jibe", counted: true,
  entryKn: 12, minKn: 7, exitKn: 12, score: 0.5833, clean: false, cleanBlockedBy: null,
  side: "port", direction: "starboard", netDeg: 90, axisTs: 20,
  axisBeforeDeg: 45, axisAfterDeg: 45, radiusM: RADIUS_M, arcM: 31.4,
  outcome: "flew_through", outcomeReason: null, borderline: false,
  offFoilS: 0, stoppedS: 0, pumped: false, submerged: false, outcomeWindowS: 12,
};

const END = {
  flightIndex: 0, ts: 20, outcome: "fell_in", borderline: false, offFoilS: 9, stoppedS: 7,
  minKn: 1.5, pumped: false, submerged: false, windowS: 20, truncated: false,
  ownedByTurn: null,
};

const CONFIG = {
  entrySpeedWindow: 3, minSpeedLag: 2, turnOutcomeLookahead: 12, turnRecoverPct: 80,
  foilEntrySpeed: 12, turnCleanQuietS: 10,
};

const WIND_FROM_DEG = 300;

/* ------------------------------------------------------------------- the battery */

const round = (v, places = 6) =>
  (v === null || v === undefined || !Number.isFinite(v)
    ? null : Math.round(v * 10 ** places) / 10 ** places);

const roundBounds = (b) => (b ? {
  minX: round(b.minX), minY: round(b.minY), maxX: round(b.maxX), maxY: round(b.maxY),
} : null);

const view = ride();
const figure = mf.turnFigure(view, TURN, WIND_FROM_DEG, CONFIG);
const northUp = mf.figurePoints(figure, false);
const windUp = mf.figurePoints(figure, true);
const endFigure = mf.flightEndFigure(view, END, WIND_FROM_DEG, CONFIG);

const out = {
  turn: {
    count: northUp.length,
    firstRt: round(northUp[0].rt),
    lastRt: round(northUp[northUp.length - 1].rt),
    // The entry sits at the origin: that is what the projection is for.
    entryXY: (() => {
      const at = northUp.find((p) => p.rt === 0);
      return [round(at.x), round(at.y)];
    })(),
    inTurnCount: northUp.filter((p) => p.inTurn).length,
    headings: northUp.map((p) => round(p.headingDeg, 4)),
    windUpHeadings: windUp.map((p) => round(p.headingDeg, 4)),
    windUpXY: windUp.map((p) => [round(p.x, 4), round(p.y, 4)]),
    bounds: roundBounds(figure.bounds),
    windUpBounds: roundBounds(figure.windUpBounds),
    axisRt: round(figure.axisRt),
    timeDomain: figure.timeDomain.map((v) => round(v)),
    durationS: round(figure.durationS),
    title: figure.title,
    speed: {
      entryKn: round(figure.speed.entryKn),
      entryRt: round(figure.speed.entryRt),
      minKn: round(figure.speed.minKn),
      minRt: round(figure.speed.minRt),
      exitKn: round(figure.speed.exitKn),
      exitRt: round(figure.speed.exitRt),
      recoverRt: round(figure.speed.recoverRt),
    },
    midRotationRt: round(figure.midRotationRt),
    lowRt: round(figure.lowRt),
    endRt: round(figure.endRt),
    pathLabels: mf.pathLabels(figure, 5, false).map((l) => round(l.rt)),
    nearest: (() => {
      const p = mf.pointNear(figure, 0, 0, false, 3);
      return p ? round(p.rt) : null;
    })(),
    nearestMiss: mf.pointNear(figure, 500, 500, false, 3) === null,
  },
  end: {
    count: endFigure.points.length,
    endRt: round(endFigure.endRt),
    axisRt: endFigure.axisRt,
    durationS: round(endFigure.durationS),
    title: endFigure.title,
    inTurnCount: endFigure.points.filter((p) => p.inTurn).length,
    speed: {
      entryKn: round(endFigure.speed.entryKn),
      entryRt: round(endFigure.speed.entryRt),
      lowKn: round(endFigure.speed.lowKn),
      lowRt: round(endFigure.speed.lowRt),
      outKn: round(endFigure.speed.outKn),
      recoverRt: round(endFigure.speed.recoverRt),
    },
  },
  ramp: {
    positions: [0, 3, 6, 9, 12, 13, 15.6, 20]
      .map((kn) => round(mf.rampPosition(kn, 12))),
    lowEntry: round(mf.rampPosition(9, 0.2)),
    stops: [0, 0.125, 0.25, 0.5, 0.75, 1].map((p) => {
      const s = mf.rampStop(p);
      return [s.lower, s.upper, round(s.blend)];
    }),
    colors: [0, 0.25, 0.5, 0.75, 1].map((p) => mf.rampColor(p)),
    legendBottomKn: round(mf.legendBottomKn(12)),
    legendTopKn: [round(mf.legendTopKn(12, 11)), round(mf.legendTopKn(12, 14)),
                  round(mf.legendTopKn(12, 40))],
  },
  scaleBar: [10, 20, 30, 56, 60, 111, 200].map((span) => mf.scaleBarM(span)),
  angles: (() => {
    const a = mf.sliceAngles(northUp, WIND_FROM_DEG);
    return {
      isTwa: a.isTwa,
      first: round(a.points[0].deg, 4),
      last: round(a.points[a.points.length - 1].deg, 4),
      peakRateDegS: round(a.peakRateDegS, 4),
      domain: mf.angleDomain(a).map((v) => round(v, 4)),
      headingOnly: round(mf.sliceAngles(northUp, null).points[0].deg, 4),
    };
  })(),
  foil: mf.foilSpans(view, TURN.ts, figure.timeDomain)
    .map((s) => [round(s.startRt), round(s.endRt), s.flying]),
  helpers: {
    normalize: [-10, 0, 359.5, 360, 720.5].map((d) => round(mf.normalizeDeg(d), 4)),
    delta: [[350, 10], [10, 350], [0, 180], [0, 181], [90, 270]]
      .map(([a, b]) => round(mf.deltaDeg(a, b), 4)),
  },
};

process.stdout.write(JSON.stringify(out, null, 2));
