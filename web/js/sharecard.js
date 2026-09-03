/* The share card: the session as one picture a rider can post.
 *
 * The web half of `ios/WingFoil/Features/Share/ShareCardView.swift`, drawn on a canvas at
 * the *exact* iOS pixel sizes (1080×1350 / 1080×1080 / 1920×1080) so a card exported from
 * the phone and a card exported from the browser are the same artefact. Everything it says
 * comes pre-resolved from js/cardstats.js — this file is layout and nothing else, and it
 * computes no metric whatsoever.
 *
 * **Why a canvas and not an SVG or a DOM node screenshotted.** The output has to be a PNG
 * a share sheet will accept as a file, on a phone, offline. `canvas.toBlob` is the only
 * path that is one call, needs no library, and cannot be defeated by a stylesheet that did
 * not load — an `<svg>` serialized into an `Image` drops every external font and every CSS
 * variable, which on this card is all of them.
 *
 * **The layout, in iOS points.** Everything below is written at `1/SCALE` of the exported
 * pixels — the same 360-pt-wide card SwiftUI lays out — so one set of paddings works for
 * every aspect and the numbers here can be read against `ShareCardView` line for line.
 *
 * **The track is the card.** It takes whatever height the header, the stat grid and the
 * footer leave, and it fits the *ride* to that box rather than the square the projection
 * normalized into (`TrackOutlineView.fillsBox`): a session sailed up and down one reach
 * would otherwise draw as a thin line in the middle of a small square in the middle of a
 * wide gap.
 *
 * **The footer is an advertisement, and deliberately so.** A card travels through WhatsApp
 * groups to people who have never heard of the analyzer, so the bottom line says what the
 * site does, and the QR beside it lets someone looking at the picture on a friend's phone
 * get there without typing. Both strings live in `BRANDING` (js/cardstats.js), once.
 *
 * **The map is optional, and off.** With it on, `js/cardmap.js` composites OpenStreetMap
 * tiles behind everything, a scrim goes over them, the breadcrumb is re-placed through the
 * *map's* projection so it sits on the water rather than near it, and the required credit is
 * drawn. With it off — the default, and what a rider who never opens the switch gets — not
 * one line of that runs and the card is identical to the card this file has always drawn.
 * Anything that goes wrong in between (offline, a tile server that will not answer, a
 * tainted canvas) lands in the same place: the plain card, no message, no missing PNG.
 */

import { CREDIT, frameTrack, mapBackdrop, placeOn } from "./cardmap.js";
import {
  BRANDING, CAPTION_SEP, NOTE_LIMIT, PRESETS, SHAPES, TITLE_LIMIT, cardDateLine,
  cardDisclaimer, cardKey, cardStats, cardTitle, cardTitleDraft, cleanNote, cleanTitle,
  isWide, loadCardChoice, loadCardText, periodCardContent, periodMapAvailable,
  saveCardChoice, saveCardText,
} from "./cardstats.js";
import { getAnalysisJson } from "./store.js";
import { indexAt, phaseRuns } from "./session.js";
import { C, OUTCOME_COLOR } from "./viz.js";

const el = (id) => document.getElementById(id);

/** Exported pixels per layout point. The card is laid out at 360 pt wide and drawn at 3×,
 *  exactly as `ShareCardView.renderScale` does. */
const SCALE = 3;

/* ------------------------------------------------------------------ the palette
 *
 * The brand colours, from `ios/WingFoil/App/Brand.swift` — the card is a surface the app
 * paints itself, so there is no system background to adapt to and no semantic token that
 * applies. The three *presentation* inks it does use (the ladder, the splash cyan, the
 * phase tints) come from `C`, which is generated from design/tokens.json: a mark has to
 * mean the same thing on a card as on the map.
 */
const BRAND = {
  /** Deep navy — the middle of the card's gradient, and the app icon's own ground. */
  navy: "#0a1e30",
  green: "#2ee6a8",
  cyan: "#35c4f0",
  /** Near-white, warm enough not to glare against the navy. */
  paper: "#f4faff",
};

/** Top-leading to bottom-trailing, the three stops of `Brand.cardGradient`. */
const CARD_GRADIENT = ["#0c283e", BRAND.navy, "#061624"];

/** A brand colour at an alpha. Written as a helper rather than as rgba() literals so that
 *  every translucent ink on this card is visibly the colour it came from, and a change to
 *  the palette reaches all of them. */
const alpha = (hex, a) => {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
};

/**
 * Phase tints, with one deliberate departure from the map's.
 *
 * Flying is brand green rather than the map's teal, and this one is load-bearing: the
 * splash mark's token (`effort.splash`, #3fc4d8) and the flying phase's (#40c8e0) are the
 * same colour to the eye. On the map the two never touch — the splash sits on a glyph and
 * the phase on a line under a dozen other layers — but on a card with three semantics and
 * nothing else they would be one colour, and the whole point of drawing splashes here is
 * that a reader can find them.
 */
const FLYING = BRAND.green;
/** Off foil is `secondary` in the tokens — a *system* semantic with no defined value over
 *  a surface the app paints itself, so the card substitutes its own paper, subdued. */
const OFF_FOIL = alpha(BRAND.paper, 0.45);

/* --------------------------------------------------------------------- geometry */

const PAD_X = 16, PAD_TOP = 14, PAD_BOTTOM = 12, STACK_GAP = 8;
/** The wide shape's word column, as a fraction of the card: fixed rather than intrinsic,
 *  so the cells are the same size on a wide card as on a tall one and the track gets the
 *  whole remainder. */
const WIDE_COLUMN = 0.40;

/* ----------------------------------------------------------------------- fonts */

/** The site's own stack, read from the stylesheet rather than repeated here. */
function sansStack() {
  const v = getComputedStyle(document.documentElement).getPropertyValue("--sans").trim();
  return v || "-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif";
}

/**
 * Every weight the card draws in, asked for explicitly and waited on.
 *
 * A canvas does not reflow: if a weight is still loading when `fillText` runs, the glyphs
 * are measured and painted in whatever the fallback is, the metrics differ, and the PNG is
 * wrong *forever* — there is no second paint. `document.fonts.ready` alone is not enough,
 * because a font the page has not yet asked for is not pending and therefore "ready".
 */
const WEIGHTS = [400, 500, 600, 700];

async function ensureFonts(family) {
  try {
    await Promise.allSettled(
      WEIGHTS.map((w) => document.fonts.load(`${w} 40px ${family}`)));
    await document.fonts.ready;
  } catch { /* a browser without the Font Loading API draws in the system stack anyway */ }
}

/* ------------------------------------------------------------------ the artwork */

let markImage = null, qrImage = null;

/** The brand mark and the QR, loaded once and kept. Both are same-origin files under
 *  web/icons/, so the canvas stays untainted and `toBlob` keeps working. */
async function artwork() {
  const load = (src) => new Promise((resolve) => {
    const img = new Image();
    img.onload = () => resolve(img);
    // A missing asset must not stop a card from being made: the footer simply loses that
    // one element (`drawFooter` skips a null).
    img.onerror = () => resolve(null);
    img.src = src;
  });
  if (!markImage) markImage = await load(new URL("../icons/icon-192.png", import.meta.url).href);
  if (!qrImage) qrImage = await load(new URL("../icons/qr-cleanjibe.png", import.meta.url).href);
  return { mark: markImage, qr: qrImage };
}

/* ------------------------------------------------------------------- the track */

