/* Rendering: summary tiles, inline-SVG track map, inline-SVG speed strip, tables.
 *
 * No chart library and no map tiles — the track is drawn in the lab's own local-metre
 * projection, exactly like lab/tools/plot_turns.py. The shared encoding, which the two
 * figures and the tables all obey:
 *
 *   line colour   off-foil = recessive grey, foiling = series-1 blue
 *   marker SHAPE  carries the outcome (disc / triangle / heavy X / hairline x / hollow square)
 *   marker colour only reinforces it — the status ramp fails a CVD check on its own
 *   marker number is the turn's row number in the Turns table
 */

const C = {
  track: "#4a4a45", foil: "#3987e5", tint: "#7fb0e8",
  good: "#0ca30c", warn: "#fab219", bad: "#d03b3b", reject: "#7a7a72",
  ink: "#ffffff", ink2: "#c3c2b7", ink3: "#8a8a80",
  surface: "#1a1a19", grid: "#333331",
};

const OUTCOME_COLOR = { flew_through: C.good, touchdown: C.warn, fell_in: C.bad,
                        glide_out: C.ink2, unknown: C.ink3 };
const OUTCOME_LABEL = { flew_through: "flew through", touchdown: "touched down",
                        fell_in: "fell in", glide_out: "glided out", unknown: "no evidence" };

/* ---------------------------------------------------------------- formatting */

const nf = (v, d = 1) => (v === null || v === undefined || Number.isNaN(v) ? "—" : v.toFixed(d));
const int = (v) => (v === null || v === undefined ? "—" : Math.round(v).toLocaleString("en-US"));

