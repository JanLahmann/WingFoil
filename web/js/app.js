/* App shell: file intake (drag & drop / picker / intervals.icu), view routing, progress,
 * saving to the library, service-worker updates.
 *
 * All analysis and all aggregation happen in js/worker.js, behind js/rpc.js. This file
 * never touches a number — it moves bytes and toggles sections.
 */

import { mountIcu } from "./icu.js";
import { mountLibrary, openStoredSession, refresh as refreshLibrary, saveSession }
  from "./library.js";
import { render } from "./render.js";
import { analyze as runAnalysis, on, warmUp } from "./rpc.js";
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
    li.querySelector(".detail").textContent = "";
  }
  el("progress-note").hidden = state.booted;
}

function setStep(step, stateName, detail) {
  const li = document.querySelector(`#steps li[data-step="${step}"]`);
  if (!li) return;
  li.dataset.state = stateName;
  li.querySelector(".detail").textContent = detail || "";
}

/* -------------------------------------------------------------------- the report */

/** Put an analysis document on screen. `highlight` marks a record window; see render.js. */
function showResult(result, { digest = null, bytes = null, fromLibrary = false,
                             highlight = null } = {}) {
  state.last = result;
  state.lastDigest = digest;
  state.lastBytes = bytes;
  state.fromLibrary = fromLibrary;
  state.highlight = highlight;

  el("progress").hidden = true;
  el("error").hidden = true;
  el("results").hidden = false;
  el("dropzone").classList.add("compact");
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
  note.innerHTML = `Showing <strong>${highlight.label}</strong>${many} — the window is
    marked in white on the track and on the speed strip.
    <button class="ghost small-btn" id="clear-highlight" type="button">Clear</button>`;
  el("clear-highlight").addEventListener("click", () => {
    showResult(state.last, { digest: state.lastDigest, bytes: state.lastBytes,
                             fromLibrary: state.fromLibrary });
  });
}

function updateSaveButton() {
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

export async function analyzeFile(file) {
  if (state.busy) return;
  const name = file.name || "session.fit";
  if (!/\.(fit|zip)$/i.test(name)) {
    fail(`"${name}" is not a .fit or .zip file.`);
    return;
  }
  state.busy = true;
  el("error").hidden = true;
  el("results").hidden = true;
  el("progress").hidden = false;
  resetSteps();
  showView("analyze");

  const buffer = await file.arrayBuffer();
  // The worker takes ownership of `buffer` (transferred, so a 6 MB FIT is not copied to
  // get there); this copy is what "Save to library" writes back out.
  const keep = buffer.slice(0);
  try {
    const msg = await runAnalysis(buffer, name);
    state.busy = false;
    showResult(JSON.parse(msg.json), { digest: JSON.parse(msg.digestJson), bytes: keep });
  } catch (err) {
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

/* ----------------------------------------------------------------------- library */

function wireSave() {
  el("save-session").addEventListener("click", async () => {
    const button = el("save-session");
    if (!state.lastDigest || !state.lastBytes) return;
    button.disabled = true;
    button.textContent = "Saving…";
    try {
      const outcome = await saveSession({
        digest: state.lastDigest,
        analysisJson: JSON.stringify(state.last),
        fitBytes: state.lastBytes,
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
      ? { label: `${record.label} — ${record.value} ${record.unit}`, windows: record.windows }
      : null;
    showResult(await openStoredSession(id), { fromLibrary: true, highlight });
  } catch (err) {
    fail(err.message);
  }
}

/* -------------------------------------------------------------------- view routing */

function showView(name) {
  const view = VIEWS.includes(name) ? name : "analyze";
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

  navigator.serviceWorker.register("./sw.js").then((reg) => {
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

/* --------------------------------------------------------------------------- go */

wireDropzone();
wireDownload();
wireSave();
wireNav();
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
