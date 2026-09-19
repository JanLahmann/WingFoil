/* The ground under the Ride tab's track: OpenStreetMap raster tiles, and the door that
 * opens the same map full screen.
 *
 * The web twin of the iPhone's `TrackMapView` sitting on MapKit and of the `Open map full
 * screen` link under it (ios/WingFoil/Features/SessionDetail). The phone has had a map
 * behind its track since the first build, because a rider reading a session at a new spot is
 * asking about the *shore* — where he launched, the pier he jibed around, the shallows he
 * stayed off — and a breadcrumb on a flat panel answers none of it.
 *
 * Nothing here draws a track, a marker or a number. `js/session.js` owns the figure; this
 * module answers two questions for it — *where does the earth sit under these metres* and
 * *how tall is the box* — and paints tiles into the SVG it is handed.
 *
 * **It is off by default and it stays off unless asked.** No tile is requested until the
 * rider presses Map, exactly as on the share card (js/cardmap.js) and for the same reason:
 * the analyzer's loudest promise is that a session never leaves the tab, and a background
 * that quietly fetched a dozen third-party pictures of the rider's home beach would be that
 * promise read from the other side. The choice is remembered per device.
 *
 * **The tiles are js/cardmap.js's**, grid, zoom ladder, `MAX_TILES` ceiling and all, so the
 * card and the page draw one picture of one beach. What differs is the delivery: the card
 * composites onto a canvas because it exports a PNG, and a page that pans has no reason to,
 * so here each tile is an `<image>` in the SVG. A failed tile is a hole the dark surface
 * shows through, a wholly failed fetch is the plain figure, and there is no retry of any
 * kind. Offline, the toggle stays where the rider left it and the map simply does not
 * arrive. See https://operations.osmfoundation.org/policies/tiles/.
 *
 * **The projection is the map's.** `js/session.js` fits the ride through the engine's local
 * metres, which is a projection about the *session* and has no idea where the water is. With
 * tiles behind it the breadcrumb has to sit on the earth the tiles are pictures of, so the
 * fit is re-derived through Web Mercator here — the same `frameTrack`/`placeOn` pair the
 * card uses — and framed so the ride lands in the box it would have occupied anyway.
 */

import { CREDIT, tileCover, worldPoint } from "./cardmap.js";
import { track as count } from "./track.js";
import { C, svg } from "./viz.js";

/* ------------------------------------------------------------------- the switch */

/** The rider's ground, per device, alongside the share card's own three choices
 *  (`wingfoil.shareCard.*` in js/cardstats.js). Same shape, same rule below. */
const LS_GROUND = "wingfoil.trackMap.ground.v1";

/** **On only when the stored value is exactly `"1"`.** An absent key, a key somebody else
 *  wrote and a storage that throws are all the plain figure — the figure this page has
 *  always drawn, and the one it keeps drawing for anybody who never asks for anything. */
export function groundOn() {
  try {
    return localStorage.getItem(LS_GROUND) === "1";
  } catch {
    return false;                                    // private window, or file://
  }
}

function setGround(on) {
  try {
    localStorage.setItem(LS_GROUND, on ? "1" : "0");
  } catch { /* nothing to do about it, and nothing worth telling the rider */ }
}

/* --------------------------------------------------------------- the projection */

/** The engine's own metres-per-degree, from `wingfoil_lab.filters` — the two numbers
 *  `view.geo` is an anchor *for*. Repeated rather than imported for the same reason
 *  js/sharecard.js repeats them: they arrive as part of an already-computed document. */
const M_PER_DEG_LAT = 110540, M_PER_DEG_LON_EQ = 111320;

/** The engine's local metres back to degrees, around the view's anchor sample. */
function toLatLon(geo, x, y) {
  const lat = geo.lat + (y - geo.y) / M_PER_DEG_LAT;
  const lon = geo.lon
    + (x - geo.x) / (Math.cos(geo.lat * Math.PI / 180) * M_PER_DEG_LON_EQ);
  return { lat, lon };
}

/** How much of the figure one tile-less spot is given when a rider never moved: 600 m
 *  across the box, which is a launch beach and its shoreline. The card's own fallback. */
const STILL_SPAN_M = 600;

