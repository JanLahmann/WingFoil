/* The range over the charts, and the two dates behind it.
 *
 * The phone's Trends screen opens on a segmented picker with three spells — 4 w, Season,
 * All (ios/WingFoil/Features/Trends/TrendsView.swift, `TrendRange`) — and its library
 * filter adds the fourth, "Custom range…", which opens two date wheels and a Done
 * (Features/Library/LibraryFilterMenu.swift, `LibraryDateRangeSheet`). The browser had
 * neither: its charts were every session it had ever been given, forever.
 *
 * The four words here are those four. Season is 1 April to 31 March, one Northern water
 * year, so a February afternoon still counts towards the winter it belongs to — the same
 * cut `TrendRange.since` makes and the same one `PeriodRules.seasonStartMonth` makes.
 *
 * WHAT IT NARROWS: the charts, and nothing else. Records are all-time on both surfaces, and
 * the sheet says so in the phone's own footer. So the range is a filter over the digests
 * the trend half of the aggregate is asked about, and the record half is asked about the
 * whole library.
 *
 * This file decides nothing about a number. It picks which afternoons the question is
 * asked of; Python answers it, as it does for every other figure on the page.
 */

import { esc } from "./render.js";
import { track } from "./track.js";

const el = (id) => document.getElementById(id);

/** The four, in the phone's order and its words. `since` is a day, `null` for all time.
 *
 *  `short` is what the SEGMENT prints where there is no room for the full name: at 400 px
 *  "Custom range…" wrapped to two lines inside a one-line control, and a control that
 *  breaks its own shape reads as a bug (docs/web-design-review.md, finding 14). The full
 *  name stays the button's accessible name and the sheet's own title. */
const RANGES = [
  { id: "fourWeeks", label: "4 w" },
  { id: "season", label: "Season" },
  { id: "all", label: "All" },
  { id: "custom", label: "Custom range…", short: "Custom…" },
];

/** The phone opens on Season, so this does (`@State private var range = TrendRange.season`). */
let chosen = "season";
let from = "";
let to = "";
let hooks = { onChange: () => {} };

const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${
  String(d.getDate()).padStart(2, "0")}`;

/** The first day the chosen spell covers, or null for all time. */
function since() {
  const now = new Date();
  if (chosen === "fourWeeks") {
    const d = new Date(now);
    d.setDate(d.getDate() - 28);
    return iso(d);
  }
  if (chosen === "season") {
    const year = now.getMonth() + 1 >= 4 ? now.getFullYear() : now.getFullYear() - 1;
    return `${year}-04-01`;
  }
  return null;
}

/** The day a stored digest belongs to: the one the rider would have written on it. */
const dayOf = (entry) =>
  String(entry.dateLocal || entry.dateUtc || entry.startUtc || "").slice(0, 10);

/** A key that changes whenever the answer would, so a memoised aggregate can be reused. */
export function rangeKey() {
  return chosen === "custom" ? `custom:${from}:${to}` : chosen;
}

/** True while the charts are showing everything the library holds. */
export const rangeIsAll = () => chosen === "all";

/**
 * The afternoons inside the chosen range, newest-first order untouched.
 *
 * A session with no date at all cannot be placed in a range, so it stays out of a narrowed
 * one and in the all-time one. Dropping it silently from both would lose it; keeping it in
 * a range it cannot be shown to belong to would be a claim.
 */
export function rangeEntries(entries) {
  if (chosen === "all") return entries;
  if (chosen === "custom") {
    if (!from && !to) return entries;
    // Both dates count, which is the sheet's own sentence and an inclusive comparison.
    return entries.filter((e) => {
      const day = dayOf(e);
      return day && (!from || day >= from) && (!to || day <= to);
    });
  }
  const first = since();
  return first ? entries.filter((e) => dayOf(e) && dayOf(e) >= first) : entries;
}

/* ---------------------------------------------------------------------- the control */

/** Draw the picker. Called on every redraw, so the chosen chip survives a rotation. */
export function renderRange() {
  const host = el("trends-range");
  if (!host) return;
  const line = chosen === "custom" && (from || to)
    ? `<span class="dim">${esc(from || "the start")} to ${esc(to || "today")}</span>` : "";
  host.innerHTML = `<div class="trend-range seg" role="group" aria-label="Range">
    ${RANGES.map((r) => `<button type="button" class="seg-btn" data-range="${esc(r.id)}"
      aria-pressed="${r.id === chosen}" aria-label="${esc(r.label)}"><span
      class="seg-wide">${esc(r.label)}</span>${r.short
        ? `<span class="seg-narrow">${esc(r.short)}</span>` : ""}</button>`).join("")}
    ${line}</div>`;
}

/** The sentence a narrowed, empty chart says — the phone's `ContentUnavailableView`. */
export const emptyRangeNote = () => {
  const host = el("trends-range");
  return host?.dataset.empty || "Nothing in this range";
};

function choose(id) {
  if (id === "custom") {
    openSheet();
    return;
  }
  chosen = id;
  // The chip that was pressed, out of the fixed set the picker draws. A preset id is not a
  // date: "90d" says which window riders read their trends in, and `custom` below says the
  // presets were not enough. Neither event ever carries the dates themselves.
  track("app-range-chosen", { range: id });
  renderRange();
  hooks.onChange();
}

/* ------------------------------------------------------------------------ the sheet */

function openSheet() {
  const dialog = el("range-dialog");
  if (!dialog || dialog.open) return;
  el("range-from").value = from || since() || "";
  el("range-to").value = to || iso(new Date());
  dialog.showModal();
}

/**
 * Wire the picker and its sheet. `onChange` is asked to redraw; this file never draws a
 * chart and never asks Python anything.
 */
export function mountRange(options = {}) {
  hooks = { ...hooks, ...options };
  const host = el("trends-range");
  if (host) {
    host.addEventListener("click", (ev) => {
      const button = ev.target.closest("button[data-range]");
      if (button) choose(button.dataset.range);
    });
  }
  const dialog = el("range-dialog");
  if (!dialog) return;
  el("range-cancel").addEventListener("click", () => dialog.close());
  el("range-done").addEventListener("click", () => {
    const a = el("range-from").value;
    const b = el("range-to").value;
    // Whichever way round they were picked: two dates are a range, and a rider who set
    // "to" first has not made a mistake to be told about.
    from = a && b && a > b ? b : a;
    to = a && b && a > b ? a : b;
    chosen = "custom";
    dialog.close();
    // A custom window was actually set. The two dates stay here: a from and a to describe
    // a rider's season, which is the kind of thing docs/analytics.md forbids an event to
    // carry. The `days` it spans is a shape, not a date, and that is what travels.
    track("app-range-custom-used",
          { days: from && to ? Math.round((Date.parse(to) - Date.parse(from)) / 86400000) : 0 });
    renderRange();
    hooks.onChange();
  });
  renderRange();
}
