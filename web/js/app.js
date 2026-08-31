/* App shell: file intake (drag & drop / picker / intervals.icu), view routing, progress,
 * saving to the library, service-worker updates.
 *
 * All analysis and all aggregation happen in js/worker.js, behind js/rpc.js. This file
 * never touches a number — it moves bytes and toggles sections.
 */

import { mountIcu } from "./icu.js";
import { mountLibrary, openStoredSession, refresh as refreshLibrary, saveSession }
  from "./library.js";
import { closePopover, render, renderFigures, resetSession } from "./render.js";
import { CANCELLED, analyze as runAnalysis, cancel as cancelWorker, on, warmUp } from "./rpc.js";
import { mountSections, resetSections } from "./sections.js";
import { mountShareCard, openShareCard } from "./sharecard.js";
import { listEntries } from "./store.js";
import { invalidateTrends, mountTrends, redrawTrends, showTrends } from "./trends.js";

const el = (id) => document.getElementById(id);

const state = {
  busy: false,
  booted: false,
  last: null,          // the analysis document currently on screen
  lastDigest: null,    // its Python digest — what the library would store
  lastBytes: null,     // the original FIT bytes, kept so "save" needs no re-read
  fromLibrary: false,  // true when the document on screen came out of storage
  isExample: false,    // true when it came from the "try the example session" button
  highlight: null,     // the record window marked on the figures, if any
};

const VIEWS = ["analyze", "library", "trends"];

/* ----------------------------------------------------------------- worker events */

on("status", (msg) => setStep(msg.step, msg.state, msg.detail));

on("ready", (msg) => {
  state.booted = true;
  const chip = el("engine-chip");
  chip.hidden = false;
  chip.textContent = `engine ${msg.engineVersion} · pyodide ${msg.pyodideVersion}`;
});

// Errors that arrive without a request id (a failed boot) still have to reach the user.
on("result", (msg) => { if (msg.type === "error") fail(msg.message); });

function fail(message) {
  state.busy = false;
  stopClock();
  el("progress").hidden = true;
  el("error").hidden = false;
  el("error-text").textContent = message;
}

/* ----------------------------------------------------------------------- progress */

const STEPS = ["runtime", "engine", "parse", "analyze"];

function resetSteps() {
  for (const s of STEPS) {
    const li = document.querySelector(`#steps li[data-step="${s}"]`);
    li.dataset.state = state.booted && (s === "runtime" || s === "engine") ? "done" : "";
    setDetail(li, "");
  }
  el("progress-note").hidden = state.booted;
}

/** The step rows carry a clock inside their detail cell, so replacing the detail text has
 *  to leave the clock element alone. One helper, so no caller can forget. */
function setDetail(li, text) {
  const cell = li.querySelector(".detail");
  const clock = cell.querySelector(".elapsed");
  cell.textContent = text || "";
  if (clock) cell.appendChild(clock);
}

function setStep(step, stateName, detail) {
  const li = document.querySelector(`#steps li[data-step="${step}"]`);
  if (!li) return;
  li.dataset.state = stateName;
  setDetail(li, detail);
}

/* ------------------------------------------------------------------ elapsed + cancel */

/**
 * A running clock on the analysis, and a way out of it.
 *
 * The measured failure this fixes: a 6 MB CIQ fixture spent over nine minutes on
 * "Analyzing" behind a card that showed a file size where progress should be, with no
 * elapsed time and no cancel (app-ui-review.md §7.3). Neither of those is a progress bar —
 * the engine genuinely cannot say how far through a FIT it is — but a number that visibly
 * increments is the difference between "this is slow" and "this has hung", and it is the
 * one honest thing the page can show.
 *
 * The clock is `mm:ss` and it lives in the *active* step's detail cell, so it moves down
 * the list with the work and never claims to be timing something that finished.
 */
let clockTimer = 0;
let clockStart = 0;

function startClock() {
  clockStart = Date.now();
  const clock = el("elapsed");
  clock.hidden = false;
  clock.textContent = "0:00";
  clearInterval(clockTimer);
  // 1 s is the resolution of what it displays; anything faster is work for no pixels.
  clockTimer = setInterval(() => {
    const s = Math.floor((Date.now() - clockStart) / 1000);
    clock.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }, 1000);
  el("cancel-analysis").hidden = false;
  el("cancel-analysis").disabled = false;
  el("progress-expect").hidden = false;
}

