/* The share card's optional map background: OpenStreetMap raster tiles, composited.
 *
 * The web twin of `ios/WingFoil/Features/Share/ShareCardMap.swift`, which asks MapKit for
 * the same picture through `MKMapSnapshotter`. Both exist for one reason: a card that shows
 * *where* the session was is a different message from a card that shows only its shape, and
 * a rider posting "Torbole, 20 kn" into a group chat is usually answering "where were you".
 *
 * **It is off by default and it stays off unless asked.** Nothing in this module runs, and
 * no request is made, until the rider turns the map on — the plain card must be the card it
 * has always been, byte for byte.
 *
 * **The projection is the map's, not the card's.** `js/sharecard.js` normally fits the ride
 * to its box through the engine's local metres; that projection is about the *session* and
 * has no idea where the water is. With a map behind it the breadcrumb has to sit on the same
 * earth the tiles are pictures of, so the track is re-placed through Web Mercator here and
 * the framing is chosen so the ride lands in exactly the box it would have occupied anyway.
 * The card's layout does not move; only the ground under it appears.
 *
 * **The tile policy.** One card render fetches at most `MAX_TILES` tiles, once, with no
 * retry of any kind: a failed tile is a hole the navy shows through, and a wholly failed
 * fetch is a plain card. The composited backdrop is cached per framing, so a rider typing a
 * caption — which redraws the card on every keystroke — asks for nothing at all after the
 * first draw. See https://operations.osmfoundation.org/policies/tiles/.
 *
 * **Attribution is not optional.** ODbL requires the credit, so `CREDIT` is drawn on the
 * card by `js/sharecard.js` whenever a single tile made it onto the picture.
 */

/** ODbL's required credit, exactly as the OSM Foundation asks for it. */
export const CREDIT = "© OpenStreetMap contributors";

/** The standard OSM raster layer. Written out rather than templated from a host constant so
 *  that the one URL this project fetches from a third party is greppable in one line. */
const TILE_URL = (z, x, y) => `https://tile.openstreetmap.org/${z}/${x}/${y}.png`;

/** Raster pixels per tile, as the layer serves them. */
const TILE = 256;

/** Raster pixels per *layout point* the backdrop aims for. The card exports at 3× (see
 *  `SCALE` in js/sharecard.js), so 2 is a two-thirds-resolution background — soft enough to
 *  cost a third of the tiles a native-resolution one would, sharp enough that a coastline
 *  under a scrim reads as a coastline. The map is the ground, not the subject. */
const MAP_SCALE = 2;

/** The ceiling on one card's fetch. The zoom steps down until the grid fits under it, so a
 *  landscape card simply gets a slightly softer map rather than thirty more requests. */
const MAX_TILES = 30;

/** How long one tile gets. A card is made on a beach as often as at a desk; past this the
 *  rider is waiting on something that is only the background. */
const TILE_TIMEOUT_MS = 6000;

/** Mercator's cut-off, where the pole would need infinite paper. */
const MAX_LAT = 85.05112878;

/**
 * One coordinate in the unit world square: x east from the anti-meridian, y **south** from
 * the top, both 0…1, which is the frame every raster tile scheme is cut out of.
 */
export function worldPoint(lat, lon) {
  const clamped = Math.max(-MAX_LAT, Math.min(MAX_LAT, lat));
  const s = Math.sin(clamped * Math.PI / 180);
  return {
    x: (lon + 180) / 360,
    y: 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI),
  };
}

/**
 * Where the map sits under the card, as a scale and an origin.
 *
 * `box` is the rectangle the card would have drawn the track into (layout points, in the
 * card's own coordinates) and `inset` the padding that box already reserves for a mark on
 * its outermost vertex. The scale is chosen so the ride fills that box exactly as it does on
 * a plain card, and the origin so that the *card* — which is larger than the box in every
 * direction — extends the same map outwards around it. That is the whole trick: the layout
 * does not know a map arrived.
 *
 * Uniform in both axes, like every other fit on this card: a track stretched to fill two
 * axes is a different-shaped session, and a *map* stretched to fill two axes is a lie about
 * the coastline.
 *
 * `null` when the track has no extent at all and no anchor to fall back on.
 */
export function frameTrack({ min, max, box, inset }) {
  const a = worldPoint(max.lat, min.lon);            // north-west corner: min y, min x
  const b = worldPoint(min.lat, max.lon);            // south-east corner: max y, max x
  const dx = Math.abs(b.x - a.x), dy = Math.abs(b.y - a.y);
  const w = Math.max(box.w - inset * 2, 1), h = Math.max(box.h - inset * 2, 1);
  // A perfectly straight leg has zero extent on one axis; that axis then imposes no limit,
  // which is exactly right — `min` takes the other one.
  let scale = Math.min(dx > 1e-12 ? w / dx : Infinity, dy > 1e-12 ? h / dy : Infinity);
  if (!Number.isFinite(scale)) {
    // A rider who never moved. There is no extent to fit, so the map is given a fixed span
    // instead — 600 m across the box, which is a launch beach and its shoreline.
    const metresPerWorld = 40075017 * Math.cos(((min.lat + max.lat) / 2) * Math.PI / 180);
    scale = metresPerWorld > 0 ? (box.w * metresPerWorld) / 600 : 0;
  }
  if (!(scale > 0) || !Number.isFinite(scale)) return null;

  const centre = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
  return {
    scale,
    originX: centre.x - (box.x + box.w / 2) / scale,
    originY: centre.y - (box.y + box.h / 2) / scale,
  };
}

