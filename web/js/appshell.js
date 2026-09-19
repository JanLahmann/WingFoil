/* The shell: four tabs, one menu, seven pages.
 *
 * Jan, 19 September 2026: *"iOS is the reference, the web is the port"*. So this file is
 * the browser's `RootView` — the four tabs the phone has, in its order and its words, with
 * the app menu on every one of them (docs/review-checklist.md, pattern M) — and the pages
 * its menu rows open. What it is NOT is a second product: the analyzer's own strengths keep
 * their place, as the first two rows of the Sessions tab's empty state rather than as a view
 * called Analyze.
 *
 * WHAT THIS FILE OWNS
 *
 *   routing      `#/sessions`, `#/records`, `#/trends`, `#/gear`, `#/settings`, `#/help`
 *                and `#/session`. The four tabs are the four the phone has; Settings and
 *                Help are menu rows, which is why they are pages and not tabs; `#/session`
 *                is what a row opens, the way the phone pushes `SessionDetailView`.
 *   the menu     the five rows of `AppMenuRow.ordered`, its one divider, and the build line
 *                under them.
 *   the welcome  once per browser, and again whenever *What CleanJibe does* is tapped.
 *   Settings     units, start over, About and What's new. The intervals.icu panel is markup
 *                in the page and js/icu.js's to wire; this file only routes to it.
 *   Help         docs/copy/help.json, rendered. The glossary section is the eleven words
 *                out of js/copy.js, which is their one home on this side of the site.
 *   Gear & spots the spots the library clusters into, and a name per session.
 *
 * WHAT IT DOES NOT OWN: a number. Every figure on every page is a field of the Python
 * digest or of `library.aggregate`, printed — the same rule the rest of this directory
 * keeps (web/README.md, "The one architectural rule"). The one piece of arithmetic here is
 * the distance between two sessions' start points, and that is grouping rather than
 * analysis: it uses the same 500 m radius and the same haversine the phone's
 * `SpotClusterer` and `lab_bundle/library.py` use, so a spot on this tab is the spot the
 * trips list already found.
 */

import { FEEDBACK, GUIDE, HELP, SETTINGS, WELCOME, WHATS_NEW } from "./appcopy.js";
import {
  forgetSettings, gearFor, gearMap, markWelcomeSeen, onSettingsChange, setGearFor,
  setUnits, units, welcomeSeen,
} from "./appsettings.js";
import { GLOSSARY } from "./copy.js";
// r3-w1: wings, boards and foils, and the tombstones a delete leaves. Both are screens of
// their own with their own files; this page only says where they are drawn.
import { renderQuiver } from "./gear.js";
import { renderDeleted } from "./deleted.js";
import { esc, hms, int, nf } from "./render.js";
/* r3-w3: the Spots half of this tab is a screen of its own now — the phone's clusterer, a
   rename that sticks, "Re-cluster spots" and "Look up names again". js/spots.js. */
import { renderSpots } from "./spots.js";
import { esc, int } from "./render.js";   // r3-w3: hms and nf left with the spots list
import { listEntries, removeSession, storageLabel } from "./store.js";

const el = (id) => document.getElementById(id);

/** Every page in the shell, and the tab that owns it. A page with no tab of its own marks
 *  none, which is what a menu row's destination should do. */
const PAGES = {
  sessions: "sessions",
  session: "sessions",
  records: "records",
  trends: "trends",
  gear: "gear",
  settings: null,
  help: null,
};

/** The routes this page answered to before it had tabs. A bookmark, a link from the
 *  homepage or a browser's own history must not land on a blank page. */
const LEGACY = { analyze: "sessions", library: "sessions" };

let hooks = {
  onExample: () => {},
  onShowPage: () => {},
  onStartOver: async () => {},
};

let current = "sessions";
let engine = { engineVersion: null, pyodideVersion: null };

/* --------------------------------------------------------------------- routing */

/** Show one page and mark its tab. Exported because js/app.js sends the reader to the
 *  session page the moment an analysis lands. */
export function showPage(name) {
  const page = PAGES[name] !== undefined ? name : (LEGACY[name] || "sessions");
  current = page;
  for (const id of Object.keys(PAGES)) {
    el(`page-${id}`).hidden = id !== page;
  }
  const tab = PAGES[page];
  for (const button of document.querySelectorAll(".tabbar button[data-tab]")) {
    button.setAttribute("aria-current", button.dataset.tab === tab ? "page" : "false");
  }
  if (location.hash !== `#/${page}`) history.replaceState(null, "", `#/${page}`);
  hooks.onShowPage(page);
  if (page === "gear") renderGear().catch(() => {});
  if (page === "settings") {
    renderAbout().catch(() => {});
    renderDeleted().catch(() => {});                                       // r3-w1
  }
}

export function currentPage() {
  return current;
}

