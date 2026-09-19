/* Restore the library from the .zip that Download all wrote.
 *
 * The phone's pair is Back up library / Restore from backup… (ios/WingFoil/Features/
 * Settings/LibraryBackupSection.swift), and its restore opens one screen first: what the
 * file turns out to be, before a single row is written. That screen is `RestoreConfirmation`
 * — Taken, Sessions, what restoring will and will not do, then "Restore N sessions" — and
 * this is it, in the browser, with its words.
 *
 * The browser already had the out half: "Download all (.zip)" packs every recording plus
 * its analysis plus the index, through Python's own `zipfile` in the worker. The way back
 * in was missing, which made the backup a file a rider could keep and never use.
 *
 * WHAT IT READS. The archive is read here rather than in the worker, because the library's
 * index.json inside it is the whole of what this screen needs and the recordings are only
 * needed one at a time, on the way through the engine. The reader below is the central
 * directory and nothing else: stored members come out as they are, deflated ones through
 * the browser's own `DecompressionStream`.
 *
 * WHAT IT WRITES. Nothing directly. Every session goes through `js/ingest.js`, so every
 * session goes through the engine and through the ±60 s dedupe, and a session already in
 * the library keeps the analysis it has.
 */

import { listTombstones } from "./deleted.js";
import { ingest } from "./ingest.js";
import { esc, zonedFormat } from "./render.js";
import { ask } from "./rpc.js";
import { listEntries } from "./store.js";

const el = (id) => document.getElementById(id);

let hooks = { onChanged: async () => {} };
let offer = null;

/* ------------------------------------------------------------------- the zip reader */

const EOCD_SIG = 0x06054b50;
const CENTRAL_SIG = 0x02014b50;

/**
 * Every member of a zip, as `{name, bytes()}`.
 *
 * The central directory at the end of the file is the index, so a 400 MB archive costs one
 * pass over its last few kilobytes to list, and a member costs its own bytes to read. Only
 * the two methods Python's `zipfile` writes are understood: stored, and deflate.
 */
async function readZip(buffer) {
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  let eocd = -1;
  // The comment may be up to 64 KB, so the record is looked for from the end backwards.
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 66000); i -= 1) {
    if (view.getUint32(i, true) === EOCD_SIG) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("That file is not a zip archive this browser can read.");
  const count = view.getUint16(eocd + 10, true);
  let at = view.getUint32(eocd + 16, true);
  const decoder = new TextDecoder();
  const members = [];
  for (let i = 0; i < count; i += 1) {
    if (view.getUint32(at, true) !== CENTRAL_SIG) break;
    const method = view.getUint16(at + 10, true);
    const compressed = view.getUint32(at + 20, true);
    const nameLen = view.getUint16(at + 28, true);
    const extraLen = view.getUint16(at + 30, true);
    const commentLen = view.getUint16(at + 32, true);
    const localAt = view.getUint32(at + 42, true);
    const name = decoder.decode(bytes.subarray(at + 46, at + 46 + nameLen));
    members.push({ name, method, compressed, localAt });
    at += 46 + nameLen + extraLen + commentLen;
  }
  return members.map((m) => ({
    name: m.name,
    bytes: async () => {
      const nameLen = view.getUint16(m.localAt + 26, true);
      const extraLen = view.getUint16(m.localAt + 28, true);
      const from = m.localAt + 30 + nameLen + extraLen;
      const raw = bytes.subarray(from, from + m.compressed);
      if (m.method === 0) return raw;
      if (m.method !== 8) {
        throw new Error(`“${m.name}” uses a compression this browser cannot read.`);
      }
      if (typeof DecompressionStream !== "function") {
        throw new Error("This browser cannot unpack a zip. Open the backup on the iPhone app.");
      }
      const stream = new Blob([raw]).stream()
        .pipeThrough(new DecompressionStream("deflate-raw"));
      return new Uint8Array(await new Response(stream).arrayBuffer());
    },
  }));
}

/* ------------------------------------------------------------------- the offer */

const say = (html) => {
  const host = el("restore-body");
  if (host) host.innerHTML = html;
};

const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

/** "Sun 30 Aug, 14:07", on the reader's own clock: when *you* took this backup. */
function taken(entries) {
  const newest = entries.map((e) => e.savedUtc).filter(Boolean).sort().pop();
  if (!newest) return "Not recorded";
  return zonedFormat(newest, null, {
    weekday: "short", day: "2-digit", month: "short", year: "numeric",
    hour: "2-digit", minute: "2-digit",
  });
}

/**
 * Open the picked file and say what it holds, before anything is written.
 *
 * The count that matters is not how many sessions the file holds but how many it would
 * add, so both are printed. The already-here half is the dedupe, asked of Python once per
 * stored digest — the archive carries the digests, so this costs no analysis at all.
 */
