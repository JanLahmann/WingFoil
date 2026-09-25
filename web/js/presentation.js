/* The presentation document, as the browser reads it (ADR-033, docs/presentation/document.md).
 *
 * The engine emits every rider-facing FACT of one session once — the block, the card, the
 * records, the legend, the turn strip, the marks, the callouts, the banner — and a surface
 * becomes a *renderer*: it formats, lays out, and decides nothing else. This module is the
 * browser's half of that contract, and it is the JavaScript twin of the kit's
 * `PresentationCopy` + the formatting half of `KeyMetrics`.
 *
 * Three rules the document keeps, and all three land here:
 *
 *   1. **No rider sentence is in it.** Every word is an *id* plus the arguments the
 *      sentence interpolates. `text()` below resolves the four namespaces and there are no
 *      others — `presentation.*` from docs/copy/presentation.json (through js/appcopy.js),
 *      `glossary.*` from docs/copy/glossary.json (through js/copy.js), `tokens.*` from
 *      design/tokens.json (through js/tokens.js) and `verdicts.notASession.*`.
 *   2. **No formatted number is in it.** A value is raw and carries a `unitKind`;
 *      `format()` puts it through `js/appsettings.js`, which is where Settings → Units
 *      lives. That is the whole point: one document serves a rider reading knots and a
 *      rider reading km/h, and the two cannot end up with different records.
 *   3. **No colour value is in it.** A cell carries a `colourRole`; js/tokens.js resolves
 *      it. Nothing here knows a hex.
 *
 * Nothing in this file derives a fact. If a renderer needs a number the document does not
 * carry, it goes into lab/src/wingfoil_lab/presentation.py, not into here.
 */

import { speed } from "./appsettings.js";
import { PRESENTATION } from "./appcopy.js";
import { GLOSSARY, NOT_A_SESSION } from "./copy.js";
import { TOKENS } from "./tokens.js";
import { int, nf } from "./viz.js";

/* ------------------------------------------------------------------- the lookups */

const GLOSSARY_BY_ID = Object.fromEntries(GLOSSARY.map((e) => [e.id, e]));
const RECORD_WINDOW_LABEL =
  Object.fromEntries(TOKENS.recordWindows.order.map((w) => [w.id, w.label]));
const LAYER_LABEL = Object.fromEntries(TOKENS.layers.map((l) => [l.id, l.label]));

/**
 * Which spelling of a glossary word a cell wants — `PresentationCopy.GlossaryForm`.
 *
 * The glossary holds one word in four lengths and the cell that prints it decides which:
 * the rate row prints `JPH · dry jibes per hour`, the falls cell prints `fell in`, the
 * streaks pair prints `flew`. That is a typographic decision, which the document leaves
 * with the renderer; what may never differ is the word itself, and all four come from one
 * entry.
 */
export const FORM = { term: "term", lowercased: "lowercased", labelled: "labelled",
                      short: "short" };

function glossaryText(entry, form) {
  if (!entry) return null;
  switch (form) {
    case FORM.lowercased: return entry.term.toLowerCase();
    case FORM.short: return entry.short;
    case FORM.labelled:
      return entry.expansion ? `${entry.term} · ${entry.expansion}` : entry.term;
    default: return entry.term;
  }
}

/* -------------------------------------------------------------- resolving an id */

/** The sentence (or the pair of forms) a `presentation.<group>.<key>` id names. */
function line(group, key) {
  const value = PRESENTATION[group]?.[key];
  return value === undefined ? null : value;
}

/** Which argument decides a caption's singular form — named per caption rather than
 *  guessed from the argument order, because an object has none. */
function countingArgument(id) {
  switch (id) {
    case "presentation.caption.ofTacks": return "tacks";
    case "presentation.caption.ofTurns": return "turns";
    case "presentation.caption.ofJibes": return "jibes";
    default: return null;
  }
}

/** `{placeholder}` substitution, with the singular form where the caption has one. */
function interpolate(value, args, count) {
  let out = typeof value === "string"
    ? value
    : (count === 1 ? (value.one ?? value.other) : value.other);
  for (const [key, replacement] of Object.entries(args)) {
    out = out.split(`{${key}}`).join(replacement);
  }
  return out;
}

/**
 * One id, resolved into the words a rider reads — the twin of `PresentationCopy.text`.
 *
 * Returns `null` for an id with no home, which is a label a rider would read as an empty
 * space; `verify_presentation.py` fails on one.
 */
export function text(id, args = {}, form = FORM.term) {
  const parts = String(id || "").split(".");
  if (parts.length < 2) return null;
  switch (parts[0]) {
    case "presentation": {
      if (parts.length !== 3) return null;
      const value = line(parts[1], parts[2]);
      return value === null ? null : interpolate(value, args, Number(args._count));
    }
    case "glossary":
      return parts.length === 2 ? glossaryText(GLOSSARY_BY_ID[parts[1]], form) ?? null : null;
    case "tokens":
      if (parts.length !== 3) return null;
      if (parts[1] === "recordWindow") return RECORD_WINDOW_LABEL[parts[2]] ?? null;
      if (parts[1] === "layer") return LAYER_LABEL[parts[2]] ?? null;
      return null;
    case "verdicts": {
      if (parts[1] !== "notASession") return null;
      if (parts[2] === "tag") return NOT_A_SESSION.tag;
      if (parts.length !== 4 || parts[2] !== "lines") return null;
      const index = Number(parts[3]);
      return NOT_A_SESSION.lines[index] ?? null;
    }
    default:
      return null;
  }
}