function wireTabs() {
  for (const button of document.querySelectorAll(".tabbar button[data-tab]")) {
    button.addEventListener("click", () => showPage(button.dataset.tab));
  }
  window.addEventListener("hashchange", () => showPage(location.hash.replace("#/", "")));
  // One delegated listener for every "go there" control on every page — the ways-in card's
  // Open Settings, the empty states' door out (pattern G), the glossary's link into Help.
  // A page rendered later joins by carrying the attribute.
  document.addEventListener("click", (ev) => {
    const go = ev.target.closest("[data-goto]");
    if (!go) return;
    ev.preventDefault();
    closeMenu();
    showPage(go.dataset.goto);
  });
  el("session-back").addEventListener("click", () => showPage("sessions"));
}

/* ------------------------------------------------------------------- the menu */

function closeMenu() {
  const menu = el("app-menu");
  if (menu.open) menu.close();
  el("app-menu-btn").setAttribute("aria-expanded", "false");
}

function wireMenu() {
  const menu = el("app-menu");
  el("app-menu-btn").addEventListener("click", () => {
    if (menu.open) return;                  // showModal() on an open dialog throws
    el("menu-build").textContent = buildLine();
    menu.showModal();
    el("app-menu-btn").setAttribute("aria-expanded", "true");
  });
  el("app-menu-close").addEventListener("click", closeMenu);
  menu.addEventListener("close", () =>
    el("app-menu-btn").setAttribute("aria-expanded", "false"));

  for (const button of menu.querySelectorAll("button[data-menu]")) {
    button.addEventListener("click", () => {
      const row = button.dataset.menu;
      closeMenu();
      if (row === "whatItDoes") openWelcome();
      else if (row === "gettingStarted") showPage("help");
      else if (row === "settings") showPage("settings");
      else if (row === "help") showPage("help");
      else if (row === "support") location.href = feedbackMail();
    });
  }
}

/** "CleanJibe 0.15.0 · engine 0.19.0", the browser's answer to the phone's build line.
 *  The version is the newest public release note's, which a generator writes. */
function buildLine() {
  const version = WHATS_NEW[0]?.version;
  const bits = ["CleanJibe"];
  if (version) bits.push(version);
  if (engine.engineVersion) bits.push(`· engine ${engine.engineVersion}`);
  return bits.join(" ");
}

/** The feedback door, composed out of docs/copy/feedback.json rather than typed. The three
 *  prompts and the invitation are what `verify_copy.py` demands of every mailto on this
 *  site, so composing beats retyping in two ways at once. */
function feedbackMail() {
  const body = FEEDBACK.prompts.map((p) => `${p}\n\n\n`).join("")
    + "Your browser and device:\n\n"
    + `${buildLine()}\n\n`
    + `${FEEDBACK.invitation} Attach a screenshot or the session's .fit file if you can.\n`;
  return `mailto:${FEEDBACK.doors.web}?subject=${encodeURIComponent(FEEDBACK.subjectPrefix)}`
    + `&body=${encodeURIComponent(body)}`;
}

/* ----------------------------------------------------------------- the welcome */

/**
 * The first screen a first open shows, and the one *What CleanJibe does* opens again.
 *
 * Its headline and promise are `WelcomeGuide`'s, its four words are the four glossary ids
 * `WelcomeGuide.highlights` selects, and its list of routes is the generated guide block —
 * the same five, in the same order, that /start/ prints. Nothing in it is hand-copied.
 */
function openWelcome() {
  // `showModal()` on an open dialog throws, and the library refreshes more than once on a
  // first run — one offer, however many times it is made.
  if (el("welcome-dialog").open) return;
  const line = (id) => GLOSSARY.find((g) => g.id === id);
  const words = WELCOME.highlights.map(line).filter(Boolean);
  el("welcome-body").innerHTML = `
    <p class="welcome-headline">${esc(WELCOME.headline)}</p>
    <p class="welcome-promise">${esc(WELCOME.promise)}</p>
    <dl class="glossary-list">${words.map((w) => `
      <div class="g-entry"><dt>${esc(w.term)}</dt><dd>${esc(w.line)}</dd></div>`).join("")}
    </dl>
    <h3 class="sub-head">Getting started</h3>
    <p class="muted small">${esc(GUIDE.framing)}</p>
    <ul class="guide-routes">${GUIDE.routes.map((r) => `
      <li><a href="${esc(r.href)}">${esc(r.title)}</a>
        <span class="dim">${esc(r.status)}</span>
        <span class="way-line">${esc(r.summary)}</span></li>`).join("")}</ul>`;
  el("welcome-dialog").showModal();
}

function wireWelcome() {
  const dialog = el("welcome-dialog");
  el("welcome-close").addEventListener("click", () => {
    markWelcomeSeen();
    dialog.close();
  });
  el("welcome-example").addEventListener("click", () => {
    markWelcomeSeen();
    dialog.close();
    hooks.onExample();
  });
  dialog.addEventListener("close", markWelcomeSeen);
}