/**
 * **Where the earth sits under this figure**, or null for "draw the plain one".
 *
 * Null covers every way the ground can be absent and the caller's answer to all of them is
 * the same: the figure it drew before any of this existed. The switch is off; the document
 * was analysed before `view.geo` and has no key back to the globe; the track has no extent
 * at all; the latitude is past Mercator's usable edge.
 *
 * The return is a *linear* projection — `X(x) = ox + x·sx`, `Y(y) = oy − y·sy` — rather than
 * a call into `placeOn` per point, and that is a decision about panning rather than about
 * accuracy. A drag redraws the figure many times a second over a track of thousands of
 * fixes, and a logarithm per fix per frame is the difference between a map that follows a
 * finger and one that lags behind it.
 *
 * It is allowed to be linear because Mercator *is* linear at this scale. The engine's local
 * metres already divide longitude by cos(latitude), so the two projections differ only in
 * Mercator's own curvature, which over a session's few kilometres is centimetres, and in the
 * engine's two metres-per-degree constants, which differ by 0.7 % — carried here as the two
 * separate factors `sx` and `sy`, because the tiles are the truth about the coastline and
 * the track is what has to agree with them.
 *
 * `frame` is the same {scale, originX, originY} the card's `frameTrack` returns, and is what
 * `paintGround` asks for tiles with. It agrees with `sx`/`sy` exactly at the track's centre.
 */
export function groundUnder(v, { b, W, H, PAD }) {
  if (!groundOn()) return null;
  const geo = v && v.geo;
  if (!geo || !Number.isFinite(geo.lat) || !Number.isFinite(geo.lon)) return null;

  const cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2;
  const centre = toLatLon(geo, cx, cy);
  const cos = Math.cos(centre.lat * Math.PI / 180);
  if (!(cos > 1e-6) || Math.abs(centre.lat) > 85) return null;

  // World units per metre at this latitude, one factor per axis. Mercator's x is longitude
  // over 360; its y is atanh(sin lat) over 2π, whose derivative is 1/cos lat.
  const wpmX = 1 / (360 * cos * M_PER_DEG_LON_EQ);
  const wpmY = 1 / (360 * cos * M_PER_DEG_LAT);

  const innerW = Math.max(W - 2 * PAD, 1), innerH = Math.max(H - 2 * PAD, 1);
  const dx = (b.x1 - b.x0) * wpmX, dy = (b.y1 - b.y0) * wpmY;
  // A perfectly straight leg has zero extent on one axis; that axis then imposes no limit,
  // which is right — `min` takes the other one.
  let scale = Math.min(dx > 1e-12 ? innerW / dx : Infinity,
                       dy > 1e-12 ? innerH / dy : Infinity);
  if (!Number.isFinite(scale)) scale = innerW / (STILL_SPAN_M * wpmX);
  if (!(scale > 0) || !Number.isFinite(scale)) return null;

  const pc = worldPoint(centre.lat, centre.lon);
  const screenCx = PAD + innerW / 2, screenCy = PAD + innerH / 2;
  const sx = scale * wpmX, sy = scale * wpmY;
  return {
    sx, sy,
    ox: screenCx - cx * sx,
    oy: screenCy + cy * sy,
    frame: { scale, originX: pc.x - screenCx / scale, originY: pc.y - screenCy / scale },
  };
}

/* -------------------------------------------------------------------- the tiles */

/**
 * How much of the map survives onto the figure.
 *
 * The standard OSM layer is pale, and every ink on this track — foil teal, the outcome
 * ladder, splash cyan, the effort orange, the off-foil grey — was chosen against the dark
 * surface under it and is a contract that may not move because of what is behind it
 * (docs/presentation.md, "Colour and glyph vocabulary"). So the ground is drawn *into* the
 * surface rather than over it: at this opacity a town reads as a town and a coastline as a
 * coastline, and the darkest thing on the picture is still the water.
 *
 * It is the same trade the card makes with its navy wash and its vertical gradient, and it
 * lands in about the same place — roughly four tenths of the map's own luminance where the
 * track is. The card needs two layers because it also carries words; a figure carries none.
 */
const GROUND_OPACITY = 0.5;

/** Raster pixels wanted per CSS pixel. Two on a retina phone, one on an ordinary monitor,
 *  and never more than the card's own `MAP_SCALE` — past that the ceiling simply steps the
 *  zoom down and the rider pays for a softer map with nothing to show for it. */
const pixelRatio = () => Math.min(Math.max(window.devicePixelRatio || 1, 1), 2);

