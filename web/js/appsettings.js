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
const LS_SPEED_RECORDS = "cleanjibe.speedRecords.v1";

/** km/h per knot. One constant, so no caller multiplies by a number it typed. Exported
 *  because the engine reports exactly one number — the session's average — in km/h, and the
 *  block that prints it beside a column of knots has to convert it somewhere. Twin of
 *  `SpeedUnit.kmhPerKnot` in the kit. */
export const KMH_PER_KN = 1.852;

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

/**
 * **The two words a speed can end in, and the only place either is spelled.**
 *
 * `SpeedUnit.suffix` in the kit, and the same two strings the picker's labels are built
 * from. A `kn` typed anywhere else is a cell that cannot follow the setting.
 */
export const UNIT_SUFFIX = { kn: "kn", kmh: "km/h" };

/** The knots word on its own, for the one surface that is knots whatever the setting says:
 *  a chart whose y domain was scaled in Python (js/trends.js, `chartUnit`). */
export const KNOTS = UNIT_SUFFIX.kn;

/** The unit's own word, for the cell beside the number. */
export function speedUnit() {
  return UNIT_SUFFIX[units()];
}

/** A speed the engine reported in knots, in the unit this browser reads. */
export function speedValue(kn) {
  if (kn === null || kn === undefined || Number.isNaN(kn)) return null;
  return units() === "kmh" ? kn * KMH_PER_KN : kn;
}

/** "13.25 kn" / "24.54 km/h", or "—" where the session has no answer.
 *
 *  **Every speed a rider reads on this site comes out of here** — the key-metrics block,
 *  the share card, the tiles, the library rows, the records table, the turn page and the
 *  watch-vs-phone rows. The kit's `Speed.format` is its twin, and `verify_glossary.py`
 *  scans for a second formatter: a `kn` typed into a template literal is a cell that keeps
 *  saying knots to a rider who switched to km/h. */
export function speed(kn, digits = 2) {
  const value = speedValue(kn);
  if (value === null) return "—";
  return `${value.toFixed(digits)} ${speedUnit()}`;
}

/** The number alone, in the unit this browser reads, for a cell that carries its unit in a
 *  column or a `<small>` of its own (the tiles, the records table). `Speed.number` in the
 *  kit. */
export function speedNumber(kn, digits = 2) {
  const value = speedValue(kn);
  return value === null ? "—" : value.toFixed(digits);
}

/* ------------------------------------------------------------- unverified records */

/**
 * **Whether a record from a track that never measured a speed may stand.**
 *
 * The browser's half of Settings → Speed records (Jan, 22 September 2026). The three
 * values are spelled exactly as the kit spells them (`SpeedRecordPolicy`), because the
 * phone and this browser have to mean the same thing by them and a second vocabulary is
 * the drift the shared copy exists to stop.
 *
 * The *rule* is not here. It is one function in Python (`library.eligible`), applied at
 * aggregate time over the stored digests, which is what lets a reader change his mind and
 * see the other answer without re-saving anything. This module only remembers the choice.
 */
export const SPEED_RECORD_POLICIES = ["onlyVerified", "preferVerified",
                                      "includeUnverified"];

/** `"preferVerified"` until the reader says otherwise, the kit's default. */
export function speedRecords() {
  const stored = read(LS_SPEED_RECORDS, "");
  return SPEED_RECORD_POLICIES.includes(stored) ? stored : "preferVerified";
}

export function setSpeedRecords(value) {
  write(LS_SPEED_RECORDS,
        SPEED_RECORD_POLICIES.includes(value) ? value : "preferVerified");
  for (const fn of listeners) fn();
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
  for (const key of [LS_UNITS, LS_WELCOME, LS_GEAR, LS_DETAIL, LS_SPEED_RECORDS,
                     "wingfoil.icu.key", "wingfoil.icu.athlete",
                     "cleanjibe.install.dismissed"]) {
    try {
      localStorage.removeItem(key);
    } catch { /* see `write` */ }
  }
}
