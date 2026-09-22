/* One way back into the library, for the two doors that put a session back rather than in.
 *
 * Restoring a deleted session and restoring a backup are the same act: bytes that were
 * already a session once, read again. Both go through the engine and both go through the
 * dedupe, because a session that is already in the library must not become a second copy
 * of itself — `DEDUPE_START_S` / `DEDUPE_DURATION_S` in `lab_bundle/library.py`, the same
 * ±60 s / ±60 s rule the Save button obeys (docs/algorithms.md).
 *
 * What this does NOT do is ask. `js/library.js` asks two questions on a save — whose
 * session is this, and replace the stored copy? — and neither has an answer here: a
 * restore is a file the rider already answered for once, and its attribution travels with
 * it. A duplicate is skipped rather than replaced, which is the phone's own rule for a
 * restore: sessions you already have keep their own analysis.
 */

import { speedRecords } from "./appsettings.js";
import { analyze, ask } from "./rpc.js";
import { listEntries, putSession } from "./store.js";

/**
 * Analyse one recording and put it in the library, unless it is already there.
 *
 * Resolves `{status, entry}` where `status` is `"added"`, `"duplicate"` or `"failed"`.
 * `bytes` is an ArrayBuffer or a Uint8Array; it is copied before the worker takes it, so
 * the caller's own copy survives.
 */
export async function ingest(bytes, name, { rider = null, example = false } = {}) {
  const source = bytes instanceof ArrayBuffer ? bytes : bytes.buffer.slice(
    bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  // The worker takes ownership of the buffer it is handed, so the copy kept here is the
  // one written back to the library.
  const keep = source.slice(0);
  let digest;
  let analysisJson;
  try {
    const msg = await analyze(source, name, speedRecords());
    analysisJson = msg.json;
    digest = JSON.parse(msg.digestJson);
  } catch (err) {
    return { status: "failed", name, message: err.message };
  }

  const index = await listEntries();
  const hit = await ask("dedupe", {
    digestJson: JSON.stringify(digest),
    indexJson: JSON.stringify(index),
  });
  if (hit.match) return { status: "duplicate", name, entry: index[hit.index] || null };

  const entry = await putSession({ digest, analysisJson, fitBytes: keep, rider, example });
  return { status: "added", name, entry };
}
