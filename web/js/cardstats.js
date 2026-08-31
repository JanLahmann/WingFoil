/* What a share card says — resolved once, as strings, with no DOM and no canvas.
 *
 * This module is the web twin of `ios/WingFoilKit/…/Presentation/ShareCard.swift`, and it
 * exists for the same reason that file does: **a card is an image**. Once a PNG is in a
 * WhatsApp group there is no optional binding left to fall back on, no re-render, and no
 * correction — so every "—", every rounding and every label has to be decided *before* a
 * pixel is drawn, in a function a test can call.
 *
 * **The stats ARE the key-metrics block.** They are not a second vocabulary. `keyMetricEntries`
 * is the one list, and `keyMetrics` in js/render.js now draws its HTML from it rather than
 * building the strings a second time — so the block a rider reads at the top of the page and
 * the card they post are literally the same array, in the same order, with the same words.
 * A preset can only ever *drop* entries (`LEAN_KEYS`); nothing on a card is computed here
 * that is not in the block. `web/tools/verify_presentation.py` §5 pins that, per fixture, by
 * parsing the rendered block back out of the HTML and comparing it to `cardStats`.
 *
 * Drawing lives in js/sharecard.js. Nothing here knows what a canvas is.
 */

import { int, nf } from "./viz.js";

/* -------------------------------------------------------------------- branding
 *
 * ONE place. The card's footer is the only surface of this project that travels to people
 * who have never heard of it, and the address has already moved once — a literal repeated
 * across a renderer and a dialog would mean a card already out in the world as a PNG
 * pointing somewhere the site no longer is.
 *
 * Divergence from iOS, deliberate and recorded in docs/presentation.md: `Branding.credit`
 * over there still reads "WingFoil · cleanjibe.org", the old app name. The web app *is*
 * CleanJibe (both page shells, the manifest and the service worker were renamed in v14), so
 * a card exported from the browser says CleanJibe.
 *
 * And the footer is a *call to action*, not a credit line: the card is how a rider's friends
 * find out the analyzer exists, so the line has to say what the site does, in one line, at
 * the size a chat thumbnail gives it. The QR beside it is the same offer for someone looking
 * at the picture on somebody else's phone.
 */
export const BRANDING = {
  /** The site, as it is written on the card. */
  name: "CleanJibe",
  /** No scheme: a card is read, not clicked, and "https://" is four characters of noise. */
  site: "cleanjibe.org",
  /** The offer, in the fewest words that still say what happens if you go there. */
  cta: "analyze your wingfoil sessions free",
  /** What the QR resolves to — the same address, as something a camera can open. */
  url: "https://cleanjibe.org",
};

/** "analyze your wingfoil sessions free — cleanjibe.org", built rather than repeated. */
BRANDING.line = `${BRANDING.cta} — ${BRANDING.site}`;

/* --------------------------------------------------------------- shapes/presets */

/**
 * Aspect of the exported image — the iOS pixel sizes exactly, because a card posted from
 * the phone and a card posted from the browser are the same artefact.
 *
 * `wide` is asked rather than the case tested, so a fourth aspect lands in the right layout
 * for free (same rule as `ShareCardStats.Shape.isWide`).
 */
export const SHAPES = {
  portrait: { id: "portrait", label: "Portrait", w: 1080, h: 1350 },
  square: { id: "square", label: "Square", w: 1080, h: 1080 },
  landscape: { id: "landscape", label: "Landscape", w: 1920, h: 1080 },
};

export const SHAPE_ORDER = ["portrait", "square", "landscape"];

export const isWide = (shape) => SHAPES[shape].w > SHAPES[shape].h;

/**
 * How much of the block the card carries. Two, not a checklist of eight: the rider is
 * choosing between "a clean picture with the headline on it" and "the session, fully
 * reported", and every finer distinction is a decision taken at the moment they least want
 * to take one.
 */
export const PRESETS = {
  complete: { id: "complete", label: "Complete",
              summary: "Everything the key-metrics block shows." },
  lean: { id: "lean", label: "Lean",
          summary: "Duration, distance, max 2 s and the jibe tally." },
};

export const PRESET_ORDER = ["complete", "lean"];

/**
 * What `lean` keeps — the four a rider quotes walking off the water.
 *
 * Held as *keys* rather than as a rebuilt list, so the preset cannot invent an entry:
 * anything `keyMetricEntries` did not produce is simply never there to be kept. Identical
 * to `ShareCardStats.Preset.leanKeys`.
 */
export const LEAN_KEYS = new Set(["duration", "distance", "max2s", "tally"]);

