/* Session library storage — the only file that touches persistence.
 *
 * Two backends behind one API:
 *
 *   OPFS  (Origin Private File System)  the primary. A private, per-origin filesystem;
 *         the FIT and the analysis JSON are ordinary files, so a 6 MB FIT costs one
 *         write and one read and never has to become a base64 string.
 *   IndexedDB                            the fallback, feature-detected. Used when
 *         `navigator.storage.getDirectory` is missing, or when the returned handles have
 *         no `createWritable()` — which is the real-world shape of the problem, because
 *         some browsers ship OPFS with only the worker-side sync API.
 *
 * Everything here is bytes and bookkeeping. Not one number the UI shows as a *metric* is
 * computed in this file: the per-session values come from the Python digest, the records
 * and trends come from `library.aggregate`. The only arithmetic below is adding up file
 * sizes for the storage indicator, and even that defers to `navigator.storage.estimate()`
 * when the browser offers it.
 *
 * Layout (identical in both backends, so an index written by one reads back in the other):
 *
 *   index.json          [ { ...digest, savedUtc, bytesFit, bytesJson, rider, example }, ... ]
 *   <id>.fit            the original bytes, exactly as they were dropped
 *   <id>.json           the full analysis document — opening a session re-renders THIS,
 *                       with no Pyodide run at all
 */

const DIR = "wingfoil-library";
const INDEX = "index.json";
const DB_NAME = "wingfoil-library";
const DB_VERSION = 1;

let backendPromise = null;

/* ------------------------------------------------------------------ OPFS backend */

/** The library directory, re-acquired on every operation.
 *
 * Holding one handle for the life of the page looks tidier and is a trap: if the user
 * clears site data (or a devtools "delete" happens) the cached handle keeps pointing at a
 * directory that no longer exists, and every later write fails with a bare NotFoundError.
 * Asking the root again with `create: true` costs microseconds and heals that.
 */
async function opfsDir() {
  const root = await navigator.storage.getDirectory();
  return root.getDirectoryHandle(DIR, { create: true });
}

async function opfsBackend() {
  if (!navigator.storage?.getDirectory) return null;
  try {
    // Feature-detect for real: a handle without createWritable is useless to us here,
    // and some engines ship OPFS with only the worker-side sync API. Probe, then clean up.
    const dir = await opfsDir();
    const probe = await dir.getFileHandle(".probe", { create: true });
    if (typeof probe.createWritable !== "function") throw new Error("no createWritable");
    const w = await probe.createWritable();
    await w.write(new Uint8Array([0]));
    await w.close();
    await dir.removeEntry(".probe");
  } catch {
    return null;
  }

  return {
    kind: "opfs",
    label: "OPFS (private browser filesystem)",
    write: async (name, data) => {
      const handle = await (await opfsDir()).getFileHandle(name, { create: true });
      const w = await handle.createWritable();
      await w.write(data);
      await w.close();
    },
    read: async (name) => {
      try {
        return await (await (await opfsDir()).getFileHandle(name)).getFile();
      } catch {
        return null;                                    // absent, not an error
      }
    },
    remove: async (name) => {
      try { await (await opfsDir()).removeEntry(name); } catch { /* already gone */ }
    },
  };
}

/* ------------------------------------------------------- IndexedDB fallback backend */

function idbOpen() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains("files")) req.result.createObjectStore("files");
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

function idbRequest(db, mode, fn) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction("files", mode);
    const req = fn(tx.objectStore("files"));
    tx.onerror = () => reject(tx.error);
    if (req) { req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error); }
    else tx.oncomplete = () => resolve(undefined);
  });
}

async function idbBackend() {
  if (!self.indexedDB) return null;
  let db;
  try {
    db = await idbOpen();
  } catch {
    return null;
  }
  return {
    kind: "idb",
    label: "IndexedDB (OPFS unavailable in this browser)",
    write: (name, data) => idbRequest(db, "readwrite", (s) => s.put(new Blob([data]), name)),
    read: async (name) => (await idbRequest(db, "readonly", (s) => s.get(name))) || null,
    remove: (name) => idbRequest(db, "readwrite", (s) => s.delete(name)),
  };
}

/* ------------------------------------------------------------------------- backend */

async function backend() {
  if (!backendPromise) {
    backendPromise = (async () => {
      const chosen = (await opfsBackend()) || (await idbBackend());
      if (!chosen) throw new Error(
        "This browser offers neither OPFS nor IndexedDB, so sessions cannot be saved. " +
        "Private-browsing windows sometimes block both.");
      return chosen;
    })();
  }
  return backendPromise;
}

