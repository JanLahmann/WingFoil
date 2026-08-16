/* Drawing primitives shared by the figures: the palette, the SVG helpers, the marker
 * vocabulary, the number formatters and the hover tooltip.
 *
 * This module was carved out of js/render.js when the session view became interactive
 * (js/session.js draws the map and the speed strip now, js/render.js the tiles and the
 * tables) — both halves have to speak the same visual language, and neither may own it.
 * Nothing here knows what a session is; it places shapes and formats numbers.
 *
 * The encoding, unchanged since the first version:
 *
 *   line colour   off-foil = recessive grey, foiling = series-1 blue
 *   marker SHAPE  carries the outcome (disc / triangle / heavy X / hairline x / hollow square)
 *   marker colour only reinforces it — the status ramp fails a CVD check on its own
 *   marker number is the turn's row number in the Turns table
 *
 * The presentation *values* are not written here: they come from js/tokens.js, generated
 * from design/tokens.json, which is also where the iOS app's EventMarkerStyle gets them
 * (docs/presentation.md "Enforcement"). `C` maps those tokens onto this app's role names,
 * so nothing downstream has to know a token from a literal.
 */

import { TOKENS } from "./tokens.js";

export const C = {
  track: TOKENS.phase.offFoil.hex, foil: TOKENS.phase.flying.hex, tint: "#7fb0e8",
  good: TOKENS.outcome.flew.hex, warn: TOKENS.outcome.touchdown.hex,
  bad: TOKENS.outcome.fellIn.hex, reject: TOKENS.outcome.courseChange.hex,
  ink: "#ffffff", ink2: TOKENS.direction.ink.hex, ink3: "#8a8a80",
  surface: "#1a1a19", grid: "#333331",
  // The three layers that are about effort and water rather than about an outcome. They
  // are deliberately outside the green/amber/red ladder (same reasoning as the iOS app's
  // EventMarkerStyle): nothing here is a verdict, so borrowing the verdict palette would
  // make a takeoff look like a good jibe.
  pump: TOKENS.effort.pumping.hex, takeoff: TOKENS.effort.takeoff.hex,
  splash: TOKENS.effort.splash.hex,
  // The one exception, and it earns it: a failed attempt is the single event in those
  // layers with an outcome, so it alone borrows the ladder's red.
  failedTakeoff: TOKENS.effort.failedTakeoff.hex,
};

export const OUTCOME_COLOR = { flew_through: C.good, touchdown: C.warn, fell_in: C.bad,
                               glide_out: C.ink2, unknown: C.ink3 };
export const OUTCOME_LABEL = { flew_through: "flew through", touchdown: "touched down",
                               fell_in: "fell in", glide_out: "glided out",
                               unknown: "no evidence" };

/* ---------------------------------------------------------------- formatting */

export const nf = (v, d = 1) =>
  (v === null || v === undefined || Number.isNaN(v) ? "—" : v.toFixed(d));
export const int = (v) =>
  (v === null || v === undefined ? "—" : Math.round(v).toLocaleString("en-US"));

