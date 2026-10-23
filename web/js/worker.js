/* Pyodide worker — the analysis runs here so the UI thread never blocks.
 *
 * It loads the pinned Pyodide build from the official CDN, micropip-installs fitdecode
 * from the wheel vendored in web/lab_bundle/wheels/ (PyPI only as the fallback), mounts
 * web/lab_bundle/ into the Pyodide filesystem
 * and calls web_entry.analyze_json(). numpy and pandas ship with Pyodide.
 *
 * Every number the app shows — including the library's dedupe key, the all-time records
 * and every trend point — is produced by Python here. The main thread renders JSON.
 *
 * Protocol (main -> worker):
 *   {type:'init'}
 *   {type:'analyze',   id, name, buffer, policy}
 *   {type:'presentation', id, json, policy}         stored analysis -> its document
 *   {type:'digest',    id, json, name}              analysis JSON -> library digest
 *   {type:'dedupe',    id, digestJson, indexJson}   is this session already stored?
 *   {type:'aggregate', id, digestsJson, speedRecords}  records + trends + periods
 *   {type:'period',    id, digestsJson, start, end} one custom date range's block
 *   {type:'zip',       id, files:[{name, bytes}]}   bulk export, via Python's zipfile
 * Protocol (worker -> main):
 *   {type:'status', step, state, detail} | {type:'ready'}
 *   {type:'result', id, json, digestJson} | {type:'json', id, kind, json}
 *   {type:'bytes',  id, kind, buffer}    | {type:'error', id, message}
 */

const PYODIDE_VERSION = "0.28.3";
const PYODIDE_URL = `https://cdn.jsdelivr.net/pyodide/v${PYODIDE_VERSION}/full/`;
const FITDECODE = "fitdecode==0.11.0";
/** The same pin, vendored (rider review X14, 23 Oct 2026): behind a school or company proxy
 *  PyPI was the second host that had to answer before a first analysis. The wheel is pure
 *  Python (py3-none-any), copied byte for byte from files.pythonhosted.org, and served from
 *  this site's own origin. Its SHA-256 is checked here before micropip sees it, and
 *  web/tools/bundle_lab.py --check holds the file on disk to the same hash and to the pin
 *  above (docs/engineering.md, "The vendored wheel"). PyPI stays as the fallback only: a
 *  missing or altered wheel installs `FITDECODE` from PyPI as before. */
const FITDECODE_WHEEL = "fitdecode-0.11.0-py3-none-any.whl";
const FITDECODE_SHA256 = "a1bdb9b4d1e9ebac0001fc58c22fe07a3f9967ca4e13258c6ef99cdb8d697a78";

let pyodide = null;
let entry = null;          // lab_bundle/web_entry.py — FIT bytes -> analysis document
let lib = null;            // lab_bundle/library.py   — digests, dedupe, records, trends
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
  const wheel = await vendoredWheel();
  // `deps: false` on the vendored wheel: fitdecode needs nothing outside the standard
  // library (its Requires-Dist are dev extras), so no index is consulted at all.
  // A vendored wheel that will not install falls back to PyPI too, the same as one that
  // is missing or altered (docs/engineering.md, "The vendored wheel").
  let installed = false;
  if (wheel) {
    try {
      await micropip.install.callKwargs(wheel, { deps: false });
      installed = true;
    } catch { /* PyPI below */ }
  }
  if (!installed) await micropip.install(FITDECODE);

  status("engine", "active", "wingfoil_lab");
  await mountLab();
  pyodide.runPython("import sys\nif '/lab_bundle' not in sys.path: sys.path.insert(0, '/lab_bundle')");
  entry = pyodide.pyimport("web_entry");
  lib = pyodide.pyimport("library");
  const version = pyodide.runPython("import wingfoil_lab; wingfoil_lab.ENGINE_VERSION");
  status("engine", "done", `engine ${version}`);
  self.postMessage({ type: "ready", engineVersion: version, pyodideVersion: PYODIDE_VERSION });
}

/** The vendored fitdecode wheel, written into the Pyodide filesystem, as the `emfs:` URL
 *  micropip installs from, or null when it cannot be had or does not match its hash. A
 *  wheel that came down altered is never installed; PyPI is asked instead. */
