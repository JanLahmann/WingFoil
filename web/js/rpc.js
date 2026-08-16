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