/**
 * The three semantics the outline carries, and no more (docs/presentation.md): the track
 * tinted by foil state, a dot per **counted manoeuvre** on the verdict ladder's inks, and
 * the barometer's submersion evidence as a cyan diamond. Course changes get no dot, by the
 * same rule the map draws by; nothing else of the map's eleven layers survives the shrink.
 *
 * Every coordinate is read out of the analysis document verbatim — `phaseRuns` and
 * `indexAt` are the map's own, imported rather than re-written.
 */
function buildTrack(result) {
  const v = result.view, g = result.golden;
  if (!v || !v.count || v.hasPositions === false || !v.bounds || v.bounds.x0 === null) {
    return null;
  }
  const runs = phaseRuns(v, v.flights);
  const marks = [];
  for (const m of v.turnMarkers) {
    if (!m.counted || !m.maneuver || m.x == null || m.y == null) continue;
    marks.push({ x: m.x, y: m.y, color: OUTCOME_COLOR[m.outcome] || C.ink3, splash: false });
  }
  const at = (t) => {
    const i = indexAt(v, t);
    return v.x[i] == null || v.y[i] == null ? null : { x: v.x[i], y: v.y[i] };
  };
  const splash = (t) => {
    const p = at(t);
    if (p) marks.push({ x: p.x, y: p.y, color: C.splash, splash: true });
  };
  for (const turn of g.turns) if (turn.submerged && turn.counted) splash(turn.ts);
  for (const end of g.flightEnds) {
    if (end.submerged && end.ownedByTurn === null && !end.truncated) splash(end.ts);
  }
  return runs.length || marks.length ? { runs, marks } : null;
}

/** The extent the drawn session actually occupies — the polyline **and** its marks, because
 *  a mark is placed from the nearest sample and can sit a hair outside the run it belongs
 *  to; a fit that ignored it would clip the dot against the edge of an exported image. */
function extent(track) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  const see = (x, y) => {
    if (x < x0) x0 = x; if (x > x1) x1 = x;
    if (y < y0) y0 = y; if (y > y1) y1 = y;
  };
  for (const run of track.runs) for (const p of run.pts) see(p[0], p[1]);
  for (const m of track.marks) see(m.x, m.y);
  return Number.isFinite(x0) ? { x0, y0, x1, y1 } : null;
}

/** Radius of an outcome dot, in layout points. 3.2 pt at the card's 3× export is a 19 px
 *  dot — the size a marker has to be to still read as a coloured verdict after a feed has
 *  resampled the picture. */
const MARK_R = 3.2;
/** The inset the track box reserves. It carries the mark radius as well as the stroke's: a
 *  dot on the outermost vertex is centred *on* the fitted edge and would otherwise lose its
 *  outer half. Named rather than inlined because the map framing has to reserve exactly the
 *  same margin, or a mapped track would come out a different size from a plain one. */
const TRACK_INSET = 4 + MARK_R;

/** The extent of a track's polyline alone, ignoring its marks — what the *stack* is fitted
 *  by, because the stack draws no marks. `extent` above is the session card's, which has to
 *  reserve room for a dot on the outermost vertex. */
function runsExtent(track) {
  return extent({ runs: track.runs, marks: [] });
}

/** An axis narrower than this has no extent worth fitting by, so it imposes no limit — a
 *  centimetre of drift is not a reach. The twin of `TrackStack.flatAxisM` in the kit. */
const FLAT_AXIS_M = 0.01;

/**
 * The metres → layout-points projection that puts `ext` in `box`, as numbers and a placer.
 *
 * `y` is metres north, so the vertical axis is flipped — north up, the same way the map
 * figure draws it. The scale is uniform: a track stretched to fill both axes is a
 * different-shaped session.
 *
 * The twin of `TrackStack.placement` in the kit, and the two are pinned against one fixture
 * (`fixtures/periods/outlines.expected.json`) so a card composed here and a card composed on
 * the phone place the same outlines in the same places.
 */
function placerFor(ext, box) {
  const inset = TRACK_INSET;
  const w = Math.max(box.w - inset * 2, 1), h = Math.max(box.h - inset * 2, 1);
  const dx = ext.x1 - ext.x0, dy = ext.y1 - ext.y0;
  // A perfectly straight leg has zero extent on one axis; that axis then imposes no limit,
  // which is exactly right — `min` takes the other one.
  const s = Math.min(dx > FLAT_AXIS_M ? w / dx : Infinity,
                     dy > FLAT_AXIS_M ? h / dy : Infinity);
  const scale = Number.isFinite(s) ? s : 1;
  const cx = (ext.x0 + ext.x1) / 2, cy = (ext.y0 + ext.y1) / 2;
  return {
    scale, centreX: cx, centreY: cy,
    place: (x, y) => ({ x: box.x + box.w / 2 + (x - cx) * scale,
                        y: box.y + box.h / 2 - (y - cy) * scale }),
  };
}

/**
 * Where a track coordinate lands, fitting the ride to `box` (layout points).
 *
 * This is the card's *own* projection, and it knows only about the session: the track is
 * placed against itself, which is all a card on a plain background has ever needed. With a
 * map behind the card it is replaced outright (`buildMap`) — see the file comment.
 */
function fittedPlacer(track, box) {
  const ext = extent(track);
  return ext ? placerFor(ext, box).place : null;
}

/**
 * **One placer for a whole stack**, fitted to the union of the tracks' metre extents.
 *
 * The period card's arithmetic, and the reason it is a named export: `web/tools/card_parity.mjs`
 * dumps what it does to a fixed set of outlines and `verify_presentation.py` §5e holds the kit's
 * `TrackStack.placement` to the same answer. A shared scale is the whole point — normalize each
 * outline against its own extent and a half-hour paddle is drawn exactly as large as a
 * three-hour reach, which is a picture of nothing.
 */
export function stackPlacer(tracks, box) {
  const extents = tracks.map(runsExtent).filter(Boolean);
  if (!extents.length) return null;
  const ext = extents.reduce((a, b) => ({
    x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0),
    x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1),
  }));
  return placerFor(ext, box);
}

/** How faint each outline is, so a dozen read as one shape. Twin of `TrackStack.opacity`. */
const stackOpacity = (count) => Math.max(0.22, Math.min(0.6, 2.4 / Math.max(1, count)));

/**
 * The **period card's** artwork: every session's outline, stacked.
 *
 * A period has no single ride to draw, and picking one would be picking a favourite. What it
 * has is a shape — a week at one spot is a dozen tracks over the same water, and laid on top
 * of one another they are recognisably that beach. So all of them go down, faint, and the
 * picture is the accumulation rather than any one afternoon.
 *
 * **One placer for all of them**, fitted to the union of their extents, so they are at one
 * scale and share a centre. Each session's `view.x`/`y` are metres in its own frame centred on
 * its own track, which is exactly what makes that meaningful: a short session draws small
 * inside a long one instead of being stretched to match it.
 *
 * No marks. Fifty outcome dots per session times a dozen sessions is confetti, and the card's
 * numbers already say how the maneuvers went.
 *
 * **With a map behind it** the shared fit is replaced by the map's own projection, one anchor
 * per session, exactly as the session card replaces its fit with `buildMap`'s. The ground is
 * only ever offered where every session in the period is in one spot cluster — see
 * `periodMapAvailable` and docs/presentation.md.
 */
