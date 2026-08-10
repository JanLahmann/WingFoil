/* Pyodide worker — the analysis runs here so the UI thread never blocks.
 *
 * It loads the pinned Pyodide build from the official CDN, micropip-installs fitdecode
 * (pure Python, no wheels to build), mounts web/lab_bundle/ into the Pyodide filesystem
 * and calls web_entry.analyze_json(). numpy and pandas ship with Pyodide.
 *
 * Protocol (main -> worker):   {type:'init'} | {type:'analyze', id, name, buffer}
 * Protocol (worker -> main):   {type:'status', step, state, detail}
 *                              {type:'ready'} | {type:'result', id, json} | {type:'error', id, message}
 */

const PYODIDE_VERSION = "0.28.3";
const PYODIDE_URL = `https://cdn.jsdelivr.net/pyodide/v${PYODIDE_VERSION}/full/`;
const FITDECODE = "fitdecode==0.11.0";
// Drop a fitdecode py3-none-any wheel next to this file and point here to run fully
// offline / behind a PyPI-blocking proxy; null = install from PyPI via micropip.
const FITDECODE_LOCAL_WHEEL = null;

let pyodide = null;
let entry = null;
let booting = null;

const status = (step, state, detail = "") =>
  self.postMessage({ type: "status", step, state, detail });

async function boot() {
  status("runtime", "active", `pyodide ${PYODIDE_VERSION}`);
  const { loadPyodide } = await import(`${PYODIDE_URL}pyodide.mjs`);
  pyodide = await loadPyodide({ indexURL: PYODIDE_URL });
  status("runtime", "active", "numpy + pandas");
  await pyodide.loadPackage(["numpy", "pandas", "micropip"]);
  status("runtime", "done", `pyodide ${PYODIDE_VERSION}`);

  status("engine", "active", "fitdecode");
  const micropip = pyodide.pyimport("micropip");
  await micropip.install(FITDECODE_LOCAL_WHEEL || FITDECODE);

  status("engine", "active", "wingfoil_lab");
  await mountLab();
  pyodide.runPython("import sys\nif '/lab_bundle' not in sys.path: sys.path.insert(0, '/lab_bundle')");
  entry = pyodide.pyimport("web_entry");
  const version = pyodide.runPython("import wingfoil_lab; wingfoil_lab.ENGINE_VERSION");
  status("engine", "done", `engine ${version}`);
  self.postMessage({ type: "ready", engineVersion: version, pyodideVersion: PYODIDE_VERSION });
}

/** Copy the bundled lab sources into the Pyodide MEMFS. FILES.json is written by
 *  web/tools/bundle_lab.py — HTTP gives us no directory listing. */
async function mountLab() {
  const base = new URL("../lab_bundle/", import.meta.url);
  const files = await fetchJson(new URL("FILES.json", base));
  pyodide.FS.mkdirTree("/lab_bundle");
  const seen = new Set();
  for (const rel of files) {
    const dir = rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "";
    if (dir && !seen.has(dir)) { pyodide.FS.mkdirTree(`/lab_bundle/${dir}`); seen.add(dir); }
    const res = await fetch(new URL(rel, base), { cache: "no-cache" });
    if (!res.ok) throw new Error(`lab_bundle/${rel}: HTTP ${res.status}`);
    pyodide.FS.writeFile(`/lab_bundle/${rel}`, await res.text());
  }
}

async function fetchJson(url) {
  const res = await fetch(url, { cache: "no-cache" });
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return res.json();
}

async function analyze(id, name, buffer) {
  if (!booting) booting = boot();
  await booting;

  status("parse", "active", name);
  const bytes = new Uint8Array(buffer);
  let json;
  try {
    // web_entry does parse + analyze in one Python call; the two UI steps bracket it.
    status("analyze", "active", `${(bytes.length / 1024).toFixed(0)} KB`);
    json = entry.analyze_json(bytes, name);
  } finally {
    status("parse", "done", "");
  }
  status("analyze", "done", "");
  self.postMessage({ type: "result", id, json });
}

self.onmessage = async (ev) => {
  const msg = ev.data || {};
  try {
    if (msg.type === "init") {
      if (!booting) booting = boot();
      await booting;
    } else if (msg.type === "analyze") {
      await analyze(msg.id, msg.name, msg.buffer);
    }
  } catch (err) {
    booting = null;                       // a failed boot must be retryable
    self.postMessage({ type: "error", id: msg.id ?? null, message: describe(err) });
  }
};

function describe(err) {
  if (!err) return "Unknown error";
  const text = err.message || String(err);
  if (/Traceback \(most recent call last\)/.test(text)) {
    // Lead with what actually went wrong; keep the traceback underneath for debugging.
    const lines = text.trimEnd().split("\n");
    const last = lines[lines.length - 1].replace(/^\w[\w.]*Error:\s*/, "");
    return `${last}\n\n${text}`;
  }
  if (/Failed to fetch|NetworkError|dynamically imported module/i.test(text)) {
    return `${text}\n\nCould not reach the Pyodide CDN (cdn.jsdelivr.net) or PyPI. ` +
           `Check your connection — the runtime is downloaded on first use and cached afterwards.`;
  }
  return text;
}
