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
 * `card.tiles` *are* the `block` cells minus the two composites. There is nothing here to
 * reword, reorder or invent one with, and nothing on a card is computed that is not in the
 * block. Since layout B v2 (26 Sep 2026) the card lays them out as a story — a hero, the
 * outcome bars, the streak line and a ribbon — and the Lean/Complete presets are gone.
 * `fixtures/presentation/*.expected.json` pins the values themselves, once, for both
 * platforms.
 *
 * Drawing lives in js/sharecard.js. Nothing here knows what a canvas is.
 */

import { FORM, cellCaption, cellLabel, cellValue, hm, text } from "./presentation.js";
import { PRESENTATION } from "./appcopy.js";
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

/** The tagline (Jan, 23 Sep 2026) — the line under "CleanJibe · cleanjibe.org" in the card's
 *  footer since layout B v2. `Branding.tagline` in the kit. */
BRANDING.tagline = "Your WingFoil session, measured.";

/** "analyze your wingfoil sessions free — cleanjibe.org", built rather than repeated. */
BRANDING.line = `${BRANDING.cta} — ${BRANDING.site}`;

/* ---------------------------------------------------------------------- shapes */

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
 *           in the block and on the card
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
 * The card's stat list: the block's tiles. Nothing else.
 *
 * There is deliberately no way to *add* a cell — no flight count, no foil percentage, no
 * longest flight. Those live in the tiles below the block, and a card that printed them
 * would be a second, quieter answer to "was that a good session" travelling in a picture
 * next to the loud one. (iOS gives its clip *outro* a ninth longest-flight cell; the
 * exported card there does not get it either, and neither does this one.)
 */
export function cardStats(doc) {
  // **The document's own tiles**, which *are* the block's cells minus the two composites:
  // there is nothing here to reword, reorder or invent one with.
  return (doc?.card?.tiles || []).map((tile) => entry(tile, 0));
}

/* ------------------------------------------------------------ layout B v2
 *
 * The session card tells the jibe story (Jan, 26 Sep 2026): a hero number, the jibe
 * outcome bar, a tack bar when the session had tacks, the best streak, and one ribbon of
 * rates in words plus max 2 s, duration and distance. Every number is still a tile of
 * `card.tiles` — `cardStats(doc)`, which verify_presentation §5 holds to the
 * block — and what this adds is the rider's choice of hero and the card's own words
 * (`presentation.card.*`, authored by the kit's `PresentationCopy.card`).
 *
 * The twin of `ShareCardStats.Story.make` in the kit. Both are pinned against one fixture,
 * fixtures/cards/stories.expected.json, by card_parity.mjs and DocumentRendererTests.
 */

/** The card's own words, with the singular form where `count` is 1. */
export const cardWord = (key, args = {}, count) =>
  text(`presentation.card.${key}`, count === undefined ? args : { ...args, _count: count })
  ?? "";

/** The numbers a card can be headlined with, in picker order. Clean jibes is the default.
 *  `sessions` is the period card's alone, and a period card never offers `tacks`. */
export const HEROES = {
  clean: { id: "clean", label: cardWord("optionClean") },
  max2s: { id: "max2s", label: cardWord("optionMax2s") },
  tacks: { id: "tacks", label: cardWord("optionTacks") },
  sessions: { id: "sessions", label: cardWord("optionSessions") },
};
/** The session card's heroes, and the fallback order. */
export const HERO_ORDER = ["clean", "max2s", "tacks"];
/** The period card's heroes, and the fallback order. */
export const PERIOD_HERO_ORDER = ["clean", "max2s", "sessions"];

/** The flew / touchdown / fell words the bars' legend prints, from the glossary. */
const legendWords = () => ["flewThrough", "touchdown", "fellIn"]
  .map((id) => text(`glossary.${id}`, {}, FORM.lowercased) ?? "");

/** "13.21 kn" → ["13.21", "kn"]: the hero draws the number big and the unit beside it. */
const splitUnit = (value) => {
  const i = String(value).lastIndexOf(" ");
  return i < 0 ? [String(value), ""] : [value.slice(0, i), value.slice(i + 1)];
};

/** "fell in 25 times", with the number in the fell-in ink. */
function fallSegments(count) {
  if (count === 0) return [{ text: cardWord("fellInNone"), role: "muted" }];
  const line = PRESENTATION.card.fellIn;
  const template = typeof line === "string" ? line
    : (count === 1 ? (line.one ?? line.other) : line.other);
  const halves = template.split("{falls}");
  if (halves.length !== 2) return [{ text: template, role: "muted" }];
  return [{ text: halves[0], role: "muted" }, { text: String(count), role: "fell" },
          { text: halves[1], role: "muted" }].filter((s) => s.text);
}