function stopClock() {
  clearInterval(clockTimer);
  clockTimer = 0;
  el("elapsed").hidden = true;
  el("cancel-analysis").hidden = true;
  el("progress-expect").hidden = true;
}

/**
 * Cancel: kill the worker, put the page back where it was before the drop.
 *
 * The worker cannot be interrupted politely mid-analysis (see `rpc.cancel`), so it is
 * terminated and replaced. That throws the booted runtime away with it, which is why the
 * engine chip goes and `booted` goes false — the next analysis re-boots Pyodide, from
 * cache, in seconds. Saying so beats letting the next run look mysteriously slow.
 */
function wireCancel() {
  el("cancel-analysis").addEventListener("click", () => {
    const button = el("cancel-analysis");
    button.disabled = true;
    button.textContent = "Cancelling…";
    cancelWorker();
    state.busy = false;
    state.booted = false;
    el("engine-chip").hidden = true;
    stopClock();
    button.textContent = "Cancel";
    el("progress").hidden = true;
    el("dropzone").classList.remove("compact");
    // Re-boot in the background so the *next* file does not pay for this cancel.
    warmUp();
  });
}

/* -------------------------------------------------------------------- the report */

/** Put an analysis document on screen. `highlight` marks a record window; see render.js. */
function showResult(result, { digest = null, bytes = null, fromLibrary = false,
                             isExample = false, highlight = null } = {}) {
  state.last = result;
  state.lastDigest = digest;
  state.lastBytes = bytes;
  state.fromLibrary = fromLibrary;
  state.isExample = isExample;
  state.highlight = highlight;

  stopClock();
  el("progress").hidden = true;
  el("error").hidden = true;
  el("results").hidden = false;
  el("dropzone").classList.add("compact");
  // Before render(), not after: below 760 px the switcher hides every panel but the active
  // section's, and a figure measured inside a hidden panel falls back to the 1100-unit
  // maximum instead of its column (js/viz.js `figureWidth`). Resetting first means the
  // Track and Speed panels are on screen when render() draws into them. A new document
  // also starts on Map · Speed the way a new session view starts unzoomed.
  resetSections();
  render(result, { highlight });
  updateSaveButton();
  showHighlightNote(highlight);
  showView("analyze");
  window.scrollTo({ top: el("results").offsetTop - 70, behavior: "smooth" });
}

function showHighlightNote(highlight) {
  const note = el("highlight-note");
  note.hidden = !highlight;
  if (!highlight) return;
  const many = highlight.windows.length > 1 ? ` (${highlight.windows.length} windows)` : "";
  const value = highlight.value === undefined ? ""
    : ` — ${highlight.value} ${highlight.unit ?? ""}`.trimEnd();
  note.innerHTML = `Showing <strong>${highlight.label}</strong>${value}${many} — the window
    is marked in orange on the track and on the speed strip.
    <button class="ghost small-btn" id="clear-highlight" type="button">Clear</button>`;
  el("clear-highlight").addEventListener("click", () => {
    showResult(state.last, { digest: state.lastDigest, bytes: state.lastBytes,
                             fromLibrary: state.fromLibrary, isExample: state.isExample });
  });
}

function updateSaveButton() {
  // The share card needs an analysis and nothing else — not a save, not a library entry —
  // so it appears the moment a document is on screen, including the bundled example.
  el("share-card").hidden = !state.last;

  const button = el("save-session");
  button.hidden = false;
  button.disabled = false;
  if (state.fromLibrary) {
    button.textContent = "Already in the library";
    button.disabled = true;
  } else if (!state.lastDigest || !state.lastBytes) {
    button.hidden = true;                       // nothing to store (should not happen)
  } else {
    button.textContent = "Save to library";
  }
}

/* --------------------------------------------------------------------- the intake */

/**
 * Analyze one dropped/picked/fetched file.
 *
 * `isExample` is the *only* thing the intake knows about a file that the file itself
 * cannot say, and it is passed rather than sniffed from the name: a visitor who renames
 * their own FIT to the example's name must not have it silently excluded from their
 * records, and the example must not count in them.
 */
