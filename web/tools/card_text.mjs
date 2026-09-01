/* The rider's own two lines on the share card — dumped as JSON for
 * `verify_presentation.py` §5b to assert against.
 *
 * Everything below is content, not drawing: what a typed title and a typed caption become
 * before a pixel exists, where they are remembered, and the one piece of the card's geometry
 * that now depends on them (the header is fourteen points taller when there is a caption, and
 * exactly as tall as it always was when there is not).
 *
 * The dialog itself cannot be driven from here — it is a `<dialog>` with a canvas in it, and
 * `verify_library.py` tests the Python library rather than any DOM. So what is proved instead
 * is everything the dialog *calls*: the normalizers, the per-session key, the localStorage
 * round trip, the header height, and the resolution of a typed title against the derived one.
 * A stubbed `localStorage` is the whole environment they need.
 *
 * Run from the repo root, with the analysis goldens as arguments (the first is used to build
 * one real `cardContent`):
 *
 *     node web/tools/card_text.mjs fixtures/goldens/*.expected.json
 */

import { readFileSync } from "node:fs";

globalThis.window = { addEventListener() {} };

/** A `localStorage` with the two behaviours that matter: it remembers, and it can be made to
 *  throw — which is what a Safari private window and a `file://` page both do, and the reason
 *  every read and write in js/cardstats.js is wrapped. */
const store = new Map();
let throwing = false;
globalThis.localStorage = {
  getItem(k) {
    if (throwing) throw new Error("storage disabled");
    return store.has(k) ? store.get(k) : null;
  },
  setItem(k, v) {
    if (throwing) throw new Error("storage disabled");
    store.set(k, String(v));
  },
  removeItem(k) { store.delete(k); },
};

const JS = new URL("../js/", import.meta.url);
const cs = await import(new URL("cardstats.js", JS).href);
const cm = await import(new URL("cardmap.js", JS).href);
const { cardContent, headerHeight } = await import(new URL("sharecard.js", JS).href);

/* ------------------------------------------------------------------ normalizing */

const NOTE_CASES = [
  "  cold and glassy  ",
  "",
  "   ",
  "cold and glassy\nfinally got the tack",
  "a\r\n\r\nb",
  "wind ".repeat(40),
  "y".repeat(300),
];

const TITLE_CASES = ["  Torbole  ", "", "\t \n", "First  20 kn", "a".repeat(100)];

/* ------------------------------------------------------------- the derived name
 *
 * What a dropped file is called before anybody types anything — including the correction the
 * name needs, since the watch that wrote the file has no wingfoil profile and names every
 * session after the windsurf one, in its own locale. */

const DERIVED_CASES = [
  "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit",   // a German Fenix, via the app
  "i123_nago-torbole-windsurfen_icu.fit",              // the same, synced from intervals.icu
  "2026-08-30-1407_nago-torbole-windsurfing_native.fit",
  "2026-08-30-1407_windsurf_native.fit",               // the bare profile name
  "example-nago-torbole-2026-08-30.fit",               // no underscore: the whole stem
  "windsurfschule-torbole.fit",                        // standalone only — not a substring
  "2026-08-30-1407__ciq.fit",                          // nothing left to name it with
  "",
];

/* ------------------------------------------------------------------------ keys */

const KEY_CASES = [
  { meta: { startUtc: "2026-08-30T12:07:00+00:00", durationS: 5000.4 },
    file: { name: "a.fit" } },
  // No `durationS`, but the timer time the digest falls back to.
  { meta: { startUtc: "2026-08-30T12:07:00+00:00", timerTimeS: 120 },
    file: { name: "b.fit" } },
  // A recording that cannot say when it started: the filename is all there is.
  { meta: {}, file: { name: "no-clock.fit" } },
  { file: {} },
];

/* ------------------------------------------------------------------- the prefill
 *
 * What the title field opens *containing*. A placeholder is not a prefill — it vanishes on the
 * first keystroke — so the value the dialog writes into the field is its own rule, and this is
 * it. `[remembered, fileName]` in, the field's opening text out. */

const DRAFT_CASES = [
  ["", "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit"],   // nothing typed here before
  ["  First 20 kn  ", "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit"],
  ["   ", "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit"], // remembered whitespace is nothing
  [null, "2026-08-30-1407_nago-torbole_ciq.fit"],
  [undefined, ""],                                           // no file, no name to derive
];

/* ---------------------------------------------------------------- the round trip */