/**
 * Everything layout B v2 prints about one session, as strings and counts.
 *
 * `wanted` is the rider's hero; the card falls back when the session cannot carry it —
 * clean jibes → best 2 s → tacks → none. With 0 clean jibes the clean number is left out
 * everywhere (Jan, 26 Sep 2026): no "★ 0", no "0 clean", no 0.0 clean jibes an hour.
 * `speedNote` is the positions-only disclaimer, kept only where a speed is on the card.
 */
export function cardStory(doc, wanted = "clean", { dateLine = "", speedNote = null } = {}) {
  const by = Object.fromEntries(cardStats(doc).map((e) => [e.key, e]));
  const tiles = Object.fromEntries((doc?.card?.tiles || []).map((t) => [t.key, t]));
  const jibesCounted = Boolean(tiles.cleanJibes);
  const cleanN = Number(tiles.cleanJibes?.value);
  const clean = jibesCounted && cleanN > 0 ? cleanN : null;
  const speed = by.max2s && by.max2s.value !== "—" ? by.max2s : null;
  const tacks = tiles.tacks?.tally || null;
  const sum = (t) => t.flewThrough + t.touchdown + t.fellIn;

  const heroOptions = [];
  if (clean !== null) heroOptions.push("clean");
  if (speed) heroOptions.push("max2s");
  if (tacks) heroOptions.push("tacks");
  const kind = heroOptions.includes(wanted) ? wanted : (heroOptions[0] ?? null);

  const tally = tiles.tally?.tally || null;
  const jibes = tally ? sum(tally) : 0;
  const jibePhrase = cardWord("jibeCount", { jibes: String(jibes) }, jibes);
  const ofJibes = text("presentation.caption.ofJibes", { jibes: String(jibes), _count: jibes });

  let hero = null;
  if (kind === "clean") {
    hero = { kind, value: String(clean), unit: cardWord("heroClean", {}, clean), sub: ofJibes };
  } else if (kind === "max2s") {
    const [value, unit] = splitUnit(speed.value);
    hero = { kind, value, unit, sub: cardWord("heroMax2s") };
  } else if (kind === "tacks") {
    const n = sum(tacks), dry = String(tacks.flewThrough + tacks.touchdown);
    hero = { kind, value: String(n), unit: cardWord("heroTacks", {}, n),
             sub: jibesCounted && jibes > 0
               ? cardWord("heroTacksBeside", { dry, jibes: jibePhrase })
               : cardWord("heroTacksDry", { dry }) };
  }

  const bars = [];
  if (tally) {
    let right = null, star = false;
    if (!jibesCounted) right = cellCaption(tiles.tally);
    else if (kind === "clean") right = null;
    else if (clean !== null) {
      right = `${ofJibes} · ${cardWord("barClean", { clean: String(clean) })}`;
      star = true;
    } else right = ofJibes;
    bars.push({ kind: jibesCounted ? "jibes" : "turns",
                label: cardWord(jibesCounted ? "barJibes" : "barTurns"),
                flewThrough: tally.flewThrough, touchdown: tally.touchdown,
                fellIn: tally.fellIn, right, star });
  }
  if (tacks) {
    bars.push({ kind: "tacks", label: cardWord("barTacks"),
                flewThrough: tacks.flewThrough, touchdown: tacks.touchdown,
                fellIn: tacks.fellIn,
                right: kind === "tacks" ? null : cellCaption(tiles.tacks), star: false });
  }

  const streak = [];
  const parts = by.streaks?.parts || [];
  if (parts.length) {
    streak.push({ text: `${cardWord("streak")} `, role: "muted" });
    parts.forEach((part, i) => {
      if (i) streak.push({ text: " · ", role: "muted" });
      streak.push({ text: String(part.value),
                    role: part.colourRole === "outcome.flew" ? "flew" : "paper" });
      streak.push({ text: ` ${part.label}`, role: "muted" });
    });
  }
  const fallsN = tiles.falls ? Number(tiles.falls.value) : NaN;
  const falls = Number.isInteger(fallsN) ? fallSegments(fallsN) : [];

  const ribbon = [];
  if (clean !== null && by.cph) {
    ribbon.push({ key: "cph", label: cardWord("rateCph"), value: by.cph.value, clean: true });
  }
  if (by.tph) ribbon.push({ key: "tph", label: cardWord("rateTph"), value: by.tph.value, clean: false });
  else if (by.jph) ribbon.push({ key: "jph", label: cardWord("rateJph"), value: by.jph.value, clean: false });
  if (speed && kind !== "max2s") {
    ribbon.push({ key: "max2s", label: speed.label, value: speed.value, clean: false });
  }
  for (const key of ["duration", "distance"]) {
    if (by[key]) ribbon.push({ key, label: by[key].label, value: by[key].value, clean: false });
  }

  return { dateLine, hero, heroOptions, bars, streak, falls, ribbon,
           speedNote: speed ? speedNote : null, legend: legendWords() };
}