export async function storageLabel() {
  try {
    return (await backend()).label;
  } catch (err) {
    return err.message;
  }
}

/* --------------------------------------------------------------------------- index */

/** The library index: one entry per stored session, newest first. */
export async function listEntries() {
  const be = await backend();
  const file = await be.read(INDEX);
  if (!file) return [];
  try {
    const parsed = JSON.parse(await file.text());
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function writeIndex(entries) {
  const be = await backend();
  await be.write(INDEX, new Blob([JSON.stringify(entries)], { type: "application/json" }));
  return entries;
}

const newestFirst = (a, b) =>
  String(b.startUtc || b.savedUtc || "").localeCompare(String(a.startUtc || a.savedUtc || ""));

/* -------------------------------------------------------------------------- writes */

/**
 * Save (or replace) one session.
 *
 * `digest` is whatever `library.digest()` produced in the worker — this function copies
 * it into the index untouched and adds only storage bookkeeping. `replaceId` comes from
 * the Python dedupe decision the user confirmed; passing it removes the old files first,
 * so a replace never leaves an orphan behind.
 *
 * `rider` and `example` are the one thing about a session that is NOT in the digest,
 * because it is not in the FIT and could not be: whose afternoon this was. They are
 * stated by the saver (js/library.js asks; the example button answers for itself) and
 * they are what `library.counts_towards_records` reads. Both are written explicitly on
 * every new entry — `rider: null`, `example: false` for the ordinary case — so an
 * exported index.json says what it means rather than leaving it to be inferred from an
 * absent key. Entries written before this existed have neither, and absent reads as
 * "mine, not example" everywhere.
 */
export async function putSession({ digest, analysisJson, fitBytes, replaceId = null,
                                   rider = null, example = false }) {
  const be = await backend();
  const id = digest.id;
  const entries = await listEntries();

  if (replaceId && replaceId !== id) {
    await be.remove(`${replaceId}.fit`);
    await be.remove(`${replaceId}.json`);
  }

  const fitBlob = new Blob([fitBytes], { type: "application/octet-stream" });
  const jsonBlob = new Blob([analysisJson], { type: "application/json" });
  await be.write(`${id}.fit`, fitBlob);
  await be.write(`${id}.json`, jsonBlob);

  const entry = {
    ...digest,
    savedUtc: new Date().toISOString(),
    bytesFit: fitBlob.size,
    bytesJson: jsonBlob.size,
    // A blank name is not a friend: "A friend's" with nothing typed would be a session
    // excluded from the records for a reason no badge could show.
    rider: (typeof rider === "string" && rider.trim()) ? rider.trim() : null,
    example: example === true,
  };
  const kept = entries.filter((e) => e.id !== id && e.id !== replaceId);
  kept.push(entry);
  kept.sort(newestFirst);
  await writeIndex(kept);
  return entry;
}

export async function removeSession(id) {
  const be = await backend();
  await be.remove(`${id}.fit`);
  await be.remove(`${id}.json`);
  const kept = (await listEntries()).filter((e) => e.id !== id);
  await writeIndex(kept);
  return kept;
}

/* --------------------------------------------------------------------------- reads */

/** The stored analysis document, as text. Rendering it needs no Python at all. */
export async function getAnalysisJson(id) {
  const file = await (await backend()).read(`${id}.json`);
  if (!file) throw new Error(`Session ${id} has an index entry but no stored analysis.`);
  return file.text();
}

export async function getFitBlob(id) {
  const file = await (await backend()).read(`${id}.fit`);
  if (!file) throw new Error(`Session ${id} has an index entry but no stored FIT.`);
  return file;
}

/* ------------------------------------------------------------------ storage in use */

/**
 * Bytes in use. `navigator.storage.estimate()` is the truthful answer (it counts the
 * Pyodide HTTP/SW caches too), so it is reported separately from the library's own
 * footprint, which is just the sum of the file sizes we wrote.
 */
export async function usage() {
  const entries = await listEntries();
  const library = entries.reduce((n, e) => n + (e.bytesFit || 0) + (e.bytesJson || 0), 0);
  let origin = null;
  let quota = null;
  try {
    const est = await navigator.storage?.estimate?.();
    if (est) { origin = est.usage ?? null; quota = est.quota ?? null; }
  } catch { /* not exposed here; the library sum still is */ }
  return { sessions: entries.length, libraryBytes: library, originBytes: origin, quotaBytes: quota };
}