function roundTrip() {
  store.clear();
  const out = {};
  out.emptyBeforeAnythingIsWritten = cs.loadCardText("s1-2");

  cs.saveCardText("s1-2", { title: "  First 20 kn  ", note: "cold and glassy\nat last" });
  out.afterWriting = cs.loadCardText("s1-2");
  // Normalized on the way IN, so what comes back needs no second pass.
  out.storedRaw = JSON.parse(store.get("wingfoil.shareCard.text.v1"))["s1-2"];

  // A different session is a different entry; nothing bleeds across.
  cs.saveCardText("s9-9", { title: "Другое", note: "" });
  out.otherSession = cs.loadCardText("s9-9");
  out.firstStillThere = cs.loadCardText("s1-2");

  // Both cleared removes the entry rather than storing two empty strings.
  cs.saveCardText("s1-2", { title: "  ", note: "" });
  out.afterClearing = cs.loadCardText("s1-2");
  out.keysAfterClearing = Object.keys(JSON.parse(store.get("wingfoil.shareCard.text.v1")));

  // The map is bounded. 60 sessions in, the oldest are gone and the newest are not.
  store.clear();
  for (let i = 0; i < 60; i++) cs.saveCardText(`s${i}`, { title: `t${i}`, note: "" });
  const kept = Object.keys(JSON.parse(store.get("wingfoil.shareCard.text.v1")));
  out.boundedTo = kept.length;
  out.oldestStillThere = kept.includes("s0");
  out.newestStillThere = kept.includes("s59");

  // Opening the dialog on a session nobody has titled prefills the field and writes nothing:
  // the prefill is a convenience for the typing, never a title the rider is recorded as having
  // given. Only a keystroke writes.
  store.clear();
  const key = "s-prefill";
  const opened = cs.cardTitleDraft(cs.loadCardText(key).title,
                                   "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit");
  out.prefillOnAnUntitledSession = opened;
  out.prefillWroteNothing = store.get("wingfoil.shareCard.text.v1") === undefined;

  // Somebody else's JSON under our key, and an outright hostile value: both read as "nothing
  // remembered" rather than throwing on the way into a dialog the rider asked to open.
  store.set("wingfoil.shareCard.text.v1", "[1,2,3]");
  out.arrayUnderTheKey = cs.loadCardText("s1-2");
  store.set("wingfoil.shareCard.text.v1", "{not json");
  out.garbageUnderTheKey = cs.loadCardText("s1-2");

  // No storage at all. Reading gives the empty pair; writing is a silent no-op.
  throwing = true;
  out.withoutStorage = cs.loadCardText("s1-2");
  let threw = false;
  try { cs.saveCardText("s1-2", { title: "x", note: "y" }); } catch { threw = true; }
  out.writeThrewWithoutStorage = threw;
  throwing = false;
  return out;
}

/* ------------------------------------------------------------- the map switch
 *
 * The rider's habit, per device — the same store the shape and the preset live in, one key
 * wider. What is proved here is mostly one thing: **the map is off** unless somebody wrote
 * exactly the value this switch writes. It is the only control on the card that reaches the
 * network, so an absent key, a foreign key, a truthy-looking string and a browser with no
 * storage at all must every one of them come back false.
 */

function choiceRoundTrip() {
  store.clear();
  const out = {};
  out.defaultsBeforeAnythingIsWritten = cs.loadCardChoice();

  cs.saveCardChoice({ shape: "landscape", preset: "lean", map: true });
  out.afterTurningOn = cs.loadCardChoice();
  out.storedOn = store.get("wingfoil.shareCard.map.v1");
  cs.saveCardChoice({ shape: "landscape", preset: "lean", map: false });
  out.afterTurningOff = cs.loadCardChoice();
  out.storedOff = store.get("wingfoil.shareCard.map.v1");

  // Anything that is not this switch's own "1" is off. `"true"` is the one worth naming: it
  // is what a hand-edited value or another implementation would most plausibly put there.
  store.set("wingfoil.shareCard.map.v1", "true");
  out.foreignTruthyValue = cs.loadCardChoice().map;
  store.set("wingfoil.shareCard.map.v1", "{not json");
  out.garbageValue = cs.loadCardChoice().map;
  store.delete?.("wingfoil.shareCard.map.v1");

  // No storage at all: the defaults, and a write that is a silent no-op.
  store.clear();
  throwing = true;
  out.withoutStorage = cs.loadCardChoice();
  let threw = false;
  try {
    cs.saveCardChoice({ shape: "square", preset: "lean", map: true });
  } catch { threw = true; }
  out.writeThrewWithoutStorage = threw;
  throwing = false;
  store.clear();
  return out;
}