/** A coordinate's place on the card, in layout points, through `frame`. The twin of
 *  `MKMapSnapshot.point(for:)` on iOS, and the only projection the breadcrumb may use once
 *  there is a map under it. */
export function placeOn(frame, lat, lon) {
  const p = worldPoint(lat, lon);
  return { x: (p.x - frame.originX) * frame.scale, y: (p.y - frame.originY) * frame.scale };
}

/** The tile grid that covers `cardW` × `cardH` layout points under `frame`, at the coarsest
 *  zoom that still resolves and the finest that still fits `MAX_TILES`. */
function tileGrid(frame, cardW, cardH) {
  // Raster pixels per world unit wanted, turned into the zoom whose tiles supply them.
  let zoom = Math.round(Math.log2(Math.max(frame.scale, 1) * MAP_SCALE / TILE));
  zoom = Math.max(0, Math.min(19, zoom));
  for (; zoom >= 0; zoom--) {
    const n = 2 ** zoom;
    const x0 = Math.floor(frame.originX * n);
    const y0 = Math.floor(frame.originY * n);
    const x1 = Math.floor((frame.originX + cardW / frame.scale) * n);
    const y1 = Math.floor((frame.originY + cardH / frame.scale) * n);
    const cols = x1 - x0 + 1, rows = y1 - y0 + 1;
    if (cols * rows <= MAX_TILES || zoom === 0) {
      return { zoom, n, x0, y0, cols, rows };
    }
  }
  return null;
}

/** One tile, or null. Never retried: a card is made once and a hole in the water is a
 *  better answer than a rider waiting on a second round of requests. */
function loadTile(url) {
  return new Promise((resolve) => {
    const img = new Image();
    let done = false;
    const finish = (value) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(value);
    };
    const timer = setTimeout(() => finish(null), TILE_TIMEOUT_MS);
    // Without this the tiles paint but taint the canvas, and `toBlob` — the whole point of
    // the card — throws. tile.openstreetmap.org sends `Access-Control-Allow-Origin: *`.
    img.crossOrigin = "anonymous";
    img.onload = () => finish(img);
    img.onerror = () => finish(null);
    img.src = url;
  });
}

/** The last backdrop composited, by framing. A caption is typed one character at a time and
 *  each keystroke redraws the whole card; without this that would be a tile fetch per
 *  letter. One entry: the rider is looking at one card. */
let cached = { key: "", canvas: null };

/**
 * The map behind one card, as a bitmap in **exported pixels**, or null.
 *
 * Null covers every way this can fail — no tile arrived, the grid could not be built, the
 * canvas came back tainted — and the caller's answer to all of them is the same: draw the
 * plain card and say nothing. A rider on a train still gets a card.
 */
export async function mapBackdrop(frame, cardW, cardH, scale) {
  const grid = tileGrid(frame, cardW, cardH);
  if (!grid) return null;

  const key = [grid.zoom, grid.x0, grid.y0, grid.cols, grid.rows,
               frame.originX.toFixed(9), frame.originY.toFixed(9),
               frame.scale.toFixed(4), cardW, cardH].join("|");
  if (cached.key === key && cached.canvas) return cached.canvas;

  const wanted = [];
  for (let row = 0; row < grid.rows; row++) {
    for (let col = 0; col < grid.cols; col++) {
      const x = grid.x0 + col, y = grid.y0 + row;
      // Off the top or the bottom of the world there is no tile; east–west wraps.
      if (y < 0 || y >= grid.n) continue;
      wanted.push({ x, y, url: TILE_URL(grid.zoom, ((x % grid.n) + grid.n) % grid.n, y) });
    }
  }
  const images = await Promise.all(wanted.map((t) => loadTile(t.url)));
  if (!images.some(Boolean)) return null;

  const canvas = document.createElement("canvas");
  canvas.width = Math.round(cardW * scale);
  canvas.height = Math.round(cardH * scale);
  const ctx = canvas.getContext("2d");
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  const side = frame.scale / grid.n;                 // one tile, in layout points
  images.forEach((img, i) => {
    if (!img) return;
    const t = wanted[i];
    const x = (t.x / grid.n - frame.originX) * frame.scale;
    const y = (t.y / grid.n - frame.originY) * frame.scale;
    // A hair of overlap: adjacent tiles drawn at fractional positions leave a seam of
    // background between them otherwise, and a grid of hairlines over the water is the one
    // artefact a reader would notice.
    ctx.drawImage(img, x, y, side + 0.5, side + 0.5);
  });

  try {
    // The taint probe. Everything above is CORS-clean in theory; this is what makes the
    // card's `toBlob` safe in fact, on whatever proxy or extension is between the rider and
    // the tile server. A tainted scratch canvas is thrown away and never reaches the card.
    ctx.getImageData(0, 0, 1, 1);
  } catch {
    return null;
  }

  cached = { key, canvas };
  return canvas;
}