export async function analyzeFile(file, { isExample = false } = {}) {
  if (state.busy) return;
  const name = file.name || "session.fit";
  if (!/\.(fit|zip)$/i.test(name)) {
    fail(`"${name}" is not a .fit or .zip file.`);
    return;
  }
  state.busy = true;
  el("error").hidden = true;
  el("results").hidden = true;
  // The session view is being torn down: drop the previous document's playhead, zoom,
  // chip states and popover with it, and let its sample arrays go before the next FIT
  // arrives — on a phone the two documents would otherwise be in memory at once.
  resetSession();
  el("progress").hidden = false;
  resetSteps();
  startClock();
  showView("analyze");

  const buffer = await file.arrayBuffer();
  // The worker takes ownership of `buffer` (transferred, so a 6 MB FIT is not copied to
  // get there); this copy is what "Save to library" writes back out.
  const keep = buffer.slice(0);
  try {
    const msg = await runAnalysis(buffer, name);
    state.busy = false;
    showResult(JSON.parse(msg.json),
               { digest: JSON.parse(msg.digestJson), bytes: keep, isExample });
  } catch (err) {
    // A cancel is the user getting what they asked for, not a failure: the Cancel handler
    // has already put the page back, and an "That didn't work" panel on top of it would
    // be the app arguing with them.
    if (err.message === CANCELLED) return;
    fail(err.message);
  }
}

/** Analyze a FIT another module (icu.js) already downloaded. */
export function analyzeBuffer(buffer, name) {
  return analyzeFile(new File([buffer], name));
}

function wireDropzone() {
  const zone = el("dropzone");
  const stop = (ev) => { ev.preventDefault(); ev.stopPropagation(); };

  for (const type of ["dragenter", "dragover"]) {
    zone.addEventListener(type, (ev) => { stop(ev); zone.classList.add("hot"); });
  }
  for (const type of ["dragleave", "dragend"]) {
    zone.addEventListener(type, (ev) => { stop(ev); zone.classList.remove("hot"); });
  }
  zone.addEventListener("drop", (ev) => {
    stop(ev);
    zone.classList.remove("hot");
    const file = ev.dataTransfer?.files?.[0];
    if (file) analyzeFile(file);
  });
  // Dropping anywhere else must not navigate away from the page.
  for (const type of ["dragover", "drop"]) {
    window.addEventListener(type, (ev) => { if (ev.target !== zone) ev.preventDefault(); });
  }

  // The whole zone is a shortcut to the picker, but the <label> and the <input> activate it
  // themselves — clicking through to `file.click()` as well would open the picker twice.
  zone.addEventListener("click", (ev) => {
    if (ev.target.closest("button, label, input")) return;
    el("file").click();
  });
  zone.addEventListener("keydown", (ev) => {
    if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); el("file").click(); }
  });
  el("file").addEventListener("change", (ev) => {
    const file = ev.target.files?.[0];
    if (file) analyzeFile(file);
    ev.target.value = "";
  });
}

/**
 * "…or try the example session".
 *
 * The same bundled recording the iOS app ships (`web/example/ExampleSession.fit`, byte for
 * byte the file in `ios/WingFoilKit/…/Resources/`): Jan's 2026-08-30 Nago-Torbole
 * afternoon with the identifiers scrubbed and nothing else touched. It is a ten-minute
 * ride, which is what lets the whole recording ship at 942 KB — 100 Hz accelerometer
 * stream included — so the demo shows the stroke counts and the failed attempts a
 * stripped file could only report as unknown.
 *
 * It goes through `analyzeFile`, so it is the ordinary path with an ordinary File: nothing
 * about the example is special-cased in the ANALYSIS, and what a visitor sees is what
 * their own file will do.
 *
 * The one thing that is special-cased is what happens if it is saved. Somebody else's
 * afternoon in the library would otherwise set the visitor's all-time records and bend
 * every trend line, which is the same defect the iOS app fixed with the EXAMPLE badge and
 * its exclusion. So the flag rides along to `saveSession`, which stores it on the entry —
 * and, unlike a friend's file, the example is never asked about: there is only one
 * possible answer to "whose session is this?" for a recording nobody here rode.
 */