function hms(sec) {
  if (sec === null || sec === undefined) return "—";
  const s = Math.round(sec);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`
           : `${m}:${String(r).padStart(2, "0")}`;
}

function clockAt(startUtc, t) {
  if (!startUtc) return hms(t);
  const d = new Date(new Date(startUtc).getTime() + t * 1000);
  return d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function sessionDate(startUtc) {
  if (!startUtc) return "Session";
  return new Date(startUtc).toLocaleString("en-GB",
    { weekday: "short", year: "numeric", month: "short", day: "numeric",
      hour: "2-digit", minute: "2-digit" });
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

const el = (id) => document.getElementById(id);

/* -------------------------------------------------------------- svg helpers */

const SVGNS = "http://www.w3.org/2000/svg";

function svg(tag, attrs = {}, parent = null) {
  const node = document.createElementNS(SVGNS, tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v !== null && v !== undefined) node.setAttribute(k, v);
  }
  if (parent) parent.appendChild(node);
  return node;
}

/** The five marker shapes, drawn centred on (0,0) and translated into place. */
function marker(parent, kind, x, y, scale = 1) {
  const g = svg("g", { transform: `translate(${x.toFixed(2)} ${y.toFixed(2)}) scale(${scale})` }, parent);
  const color = kind.color;
  switch (kind.shape) {
    case "disc":
      svg("circle", { r: 4.2, fill: color, stroke: C.surface, "stroke-width": 1.2 }, g);
      break;
    case "triangle":
      svg("path", { d: "M-4.6,-3.4 L4.6,-3.4 L0,4.4 Z", fill: color,
                    stroke: C.surface, "stroke-width": 1.2, "stroke-linejoin": "round" }, g);
      break;
    case "cross":
      svg("path", { d: "M-4,-4 L4,4 M-4,4 L4,-4", stroke: color, "stroke-width": 2.8,
                    "stroke-linecap": "round", fill: "none" }, g);
      break;
    case "hairline":
      svg("path", { d: "M-3.4,-3.4 L3.4,3.4 M-3.4,3.4 L3.4,-3.4", stroke: color,
                    "stroke-width": 1.3, "stroke-linecap": "round", fill: "none" }, g);
      break;
    case "square":
      svg("rect", { x: -4.4, y: -4.4, width: 8.8, height: 8.8, rx: 1.2,
                    fill: "none", stroke: color, "stroke-width": 1.8 }, g);
      break;
  }
  return g;
}

/** Marker style for a turn: bear-aways/round-ups are not manoeuvres, so they stay a
 *  recessive hairline whatever their outcome was (same rule as plot_turns.py). */
const turnStyle = (m) => m.maneuver
  ? { shape: { flew_through: "disc", touchdown: "triangle", fell_in: "cross" }[m.outcome] || "disc",
      color: OUTCOME_COLOR[m.outcome] || C.reject }
  : { shape: "hairline", color: C.reject };

const endStyle = (e) => ({ shape: "square", color: OUTCOME_COLOR[e.outcome] || C.ink3 });

function label(parent, x, y, n, color, up) {
  const t = svg("text", {
    x: x.toFixed(2), y: (y + (up ? -9 : 15)).toFixed(2), "text-anchor": "middle",
    "font-size": 10, "font-weight": 700, fill: color,
    stroke: C.surface, "stroke-width": 2.6, "paint-order": "stroke",
    "stroke-linejoin": "round",
  }, parent);
  t.textContent = String(n);
  return t;
}

/* ---------------------------------------------------------------- the report */

export function render(result) {
  const g = result.golden, v = result.view, meta = result.meta;
  renderSummary(result);
  renderMap(el("map-figure"), el("map-legend"), result);
  renderStrip(el("strip-figure"), el("strip-legend"), result);
  renderTakeoffs(el("takeoff-body"), g, meta);
  renderTurns(el("turns-table"), el("turns-caption"), g, v, meta);
  renderEnds(el("ends-table"), el("ends-caption"), g, meta);
}

/* -------------------------------------------------------------------- header */

function renderSummary(result) {
  const g = result.golden, meta = result.meta, caps = g.capabilities;
  const s = g.summary, rec = g.records, w = g.wind;

  el("session-title").textContent = sessionDate(meta.startUtc);
  el("session-sub").innerHTML =
    `${esc(result.file.name)} · ${int(meta.samples)} samples @ ${nf(caps.sampleRateHz, 0)} Hz` +
    (meta.startUtc ? ` · times shown in your local timezone` : "");

  const badges = [];
  if (meta.discipline) badges.push([meta.discipline, true]);
  badges.push([{ a: "CIQ dev fields", b: "native FIT", c: "degraded source" }[meta.sourceClass],
               meta.sourceClass === "a"]);
  if (meta.sport) badges.push([meta.sport, false]);
  if (caps.hasAccel) badges.push(["accel", false]);
  if (caps.hasWatchLaps) badges.push([`${meta.laps} laps`, false]);
  if (caps.hasHR) badges.push(["HR", false]);
  el("session-badges").innerHTML = badges
    .map(([t, accent]) => `<span class="badge${accent ? " accent" : ""}">${esc(t)}</span>`).join("");

  const windTile = w
    ? { k: "Wind axis", v: `${nf(w.dirDeg, 0)}°`, unit: "from",
        n: `confidence ${nf(w.confidence, 2)} · lobes ${nf(w.lobesDeg?.[0], 0)}/${nf(w.lobesDeg?.[1], 0)}°` +
           (meta.windDirUserDeg !== null && meta.windDirUserDeg !== undefined
              ? ` · watch says ${nf(meta.windDirUserDeg, 0)}°` : "") }
    : { k: "Wind axis", v: "—", n: "no usable axis in the COG distribution" };

  const tiles = [
    { k: "Duration", v: hms(meta.durationS), n: `moving ${hms(meta.timerTimeS)}` },
    { k: "Distance", v: nf(s.distanceKm, 2), unit: "km", n: `best 500 m ${nf(rec.best500mKn, 1)} kn` },
    { k: "On foil", v: `${nf(s.foilPct, 0)}%`, n: `${hms(s.foilTimeS)} flying` },
    { k: "Flights", v: int(s.flightCount),
      n: `longest ${hms(s.longestFlightS)} · ${int(s.longestFlightM)} m` },
    { k: "Best 2 s", v: nf(rec.best2sKn, 2), unit: "kn", n: `10 s ${nf(rec.best10sKn, 2)} kn` },
    { k: "Best 5×10 s", v: nf(rec.best5x10sKn, 2), unit: "kn", n: `1 NM ${nf(rec.bestNmKn, 2)} kn` },
    { k: "Alpha 500", v: nf(rec.alpha500Kn, 2), unit: "kn", n: `250 m ${nf(rec.best250mKn, 2)} kn` },
    { k: "Turns", v: int(s.turns.turnsCounted),
      n: `${s.turns.jibes} jibes · ${s.turns.tacks} tacks · ${nf(s.turns.successPct, 0)}% held speed` },
    { k: "Outcomes", v: `${s.turns.outcomes.flewThrough}/${s.turns.outcomes.touchdown}/${s.turns.outcomes.fellIn}`,
      n: "flew through / touchdown / fell in" },
    windTile,
  ];
  el("tiles").innerHTML = tiles.map((t) => `
    <div class="tile">
      <div class="k">${esc(t.k)}</div>
      <div class="v">${esc(t.v)}${t.unit ? `<small>${esc(t.unit)}</small>` : ""}</div>
      <div class="n">${esc(t.n || "")}</div>
    </div>`).join("");
}

/* ----------------------------------------------------------------------- map */

function renderMap(host, legendHost, result) {
  host.innerHTML = "";
  const v = result.view, g = result.golden;
  // `hasPositions` is false for Doppler-only sources: the analysis (speed strip, records,
  // flights, outcomes) is all still there, there is simply no track to plot.
  if (!v.count || !v.bounds || v.hasPositions === false || v.bounds.x0 === null) {
    host.innerHTML = `<p class="note">No GPS positions in this file — no track to draw. ` +
                     `The speed strip and the tables below are unaffected.</p>`;
    legendHost.innerHTML = "";
    return;
  }

  const b = v.bounds;
  const W = 1100, PAD = 34;
  const dw = Math.max(b.x1 - b.x0, 1), dh = Math.max(b.y1 - b.y0, 1);
  const inner = W - 2 * PAD;
  let H = Math.round(inner * (dh / dw)) + 2 * PAD;
  H = Math.min(Math.max(H, 340), 760);
  const s = Math.min(inner / dw, (H - 2 * PAD) / dh);
  const ox = PAD + (inner - dw * s) / 2 - b.x0 * s;
  const oy = PAD + (H - 2 * PAD - dh * s) / 2 + b.y1 * s;   // y flipped: north up
  const X = (x) => ox + x * s;
  const Y = (y) => oy - y * s;

  const root = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img",
                            "aria-label": "GPS track with turn outcome markers" }, host);
  svg("rect", { width: W, height: H, fill: C.surface }, root);

  // Off-foil track, broken at recording gaps.
  const runs = polylineRuns(v, () => true);
  for (const pts of runs) {
    svg("polyline", { points: pts.map(([x, y]) => `${X(x).toFixed(1)},${Y(y).toFixed(1)}`).join(" "),
                      fill: "none", stroke: C.track, "stroke-width": 1.4,
                      "stroke-linecap": "round", "stroke-linejoin": "round" }, root);
  }
  // Foiling segments on top.
  for (const f of v.flights) {
    for (const pts of polylineRuns(v, (t) => t >= f.startTs && t <= f.endTs)) {
      svg("polyline", { points: pts.map(([x, y]) => `${X(x).toFixed(1)},${Y(y).toFixed(1)}`).join(" "),
                        fill: "none", stroke: C.foil, "stroke-width": 2.1, opacity: 0.9,
                        "stroke-linecap": "round", "stroke-linejoin": "round" }, root);
    }
  }

  // Straight-line flight ends (hollow squares) below the turn markers.
  for (const e of v.endMarkers.filter((e) => e.drawOnMap)) {
    const m = marker(root, endStyle(e), X(e.x), Y(e.y));
    tipTarget(m, `<b>${clockAt(result.meta.startUtc, e.t)}</b> — flight ${e.flightIndex + 1} ends<br>` +
                 `${OUTCOME_LABEL[e.outcome]} · straight line (no manoeuvre)`);
  }
  // Numbered turn markers.
  v.turnMarkers.forEach((m) => {
    const st = turnStyle(m);
    const node = marker(root, st, X(m.x), Y(m.y));
    label(root, X(m.x), Y(m.y), m.n, st.color, m.n % 2 === 1);
    const turn = g.turns[m.i];
    tipTarget(node, `<b>#${m.n} ${clockAt(result.meta.startUtc, m.t)}</b> — ${esc(m.kind)}<br>` +
      `${OUTCOME_LABEL[m.outcome] || m.outcome} · ${nf(turn.entryKn, 1)} → ${nf(turn.minKn, 1)} kn ` +
      `(${nf(turn.score * 100, 0)} %)`);
  });

  if (g.wind) windArrow(root, g.wind, W, H);
  scaleBar(root, s, PAD, H - 16);

  legendHost.innerHTML = mapLegend(g);
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

