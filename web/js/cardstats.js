/* What a share card says — resolved once, as strings, with no DOM and no canvas.
 *
 * This module is the web twin of `ios/WingFoilKit/…/Presentation/ShareCard.swift`, and it
 * exists for the same reason that file does: **a card is an image**. Once a PNG is in a
 * WhatsApp group there is no optional binding left to fall back on, no re-render, and no
 * correction — so every "—", every rounding and every label has to be decided *before* a
 * pixel is drawn, in a function a test can call.
 *
 * **The stats ARE the key-metrics block**, and since round 3 of ADR-033 that is true by
 * construction rather than by agreement: both read the presentation document, where
 * `card.tiles` *are* the `block` cells minus the two composites, each carrying the presets
 * it belongs to. A preset can only ever *drop* a tile; there is nothing here to reword,
 * reorder or invent one with, and nothing on a card is computed that is not in the block.
 * `fixtures/presentation/*.expected.json` pins the values themselves, once, for both
 * platforms.
 *
 * Drawing lives in js/sharecard.js. Nothing here knows what a canvas is.
 */

import { cellCaption, cellLabel, cellValue, hm, text } from "./presentation.js";
import { zonedFormat } from "./viz.js";

/* -------------------------------------------------------------------- branding
 *
 * ONE place. The card's footer is the only surface of this project that travels to people
 * who have never heard of it, and the address has already moved once — a literal repeated
 * across a renderer and a dialog would mean a card already out in the world as a PNG
 * pointing somewhere the site no longer is.
 *
 * There is no branding divergence from iOS any more: both platforms are CleanJibe and
 * docs/presentation.md states the footer as one shared contract — mark, wordmark, CTA, QR.
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

/* What `lean` keeps — the five a rider quotes walking off the water — is not a list here
 * any more. Each tile of `card.tiles` carries the presets it belongs to
 * (`LEAN_CARD_KEYS` in lab/src/wingfoil_lab/presentation.py, `ShareCardStats.Preset
 * .leanKeys` in the kit), so a preset cannot invent an entry and the browser cannot hold a
 * second opinion about which five they are.
 *
 * **`falls` is lean too** (20 September 2026). The tally counts *jibe* outcomes and its
 * caption says "of 55 jibes", so a card that carried only the tally reported one fall on an
 * afternoon with three in it — two of them in a straight line. A card is read next to
 * nothing, so the honest number travels on both presets. */

/* ---------------------------------------------------------------- the entries */

/** Re-exported: `hm` moved to js/presentation.js with the rest of the document's
 *  formatting, and the tiles in js/render.js still print a session duration with it. */
export { hm };

/**
 * The KEY METRICS block as data — the single list both the page and the card read.
 *
 * **It is the document's `block`, drawn** (ADR-033, round 3). Every gate that used to live
 * here — the jibe tally's fallback to the counted-turn ladder, the tack cell's two
 * conditions, the falls cell's absence where no flight ended, the rate row's `turns.jibes`
 * test and its JPH→TPH degradation — is in `build_presentation` now, once, beside the kit's
 * twin of it. What is left is formatting and the words: the three decisions this file is
 * entitled to make and the document is not (docs/presentation/document.md, "What stays with
 * the renderer"). `KeyMetrics.make(block:)` is the Swift half of exactly this function.
 *
 * Each entry:
 *
 *   key     the document cell's own `key` — stable, and the same key names the same fact
 *           in the block, on the card and in a preset's key set
 *   label   exactly the words printed under the number on the page. A cell with something
 *           to qualify carries its caption after an em-dash separator (`CAPTION_SEP`) — the
 *           two tallies' "of 55 jibes" and "of 14 tacks", and the falls cell's split; the
 *           card splits there to get two lines, which is layout, not content. iOS holds the
 *           two halves in two fields (`KeyMetrics.Metric.caption`) and joins them with the
 *           same separator.
 *   value   the display string, "—" included. The tally's spells its three counts out, so a
 *           renderer that ignores `tally` still prints the truth — just in one colour.
 *   tally   the document cell's own three counts, where it has them: they stay numbers
 *           because the ladder's inks are the point
 *   row     which line of the block the entry sits on — the document row's position, so a
 *           row the document left out takes its line with it (row 4 on a recording with no
 *           hour to divide by)
 *   hero    the one entry the block gives its largest type to
 *   blockOnly  the two composites the card drops; `card.tiles` is what says so
 */