/* ---------------------------------------------------------------------- settings */

function wireSettings() {
  // The two section captions the phone prints, from the file the phone reads them from.
  el("icu-footer").textContent = SETTINGS.intervalsIcu;
  el("strava-footer").textContent = SETTINGS.strava;

  for (const button of document.querySelectorAll("#settings-units .seg-btn")) {
    button.addEventListener("click", () => {
      setUnits(button.dataset.units);
      markUnits();
    });
  }
  markUnits();

  el("start-over").addEventListener("click", async () => {
    // A confirm rather than a second screen: it is one question with two answers, and the
    // one thing it must not be is a button that wipes a library on a mis-tap.
    if (!window.confirm("Start over?\n\nYour library, your settings and your "
                        + "intervals.icu key are removed from this browser. "
                        + "This cannot be undone.")) return;
    for (const entry of await listEntries()) await removeSession(entry.id);
    forgetSettings();
    await hooks.onStartOver();
    location.hash = "#/sessions";
    location.reload();
  });

  renderWhatsNew();
}

function markUnits() {
  const chosen = units();
  for (const button of document.querySelectorAll("#settings-units .seg-btn")) {
    button.setAttribute("aria-pressed", String(button.dataset.units === chosen));
  }
}

/** The release notes /whats-new/ prints, in the app that they are about. Rendered rather
 *  than typed: every line of this section is a date and a build number, which
 *  `docs/copy/check_voice.py` fails in page markup because a hand-typed one goes stale
 *  (pattern C). A generator's fact is allowed to be a number. */
function renderWhatsNew() {
  const host = el("whats-new-body");
  if (!WHATS_NEW.length) {
    host.innerHTML = `<p class="note">Nothing yet.</p>`;
    return;
  }
  host.innerHTML = WHATS_NEW.map((entry) => `
    <article class="release">
      <h3>${esc(heading(entry))}</h3>
      <p class="dim small">${esc(entry.title)} · ${esc(dayText(entry.date))}</p>
      <ul>${entry.lines.map((l) => `<li>${esc(l)}</li>`).join("")}</ul>
    </article>`).join("");
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August",
                "September", "October", "November", "December"];

/** `2026-09-19` → `19 September 2026`, the spelling /whats-new/ already uses. */
function dayText(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || ""));
  if (!m) return String(iso || "");
  return `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}`;
}

/** What a card is titled: the product, then its number — `make_whats_new.heading`. */
function heading(entry) {
  return entry.build === null || entry.build === undefined
    ? `Garmin watch app · ${entry.version}`
    : `iPhone · build ${entry.build}`;
}

async function renderAbout() {
  const rows = [
    ["Version", WHATS_NEW[0]?.version || "—"],
    ["Analysis engine", engine.engineVersion || "not started yet"],
    ["Python in the browser", engine.pyodideVersion || "not started yet"],
  ];
  try {
    rows.push(["Your library", await storageLabel()]);
  } catch { /* storage is unavailable; the row is simply not there */ }
  el("about-rows").innerHTML = rows.map(([k, v]) =>
    `<div class="row"><span>${esc(k)}</span><span>${esc(String(v))}</span></div>`).join("");
}

/** js/app.js hands the worker's `ready` on, so About can print what is actually running
 *  rather than what the bundle claims. */
export function noteEngine(versions) {
  engine = { ...engine, ...versions };
  if (current === "settings") renderAbout().catch(() => {});
}

/* -------------------------------------------------------------------------- help */

function renderHelp() {
  el("help-sub").textContent = HELP.stub
    ? "The full reference is on the iPhone app. This is what the browser can answer."
    : "";
  el("help-body").innerHTML = HELP.sections.map((section) => `
    <section class="help-section" id="help-${esc(section.id)}">
      <h3 class="sub-head">${esc(section.title)}</h3>
      ${section.glossary ? glossaryHtml() : ""}
      ${section.topics.map(topicHtml).join("")}
      ${!section.glossary && !section.topics.length
        ? `<p class="muted small">On the iPhone app.</p>` : ""}
    </section>`).join("");
}

const glossaryHtml = () =>
  `<dl class="glossary-list">${GLOSSARY.map((g) => `
    <div class="g-entry"><dt>${esc(g.term)}</dt><dd>${esc(g.line)}</dd></div>`).join("")}</dl>`;

const topicHtml = (topic) => `
  <article class="help-topic" id="help-topic-${esc(topic.id)}">
    <h4>${esc(topic.title)}</h4>
    <p class="muted small">${esc(topic.summary)}</p>
    ${(topic.body || []).map((p) => `<p>${esc(p)}</p>`).join("")}
    ${(topic.items || []).length ? `<dl class="glossary-list">${topic.items.map((i) => `
      <div class="g-entry"><dt>${esc(i.term)}</dt><dd>${esc(i.detail)}</dd></div>`)
      .join("")}</dl>` : ""}
  </article>`;