/**
 * Paint the ground into `root`, under everything the caller draws next.
 *
 * The camera is folded into the frame rather than applied to the tiles: zooming in raises
 * the effective scale, which asks `tileCover` for a finer zoom level, which is why a
 * zoomed-in map sharpens instead of stretching. The `MAX_TILES` ceiling is the same one the
 * card lives under, so a full-screen map at 4× is a slightly softer map and never thirty
 * more requests.
 *
 * The tiles are re-emitted on every redraw, a drag's included, because `drawMap` empties the
 * figure and builds it again — which it already did for every polyline and every marker, and
 * fifteen `<image>` elements are the small half of that. No request follows: the URLs are the
 * same ones, and the browser's own image cache and the service worker's RUNTIME cache are
 * both in front of them (web/sw.js).
 */
export function paintGround(root, ground, W, H, cam) {
  const scale = ground.frame.scale * cam.k;
  const seen = {
    scale,
    originX: ground.frame.originX - cam.tx / scale,
    originY: ground.frame.originY - cam.ty / scale,
  };
  const cover = tileCover(seen, W, H, pixelRatio());
  if (!cover || !cover.tiles.length) return;

  const g = svg("g", { "data-ground": "osm", opacity: GROUND_OPACITY,
                       "pointer-events": "none" }, root);
  for (const t of cover.tiles) {
    // A hair of overlap, for the same reason the card takes one: adjacent tiles at
    // fractional positions leave a seam of surface between them, and a grid of hairlines
    // over the water is the one artefact a reader would notice.
    const image = svg("image", {
      x: t.left.toFixed(2), y: t.top.toFixed(2),
      width: (t.side + 0.5).toFixed(2), height: (t.side + 0.5).toFixed(2),
      preserveAspectRatio: "none", decoding: "async",
      // The request has to be a CORS one or the service worker gets an opaque response back
      // and refuses to keep it (web/sw.js), which would cost a fetch per pan. The layer
      // sends `Access-Control-Allow-Origin: *`.
      crossorigin: "anonymous",
    }, g);
    image.setAttribute("href", t.url);
  }
  drawCredit(root, W, H);
}

/** ODbL's credit, in the corner MapKit puts its own in. Drawn whenever tiles are asked for,
 *  so it travels with a screenshot and with the full-screen view. */
function drawCredit(root, W, H) {
  const t = svg("text", {
    x: (W - 8).toFixed(1), y: (H - 6).toFixed(1), "text-anchor": "end",
    "font-size": 9.5, fill: C.ink3, stroke: C.surface, "stroke-width": 2.4,
    "paint-order": "stroke", "stroke-linejoin": "round", "pointer-events": "none",
  }, root);
  t.textContent = CREDIT;
  return t;
}

/* ------------------------------------------------------------------- the toggle */

/**
 * **Map / Plain**, in the legend's utilities group, where the iOS legend keeps its own
 * ground control (`MapStyleChip` in MapLegendView).
 *
 * One style, because there is only one: the standard OSM layer has no satellite twin, and a
 * picker offering four grounds that are all the same ground would be a control that lies.
 * The phone's four names are Apple's and a rider recognises them; the web's two are the two
 * states it actually has.
 *
 * The credit rides beside it while the map is on, so the legend names OpenStreetMap the way
 * the phone's map names Apple Maps in its corner.
 */
export function groundToggle() {
  const on = groundOn();
  const button = (mode, text, live) =>
    `<button type="button" class="ghost small-btn ground-btn${live ? " on" : ""}" ` +
    `data-ground="${mode}" aria-pressed="${live}">${text}</button>`;
  return `<span class="item ground-toggle" role="group" ` +
         `aria-label="Ground under the track">` +
         button("map", "Map", on) + button("plain", "Plain", !on) +
         `</span>` +
         (on ? `<span class="item muted-item ground-credit">${CREDIT}</span>` : "");
}

/** Handle a press on either half. Returns true when it was one. */
export function onGroundButton(ev, redraw) {
  const button = ev.target.closest("[data-ground]");
  if (!button) return false;
  const wanted = button.dataset.ground === "map";
  if (wanted !== groundOn()) {
    setGround(wanted);
    // The one control on this page that starts a request to somebody else's server, so it
    // is the one worth counting: the map background is off until a rider turns it on, and
    // /privacy/ says so. The event is the word "map" or "plain" and no coordinate.
    count("app-map-ground-set", { ground: wanted ? "map" : "plain" });
    redraw();
  }
  return true;
}