function drawTrackStack(ctx, tracks, box, map = null) {
  const shared = map ? null : stackPlacer(tracks, box);
  if (!map && !shared) return;
  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  // Faint enough that twelve of them read as one shape rather than as a scribble, and the
  // overlap is what draws the eye: the water everything was ridden over comes out brightest.
  ctx.globalAlpha = stackOpacity(tracks.length);
  for (const track of tracks) {
    // With a map behind the card every track goes through the *map's* projection instead,
    // around its own anchor — the same substitution the session card makes, once per session,
    // because each outline's metres are in a frame of its own.
    const place = map ? map.placer(track) : shared.place;
    if (!place) continue;
    for (const run of track.runs) {
      if (run.pts.length < 2) continue;
      ctx.beginPath();
      const first = place(run.pts[0][0], run.pts[0][1]);
      ctx.moveTo(first.x, first.y);
      for (let i = 1; i < run.pts.length; i++) {
        const p = place(run.pts[i][0], run.pts[i][1]);
        ctx.lineTo(p.x, p.y);
      }
      ctx.strokeStyle = run.flying ? FLYING : OFF_FOIL;
      ctx.lineWidth = run.flying ? 1.8 : 1.8 * 0.5;
      ctx.stroke();
    }
  }
  ctx.restore();
}

/** Draw the outline through `place`, a metres → layout-points projection. */
function drawTrack(ctx, track, place) {
  const markR = MARK_R;

  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  for (const run of track.runs) {
    if (run.pts.length < 2) continue;
    ctx.beginPath();
    const first = place(run.pts[0][0], run.pts[0][1]);
    ctx.moveTo(first.x, first.y);
    for (let i = 1; i < run.pts.length; i++) {
      const p = place(run.pts[i][0], run.pts[i][1]);
      ctx.lineTo(p.x, p.y);
    }
    ctx.strokeStyle = run.flying ? FLYING : OFF_FOIL;
    ctx.lineWidth = run.flying ? 2.6 : 2.6 * 0.5;
    if (run.flying) {
      // The one glow on the card: the flying line is what the picture is about.
      ctx.shadowColor = alpha(FLYING, 0.45);
      ctx.shadowBlur = 5;
    }
    ctx.stroke();
    ctx.shadowBlur = 0;
  }

  // Splashes last, so the one mark that is *evidence* rather than a verdict sits on top of
  // the verdict it belongs to instead of hiding under it.
  const ordered = [...track.marks].sort((a, b) => (a.splash ? 1 : 0) - (b.splash ? 1 : 0));
  for (const m of ordered) {
    const { x, y } = place(m.x, m.y);
    ctx.beginPath();
    if (m.splash) {
      // Shape is a channel of its own: a splash usually sits on the fell-in verdict it
      // belongs to, and colour alone would separate them for nobody who cannot tell cyan
      // from green.
      const arm = markR * 1.3;
      ctx.moveTo(x, y - arm); ctx.lineTo(x + arm, y);
      ctx.lineTo(x, y + arm); ctx.lineTo(x - arm, y);
      ctx.closePath();
    } else {
      ctx.arc(x, y, markR, 0, Math.PI * 2);
    }
    // A dark halo first: a green dot on a green reach is invisible without one.
    ctx.strokeStyle = "rgba(0, 0, 0, 0.55)";
    ctx.lineWidth = markR * 0.75;
    ctx.stroke();
    ctx.fillStyle = m.color;
    ctx.fill();
  }
  ctx.restore();
}

/* ------------------------------------------------------------------- the map
 *
 * Everything below runs only when the rider turned the map on. See js/cardmap.js for the
 * tiles, the policy and the credit; what lives here is the one thing that is about the
 * *card* — getting the breadcrumb onto the same earth the tiles are pictures of.
 */

/** The engine's own metres-per-degree, from `wingfoil_lab.filters`. Repeated rather than
 *  imported because they arrive here as part of an already-computed document: these two
 *  numbers are what `view.geo` is an anchor *for*. */
const M_PER_DEG_LAT = 110540, M_PER_DEG_LON_EQ = 111320;

/** The engine's local metres back to degrees, around the view's anchor sample. The inverse
 *  of the forward projection the analysis did, to well under a metre — see `_geo_anchor` in
 *  web/lab_bundle/web_entry.py for why one row is enough. */
function toLatLon(geo, x, y) {
  const lat = geo.lat + (y - geo.y) / M_PER_DEG_LAT;
  const lon = geo.lon
    + (x - geo.x) / (Math.cos(geo.lat * Math.PI / 180) * M_PER_DEG_LON_EQ);
  return { lat, lon };
}

/**
 * The map under one card: a bitmap and the projection that agrees with it.
 *
 * The framing is asked for the *track box* — the rectangle the card would have fitted the
 * ride into anyway — so the ride comes out at the size and in the place it occupies on a
 * plain card, and the map simply extends outwards to the card's own edges. Nothing in the
 * layout moves, which is the point: a rider comparing the two switch positions is looking at
 * one card with and without ground under it, not at two cards.
 *
 * `null` for every failure, and the caller draws the plain card.
 */
async function buildMap(content, box, W, H, scale) {
  const { geo, track } = content;
  if (!geo || !track) return null;
  const ext = extent(track);
  if (!ext) return null;
  const frame = frameTrack({
    min: toLatLon(geo, ext.x0, ext.y0),
    max: toLatLon(geo, ext.x1, ext.y1),
    box, inset: TRACK_INSET,
  });
  if (!frame) return null;
  const image = await mapBackdrop(frame, W, H, scale);
  if (!image) return null;
  return {
    image,
    place: (x, y) => {
      const c = toLatLon(geo, x, y);
      return placeOn(frame, c.lat, c.lon);
    },
  };
}

/**
 * The map under a **period** card: one bitmap for a whole week, and a placer per session.
 *
 * The framing is the union bounding box of every outline in the stack, which is the honest
 * answer to "which rectangle of the earth?" — and the reason the switch is only offered when
 * there is one: a period whose afternoons are 15 km apart has a union box that is mostly the
 * road between them (see `periodMapAvailable` and docs/presentation.md). Once the sessions are
 * one cluster the box is the beach, and the same three-kilometre radius that made them a trip
 * is what bounds it.
 *
 * Everything else is the session card's contract unchanged: the ride fills exactly the box the
 * layout gave it, the card's own margins become map, the scrim and the credit follow, and every
 * failure is `null` — which the caller draws as the plain card.
 *
 * The placer is **per track**, because each session's metres are in a frame anchored on its own
 * `view.geo`; one shared frame would put a dozen beaches on top of each other.
 */
async function buildStackMap(tracks, box, W, H, scale) {
  const anchored = tracks.filter((t) => t.geo && runsExtent(t));
  if (!anchored.length) return null;
  let minLat = Infinity, minLon = Infinity, maxLat = -Infinity, maxLon = -Infinity;
  for (const track of anchored) {
    const ext = runsExtent(track);
    for (const [x, y] of [[ext.x0, ext.y0], [ext.x1, ext.y1]]) {
      const c = toLatLon(track.geo, x, y);
      minLat = Math.min(minLat, c.lat); maxLat = Math.max(maxLat, c.lat);
      minLon = Math.min(minLon, c.lon); maxLon = Math.max(maxLon, c.lon);
    }
  }
  if (!Number.isFinite(minLat)) return null;
  const frame = frameTrack({ min: { lat: minLat, lon: minLon },
                             max: { lat: maxLat, lon: maxLon },
                             box, inset: TRACK_INSET });
  if (!frame) return null;
  const image = await mapBackdrop(frame, W, H, scale);
  if (!image) return null;
  return {
    image,
    placer: (track) => (track.geo ? (x, y) => {
      const c = toLatLon(track.geo, x, y);
      return placeOn(frame, c.lat, c.lon);
    } : null),
  };
}

