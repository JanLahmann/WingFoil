/* The session view's section switcher — narrow viewports only.
 *
 * On a 430 × 932 phone the session view is roughly seven screens before the turns table
 * even starts, then 34 turn rows, then 23 flight-end rows: ~6 000 px of one column
 * (app-ui-review.md §7.2). Below 760 px this file puts a second row of chips under the
 * topbar's `.views` control and shows one section of panels at a time, which is the same
 * switcher the iOS SessionDetail gets in this change.
 *
 * Two things this file must never do.
 *
 * 1. **Appear above 760 px.** app-ui-review.md §3.4 puts "tabs on the desktop web session
 *    view" on the review's "deliberately not recommended" list: at 1120 px the session is a
 *    document and a good one, the two long tables want a continuous page, and that is what
 *    makes it a lab tool rather than an app. The chip row is `display: none` in css above
 *    the breakpoint and `apply()` un-hides every panel there, so no sequence of taps and
 *    resizes can leave a desktop reader with a panel missing.
 * 2. **Split the map from the speed strip.** docs/presentation.md "Scrub and zoom" mandates
 *    ONE playhead — the map dot and the strip's scrub position are the same timestamp and
 *    moving either moves both — and "Pairing" adds that tapping a flown stretch of track
 *    focuses the strip on that flight. They are one instrument with a visible link, not two
 *    pages, which is exactly why §3.2 rejected an `Overview / Map / Turns / …` split. The
 *    Track and Speed panels therefore share the one `data-section="mapSpeed"` chip. Do not
 *    give either its own.
 *
 * The chips are built from the `data-section` attributes actually present in `#results`,
 * not from a list kept here, so a panel added to index.html later joins the switcher by
 * carrying the attribute — the web has no HR/effort content today (an "Effort" chip would
 * open an empty tab, which is worse than an honest label), and when it gains some, adding
 * `effort` to SECTIONS below and the attribute to the panel is the whole change.
 */

import { closePopover } from "./render.js";

/** The one place a section id becomes a chip. Iteration order is chip order, and it is the
 *  iOS switcher's order (`Map · Speed | Turns | Takeoffs | …`) rather than the document
 *  order the panels happen to sit in, because the two platforms are meant to read the
 *  same. An id with no panel in the DOM simply gets no chip. */
const SECTIONS = {
  mapSpeed: "Map · Speed",
  turns: "Turns",
  takeoffs: "Takeoffs",
  data: "Data",
};

/* Map · Speed is the default for a reason beyond it being the first chip: a figure drawn
 * while its panel is `hidden` measures its container at 0 and falls back to the 1100-unit
 * maximum (js/viz.js `figureWidth`), so the track would land in a 400 px column at a third
 * of the type size it was tuned at. The default section is the one that is on screen when
 * `render()` first draws, and every later reveal redraws — see `apply`. */
const DEFAULT_SECTION = "mapSpeed";

/* The same 760 px the phone block in css/style.css uses. Kept as a media query rather than
 * a width comparison so the two cannot drift: whatever the css thinks is a phone is what
 * this file hides panels for. */
const NARROW = "(max-width: 760px)";

const media = window.matchMedia(NARROW);

let active = DEFAULT_SECTION;
let redrawFigures = () => {};

const nav = () => document.getElementById("section-nav");
const panels = () =>
  Array.from(document.querySelectorAll("#results .panel[data-section]"));

/**
 * Show `active`'s panels and mark its chip.
 *
 * `redraw` asks for the figures to be re-drawn afterwards, and only ever does so when a
 * figure is now on screen that may have been laid out while it was hidden — the user was
 * reading the turns table when the phone rotated, the debounced resize handler in
 * js/app.js redrew the report, and the track it redrew was measured at zero.
 */
function apply({ redraw = false } = {}) {
  const narrow = media.matches;
  for (const panel of panels()) {
    panel.hidden = narrow && panel.dataset.section !== active;
  }
  for (const button of nav().querySelectorAll("button[data-section]")) {
    button.setAttribute("aria-current",
                        narrow && button.dataset.section === active ? "page" : "false");
  }
  if (redraw && panels().some((p) => !p.hidden && p.querySelector(".figure"))) {
    redrawFigures();
  }
}

/** Build the chip row from the panels the page actually has. A single section is not a
 *  choice, so the row stays hidden rather than showing one inert chip. */
function buildChips() {
  const seen = new Set(panels().map((p) => p.dataset.section));
  const ids = Object.keys(SECTIONS).filter((id) => seen.has(id));
  const row = nav();
  row.innerHTML = ids.map((id) =>
    `<button type="button" data-section="${id}" aria-current="false">${SECTIONS[id]}</button>`)
    .join("");
  row.hidden = ids.length < 2;
  if (!ids.includes(active)) active = ids[0] ?? DEFAULT_SECTION;
  for (const button of row.querySelectorAll("button[data-section]")) {
    button.addEventListener("click", () => select(button.dataset.section));
  }
}

function select(id) {
  if (id === active) return;
  active = id;
  // A marker popover is a fixed-position child of <body>, not of the figure that opened
  // it, so leaving Map · Speed with one open would strand it over the turns table — the
  // same reason `showView()` closes it when a top-level view changes.
  closePopover();
  apply({ redraw: true });
}

/**
 * Wire the switcher. `redrawFigures` is called when a reveal puts a figure back on screen;
 * it is expected to be a no-op when no document is loaded.
 */
export function mountSections({ redrawFigures: redraw }) {
  redrawFigures = redraw;
  buildChips();
  // matchMedia rather than the debounced `resize` handler in js/app.js: that one ignores
  // width changes under 40 px, and dragging a window from 761 px to 759 px is a two-pixel
  // change that switches the entire layout. This fires exactly on the crossing, in both
  // directions, and ends with every panel visible when the answer is "desktop".
  media.addEventListener("change", () => apply({ redraw: true }));
  apply();
}

/** Back to Map · Speed. Called before a new document is drawn, so `render()` measures the
 *  figures' containers while they are visible and the state a chip could have left behind
 *  never outlives the session it belonged to. */
export function resetSections() {
  active = DEFAULT_SECTION;
  apply();
}
