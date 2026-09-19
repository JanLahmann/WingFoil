/* Wings, boards and foils, and what each session was ridden on.
 *
 * The phone keeps three kinds of gear as rows of their own, with a history behind each and
 * the combo recorded per session (ios/WingFoil/Features/Gear). This is that, ported: the
 * same three kinds, the same editor fields, the same words. The Gear & spots tab lists the
 * quiver; the session page's Log tab assigns one of each to the afternoon on screen.
 *
 * It replaces the one free-text name per session that `js/appsettings.js` kept, and reads
 * that name forward: a library that already has "Duotone Unit 5 m" typed on nine sessions
 * arrives here with the wing in the quiver and those nine sessions assigned to it. A rider
 * does not retype what he already typed.
 *
 * Nothing here is a metric. A gear name is a rider's note, and the totals beside it are
 * counts of his own rows.
 */

import { db } from "./appdb.js";
import { gearMap } from "./appsettings.js";
import { esc, hms, int, nf } from "./render.js";
import { listEntries } from "./store.js";

const store = db("wingfoil-gear");
const QUIVER = "quiver.json";
const ASSIGNED = "assigned.json";

/** The three kinds, in the phone's order, with the phone's labels (`GearKind`). */
export const KINDS = [
  { id: "wing", label: "Wing", plural: "Wings" },
  { id: "board", label: "Board", plural: "Boards" },
  { id: "foil", label: "Foil", plural: "Foils" },
];

const el = (id) => document.getElementById(id);
const listeners = new Set();

/** Called whenever the quiver or an assignment changes, so a list on screen can redraw. */
export function onGearChange(fn) {
  listeners.add(fn);
}

const announce = () => {
  for (const fn of listeners) fn();
};

/* ------------------------------------------------------------------- the quiver */

let migrated = false;

/**
 * Every row in the quiver, retired ones included, newest name last.
 *
 * The first read also carries the old per-session names across. It runs once per page,
 * writes only when there is something to write, and is keyed on the name — two sessions
 * that said "Armstrong HA 925" were always one foil, and the rider said so by typing it
 * twice.
 */
export async function listGear() {
  const rows = (await store.get(QUIVER, [])) || [];
  if (migrated) return rows;
  migrated = true;
  const legacy = gearMap();
  const names = new Set(rows.map((r) => r.name.toLowerCase()));
  const added = [];
  const assigned = { ...((await store.get(ASSIGNED, {})) || {}) };
  let touched = false;
  for (const [sessionId, name] of Object.entries(legacy)) {
    const clean = String(name || "").trim();
    if (!clean) continue;
    let row = [...rows, ...added].find((r) => r.name.toLowerCase() === clean.toLowerCase());
    if (!row && !names.has(clean.toLowerCase())) {
      // A name typed on a session says what it is called and nothing about which kind it
      // is, so it lands on `wing` and the rider moves it. Guessing "board" from the word
      // "board" would be right nine times and wrong once, silently.
      row = { id: newId(), name: clean, notes: null, kind: "wing", active: true };
      added.push(row);
      names.add(clean.toLowerCase());
    }
    if (row && !assigned[sessionId]) {
      assigned[sessionId] = { [row.kind]: row.id };
      touched = true;
    }
  }
  if (added.length) await store.put(QUIVER, [...rows, ...added]);
  if (touched) await store.put(ASSIGNED, assigned);
  return added.length ? [...rows, ...added] : rows;
}