/**
 * What keeps the card readable over a photograph of a coastline.
 *
 * Two layers, and both earn their place. A flat navy wash first, so the map's own greens and
 * ochres are pulled towards the card's palette and the phase tints — brand green for flying,
 * paper for off foil — are again the only saturated thing on the picture. Then a vertical
 * gradient, heavier at the two ends where every word actually sits and lightest across the
 * middle, where the track is and where a rider wants to see the shore he sailed off.
 *
 * The wide shape gets a third pass: its words are a column on the right rather than two
 * bands, so the darkness has to run the other way for them.
 *
 * The opacities were set by eye against the worst case the standard OSM layer produces — a
 * town's white building fill under the footer — and not against open water, which needs
 * about half of this.
 */
function drawScrim(ctx, W, H, wide) {
  ctx.fillStyle = alpha(BRAND.navy, 0.34);
  ctx.fillRect(0, 0, W, H);

  const v = ctx.createLinearGradient(0, 0, 0, H);
  v.addColorStop(0, "rgba(0, 0, 0, 0.70)");
  v.addColorStop(0.30, "rgba(0, 0, 0, 0.34)");
  v.addColorStop(0.62, "rgba(0, 0, 0, 0.38)");
  v.addColorStop(1, "rgba(0, 0, 0, 0.80)");
  ctx.fillStyle = v;
  ctx.fillRect(0, 0, W, H);

  if (!wide) return;
  // The wide shape's words are a column, not two bands, so they need their own darkness
  // running the other way — and a *panel* rather than a ramp: a gradient that is still
  // brightening at the right-hand edge leaves the last stat cell and the QR sitting on
  // whatever the map put there. It ramps in over 70 points so the edge of the panel is not
  // a visible seam down the middle of the picture.
  const x0 = W * (1 - WIDE_COLUMN) - PAD_X;
  const h = ctx.createLinearGradient(x0 - 70, 0, x0, 0);
  h.addColorStop(0, "rgba(0, 0, 0, 0)");
  h.addColorStop(1, "rgba(0, 0, 0, 0.55)");
  ctx.fillStyle = h;
  ctx.fillRect(x0 - 70, 0, 70, H);
  ctx.fillStyle = "rgba(0, 0, 0, 0.55)";
  ctx.fillRect(x0, 0, W - x0, H);
}

/** What a stat cell is filled with. White at a tenth over the brand gradient — which is how
 *  the card has always drawn it, and how `ShareCardView` draws it — but the *opposite*
 *  direction over a map: a translucent white plate over a town's white building fill is not
 *  a plate at all, and the eight numbers are the half of the card a reader actually reads. */
const cellFill = (mapped) => (mapped ? "rgba(0, 0, 0, 0.34)" : "rgba(255, 255, 255, 0.10)");

/** How much of the header's width the credit takes on a tall card, in layout points, so the
 *  title can be told to stop short of it. Measured once at the credit's own size. */
function creditWidth(ctx, family) {
  ctx.font = `500 ${CREDIT_SIZE}px ${family}`;
  return ctx.measureText(CREDIT).width;
}

const CREDIT_SIZE = 6.5;

/**
 * The map credit — required by ODbL, and drawn where it costs the card nothing.
 *
 * **Top-right on the tall shapes.** The bottom-right corner is the QR's, and a decoder that
 * has to find three finder patterns in a photograph of a phone screen does not need six
 * points of grey type against its quiet zone; the bottom-left is the brand mark and the call
 * to action, which is the line the whole card exists to carry. That leaves the top corner
 * opposite the title, and the title is told to stop short of it (`drawHeader`) so the two
 * can never collide — a card is a PNG, and overlapping type on one is permanent.
 *
 * **Bottom-left on the wide shape**, where every word is in the right-hand column and the
 * corner under the track is empty. Its header has 40 % of the card to work in and cannot
 * afford to give a credit any of it.
 */
function drawCredit(ctx, inner, wide, family) {
  ctx.save();
  ctx.font = `500 ${CREDIT_SIZE}px ${family}`;
  ctx.fillStyle = alpha(BRAND.paper, 0.62);
  ctx.textBaseline = "alphabetic";
  if (wide) {
    ctx.textAlign = "left";
    ctx.fillText(CREDIT, inner.x, inner.y + inner.h);
  } else {
    ctx.textAlign = "right";
    ctx.fillText(CREDIT, inner.x + inner.w, inner.y + CREDIT_SIZE);
  }
  ctx.restore();
}

/* --------------------------------------------------------------- text helpers */

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/**
 * The largest size at or below `size` at which `text` fits `maxWidth`.
 *
 * A card is an image: an ellipsis on it is permanent, where three points of type size are
 * only small. So nothing here ever truncates — it shrinks, without a floor, because the
 * alternative to a slightly small streak pair is a lie with a "…" on the end of it.
 */
function fitSize(ctx, text, maxWidth, size, weight, family) {
  let s = size;
  for (let i = 0; i < 24; i++) {
    ctx.font = `${weight} ${s}px ${family}`;
    if (ctx.measureText(text).width <= maxWidth || s < 3) break;
    s *= 0.94;
  }
  return s;
}

function drawFitted(ctx, text, x, y, maxWidth, size, weight, family, color) {
  const s = fitSize(ctx, text, maxWidth, size, weight, family);
  ctx.font = `${weight} ${s}px ${family}`;
  ctx.fillStyle = color;
  ctx.fillText(text, x, y);
  return s;
}

/* ------------------------------------------------------------------ the pieces */

function drawBackground(ctx, w, h) {
  const g = ctx.createLinearGradient(0, 0, w, h);
  g.addColorStop(0, CARD_GRADIENT[0]);
  g.addColorStop(0.5, CARD_GRADIENT[1]);
  g.addColorStop(1, CARD_GRADIENT[2]);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  // A faint horizon glow, so the plain card is not a flat rectangle.
  const r = ctx.createRadialGradient(w / 2, h * 0.34, 0, w / 2, h * 0.34, w * 0.75);
  r.addColorStop(0, alpha(BRAND.cyan, 0.22));
  r.addColorStop(1, alpha(BRAND.cyan, 0));
  ctx.fillStyle = r;
  ctx.fillRect(0, 0, w, h);
}

/** The header with no caption on it: a 25-pt title on a 22-pt baseline, a 12-pt date on a
 *  38-pt one, and four points of air under it. Unchanged, and deliberately so — a card
 *  without a caption has to lay out exactly as it always did, down to the point. */
const HEADER_BASE_H = 42;
/** What the rider's own line costs when there is one. 10.5 pt of type plus its leading, on a
 *  baseline 12 pt below the date's — which is the whole price of the feature, paid by the
 *  track in the tall layouts and by the word column's slack in the wide one. */
const NOTE_LINE_H = 14;

/**
 * How tall the header is for *this* card. Exported because it is the only piece of the
 * card's geometry that now depends on the content, and therefore the only piece worth a
 * test: `web/tools/card_parity.mjs` dumps it with and without a caption, and
 * `verify_presentation.py` §5 asserts both numbers against a second copy of the rule.
 */
export const headerHeight = (content) => HEADER_BASE_H + (content?.note ? NOTE_LINE_H : 0);