function windArrow(root, wind, W, H) {
  const cx = W - 92, cy = 62, span = 62;
  const to = ((wind.dirDeg + 180) * Math.PI) / 180;      // where the air travels
  const dx = Math.sin(to) * span, dy = -Math.cos(to) * span;
  const g = svg("g", {}, root);
  svg("defs", {}, g).innerHTML =
    `<marker id="windhead" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6"
             orient="auto"><path d="M0,1 L9,5 L0,9 z" fill="${C.ink2}"/></marker>`;
  svg("line", { x1: cx - dx / 2, y1: cy - dy / 2, x2: cx + dx / 2, y2: cy + dy / 2,
                stroke: C.ink2, "stroke-width": 2.2, "stroke-linecap": "round",
                "marker-end": "url(#windhead)" }, g);
  const t = svg("text", { x: cx, y: cy + span / 2 + 18, "text-anchor": "middle",
                          "font-size": 11, "font-weight": 600, fill: C.ink2 }, g);
  t.textContent = `wind ${wind.dirDeg.toFixed(0)}° (conf ${wind.confidence.toFixed(2)})`;
}

function scaleBar(root, s, x, y) {
  const targets = [100, 200, 500, 1000, 2000];
  const meters = targets.find((m) => m * s > 70) ?? 100;
  const w = meters * s;
  const g = svg("g", {}, root);
  svg("path", { d: `M${x},${y - 5} v5 h${w.toFixed(1)} v-5`, fill: "none",
                stroke: C.ink3, "stroke-width": 1.2 }, g);
  const t = svg("text", { x: x + w / 2, y: y + 12, "text-anchor": "middle",
                          "font-size": 10.5, fill: C.ink3 }, g);
  t.textContent = meters >= 1000 ? `${meters / 1000} km` : `${meters} m`;
}

