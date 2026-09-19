/* App shell: file intake (drag & drop / picker / intervals.icu), view routing, progress,
 * saving to the library, service-worker updates.
 *
 * All analysis and all aggregation happen in js/worker.js, behind js/rpc.js. This file
 * never touches a number — it moves bytes and toggles sections.
 */

import { mountShell, noteEngine, offerWelcome, setSessionCount, showPage }
  from "./appshell.js";
import { WHATS_NEW } from "./appcopy.js";
import { mountIcu } from "./icu.js";
import { mountLibrary, openStoredSession, refresh as refreshLibrary, saveSession }
  from "./library.js";
import { closePopover, render, renderFigures, renderGlossary, resetSession } from "./render.js";
import { CANCELLED, analyze as runAnalysis, cancel as cancelWorker, on, warmUp } from "./rpc.js";
import { mountSections, resetSections } from "./sections.js";
import { mountShareCard, openPeriodCard, openShareCard } from "./sharecard.js";
import { listEntries } from "./store.js";
import { track } from "./track.js";
import { invalidateTrends, mountTrends, redrawTrends, showTrends } from "./trends.js";
// r3-w1: the four screens the port was missing — the Log tab's gear card and its
// watch-against-phone block, the quiver's editor, Deleted sessions, Restore from a backup,
// and the range over the charts. Each is its own file; these are the wires.
import { mountBackup } from "./backup.js";
import { mountRange } from "./daterange.js";
import { mountDeleted } from "./deleted.js";
import { mountGear, onGearChange } from "./gear.js";
import { refreshLog, showLog } from "./log.js";

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
  // r3-w1: the library id of the document on screen, or null while it is only analysed.
  // The Log tab's gear card hangs an assignment on it, and there is nothing to hang one
  // on until the session has been saved.
  sessionId: null,
};

/* The four tabs and the pages behind the menu are js/appshell.js's; this file moves bytes
 * and toggles sections, and asks the shell to show a page when a document lands. */

/* ----------------------------------------------------------------- worker events */

on("status", (msg) => setStep(msg.step, msg.state, msg.detail));

on("ready", (msg) => {
  state.booted = true;
  const chip = el("engine-chip");
  chip.hidden = false;
  chip.textContent = `engine ${msg.engineVersion} · pyodide ${msg.pyodideVersion}`;
  // Settings → About prints what is actually running rather than what the bundle claims.
  noteEngine({ engineVersion: msg.engineVersion, pyodideVersion: msg.pyodideVersion });
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
                             isExample = false, highlight = null,
                             sessionId = null } = {}) {
  state.sessionId = sessionId;                                             // r3-w1
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
  // BOTH BEFORE render(), and in this order. A figure measured inside a hidden element
  // falls back to the 1100-unit maximum instead of its column (js/viz.js `figureWidth`),
  // so the track would land in a 400 px column at a third of the type size it was tuned
  // at. The session is a page of its own now — the way the phone pushes
  // `SessionDetailView` off the library list — so the page has to be on screen first, and
  // then the switcher has to put Ride's panels back on it. A new document also starts on
  // Ride the way a new session view starts unzoomed.
  showPage("session");
  resetSections();
  render(result, { highlight, isExample });
  // r3-w1: the Log tab's two blocks. The gear card needs the library id; the
  // watch-against-phone table needs only the document, and is absent without one.
  showLog(result, sessionId);
  updateSaveButton();
  showHighlightNote(highlight);
  window.scrollTo({ top: 0, behavior: "smooth" });
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
                             fromLibrary: state.fromLibrary, isExample: state.isExample,
                             sessionId: state.sessionId });                // r3-w1
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
 *
 * `source` is the class of door the bytes came through — drop, picker, example, shared,
 * icu — and it exists for the counter and for nothing else (docs/analytics.md). It is a
 * fixed word from a closed set, never anything off the file: the question it answers is
 * which way in a visitor actually uses, which decides which way in is worth building next.
 */
