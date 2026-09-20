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
 * WATCH VS PHONE is the kit's `DivergenceCheck`, in the browser. Its thresholds are the
 * kit's to the digit (foil time over 5 %, any speed record over 0.3 kn, a count off by more
 * than one) and its advice is the kit's sentence for sentence. The watch's own numbers
 * reach the page as `meta.watch`, which `lab_bundle/web_entry.py` reads out of the session's
 * developer fields; a recording that carries none has nothing to compare and the block is
 * ABSENT, never a table of zeroes (docs/presentation.md, missing is absent).
 *
 * Nothing here derives a metric. Both sides of every row are printed as they arrived: the
 * watch's from the FIT, the phone's from the analysis document.
 */

import { speed, speedUnit, speedValue } from "./appsettings.js";
import { renderSessionGear } from "./gear.js";
import { esc } from "./render.js";

const el = (id) => document.getElementById(id);

/* --------------------------------------------------------- the divergence thresholds */

/** `DivergenceCheck.foilTimePctThreshold` (ios/WingFoilKit/.../DivergenceCheck.swift). */
const FOIL_TIME_PCT = 5.0;
/** `DivergenceCheck.recordKnThreshold` — in KNOTS, whatever unit the table prints. */
const RECORD_KN = 0.3;
/** `DivergenceCheck.countThreshold`. */
const COUNT = 1;

/** The six speed records the two devices both claim, in the kit's order and its words. */
const RECORDS = [
  ["Best 2 s", "best2sKn", "best2sKn"],
  ["Best 10 s", "best10sKn", "best10sKn"],
  ["Best 5×10 s", "best5x10sKn", "best5x10sKn"],
  ["Best 500 m", "best500mKn", "best500mKn"],
  ["Best 1 NM", "bestNmKn", "bestNmKn"],
  ["Alpha 500", "alpha500Kn", "alpha500Kn"],
];

/** `mm:ss`, the kit's `DivergenceCheck.seconds`. */
function clock(seconds) {
  const total = Math.round(seconds);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

const signed = (value, digits = 0) =>
  `${value >= 0 ? "+" : "-"}${Math.abs(value).toFixed(digits)}`;

/**
 * Every disagreement worth a row, as the kit finds them.
 *
 * `watch` is `meta.watch`; `golden` is the analysis document's own golden. An empty list
 * means the two agree, which is a different answer from having nothing to compare — the
 * caller tells them apart by whether `watch` was there at all.
 */
export function divergences(watch, golden) {
  if (!watch || !golden) return [];
  const out = [];
  const summary = golden.summary || {};
  const records = golden.records || {};

  if (typeof watch.foilTimeS === "number" && watch.foilTimeS > 0
      && typeof summary.foilTimeS === "number") {
    const drift = (summary.foilTimeS - watch.foilTimeS) / watch.foilTimeS * 100;
    if (Math.abs(drift) > FOIL_TIME_PCT) {
      out.push({ metric: "Foil time", watch: clock(watch.foilTimeS),
                 phone: clock(summary.foilTimeS), delta: `${signed(drift)} %` });
    }
  }

  for (const [label, watchKey, phoneKey] of RECORDS) {
    const w = watch[watchKey];
    const p = records[phoneKey];
    if (typeof w !== "number" || typeof p !== "number" || w <= 0 || p <= 0) continue;
    if (Math.abs(p - w) <= RECORD_KN) continue;
    // The threshold is in knots; the row is in the unit this browser reads. Converting the
    // gap rather than the threshold keeps the rule the kit's and the print the reader's.
    const gap = speedValue(p) - speedValue(w);
    out.push({ metric: label, watch: speed(w), phone: speed(p),
               delta: `${signed(gap, 2)} ${speedUnit()}` });
  }

  const counts = [
    ["Flights", watch.flightCount, summary.flightCount],
    ["Tacks", watch.tackCount, summary.turns?.tacks],
    ["Jibes", watch.jibeCount, summary.turns?.jibes],
    ["Takeoff attempts", watch.takeoffAttempts, summary.takeoff?.takeoffAttempts],
    // **"Takeoffs", not "Takeoff successes"** (20 September 2026, `DivergenceCheck`). A
    // banner row is read beside the watch's own word for the same count, and `success` is
    // engine vocabulary that reaches no rider text (CLAUDE.md). `advice` below still reads
    // the prefix, which both takeoff rows keep.
    ["Takeoffs", watch.takeoffSuccesses, summary.takeoff?.takeoffSuccesses],
  ];
  for (const [label, w, p] of counts) {
    if (typeof w !== "number" || typeof p !== "number") continue;
    if (Math.abs(p - w) <= COUNT) continue;
    out.push({ metric: label, watch: String(w), phone: String(p), delta: signed(p - w) });
  }
  return out;
}

/**
 * The advice under the table, the kit's `DivergenceDetailCard.advice`.
 *
 * The takeoff-only case earns the calmer ending: the watch counts attempts live on a wrist
 * and the phone reads the whole session back afterwards, so those two are expected to
 * differ in a way a speed is not.
 */
function advice(rows) {
  const base = "Trust the phone's numbers. It reads the whole session back afterwards. "
    + "The watch has to work these out live on your wrist, as you ride. "
    + "Nothing is wrong with your session.";
  const takeoffOnly = rows.length > 0 && rows.every((r) => r.metric.startsWith("Takeoff"));
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