const newId = () => `g${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;

/** Add or replace one row. Returns the saved row, with the id it ended up with. */
export async function saveGear(row) {
  const rows = await listGear();
  const clean = {
    id: row.id || newId(),
    name: String(row.name || "").trim(),
    notes: String(row.notes || "").trim() || null,
    kind: KINDS.some((k) => k.id === row.kind) ? row.kind : "wing",
    active: row.active !== false,
  };
  if (!clean.name) return null;
  const kept = rows.filter((r) => r.id !== clean.id);
  kept.push(clean);
  await store.put(QUIVER, kept);
  announce();
  return clean;
}

/* --------------------------------------------------------------- the assignments */

/** `{wing, board, foil}` for one session, each a gear id or absent. */
export async function gearOfSession(sessionId) {
  await listGear();                       // the carry-across runs before the first read
  const all = (await store.get(ASSIGNED, {})) || {};
  return all[sessionId] || {};
}

export async function assignGear(sessionId, kind, gearId) {
  const all = { ...((await store.get(ASSIGNED, {})) || {}) };
  const row = { ...(all[sessionId] || {}) };
  if (gearId) row[kind] = gearId;
  else delete row[kind];
  if (Object.keys(row).length) all[sessionId] = row;
  else delete all[sessionId];
  await store.put(ASSIGNED, all);
  announce();
}

/** Every session assigned to one gear row, for the totals beside its name. */
async function useCounts() {
  const all = (await store.get(ASSIGNED, {})) || {};
  const entries = await listEntries().catch(() => []);
  const byId = new Map(entries.map((e) => [e.id, e]));
  const out = new Map();
  for (const [sessionId, row] of Object.entries(all)) {
    const entry = byId.get(sessionId);
    if (!entry) continue;
    for (const gearId of Object.values(row)) {
      const tally = out.get(gearId) || { sessions: 0, km: 0, foilS: 0 };
      tally.sessions += 1;
      tally.km += entry.distanceKm || 0;
      tally.foilS += entry.foilTimeS || 0;
      out.set(gearId, tally);
    }
  }
  return out;
}

/* ------------------------------------------------------ the Gear & spots sections */

/**
 * Wings, boards and foils under the spots, as the phone stacks them.
 *
 * `host` carries its own empty state in `data-empty` so the markup holds the sentence and
 * the verifier can read it without a browser — the same reason every other ported screen
 * on this page carries one.
 */
export async function renderQuiver(host) {
  if (!host) return;
  const rows = await listGear();
  const counts = await useCounts();
  const empty = host.dataset.empty || "";
  const parts = [];
  for (const kind of KINDS) {
    const mine = rows.filter((r) => r.kind === kind.id)
      .sort((a, b) => Number(b.active) - Number(a.active) || a.name.localeCompare(b.name));
    parts.push(`<h3 class="sub-head">${esc(kind.plural)}</h3>`);
    parts.push(mine.length
      ? `<ul class="quiver-list">${mine.map((r) => gearRow(r, counts.get(r.id))).join("")}</ul>`
      // "No wings yet" — the phone's own per-kind empty state. The wing's is the sentence
      // the markup pins, because one of the three is enough to hold the wording.
      : `<p class="note">${esc(kind.id === "wing" && empty ? empty : `No ${kind.label.toLowerCase()}s yet`)}</p>`);
    parts.push(`<p><button class="ghost small-btn" type="button" data-add-gear="${kind.id}">Add ${
      esc(kind.label.toLowerCase())}</button></p>`);
  }
  parts.push(`<p class="muted small">Your quiver stays in this browser. Name a session's
    gear on its Log tab.</p>`);
  host.innerHTML = parts.join("");
  wireQuiver(host);
}

function gearRow(row, tally) {
  const totals = tally
    ? `${int(tally.sessions)} session${tally.sessions === 1 ? "" : "s"} · ${
        nf(tally.km, 1)} km · ${hms(tally.foilS)} on foil`
    : "Not ridden yet";
  return `<li data-gear-id="${esc(row.id)}">
    <span class="quiver-name">${esc(row.name)}${row.active ? "" : " <i>retired</i>"}</span>
    <span class="dim">${esc(totals)}</span>
    ${row.notes ? `<span class="dim">${esc(row.notes)}</span>` : ""}
    <button class="ghost small-btn" type="button" data-edit-gear="${esc(row.id)}">Edit</button>
  </li>`;
}

function wireQuiver(host) {
  for (const button of host.querySelectorAll("button[data-add-gear]")) {
    button.addEventListener("click", () => openGearSheet({ kind: button.dataset.addGear }));
  }
  for (const button of host.querySelectorAll("button[data-edit-gear]")) {
    button.addEventListener("click", async () => {
      const row = (await listGear()).find((r) => r.id === button.dataset.editGear);
      if (row) openGearSheet(row);
    });
  }
}

/* ------------------------------------------------------- the session's gear card */

/**
 * The combo one session was ridden on — the phone's `SessionGearCard`, as three pickers.
 *
 * A session that is not in the library yet has no id to hang an assignment on, and saying
 * so beats a picker that forgets what it was told. The empty quiver gets the phone's own
 * sentence, which is the one in `data-empty`.
 */
export async function renderSessionGear(host, sessionId) {
  if (!host) return;
  const rows = await listGear();
  if (!sessionId) {
    host.innerHTML = `<p class="note">Save this session to the library to name its gear.</p>`;
    return;
  }
  const assigned = await gearOfSession(sessionId);
  const pickers = KINDS.map((kind) => {
    const mine = rows.filter((r) => r.kind === kind.id
      && (r.active || r.id === assigned[kind.id]));
    const options = [`<option value="">Not set</option>`,
      ...mine.map((r) => `<option value="${esc(r.id)}"${
        r.id === assigned[kind.id] ? " selected" : ""}>${esc(r.name)}</option>`)];
    return `<label class="gear-row"><span>${esc(kind.label)}</span>
      <select data-assign="${esc(kind.id)}">${options.join("")}</select></label>`;
  }).join("");
  const bare = !rows.length;
  host.innerHTML = pickers
    + (bare ? `<p class="note">${esc(host.dataset.empty || "")}</p>` : "")
    + `<p><button class="ghost small-btn" type="button" data-add-gear="wing">Add gear</button></p>`;

  for (const select of host.querySelectorAll("select[data-assign]")) {
    select.addEventListener("change", () =>
      assignGear(sessionId, select.dataset.assign, select.value || null));
  }
  for (const button of host.querySelectorAll("button[data-add-gear]")) {
    button.addEventListener("click", () => openGearSheet({ kind: button.dataset.addGear }));
  }
}

/* --------------------------------------------------------------- the New gear sheet */

let editing = null;
let kindChoice = "wing";

/** The phone's gear editor: a name, a kind, notes, and the retire switch. */
export function openGearSheet(row = {}) {
  const dialog = el("gear-dialog");
  if (!dialog || dialog.open) return;
  editing = row.id ? { ...row } : null;
  kindChoice = KINDS.some((k) => k.id === row.kind) ? row.kind : "wing";
  el("gear-dialog-title").textContent = row.name ? row.name : "New gear";
  el("gear-name").value = row.name || "";
  el("gear-notes").value = row.notes || "";
  el("gear-active").checked = row.active !== false;
  markKind();
  dialog.showModal();
  el("gear-name").focus();
}

function markKind() {
  for (const button of document.querySelectorAll("#gear-dialog .seg-btn[data-kind]")) {
    button.setAttribute("aria-pressed", String(button.dataset.kind === kindChoice));
  }
}

export function mountGear() {
  const dialog = el("gear-dialog");
  if (!dialog) return;
  for (const button of dialog.querySelectorAll(".seg-btn[data-kind]")) {
    button.addEventListener("click", () => {
      kindChoice = button.dataset.kind;
      markKind();
    });
  }
  el("gear-cancel").addEventListener("click", () => dialog.close());
  el("gear-save").addEventListener("click", async () => {
    const saved = await saveGear({
      id: editing?.id,
      name: el("gear-name").value,
      notes: el("gear-notes").value,
      kind: kindChoice,
      active: el("gear-active").checked,
    });
    // A blank name is not a wing. The sheet stays open on the field the rider has to fill.
    if (!saved) {
      el("gear-name").focus();
      return;
    }
    dialog.close();
  });
}
