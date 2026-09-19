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
import { speed } from "./appsettings.js";
// r3-w1: a delete leaves a tombstone, with the recording that made it. Settings → Deleted
// sessions is the way back (ios/WingFoil/Features/Import/ReAddDeletedSheet.swift).
import { keepTombstone } from "./deleted.js";
import { sportCorrected } from "./cardstats.js";
import { NOT_A_SESSION } from "./copy.js";
import { esc, hms, int, nf, pct, sessionDate, zonedFormat } from "./render.js";
import { askRider } from "./rider.js";
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
 *
 * Attribution: `example` is true only for the bundled recording (js/app.js knows, because
 * it fetched it), and it is the one case that is not asked about — a demonstration nobody
 * in front of this browser rode has one possible answer. Everything else gets the "Whose
 * session is this?" prompt, because the analyzer answers for any .fit that reaches it and
 * a friend's afternoon must not become the reader's personal best. Dismissing the prompt
 * saves nothing; see js/rider.js.
 */
export async function saveSession({ digest, analysisJson, fitBytes, example = false }) {
  const index = await listEntries();
  const hit = await ask("dedupe", {
    digestJson: JSON.stringify(digest),
    indexJson: JSON.stringify(index),
  });

  let replaceId = null;
  let replacing = null;
  if (hit.match) {
    const existing = index[hit.index] || {};
    replacing = existing;
    const when = existing.startUtc ? sessionDate(existing) : "unknown date";
    const ok = window.confirm(
      `This looks like a session you already have.\n\n` +
      `In the library: ${existing.fileName || existing.id} (${when})\n` +
      `Start differs by ${hit.deltaStartS} s, duration by ${hit.deltaDurS} s — ` +
      `inside the ±60 s / ±60 s rule, so it is the same session.\n\n` +
      `Replace the stored copy with this one?`);
    if (!ok) return { saved: false, reason: "duplicate" };
    replaceId = existing.id;
  }

  let rider = null;
  if (!example) {
    const answer = await askRider({
      fileName: digest.fileName || "",
      known: riderNames(index),
      // A replace starts where the entry it replaces left off: confirming a second copy
      // of a friend's session must not quietly promote it into the records.
      initial: replacing?.rider || null,
    });
    if (!answer) return { saved: false, reason: "cancelled" };
    rider = answer.rider;
  }

  const entry = await putSession({ digest, analysisJson, fitBytes, replaceId, rider, example });
  invalidateTrends();
  await refresh();
  return { saved: true, replaced: Boolean(replaceId), entry };
}

/** The friends already in the library, offered by the prompt. The distinct values of one
 *  field are the whole address book — there is nothing else to keep, and nothing else that
 *  could get out of step with what the rows actually say. */
const riderNames = (entries) =>
  [...new Set(entries.map((e) => e.rider).filter(Boolean))]
    .sort((a, b) => a.localeCompare(b));

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
  // Said once, in the count, rather than left to be inferred from a badge per row: the
  // library holds everything, the records do not, and the difference is a number.
  const aside = entries.filter((e) => e.example || e.rider).length;
  if (aside) bits.push(`${aside} not counted in your records`);
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

/** A library row's date, on the *session's* clock (`zonedFormat`) rather than the reader's
 *  — a row that changed its own time every time the reader crossed a timezone would make
 *  the library look like it had been edited. `e` is the stored digest, which carries both
 *  the instant and the offset it was recorded at.
 *
 *  "Sun 30 Aug, 14:07", which is `Fmt.date` on the phone (ios/WingFoil/App/SessionDisplay
 *  .swift). The year joins it only when the session is not in the reader's own year, for
 *  the same reason the phone adds it: a column of "2026" says nothing. */
const shortDate = (e) => {
  if (!e || !e.startUtc) return "—";
  const sameYear = String(e.dateLocal || e.dateUtc || "").slice(0, 4)
    === String(new Date().getFullYear());
  return zonedFormat(e.startUtc, e.utcOffsetS, {
    weekday: "short", day: "2-digit", month: "short",
    ...(sameYear ? {} : { year: "numeric" }),
    hour: "2-digit", minute: "2-digit",
  });
};

/**
 * **The three numbers a row carries, each under its own word** — `RowMetric` on the phone,
 * and its `defaultTriple`: how much of it he flew, how many jibes, how fast.
 *
 * The words are the kit's, character for character, because one wording per metric is the
 * rule across iOS and web (docs/presentation.md). The value is a field of the Python
 * digest, printed — nothing here derives a metric, and the speed is only put into the unit
 * this browser reads (js/appsettings.js).
 */
const ROW_METRICS = [
  { label: "foil", value: (e) => pct(e.foilPct) },
  { label: "jibes", value: (e) => int(e.turns?.jibes) },
  { label: "best 2 s", value: (e) => speed(e.records?.best2sKn) },
];

/** What a row is *called*. The Python digest's `spot` is derived from the filename, and the
 *  watch that wrote the filename records wingfoil under Garmin's windsurf profile — so the
 *  one correction the derived name needs is applied here, on the way to the screen, exactly
 *  as `cardTitle` applies it to the card's headline. The stored digest keeps its own word;
 *  the filename under the label prints verbatim, and remains the row's identity. */