function mapLegend(g) {
  const oc = g.summary.turns.outcomes, st = g.summary.flightEnds.straight;
  const items = [
    line(C.track, "off foil"), line(C.foil, "foiling"),
    glyph("disc", C.good, `flew through (${oc.flewThrough})`),
    glyph("triangle", C.warn, `touched down (${oc.touchdown})`),
    glyph("cross", C.bad, `fell in (${oc.fellIn})`),
  ];
  if (g.summary.turns.rejected) {
    items.push(glyph("hairline", C.reject, `bear-away / round-up, not counted (${g.summary.turns.rejected})`));
  }
  for (const [key, n, text] of [["glide_out", st.glideOut, "straight-line glide-out"],
                                ["touchdown", st.touchdown, "straight-line touchdown"],
                                ["fell_in", st.fellIn, "straight-line fall"]]) {
    if (n) items.push(glyph("square", OUTCOME_COLOR[key], `${text} (${n})`));
  }
  if (g.wind) items.push(`<span class="item">
    <svg viewBox="-8 -8 16 16"><line x1="-6" y1="4" x2="6" y2="-4" stroke="${C.ink2}"
      stroke-width="2" stroke-linecap="round"/><path d="M6,-4 L2,-4 M6,-4 L6,0"
      stroke="${C.ink2}" stroke-width="2" stroke-linecap="round" fill="none"/></svg>
    estimated wind axis</span>`);
  return items.join("");
}

const line = (color, text) => `<span class="item">
  <svg viewBox="-8 -8 16 16"><line x1="-7" y1="0" x2="7" y2="0" stroke="${color}"
    stroke-width="2.4" stroke-linecap="round"/></svg>${esc(text)}</span>`;

function glyph(shape, color, text) {
  const holder = document.createElementNS(SVGNS, "svg");
  holder.setAttribute("viewBox", "-8 -8 16 16");
  marker(holder, { shape, color }, 0, 0);
  return `<span class="item">${holder.outerHTML}${esc(text)}</span>`;
}

/* --------------------------------------------------------------- speed strip */