/**
 * Name, date, and — when the rider wrote one — his own caption.
 *
 * The caption is the only thing on this card addressed by the sender to the reader, so it
 * sits directly under the two lines that say which afternoon this is, a shade brighter than
 * the date because it is the newer information.
 *
 * It is drawn with `drawFitted`, so it shrinks rather than truncating, by the rule the whole
 * card follows: an ellipsis in a PNG is permanent, three points of type size are only small.
 * At `NOTE_LIMIT` characters the shrink never gets far — the wide shape's 40 % column is the
 * tightest and a full-length caption lands there around 6.5 pt, which is 19 px in an exported
 * 1920-pixel image.
 */
function drawHeader(ctx, { title, dateLine, note }, box, family, titleInset = 0) {
  ctx.textBaseline = "alphabetic";
  // `titleInset` is the room the map credit needs in the top-right corner. It shrinks the
  // title rather than moving it, by the rule the whole card follows.
  drawFitted(ctx, title, box.x, box.y + 22, Math.max(box.w - titleInset, 40), 25, 700,
             family, BRAND.paper);
  ctx.font = `500 12px ${family}`;
  ctx.fillStyle = alpha(BRAND.paper, 0.72);
  ctx.fillText(dateLine, box.x, box.y + 38);
  if (note) {
    drawFitted(ctx, note, box.x, box.y + 50, box.w, 10.5, 500, family,
               alpha(BRAND.paper, 0.88));
  }
}

/** Four across once the block is more than a headline. The complete block is up to eight
 *  cells; at two columns that is four rows and a card with no room left for the ride it is
 *  about. The wide shape keeps two, because its word column is 40 % of the card. */
const columnCount = (stats, shape) => (isWide(shape) || stats.length <= 4 ? 2 : 4);
/** Smaller type and tighter cells for the full block — the same trade the block itself
 *  makes on a phone, where eight numbers do not get eight headlines. */
const isDense = (stats) => stats.length > 4;

function gridMetrics(stats, shape) {
  const dense = isDense(stats);
  return {
    cols: columnCount(stats, shape),
    gap: dense ? 5 : 8,
    padV: dense ? 4 : 8,
    padH: dense ? 6 : 10,
    radius: dense ? 9 : 12,
    labelSize: dense ? 7.5 : 9,
    valueSize: dense ? 16 : 21,
    captionSize: dense ? 7 : 8.5,
    // Uniform, so the grid is a grid: the caption line is reserved on every cell even
    // though only the tally has one. Sized to the tallest content (label + value +
    // caption + descender) and no more — every point spent here is a point the track,
    // which is what the picture is about, does not get.
    cellH: dense ? 45 : 56,
  };
}

function gridHeight(stats, shape) {
  const m = gridMetrics(stats, shape);
  const rows = Math.max(1, Math.ceil(stats.length / m.cols));
  return rows * m.cellH + (rows - 1) * m.gap;
}

function drawGrid(ctx, stats, box, shape, family, mapped = false) {
  const m = gridMetrics(stats, shape);
  const cellW = (box.w - m.gap * (m.cols - 1)) / m.cols;
  stats.forEach((stat, i) => {
    const cx = box.x + (i % m.cols) * (cellW + m.gap);
    const cy = box.y + Math.floor(i / m.cols) * (m.cellH + m.gap);
    ctx.fillStyle = cellFill(mapped);
    roundRect(ctx, cx, cy, cellW, m.cellH, m.radius);
    ctx.fill();

    const inner = cellW - m.padH * 2;
    // The tally's caption hangs off its label after an em-dash; splitting it here is
    // layout, not content — the two halves are the block's own words in the block's own
    // order (js/cardstats.js, CAPTION_SEP).
    const [label, caption] = stat.label.split(CAPTION_SEP);
    let y = cy + m.padV + m.labelSize;
    drawFitted(ctx, label, cx + m.padH, y, inner, m.labelSize, 600, family,
               alpha(BRAND.green, 0.85));
    y += m.valueSize + 2;
    drawValue(ctx, stat, cx + m.padH, y, inner, m.valueSize, family);
    if (caption) {
      // Fitted like the label above it rather than drawn raw: the tally's caption grew a
      // clean count ("of 50 jibes · 12 clean") and a card is a PNG — a caption that runs
      // out of its cell is permanent, where a point of type size is only small.
      y += m.captionSize + 4;
      drawFitted(ctx, caption, cx + m.padH, y, inner, m.captionSize, 400, family,
                 alpha(BRAND.paper, 0.6));
    }
  });
}

/** The tally cell is the one that is not a string: its three counts are drawn on the
 *  verdict ladder's own inks, the same way the key-metrics block draws them on the page.
 *  Every other cell is `stat.value` and nothing else. */
function drawValue(ctx, stat, x, y, maxWidth, size, family) {
  if (!stat.tally) {
    drawFitted(ctx, stat.value, x, y, maxWidth, size, 700, family, BRAND.paper);
    return;
  }
  const t = stat.tally;
  const parts = [
    [String(t.flewThrough), C.good], [" · ", alpha(BRAND.paper, 0.45)],
    [String(t.touchdown), C.warn], [" · ", alpha(BRAND.paper, 0.45)],
    [String(t.fellIn), C.bad],
  ];
  const s = fitSize(ctx, parts.map((p) => p[0]).join(""), maxWidth, size, 700, family);
  ctx.font = `700 ${s}px ${family}`;
  let cx = x;
  for (const [text, color] of parts) {
    ctx.fillStyle = color;
    ctx.fillText(text, cx, y);
    cx += ctx.measureText(text).width;
  }
}

/** Height of the footer block, and the QR's side.
 *
 * 33 pt is 99 exported px, which is 3 whole pixels per module of a 33-module symbol — the
 * only size in the 90–110 px band the contract asks for that upscales without a fraction.
 * Everything else in the footer lines up beside it. */
const QR_SIZE = 33;                                  // layout points → 99 exported px
const footerHeight = (disclaimer) => QR_SIZE + (disclaimer ? 8 : 0);

/** The asset's module count: a 25-module version-2 symbol plus the four modules of quiet
 *  zone the spec wants, baked into the PNG. One module is therefore exactly 1 layout point,
 *  which is what lets the mark below be measured in modules. */
const QR_MODULES = 33;
/** The side of the brand mark's white plate, **in modules** — the twin of
 *  `BrandQRImage.markModules` in the kit, and the number has to stay the same on both
 *  platforms or one of the two cards ships a code that does not scan.
 *
 *  Five, for three reasons. It is 25 of the symbol's 625 cells — **4 % of its area**, a
 *  quarter of what level M's parity can rebuild, leaving the rest for the recompression a
 *  chat app applies to a photograph of a phone screen. It stops a clear module short of the
 *  version-2 **alignment pattern** at module 16, which parity cannot substitute for: a
 *  decoder that cannot find that landmark never gets as far as error correction, which is
 *  why decoding fails abruptly at six modules rather than degrading. And it is odd — the
 *  symbol's centre is the middle of a module, so only an odd-width plate lands on module
 *  boundaries and costs whole cells instead of leaving a rim of half-covered ones. */
const QR_MARK_MODULES = 5;
/** The mark's own side inside the plate: three quarters of it, so a white rim about an
 *  eighth of the plate wide separates the artwork's dark edge from the dark modules it
 *  abuts. Without it the mark reads as a blot in the code rather than as a badge on it. */
const QR_MARK_INNER = 0.75;