async function vendoredWheel() {
  try {
    const url = new URL(`../lab_bundle/wheels/${FITDECODE_WHEEL}`, import.meta.url);
    const res = await fetch(url);
    if (!res.ok) return null;
    const bytes = new Uint8Array(await res.arrayBuffer());
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    const hex = Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
    if (hex !== FITDECODE_SHA256) return null;
    const path = `/tmp/${FITDECODE_WHEEL}`;
    pyodide.FS.writeFile(path, bytes);
    return `emfs:${path}`;
  } catch {
    return null;
  }
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

/** `policy` is Settings → Speed records, the one rider choice the presentation document
 *  takes (ADR-033). It travels with the analysis because the document is built in the same
 *  Python call: one pass over the golden rather than a second round trip, and the result
 *  the UI gets back already carries every fact its renderers need. */
async function analyze(id, name, buffer, policy, example = false) {
  if (!booting) booting = boot();
  await booting;

  status("parse", "active", name);
  const bytes = new Uint8Array(buffer);
  let json;
  try {
    // web_entry does parse + analyze in one Python call; the two UI steps bracket it.
    status("analyze", "active", `${(bytes.length / 1024).toFixed(0)} KB`);
    json = entry.analyze_json(bytes, name, policy || "preferVerified", example === true);
  } finally {
    status("parse", "done", "");
  }
  status("analyze", "done", "");
  // The library digest costs one extra Python call on a document we already have, and
  // saves the UI from ever having to derive a summary row itself.
  self.postMessage({ type: "result", id, json, digestJson: lib.digest_json(json, name) });
}

async function ready() {
  if (!booting) booting = boot();
  await booting;
}

/** Bulk export. Python's own `zipfile` writes the archive one member at a time — no JS
 *  zip library, and no moment where the whole library sits in JS *and* in Python at
 *  once. The finished archive lands in the Pyodide filesystem and comes back through
 *  `FS.readFile`, which hands JS a real Uint8Array. */
const ZIP_PATH = "/tmp/wingfoil-library.zip";

async function buildZip(id, files) {
  await ready();
  lib.export_begin();
  try {
    for (const f of files) lib.export_add(f.name, f.bytes, !!f.deflate);
    lib.export_finish(ZIP_PATH);
  } catch (err) {
    lib.export_abort();
    throw err;
  }
  const bytes = pyodide.FS.readFile(ZIP_PATH);
  pyodide.FS.unlink(ZIP_PATH);
  const buffer = bytes.buffer;
  self.postMessage({ type: "bytes", id, kind: "zip", buffer }, [buffer]);
}

self.onmessage = async (ev) => {
  const msg = ev.data || {};
  try {
    switch (msg.type) {
      case "init":
        await ready();
        break;
      case "analyze":
        await analyze(msg.id, msg.name, msg.buffer, msg.policy, msg.example);
        break;
      // The one door for a session stored before the document existed. A session analysed
      // since carries its own inside the analysis JSON and never comes through here, which
      // is what keeps "re-opening a stored session needs no Pyodide" true.
      case "presentation":
        await ready();
        self.postMessage({ type: "json", id: msg.id, kind: "presentation",
                           json: entry.presentation_json(msg.json,
                                                         msg.policy || "preferVerified") });
        break;
      case "digest":
        await ready();
        self.postMessage({ type: "json", id: msg.id, kind: "digest",
                           json: lib.digest_json(msg.json, msg.name || "session.fit") });
        break;
      case "dedupe":
        await ready();
        self.postMessage({ type: "json", id: msg.id, kind: "dedupe",
                           json: lib.dedupe_match_json(msg.digestJson, msg.indexJson) });
        break;
      case "aggregate":
        await ready();
        self.postMessage({ type: "json", id: msg.id, kind: "aggregate",
                           json: lib.aggregate_json(msg.digestsJson,
                                                    msg.speedRecords || "") });
        break;
      // The trips, months and seasons ride along with `aggregate` — they read the same
      // digests, and a second pass over the same list would be a second answer waiting to
      // disagree. Only the range the rider types needs a call of its own, because only it
      // has an input the aggregate could not have known.
      case "period":
        await ready();
        self.postMessage({ type: "json", id: msg.id, kind: "period",
                           json: lib.custom_period_json(msg.digestsJson,
                                                        msg.start || null,
                                                        msg.end || null) });
        break;
      case "zip":
        await buildZip(msg.id, msg.files);
        break;
    }
  } catch (err) {
    // A failure before the engine is up is the engine's download, never the file: a
    // missing wheel behind a proxy that also blocks PyPI raises a Python traceback, and
    // the rider must read "the engine did not download", not "send us this file". The
    // traceback still travels as `message`, behind Details.
    const stage = entry ? "run" : "boot";
    if (!entry) booting = null;           // a failed *boot* must be retryable
    const why = describe(err);
    self.postMessage({ type: "error", id: msg.id ?? null, kind: msg.type, stage,
                       cause: stage === "boot" ? "network" : why.kind,
                       summary: why.summary, message: why.message });
  }
};

/** What went wrong, for the page to say in the rider's words (rider review X15). The
 *  worker types no rider sentence: it names the kind of failure and hands over the text.
 *
 *    python   a Python exception. `summary` is its last line, the exception's own message
 *             (web_entry.py's "not a FIT, GPX or TCX file", "zip contains 3 recordings");
 *             `message` is the whole traceback, which the page keeps behind Details.
 *    network  the runtime or a bundle file could not be fetched.
 *    other    anything else, as it came. */
function describe(err) {
  if (!err) return { kind: "other", summary: "Unknown error", message: "Unknown error" };
  const text = err.message || String(err);
  if (/Traceback \(most recent call last\)/.test(text)) {
    const lines = text.trimEnd().split("\n");
    const summary = lines[lines.length - 1].replace(/^\w[\w.]*Error:\s*/, "");
    return { kind: "python", summary, message: text };
  }
  if (/Failed to fetch|NetworkError|dynamically imported module|HTTP \d{3}/i.test(text)) {
    return { kind: "network", summary: text, message: text };
  }
  return { kind: "other", summary: text, message: text };
}