/** A document value as the digits a sentence prints. Whole numbers lose the `.0` the JSON
 *  spells them with: the document rounds for determinism, the sentence prints. */
export function plain(value) {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") {
    return Number.isInteger(value) ? String(value) : String(value);
  }
  return String(value);
}

/**
 * A caption cell — `{id, args}` — as its sentence.
 *
 * Three rules, and they are the whole of it (`PresentationCopy.arguments`): a number is
 * printed plainly; an argument named `<name>Id` is itself an id and fills the `{<name>}`
 * the sentence spells; the plural form follows the caption's own counting argument.
 */
export function captionText(caption) {
  if (!caption || !caption.id) return null;
  const args = {};
  for (const [key, value] of Object.entries(caption.args || {})) {
    if (key.endsWith("Id") && typeof value === "string") {
      args[key.slice(0, -2)] = text(`presentation.turnKind.${value}`) ?? value;
    } else {
      args[key] = plain(value);
    }
  }
  const counting = countingArgument(caption.id);
  if (counting !== null && typeof caption.args?.[counting] === "number") {
    args._count = caption.args[counting];
  }
  return text(caption.id, args);
}

/* --------------------------------------------------------------- formatting a value */

/**
 * `1:57 h` past an hour, `10:45 min` under one — the block's duration rule.
 *
 * **Why the short form exists.** The block was `h:mm` at every length, so a ten minute
 * forty-five second session printed `0:11` — the two most interesting digits rounded away.
 * That is survivable on a page the rider can scroll past; it is not survivable on the share
 * card, which is a PNG in somebody else's chat thread with no re-render and nothing beside
 * it to check against.
 *
 * **Why the unit rides inside the value.** Every other cell carries its own unit in the big
 * type — `2.6 km`, `13.47 kn` — and `10:45` under the word "duration" reads as ten and
 * three quarter *hours* just as easily as minutes. Twin of `KeyMetrics.duration`.
 */
export function hm(sec) {
  if (sec === null || sec === undefined) return "—";
  const total = Math.max(0, Math.round(sec));
  if (total >= 3600) {
    const m = Math.round(total / 60);
    return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")} h`;
  }
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")} min`;
}

/**
 * The session list's spelling of the same clock: `58 min` under an hour, `1:57 h` from one
 * up, seconds under a minute. The row puts it after the date on one line, and `57:38`
 * there wrapped on a phone (Jan, F7f). Twin of `KeyMetrics.listDuration`.
 */
export function listDuration(sec) {
  if (sec === null || sec === undefined) return "—";
  const total = Math.max(0, Math.round(sec));
  if (total >= 3600) return hm(sec);
  if (total < 60) return `${total} s`;
  return `${Math.min(59, Math.round(total / 60))} min`;
}

/**
 * The document's raw value in the unit the rider reads. The one place a `unitKind` becomes
 * a string on this surface — `KeyMetrics.format` is its twin.
 */
export function format(value, unitKind) {
  if (value === null || value === undefined) return "—";
  switch (unitKind) {
    case "durationS": return hm(value);
    case "distanceKm": return `${nf(value, 1)} km`;
    case "speedKn": return speed(value);
    case "rate": return nf(value, 1);
    case "percent": return nf(value, 1);
    default: return int(value);
  }
}

/**
 * **The record cells that mean "no window of that length exists" by a zero.**
 *
 * The Swift model carries nil there and the document carries `null`; the *analysis
 * goldens* serialize the same absence as `0.0`, and a browser reads a stored document
 * written from one. Both mean the same thing and neither may print as a speed, so the
 * three cells whose value IS a record window take a floor. `avgSpeed` deliberately does
 * not: a measured average of zero is a measurement.
 */
const RECORD_CELLS = new Set(["max2s", "best5x10s", "alpha500"]);

const absentRecord = (cell) =>
  RECORD_CELLS.has(cell.key) && typeof cell.value === "number" && cell.value < 0.05;

/* -------------------------------------------------------------------------- a cell */

/** Which glossary spelling a cell's own label wants. Only two cells name one: the rates,
 *  which want the expansion under them, and the falls cell, which does not. */
const cellForm = (key) =>
  (["jph", "cph", "tph", "wph"].includes(key) ? FORM.labelled : FORM.lowercased);

/** The word under a cell's number, with no caption on it. */
export const cellLabel = (cell) => text(cell.labelId, {}, cellForm(cell.key)) ?? "";

/** The small line under a cell — the falls split, the tally's "of 55 jibes · 12 clean" —
 *  or null where the cell has nothing to qualify. */
export const cellCaption = (cell) =>
  ((cell.captions || []).length ? captionText(cell.captions[0]) : null);

/**
 * A cell's value, formatted.
 *
 * A cell with `counts` is the pair — "5 flew · 11 dry", where the two halves are two
 * *different* metrics rather than three rungs of one — and each half takes the glossary's
 * watch-width `short`. Everything else is one scalar in the unit its `unitKind` names, and
 * `null` is the em dash: an absent answer, never a zero.
 */
export function cellValue(cell) {
  if (cell.counts && cell.counts.length) {
    return cell.counts
      .map((part) => `${plain(part.value)} ${text(part.labelId, {}, FORM.short) ?? ""}`)
      .join(" · ");
  }
  if (cell.tally) {
    const t = cell.tally;
    return `${int(t.flewThrough)} · ${int(t.touchdown)} · ${int(t.fellIn)}`;
  }
  return absentRecord(cell) ? "—" : format(cell.value, cell.unitKind);
}