export async function analyzeFile(file, { isExample = false, source = "drop" } = {}) {
  if (state.busy) return;
  const name = file.name || "session.fit";
  const format = (/\.(fit|gpx|tcx|zip)$/i.exec(name)?.[1] || "other").toLowerCase();
  if (!/\.(fit|gpx|tcx|zip)$/i.test(name)) {
    // The turn-away is counted too, and it is the one number on this page that can change
    // what the engine reads next: a run of rejections is riders arriving with a format
    // CleanJibe does not take. The extension only, never the name.
    track("app-file-rejected", { source });
    // Say what to bring instead. The rejection states the rule *and* the way out: since
    // engine 0.9.0 a GPX is a way out, and a TCX now too — so the formats people used to be
    // turned away with are offered here instead, with their limits named, because a rider
    // who brings one should learn what it costs here rather than from a missing section.
    fail(`"${name}" is not a .fit, .gpx, .tcx or .zip file. CleanJibe reads the .fit file ` +
         `a watch records — from the CleanJibe watch app, Garmin's own Windsurf profile, ` +
         `or another wingfoil Connect IQ app. A .gpx or .tcx works too: no pump data, and ` +
         `unless the file carries its own speed channel the speed records are estimates.`);
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
  // The progress card lives on Sessions, where the file was dropped. The reader watches it
  // there and is moved to the session page only when there is a session to show.
  showPage("sessions");

  const buffer = await file.arrayBuffer();
  // The worker takes ownership of `buffer` (transferred, so a 6 MB FIT is not copied to
  // get there); this copy is what "Save to library" writes back out.
  const keep = buffer.slice(0);
  try {
    const msg = await runAnalysis(buffer, name);
    state.busy = false;
    showResult(JSON.parse(msg.json),
               { digest: JSON.parse(msg.digestJson), bytes: keep, isExample });
    // Counted here and nowhere earlier: the question worth answering is how many sessions
    // the analyzer actually finished, not how many files were picked — a FIT that failed to
    // parse is not a conversion. Two properties travel with it and no third is allowed: the
    // file EXTENSION and the class of door it came through. Never the name, the size, the
    // date or a number out of the session. js/track.js is the guard — the umami script is
    // third-party and absent for a good share of real visitors, and the analyzer must not
    // care either way.
    track("app-file-analyzed", { format, source });
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
  return analyzeFile(new File([buffer], name), { source: "icu" });
}

/* ------------------------------------------------- Android's share sheet (issue #9) */

/**
 * Collect the file Android's share sheet handed to the service worker.
 *
 * The whole mechanism is in `sw.js` ("Android's share sheet"): a POST cannot pass a File to
 * a page, so the worker parks it in a cache under one fixed key and redirects here with
 * `?shared=1`. This reads the key, empties it, and hands back a real `File` for the same
 * intake a drop or a picker uses — no second code path for a session that arrived by
 * sharing.
 *
 * Every failure returns null and the analyzer simply shows its drop zone, which is where a
 * rider would have gone anyway. `caches` is absent in a private window in some engines, and
 * this must not be the line that stops the page booting.
 */
const SHARE_CACHE = "wingfoil-share";

async function takeSharedFile() {
  if (!("caches" in window)) return null;
  // The same absolute URL `sw.js` parked it under: the worker built it from the app dir, the
  // page builds it from its own location, and both land on <origin>/app/__shared__.
  const key = new URL("__shared__", location.href).href;
  try {
    const cache = await caches.open(SHARE_CACHE);
    const res = await cache.match(key);
    if (!res) return null;
    await cache.delete(key);
    const name = decodeURIComponent(res.headers.get("x-shared-name") || "") || "session.fit";
    return new File([await res.blob()], name);
  } catch {
    return null;
  }
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
    if (file) analyzeFile(file, { source: "drop" });
  });
  // Dropping anywhere else must not navigate away from the page.
  for (const type of ["dragover", "drop"]) {
    window.addEventListener(type, (ev) => { if (ev.target !== zone) ev.preventDefault(); });
  }

  // The whole zone is a shortcut to the picker, but the <label> and the <input> activate it
  // themselves — clicking through to `file.click()` as well would open the picker twice.
  // `a` joined the list when the zone became the ways-in card: five of its rows are links
  // to a route on /start/, and a link that also opened a file picker on its way out would
  // be the worst control on the page.
  zone.addEventListener("click", (ev) => {
    if (ev.target.closest("a, button, label, input")) return;
    el("file").click();
  });
  zone.addEventListener("keydown", (ev) => {
    // Same guard as the click above, for the same reason: Enter on a row's link is that
    // link's, and it bubbles to the zone.
    if (ev.target.closest("a, button, label, input")) return;
    if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); el("file").click(); }
  });
  el("file").addEventListener("change", (ev) => {
    const file = ev.target.files?.[0];
    if (file) analyzeFile(file, { source: "picker" });
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
/** Every control that means "run the bundled session": the link in the dropzone and each
 *  of the three preview thumbnails beside it. They all disable together while it runs, so
 *  a second press cannot queue a second analysis behind the first. */
const exampleTriggers = () =>
  [...document.querySelectorAll("#try-example, .drop-peek [data-example]")];

async function runExample() {
  if (state.busy) return;
  const buttons = exampleTriggers();
  for (const b of buttons) b.disabled = true;
  // The PRESS, counted where it happens; the finished analysis is counted again in
  // `analyzeFile` as `source: "example"`. Two events rather than one because the gap
  // between them is the whole question: a visitor who taps the example and never sees a
  // report waited out a 12 MB runtime download and left.
  track("app-example-loaded");
  try {
    // Resolved against this module, not against the document: the page lives at /app/
    // while the example (like css/, icons/ and lab_bundle/) stays at the site root,
    // shared with the homepage. js/worker.js reaches lab_bundle/ the same way.
    const url = new URL("../example/ExampleSession.fit", import.meta.url);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`example/ExampleSession.fit: HTTP ${res.status}`);
    await analyzeFile(new File([await res.arrayBuffer()],
                               "example-nago-torbole-2026-08-30.fit"),
                      { isExample: true, source: "example" });
  } catch (err) {
    fail(`Could not load the example session: ${err.message}`);
  } finally {
    for (const b of buttons) b.disabled = false;
  }
}

function wireExample() {
  for (const b of exampleTriggers()) b.addEventListener("click", runExample);
}

function wireDownload() {
  el("download-json").addEventListener("click", () => {
    if (!state.last) return;
    const blob = new Blob([JSON.stringify(state.last, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${state.last.file.name.replace(/\.(fit|gpx|tcx|zip)$/i, "")}.analysis.json`;
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
        // r3-w1: the session now has a row, so the gear card has something to write on.
        state.sessionId = outcome.entry?.id ?? null;
        showLog(state.last, state.sessionId);
        button.textContent = outcome.replaced ? "Replaced in the library" : "Saved";
        // After the write, and only on `saved` — the two questions `saveSession` can ask
        // ("whose session is this?", "replace it?") both have a No that lands here as
        // `saved: false`, and a cancelled save is not a save.
        track("app-session-saved", { replaced: !!outcome.replaced });
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

/** Open a stored session, optionally with one of its records marked. `from` is the class of
 *  row that opened it — the library list, a record row, a trend dot — and travels to the
 *  counter and nowhere else (docs/analytics.md). It is never the session's id. */
async function openStored(id, record = null, from = "library") {
  track("app-session-opened", { from });
  try {
    const highlight = record
      // The label is the record's own ("Best 2 s"), because it is also the legend chip's
      // text and the chip names the *window*, not its value (the iOS chip reads the same).
      // The value travels beside it, for the note and for the band's popover.
      ? { label: record.label, value: record.value, unit: record.unit,
          windows: record.windows }
      : null;
    // The example keeps its badge when it is reopened from the library, not only when it
    // is first analyzed: the list says EXAMPLE beside it, and the report has to agree.
    const entry = (await listEntries()).find((e) => e.id === id);
    showResult(await openStoredSession(id),
               { fromLibrary: true, highlight, isExample: !!entry?.example,
                 sessionId: id });                                         // r3-w1
  } catch (err) {
    fail(err.message);
  }
}

/* -------------------------------------------------------------------- page routing */

/**
 * What a page needs the moment it appears. js/appshell.js owns which page is on screen; it
 * calls this so the two files do not both have to know that Records and Trends read one
 * aggregate and the Sessions list reads the index.
 *
 * A marker popover is a fixed-position child of <body>, not of the session panel, so a page
 * change has to close it: it belongs to the figure that opened it, and when that figure
 * goes off screen so does it.
 */
function onShowPage(page) {
  closePopover();
  if (page === "records" || page === "trends") {
    listEntries().then(showTrends).catch(() => showTrends([]));
  }
  if (page === "sessions") refreshLibrary();
}

/* ------------------------------------------------------------- service worker / PWA */

/**
 * Register the service worker and surface updates instead of applying them behind the
 * user's back: a swap mid-analysis would reload the page and throw the result away. The
 * new worker waits until "Reload" is pressed.
 */
/** *Later* on the update banner, remembered for the build it was said about.
 *
 * It only set `hidden`, so the bar came back on every reload and the rider said no to the
 * same version all afternoon (docs/web-design-review.md, finding 6). The key carries the
 * version it was dismissed at, so the NEXT update asks again. In try/catch throughout: a
 * preference that cannot be read must never be the reason a page misbehaves, which is the
 * contract the install banner in web/app/index.html already keeps. */
const UPDATE_DISMISS_KEY = "cleanjibe.update.dismissed";

function updateDismissed(tag) {
  try {
    return localStorage.getItem(UPDATE_DISMISS_KEY) === tag;
  } catch { return false; }
}

function rememberUpdateDismissed(tag) {
  try {
    localStorage.setItem(UPDATE_DISMISS_KEY, tag);
  } catch { /* private window: offer it again */ }
}

function wireServiceWorker() {
  if (!("serviceWorker" in navigator)) return;
  const banner = el("update-banner");
  // WHICH BUILD THE RIDER SAID *Later* ON. The worker's script URL never changes, so it
  // cannot be the key; the build that is running while the offer is made can, and it is
  // the one fact that moves when the update is finally taken.
  const tag = () => String(WHATS_NEW[0]?.version || "unknown");

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
          banner.hidden = updateDismissed(tag());
          el("update-reload").onclick = () => {
            el("update-reload").disabled = true;
            worker.postMessage({ type: "skipWaiting" });
          };
        }
      });
    };
    if (reg.waiting && navigator.serviceWorker.controller) {
      banner.hidden = updateDismissed(tag());
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

  el("update-dismiss").addEventListener("click", () => {
    banner.hidden = true;
    rememberUpdateDismissed(tag());
  });
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
      if (state.last && !el("results").hidden && !el("page-session").hidden) {
        render(state.last, { highlight: state.highlight, isExample: state.isExample });
      }
      if (!el("page-trends").hidden || !el("page-records").hidden) redrawTrends();
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
      if (state.last && !el("results").hidden && !el("page-session").hidden) {
        renderFigures(state.last, state.highlight);
      }
    },
  });
}

/* --------------------------------------------------------------------------- go */

wireDropzone();
wireExample();
// The `?` beside the key-metrics block: eight fixed lines out of docs/copy, so they are
// written once at boot rather than rebuilt with every document (js/render.js).
renderGlossary();
wireCancel();
wireDownload();
wireSave();
wireShareCard();
wireSections();
wireReflow();
wireServiceWorker();
// r3-w1 · the ported screens. Each wires its own markup and owns its own storage; the
// callbacks below are the one thing they share, which is that the library changed.
mountGear();
mountDeleted({ onChanged: async () => { invalidateTrends(); await refreshLibrary(); } });
mountBackup({ onChanged: async () => { invalidateTrends(); await refreshLibrary(); } });
mountRange({
  onChange: () => listEntries().then(showTrends).catch(() => showTrends([])),
});
// A wing added from the session page belongs in that session's picker straight away, and
// in the quiver on the Gear tab when the reader gets there.
onGearChange(() => refreshLog());
mountIcu({ analyzeBuffer });
mountTrends({
  openSession: (id) => openStored(id, null, "trend"),
  openRecord: (record) => openStored(record.id, record, "record"),
  // The period card opens the same composer the session card does — same shapes, same
  // footer, same export — with a week's block on it instead of an afternoon's.
  openPeriodCard: (period, entries) => { if (period) openPeriodCard(period, entries); },
});
// The library lists and stores; opening comes back through `openStored` so there is one
// code path for "a document is on screen", whether it arrived by drop or from disk.
mountLibrary({
  onOpen: (id) => openStored(id, null, "library"),
  // The count on the Sessions tab, and which half of that tab is on screen — the ways-in
  // card or the list. js/appshell.js owns both, because they are one fact.
  setCount: (n) => {
    setSessionCount(n);
    // Once per browser, and never in front of somebody who already has sessions. The
    // library arriving is what settles that, which is why the offer is made from here and
    // not at boot — the same reason `RootView` waits on `libraryGeneration`.
    offerWelcome(n);
  },
});

// `/app/#example` runs the bundled session on arrival. The homepage's second CTA points
// here, and a link that promised an example and delivered a drop target would be the
// worst version of this page's first impression. Read BEFORE the shell mounts, which
// normalizes the hash to `#/sessions` on its way past.
const openExampleOnLoad = location.hash === "#example";
// `?shared=1` is the service worker saying "Android handed us a file". Read BEFORE the
// shell mounts for the same reason as the hash above, and cleared from the address bar
// straight away: a reload of this URL with the slot already emptied would otherwise look
// like a lost file.
const openSharedOnLoad = new URLSearchParams(location.search).get("shared") === "1";
mountShell({
  onShowPage,
  onExample: runExample,
  // Start over reloads the page, so nothing this file is holding may survive it.
  onStartOver: async () => { invalidateTrends(); },
});
warmUp();
if (openExampleOnLoad) runExample();
if (openSharedOnLoad) {
  history.replaceState(null, "", location.pathname + location.hash);
  takeSharedFile().then((file) => {
    if (!file) {
      // The slot was empty: the worker never parked a file, or a reload spent it. The
      // page used to call nothing and say nothing, and the rider landed on an untouched
      // Sessions tab (pattern G; docs/web-design-review.md, finding 18).
      el("shared-note").hidden = false;
      return;
    }
    // Android's share sheet handed CleanJibe a session. Counted on its own because the
    // whole mechanism is invisible from here otherwise: the POST never reaches a server,
    // so the only evidence the share target works at all is this line.
    track("app-shared-file-taken");
    analyzeFile(file, { source: "shared" });
  });
}
