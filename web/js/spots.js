/* **Spots** — the places you sail, clustered out of where your sessions start.
 *
 * The phone has had this screen since the library had a map: a spot is a cluster of session
 * start coordinates, it is born nameless, and it gets a real name from a reverse geocoder.
 * The browser had half of it — `renderGear` in js/appshell.js listed the clusters and
 * stopped — and this file is the other half: rename, re-cluster, look the names up again,
 * and the "All spots" chip that Records and Trends filter through.
 *
 * **The clusterer is the phone's, to the metre.** `SpotClusterer.cluster` is a single-link
 * greedy assignment against a moving centroid at 500 m, over the sessions oldest first, and
 * `library._spot_clusters` in the lab bundle is the same algorithm in Python. The Python one
 * is reachable from this tab only at **3 km**, which is a different question on purpose —
 * it clusters *trips*, so Torbole and Malcesine come out as one week at Garda
 * (docs/presentation.md, "A trip clusters on coordinates"). A spot is a launch and wants the
 * beach. So the rule is ported here rather than called through Pyodide, and it is ported
 * from the Swift:
 *
 *   ios/WingFoilKit/Sources/WingFoilKit/Persistence/SpotClusterer.swift
 *   ios/WingFoilKit/Sources/WingFoilKit/Persistence/SpotNaming.swift
 *   ios/WingFoil/Features/Spots/SpotsView.swift
 *   ios/WingFoil/Features/Records/LibraryFilterBar.swift
 *
 * **What a browser cannot have.** The phone asks Apple's geocoder. A tab has no CoreLocation
 * and no Apple Maps, so the name comes from Nominatim, which is the OpenStreetMap
 * Foundation's own reverse geocoder. The coordinate is rounded to three decimals before it
 * is sent, exactly as on the phone, it is asked once per spot and cached, and /privacy says
 * so in the same words the map-tile paragraph uses.
 */

import { esc, hms, nf } from "./viz.js";

/* ---------------------------------------------------------------- the clusterer */

/** The phone's `SpotClusterer.defaultRadiusM`. A rig-up beach is tens of metres across and
 *  the next spot is kilometres away, so there is no cluster count to get wrong. */
export const SPOT_RADIUS_M = 500;
const EARTH_RADIUS_M = 6371000;

/** Great-circle metres — the haversine `SpotClusterer.distance` and `library._distance_m`
 *  both compute, including the clamp under the second square root. */