/**
 * The brand mark on its white plate, in the middle of the code.
 *
 * **Why the plate is composited here and not baked into the PNG.** `icons/qr-cleanjibe.png`
 * is one pixel per module, so a mark drawn into it would be a five-pixel square — the
 * artwork would be gone, and every rounded corner would be a stair. Drawn at *this* size
 * instead, the plate and the icon are vector-and-bitmap at the card's own 3× scale and the
 * asset stays what it is: the code, and only the code, at its natural resolution.
 *
 * `mark` null (the icon failed to load) simply leaves the bare code, which still scans.
 */
function drawQrMark(ctx, mark, x, y, size) {
  if (!mark) return;
  const module = size / QR_MODULES;
  const plate = QR_MARK_MODULES * module;
  const px = x + (size - plate) / 2, py = y + (size - plate) / 2;
  ctx.save();
  ctx.fillStyle = "#fff";
  roundRect(ctx, px, py, plate, plate, plate * 0.22);
  ctx.fill();
  const inner = plate * QR_MARK_INNER;
  const ix = x + (size - inner) / 2, iy = y + (size - inner) / 2;
  // The icon's own corners are rounded, but it is a square PNG and the clip is what keeps a
  // hairline of its navy backing off the white plate at an export scale.
  roundRect(ctx, ix, iy, inner, inner, inner * 0.24);
  ctx.clip();
  // Smoothing back on — unlike the code, this is real artwork being reduced, and it is
  // inside the plate where softening an edge cannot soften a module.
  ctx.imageSmoothingEnabled = true;
  ctx.drawImage(mark, ix, iy, inner, inner);
  ctx.restore();
}

/**
 * The mark, the name, the offer and the QR — the whole point of a card someone else sees.
 *
 * Not a credit line. Someone reading this card has been sent a picture by a friend and has
 * never heard of the site; "CleanJibe · cleanjibe.org" tells them a name and an address but
 * not what happens if they go there. One line does that instead, and the QR means they do
 * not have to type it.
 */
function drawFooter(ctx, { disclaimer }, box, art, family) {
  const qr = art.qr ? QR_SIZE : 0;
  const markSize = 20;
  const x = box.x;
  const top = box.y + (box.h - QR_SIZE) / 2;

  if (art.qr) {
    // The asset is 33 × 33: **one pixel per module**, including the four-module quiet zone,
    // exactly as it came out of the generator. Drawn at 33 pt — 99 exported px — which is a
    // whole 3× **nearest-neighbour** upscale, so every module is three hard pixels wide.
    // Smoothing here would turn each module edge into a grey ramp for a decoder to guess at
    // after a chat app has recompressed the picture, which is the whole ballgame for a code
    // that has to survive a photo of a phone screen (docs/presentation.md).
    ctx.save();
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(art.qr, box.x + box.w - qr, top, qr, qr);
    ctx.restore();
    drawQrMark(ctx, art.mark, box.x + box.w - qr, top, qr);
  }

  let textX = x;
  if (art.mark) {
    const my = top + (QR_SIZE - markSize) / 2;
    ctx.save();
    roundRect(ctx, x, my, markSize, markSize, 4.5);
    ctx.clip();
    ctx.drawImage(art.mark, x, my, markSize, markSize);
    ctx.restore();
    // The mark's own background is the brand navy, which is the card's background too, so
    // without an edge it reads as a squiggle floating in the footer rather than as an icon.
    roundRect(ctx, x + 0.25, my + 0.25, markSize - 0.5, markSize - 0.5, 4.5);
    ctx.strokeStyle = alpha(BRAND.paper, 0.22);
    ctx.lineWidth = 0.5;
    ctx.stroke();
    textX = x + markSize + 7;
  }

  const textW = Math.max(box.x + box.w - qr - (qr ? 8 : 0) - textX, 40);
  const midY = top + QR_SIZE / 2;
  drawFitted(ctx, BRANDING.name, textX, midY - 3, textW, 13, 700, family, BRAND.paper);
  drawFitted(ctx, BRANDING.line, textX, midY + 10, textW, 9.5, 500, family,
             alpha(BRAND.paper, 0.86));
  if (disclaimer) {
    ctx.font = `400 7px ${family}`;
    ctx.fillStyle = alpha(C.effort, 0.9);
    ctx.fillText(disclaimer, textX, midY + 20);
  }
}

/* -------------------------------------------------------------------- the card */

/**
 * Draw one card into `canvas`, which is resized to the shape's exact pixels.
 *
 * Layout is in points throughout — the context is scaled by `SCALE` once, at the top — so
 * the paddings below can be read against `ShareCardView` directly.
 */
export async function drawCard(canvas, content, shape, options = {}) {
  const size = SHAPES[shape];
  const family = sansStack();
  await ensureFonts(family);
  const art = await artwork();

  canvas.width = size.w;
  canvas.height = size.h;
  const ctx = canvas.getContext("2d");
  ctx.setTransform(SCALE, 0, 0, SCALE, 0, 0);
  const W = size.w / SCALE, H = size.h / SCALE;
  const wide = isWide(shape);
  const boxes = cardBoxes(content, shape, W, H);

  // The one await between the layout and the ink. Off — the default — neither branch is
  // reached at all, and everything below draws the card this file has always drawn. A period
  // takes the stack's framing (the union of its outlines) and a session its own.
  let map = null;
  if (options.map && boxes.track) {
    map = content.tracks?.length
      ? await buildStackMap(content.tracks, boxes.track, W, H, SCALE)
      : await buildMap(content, boxes.track, W, H, SCALE);
  }

  if (map) {
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(map.image, 0, 0, size.w, size.h);
    ctx.restore();
    drawScrim(ctx, W, H, wide);
  } else {
    drawBackground(ctx, W, H);
  }
  ctx.textBaseline = "alphabetic";

  // The track goes down before the words on every shape, mapped or not: on the tall shapes
  // the two do not overlap, and on a mapped card the breadcrumb runs past its own box into
  // the map's margins, where the header and the footer must stay on top of it.
  if (content.track) {
    const place = map ? map.place : fittedPlacer(content.track, boxes.track);
    if (place) drawTrack(ctx, content.track, place);
  } else if (content.tracks?.length && boxes.track) {
    drawTrackStack(ctx, content.tracks, boxes.track, map);
  }

  const titleInset = map && !wide ? creditWidth(ctx, family) + 8 : 0;
  drawHeader(ctx, content, boxes.header, family, titleInset);
  drawGrid(ctx, content.stats, boxes.grid, shape, family, Boolean(map));
  drawFooter(ctx, content, boxes.footer, art, family);
  if (map) drawCredit(ctx, boxes.inner, wide, family);
  return canvas;
}

/**
 * Where the four pieces sit, in layout points.
 *
 * Pulled out of `drawCard` because the map framing needs the *track box* before anything is
 * drawn: the whole promise of the map background is that the ride lands where it would have
 * landed anyway, and that can only be kept by asking the layout first and painting second.
 */