async function offerRestore(file) {
  say(`<p class="note">Opening ${esc(file.name)}…</p>`);
  let members;
  try {
    members = await readZip(await file.arrayBuffer());
  } catch (err) {
    say(`<p class="note">${esc(err.message)}</p>`);
    return;
  }
  const indexMember = members.find((m) => /(^|\/)index\.json$/.test(m.name));
  if (!indexMember) {
    say(`<p class="note">That zip holds no library index, so it is not a CleanJibe
      backup. Download all on the Sessions tab writes the file this screen reads.</p>`);
    return;
  }
  let stored;
  try {
    stored = JSON.parse(new TextDecoder().decode(await indexMember.bytes()));
  } catch {
    stored = null;
  }
  if (!Array.isArray(stored) || !stored.length) {
    say(`<p class="note">That backup holds no sessions.</p>`);
    return;
  }

  const index = await listEntries();
  const indexJson = JSON.stringify(index);
  const buried = new Set((await listTombstones()).map((s) => s.id));
  const fits = new Map(members.filter((m) => /\.fit$/i.test(m.name))
    .map((m) => [stem(m.name), m]));

  const plan = [];
  let already = 0;
  let orphan = 0;
  for (const entry of stored) {
    const member = fits.get(stem(entry.fileName || `${entry.id}.fit`));
    if (!member) { orphan += 1; continue; }
    // Sessions you deleted after this backup stay deleted — the phone's own rule, and the
    // reason a tombstone survives the session it is about.
    if (buried.has(entry.id)) { already += 1; continue; }
    const hit = await ask("dedupe", { digestJson: JSON.stringify(entry), indexJson });
    if (hit.match) { already += 1; continue; }
    plan.push({ entry, member });
  }
  offer = { file, plan };

  const rows = [
    ["Taken", taken(stored)],
    ["Sessions", String(stored.length)],
    ["Already in your library", String(already)],
  ];
  if (orphan) rows.push(["Without a recording", String(orphan)]);
  say(`<p class="muted small">${esc(file.name)}</p>
    <div class="kv">${rows.map(([k, v]) =>
      `<div class="row"><span>${esc(k)}</span><span>${esc(v)}</span></div>`).join("")}</div>
    <p class="muted small">Nothing is deleted or overwritten. Sessions you already have
      keep their own analysis. Sessions you deleted after this backup stay deleted.</p>
    <p>
      <button class="primary small-btn" type="button" data-act="restore-go"${
        plan.length ? "" : " disabled"}>Restore ${esc(plural(plan.length, "session"))}</button>
      <button class="ghost small-btn" type="button" data-act="restore-cancel">Cancel</button>
    </p>
    <div id="restore-status" role="status"></div>`);
}

const stem = (name) => String(name).split("/").pop().replace(/\.(fit|zip)$/i, "");

/* ------------------------------------------------------------------ the restoring */

async function runRestore() {
  if (!offer || !offer.plan.length) return;
  const status = el("restore-status");
  const button = document.querySelector("#restore-body button[data-act=restore-go]");
  if (button) button.disabled = true;
  let added = 0;
  let skipped = 0;
  const failed = [];
  for (let i = 0; i < offer.plan.length; i += 1) {
    const { entry, member } = offer.plan[i];
    if (status) {
      status.innerHTML = `<p class="note">Restoring session ${i + 1} of ${
        offer.plan.length}…</p>`;
    }
    try {
      const outcome = await ingest(await member.bytes(), entry.fileName || member.name,
                                  { rider: entry.rider || null, example: entry.example === true });
      if (outcome.status === "added") added += 1;
      else if (outcome.status === "duplicate") skipped += 1;
      else failed.push(entry.fileName || member.name);
    } catch {
      failed.push(entry.fileName || member.name);
    }
  }
  await hooks.onChanged();
  offer = null;
  const lines = [`${plural(added, "session")} restored.`];
  if (skipped) lines.push(`${skipped} were already in your library.`);
  if (failed.length) lines.push(`${plural(failed.length, "recording")} could not be read.`);
  say(`<p class="note">${esc(lines.join(" "))}</p>`);
}

function reset() {
  offer = null;
  const host = el("restore-body");
  if (host) host.innerHTML = `<p class="note">${esc(host.dataset.empty || "")}</p>`;
}

/** Wire the Settings section. `onChanged` is the library's own refresh. */
export function mountBackup(options = {}) {
  hooks = { ...hooks, ...options };
  const pick = el("restore-pick");
  const input = el("restore-file");
  const host = el("restore-body");
  if (!pick || !input || !host) return;
  pick.addEventListener("click", () => input.click());
  input.addEventListener("change", () => {
    const file = input.files?.[0];
    input.value = "";
    if (file) offerRestore(file).catch((err) => say(`<p class="note">${esc(err.message)}</p>`));
  });
  host.addEventListener("click", (ev) => {
    const button = ev.target.closest("button[data-act]");
    if (!button) return;
    if (button.dataset.act === "restore-go") runRestore().catch(() => {});
    if (button.dataset.act === "restore-cancel") reset();
  });
  reset();
}