/* ------------------------------------------------------------ the period card
 *
 * The second card kind, and the same card: three shapes, one footer, layout B v2, the
 * rider's title and caption. What differs is what is being described — a week rather than
 * an afternoon — so the numbers are the aggregate block `library.period_block` produced,
 * the story facts beside it are `library.period_card`'s, and the date line is the span.
 *
 * Nothing here computes a number. `period.block` arrives from Python as `{key, label,
 * value}` strings and `period.card` as counts and one rate string; this file chooses the
 * hero and puts the card's own words around them.
 */

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

/** The card's numbers for a period: the block, verbatim. Nothing else — and, as on the
 *  session card, deliberately no way to *add* one. */
export function periodCardStats(period) {
  return (period?.block || []).map((e) => ({ key: e.key, label: e.label, value: e.value }));
}

/**
 * **The period card's story** — layout B v2 for a trip, a month, a season or a range. The
 * twin of `ShareCardStats.Story.make(period:hero:)` in the kit; both are pinned against
 * fixtures/cards/period-stories.expected.json.
 *
 * Heroes: clean jibes → best 2 s → sessions. The one outcome bar is the jibe bar only when
 * every counted turn of the period was a jibe (`card.dryKind`), the turn bar otherwise —
 * a stored row carries no tack ladder to draw a tack bar from. With 0 clean jibes the clean
 * number and clean jibes / h are left out, as on the session card.
 */
export function periodCardStory(period, wanted = "clean") {
  const block = Object.fromEntries((period?.block || []).map((e) => [e.key, e]));
  const card = period?.card || {};
  const cleanN = Number(block.cleanJibes?.value);
  const clean = block.cleanJibes && cleanN > 0 ? cleanN : null;
  const speed = block.best2s || null;

  const heroOptions = [];
  if (clean !== null) heroOptions.push("clean");
  if (speed) heroOptions.push("max2s");
  if ((period?.sessions || 0) > 0) heroOptions.push("sessions");
  const kind = heroOptions.includes(wanted) ? wanted : (heroOptions[0] ?? null);

  const jibes = card.jibes ?? 0;
  const ofJibes = text("presentation.caption.ofJibes", { jibes: String(jibes), _count: jibes });
  let hero = null;
  if (kind === "clean") {
    hero = { kind, value: String(clean), unit: cardWord("heroClean", {}, clean), sub: ofJibes };
  } else if (kind === "max2s") {
    const [value, unit] = splitUnit(speed.value);
    hero = { kind, value, unit, sub: cardWord("heroMax2s") };
  } else if (kind === "sessions") {
    const spots = block.spots?.value ?? "1";
    hero = { kind, value: String(period.sessions),
             unit: cardWord("heroSessions", {}, period.sessions),
             sub: cardWord("heroSessionsSpots", { spots }, Number(spots)) };
  }

  const bars = [];
  const o = card.outcomes;
  const total = o ? o.flewThrough + o.touchdown + o.fellIn : 0;
  if (o && total > 0) {
    const isJibes = card.dryKind === "jibes";
    let right = isJibes
      ? (kind === "clean" ? null : ofJibes)
      : text("presentation.caption.ofTurns", { turns: String(total), _count: total });
    let star = false;
    if (kind !== "clean" && clean !== null) {
      right = `${right ?? ""} · ${cardWord("barClean", { clean: String(clean) })}`;
      star = true;
    }
    bars.push({ kind: isJibes ? "jibes" : "turns",
                label: cardWord(isJibes ? "barJibes" : "barTurns"),
                flewThrough: o.flewThrough, touchdown: o.touchdown, fellIn: o.fellIn,
                right, star });
  }

  const streak = [];
  const parts = [[card.flewStreak, "glossary.flewThrough", "flew"],
                 [card.dryStreak, "glossary.dry", "paper"]]
    .filter(([value]) => value !== null && value !== undefined);
  if (parts.length) {
    streak.push({ text: `${cardWord("streak")} `, role: "muted" });
    parts.forEach(([value, id, role], i) => {
      if (i) streak.push({ text: " · ", role: "muted" });
      streak.push({ text: String(value), role });
      streak.push({ text: ` ${text(id, {}, FORM.short) ?? ""}`, role: "muted" });
    });
  }
  const falls = Number.isInteger(card.falls) ? fallSegments(card.falls) : [];

  const ribbon = [];
  if (clean !== null && block.cph) {
    ribbon.push({ key: "cph", label: cardWord("rateCph"), value: block.cph.value, clean: true });
  }
  if (card.dryRate) {
    const jibesOnly = card.dryKind === "jibes";
    ribbon.push({ key: jibesOnly ? "jph" : "tph",
                  label: cardWord(jibesOnly ? "rateJph" : "rateTph"),
                  value: card.dryRate, clean: false });
  }
  if (kind !== "sessions" && block.sessions) {
    ribbon.push({ key: "sessions", label: block.sessions.label, value: block.sessions.value,
                  clean: false });
  }
  if (block.hours) {
    ribbon.push({ key: "hours", label: cardWord("ribbonHours"), value: block.hours.value,
                  clean: false });
  }
  if (block.distance) {
    ribbon.push({ key: "distance", label: block.distance.label, value: block.distance.value,
                  clean: false });
  }

  return { dateLine: period?.dateLine || "", hero, heroOptions, bars, streak, falls, ribbon,
           speedNote: null, legend: legendWords() };
}