function renderStrip(host, legendHost, result) {
  host.innerHTML = "";
  const v = result.view, g = result.golden;
  if (!v.count) { host.innerHTML = `<p class="note">No speed samples.</p>`; return; }

  const W = 1100, H = 320, L = 46, R = 16, T = 18, B = 34;
  const b = v.bounds;
  const t0 = b.t0, t1 = Math.max(b.t1, t0 + 1);
  const knMax = Math.max(2, Math.ceil((b.knMax * 1.12) / 2) * 2);
  const X = (t) => L + ((t - t0) / (t1 - t0)) * (W - L - R);
  const Y = (kn) => H - B - (kn / knMax) * (H - T - B);

  const root = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img",
                            "aria-label": "Speed over time with flight bands and turn markers" }, host);
  svg("rect", { width: W, height: H, fill: C.surface }, root);

  for (const f of v.flights) {
    svg("rect", { x: X(f.startTs), y: T, width: Math.max(1, X(f.endTs) - X(f.startTs)),
                  height: H - T - B, fill: C.foil, opacity: 0.10 }, root);
  }
  for (let kn = 0; kn <= knMax; kn += 2) {
    svg("line", { x1: L, x2: W - R, y1: Y(kn), y2: Y(kn), stroke: C.grid, "stroke-width": 1,
                  opacity: kn === 0 ? 0.9 : 0.45 }, root);
    const t = svg("text", { x: L - 8, y: Y(kn) + 3.5, "text-anchor": "end",
                            "font-size": 10.5, fill: C.ink3 }, root);
    t.textContent = String(kn);
  }
  const stepMin = tickStep((t1 - t0) / 60);
  for (let m = 0; m * 60 <= t1; m += stepMin) {
    const x = X(m * 60);
    svg("line", { x1: x, x2: x, y1: H - B, y2: H - B + 4, stroke: C.grid, "stroke-width": 1 }, root);
    const t = svg("text", { x, y: H - B + 17, "text-anchor": "middle", "font-size": 10.5,
                            fill: C.ink3 }, root);
    t.textContent = `${m}`;
  }
  axisLabel(root, L - 34, T + (H - T - B) / 2, "speed (kn)", true);
  axisLabel(root, L + (W - L - R) / 2, H - 4, "session time (min)", false);

  series(root, v, v.speedKn, X, Y, C.tint, 1.0, 0.85);
  series(root, v, v.dopplerKn, X, Y, C.foil, 1.5, 1);

  for (const e of v.endMarkers.filter((e) => e.drawOnMap)) {
    const kn = sampleAt(v, e.t);
    marker(root, endStyle(e), X(e.t), Y(kn), 0.85);
  }
  v.turnMarkers.forEach((m) => {
    const st = turnStyle(m);
    marker(root, st, X(m.t), Y(m.kn), 0.85);
    label(root, X(m.t), Y(m.kn), m.n, st.color, m.n % 2 === 1);
  });

  crosshair(root, result, X, Y, { W, H, L, R, T, B, t0, t1 });
  legendHost.innerHTML =
    line(C.foil, "Doppler — drives the flight state") +
    line(C.tint, "positional — scores the turns") +
    `<span class="item"><svg viewBox="-8 -8 16 16"><rect x="-7" y="-6" width="14" height="12"
      fill="${C.foil}" opacity="0.22"/></svg>flight (on foil)</span>`;
}

function series(root, v, arr, X, Y, color, width, opacity) {
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
    if (arr[i] === null || (i > 0 && v.segment[i] !== v.segment[i - 1])) flush();
    if (arr[i] !== null) cur.push(`${X(v.t[i]).toFixed(1)},${Y(arr[i]).toFixed(1)}`);
  }
  flush();
}

function tickStep(minutes) {
  for (const s of [1, 2, 5, 10, 15, 20, 30, 60]) if (minutes / s <= 14) return s;
  return 120;
}

function axisLabel(root, x, y, text, rotate) {
  const t = svg("text", { x, y, "text-anchor": "middle", "font-size": 11, fill: C.ink3,
                          transform: rotate ? `rotate(-90 ${x} ${y})` : null }, root);
  t.textContent = text;
}

