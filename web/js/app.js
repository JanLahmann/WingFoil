/* App shell: file intake (drag & drop / picker / intervals.icu), worker orchestration,
 * progress state. All analysis happens in js/worker.js; this file never touches numbers. */

import { render } from "./render.js";
import { mountIcu } from "./icu.js";

const el = (id) => document.getElementById(id);

const state = { worker: null, busy: false, nextId: 1, pending: null, last: null, booted: false };

/* ------------------------------------------------------------------- worker */

function worker() {
  if (state.worker) return state.worker;
  const w = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
  w.onmessage = (ev) => onWorkerMessage(ev.data);
  w.onerror = (ev) => fail(ev.message || "Worker failed to start");
  state.worker = w;
  return w;
}

function onWorkerMessage(msg) {
  switch (msg.type) {
    case "status":
      setStep(msg.step, msg.state, msg.detail);
      break;
    case "ready":
      state.booted = true;
      el("engine-chip").hidden = false;
      el("engine-chip").textContent = `engine ${msg.engineVersion} · pyodide ${msg.pyodideVersion}`;
      break;
    case "result": {
      const result = JSON.parse(msg.json);
      state.busy = false;
      state.last = result;
      el("progress").hidden = true;
      el("results").hidden = false;
      el("dropzone").classList.add("compact");
      render(result);
      window.scrollTo({ top: el("results").offsetTop - 70, behavior: "smooth" });
      break;
    }
    case "error":
      fail(msg.message);
      break;
  }
}

function fail(message) {
  state.busy = false;
  el("progress").hidden = true;
  el("error").hidden = false;
  el("error-text").textContent = message;
}

/* ----------------------------------------------------------------- progress */

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

/* --------------------------------------------------------------------- intake */

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

  const buffer = await file.arrayBuffer();
  worker().postMessage({ type: "analyze", id: state.nextId++, name, buffer }, [buffer]);
}

/** Fetch a FIT that another module (icu.js) already downloaded as an ArrayBuffer. */
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

  zone.addEventListener("click", (ev) => { if (!ev.target.closest("button")) el("file").click(); });
  zone.addEventListener("keydown", (ev) => {
    if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); el("file").click(); }
  });
  el("pick").addEventListener("click", (ev) => { ev.stopPropagation(); el("file").click(); });
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

/* ----------------------------------------------------------------------- go */

wireDropzone();
wireDownload();
mountIcu({ analyzeBuffer });

// Warm the runtime immediately: the ~12 MB download dominates the first analysis and
// there is nothing else for the page to do while the user finds a file.
worker().postMessage({ type: "init" });