function cardBoxes(content, shape, W, H) {
  const stats = content.stats;
  const footH = footerHeight(content.disclaimer);
  const gridH = gridHeight(stats, shape);
  const headH = headerHeight(content);
  const inner = { x: PAD_X, y: PAD_TOP, w: W - PAD_X * 2, h: H - PAD_TOP - PAD_BOTTOM };

  // A period card has no single ride and a stack of them instead, and either way the box is
  // the same box — the layout does not care which artwork lands in it.
  const hasArt = Boolean(content.track) || Boolean(content.tracks?.length);

  if (isWide(shape)) {
    // Track left, everything that is words right — at 1920×1080 a track stretched across
    // the full width leaves the stat block a 70-pt strip and the title reads as a caption
    // under a banner.
    const colW = W * WIDE_COLUMN;
    const trackW = inner.w - colW - STACK_GAP * 2;
    const cx = inner.x + trackW + STACK_GAP * 2;
    return {
      inner,
      track: hasArt ? { x: inner.x, y: inner.y, w: trackW, h: inner.h } : null,
      header: { x: cx, y: inner.y, w: colW },
      grid: { x: cx, y: inner.y + headH + STACK_GAP, w: colW },
      footer: { x: cx, y: inner.y + inner.h - footH, w: colW, h: footH },
    };
  }
  const trackY = inner.y + headH + STACK_GAP;
  const gridY = inner.y + inner.h - footH - STACK_GAP - gridH;
  return {
    inner,
    track: hasArt
      ? { x: inner.x, y: trackY, w: inner.w, h: gridY - STACK_GAP - trackY } : null,
    header: { x: inner.x, y: inner.y, w: inner.w },
    grid: { x: inner.x, y: gridY, w: inner.w },
    footer: { x: inner.x, y: inner.y + inner.h - footH, w: inner.w, h: footH },
  };
}

/**
 * Everything the card prints, resolved from one analysis document.
 *
 * `text` is the rider's own pair — a title that overrides the one derived from the filename,
 * and a caption that has no derived form at all. Both default to nothing, so every caller
 * that predates them (and every test) gets the card exactly as it was.
 */
export function cardContent(result, preset, text = {}) {
  return {
    title: cleanTitle(text.title) || cardTitle(result.file?.name),
    dateLine: cardDateLine(result.meta),
    note: cleanNote(text.note) || null,
    stats: cardStats(result.golden, preset),
    disclaimer: cardDisclaimer(result.meta),
    track: buildTrack(result),
    // The key back to the globe, for the optional map background and for nothing else. Null
    // on a document analysed before the anchor existed (one re-opened from the library) and
    // on any recording with no fixes — both of which simply cannot offer a map.
    geo: result.view?.geo || null,
  };
}

/* ------------------------------------------------------------------ the dialog */

const state = { result: null, key: "", shape: "portrait", preset: "complete", map: false,
                title: "", note: "", blob: null, seq: 0,
                // The second payload: a period, and the outlines of the sessions in it.
                // Null for the session card, which is every card this composer used to make.
                period: null, tracks: [] };

/** The offscreen canvas the PNG comes off. One per page: a 1920×1080 bitmap is 8 MB, and
 *  a phone that has just run an analysis does not need three of them. */
let full = null;

export function mountShareCard() {
  const dialog = el("card-dialog");
  if (!dialog) return;
  dialog.addEventListener("click", (ev) => {
    // The backdrop, and nothing inside the card.
    if (ev.target === dialog) dialog.close();
  });
  el("card-close").addEventListener("click", () => dialog.close());
  for (const b of dialog.querySelectorAll("[data-shape]")) {
    b.addEventListener("click", () => choose({ shape: b.dataset.shape }));
  }
  for (const b of dialog.querySelectorAll("[data-preset]")) {
    b.addEventListener("click", () => choose({ preset: b.dataset.preset }));
  }
  el("card-map").addEventListener("change", (ev) => choose({ map: ev.target.checked }));
  // `input`, not `change`: the preview is the point of the field, so it follows the typing.
  // The seq guard in `refresh` already throws away every draw but the newest, and the write
  // behind it is one `localStorage.setItem` of a small object.
  el("card-title-input").maxLength = TITLE_LIMIT;
  el("card-note-input").maxLength = NOTE_LIMIT;
  el("card-title-input").addEventListener("input", (ev) => {
    // A field that still reads exactly like the derived name is the prefill, not a title of
    // the rider's own, so it is remembered as nothing — the twin of what `commit()` does on
    // iOS. The card is headlined identically either way.
    const typed = ev.target.value;
    const derived = state.period ? state.period.title
                                 : cardTitle(state.result?.file?.name);
    choose({ title: typed === derived ? "" : typed });
  });
  el("card-note-input").addEventListener("input", (ev) => {
    choose({ note: ev.target.value });
    syncNoteCount();
  });
  el("card-download").addEventListener("click", download);
  el("card-share").addEventListener("click", share);
}

/** The remaining-characters line, shown only once the limit is in sight — a counter under an
 *  empty field announces a limit before anybody has approached it. */
function syncNoteCount() {
  const used = el("card-note-input").value.length;
  const out = el("card-note-count");
  out.hidden = used < NOTE_LIMIT - 20;
  out.textContent = `${used}/${NOTE_LIMIT}`;
}

/** Open the composer for the document currently on screen. */
export function openShareCard(result) {
  const dialog = el("card-dialog");
  if (!dialog || !result) return;
  state.result = result;
  state.period = null;
  state.tracks = [];
  state.key = cardKey(result);
  const saved = loadCardChoice();
  state.shape = saved.shape;
  state.preset = saved.preset;
  // Remembered, but only where it can be honoured: a document with no geographic anchor
  // (no fixes, or one analysed by a build that predates it) has no map to offer, and a
  // switch that is on and does nothing is worse than a switch that is not there.
  state.map = saved.map && mapAvailable(result);
  // The rider's own words for *this* session, if he wrote any here before.
  //
  // The title field opens **filled in** with what the card is currently headlined
  // (`cardTitleDraft`), because a rider titling a card is nearly always editing that headline
  // — adding "— first 20 kn" to the spot — and a blank field with the name greyed out behind
  // it made him retype the spot first. `state.title` stays whatever was remembered, so an
  // untouched field still means "no title of my own" and only a keystroke writes one; the
  // placeholder stays on for the one moment it is now visible, after a select-all and delete.
  const text = loadCardText(state.key);
  state.title = text.title;
  state.note = text.note;
  el("card-title-input").value = cardTitleDraft(state.title, result.file?.name);
  el("card-title-input").placeholder = cardTitle(result.file?.name);
  el("card-note-input").value = state.note;
  syncNoteCount();
  el("card-sub").textContent =
    `${cardTitle(result.file?.name)} · ${cardDateLine(result.meta)}`;
  // Only offered where it works: `canShare` with a file is the WhatsApp path on a phone,
  // and a "Share…" button that silently does nothing on a desktop browser is worse than no
  // button at all. Re-tested on every open, because a page can be opened on either.
  el("card-share").hidden = !canShareFiles();
  syncChoices();
  dialog.showModal();
  refresh();
}

/**
 * Open the same composer for a **period**.
 *
 * The dialog, the shapes, the presets, the title and caption fields and the export are the
 * session card's, unchanged: this is the same card describing a week instead of an afternoon.
 * Two things are different and both are stated rather than inferred — the artwork is every
 * session's outline stacked rather than one ride, and the map switch is offered only where a
 * period *has* a single ground (`periodMapAvailable`; docs/presentation.md).
 *
 * The outlines come from the stored analyses, read on demand: the Records tab holds digests,
 * which is all a number needs and not enough to draw with. A session whose document cannot be
 * read is simply not in the stack — a card with eleven of a rider's twelve afternoons on it is
 * a card, and a missing one is not worth refusing to make it.
 */