function indexAt(v, t) {
  let lo = 0, hi = v.count - 1;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (v.t[mid] < t) lo = mid + 1; else hi = mid; }
  if (lo > 0 && Math.abs(v.t[lo - 1] - t) < Math.abs(v.t[lo] - t)) lo -= 1;
  return lo;
}
const sampleAt = (v, t) => v.speedKn[indexAt(v, t)] ?? 0;

/** Crosshair + tooltip on the speed strip (the default interaction layer). */
function crosshair(root, result, X, Y, box) {
  const v = result.view;
  const g = svg("g", { visibility: "hidden" }, root);
  const vline = svg("line", { y1: box.T, y2: box.H - box.B, stroke: C.ink3,
                              "stroke-width": 1, "stroke-dasharray": "3 3" }, g);
  const dot = svg("circle", { r: 3.4, fill: C.foil, stroke: C.surface, "stroke-width": 1.4 }, g);
  const hit = svg("rect", { x: box.L, y: box.T, width: box.W - box.L - box.R,
                            height: box.H - box.T - box.B, fill: "transparent" }, root);

  hit.addEventListener("pointermove", (ev) => {
    const r = root.getBoundingClientRect();
    const ux = ((ev.clientX - r.left) / r.width) * box.W;
    const t = box.t0 + ((ux - box.L) / (box.W - box.L - box.R)) * (box.t1 - box.t0);
    const i = indexAt(v, t);
    const kn = v.dopplerKn[i] ?? v.speedKn[i] ?? 0;
    g.setAttribute("visibility", "visible");
    vline.setAttribute("x1", X(v.t[i])); vline.setAttribute("x2", X(v.t[i]));
    dot.setAttribute("cx", X(v.t[i])); dot.setAttribute("cy", Y(kn));
    showTip(ev, `<b>${clockAt(result.meta.startUtc, v.t[i])}</b> · ${hms(v.t[i])}<br>` +
                `Doppler <b>${nf(v.dopplerKn[i], 2)}</b> kn · positional <b>${nf(v.speedKn[i], 2)}</b> kn`);
  });
  hit.addEventListener("pointerleave", () => { g.setAttribute("visibility", "hidden"); hideTip(); });
}

/* ------------------------------------------------------------------- tooltip */

let tipEl = null;
function tip() {
  if (!tipEl) { tipEl = document.createElement("div"); tipEl.className = "tip"; document.body.appendChild(tipEl); }
  return tipEl;
}
function showTip(ev, html) {
  const t = tip();
  t.innerHTML = html;
  t.classList.add("on");
  const pad = 14;
  const r = t.getBoundingClientRect();
  let x = ev.clientX + pad, y = ev.clientY + pad;
  if (x + r.width > window.innerWidth - 8) x = ev.clientX - r.width - pad;
  if (y + r.height > window.innerHeight - 8) y = ev.clientY - r.height - pad;
  t.style.left = `${x}px`; t.style.top = `${y}px`;
}
const hideTip = () => tipEl && tipEl.classList.remove("on");

function tipTarget(node, html) {
  node.style.cursor = "pointer";
  node.addEventListener("pointerenter", (ev) => showTip(ev, html));
  node.addEventListener("pointermove", (ev) => showTip(ev, html));
  node.addEventListener("pointerleave", hideTip);
}

/* ------------------------------------------------------------------ takeoffs */