export function keyMetricEntries(doc) {
  const rows = doc?.block?.rows || [];
  const out = [];
  rows.forEach((row, index) => {
    for (const cell of row.cells || []) out.push(entry(cell, index));
  });
  return out;
}

/** One document cell as the block draws it. `hero` and `blockOnly` are layout: which cell
 *  gets the largest type, and which two never reach a card. */
function entry(cell, row) {
  const caption = cellCaption(cell);
  return {
    key: cell.key,
    label: cellLabel(cell) + (caption ? CAPTION_SEP + caption : ""),
    value: cellValue(cell),
    ...(cell.tally ? { tally: cell.tally } : {}),
    // The ink the value wears where it is not the body's — the clean jibes' own (25 Sep
    // 2026) — and a pair cell's halves, each in its own (the streaks: flew in the ladder's
    // green). `value` still spells the whole thing, so a renderer that ignores these two
    // prints the truth in one colour.
    ...(cell.colourRole && cell.colourRole !== "neutral" ? { colourRole: cell.colourRole } : {}),
    ...(cell.counts && cell.counts.length
      ? { parts: cell.counts.map((part) => ({
          value: part.value, label: text(part.labelId, {}, "short") ?? "",
          colourRole: part.colourRole || "neutral" })) }
      : {}),
    row,
    // The session's fastest measured window, alone on its line and in the block's largest
    // type: it is the number a rider quotes (docs/presentation/records.md, "Record windows").
    ...(cell.key === "max2s" ? { hero: true } : {}),
    // The two composites beside it (6 Sep 2026 — "the second row is a bit empty"). The
    // card never carries them — one speed on a card, the one a rider quotes; the Records
    // page owns the set — and the document says so by leaving them out of `card.tiles`.
    ...(BLOCK_ONLY.has(cell.key) ? { blockOnly: true } : {}),
  };
}

/** The two cells `card.tiles` drops. Held here rather than re-derived from the tiles so
 *  the block can be drawn from `block` alone. */
const BLOCK_ONLY = new Set(["best5x10s", "alpha500"]);

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
export function cardStats(doc, preset = "complete") {
  // **The document's own tiles**, which *are* the block's cells minus the two composites,
  // each carrying the presets it belongs to. A preset can only ever drop a tile: there is
  // nothing here to reword, reorder or invent one with.
  return (doc?.card?.tiles || [])
    .filter((tile) => (tile.presets || []).includes(preset))
    .map((tile) => entry(tile, 0));
}

/* ------------------------------------------------------------ the period card
 *
 * The second card kind, and the same card: three shapes, one footer, two presets, the
 * rider's title and caption. What differs is what is being described — a week rather than
 * an afternoon — so the stats are the aggregate block `library.period_block` produced and
 * the date line is the period's span.
 *
 * Nothing here computes anything. `period.block` arrives from Python as `{key, label,
 * value}` strings, and the only thing this file is allowed to do with it is drop entries,
 * which is exactly the licence the session card's presets have.
 */

/** What the period card's `lean` preset keeps — the five a rider quotes about a holiday.
 *  Identical to `PeriodBlock.leanKeys` in the kit and `library.PERIOD_LEAN_KEYS`. */
export const PERIOD_LEAN_KEYS = new Set(["sessions", "hours", "cleanJibes", "cph", "best2s"]);

/**
 * Whether a period has a single ground worth drawing under it.
 *
 * A period is a set of afternoons and they need not have happened anywhere near one another,
 * so "which rectangle of the earth?" has no answer a card can take for granted: the union box
 * of a month split between Garda and the Rhine is mostly the motorway between them. The rule
 * is therefore the trip clusterer's own — every session in the period inside **one** 3 km spot
 * cluster, and every one of them actually placed by a fix rather than by the name its file
 * carries. `library._period` decides it, once, and hands it over as `mapGround`; nothing in
 * the browser re-derives it, because a second copy of a clustering rule is a second answer.
 *
 * False is "not offered", never "offered and inert": a switch that is on and does nothing is
 * worse than a switch that is not there.
 */
export const periodMapAvailable = (period) => Boolean(period?.mapGround);