/* --------------------------------------------------------------- the full screen
 *
 * "Open map full screen" is the phone's door, in the phone's words, and behind it is **the
 * same map**: the figure and its legend are moved into a full-viewport shell and drawn
 * again at the viewport's own size. Not a second map — a second map would be a second
 * camera, a second playhead and a second set of chips to keep in step with the first, which
 * is the bug the one-playhead rule exists to prevent (docs/presentation.md, "Scrub and
 * zoom").
 *
 * So every gesture the inline map has is already here, unchanged: wheel and pinch zoom about
 * the pointer, a drag pans once there is somewhere to pan to, the zoom buttons and the layer
 * chips do what they do on the page. Escape and Back put it away.
 *
 * **Rotate is not offered.** The phone's full-screen map can be turned because MapKit turns;
 * this figure is north-up by construction, the wind arrow and the chevrons are read against
 * that, and a rotated track answers no question the fitted one does not.
 */

/** Open, this holds what has to be put back. Null when the map is on the page. */
let full = null;
let wired = false;
let redrawAll = () => {};

export const fullMapOpen = () => !!full;

/** The height the figure should take while it is full screen, or 0 on the page. The shell is
 *  a column — bar, map, legend — so this is whatever the flex row was left. */
export function fullMapHeight() {
  const body = document.getElementById("map-full-body");
  if (!full || !body) return 0;
  return Math.max(Math.round(body.clientHeight), 240);
}

/** Whether this document has a track to open full screen. A Doppler-only recording has no
 *  map, so it has no door either. */
export function fullMapDoor(available) {
  const door = document.getElementById("map-full-open");
  if (door) door.hidden = !available;
  // `redraw: false` because the only caller is *inside* a draw: a session with no track
  // replacing one that had it would otherwise redraw the figure from within its own draw.
  if (!available && full) closeFullMap({ redraw: false });
}

/** Wire the two buttons once. `redraw` is what redraws both figures and the legend. */
export function wireFullMap(redraw) {
  redrawAll = redraw;
  if (wired) return;
  wired = true;
  const open = document.getElementById("map-full-open");
  const close = document.getElementById("map-full-close");
  // Wrapped rather than passed: both take options, and a click handler would hand them
  // a MouseEvent as one.
  if (open) open.addEventListener("click", () => openFullMap());
  if (close) close.addEventListener("click", () => closeFullMap());
}

function onKey(ev) {
  if (ev.key === "Escape") {
    ev.preventDefault();
    closeFullMap();
  }
}

let resizeTimer = 0;
function onResize() {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => { if (full) redrawAll(); }, 120);
}

export function openFullMap() {
  if (full) return;
  const figure = document.getElementById("map-figure");
  const legend = document.getElementById("map-legend");
  const shell = document.getElementById("map-full");
  const body = document.getElementById("map-full-body");
  const slot = document.getElementById("map-full-legend");
  if (!figure || !legend || !shell || !body || !slot) return;

  full = { figure, legend, parent: figure.parentNode, after: legend.nextSibling };
  // The phone's door, in the browser. Whether it is ever pushed decides whether the
  // full-screen shell earns the code it costs.
  count("app-map-opened-full");
  shell.hidden = false;
  document.body.classList.add("map-full-on");
  body.appendChild(figure);
  slot.appendChild(legend);
  window.addEventListener("keydown", onKey, true);
  window.addEventListener("resize", onResize);

  const close = document.getElementById("map-full-close");
  if (close) close.focus();
  redrawAll();
  // The shell's own height is only known once the browser has laid the column out, and the
  // first draw asked for it before the legend had any chips in it. One more pass on the next
  // frame, when the box is the size it will stay; the tiles are cached by then.
  requestAnimationFrame(() => { if (full) redrawAll(); });
}

export function closeFullMap({ redraw = true } = {}) {
  if (!full) return;
  const { figure, legend, parent, after } = full;
  const shell = document.getElementById("map-full");
  full = null;
  if (parent) {
    parent.insertBefore(figure, after);
    parent.insertBefore(legend, after);
  }
  if (shell) shell.hidden = true;
  document.body.classList.remove("map-full-on");
  window.removeEventListener("keydown", onKey, true);
  window.removeEventListener("resize", onResize);
  const door = document.getElementById("map-full-open");
  if (door && !door.hidden) door.focus();
  if (redraw) redrawAll();
}
