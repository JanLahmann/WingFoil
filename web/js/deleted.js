/* Deleted sessions: the receipt a delete leaves, and the way back.
 *
 * On the phone, deleting a session leaves a tombstone — the id, the title and the date —
 * so a sync knows to leave that afternoon on intervals.icu rather than downloading it
 * again, and so Settings can offer it back (`SessionTombstones`, ReAddDeletedSheet, the
 * Deleted sessions section of SettingsView). The browser has no sync to teach, so the
 * tombstone here does the other half of the job: it keeps the file the session was made
 * from, and Restore reads that file again.
 *
 * Why keep the recording and not the analysis. An analysis document is the engine's answer
 * at one version, and the engine moves; the recording is the rider's own bytes and does
 * not. Restoring re-runs the analysis, so a session that comes back comes back at today's
 * engine rather than at the one that was current when it was thrown away. The dedupe
 * decides whether it is a second copy, which is the ±60 s / ±60 s rule and Python's call.
 *
 * Clear is the other half of Restore and is said plainly, because it is the one door on
 * this screen that cannot be undone: the file goes, and with it the only way back.
 */

import { db } from "./appdb.js";
import { ingest } from "./ingest.js";
import { esc, hms, zonedFormat } from "./render.js";

const store = db("wingfoil-deleted");
const INDEX = "index.json";

const el = (id) => document.getElementById(id);

let hooks = { onChanged: async () => {} };

/* -------------------------------------------------------------------- the writes */

/**
 * Remember one deletion, with the recording that made it.
 *
 * Called before the library row goes, so the FIT is still readable. A failure here must
 * never stop the delete the rider asked for: the tombstone is a courtesy, and a browser
 * that refuses IndexedDB still has to be able to throw a session away.
 */
export async function keepTombstone(entry, fitBlob) {
  try {
    const stones = await listTombstones();
    const stone = {
      id: entry.id,
      title: entry.spot || entry.fileName || entry.id,
      fileName: entry.fileName || `${entry.id}.fit`,
      startUtc: entry.startUtc || null,
      utcOffsetS: entry.utcOffsetS ?? null,
      durationS: entry.rateDurationS ?? entry.durationS ?? null,
      rider: entry.rider || null,
      example: entry.example === true,
      deletedUtc: new Date().toISOString(),
    };
    if (fitBlob) await store.put(`${entry.id}.fit`, fitBlob);
    await store.put(INDEX, [stone, ...stones.filter((s) => s.id !== entry.id)]);
  } catch { /* the delete itself has already been asked for, and still happens */ }
}

export async function listTombstones() {
  const stones = await store.get(INDEX, []);
  return Array.isArray(stones) ? stones : [];
}

async function forget(id) {
  await store.remove(`${id}.fit`);
  await store.put(INDEX, (await listTombstones()).filter((s) => s.id !== id));
}

/* --------------------------------------------------------------------- the screen */

/** "Sun 30 Aug, 14:07" on the session's own clock, as the library rows print it. */
function when(stone) {
  if (!stone.startUtc) return "Date not recorded";
  return zonedFormat(stone.startUtc, stone.utcOffsetS, {
    weekday: "short", day: "2-digit", month: "short", year: "numeric",
    hour: "2-digit", minute: "2-digit",
  });
}

export async function renderDeleted() {
  const host = el("deleted-body");
  if (!host) return;
  const stones = await listTombstones();
  if (!stones.length) {
    host.innerHTML = `<p class="note">${esc(host.dataset.empty || "")}</p>`;
    return;
  }
  host.innerHTML = `<ul class="stone-list">${stones.map((s) => `
    <li data-stone="${esc(s.id)}">
      <span class="stone-title">${esc(s.title)}</span>
      <span class="dim">${esc(when(s))}${
        s.durationS ? ` · ${hms(s.durationS)}` : ""}</span>
      <button class="ghost small-btn" type="button" data-act="restore">Restore</button>
      <button class="ghost small-btn danger" type="button" data-act="clear">Clear</button>
    </li>`).join("")}</ul>
    <p><button class="ghost small-btn danger" type="button" data-act="clear-all">Clear
      all</button></p>
    <div id="deleted-status" role="status"></div>`;
}

function say(text) {
  const host = el("deleted-status");
  if (host) host.innerHTML = text ? `<p class="note">${esc(text)}</p>` : "";
}

async function restore(id) {
  const stone = (await listTombstones()).find((s) => s.id === id);
  if (!stone) return;
  const file = await store.get(`${id}.fit`, null);
  if (!file) {
    say("The file for that session is gone, so it cannot come back.");
    return;
  }
  say("Reading that recording again…");
  const outcome = await ingest(await file.arrayBuffer(), stone.fileName,
                              { rider: stone.rider, example: stone.example });
  if (outcome.status === "failed") {
    say(`That recording could not be read again: ${outcome.message}`);
    return;
  }
  await forget(id);
  await hooks.onChanged();
  await renderDeleted();
  say(outcome.status === "duplicate"
    ? "That session is already in your library, so nothing was added."
    : `${stone.title} is back in your library.`);
}

async function clear(id) {
  const stone = (await listTombstones()).find((s) => s.id === id);
  if (!stone) return;
  if (!window.confirm(`Clear “${stone.title}”?\n\n`
                      + `The recording is removed from this browser and cannot come back. `
                      + `This cannot be undone.`)) return;
  await forget(id);
  await renderDeleted();
}

async function clearAll() {
  const stones = await listTombstones();
  if (!stones.length) return;
  if (!window.confirm(`Clear ${stones.length} deleted session`
                      + `${stones.length === 1 ? "" : "s"}?\n\n`
                      + `Their recordings are removed from this browser and cannot come `
                      + `back. This cannot be undone.`)) return;
  for (const stone of stones) await store.remove(`${stone.id}.fit`);
  await store.put(INDEX, []);
  await renderDeleted();
}

/**
 * Wire the section. `onChanged` is the library's own refresh — a restored session belongs
 * in the list and in the records the moment it lands.
 */
export function mountDeleted(options = {}) {
  hooks = { ...hooks, ...options };
  const host = el("deleted-body");
  if (!host) return;
  host.addEventListener("click", (ev) => {
    const button = ev.target.closest("button[data-act]");
    if (!button) return;
    const id = button.closest("[data-stone]")?.dataset.stone;
    if (button.dataset.act === "clear-all") clearAll().catch(() => {});
    else if (button.dataset.act === "restore" && id) restore(id).catch(() => {});
    else if (button.dataset.act === "clear" && id) clear(id).catch(() => {});
  });
  renderDeleted().catch(() => {});
}
