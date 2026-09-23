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

import {
  FEEDBACK, GUIDE, HELP, SETTINGS_SECTIONS, WELCOME, WHATS_NEW,
} from "./appcopy.js";
import {
  forgetSettings, gearFor, gearMap, markWelcomeSeen, onSettingsChange, setGearFor,
  setSpeedRecords, setUnits, speedRecords, units, welcomeSeen,
} from "./appsettings.js";
/* r7-w5: how much every explanation on this site says, and the `?` that carries the rest.
   One switch, remembered, obeyed by Settings, the session page and the panel notes alike. */
import { helpSectionOf, helpTopic, mountExplain } from "./explain.js";
import { GLOSSARY } from "./copy.js";
// r3-w1: wings, boards and foils, and the tombstones a delete leaves. Both are screens of
// their own with their own files; this page only says where they are drawn.
import { renderQuiver } from "./gear.js";
import { renderDeleted } from "./deleted.js";
/* r3-w3: the Spots half of this tab is a screen of its own now — the phone's clusterer, a
   rename that sticks, "Re-cluster spots" and "Look up names again". js/spots.js. */
import { renderSpots } from "./spots.js";
import { esc, int } from "./render.js";   // r3-w3: hms and nf left with the spots list
import { listEntries, removeSession, storageLabel } from "./store.js";
import { track } from "./track.js";

const el = (id) => document.getElementById(id);

/** Every page in the shell, and the tab that owns it. A page with no tab of its own marks
 *  none, which is what a menu row's destination should do. */