export function metresBetween(a, b) {
  const rad = Math.PI / 180;
  const p1 = a.lat * rad;
  const p2 = b.lat * rad;
  const dp = (b.lat - a.lat) * rad;
  const dl = (b.lon - a.lon) * rad;
  const h = Math.sin(dp / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.atan2(Math.sqrt(h), Math.sqrt(Math.max(0, 1 - h)));
}

const anchorOf = (entry) => {
  const geo = entry && entry.geo;
  return geo && typeof geo.lat === "number" && typeof geo.lon === "number" ? geo : null;
};

/** Oldest first, the order `SpotClusterer.recluster` reads its sessions in (`ORDER BY
 *  startDate`) and the order `library._spot_clusters` reads its digests in. A greedy
 *  clusterer depends on its order, so two surfaces that disagree about it produce two
 *  different sets of spots from one library. */
const oldestFirst = (a, b) =>
  (a.startEpoch ?? 0) - (b.startEpoch ?? 0) || String(a.id).localeCompare(String(b.id));

/**
 * Group the library into places.
 *
 * 1. Take the sessions oldest first.
 * 2. For each, find the nearest existing cluster whose centre is within the radius.
 * 3. Join it and move its centre to the running mean, or start a cluster at this point.
 * 4. A session with no anchor joins the cluster that already holds its filename name, and
 *    otherwise starts a nameless one. That fallback is `library._spot_clusters`'s, for a
 *    row saved before the anchor field existed.
 *
 * Ties go to the cluster created first, because the test is a strict `<`.
 */
export function clusterSpots(entries) {
  const clusters = [];
  const unplaced = [];
  for (const entry of [...entries].sort(oldestFirst)) {
    const geo = anchorOf(entry);
    if (!geo) {
      unplaced.push(entry);
      continue;
    }
    let best = null;
    let bestGap = Infinity;
    for (const c of clusters) {
      const gap = metresBetween(geo, c);
      if (gap <= SPOT_RADIUS_M && gap < bestGap) {
        best = c;
        bestGap = gap;
      }
    }
    if (!best) {
      clusters.push({ lat: geo.lat, lon: geo.lon, n: 1, members: [entry] });
      continue;
    }
    best.lat = (best.lat * best.n + geo.lat) / (best.n + 1);
    best.lon = (best.lon * best.n + geo.lon) / (best.n + 1);
    best.n += 1;
    best.members.push(entry);
  }
  for (const entry of unplaced) {
    const name = String(entry.spot || "");
    const home = clusters.find((c) => c.members.some((m) => String(m.spot || "") === name));
    if (home) home.members.push(entry);
    else clusters.push({ lat: null, lon: null, n: 0, members: [entry] });
  }
  return clusters;
}

/** What to call a cluster before anybody names it: the name most of its afternoons carry,
 *  ties to the earliest, because the first name a place was given is the one the rider has
 *  been reading ever since. `library._cluster_name`. */
export function filenameName(members) {
  const counts = new Map();
  for (const m of members) {
    const name = String(m.spot || "").trim();
    if (name) counts.set(name, (counts.get(name) || 0) + 1);
  }
  if (!counts.size) return "Session";
  const best = Math.max(...counts.values());
  for (const m of members) {
    const name = String(m.spot || "").trim();
    if (counts.get(name) === best) return name;
  }
  return "Session";
}

/* -------------------------------------------------------------- what is stored */

/** The names the rider typed, and the names the geocoder found. Both are kept as a
 *  coordinate and a word, never as a cluster id: a cluster has no identity that survives a
 *  new session arriving, and a centroid does. That is also how the phone carries names
 *  across a re-cluster (`SpotClusterer.recluster`). */
const TYPED_KEY = "spots.typed.v1";
const LOOKED_UP_KEY = "spots.lookedUp.v1";

function readStore(key) {
  try {
    const raw = localStorage.getItem(key);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch { return []; }
}

function writeStore(key, rows) {
  try { localStorage.setItem(key, JSON.stringify(rows)); } catch { /* private window */ }
}

/**
 * Give every cluster its name, in the order the phone settles them.
 *
 * A name somebody typed wins. A name the geocoder found is next. The filename is last, and
 * a spot still wearing it is the browser's equivalent of the phone's `Spot 7` placeholder:
 * it is the set "Look up names again" offers to resolve.
 *
 * Each stored name is claimed **once** per pass, by the nearest cluster inside the radius,
 * which is the rule that stops two clusters in one bay from both answering to one name.
 */
export function nameClusters(clusters) {
  const typed = readStore(TYPED_KEY);
  const lookedUp = readStore(LOOKED_UP_KEY);
  const claimed = new Set();

  const claim = (cluster, rows, tag) => {
    if (cluster.lat === null) return null;
    let best = null;
    let bestGap = Infinity;
    for (const row of rows) {
      const key = `${tag}:${row.lat},${row.lon}`;
      if (claimed.has(key)) continue;
      const gap = metresBetween(cluster, row);
      if (gap <= SPOT_RADIUS_M && gap < bestGap) {
        best = { row, key };
        bestGap = gap;
      }
    }
    if (!best) return null;
    claimed.add(best.key);
    return best.row.name;
  };

  return clusters.map((cluster) => {
    const typedName = claim(cluster, typed, "typed");
    const lookedUpName = typedName ? null : claim(cluster, lookedUp, "found");
    const name = typedName || lookedUpName || filenameName(cluster.members);
    return { ...cluster, name, typed: !!typedName, lookedUp: !!lookedUpName,
             auto: !typedName && !lookedUpName };
  });
}

/** The spots this library has, named and in the phone's order: alphabetical, which is
 *  `SpotRow.order(Column("name"))`. */
export function spotsFor(entries) {
  return nameClusters(clusterSpots(entries))
    .filter((c) => c.members.length > 0)
    .sort((a, b) => a.name.localeCompare(b.name));
}

/** Remember a name the rider typed. An empty name is ignored rather than refused, which is
 *  what `LibraryStore.renameSpot` does. */
export function renameSpot(cluster, name) {
  const clean = String(name || "").trim();
  if (!clean || cluster.lat === null) return false;
  const rows = readStore(TYPED_KEY).filter(
    (row) => metresBetween(cluster, row) > SPOT_RADIUS_M);
  rows.push({ lat: cluster.lat, lon: cluster.lon, name: clean });
  writeStore(TYPED_KEY, rows);
  return true;
}

/* ------------------------------------------------------- looking a name up again */

/** Three decimals is about 110 m, and it is what leaves this browser. The phone rounds by
 *  the same rule before it asks Apple (`SpotNamer.roundedForLookup`). */
const LOOKUP_PRECISION = 3;
const roundForLookup = (v) => Math.round(v * 1000) / 1000;
/** Nominatim's usage policy is at most one request a second. The phone spaces its own at
 *  1.2 s and so does this. */
const LOOKUP_SPACING_MS = 1200;
const LOOKUP_URL = "https://nominatim.openstreetmap.org/reverse";

let lastRequest = 0;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Ask OpenStreetMap what one place is called.
 *
 * A browser cannot set its own `User-Agent`, so the identification the policy asks for is
 * the `Referer` the browser sends by itself, which names cleanjibe.org. The rate limit is
 * ours to keep and is kept above.
 *
 * The composition order is the phone's: the town wins, then the county, then whatever the
 * place itself is called, then the region. Failure returns null and the spot keeps the name
 * it had, which is what "Look up names again" is for.
 */
async function lookupName(lat, lon) {
  const wait = LOOKUP_SPACING_MS - (Date.now() - lastRequest);
  if (wait > 0) await sleep(wait);
  lastRequest = Date.now();
  const url = `${LOOKUP_URL}?format=jsonv2&zoom=14`
    + `&lat=${roundForLookup(lat).toFixed(LOOKUP_PRECISION)}`
    + `&lon=${roundForLookup(lon).toFixed(LOOKUP_PRECISION)}`;
  try {
    const response = await fetch(url, { headers: { Accept: "application/json" } });
    if (!response.ok) return null;
    const body = await response.json();
    const a = body.address || {};
    return a.village || a.town || a.city || a.county || body.name || a.state || null;
  } catch {
    return null;
  }
}

/** One request per spot that has no name of its own, cached for good. */
export async function lookUpNames(clusters, onProgress) {
  const rows = readStore(LOOKED_UP_KEY);
  let found = 0;
  const pending = clusters.filter((c) => c.auto && c.lat !== null);
  for (let i = 0; i < pending.length; i++) {
    if (onProgress) onProgress(i + 1, pending.length);
    const name = await lookupName(pending[i].lat, pending[i].lon);
    if (!name) continue;
    rows.push({ lat: pending[i].lat, lon: pending[i].lon, name });
    found += 1;
  }
  writeStore(LOOKED_UP_KEY, rows);
  return found;
}

/* ------------------------------------------------------------------ the filter */

const FILTER_KEY = "spots.filter.v1";

/** Which spot the Records and Trends chip is on, as the name, or null for all of them. The
 *  name rather than an index, because a saved session can change what index 2 is. */
export function spotFilter() {
  try { return localStorage.getItem(FILTER_KEY) || null; } catch { return null; }
}

export function setSpotFilter(name) {
  try {
    if (name) localStorage.setItem(FILTER_KEY, name);
    else localStorage.removeItem(FILTER_KEY);
  } catch { /* private window */ }
}

/**
 * The sessions of the chosen spot, or all of them.
 *
 * Called by js/trends.js before it aggregates, so Records, Trends and Periods all answer to
 * one chip — which is what the phone's `LibraryFilterBar` does for the same three screens.
 */
export function filterBySpot(entries) {
  const wanted = spotFilter();
  if (!wanted) return entries;
  const spot = spotsFor(entries).find((s) => s.name === wanted);
  if (!spot) return entries;
  const ids = new Set(spot.members.map((m) => m.id));
  return entries.filter((e) => ids.has(e.id));
}

/** The chip itself, over Records and over Trends. */
export function renderSpotChip(host, entries, onChange) {
  if (!host) return;
  const spots = spotsFor(entries);
  const active = spotFilter();
  if (!spots.length) {
    host.innerHTML = "";
    return;
  }
  const options = [`<option value=""${active ? "" : " selected"}>All spots</option>`]
    .concat(spots.map((s) =>
      `<option value="${esc(s.name)}"${s.name === active ? " selected" : ""}>${
        esc(s.name)} (${s.members.length})</option>`));
  host.innerHTML = `<label class="spot-chip">Spot
    <select class="spot-select">${options.join("")}</select></label>`;
  host.querySelector("select").addEventListener("change", (ev) => {
    setSpotFilter(ev.target.value || null);
    if (onChange) onChange();
  });
}

/* -------------------------------------------------------------------- the page */

const totalKm = (members) => members.reduce((t, m) => t + (m.distanceKm || 0), 0);
const totalFoil = (members) => members.reduce((t, m) => t + (m.foilTimeS || 0), 0);

const lastVisit = (members) => {
  const dates = members.map((m) => m.startUtc).filter(Boolean).sort();
  return dates.length ? dates[dates.length - 1].slice(0, 10) : null;
};

/**
 * The Spots section of Gear & spots.
 *
 * The row is the phone's row plus the two totals this tab has always shown: the phone drops
 * them because it has a session list one tap away and the browser's Library tab does not
 * sort by spot. The empty state, the two doors and the footer are the phone's words.
 */
export function renderSpots(host, entries, onChanged) {
  if (!host) return;
  const spots = spotsFor(entries);
  if (!spots.length) {
    host.innerHTML = `<h3 class="sub-head">Spots</h3>
      <p class="note">No spots yet. Spots appear once sessions with GPS are in the
        library.</p>`;
    return;
  }
  const anyAuto = spots.some((s) => s.auto && s.lat !== null);
  host.innerHTML = `<h3 class="sub-head">Spots</h3>
    <ul class="spot-list">${spots.map((spot, index) => {
      const last = lastVisit(spot.members);
      return `<li>
        <button type="button" class="linkish spot-name" data-spot="${index}">${
          esc(spot.name)}</button>
        <span class="dim">${spot.members.length} sessions ·
          ${nf(totalKm(spot.members), 1)} km ·
          ${hms(totalFoil(spot.members))} on foil${last ? ` · last ${esc(last)}` : ""}</span>
      </li>`;
    }).join("")}</ul>
    <p class="spot-actions">
      <button type="button" class="ghost small-btn" id="spot-recluster">Re-cluster
        spots</button>
      <button type="button" class="ghost small-btn" id="spot-lookup"${
        anyAuto ? "" : " disabled"}>Look up names again</button>
      <span class="muted small" id="spot-status" role="status"></span>
    </p>
    <p class="muted small">Tap a spot to rename it. A name you type sticks through a
      re-cluster. Sessions starting within ${SPOT_RADIUS_M} m of each other are one spot.
      Names come from the map when the network allows.</p>`;

  const status = host.querySelector("#spot-status");
  for (const button of host.querySelectorAll("[data-spot]")) {
    button.addEventListener("click", () => {
      const spot = spots[Number(button.dataset.spot)];
      // eslint-disable-next-line no-alert
      const typed = window.prompt("Rename spot", spot.name);
      if (typed === null) return;
      if (renameSpot(spot, typed) && onChanged) onChanged();
    });
  }
  host.querySelector("#spot-recluster").addEventListener("click", () => {
    const fresh = spotsFor(entries);
    status.textContent = `Re-clustered into ${fresh.length} `
      + `${fresh.length === 1 ? "spot" : "spots"}`;
    if (onChanged) onChanged();
  });
  host.querySelector("#spot-lookup").addEventListener("click", async (ev) => {
    ev.target.disabled = true;
    status.textContent = "Looking up names…";
    const found = await lookUpNames(spots, (done, all) => {
      status.textContent = `Looking up names… ${done} of ${all}`;
    });
    status.textContent = found
      ? `Named ${found} ${found === 1 ? "spot" : "spots"}`
      : "No new names. The lookup needs a network.";
    if (onChanged) onChanged();
  });
}