function renderTakeoffs(host, g, meta) {
  const k = g.summary.takeoff;
  const accel = g.capabilities.hasAccel;
  const rows = [
    ["Attempts", int(k.takeoffAttempts)],
    ["Successful", `${int(k.takeoffSuccesses)} (${nf(k.successPct, 0)} %)`],
    ["Failed", int(k.failedAttempts)],
    ["Avg time to foil", k.avgTakeoffS === null ? "—" : `${nf(k.avgTakeoffS, 1)} s`],
    ["Median time to foil", k.medianTakeoffS === null ? "—" : `${nf(k.medianTakeoffS, 1)} s`],
  ];
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
    ${accel ? "" : `<p class="note" style="margin-top:14px">
      No wrist accelerometer stream in this file, so pump-stroke detection could not run:
      pumps-to-takeoff and stroke counts are unavailable. Attempts and timings above come from
      the speed trace alone.</p>`}`;
}

/* -------------------------------------------------------------------- tables */

function outcomePill(outcome) {
  const holder = document.createElementNS(SVGNS, "svg");
  holder.setAttribute("viewBox", "-6 -6 12 12");
  const shape = { flew_through: "disc", touchdown: "triangle", fell_in: "cross" }[outcome] || "square";
  marker(holder, { shape, color: OUTCOME_COLOR[outcome] || C.ink3 }, 0, 0, 0.85);
  return `<span class="pill ${outcome}">${holder.outerHTML}${OUTCOME_LABEL[outcome] || outcome}</span>`;
}

const yn = (b) => (b ? "yes" : "–");

function renderTurns(table, caption, g, v, meta) {
  const s = g.summary.turns;
  caption.textContent =
    `${s.turnsCounted} counted (${s.jibes} jibes, ${s.tacks} tacks), ${s.rejected} bear-aways rejected · ` +
    `${s.turnsSuccessful} held ≥ 70 % of entry speed (${nf(s.successPct, 0)} %) · ` +
    `port/starboard ${s.port}/${s.starboard}`;

  const head = ["#", "time", "type", "turn", "tack", "entry kn", "min kn", "score", "held",
                "outcome", "stop s", "off foil s", "pump", "wet", "arc m", "R m"];
  table.innerHTML = `<thead><tr>${head
    .map((h, i) => `<th${i <= 4 || i === 9 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${g.turns.map((t, i) => `
      <tr>
        <td class="l">${i + 1}</td>
        <td class="l">${clockAt(meta.startUtc, t.ts)}</td>
        <td class="l">${esc(t.type)}${t.counted ? "" : ' <span class="pill">not counted</span>'}</td>
        <td class="l dim">${esc(t.direction)}</td>
        <td class="l dim">${esc(t.side)}</td>
        <td>${nf(t.entryKn, 2)}</td>
        <td>${nf(t.minKn, 2)}</td>
        <td>${nf(t.score * 100, 0)} %</td>
        <td>${yn(t.success)}</td>
        <td class="l">${outcomePill(t.outcome)}${t.borderline ? ' <span class="pill">borderline</span>' : ""}</td>
        <td>${nf(t.stoppedS, 1)}</td>
        <td>${nf(t.offFoilS, 1)}</td>
        <td class="dim">${yn(t.pumped)}</td>
        <td class="dim">${yn(t.submerged)}</td>
        <td class="dim">${nf(t.arcM, 0)}</td>
        <td class="dim">${nf(t.radiusM, 0)}</td>
      </tr>`).join("")}</tbody>`;
}

function renderEnds(table, caption, g, meta) {
  const e = g.summary.flightEnds, sp = g.summary.outcomeSplit;
  caption.textContent =
    `${sp.turnFalls} falls in turns / ${sp.straightFalls} straight-line · ` +
    `${sp.turnTouchdowns} touchdowns in turns / ${sp.straightTouchdowns} straight-line · ` +
    `${sp.glideOuts} glide-outs` + (sp.unknownEnds ? ` · ${sp.unknownEnds} truncated by a gap` : "");

  const head = ["flight", "time", "outcome", "stop s", "off foil s", "min kn", "pump", "wet",
                "window s", "in turn"];
  table.innerHTML = `<thead><tr>${head
    .map((h, i) => `<th${i <= 2 || i === 9 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${g.flightEnds.map((x) => `
      <tr>
        <td class="l">${x.flightIndex + 1}</td>
        <td class="l">${clockAt(meta.startUtc, x.ts)}</td>
        <td class="l">${outcomePill(x.outcome)}${x.borderline ? ' <span class="pill">borderline</span>' : ""}</td>
        <td>${nf(x.stoppedS, 1)}</td>
        <td>${nf(x.offFoilS, 1)}</td>
        <td>${x.minKn === null ? "—" : nf(x.minKn, 2)}</td>
        <td class="dim">${yn(x.pumped)}</td>
        <td class="dim">${yn(x.submerged)}</td>
        <td class="dim">${nf(x.windowS, 0)}</td>
        <td class="l dim">${x.ownedByTurn === null ? "–" : `turn ${x.ownedByTurn + 1}`}</td>
      </tr>`).join("")}</tbody>`;
}
