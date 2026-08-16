/* The session library view: rows, open, delete, export.
 *
 * Opening a stored session does NOT re-run the analysis — the full document was written
 * to disk when it was saved, so it is parsed and handed straight to `render()`. That is
 * what makes the library instant, and it is also why the library keeps working when the
 * Pyodide CDN is unreachable.
 *
 * Nothing in this file derives a metric. Every number in a row is a field of the Python
 * digest, printed. The dedupe decision is a Python call. The only arithmetic is adding up
 * file sizes for the storage indicator.
 */

import { ask, askBytes } from "./rpc.js";
import { esc, hms, int, nf, sessionDate } from "./render.js";
import {
  getAnalysisJson, getFitBlob, listEntries, putSession, removeSession, storageLabel, usage,
} from "./store.js";
import { invalidateTrends } from "./trends.js";

const el = (id) => document.getElementById(id);

let hooks = { onOpen: () => {}, setCount: () => {} };

export function mountLibrary(options) {
  hooks = { ...hooks, ...options };
  el("lib-export").addEventListener("click", exportAll);
  el("lib-body").addEventListener("click", onRowClick);
  return refresh().catch(() => []);
}

/* -------------------------------------------------------------------- saving */

/**
 * Save one analysed session. `digest` is the Python digest that came back with the
 * analysis; `analysisJson` is the document verbatim; `fitBytes` are the original bytes.
 *
 * Dedupe: the "same session" test (start within ±60 s AND duration within ±60 s) runs in
 * Python over the stored index. A match is never resolved silently — the user is asked,
 * and answering no leaves the library untouched rather than adding a second copy.
 */
export async function saveSession({ digest, analysisJson, fitBytes }) {
  const index = await listEntries();
  const hit = await ask("dedupe", {
    digestJson: JSON.stringify(digest),
    indexJson: JSON.stringify(index),
  });

  let replaceId = null;
  if (hit.match) {
    const existing = index[hit.index] || {};
    const when = existing.startUtc ? sessionDate(existing.startUtc) : "unknown date";
    const ok = window.confirm(
      `This looks like a session you already have.\n\n` +
      `In the library: ${existing.fileName || existing.id} (${when})\n` +
      `Start differs by ${hit.deltaStartS} s, duration by ${hit.deltaDurS} s — ` +
      `inside the ±60 s / ±60 s rule, so it is the same session.\n\n` +
      `Replace the stored copy with this one?`);
    if (!ok) return { saved: false, reason: "duplicate" };
    replaceId = existing.id;
  }

  const entry = await putSession({ digest, analysisJson, fitBytes, replaceId });
  invalidateTrends();
  await refresh();
  return { saved: true, replaced: Boolean(replaceId), entry };
}

/* ------------------------------------------------------------------- the view */

export async function refresh() {
  let entries;
  try {
    entries = await listEntries();
  } catch (err) {
    // No OPFS and no IndexedDB (a locked-down private window, say). The analyzer itself
    // is unaffected, so say so plainly instead of taking the page down.
    el("lib-sub").textContent = "Storage is unavailable in this browser context.";
    el("lib-body").innerHTML = `<p class="note">${esc(err.message)}<br><br>
      Analyzing files still works — only saving does not.</p>`;
    el("lib-export").disabled = true;
    hooks.setCount(0);
    return [];
  }
  hooks.setCount(entries.length);
  el("lib-export").disabled = entries.length === 0;
  await renderSub(entries);
  renderRows(entries);
  return entries;
}

async function renderSub(entries) {
  const u = await usage();
  const where = await storageLabel();
  const bits = [`${entries.length} session${entries.length === 1 ? "" : "s"}`];
  if (entries.length) bits.push(`${mb(u.libraryBytes)} stored`);
  if (u.originBytes !== null) {
    bits.push(`${mb(u.originBytes)} used by this site in total` +
              (u.quotaBytes ? ` of ~${mb(u.quotaBytes)} available` : ""));
  }
  el("lib-sub").innerHTML =
    `${esc(bits.join(" · "))} — in ${esc(where)}. Clearing this site's data deletes it all.`;
}

const mb = (bytes) => (bytes === null || bytes === undefined ? "—"
  : bytes >= 1024 * 1024 * 1024 ? `${(bytes / 1024 ** 3).toFixed(1)} GB`
  : bytes >= 1024 * 1024 ? `${(bytes / 1024 ** 2).toFixed(1)} MB`
  : `${Math.max(1, Math.round(bytes / 1024))} KB`);

const shortDate = (utc) => (utc
  ? new Date(utc).toLocaleString("en-GB",
      { year: "numeric", month: "short", day: "2-digit", hour: "2-digit", minute: "2-digit" })
  : "—");