/* ---------------------------------------------------------------- the entries */

/** `1:57` — hours and minutes, which is how long a session is talked about. Rounded to the
 *  nearest minute, not truncated: `0:00` over a recording that exists reads as a failure to
 *  measure. Twin of `KeyMetrics.hoursMinutes`. */
export function hm(sec) {
  if (sec === null || sec === undefined) return "—";
  const m = Math.max(0, Math.round(sec / 60));
  return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")}`;
}

/**
 * The KEY METRICS block as data — the single list both the page and the card read.
 *
 * Every rule the two platforms have to agree on lives here, and its Swift twin
 * (`KeyMetrics.swift`) is pinned by `PresentationTests.keyMetrics*`. A difference between
 * the two is a bug.
 *
 * Each entry:
 *
 *   key     stable id — the `KeyMetrics.Metric.key` values, plus `tally`, which is not a
 *           metric because its three counts stay counts (they wear the ladder's inks)
 *   label   exactly the words printed under the number on the page. The tally's carries its
 *           own caption after an em-dash separator (`CAPTION_SEP`); the card splits there
 *           to get two lines, which is layout, not content.
 *   value   the display string, "—" included. The tally's spells its three counts out, so a
 *           renderer that ignores `tally` still prints the truth — just in one colour.
 *   tally   set only on the outcome cell: `{flewThrough, touchdown, fellIn}`
 *   row     which line of the block the entry sits on (the page draws four rows; the card
 *           ignores this and flows a grid)
 *   hero    the one entry the block gives its largest type to
 */
export function keyMetricEntries(g) {
  const s = g.summary, t = s.turns, rec = g.records;

  // Goldens serialize a non-qualifying record as 0.0 where the Swift model uses nil; both
  // mean "no window of that length exists", and neither may print as a speed.
  const best2s = rec.best2sKn >= 0.05 ? `${nf(rec.best2sKn, 2)} kn` : "—";
  // Every other speed in either app is knots, so the one summary number the engine reports
  // in km/h is converted rather than set beside a column of them.
  const avg = s.avgSpeedKmh === null || s.avgSpeedKmh === undefined
    ? "—" : `${nf(s.avgSpeedKmh / 1.852, 2)} kn`;

  // Jibes are what the rider asked for and what JPH counts a row below, so the tally has
  // to be about the same turns. A session whose wind axis never resolved has no jibes at
  // all, and an empty ladder over an afternoon of turns would read as "nothing happened" —
  // so it falls back to every counted turn, the same way the rate row falls back to TPH.
  // The caption says which, so the three numbers can never be read as the other set.
  const tally = t.jibes > 0 ? { o: t.jibeOutcomes, of: `of ${t.jibes} jibes` }
    : (t.turnsCounted > 0 ? { o: t.outcomes, of: `of ${t.turnsCounted} turns` } : null);

  const out = [
    { key: "duration", label: "duration", value: hm(s.durationS), row: 0 },
    { key: "distance", label: "distance", value: `${nf(s.distanceKm, 1)} km`, row: 0 },
    { key: "avgSpeed", label: "avg speed", value: avg, row: 0 },
    // The session's fastest measured window, alone on its line and in the block's largest
    // type: it is the number a rider quotes, and the label names the window rather than
    // letting "max" imply a peak sample (docs/presentation.md, "Record windows").
    { key: "max2s", label: "max 2 s", value: best2s, row: 1, hero: true },
  ];

  if (tally) {
    const o = tally.o;
    out.push({
      key: "tally",
      label: `flew · touchdown · fell${CAPTION_SEP}${tally.of}`,
      value: `${int(o.flewThrough)} · ${int(o.touchdown)} · ${int(o.fellIn)}`,
      tally: { flewThrough: o.flewThrough, touchdown: o.touchdown, fellIn: o.fellIn },
      row: 2,
    });
  }
  if (t.turnsCounted > 0) {
    out.push({ key: "streaks", label: "best streaks",
               value: `${int(t.longestDryStreak)} dry · ${int(t.longestFlewStreak)} flew`,
               row: 2 });
  }

  // `durationS <= 0` makes the engine report all four rates as null: there is no hour to
  // divide by, which is an absence and never a flattering 0.0. The row disappears.
  if (s.wetPerHour !== null && s.wetPerHour !== undefined) {
    out.push((s.jibesPerHour > 0 || !(s.turnsPerHour > 0))
      ? { key: "jph", label: "JPH · dry jibes per hour", value: nf(s.jibesPerHour, 1), row: 3 }
      : { key: "tph", label: "TPH · turns per hour", value: nf(s.turnsPerHour, 1), row: 3 });
    out.push({ key: "wph", label: "WPH · swims per hour", value: nf(s.wetPerHour, 1), row: 3 });
  }

  return out;
}