function wireExample() {
  el("try-example").addEventListener("click", async () => {
    const button = el("try-example");
    if (state.busy) return;
    button.disabled = true;
    try {
      // Resolved against this module, not against the document: the page lives at /app/
      // while the example (like css/, icons/ and lab_bundle/) stays at the site root,
      // shared with the homepage. js/worker.js reaches lab_bundle/ the same way.
      const url = new URL("../example/ExampleSession.fit", import.meta.url);
      const res = await fetch(url);
      if (!res.ok) throw new Error(`example/ExampleSession.fit: HTTP ${res.status}`);
      await analyzeFile(new File([await res.arrayBuffer()],
                                 "example-nago-torbole-2026-08-30.fit"),
                        { isExample: true });
    } catch (err) {
      fail(`Could not load the example session: ${err.message}`);
    } finally {
      button.disabled = false;
    }
  });
}

function wireDownload() {
  el("download-json").addEventListener("click", () => {
    if (!state.last) return;
    const blob = new Blob([JSON.stringify(state.last, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${state.last.file.name.replace(/\.(fit|zip)$/i, "")}.analysis.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  });
}

/* --------------------------------------------------------------------- share card */

function wireShareCard() {
  mountShareCard();
  el("share-card").addEventListener("click", () => openShareCard(state.last));
}

/* ----------------------------------------------------------------------- library */

function wireSave() {
  el("save-session").addEventListener("click", async () => {
    const button = el("save-session");
    if (!state.lastDigest || !state.lastBytes) return;
    button.disabled = true;
    button.textContent = "Saving…";
    try {
      // `saveSession` may put a question on screen first ("Whose session is this?", and
      // for a duplicate, "replace it?"). Both can be answered no, and both come back as
      // `saved: false` — the button goes back to offering the save rather than claiming one.
      const outcome = await saveSession({
        digest: state.lastDigest,
        analysisJson: JSON.stringify(state.last),
        fitBytes: state.lastBytes,
        example: state.isExample,
      });
      if (outcome.saved) {
        invalidateTrends();
        state.fromLibrary = true;
        button.textContent = outcome.replaced ? "Replaced in the library" : "Saved";
      } else {
        button.textContent = "Save to library";
        button.disabled = false;
      }
    } catch (err) {
      button.textContent = "Save to library";
      button.disabled = false;
      fail(`Could not save this session: ${err.message}`);
    }
  });
}

/** Open a stored session, optionally with one of its records marked. */
async function openStored(id, record = null) {
  try {
    const highlight = record
      // The label is the record's own ("Best 2 s"), because it is also the legend chip's
      // text and the chip names the *window*, not its value (the iOS chip reads the same).
      // The value travels beside it, for the note and for the band's popover.
      ? { label: record.label, value: record.value, unit: record.unit,
          windows: record.windows }
      : null;
    showResult(await openStoredSession(id), { fromLibrary: true, highlight });
  } catch (err) {
    fail(err.message);
  }
}

/* -------------------------------------------------------------------- view routing */

function showView(name) {
  const view = VIEWS.includes(name) ? name : "analyze";
  // A marker popover is a fixed-position child of <body>, not of the session panel, so
  // hiding the analyze view would leave it floating over the library. It belongs to the
  // figure that opened it; when that figure goes off screen, so does it.
  closePopover();
  for (const v of VIEWS) {
    el(`view-${v}`).hidden = v !== view;
    const tab = document.querySelector(`.views button[data-view="${v}"]`);
    tab.setAttribute("aria-current", v === view ? "page" : "false");
  }
  if (location.hash !== `#/${view}`) history.replaceState(null, "", `#/${view}`);
  if (view === "trends") listEntries().then(showTrends).catch(() => showTrends([]));
  if (view === "library") refreshLibrary();
}

function wireNav() {
  for (const button of document.querySelectorAll(".views button[data-view]")) {
    button.addEventListener("click", () => showView(button.dataset.view));
  }
  window.addEventListener("hashchange", () => showView(location.hash.replace("#/", "")));
}

/* ------------------------------------------------------------- service worker / PWA */

/**
 * Register the service worker and surface updates instead of applying them behind the
 * user's back: a swap mid-analysis would reload the page and throw the result away. The
 * new worker waits until "Reload" is pressed.
 */
function wireServiceWorker() {
  if (!("serviceWorker" in navigator)) return;
  const banner = el("update-banner");

  // `sw.js` stays at the site ROOT even though the page is at /app/, and that placement is
  // the point: a worker's default scope is its own directory, so a root script controls the
  // homepage and the analyzer with one registration and one cache. The URL is resolved
  // against this module (js/ is at the root too) rather than against the document, so the
  // page can move again without moving the scope with it.
  navigator.serviceWorker.register(new URL("../sw.js", import.meta.url)).then((reg) => {
    const offer = (worker) => {
      if (!worker) return;
      worker.addEventListener("statechange", () => {
        if (worker.state === "installed" && navigator.serviceWorker.controller) {
          banner.hidden = false;
          el("update-reload").onclick = () => {
            el("update-reload").disabled = true;
            worker.postMessage({ type: "skipWaiting" });
          };
        }
      });
    };
    if (reg.waiting && navigator.serviceWorker.controller) {
      banner.hidden = false;
      el("update-reload").onclick = () => {
        el("update-reload").disabled = true;
        reg.waiting.postMessage({ type: "skipWaiting" });
      };
    }
    reg.addEventListener("updatefound", () => offer(reg.installing));
  }).catch(() => { /* offline support is a bonus; never break the page over it */ });

  let reloading = false;
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (reloading) return;
    reloading = true;
    location.reload();
  });

  el("update-dismiss").addEventListener("click", () => { banner.hidden = true; });
}

/* ------------------------------------------------------------------- reflow */

/**
 * The figures are drawn at their container's real CSS width so their type stays at its
 * stated size instead of being shrunk by a viewBox (a 1100-unit chart in a 350 px slot
 * renders 10.5 px axis labels at 3.3 px). That makes them width-dependent, so a rotation
 * or a window resize has to redraw them. Debounced, and only past a width that actually
 * changes the layout — a Safari toolbar collapsing must not repaint the page.
 */
function wireReflow() {
  let width = document.documentElement.clientWidth;
  let timer = 0;
  window.addEventListener("resize", () => {
    const now = document.documentElement.clientWidth;
    if (Math.abs(now - width) < 40) return;
    width = now;
    clearTimeout(timer);
    timer = setTimeout(() => {
      if (state.last && !el("results").hidden && !el("view-analyze").hidden) {
        render(state.last, { highlight: state.highlight });
      }
      if (!el("view-trends").hidden) redrawTrends();
    }, 180);
  });
}

/* ------------------------------------------------------------------ sections */

/**
 * The narrow-viewport section switcher (app-ui-review.md §3.4 / §7.2). js/sections.js owns
 * the chips and which panels are on screen; this is the one thing it cannot do for itself —
 * put the figures back at their real width when a chip reveals them.
 *
 * `renderFigures` rather than the whole-report `render()`, and not because `render()` would
 * lose anything: `renderFigures` clears the playhead, the zoom, the camera and the chip
 * states only when the document IDENTITY changes, and a chip tap passes the same object, so
 * either call keeps the playhead the user set. It is that `render()` rebuilds a 34-row and
 * a 23-row table, plus every tile, to fix two SVGs — work for no pixels on the device with
 * the least of it to spare. The guards are the same ones `wireReflow` uses, so a chip tap
 * with no document loaded (impossible today, `#results` is hidden, but cheap to promise)
 * does nothing rather than throwing.
 */
function wireSections() {
  mountSections({
    redrawFigures: () => {
      if (state.last && !el("results").hidden && !el("view-analyze").hidden) {
        renderFigures(state.last, state.highlight);
      }
    },
  });
}

/* --------------------------------------------------------------------------- go */

wireDropzone();
wireExample();
wireCancel();
wireDownload();
wireSave();
wireShareCard();
wireNav();
wireSections();
wireReflow();
wireServiceWorker();
mountIcu({ analyzeBuffer });
mountTrends({
  openSession: (id) => openStored(id),
  openRecord: (record) => openStored(record.id, record),
});
// The library lists and stores; opening comes back through `openStored` so there is one
// code path for "a document is on screen", whether it arrived by drop or from disk.
mountLibrary({
  onOpen: (id) => openStored(id),
  setCount: (n) => {
    const chip = document.querySelector('.views button[data-view="library"] .count');
    chip.textContent = n ? String(n) : "";
    chip.hidden = !n;
  },
});

showView(location.hash.replace("#/", ""));
warmUp();
