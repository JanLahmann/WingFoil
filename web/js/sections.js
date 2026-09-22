/* The session page's four sub-tabs: Ride · Turns · Takeoffs · Log.
 *
 * The web is a port of the iPhone app (Jan, 19 September 2026: "iOS is the reference, the
 * web is the port"), so the session page is cut the way `SessionSection` cuts it and the
 * chips carry its four words. They are on at EVERY width now. app-ui-review.md §3.4 put
 * "tabs on the desktop web session view" on the review's deliberately-not-recommended list
 * while the analyzer was a lab tool whose session page was a document; it is a page of an
 * app now, and two structures for one product is what the port was asked to end. The old
 * divergence is written down in docs/presentation.md, "The web still carries the pre-re-cut
 * ids", and that paragraph is retired with this change.
 *
 * Two things this file must never do.
 *
 * 1. **Split the map from the speed strip.** docs/presentation/scrub-pairing.md "Scrub and zoom" mandates
 *    ONE playhead — the map dot and the strip's scrub position are the same timestamp and
 *    moving either moves both — and "Pairing" adds that tapping a flown stretch of track
 *    focuses the strip on that flight. They are one instrument with a visible link, not two
 *    pages. The Track and Speed panels therefore share the one `data-section="ride"` chip,
 *    which is exactly why the phone's first tab is called Ride rather than Map.
 * 2. **Take the key metrics with it.** The block that answers "was that a good session" is
 *    above the switcher and on every section, on both surfaces (§3.3).
 *
 * The chips are built from the `data-section` attributes actually present in `#results`,
 * not from a list kept here, so a panel added to index.html later joins the switcher by
 * carrying the attribute.
 */

import { closePopover } from "./render.js";

/** The one place a section id becomes a chip. Iteration order is chip order, and it is the
 *  phone's: `SessionSection.allCases` is ride, turns, takeoffs, log, and its labels are
 *  these four words (ios/WingFoilKit/Sources/WingFoilKit/Presentation/SessionSection.swift).
 *  docs/copy/app-shell.json carries the same four, for this page and for the verifier that
 *  holds the two sides together. An id with no panel in the DOM simply gets no chip. */
const SECTIONS = {
  ride: "Ride",
  turns: "Turns",
  takeoffs: "Takeoffs",
  log: "Log",
};

/* Ride is the default for a reason beyond it being the first chip: a figure drawn while its
 * panel is `hidden` measures its container at 0 and falls back to the 1100-unit maximum
 * (js/viz.js `figureWidth`), so the track would land in a 400 px column at a third of the
 * type size it was tuned at. The default section is the one that is on screen when
 * `render()` first draws, and every later reveal redraws — see `apply`. */
const DEFAULT_SECTION = "ride";

let active = DEFAULT_SECTION;
let redrawFigures = () => {};

const nav = () => document.getElementById("section-nav");
const panels = () =>
  Array.from(document.querySelectorAll("#results .panel[data-section]"));

/**
 * Show `active`'s panels and mark its chip.
 *
 * `redraw` asks for the figures to be re-drawn afterwards, and only ever does so when a
 * figure is now on screen that may have been laid out while it was hidden — the reader was
 * on Turns when the phone rotated, the debounced resize handler in js/app.js redrew the
 * report, and the track it redrew was measured at zero.
 */
function apply({ redraw = false } = {}) {
  for (const panel of panels()) {
    panel.hidden = panel.dataset.section !== active;
  }
  for (const button of nav().querySelectorAll("button[data-section]")) {
    button.setAttribute("aria-current",
                        button.dataset.section === active ? "page" : "false");
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
  // it, so leaving Ride with one open would strand it over the turns table — the same
  // reason the tab router closes it when a top-level page changes.
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
  apply();
}

/** Back to Ride. Called before a new document is drawn, so `render()` measures the figures'
 *  containers while they are visible and the state a chip could have left behind never
 *  outlives the session it belonged to. */
export function resetSections() {
  active = DEFAULT_SECTION;
  apply();
}