/** The em-dash the tally's label uses to hang its caption off the words. The card splits
 *  the label here to get the two lines iOS lays out as `label` + `caption`; nothing else
 *  in the block contains it, which is what makes the split safe. */
export const CAPTION_SEP = " — ";

/**
 * The card's stat list: the block, filtered by the preset. Nothing else.
 *
 * There is deliberately no way to *add* a cell — no flight count, no foil percentage, no
 * longest flight. Those live in the tiles below the block, and a card that printed them
 * would be a second, quieter answer to "was that a good session" travelling in a picture
 * next to the loud one. (iOS gives its clip *outro* a ninth longest-flight cell; the
 * exported card there does not get it either, and neither does this one.)
 */
export function cardStats(g, preset = "complete") {
  const entries = keyMetricEntries(g);
  return preset === "lean" ? entries.filter((e) => LEAN_KEYS.has(e.key)) : entries;
}

/* --------------------------------------------------------------- the identity */

/**
 * A readable session name out of the original filename — the port of
 * `SessionDisplay.title` (iOS), so the two platforms name the same recording the same way.
 *
 * `2026-08-07-0754_nago-torbole-windsurfen_ciq.fit` → `Nago Torbole Windsurfen`: the
 * middle underscore-part, hyphens to spaces, every all-digit word dropped, each word
 * capitalised.
 *
 * The one divergence from the Swift original, and it is one character of rule: iOS drops a
 * numeric word only when it is four digits or more (the year). That is exactly right for
 * files named the way the app names them — `…_nago-torbole-windsurfen_ciq.fit` has no
 * digits in the part that gets used — and wrong for anything else. The bundled example is
 * `example-nago-torbole-2026-08-30.fit`, which has no underscore at all, so the whole stem
 * is the name and iOS's rule yields "Example Nago Torbole 08 30" — a date, half-eaten,
 * printed 75 px high on the card most likely to be somebody's first sight of this project.
 * A number in a session filename is a date or a clock; a spot is words. So all of them go.
 */
export function cardTitle(fileName) {
  let stem = String(fileName || "").replace(/\.[^./\\]+$/, "");
  const parts = stem.split("_");
  if (parts.length >= 2) stem = parts[1];
  const words = stem.replace(/-/g, " ").split(" ")
    .filter((w) => w && !/^\d+$/.test(w));
  if (!words.length) return "Session";
  return words.map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");
}

/** `7 August 2026`, in the reader's own timezone — the same line `ShareCardStats.dateLine`
 *  writes. Fixed to en-GB so a card exported anywhere spells the month the same way. */
export function cardDateLine(startUtc) {
  if (!startUtc) return "";
  return new Date(startUtc).toLocaleDateString("en-GB",
    { day: "numeric", month: "long", year: "numeric" });
}

/** Set when the session's records cannot be certified, so the card cannot be read as a
 *  speed claim it has no right to make (`meta.sourceClass === "c"` — a degraded source). */
export function cardDisclaimer(meta) {
  return meta?.sourceClass === "c" ? "Speeds from a degraded source — uncertified" : null;
}

/* ------------------------------------------------------------------- the store
 *
 * The rider's last shape and preset, per device — so the second card comes out the way the
 * first one did. Both reads and both writes are wrapped: `localStorage` throws outright in
 * a Safari private window and in a page opened from file://, and a share dialog that cannot
 * open because a preference could not be read would be the worst possible trade.
 */

const LS_SHAPE = "wingfoil.shareCard.shape.v1";
const LS_PRESET = "wingfoil.shareCard.preset.v1";

/** An unreadable or unknown stored value falls back to the defaults: portrait (the shape a
 *  feed and a chat both show whole) and complete (the numbers are the point of the card). */
export function loadCardChoice() {
  let shape = null, preset = null;
  try {
    shape = localStorage.getItem(LS_SHAPE);
    preset = localStorage.getItem(LS_PRESET);
  } catch { /* no storage: the defaults are perfectly good */ }
  return {
    shape: SHAPES[shape] ? shape : "portrait",
    preset: PRESETS[preset] ? preset : "complete",
  };
}

export function saveCardChoice({ shape, preset }) {
  try {
    localStorage.setItem(LS_SHAPE, shape);
    localStorage.setItem(LS_PRESET, preset);
  } catch { /* nothing to do about it, and nothing worth telling the rider */ }
}