/** The card's stat list for a period: the block, filtered by the preset. Nothing else — and,
 *  as on the session card, deliberately no way to *add* a cell. */
export function periodCardStats(period, preset = "complete") {
  const entries = (period?.block || []).map(
    (e) => ({ key: e.key, label: e.label, value: e.value }));
  return preset === "lean" ? entries.filter((e) => PERIOD_LEAN_KEYS.has(e.key)) : entries;
}

/** Everything a period card prints. `tracks` are the outlines to stack behind it — the
 *  period's own sessions, drawn faint on one another (see js/sharecard.js).
 *
 *  No disclaimer: the speed one is a claim about a single recording's speed channel, and
 *  marking a whole holiday because one afternoon came from a GPX would answer a question
 *  nobody asked. */
export function periodCardContent(period, preset, text = {}, tracks = []) {
  return {
    title: cleanTitle(text.title) || period.title,
    dateLine: period.dateLine,
    note: cleanNote(text.note) || null,
    stats: periodCardStats(period, preset),
    disclaimer: null,
    tracks,
    track: null,
    geo: null,
  };
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
 *
 * The last step is the guess's one correction — see `sportCorrected`.
 */
export function cardTitle(fileName) {
  let stem = String(fileName || "").replace(/\.[^./\\]+$/, "");
  const parts = stem.split("_");
  if (parts.length >= 2) stem = parts[1];
  const words = stem.replace(/-/g, " ").split(" ")
    .filter((w) => w && !/^\d+$/.test(w));
  if (!words.length) return "Session";
  return sportCorrected(words.map((w) => w[0].toUpperCase() + w.slice(1)).join(" "));
}

/** The sport this app is about. One word, one spelling, one place. */
export const SPORT = "Wingfoil";

/** The words a Garmin watch puts there instead, lower-cased for the comparison. Garmin has no
 *  wingfoil profile, so a session is recorded under the windsurf one (docs/fit-schema.md:
 *  sport 43 alone does not mean wingfoil) and the watch names the activity after it — in the
 *  watch's own locale, which is why the German word is on this list beside the two English
 *  ones. */
const GARMIN_SPORT_WORDS = new Set(["windsurfen", "windsurfing", "windsurf"]);

/**
 * A **derived** name with Garmin's sport word swapped for this app's — the port of
 * `SessionNaming.sportCorrected` (iOS), so the two platforms rename the same session the same
 * way.
 *
 * `Nago Torbole Windsurfen` → `Nago Torbole Wingfoil`. A file dropped on this page was written
 * by the same watch that syncs to the phone, so it arrives under the same word, and a card
 * exported from the browser must not caption a wingfoil session with somebody else's sport.
 *
 * **Display only.** The file keeps its name — the report's own header prints `result.file.name`
 * verbatim, and the download slug is built from what the card is *titled*, which is this. And a
 * title the rider typed wins over this whole function: `cardContent` prefers `cleanTitle(text)`
 * and only falls through to the derived branch.
 *
 * The word has to stand alone: `Windsurfen` becomes `Wingfoil`, `Windsurfschule` stays itself.
 * The boundary is the space `cardTitle` already split on, and the swap keeps the case of the
 * position it lands in.
 */
export function sportCorrected(derived) {
  return String(derived ?? "").split(" ")
    .map((w) => {
      if (!GARMIN_SPORT_WORDS.has(w.toLowerCase())) return w;
      return w[0] === w[0].toUpperCase() ? SPORT : SPORT.toLowerCase();
    })
    .join(" ");
}

/** `7 August 2026`, on the **session's** own clock — the same line `ShareCardStats.dateLine`
 *  writes. Fixed to en-GB so a card exported anywhere spells the month the same way, and
 *  dated by `meta.utcOffsetS` so a card exported anywhere is dated the same way too: a PNG
 *  in somebody else's chat thread has no way to correct itself, and a session that started
 *  at 00:30 in Torbole must not be published under the previous day because the exporter
 *  happened to be sitting in London. */
export function cardDateLine(meta) {
  if (!meta || !meta.startUtc) return "";
  return zonedFormat(meta.startUtc, meta.utcOffsetS,
    { day: "numeric", month: "long", year: "numeric" });
}

/** Set when the session's records cannot be certified, so the card cannot be read as a
 *  speed claim it has no right to make.
 *
 *  **The flag, not the rule.** `certified` is one line of Python (`web_entry`'s meta,
 *  `source_class != "c"`), the same line `LibraryQueries.certified` is on iOS. This used to
 *  re-derive it from `meta.sourceClass === "c"` in JavaScript, which is a second spelling
 *  of a one-line rule and one more place for it to drift. A digest written before the flag
 *  existed carries no `certified` at all, so the class is still the fallback — an absence
 *  must not certify a degraded recording by default. */
export function cardDisclaimer(meta) {
  const certified = meta?.certified ?? (meta?.sourceClass !== "c");
  return certified ? null : "Speeds from a degraded source — uncertified";
}

/* ------------------------------------------------------- what the rider calls it
 *
 * The analyzer has no rename. A page here is one file somebody dropped on a dropzone, and
 * the library stores the digest the engine produced — there is no session *record* to carry
 * a name, and inventing one would mean a second source of truth for what a session is
 * called, in the half of the project that deliberately keeps none.
 *
 * So the two fields are transient: they feed this render, and they are remembered per
 * session on this device so that re-opening the dialog does not throw the sentence away.
 * That is the same promise `loadCardChoice` makes about the shape and the preset, one scope
 * narrower — those are about the rider, these are about one afternoon.
 *
 * (iOS does have a session record, and there the title field is a *rename*: it writes to the
 * row and every surface follows. The two platforms differ here because the thing being named
 * differs, not because they disagree about what a card should say.)
 */

/** The most characters a caption may carry — `SessionNaming.noteLimit` on iOS, and the same
 *  number for the same reason: it is about what fits in the card's header on one line at a
 *  size a chat thumbnail still resolves, and a card is a PNG. */
export const NOTE_LIMIT = 80;
/** The most characters a title may carry — `SessionNaming.titleLimit`. */
export const TITLE_LIMIT = 60;

/** A typed caption as it is stored and drawn: one line, trimmed, capped, and "" for nothing.
 *  Newlines are folded to spaces rather than rejected — the only way one arrives is a paste,
 *  and a rider who pasted two lines meant both of them. */
export function cleanNote(raw) {
  return clamp(String(raw ?? "").split(/[\r\n]+/).join(" "), NOTE_LIMIT);
}

/** A typed title, same rules, its own cap. Interior spacing is left exactly as typed. */
export function cleanTitle(raw) {
  return clamp(String(raw ?? ""), TITLE_LIMIT);
}

/** Trim, cap, trim again — the second trim matters, because a cap landing mid-space would
 *  otherwise leave a caption with a trailing one, which draws as a gap before nothing. */
function clamp(text, limit) {
  const trimmed = text.trim();
  return (trimmed.length > limit ? trimmed.slice(0, limit).trim() : trimmed);
}

/**
 * A stable key for the session on screen — the twin of the Python digest's `id`
 * (`web/lab_bundle/library.py`, `_session_id`), so a document opened out of the library and
 * the same document freshly analysed remember the same title.
 *
 * The digest itself is not always to hand — a session re-opened from the library arrives as
 * an analysis document with no digest beside it — so the id is re-derived from the two facts
 * it is made of, which are both in `meta`. A recording that cannot say when it started falls
 * back to its filename, exactly as the Python does; the two need not agree on that branch's
 * spelling, because nothing but this file's own storage ever reads the result.
 */
export function cardKey(result) {
  const meta = result?.meta || {};
  const start = Date.parse(meta.startUtc || "");
  const dur = Number(meta.durationS ?? meta.timerTimeS);
  if (Number.isFinite(start) && Number.isFinite(dur)) {
    return `s${Math.floor(start / 1000)}-${Math.round(dur)}`;
  }
  return `x${String(result?.file?.name || "session").slice(0, 60)}`;
}

/** Where the per-session title and caption live: one object keyed by `cardKey`, under one
 *  key, so the whole thing is read, written and pruned in one call. */
const LS_TEXT = "wingfoil.shareCard.text.v1";
/** How many sessions' worth to keep. A rider who has captioned two hundred sessions in one
 *  browser has captioned two hundred sessions; what he has not done is want the earliest of
 *  them back, and `localStorage` is a small, shared, throwable budget. Most recently written
 *  wins, which is the only ordering the map can honestly claim. */
const TEXT_KEEP = 50;

function readText() {
  try {
    const raw = JSON.parse(localStorage.getItem(LS_TEXT) || "{}");
    return (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {};
  } catch { return {}; }        // no storage, or somebody else's JSON under our key
}

/** The remembered title and caption for one session, or a pair of empty strings.
 *
 * Empty is not "no answer" here: an empty title means the derived one, which is exactly what
 * `cardTitle` produces, so a caller can use both fields verbatim. */
export function loadCardText(key) {
  const entry = readText()[key];
  return {
    title: cleanTitle(entry?.title),
    note: cleanNote(entry?.note),
  };
}

/**
 * What the dialog's title field **opens containing** — the card's current headline, as
 * editable text. The twin of `SessionNaming.titleDraft` on iOS.
 *
 * The field used to open *empty*, with the derived name greyed out behind it as a
 * placeholder. That looks like a prefill and is not one: a placeholder vanishes on the first
 * keystroke, so a rider who wanted "Nago Torbole Wingfoil — first 20 kn" had to type all six
 * words. He is nearly always editing what the card already says, not replacing it.
 *
 * It resolves the same way the card's headline does (`cardContent`) — remembered title first,
 * derived name otherwise — because the only prefill worth editing is the one that matches
 * what he is looking at. `state.title` is deliberately *not* seeded from it: an untouched
 * field leaves the session remembering nothing, exactly as before, and only a keystroke
 * writes.
 */
export function cardTitleDraft(remembered, fileName) {
  return cleanTitle(remembered) || cardTitle(fileName);
}

/** Remember (or forget) one session's pair. Both blank removes the entry rather than storing
 *  two empty strings — a rider who cleared both fields has asked for the card he started
 *  with, and a map full of `{title: "", note: ""}` is a map of nothing. */
export function saveCardText(key, { title, note }) {
  const t = cleanTitle(title), n = cleanNote(note);
  const map = readText();
  // Deleted before it is re-inserted, so a re-edited session moves to the *end* of the
  // insertion order rather than keeping the position it had when it was first captioned.
  delete map[key];
  if (t || n) map[key] = { title: t, note: n };
  // Oldest-first eviction by that insertion order — good enough for a convenience cache, and
  // it can never evict the entry just written, which is by construction the last one.
  const keys = Object.keys(map);
  for (const stale of keys.slice(0, Math.max(0, keys.length - TEXT_KEEP))) delete map[stale];
  try {
    localStorage.setItem(LS_TEXT, JSON.stringify(map));
  } catch { /* nothing to do about it, and nothing worth telling the rider */ }
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
/** The map background, per device — the rider's habit, like the shape and the preset.
 *
 * **Off unless the stored value is exactly `"1"`.** Nothing else counts: an absent key, a
 * key somebody else wrote, a storage that throws — all of them are a plain card, which is
 * the card this project has always exported and the one it must keep exporting for anybody
 * who never asks for anything else. The map costs a handful of third-party requests, and a
 * default that quietly made them would be a promise broken in the one place ("your file
 * never leaves this tab") the analyzer makes it loudest. */
const LS_MAP = "wingfoil.shareCard.map.v1";

/** An unreadable or unknown stored value falls back to the defaults: portrait (the shape a
 *  feed and a chat both show whole), complete (the numbers are the point of the card) and no
 *  map (the card as it has always been). */
export function loadCardChoice() {
  let shape = null, preset = null, map = null;
  try {
    shape = localStorage.getItem(LS_SHAPE);
    preset = localStorage.getItem(LS_PRESET);
    map = localStorage.getItem(LS_MAP);
  } catch { /* no storage: the defaults are perfectly good */ }
  return {
    shape: SHAPES[shape] ? shape : "portrait",
    preset: PRESETS[preset] ? preset : "complete",
    map: map === "1",
  };
}

export function saveCardChoice({ shape, preset, map }) {
  try {
    localStorage.setItem(LS_SHAPE, shape);
    localStorage.setItem(LS_PRESET, preset);
    localStorage.setItem(LS_MAP, map ? "1" : "0");
  } catch { /* nothing to do about it, and nothing worth telling the rider */ }
}
