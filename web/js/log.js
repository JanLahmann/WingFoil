/* The session page's Log tab: what was ridden, and where the two devices disagree.
 *
 * Ride, Turns and Takeoffs are three readings of what happened on the water. Log is the
 * fourth thing a session is — a record, with a provenance — and the phone puts four blocks
 * on it (ios/WingFoil/Features/SessionDetail/SessionLogView.swift): gear, wind, the
 * recording, and the watch against the phone. The browser already had the wind and the
 * recording in the badges above the switcher, so this file adds the two it did not have.
 *
 * GEAR is `js/gear.js`'s to draw; this file only says which session it is for.
 *
 * WATCH VS PHONE is the kit's `DivergenceCheck`, **read off the presentation document**
 * (ADR-033, round 3). The check itself runs once, in `lab_bundle/web_entry.py`, against the
 * watch's own session fields; the thresholds and the metric set are the kit's to the digit
 * and live there. What is left here is the kit's `DivergenceText`: a line is `{metricId,
 * labelId, watch, phone, unitKind}` — ids and **raw** values — and this turns it into a
 * name, two numbers in the rider's unit and the signed difference. A recording that carries
 * no watch summary has nothing to compare and the block is ABSENT, never a table of zeroes
 * (docs/presentation.md, missing is absent).
 *
 * Nothing here derives a metric, and since round 3 nothing here derives a threshold either.
 */

import { speed, speedUnit, speedValue } from "./appsettings.js";
import { renderSessionGear } from "./gear.js";
import { text } from "./presentation.js";
import { esc } from "./render.js";

const el = (id) => document.getElementById(id);

/* ------------------------------------------------------------------ the banner's words */

const signed = (value, digits = 0) =>
  `${value >= 0 ? "+" : "-"}${Math.abs(value).toFixed(digits)}`;

/** One side of a row, in the unit the rider reads — `DivergenceText.value`.
 *
 *  Foil time is `m:ss`, which is the banner's own spelling and deliberately not the block's
 *  `10:45 min`: this is a *duration measured by two devices*, which is what the table is
 *  comparing, rather than the session clock. */
function value(raw, unitKind) {
  if (unitKind === "durationS") {
    const total = Math.round(raw);
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
  }
  if (unitKind === "speedKn") return speed(raw);
  return String(Math.round(raw));
}

/**
 * The signed difference, **in the unit the difference is interesting in** —
 * `DivergenceText.delta`, and the one judgement the document deliberately leaves here.
 *
 * A percentage for foil time (five minutes on an hour is not five minutes on four), the
 * rider's speed unit for a record, a plain signed integer for a count.
 */
function delta(line) {
  const change = line.phone - line.watch;
  if (line.unitKind === "durationS") {
    return line.watch > 0 ? `${signed(change / line.watch * 100)} %` : "—";
  }
  if (line.unitKind === "speedKn") {
    return `${signed(speedValue(line.phone) - speedValue(line.watch), 2)} ${speedUnit()}`;
  }
  return signed(Math.round(change));
}

/** One document line as the table prints it. */
const row = (line) => ({
  metric: text(line.labelId) ?? line.metricId,
  watch: value(line.watch, line.unitKind),
  phone: value(line.phone, line.unitKind),
  delta: delta(line),
});

/**
 * The advice under the table, the kit's `DivergenceDetailCard.advice`.
 *
 * The takeoff-only case earns the calmer ending: the watch counts attempts live on a wrist
 * and the phone reads the whole session back afterwards, so those two are expected to
 * differ in a way a speed is not. It reads the **metric ids**, not the printed names, which
 * is `DivergenceText.isTakeoffOnly` and is why a renamed column cannot change the sentence.
 */
function advice(lines) {
  const base = "Trust the phone's numbers. It reads the whole session back afterwards. "
    + "The watch has to work these out live on your wrist, as you ride. "
    + "Nothing is wrong with your session.";
  const takeoffOnly = lines.length > 0 && lines.every(
    (l) => l.metricId === "takeoffs" || l.metricId === "takeoffAttempts");
  return takeoffOnly
    ? base + " Takeoff and pump counting is where the two differ most. "
      + "Keep the watch app up to date to narrow the gap."
    : base;
}

/* --------------------------------------------------------------------- the rendering */

let lastSessionId = null;

/**
 * Draw both blocks for the document on screen.
 *
 * `sessionId` is the library id when the session is stored and null when it is not — a
 * freshly dropped file has no row to hang a gear assignment on yet.
 */
export function showLog(result, sessionId = null) {
  lastSessionId = sessionId;
  renderSessionGear(el("log-gear"), sessionId).catch(() => {});
  renderDivergence(result);
}

function renderDivergence(result) {
  const panel = el("log-divergence-panel");
  const host = el("log-divergence");
  if (!panel || !host) return;
  const watch = result?.meta?.watch;
  // Nothing to compare: no watch summary in this recording. The block is not here at all,
  // which is the honest answer and the phone's own.
  //
  // A CLASS rather than `hidden`, because `hidden` on this element belongs to somebody
  // else: js/sections.js sets it on every `.panel[data-section]` when a chip is pressed,
  // so a panel that hid itself would be un-hidden the next time the reader tapped Log.
  panel.classList.toggle("is-absent", !watch);
  if (!watch) {
    host.innerHTML = "";
    return;
  }
  const rows = divergences(watch, result.golden);
  if (!rows.length) {
    host.innerHTML = `<p class="note">${esc(host.dataset.empty || "")}</p>`;
    return;
  }
  host.innerHTML = `<div class="table-scroll"><table class="divergence-table">
    <thead><tr><th>metric</th><th>watch</th><th>phone</th><th>&Delta;</th></tr></thead>
    <tbody>${rows.map((r) => `<tr>
      <td>${esc(r.metric)}</td><td>${esc(r.watch)}</td><td>${esc(r.phone)}</td>
      <td class="delta">${esc(r.delta)}</td></tr>`).join("")}</tbody></table></div>
    <p class="muted small">${esc(advice(rows))}</p>`;
}

/** Redraw the gear card after the quiver changed, without a new analysis. */
export function refreshLog() {
  renderSessionGear(el("log-gear"), lastSessionId).catch(() => {});
}