const PAGES = {
  sessions: "sessions",
  session: "sessions",
  records: "records",
  trends: "trends",
  // Periods and one period are pushed from Trends, so they keep the Trends tab marked —
  // the phone's own arrangement (docs/screens.md, Trends · Periods · Period page).
  periods: "trends",
  period: "trends",
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

/** A hash, split into the page it names and the thing on it: `#/help/mapLegend` is the
 *  Help page opened at one topic. Only Help takes an argument today, and the shape is the
 *  one the phone's own deep links have — a screen, then what is on it. */
function route(hash) {
  const [name, arg] = String(hash || "").replace(/^#\//, "").split("/");
  return { name, arg: arg || null };
}

/** Show one page and mark its tab. Exported because js/app.js sends the reader to the
 *  session page the moment an analysis lands. */
export function showPage(name, arg = null) {
  const page = PAGES[name] !== undefined ? name : (LEGACY[name] || "sessions");
  current = page;
  for (const id of Object.keys(PAGES)) {
    el(`page-${id}`).hidden = id !== page;
  }
  const tab = PAGES[page];
  for (const button of document.querySelectorAll(".tabbar button[data-tab]")) {
    button.setAttribute("aria-current", button.dataset.tab === tab ? "page" : "false");
  }
  const want = arg ? `#/${page}/${arg}` : `#/${page}`;
  if (location.hash !== want) history.replaceState(null, "", want);
  hooks.onShowPage(page, arg);
  if (page === "gear") renderGear().catch(() => {});
  if (page === "settings") {
    renderAbout().catch(() => {});
    renderDeleted().catch(() => {});                                       // r3-w1
  }
  if (page === "help") openHelpAt(arg);
}

/** Send the reader to one help topic, from anywhere: the `?` beside an explanation, a
 *  bookmark, a link out of the glossary fold. The topic's own section is opened and the
 *  article is scrolled to, which is what a deep link into a folded reference work owes. */
export function showHelpTopic(id) {
  showPage("help", id || null);
}

export function currentPage() {
  return current;
}

function wireTabs() {
  for (const button of document.querySelectorAll(".tabbar button[data-tab]")) {
    button.addEventListener("click", () => {
      // The tab bar, counted at the press rather than inside `showPage`: that function is
      // also how a finished analysis puts the session page on screen and how a hash on a
      // bookmark routes, and neither is somebody choosing a tab. The property is the tab's
      // own id out of a closed set of four (docs/analytics.md).
      track("app-tab-switched", { tab: button.dataset.tab });
      showPage(button.dataset.tab);
    });
  }
  window.addEventListener("hashchange", () => {
    const { name, arg } = route(location.hash);
    showPage(name, arg);
  });
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
      // Five rows, one closed set, one event. The menu is the phone's menu, so the same
      // question is asked on both surfaces: which of the five is ever pressed.
      track("app-menu-row-opened", { row });
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
  // The phone's third door (docs/screens.md, What CleanJibe does). A rider with a Garmin
  // takes this one, and the browser had nowhere to send him from here.
  el("welcome-icu").addEventListener("click", () => {
    markWelcomeSeen();
    dialog.close();
    showPage("settings");
  });
  el("welcome-example").addEventListener("click", () => {
    markWelcomeSeen();
    dialog.close();
    hooks.onExample();
  });
  dialog.addEventListener("close", markWelcomeSeen);
}

/* ---------------------------------------------------------------------- settings */

/**
 * **The header and the one line under it, written from the phone's own file.**
 *
 * `SETTINGS_SECTIONS` is docs/copy/settings.json, which the kit's `SettingsCopyExportTests`
 * writes out of `SettingsCopy` — the same enum `SettingsView` prints. So the browser cannot
 * word a switch differently from the phone, and a section whose lead is edited is edited
 * once (docs/review-checklist.md, pattern F).
 *
 * The lead is the CONCISE reading and it is what every rider gets. The phone's own footer
 * paragraphs ride along as the extensive one, in a `.explain-more` js/explain.js shows and
 * hides — they are the same paragraphs, not a second copy of them.
 */
function renderSettingsCopy() {
  for (const section of SETTINGS_SECTIONS) {
    const host = document.querySelector(`[data-settings="${section.id}"]`);
    if (!host) continue;
    const head = document.createElement("div");
    head.className = "panel-head";
    head.innerHTML = `<h2>${esc(section.title)}</h2>`;

    const lead = document.createElement("p");
    lead.className = "muted small settings-lead";
    lead.textContent = section.lead;
    // A section whose `?` would open a topic that is not in this build's catalogue gets no
    // `?`, and nothing is lost: the lead already says what the rows do.
    if (section.help && helpTopic(section.help)) lead.dataset.explain = section.help;
    // The phone's footer, where there is one. It is handed in rather than looked up,
    // because these paragraphs are Settings' own and are not a help topic's body.
    if ((section.footer || []).length) {
      const more = document.createElement("div");
      more.className = "explain-more";
      more.innerHTML = section.footer.map((p) => `<p>${esc(p)}</p>`).join("");
      lead.appendChild(more);
    }
    host.prepend(lead);
    host.prepend(head);
  }
}

function wireSettings() {
  renderSettingsCopy();

  for (const button of document.querySelectorAll("#settings-units .seg-btn")) {
    button.addEventListener("click", () => {
      setUnits(button.dataset.units);
      markUnits();
    });
  }
  markUnits();

  // Settings → Speed records. Same shape as the unit switch above it, and for the same
  // reason: three buttons, one stored word, and everything that reads a record asks the
  // store rather than remembering an answer of its own.
  for (const button of document.querySelectorAll("#settings-speed-records .seg-btn")) {
    button.addEventListener("click", () => {
      setSpeedRecords(button.dataset.speedRecords);
      markSpeedRecords();
    });
  }
  markSpeedRecords();

  // **THE CONFIRMATION IS ON THE PAGE** (Jan, 20 September 2026). It was `window.confirm`,
  // which is the browser asking in the browser's words over an app that has its own, and
  // on a phone the two are indistinguishable. One question, two answers, both here, and
  // the destructive one is never what a stray tap lands on.
  const wipe = el("wipe-confirm");
  el("start-over").addEventListener("click", () => {
    wipe.hidden = false;
    el("wipe-cancel").focus();
  });
  el("wipe-cancel").addEventListener("click", () => {
    wipe.hidden = true;
    el("start-over").focus();
  });
  el("wipe-go").addEventListener("click", async () => {
    wipe.hidden = true;
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

/** What the chosen mode does, under the buttons. One line per mode, the phone's own
 *  (`SpeedRecordPolicy.summary` in the kit): three two-word labels cannot say when an
 *  unverified record counts, and that is the whole difference between them. */
const SPEED_RECORD_SUMMARY = {
  onlyVerified: "Only records your watch measured. Nothing else counts.",
  preferVerified: "A measured record wins. An estimated one fills an empty row, marked.",
  includeUnverified: "Every record counts. Estimated ones are marked.",
};

function markSpeedRecords() {
  const chosen = speedRecords();
  for (const button of document.querySelectorAll("#settings-speed-records .seg-btn")) {
    button.setAttribute("aria-pressed",
                        String(button.dataset.speedRecords === chosen));
  }
  const line = el("speed-records-summary");
  if (line) line.textContent = SPEED_RECORD_SUMMARY[chosen] || "";
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

const kvHtml = (rows) => rows.map(([k, v]) =>
  `<div class="row"><span>${esc(k)}</span><span>${esc(String(v))}</span></div>`).join("");

async function renderAbout() {
  el("about-rows").innerHTML = kvHtml([
    ["Version", WHATS_NEW[0]?.version || "—"],
    ["Analysis engine", engine.engineVersion || "not started yet"],
    ["Python in the browser", engine.pyodideVersion || "not started yet"],
  ]);
  await renderStorage();
}

/** The figures the phone's Storage section carries, under *Your data* — how many sessions
 *  and where they are. It is the one row About used to hold and Sessions used to explain,
 *  and it is in the section that owns the subject on both shells. */
async function renderStorage() {
  const rows = [["Sessions", String((await listEntries().catch(() => [])).length)]];
  try {
    rows.push(["Saved in", await storageLabel()]);
  } catch { /* storage is unavailable; the row is simply not there */ }
  el("storage-rows").innerHTML = kvHtml(rows);
}

/** js/app.js hands the worker's `ready` on, so About can print what is actually running
 *  rather than what the bundle claims. */
export function noteEngine(versions) {
  engine = { ...engine, ...versions };
  if (current === "settings") renderAbout().catch(() => {});
}

/* -------------------------------------------------------------------------- help */

/**
 * **Forty topics, met the way a reader meets a reference work** (docs/web-design-review.md,
 * finding 11; Jan, 20 September 2026: *"/app/#/help is way too long"*).
 *
 * It used to be every section expanded, no index and no search — a wall, with the ladder
 * inverted, because a topic's summary was set smaller than the body under it. It is now
 * what the phone's Help is: ten handles, a filter, and the article you asked for.
 *
 *   * a chip row of the ten sections at the top, in the session switcher's shape;
 *   * one `<details>` per section, **shut**, its handle carrying the topic count;
 *   * a filter over every title and every summary, which opens the sections that still
 *     have a match and says how many are left;
 *   * `#/help/<id>` opens the section a topic is in and scrolls to it.
 *
 * The summary is at body size, over the body, which is the order it is read in.
 */
function renderHelp() {
  el("help-sub").textContent = HELP.stub
    ? "The full reference is on the iPhone app. This is what the browser can answer."
    : "";

  const sections = HELP.sections.filter((s) => s.glossary || s.topics.length);
  el("help-index").innerHTML = sections.map((section) => `
    <button type="button" class="help-chip" data-help-section="${esc(section.id)}">
      ${esc(section.title)}
      <span class="help-count">${countOf(section)}</span>
    </button>`).join("");

  el("help-body").innerHTML = sections.map((section) => `
    <details class="help-section" id="help-${esc(section.id)}">
      <summary>
        <span class="help-section-name">${esc(section.title)}</span>
        <span class="help-count">${countOf(section)}</span>
      </summary>
      ${section.glossary ? glossaryHtml() : ""}
      ${section.topics.map(topicHtml).join("")}
    </details>`).join("");

  wireHelpFilter();
}

const countOf = (section) => {
  const n = section.glossary ? GLOSSARY.length : section.topics.length;
  return n === 1 ? "1 page" : `${n} pages`;
};

const glossaryHtml = () =>
  `<dl class="glossary-list">${GLOSSARY.map((g) => `
    <div class="g-entry"><dt>${esc(g.term)}</dt><dd>${esc(g.line)}</dd></div>`).join("")}</dl>`;

/** One topic. The summary is `.what` — body size, over the body — because a summary set
 *  smaller than the prose it introduces is a ladder upside down (finding 11). */
const topicHtml = (topic) => `
  <article class="help-topic" id="help-topic-${esc(topic.id)}"
           data-find="${esc(`${topic.title} ${topic.summary}`.toLowerCase())}">
    <h4>${esc(topic.title)}</h4>
    <p class="what">${esc(topic.summary)}</p>
    ${(topic.body || []).map((p) => `<p>${esc(p)}</p>`).join("")}
    ${(topic.items || []).length ? `<dl class="glossary-list">${topic.items.map((i) => `
      <div class="g-entry"><dt>${esc(i.term)}</dt><dd>${esc(i.detail)}</dd></div>`)
      .join("")}</dl>` : ""}
  </article>`;

/** The filter, and the chip row: both are ways of opening one fold out of ten. */
function wireHelpFilter() {
  const field = el("help-filter");
  const status = el("help-filter-count");

  const run = () => {
    const needle = field.value.trim().toLowerCase();
    let hits = 0;
    for (const section of el("help-body").querySelectorAll("details.help-section")) {
      let shown = 0;
      for (const topic of section.querySelectorAll(".help-topic")) {
        const match = !needle || (topic.dataset.find || "").includes(needle);
        topic.hidden = !match;
        if (match) shown += 1;
      }
      // The glossary fold has no articles of its own, so it answers to the filter as a
      // whole: a search that matches nothing in it closes it rather than emptying it.
      const glossary = section.querySelector(".glossary-list");
      const glossaryOnly = glossary && !section.querySelector(".help-topic");
      const hit = glossaryOnly
        ? !needle || section.textContent.toLowerCase().includes(needle)
        : shown > 0;
      section.hidden = needle ? !hit : false;
      if (needle && hit) section.open = true;
      if (!needle) section.open = false;
      hits += glossaryOnly ? (hit ? 1 : 0) : shown;
    }
    status.textContent = needle
      ? (hits === 1 ? "1 page matches." : `${hits} pages match.`)
      : "";
  };

  field.addEventListener("input", run);
  el("help-index").addEventListener("click", (ev) => {
    const chip = ev.target.closest("[data-help-section]");
    if (!chip) return;
    openHelpSection(chip.dataset.helpSection);
  });
}

/** Open one fold and put it at the top of the screen. */
function openHelpSection(id) {
  const section = el(`help-${id}`);
  if (!section) return;
  section.open = true;
  section.scrollIntoView({ block: "start", behavior: "smooth" });
}

/** The Help page, arrived at by a deep link. `arg` is a topic id, or a section id, or
 *  nothing at all — a bookmark written before a topic was renamed must not blank the page,
 *  so an id that resolves to neither simply leaves the index on screen. */
function openHelpAt(arg) {
  if (!arg) return;
  const section = helpSectionOf(arg);
  if (section) {
    openHelpSection(section);
    const article = el(`help-topic-${arg}`);
    if (article) {
      article.scrollIntoView({ block: "start", behavior: "smooth" });
      // A found article says so for a beat. The phone pushes a screen; a fold that simply
      // scrolled would leave a reader wondering which of the ten paragraphs he asked for.
      article.classList.add("found");
      setTimeout(() => article.classList.remove("found"), 2000);
    }
    return;
  }
  openHelpSection(arg);
}

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
    // The phone's own sentence for this half of the tab (docs/screens.md, Gear & spots;
    // docs/web-design-review.md, finding 4). The wings half says "No wings yet" under it,
    // from js/gear.js, which is where the phone says it too.
    host.innerHTML = `<p class="note">No spots yet. A session with GPS brings them.</p>
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
  // How much every explanation says, and the `?` beside each one. After renderHelp, so the
  // catalogue a `?` deep-links into is already on the page; before the first route, so the
  // page a bookmark lands on is already wearing the reader's choice.
  mountExplain({ onOpenTopic: showHelpTopic });
  onSettingsChange(() => {
    if (current === "gear") renderGear().catch(() => {});
  });
  const { name, arg } = route(location.hash);
  showPage(name, arg);
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
  // "Where this lives" is Settings -> Your data now, so the Sessions tab has one thing to
  // say about its own library and says it in the count line (Jan, 20 September 2026).
}

/** Open the welcome once per browser, on a genuinely empty library. A reader with sessions
 *  has been through the front door already, whatever the flag says — the same evidence the
 *  phone's `WelcomePrompt` trusts. */
export function offerWelcome(sessionCount) {
  if (welcomeSeen() || sessionCount > 0) return;
  openWelcome();
}