const spotLabel = (entry) => sportCorrected(entry.spot || "") || "Session";

/**
 * **The list, as the phone draws it** (ios/WingFoil/Features/Library/SessionRowView.swift).
 *
 * A row was ten table columns, browsed one at a time and scanned as a column by nobody. It
 * is the phone's row now: the title, the date and the clock under it, three numbers each
 * with its word, then the outcome tally in words and the distance. Tapping it opens the
 * session, which is what a row on the phone does and what a row here never did.
 *
 * An empty library draws nothing at all here: the ways-in card above it is the empty state
 * (js/appshell.js decides which of the two is on screen), and a note under the card saying
 * the same thing in other words would be the second empty state on one screen.
 */
function renderRows(entries) {
  const host = el("lib-body");
  if (!entries.length) {
    host.innerHTML = "";
    return;
  }

  host.innerHTML = `<ul class="lib-list">${entries.map((e) => `
    <li class="lib-row" data-id="${esc(e.id)}">
      <button class="lib-open" type="button" data-act="open">
        <span class="row-title">${esc(spotLabel(e))}${tags(e)}</span>
        <span class="row-when">${esc(shortDate(e))} · ${hms(e.rateDurationS ?? e.durationS)}</span>
        ${e.isSession === false
          ? `<span class="row-note">${esc(NOT_A_SESSION.tag)}</span>` : ""}
        <span class="row-metrics">${ROW_METRICS.map((m) =>
          `<span class="rm"><b>${m.value(e)}</b><i>${esc(m.label)}</i></span>`).join("")}</span>
        <span class="row-foot">${tally(e.turns?.outcomes)}
          <span class="row-km">${nf(e.distanceKm, 1)} km</span></span>
      </button>
      <span class="lib-row-actions">
        <button class="ghost small-btn" data-act="fit">.fit</button>
        <button class="ghost small-btn" data-act="json">.json</button>
        <button class="ghost small-btn danger" data-act="delete">Delete</button>
        <span class="dim small">${esc(mb((e.bytesFit || 0) + (e.bytesJson || 0)))}</span>
      </span>
    </li>`).join("")}</ul>`;
}

/**
 * "Example", or a friend's name, beside the spot.
 *
 * The one thing on a row that cannot be read off any other cell, and the one that changes
 * what the row *means*: these two kinds of session are shown in full and counted in
 * nothing, so the row has to say so where the eye already is. The name itself is the
 * badge — "SHARED" would leave the reader to remember which friend — and the title says
 * the consequence in words, because a colour cannot.
 *
 * The exclusion itself is not decided here. `library.counts_towards_records`
 * (lab_bundle/library.py) owns the rule for every number; this only reads the two fields
 * it reads. An entry saved before they existed has neither, which is exactly the "mine,
 * not example" it always was, and gets no badge.
 */
function tags(e) {
  const out = [];
  if (e.example) {
    out.push(`<span class="lib-tag example" title="The bundled demonstration session — ` +
             `not counted in your records or trends">Example</span>`);
  }
  if (e.rider) {
    out.push(`<span class="lib-tag rider" title="${esc(e.rider)}'s session, shared with ` +
             `you — not counted in your records or trends">${esc(e.rider)}</span>`);
  }
  return out.join("");
}

/**
 * `35 · 8 · 8` on the outcome ladder's own inks — the headline metric every iOS library
 * row has carried since the start and these rows did not (app-ui-review.md §5.6).
 *
 * The ladder is a verdict scale and this is a verdict, so it may use it (the same licence
 * the key-metrics block takes, docs/presentation.md). A digest written before the field
 * existed has no tally: it renders as "—", never as three zeroes, which would say the
 * session had fifty turns and none of them went anywhere.
 */
function tally(o) {
  if (!o) return '<span class="dim">—</span>';
  // **With its words** (Jan, Beta 75; pattern H). "9 · 9 · 12" is the ladder in three
  // colours and nothing else, and a colour is not a word. The three words are the phone's
  // own (`OutcomeTally`): flew, touch, fell.
  const part = (value, ink, word) =>
    `<span class="${ink}">${int(value)}<i>${word}</i></span>`;
  return `<span class="tally">${part(o.flewThrough, "flew", "flew")}<b>·</b>` +
         `${part(o.touchdown, "touchdown", "touch")}<b>·</b>` +
         `${part(o.fellIn, "fell", "fell")}</span>`;
}

/* ------------------------------------------------------------------- actions */

async function onRowClick(ev) {
  const button = ev.target.closest("button[data-act]");
  if (!button) return;
  const id = button.closest("[data-id]")?.dataset.id;
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
        `Delete “${sportCorrected(entry.spot || "") || entry.fileName}” ` +
        `(${shortDate(entry)})?\n\n` +
        // r3-w1: no longer "this cannot be undone" — the recording is kept under a
        // tombstone and Settings → Deleted sessions reads it again.
        `The session leaves your library, your records and your trends. ` +
        `Settings keeps the file, so you can put it back.`)) {
        // r3-w1: read the recording while it is still there, and keep it under the
        // tombstone. Settings → Deleted sessions reads it again on a Restore.
        await keepTombstone(entry, await getFitBlob(id).catch(() => null));
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