export function hms(sec) {
  if (sec === null || sec === undefined) return "—";
  const s = Math.round(sec);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`
           : `${m}:${String(r).padStart(2, "0")}`;
}

export function clockAt(startUtc, t) {
  if (!startUtc) return hms(t);
  const d = new Date(new Date(startUtc).getTime() + t * 1000);
  return d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

export function sessionDate(startUtc) {
  if (!startUtc) return "Session";
  return new Date(startUtc).toLocaleString("en-GB",
    { weekday: "short", year: "numeric", month: "short", day: "numeric",
      hour: "2-digit", minute: "2-digit" });
}

export const esc = (s) => String(s).replace(/[&<>"]/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

/* -------------------------------------------------------------- svg helpers */

export const SVGNS = "http://www.w3.org/2000/svg";

/**
 * The user-unit width to draw a figure at.
 *
 * Every figure is `width: 100%` over a viewBox, so the viewBox width sets the scale factor
 * between user units and CSS pixels. Drawing a 1100-unit chart into a 350 px column scales
 * everything by 0.32 — a 10.5 px axis label lands at 3.3 px and the figure is decoration,
 * not data. So the viewBox is the container's real width: scale 1, type at its stated size,
 * on a phone and on a desktop alike. Clamped so a freak container cannot produce a
 * degenerate chart, and rounded so the numbers in the markup stay readable.
 */
export function figureWidth(host, { min = 300, max = 1100 } = {}) {
  const w = host?.clientWidth || host?.parentElement?.clientWidth || max;
  return Math.round(Math.max(min, Math.min(max, w)));
}

/** Below this the figures switch to their compact geometry (paddings, gutters, ticks). */
export const isNarrow = (w) => w < 640;

export function svg(tag, attrs = {}, parent = null) {
  const node = document.createElementNS(SVGNS, tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v !== null && v !== undefined) node.setAttribute(k, v);
  }
  if (parent) parent.appendChild(node);
  return node;
}

/** The marker shapes, drawn centred on (0,0) and translated into place. */
export function marker(parent, kind, x, y, scale = 1) {
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
    // Takeoffs and splashes are glyphs, not dots, so they can never be mistaken for an
    // outcome at a glance on a busy track (the iOS app makes the same split). A *pumped*
    // takeoff is the filled "this cost something" arrow; `free` is hollow.
    case "arrow-up":
      svg("circle", { r: 5.2, fill: color, stroke: C.surface, "stroke-width": 1.1 }, g);
      svg("path", { d: "M0,-3 L0,3 M-2.4,-0.6 L0,-3 L2.4,-0.6", stroke: C.surface,
                    "stroke-width": 1.5, fill: "none", "stroke-linecap": "round",
                    "stroke-linejoin": "round" }, g);
      break;
    case "arrow-up-hollow":
      svg("circle", { r: 5.2, fill: C.surface, stroke: color, "stroke-width": 1.6 }, g);
      svg("path", { d: "M0,-3 L0,3 M-2.4,-0.6 L0,-3 L2.4,-0.6", stroke: color,
                    "stroke-width": 1.5, fill: "none", "stroke-linecap": "round",
                    "stroke-linejoin": "round" }, g);
      break;
    // A *failed* attempt turns the arrow around: it is the only mark in the takeoff layer
    // that did not end in a flight, so the u-turn says "went at it and came back down" at
    // any zoom, hollow says nothing came of it, and red says it on a third channel.
    case "uturn":
      svg("circle", { r: 5.2, fill: C.surface, stroke: color, "stroke-width": 1.6 }, g);
      svg("path", { d: "M-2.4,2.6 L-2.4,-0.6 A2.4,2.4 0 0 1 2.4,-0.6 L2.4,2.2",
                    stroke: color, "stroke-width": 1.5, fill: "none",
                    "stroke-linecap": "round" }, g);
      svg("path", { d: "M0.6,1.1 L2.4,2.9 L4.1,1.1", stroke: color, "stroke-width": 1.5,
                    fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round" }, g);
      break;
    case "drop":
      svg("path", { d: "M0,-5 C2.6,-1.6 4,-0.2 4,1.6 A4,4 0 0 1 -4,1.6 C-4,-0.2 -2.6,-1.6 0,-5 Z",
                    fill: color, stroke: C.surface, "stroke-width": 1 }, g);
      break;
  }
  return g;
}

/** Marker style for a turn: bear-aways/round-ups are not manoeuvres, so they stay a
 *  recessive hairline whatever their outcome was (same rule as plot_turns.py). */
export const turnStyle = (m) => (m.maneuver
  ? { shape: { flew_through: "disc", touchdown: "triangle", fell_in: "cross" }[m.outcome] || "disc",
      color: OUTCOME_COLOR[m.outcome] || C.reject }
  : { shape: "hairline", color: C.reject });

export const endStyle = (e) => ({ shape: "square", color: OUTCOME_COLOR[e.outcome] || C.ink3 });

export function label(parent, x, y, n, color, up) {
  const t = svg("text", {
    x: x.toFixed(2), y: (y + (up ? -9 : 15)).toFixed(2), "text-anchor": "middle",
    "font-size": 10, "font-weight": 700, fill: color,
    stroke: C.surface, "stroke-width": 2.6, "paint-order": "stroke",
    "stroke-linejoin": "round",
  }, parent);
  t.textContent = String(n);
  return t;
}

/** A legend swatch: the marker shape at chip size, as markup. */
export function glyphSwatch(shape, color) {
  const holder = document.createElementNS(SVGNS, "svg");
  holder.setAttribute("viewBox", "-8 -8 16 16");
  marker(holder, { shape, color }, 0, 0);
  return holder.outerHTML;
}

export const lineSwatch = (color, width = 2.4, dash = null) =>
  `<svg viewBox="-8 -8 16 16"><line x1="-7" y1="0" x2="7" y2="0" stroke="${color}"
    stroke-width="${width}" stroke-linecap="round"${
      dash ? ` stroke-dasharray="${dash}"` : ""}/></svg>`;

export const bandSwatch = (color, opacity = 0.22) =>
  `<svg viewBox="-8 -8 16 16"><rect x="-7" y="-6" width="14" height="12"
    fill="${color}" opacity="${opacity}"/></svg>`;

/* ------------------------------------------------------------------- tooltip */

let tipEl = null;
function tip() {
  if (!tipEl) {
    tipEl = document.createElement("div");
    tipEl.className = "tip";
    document.body.appendChild(tipEl);
  }
  return tipEl;
}

export function showTip(ev, html) {
  const t = tip();
  t.innerHTML = html;
  t.classList.add("on");
  const pad = 14;
  const r = t.getBoundingClientRect();
  let x = ev.clientX + pad, y = ev.clientY + pad;
  if (x + r.width > window.innerWidth - 8) x = ev.clientX - r.width - pad;
  if (y + r.height > window.innerHeight - 8) y = ev.clientY - r.height - pad;
  t.style.left = `${x}px`;
  t.style.top = `${y}px`;
}

export const hideTip = () => tipEl && tipEl.classList.remove("on");

export function tipTarget(node, html) {
  node.style.cursor = "pointer";
  // Hover only: on a touch device the same gesture opens the popover, and a tooltip that
  // sticks after a tap is the classic phone bug.
  node.addEventListener("pointerenter", (ev) => { if (ev.pointerType === "mouse") showTip(ev, html); });
  node.addEventListener("pointermove", (ev) => { if (ev.pointerType === "mouse") showTip(ev, html); });
  node.addEventListener("pointerleave", hideTip);
}