export async function openPeriodCard(period, entries) {
  const dialog = el("card-dialog");
  if (!dialog || !period) return;
  state.result = null;
  state.period = period;
  state.tracks = [];
  state.key = `period:${period.key}`;
  const saved = loadCardChoice();
  state.shape = saved.shape;
  state.preset = saved.preset;
  // Remembered, but only where it can be honoured — the same rule the session card follows,
  // asking a different question: a period has a ground when all of its afternoons were at one
  // place, and none at all when they were 15 km apart.
  state.map = saved.map && periodMapAvailable(period);
  const text = loadCardText(state.key);
  state.title = text.title;
  state.note = text.note;
  el("card-title-input").value = cleanTitle(state.title) || period.title;
  el("card-title-input").placeholder = period.title;
  el("card-note-input").value = state.note;
  syncNoteCount();
  el("card-sub").textContent = `${period.title} · ${period.dateLine}`;
  el("card-share").hidden = !canShareFiles();
  syncChoices();
  dialog.showModal();
  refresh();
  // After the first draw, not before it: the dialog opens on the stats immediately and the
  // outlines arrive when the documents do, which on a dozen sessions is a second or two.
  state.tracks = await loadTracks(period, entries);
  if (state.period === period) refresh();
}

/** The period's sessions as drawable outlines, oldest first, silently skipping any the
 *  library cannot hand back.
 *
 *  Each carries its own `geo` anchor, because a stack on a map is a dozen frames rather than
 *  one: the metres in `view.x`/`y` are relative to that session's own anchor sample, so the
 *  key back to the globe has to travel with the outline it belongs to. Null on a document
 *  analysed before the anchor existed, which simply keeps that session off the ground. */
async function loadTracks(period, entries) {
  const known = new Set((entries || []).map((e) => e.id));
  const out = [];
  for (const id of period.sessionIds || []) {
    if (!known.has(id)) continue;
    try {
      const json = await getAnalysisJson(id);
      if (!json) continue;
      const result = JSON.parse(json);
      const track = buildTrack(result);
      if (track) out.push({ ...track, geo: result.view?.geo || null });
    } catch { /* one unreadable document is not a reason to refuse the card */ }
  }
  return out;
}

/** Everything the card prints, for whichever payload the composer is holding. */
function content() {
  return state.period
    ? periodCardContent(state.period, state.preset,
                        { title: state.title, note: state.note }, state.tracks)
    : cardContent(state.result, state.preset, { title: state.title, note: state.note });
}

/** Whether the card on screen can carry a map at all. A session can when the document has a
 *  geographic anchor (`cardContent`'s `geo`); a period can when its afternoons share one spot
 *  cluster (`periodMapAvailable`). */
const mapAvailable = (result) => (state.period ? periodMapAvailable(state.period)
                                               : Boolean(result?.view?.geo));

function choose(next) {
  Object.assign(state, next);
  // Two stores, two scopes: the shape, the preset and the map are the rider's habit and
  // belong to the device, the title and caption belong to this one session (`cardKey`).
  saveCardChoice({ shape: state.shape, preset: state.preset, map: state.map });
  saveCardText(state.key, { title: state.title, note: state.note });
  syncChoices();
  refresh();
}

function syncChoices() {
  const dialog = el("card-dialog");
  for (const b of dialog.querySelectorAll("[data-shape]")) {
    b.setAttribute("aria-pressed", String(b.dataset.shape === state.shape));
  }
  for (const b of dialog.querySelectorAll("[data-preset]")) {
    b.setAttribute("aria-pressed", String(b.dataset.preset === state.preset));
  }
  el("card-preset-note").textContent = PRESETS[state.preset].summary;
  const offered = mapAvailable(state.result);
  const box = el("card-map");
  box.checked = state.map;
  box.disabled = !offered;
  el("card-map-row").hidden = !offered;
}

/**
 * Redraw the card and the preview.
 *
 * `seq` guards against a rider tapping three shapes faster than the fonts resolve: only the
 * newest draw is allowed to reach the screen, so the preview can never end up showing the
 * shape before last.
 */
async function refresh() {
  if (!state.result && !state.period) return;
  const seq = ++state.seq;
  const preview = el("card-canvas");
  if (!full) full = document.createElement("canvas");
  const size = SHAPES[state.shape];
  await drawCard(full, content(), state.shape, { map: state.map });
  if (seq !== state.seq) return;

  // The preview IS the PNG, scaled — not a second rendering of it, so what the rider
  // approves is exactly what they send. The backing store is sized in device pixels so a
  // retina phone previews a sharp card rather than a blurred one.
  // 280 is what a 390 px phone leaves once the dialog, the form padding and the preview
  // frame have taken theirs; 340 is what the shortest laptop window leaves above the
  // pickers. The landscape shape is the one that hits the width bound.
  const maxW = 280, maxH = 340;
  const k = Math.min(maxW / size.w, maxH / size.h);
  const cssW = Math.round(size.w * k), cssH = Math.round(size.h * k);
  const dpr = Math.min(window.devicePixelRatio || 1, 3);
  preview.style.width = `${cssW}px`;
  preview.style.height = `${cssH}px`;
  preview.width = Math.round(cssW * dpr);
  preview.height = Math.round(cssH * dpr);
  const pctx = preview.getContext("2d");
  pctx.clearRect(0, 0, preview.width, preview.height);
  pctx.drawImage(full, 0, 0, preview.width, preview.height);

  state.blob = null;
  el("card-size").textContent = `${size.w} × ${size.h}`;
}

/** The download's name, from whatever the card is actually titled — the rider's own words if
 *  he gave any, reduced to a slug that is safe in a Downloads folder on every platform (the
 *  twin of `FitShareFilter.filename` on iOS). A title of nothing but emoji slugs to nothing,
 *  which is why the stem falls back rather than producing a file called `-portrait.png`. */
const fileName = () => {
  const title = cleanTitle(state.title)
    || (state.period ? state.period.title : cardTitle(state.result?.file?.name));
  const slug = title.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40).replace(/-+$/, "");
  return `${slug || "session"}-${state.shape}.png`;
};

async function toBlob() {
  if (state.blob) return state.blob;
  state.blob = await new Promise((resolve) => full.toBlob(resolve, "image/png"));
  return state.blob;
}

async function download() {
  const blob = await toBlob();
  if (!blob) return;
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = fileName();
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  // A card exists now — the PNG is rendered and the save is handed to the browser. The
  // event is the bare name: `fileName()` two lines up is built out of the rider's own
  // title, and that is exactly the kind of thing a counter must never be told. Guarded
  // because the umami script is third-party and frequently absent (blocked, offline, or
  // any host that is not cleanjibe.org).
  window.umami?.track?.("card-created");
}

/** Feature-detected with a *file*, not with `navigator.share`: several browsers can share a
 *  URL and refuse a file, and the file is the whole point here. */
function canShareFiles() {
  try {
    if (!navigator.canShare) return false;
    const probe = new File([new Blob([""], { type: "image/png" })], "card.png",
                           { type: "image/png" });
    return navigator.canShare({ files: [probe] });
  } catch { return false; }
}

async function share() {
  const blob = await toBlob();
  if (!blob) return;
  const file = new File([blob], fileName(), { type: "image/png" });
  try {
    await navigator.share({ files: [file] });
    // Inside the `try`, after the sheet resolves: a dismissal rejects and lands in the
    // catch, and a card the rider backed out of sharing is not a card that went anywhere.
    window.umami?.track?.("card-created");
  } catch { /* the rider dismissed the sheet — not an error, and not worth a message */ }
}