/* ---------------------------------------------------------------- gear & spots */

/* r3-w3: the 500 m clusterer, its haversine and the cluster's name moved to js/spots.js,
   which is also where the rename, the two doors and the "All spots" chip read them from.
   One spelling of a greedy clusterer per product: two would produce two sets of spots out
   of one library, and a greedy clusterer is sensitive to the order it reads its sessions
   in, so "roughly the same rule" is not the same spots. */

async function renderGear() {
  const host = el("gear-body");
  let entries = [];
  try {
    entries = await listEntries();
  } catch { /* storage refused; the empty state below is the honest answer */ }

  if (!entries.length) {
    host.innerHTML = `<p class="note">No sessions yet, so no spots and no gear. A session
      brings both.</p>
      <p><button class="ghost small-btn" type="button" data-goto="sessions">Go to
        Sessions</button></p>`;
    // r3-w1: the quiver is not a fact about the library. A rider may put his wings in
    // before his first session, the way he can on the phone.
    renderQuiver(el("gear-quiver")).catch(() => {});
    return;
  }

  const named = gearMap();
  const rollUp = new Map();
  for (const entry of entries) {
    const name = named[entry.id];
    if (name) rollUp.set(name, (rollUp.get(name) || 0) + 1);
  }

  // r3-w3:begin — the Spots section is js/spots.js now, and it is the phone's screen: the
  // same 500 m clusterer, a rename that sticks, "Re-cluster spots" and "Look up names
  // again". The Gear half below is untouched.
  host.innerHTML = `
    <div id="spots-section"></div>

    <h3 class="sub-head">Gear</h3>
    ${rollUp.size
      ? `<ul class="spot-list">${[...rollUp.entries()]
          .sort((a, b) => b[1] - a[1])
          .map(([name, n]) =>
            `<li><span class="spot-name">${esc(name)}</span>
               <span class="dim">${int(n)} sessions</span></li>`).join("")}</ul>`
      : `<p class="muted small">Nothing named yet. Type a wing, a board or a foil on a
           session below and it is counted here.</p>`}
    <ul class="gear-list">${entries.map((entry) => `
      <li>
        <label>${esc(entry.spot || entry.fileName || entry.id)}
          <input type="text" data-gear="${esc(entry.id)}" value="${esc(gearFor(entry.id))}"
                 placeholder="wing, board or foil" autocomplete="off" spellcheck="false">
        </label>
      </li>`).join("")}</ul>
    <p class="muted small">A name is yours and stays in this browser. The iPhone app keeps
      wings, boards and foils apart, with a history behind each.</p>`;

  renderSpots(el("spots-section"), entries, () => { renderGear().catch(() => {}); });
  // r3-w3:end

  for (const input of host.querySelectorAll("input[data-gear]")) {
    input.addEventListener("change", () => setGearFor(input.dataset.gear, input.value));
  }
  await renderQuiver(el("gear-quiver"));                                   // r3-w1
}

/* ------------------------------------------------------------------------- boot */

/**
 * Wire the shell and route to the page the URL asks for.
 *
 * `onExample` runs the bundled session; `onStartOver` lets js/app.js drop whatever it is
 * holding before the reload. Both are callbacks rather than imports, so this file and
 * js/app.js do not import each other.
 */
export function mountShell(options = {}) {
  hooks = { ...hooks, ...options };
  wireTabs();
  wireMenu();
  wireWelcome();
  wireSettings();
  renderHelp();
  onSettingsChange(() => {
    if (current === "gear") renderGear().catch(() => {});
  });
  showPage(location.hash.replace("#/", ""));
}

/** The count beside the Sessions tab, and which half of the Sessions tab is on screen: the
 *  ways-in card, or the list. Both are one fact, so they move together. */
export function setSessionCount(n) {
  const chip = document.querySelector('.tabbar button[data-tab="sessions"] .count');
  if (chip) {
    chip.textContent = n ? String(n) : "";
    chip.hidden = !n;
  }
  // The ways-in card is the empty state, and it is also the drop target, so it never goes
  // away entirely — it shrinks to the drop row. css/app.css does the shrinking.
  el("dropzone").classList.toggle("compact", n > 0);
  el("where-it-lives").hidden = n === 0;
}

/** Open the welcome once per browser, on a genuinely empty library. A reader with sessions
 *  has been through the front door already, whatever the flag says — the same evidence the
 *  phone's `WelcomePrompt` trusts. */
export function offerWelcome(sessionCount) {
  if (welcomeSeen() || sessionCount > 0) return;
  openWelcome();
}
