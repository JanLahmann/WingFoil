/* The one channel to the Pyodide worker.
 *
 * Every module that needs a number asks for it here, and gets JSON back. There is no
 * second path: `js/library.js` and `js/trends.js` never compute a maximum, a mean or a
 * dedupe key themselves, they call `ask("aggregate", …)` / `ask("dedupe", …)` and render
 * what Python returns.
 *
 * Requests are correlated by a monotonic id, because the worker answers out of order once
 * an analysis and an aggregation are in flight at the same time.
 */

const pending = new Map();
let worker = null;
let nextId = 1;

const listeners = { status: [], ready: [], result: [] };

/** Subscribe to worker lifecycle events: `on("status"|"ready"|"result", fn)`. */
export function on(event, fn) {
  listeners[event].push(fn);
}

const emit = (event, payload) => listeners[event].forEach((fn) => fn(payload));

function ensure() {
  if (worker) return worker;
  worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
  worker.onmessage = (ev) => route(ev.data);
  worker.onerror = (ev) => {
    const message = ev.message || "Worker failed to start";
    for (const [, p] of pending) p.reject(new Error(message));
    pending.clear();
    emit("result", { type: "error", message });
  };
  return worker;
}

function route(msg) {
  switch (msg.type) {
    case "status":
      emit("status", msg);
      return;
    case "ready":
      emit("ready", msg);
      return;
    case "json":
    case "bytes":
    case "result": {
      const p = pending.get(msg.id);
      if (p) {
        pending.delete(msg.id);
        p.resolve(msg);
      }
      if (msg.type === "result") emit("result", msg);
      return;
    }
    case "error": {
      const p = pending.get(msg.id);
      if (p) {
        pending.delete(msg.id);
        p.reject(new Error(msg.message));
      } else {
        emit("result", msg);
      }
      return;
    }
  }
}

/** Warm the runtime: the ~12 MB download dominates the first analysis. */
export function warmUp() {
  ensure().postMessage({ type: "init" });
}

/** The message a cancelled request rejects with, so callers can tell it from a failure. */
export const CANCELLED = "cancelled";

/**
 * Abandon everything in flight and start over with a fresh worker.
 *
 * There is no gentler way, and pretending otherwise would be the bug. `entry.analyze_json`
 * is a single synchronous call into CPython-on-WASM: once it is running, the worker's
 * message loop does not turn again until it returns, so a `{type:'cancel'}` message would
 * sit unread in the queue for the entire nine minutes it was sent to interrupt
 * (app-ui-review.md §7.3). `terminate()` is the only thing that actually stops the work,
 * and it is clean here precisely because the worker owns nothing durable — the FIT bytes
 * were transferred into it, every result travels back as JSON, and the library lives in
 * OPFS on the main thread. Nothing is half-written when it dies.
 *
 * The cost is the runtime: the replacement worker re-boots Pyodide from scratch. That is
 * a cache read rather than a 12 MB download (the service worker and the HTTP cache both
 * hold it), so it is seconds, not minutes — and the caller is told to say so.
 */
export function cancel() {
  if (!worker) return false;
  worker.terminate();
  worker = null;
  for (const [, p] of pending) p.reject(new Error(CANCELLED));
  pending.clear();
  return true;
}

function send(payload, transfer = []) {
  const id = nextId++;
  const promise = new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
  ensure().postMessage({ ...payload, id }, transfer);
  return promise;
}

/** Run the engine over FIT bytes. Resolves with `{json, digestJson}`. */
export function analyze(buffer, name) {
  return send({ type: "analyze", name, buffer }, [buffer]);
}

/** A Python call that answers with JSON — `digest`, `dedupe`, `aggregate`. */
export async function ask(type, payload) {
  const msg = await send({ type, ...payload });
  return JSON.parse(msg.json);
}

/** A Python call that answers with bytes — the zip export. */
export async function askBytes(type, payload) {
  const msg = await send({ type, ...payload });
  return msg.buffer;
}
