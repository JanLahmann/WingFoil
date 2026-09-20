/* One line, or the whole page — the reader picks, once, and every surface obeys.
 *
 * Jan, 20 September 2026, reading the browser app on his phone: *"/app/#/help is way too
 * long"*, *"/app/#/settings is way too long, do we need all this?"*, *"parts of
 * /app/#/session are too long"*. Three complaints, one shape (docs/review-checklist.md is
 * written from exactly this): the app explained its mechanism where it should have said
 * what you get, and it did it in a paragraph where a line would do (pattern K, pattern I).
 *
 * WHAT AN EXPLANATION IS, HERE. Any element carrying `data-explain="<help topic id>"`:
 *
 *     <p class="muted small" data-explain="mapLegend">Shape carries the outcome…</p>
 *
 * The element's own text is the **concise** reading, and it is the one every rider gets by
 * default: what you get, in one line, twenty words at the outside. Beside it this module
 * puts a `?` that opens `#/help/<id>` — the help topic that carries the rest.
 *
 * In the **extensive** reading the `?` stays where it is and the topic's body is drawn
 * under the line. It is READ FROM THE CATALOGUE at that moment, out of `HELP` in
 * js/appcopy.js, which the generator writes from the kit's own `HelpCatalog`. It is never
 * typed into a page: one sentence, one home (pattern F). A surface whose detail is
 * generated rather than written — the turn page's footnote, whose paragraphs quote the
 * engine's own thresholds — hands its own `<div class="explain-more">` in instead, and
 * this module leaves it alone and only shows and hides it.
 *
 * A topic id that is not in the catalogue draws no `?` and no body rather than a dead
 * link, which is what lets `data-explain` be written before a topic exists.
 *
 * WHY A MutationObserver. Half of these paragraphs are in web/app/index.html and half are
 * written at run time by js/session.js, js/turnpage.js and js/appshell.js. A caller that
 * had to remember to re-run this after every render is a caller that will forget, and the
 * failure mode is a paragraph with no `?` on it that nobody notices. The observer is
 * fifteen lines and cannot forget.
 */

import { HELP } from "./appcopy.js";
import { detail, onSettingsChange, setDetail } from "./appsettings.js";
import { esc } from "./render.js";

/** Every topic in the catalogue, by id — the same lookup the Help page does. */
const TOPICS = new Map();
for (const section of HELP.sections || []) {
  for (const topic of section.topics || []) TOPICS.set(topic.id, topic);
}

export function helpTopic(id) {
  return TOPICS.get(id) || null;
}

/** The section a topic sits in, so a deep link can open the right fold. */
export function helpSectionOf(id) {
  for (const section of HELP.sections || []) {
    if ((section.topics || []).some((t) => t.id === id)) return section.id;
  }
  return null;
}

/* ------------------------------------------------------------------ one element */

/** The `?`, as the page's own control rather than a link: the app routes on the hash and
 *  a rider who middle-clicks a `?` should not open a second copy of the analyzer. */
function question(id) {
  const topic = TOPICS.get(id);
  const button = document.createElement("button");
  button.type = "button";
  button.className = "explain-q";
  button.dataset.explainQ = id;
  button.textContent = "?";
  // The accessible name is the topic's title, because "?" is a bare code and a bare code
  // needs its word within reach (pattern H). Sighted readers get the title on hover.
  const title = topic ? topic.title : "Help";
  button.setAttribute("aria-label", `Help: ${title}`);
  button.title = title;
  return button;
}

/** The topic's own body, as the extensive reading. Summary first, then the paragraphs,
 *  then the term/detail items — the order the Help page draws, because it is the same
 *  article read in a narrower place. */
function bodyHtml(topic) {
  const items = (topic.items || []).map((i) =>
    `<div class="g-entry"><dt>${esc(i.term)}</dt><dd>${esc(i.detail)}</dd></div>`).join("");
  return `<p class="explain-summary">${esc(topic.summary)}</p>`
    + (topic.body || []).map((p) => `<p>${esc(p)}</p>`).join("")
    + (items ? `<dl class="glossary-list">${items}</dl>` : "");
}

/** Wire one explanation: a `?` after the line, and a place to put the rest. */
function mount(host) {
  if (host.dataset.explainReady === "1") return;
  host.dataset.explainReady = "1";
  host.classList.add("explain");

  const id = host.dataset.explain;
  const topic = TOPICS.get(id);

  // A body the renderer handed in — the turn page's footnote, whose numbers are the
  // engine's — wins over the catalogue's. Nothing here rewrites it; it is only shown.
  let more = host.querySelector(":scope > .explain-more");
  if (more) more.dataset.explainOwn = "1";

  if (topic) {
    host.appendChild(document.createTextNode(" "));
    host.appendChild(question(id));
    if (!more) {
      more = document.createElement("div");
      more.className = "explain-more";
      more.innerHTML = bodyHtml(topic);
      host.appendChild(more);
    }
  }
  if (more) more.hidden = detail() !== "extensive";
}

/* -------------------------------------------------------------------- the sweep */

/** Wire everything under `root` that is not wired yet. Safe to call as often as you like. */
export function mountExplanations(root = document) {
  for (const host of root.querySelectorAll("[data-explain]")) mount(host);
}

/** Show or hide every extensive body, and stamp the choice on the document so the
 *  stylesheet can answer for the rest (`body[data-detail="extensive"]`). */
export function applyDetail() {
  const level = detail();
  document.body.dataset.detail = level;
  for (const more of document.querySelectorAll(".explain-more")) {
    more.hidden = level !== "extensive";
  }
  for (const control of document.querySelectorAll("[data-detail-set]")) {
    control.setAttribute("aria-pressed",
                         String(control.dataset.detailSet === level));
  }
}

/**
 * Start the whole thing: wire what is on the page, watch for what arrives later, and put
 * one delegated listener on the `?` and on every concise/extensive switch.
 *
 * `onOpenTopic` is the router's — this module knows which topic a `?` names and nothing at
 * all about how the app gets there.
 */
export function mountExplain({ onOpenTopic = () => {} } = {}) {
  mountExplanations();
  applyDetail();

  const observer = new MutationObserver((records) => {
    let touched = false;
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node.nodeType !== 1) continue;
        if (node.matches?.("[data-explain]") || node.querySelector?.("[data-explain]")) {
          touched = true;
        }
      }
    }
    if (touched) {
      mountExplanations();
      applyDetail();
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });

  document.addEventListener("click", (ev) => {
    const q = ev.target.closest?.("[data-explain-q]");
    if (q) {
      ev.preventDefault();
      onOpenTopic(q.dataset.explainQ);
      return;
    }
    const set = ev.target.closest?.("[data-detail-set]");
    if (set) {
      ev.preventDefault();
      setDetail(set.dataset.detailSet);
    }
  });

  onSettingsChange(applyDetail);
}
