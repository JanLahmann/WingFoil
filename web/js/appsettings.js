/* The handful of choices this browser remembers, and the one number they change.
 *
 * Small on purpose, and separate from js/appshell.js on purpose: the library rows, the
 * records table and the Settings page all read the unit, and a settings module that also
 * owned the shell would make the library import the router to print a speed.
 *
 * Everything here is `localStorage` and nothing here is analysis. The engine reports knots
 * because the speedsurfing windows are defined in knots (docs/algorithms.md); this converts
 * that one number on the way to the screen and never on the way into a record.
 */

const LS_UNITS = "cleanjibe.units";
const LS_WELCOME = "cleanjibe.welcomeSeen.v1";
const LS_GEAR = "cleanjibe.gear.v1";
const LS_DETAIL = "cleanjibe.detail.v1";

/** Knots per km/h. One constant, so no caller multiplies by a number it typed. */
const KMH_PER_KN = 1.852;

const listeners = new Set();

function read(key, fallback) {
  try {
    return localStorage.getItem(key) ?? fallback;
  } catch {
    // A locked-down private window. The app works, it just forgets.
    return fallback;
  }
}

function write(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch { /* nothing to do, and nothing worth breaking the page over */ }
}

/** `"kn"` or `"kmh"`. Knots is the default because the records are defined in them. */
export function units() {
  return read(LS_UNITS, "kn") === "kmh" ? "kmh" : "kn";
}

export function setUnits(value) {
  write(LS_UNITS, value === "kmh" ? "kmh" : "kn");
  for (const fn of listeners) fn();
}

/** Called whenever a stored choice changes, so a list already on screen can redraw. */
export function onSettingsChange(fn) {
  listeners.add(fn);
}

/** The unit's own word, for the cell beside the number. */
export function speedUnit() {
  return units() === "kmh" ? "km/h" : "kn";
}

/** A speed the engine reported in knots, in the unit this browser reads. */
export function speedValue(kn) {
  if (kn === null || kn === undefined || Number.isNaN(kn)) return null;
  return units() === "kmh" ? kn * KMH_PER_KN : kn;
}

/** "13.25 kn" / "24.54 km/h", or "—" where the session has no answer. */
export function speed(kn, digits = 2) {
  const value = speedValue(kn);
  if (value === null) return "—";
  return `${value.toFixed(digits)} ${speedUnit()}`;
}

/* --------------------------------------------------------------- how much to say */

/**
 * `"concise"` or `"extensive"`, site-wide, and **concise is the default**.
 *
 * Jan, 20 September 2026, from his phone: *"/app/#/help is way too long"*, *"/app/#/settings
 * is way too long, do we need all this?"*, *"parts of /app/#/session are too long"*. The
 * answer is not to delete the explanations — a rider meeting *CPH* or a turn verdict for
 * the first time needs them — it is to let him say how much he wants, once, and have every
 * surface obey (js/explain.js).
 *
 * Concise: one line per explanation, plus a `?` into the help topic that carries the rest.
 * Extensive: that same `?` stays, and the help topic's own body is drawn under the line,
 * read from the catalogue at render time so there is never a second copy of it
 * (docs/review-checklist.md, pattern F).
 */
export function detail() {
  return read(LS_DETAIL, "concise") === "extensive" ? "extensive" : "concise";
}

export function setDetail(value) {
  write(LS_DETAIL, value === "extensive" ? "extensive" : "concise");
  for (const fn of listeners) fn();
}

/* ------------------------------------------------------------------- first open */

export function welcomeSeen() {
  return read(LS_WELCOME, "") === "1";
}

export function markWelcomeSeen() {
  write(LS_WELCOME, "1");
}

/* ------------------------------------------------------------------------ gear */

/**
 * The gear a session was ridden on, as a name per session id.
 *
 * The phone keeps wings, boards and foils as rows of their own with a history behind each
 * (ios/WingFoil/Features/Gear). This is the honest small version of that: one name, typed
 * on the session, rolled up on the Gear tab. Stored here rather than in the session's
 * analysis document, because the document is the engine's output and a rider's note is not.
 */
export function gearMap() {
  try {
    return JSON.parse(read(LS_GEAR, "{}")) || {};
  } catch {
    return {};
  }
}

export function gearFor(id) {
  return gearMap()[id] || "";
}

export function setGearFor(id, name) {
  const map = gearMap();
  const clean = String(name || "").trim();
  if (clean) map[id] = clean;
  else delete map[id];
  write(LS_GEAR, JSON.stringify(map));
  for (const fn of listeners) fn();
}

/** Everything this browser remembers about the reader, forgotten. The library itself is
 *  wiped by the caller — it lives in OPFS or IndexedDB, not here. */
export function forgetSettings() {
  // The two intervals.icu keys are js/icu.js's own (`LS_KEY`, `LS_ATHLETE`) and are named
  // here rather than imported: a start-over that forgot to forget the key would leave the
  // one piece of the reader's account behind, and a cross-import for two strings is worse
  // than two strings. Keep them in step with js/icu.js.
  for (const key of [LS_UNITS, LS_WELCOME, LS_GEAR, LS_DETAIL,
                     "wingfoil.icu.key", "wingfoil.icu.athlete",
                     "cleanjibe.install.dismissed"]) {
    try {
      localStorage.removeItem(key);
    } catch { /* see `write` */ }
  }
}