function renderRows(entries) {
  const host = el("lib-body");
  if (!entries.length) {
    host.innerHTML = `<p class="note">Nothing saved yet. Analyze a FIT file and press
      <strong>Save to library</strong> — the file and its analysis are written to this
      browser's private storage, and never leave the device.</p>`;
    return;
  }

  // Ten columns is a lot for a 390 px screen, and these rows are *browsed* one at a time
  // rather than scanned as a column — so on a phone `stack-sm` (css/style.css) turns each
  // row into a card. Every cell carries the same label its <th> has, from the same list.
  const head = ["date", "session", "on foil", "distance", "flights", "longest", "turns",
                "best 2 s", "size", ""];
  const th = (i) => ` data-th="${esc(head[i])}"`;
  host.innerHTML = `<div class="table-scroll"><table class="lib-table stack-sm">
    <thead><tr>${head.map((h, i) =>
      `<th${i <= 1 || i === 9 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${entries.map((e) => `
      <tr data-id="${esc(e.id)}">
        <td class="l stack-lead"${th(0)}>${esc(shortDate(e.startUtc))}</td>
        <td class="l stack-block"${th(1)}><span class="lib-spot">${esc(e.spot || "Session")}</span>
          <span class="lib-file">${esc(e.fileName || "")}</span></td>
        <td${th(2)}>${nf(e.foilPct, 0)} %</td>
        <td${th(3)}>${nf(e.distanceKm, 2)} km</td>
        <td${th(4)}>${int(e.flightCount)}</td>
        <td${th(5)}>${hms(e.longestFlightS)}</td>
        <td${th(6)}>${int(e.turns?.counted)}</td>
        <td${th(7)}>${nf(e.records?.best2sKn, 2)}</td>
        <td class="dim"${th(8)}>${esc(mb((e.bytesFit || 0) + (e.bytesJson || 0)))}</td>
        <td class="l lib-row-actions stack-actions"${th(9)}>
          <button class="ghost small-btn" data-act="open">Open</button>
          <button class="ghost small-btn" data-act="fit">.fit</button>
          <button class="ghost small-btn" data-act="json">.json</button>
          <button class="ghost small-btn danger" data-act="delete">Delete</button>
        </td>
      </tr>`).join("")}</tbody></table></div>`;
}

/* ------------------------------------------------------------------- actions */

async function onRowClick(ev) {
  const button = ev.target.closest("button[data-act]");
  if (!button) return;
  const id = button.closest("tr")?.dataset.id;
  if (!id) return;
  const entries = await listEntries();
  const entry = entries.find((e) => e.id === id);
  if (!entry) return;

  switch (button.dataset.act) {
    case "open":
      hooks.onOpen(id);
      break;
    case "fit":
      download(await getFitBlob(id), entry.fileName || `${id}.fit`);
      break;
    case "json":
      download(new Blob([await getAnalysisJson(id)], { type: "application/json" }),
               `${stem(entry.fileName || id)}.analysis.json`);
      break;
    case "delete":
      if (window.confirm(
        `Delete “${entry.spot || entry.fileName}” (${shortDate(entry.startUtc)})?\n\n` +
        `The stored FIT and its analysis are removed from this browser. ` +
        `This cannot be undone.`)) {
        await removeSession(id);
        invalidateTrends();                 // the records may have belonged to this one
        await refresh();
      }
      break;
  }
}

/** The stored analysis document for one session. Parsing it is all it takes to redraw the
 *  whole report — no FIT decode, no Pyodide, works with the CDN unreachable. */
export async function openStoredSession(id) {
  return JSON.parse(await getAnalysisJson(id));
}

const stem = (name) => String(name).replace(/\.(fit|zip)$/i, "");

function download(blob, name) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}

/* -------------------------------------------------------------------- export */

/** Everything, as one zip: the original FITs plus their analysis documents.
 *  The archive is built by CPython's `zipfile` inside the worker — see js/worker.js. */
async function exportAll() {
  const button = el("lib-export");
  const entries = await listEntries();
  if (!entries.length) return;
  button.disabled = true;
  const was = button.textContent;
  button.textContent = "Packing…";
  try {
    const files = [];
    for (const e of entries) {
      const base = stem(e.fileName || e.id);
      files.push({ name: `wingfoil-library/${base}.fit`,
                   bytes: new Uint8Array(await (await getFitBlob(e.id)).arrayBuffer()) });
      files.push({ name: `wingfoil-library/${base}.analysis.json`,
                   bytes: await getAnalysisJson(e.id), deflate: true });
    }
    files.push({ name: "wingfoil-library/index.json",
                 bytes: JSON.stringify(entries, null, 2), deflate: true });
    const buffer = await askBytes("zip", { files });
    download(new Blob([buffer], { type: "application/zip" }),
             `wingfoil-library-${new Date().toISOString().slice(0, 10)}.zip`);
  } catch (err) {
    window.alert(`The export failed: ${err.message}\n\n` +
                 `The per-session .fit / .json buttons in each row always work — they are ` +
                 `plain file downloads and need no Python at all.`);
  } finally {
    button.textContent = was;
    button.disabled = false;
  }
}
