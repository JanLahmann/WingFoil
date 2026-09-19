/* The second small store: JSON documents this browser keeps beside the library.
 *
 * `js/store.js` owns the library — the FIT bytes and the analysis document per session, in
 * OPFS where the browser offers it. This owns the three lists that are not sessions and are
 * far too big for `localStorage`: the quiver (wings, boards, foils), what each session was
 * ridden on, and the tombstones a delete leaves behind with the file that made them.
 *
 * Same shape as `js/store.js`, one backend smaller. IndexedDB only, because every document
 * here is small, is written one key at a time and is read back as a whole — the reason
 * store.js reaches for OPFS is a 6 MB FIT that must not become a base64 string, and the one
 * blob this file holds (a tombstone's original recording) is written once and read once.
 *
 * Nothing here is analysis. Not one number the UI shows as a metric is computed in this
 * file, and none ever may be: a gear name is a rider's note, a tombstone is a receipt.
 */

const DB_VERSION = 1;
const STORE = "docs";

const opened = new Map();

function open(name) {
  if (!opened.has(name)) {
    opened.set(name, new Promise((resolve, reject) => {
      if (!self.indexedDB) {
        reject(new Error("This browser context offers no IndexedDB, so nothing can be kept."));
        return;
      }
      const req = indexedDB.open(name, DB_VERSION);
      req.onupgradeneeded = () => {
        if (!req.result.objectStoreNames.contains(STORE)) req.result.createObjectStore(STORE);
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    }));
  }
  return opened.get(name);
}

function run(db, mode, fn) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode);
    const req = fn(tx.objectStore(STORE));
    tx.onerror = () => reject(tx.error);
    if (req) {
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    } else {
      tx.oncomplete = () => resolve(undefined);
    }
  });
}

/**
 * One named database, as four calls. `get` answers `fallback` for anything absent or
 * unreadable — a store that has never been written to is not an error, it is a first run,
 * and a caller that had to tell those apart would need a branch for every read.
 */
export function db(name) {
  return {
    async get(key, fallback = null) {
      try {
        const value = await run(await open(name), "readonly", (s) => s.get(key));
        return value === undefined ? fallback : value;
      } catch {
        return fallback;
      }
    },
    async put(key, value) {
      await run(await open(name), "readwrite", (s) => s.put(value, key));
      return value;
    },
    async remove(key) {
      try {
        await run(await open(name), "readwrite", (s) => s.delete(key));
      } catch { /* already gone, which is what was asked for */ }
    },
    async available() {
      try {
        await open(name);
        return true;
      } catch {
        return false;
      }
    },
  };
}