/** Everything a period card prints. `tracks` are the outlines to stack behind it — the
 *  period's own sessions, drawn faint on one another (see js/sharecard.js).
 *
 *  No disclaimer: the speed one is a claim about a single recording's speed channel, and
 *  marking a whole holiday because one afternoon came from a GPX would answer a question
 *  nobody asked. */
export function periodCardContent(period, hero, text = {}, tracks = []) {
  return {
    title: cleanTitle(text.title) || period.title,
    dateLine: period.dateLine,
    note: cleanNote(text.note) || null,
    stats: periodCardStats(period),
    story: periodCardStory(period, HEROES[hero] ? hero : "clean"),
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

/** `29 August 2026 · 14:40` — the date line and the start time, on the session's own clock:
 *  the session card's header since layout B v2 (`ShareCardStats.startLine` in the kit). */
export function cardStartLine(meta) {
  const day = cardDateLine(meta);
  if (!day) return "";
  const time = zonedFormat(meta.startUtc, meta.utcOffsetS,
    { hour: "2-digit", minute: "2-digit", hour12: false });
  return `${day} · ${time}`;
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
  return certified ? null : cardWord("speedEstimated");
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
 * That is the same promise `loadCardChoice` makes about the shape and the hero, one scope
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
 * The rider's last shape, hero and map switch, per device — so the second card comes out the way the
 * first one did. Both reads and both writes are wrapped: `localStorage` throws outright in
 * a Safari private window and in a page opened from file://, and a share dialog that cannot
 * open because a preference could not be read would be the worst possible trade.
 */

const LS_SHAPE = "wingfoil.shareCard.shape.v1";
/** The map background, per device — the rider's habit, like the shape and the hero.
 *
 * **Off unless the stored value is exactly `"1"`.** Nothing else counts: an absent key, a
 * key somebody else wrote, a storage that throws — all of them are a plain card, which is
 * the card this project has always exported and the one it must keep exporting for anybody
 * who never asks for anything else. The map costs a handful of third-party requests, and a
 * default that quietly made them would be a promise broken in the one place ("your file
 * never leaves this tab") the analyzer makes it loudest. */
const LS_MAP = "wingfoil.shareCard.map.v1";
/** The card's hero (layout B v2), per device — one habit for both card kinds. Anything but a known hero is clean
 *  jibes, the default — `ShareCardHeroStore` in the kit. */
const LS_HERO = "wingfoil.shareCard.hero.v1";

/** An unreadable or unknown stored value falls back to the defaults: portrait (the shape a
 *  feed and a chat both show whole), clean jibes and no map (the card as it has always
 *  been). */
export function loadCardChoice() {
  let shape = null, map = null, hero = null;
  try {
    shape = localStorage.getItem(LS_SHAPE);
    map = localStorage.getItem(LS_MAP);
    hero = localStorage.getItem(LS_HERO);
  } catch { /* no storage: the defaults are perfectly good */ }
  return {
    shape: SHAPES[shape] ? shape : "portrait",
    map: map === "1",
    hero: HEROES[hero] ? hero : "clean",
  };
}

export function saveCardChoice({ shape, map, hero = "clean" }) {
  try {
    localStorage.setItem(LS_SHAPE, shape);
    localStorage.setItem(LS_MAP, map ? "1" : "0");
    localStorage.setItem(LS_HERO, HEROES[hero] ? hero : "clean");
  } catch { /* nothing to do about it, and nothing worth telling the rider */ }
}