/* --------------------------------------------------------------- the projection
 *
 * The map background's whole promise, as two numbers a test can hold: the breadcrumb is
 * placed through **Web Mercator** rather than through the card's own fit, and the framing is
 * chosen so the ride still lands in exactly the box the layout gave it. Both halves are pure
 * functions in js/cardmap.js — nothing below fetches a tile or touches a canvas.
 */

/** A box roughly the size the portrait card's track slot gets, in layout points. */
const TRACK_BOX = { x: 16, y: 64, w: 328, h: 250 };
const TRACK_INSET = 7.2;
/** Lake Garda, about the extent of the bundled example session. */
const SPOT = { min: { lat: 45.860, lon: 10.869 }, max: { lat: 45.869, lon: 10.877 } };

function projection() {
  const frame = cm.frameTrack({ ...SPOT, box: TRACK_BOX, inset: TRACK_INSET });
  const corner = (lat, lon) => {
    const p = cm.placeOn(frame, lat, lon);
    return [Number(p.x.toFixed(4)), Number(p.y.toFixed(4))];
  };
  return {
    // The world square, at the three points every Mercator implementation agrees on.
    world: [cm.worldPoint(0, 0), cm.worldPoint(0, -180), cm.worldPoint(0, 180)],
    // Torbole, to six places, against a second implementation of the same formula.
    spot: cm.worldPoint(45.8647, 10.8751),
    // The two corners of the ride, on the card. One axis binds and lands on the inset box's
    // own edges; the other is centred in what is left. Which one binds depends on the shape
    // of the session against the shape of the box, and the assertion is written not to care.
    northWest: corner(SPOT.max.lat, SPOT.min.lon),
    southEast: corner(SPOT.min.lat, SPOT.max.lon),
    box: TRACK_BOX,
    inset: TRACK_INSET,
  };
}

/* ----------------------------------------------------------------- the geometry */

const golden = JSON.parse(readFileSync(process.argv[2], "utf8"));
const result = { golden, file: { name: "2026-08-30-1407_nago-torbole_ciq.fit" },
                 meta: { startUtc: "2026-08-30T12:07:00+00:00", utcOffsetS: 7200 } };

const plain = cardContent(result, "complete");
const named = cardContent(result, "complete",
                          { title: "  First 20 kn  ", note: "  cold and glassy  " });
const cleared = cardContent(result, "complete", { title: "   ", note: "   " });

process.stdout.write(JSON.stringify({
  limits: { note: cs.NOTE_LIMIT, title: cs.TITLE_LIMIT },
  notes: NOTE_CASES.map((raw) => [raw, cs.cleanNote(raw)]),
  titles: TITLE_CASES.map((raw) => [raw, cs.cleanTitle(raw)]),
  derived: DERIVED_CASES.map((name) => [name, cs.cardTitle(name)]),
  sport: cs.SPORT,
  drafts: DRAFT_CASES.map(([remembered, name]) =>
    [remembered ?? null, name, cs.cardTitleDraft(remembered, name)]),
  keys: KEY_CASES.map((r) => cs.cardKey(r)),
  storage: roundTrip(),
  choice: choiceRoundTrip(),
  projection: projection(),
  credit: cm.CREDIT,
  header: { plain: headerHeight(plain), named: headerHeight(named),
            cleared: headerHeight(cleared) },
  content: {
    plain: { title: plain.title, note: plain.note },
    named: { title: named.title, note: named.note },
    cleared: { title: cleared.title, note: cleared.note },
    // The caption may not touch the stats. Same list, same order, same strings.
    statsUnchanged: JSON.stringify(named.stats) === JSON.stringify(plain.stats),
    disclaimerUnchanged: named.disclaimer === plain.disclaimer,
    dateUnchanged: named.dateLine === plain.dateLine,
    // The map background is a *drawing* option, not content: `cardContent` does not take it
    // and has nowhere to put it, which is why turning it on cannot move a number. What the
    // content does carry is the key back to the globe, and only when the document has one.
    geoWithoutAView: plain.geo,
    geoFromTheView: cardContent(
      { ...result, view: { geo: { lat: 45.86, lon: 10.87, x: 1, y: 2 } } }, "complete").geo,
  },
}));
