/* Records & trends over the whole library.
 *
 * One Python call (`library.aggregate`) produces the entire view: the all-time record
 * winners with the window each was set in, the per-session series, the y-axis domains,
 * and the weighted totals. This file places SVG elements at coordinates. It does not
 * decide what the numbers are, and it must never start to — if a value is missing here,
 * add it to `lab_bundle/library.py`.
 *
 * The drawing idiom is the one js/render.js established: the same dark surface, the same
 * grid ink, series-1 blue for the primary line, its tint (plus a dashed stroke, so the
 * split survives a colour-vision check) for the second, direct end-labels instead of a
 * colour key, and markers that are hit targets with a tooltip.
 */

import { ask } from "./rpc.js";
import { C, esc, figureWidth, hideTip, hms, int, isNarrow, nf, showTip, svg } from "./render.js";

const el = (id) => document.getElementById(id);

const ROLE = {
  primary: { color: C.foil, dash: null, width: 1.9 },
  secondary: { color: C.tint, dash: "5 3", width: 1.7 },
};

let hooks = { openRecord: () => {}, openSession: () => {} };
let cache = { signature: null, data: null };

export function mountTrends(options) {
  hooks = { ...hooks, ...options };
  el("trends-body").addEventListener("click", onClick);
}

/**
 * (Re)build the view from the library index. `entries` are the stored digests — they go
 * to Python untouched, and everything drawn below comes back from it.
 */
export async function showTrends(entries) {
  const host = el("trends-body");
  if (!entries.length) {
    host.innerHTML = `<p class="note">No saved sessions yet. Records and trends appear
      once the library has something in it.</p>`;
    return;
  }
  const signature = entries.map((e) => e.id).join("|");
  if (cache.signature !== signature) {
    host.innerHTML = `<p class="note">Aggregating ${entries.length} sessions in Python…</p>`;
    try {
      cache = { signature, data: await ask("aggregate", { digestsJson: JSON.stringify(entries) }) };
    } catch (err) {
      host.innerHTML = `<p class="note">Could not aggregate the library: ${esc(err.message)}
        <br><br>The trends view needs the Python runtime; the library list itself does not,
        so your sessions are still there and still openable.</p>`;
      return;
    }
  }
  draw(host, cache.data);
}

/** Drop the memoised aggregate — call after a save or a delete. */
export function invalidateTrends() {
  cache = { signature: null, data: null };
}

/** Redraw from the memoised aggregate — the figures are sized to their container, so a
 *  rotation or a resize has to lay them out again. No Python call, nothing recomputed. */
export function redrawTrends() {
  if (cache.data) draw(el("trends-body"), cache.data);
}

/* --------------------------------------------------------------------- drawing */

function draw(host, agg) {
  host.innerHTML = `
    <div class="kv" id="trend-totals"></div>
    <h3 class="sub-head">All-time records</h3>
    <p class="muted small">Each record links back to the session it was set in, and to the
      exact window inside it — the provenance is in every analysis document under
      <code>records.windows</code>.</p>
    <div class="table-scroll"><table id="records-table"></table></div>
    <h3 class="sub-head">Session by session</h3>
    <p class="muted small">Oldest first. Click a point to open that session. A gap in a line
      is a session where the value could not be measured — not a zero.</p>
    <div id="trend-charts"></div>`;

  renderTotals(el("trend-totals"), agg.totals);
  renderRecords(el("records-table"), agg.records);
  const charts = el("trend-charts");
  for (const chart of agg.trends.charts) {
    const box = document.createElement("div");
    box.className = "trend-chart";
    box.innerHTML = `<div class="trend-head"><h4>${esc(chart.label)}</h4>` +
      (chart.unit ? `<span class="trend-unit">${esc(chart.unit)}</span>` : "") +
      `</div><div class="figure"></div>`;
    charts.appendChild(box);
    drawChart(box.querySelector(".figure"), chart, agg.trends.sessions);
  }
}

function renderTotals(host, t) {
  const rows = [
    ["Sessions", int(t.sessions)],
    ["Distance", `${nf(t.distanceKm, 1)} km`],
    ["Time on foil", hms(t.foilTimeS)],
    ["On foil", `${nf(t.foilPct, 1)} %`],
    ["Flights", int(t.flightCount)],
    ["Turns counted", int(t.turnsCounted)],
    ["Turns held", `${int(t.turnsSuccessful)} (${nf(t.turnSuccessPct, 0)} %)`],
    ["Port / starboard entries",
     `${int(t.turnsBySide.port.entries)} / ${int(t.turnsBySide.starboard.entries)}`],
  ];
  host.innerHTML = rows
    .map(([a, b]) => `<div class="row"><span>${esc(a)}</span><span>${esc(b)}</span></div>`)
    .join("");
}

function renderRecords(table, records) {
  if (!records.length) {
    table.innerHTML = "";
    return;
  }
  // `stack-sm` + data-th: on a phone this table restacks into one card per record (CSS).
  // The record's name leads the card; the rest become labelled rows.
  const head = ["record", "value", "session", "date", ""];
  table.className = "stack-sm";
  table.innerHTML = `<thead><tr>${head.map((h, i) =>
    `<th${i !== 1 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${records.map((r) => `
      <tr data-record="${esc(r.key)}">
        <td class="l stack-lead" data-th="record">${esc(r.label)}</td>
        <td data-th="value"><strong>${nf(r.value, 2)}</strong> <span class="dim">${esc(r.unit)}</span></td>
        <td class="l" data-th="session">${esc(r.spot || r.fileName || r.id)}</td>
        <td class="l dim" data-th="date">${esc(r.dateUtc || "—")}</td>
        <td class="l stack-actions" data-th=""><button class="ghost small-btn" data-act="record"
          data-id="${esc(r.id)}">Show the window</button></td>
      </tr>`).join("")}</tbody>`;
}

/* ----------------------------------------------------------------------- charts */

function drawChart(host, chart, sessions) {
  host.innerHTML = "";
  const W = figureWidth(host);
  const narrow = isNarrow(W);
  // Desktop keeps a wide right gutter for the direct end-labels. On a phone that gutter
  // would be half the chart, so the labels move inside the plot instead (see below) and
  // the gutter shrinks to nothing.
  const H = narrow ? Math.round(Math.max(170, W * 0.56)) : 220;
  const nLines = Math.max(1, chart.lines.length);
  const L = narrow ? 34 : 52, R = narrow ? 12 : 176, B = 34;
  const T = narrow ? 10 + nLines * 12 : 16;      // narrow: the line labels live above the plot
  const n = sessions.length;
  const plot = W - L - R;
  // One column per session: categorical, evenly spaced, because sessions are events and
  // not a continuous time axis. A single session sits in the middle of its column.
  const X = (i) => (n === 1 ? L + plot / 2 : L + (i / (n - 1)) * plot);
  const Y = (v) => H - B - (v / chart.yMax) * (H - T - B);

  const root = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img",
                            "aria-label": `${chart.label} per session` }, host);
  svg("rect", { width: W, height: H, fill: C.surface }, root);

  for (let v = 0; v <= chart.yMax + 1e-9; v += chart.yStep) {
    svg("line", { x1: L, x2: W - R, y1: Y(v), y2: Y(v), stroke: C.grid, "stroke-width": 1,
                  opacity: v === 0 ? 0.9 : 0.45 }, root);
    const t = svg("text", { x: L - 8, y: Y(v) + 3.5, "text-anchor": "end",
                            "font-size": 10.5, fill: C.ink3 }, root);
    t.textContent = chart.yStep >= 1 ? String(Math.round(v)) : v.toFixed(1);
  }

  // A "06 Aug" tick is ~42 units wide; leave at least that much between the ones we keep.
  const stride = Math.max(1, Math.ceil(n / Math.max(2, Math.floor(plot / (narrow ? 52 : 120)))));
  sessions.forEach((s, i) => {
    if (i % stride && i !== n - 1) return;
    const first = i === 0, last = i === n - 1;
    const t = svg("text", {
      // The end ticks are pulled inside the plot so they cannot hang off the figure.
      x: narrow && first ? L : narrow && last ? W - R : X(i),
      y: H - B + 16,
      "text-anchor": narrow && first ? "start" : narrow && last ? "end" : "middle",
      "font-size": 10.5, fill: C.ink3,
    }, root);
    t.textContent = tickLabel(s.startUtc);
  });

  chart.lines.forEach((line, li) => {
    const style = ROLE[line.role] || ROLE.primary;
    let run = [];
    const flush = () => {
      if (run.length > 1) {
        svg("polyline", { points: run.join(" "), fill: "none", stroke: style.color,
                          "stroke-width": style.width, "stroke-dasharray": style.dash,
                          "stroke-linejoin": "round", "stroke-linecap": "round" }, root);
      }
      run = [];
    };
    for (const p of line.points) {
      if (p.v === null) { flush(); continue; }
      run.push(`${X(p.i).toFixed(1)},${Y(p.v).toFixed(1)}`);
    }
    flush();

    let last = null;
    for (const p of line.points) {
      if (p.v === null) continue;
      last = p;
      const dot = svg("circle", { cx: X(p.i), cy: Y(p.v), r: 3.2, fill: style.color,
                                  stroke: C.surface, "stroke-width": 1.2 }, root);
      dot.dataset.session = p.id;
      dot.style.cursor = "pointer";
      const s = sessions[p.i] || {};
      const html = `<b>${esc(s.spot || s.id)}</b><br>${esc(s.dateUtc || "")}<br>` +
                   `${esc(chart.label)} · ${esc(line.label)}: ` +
                   `<b>${nf(p.v, 2)}</b> ${esc(chart.unit)}`;
      dot.addEventListener("pointerenter", (ev) => showTip(ev, html));
      dot.addEventListener("pointermove", (ev) => showTip(ev, html));
      dot.addEventListener("pointerleave", hideTip);
    }
    // Direct end-label instead of a colour key: the reader never has to match a swatch.
    // Narrow charts have no right gutter to put it in, so it goes above the last point,
    // right-aligned to the plot edge — still directly attached to its own line, still no
    // swatch to match, and haloed in the surface colour so it survives over the grid.
    if (last) {
      const t = svg("text", {
        x: narrow ? W - R : Math.min(X(last.i) + 10, W - R + 8),
        y: narrow ? T - 8 - (nLines - 1 - li) * 12 : Y(last.v) + 3.5 + (li ? 13 : 0),
        "text-anchor": narrow ? "end" : "start",
        "font-size": narrow ? 10.5 : 11,
        "font-weight": 600, fill: style.color, stroke: C.surface,
        "stroke-width": 3, "paint-order": "stroke",
      }, root);
      t.textContent = line.label;
    }
  });
}

const tickLabel = (utc) => (utc
  ? new Date(utc).toLocaleDateString("en-GB", { month: "short", day: "2-digit" })
  : "—");

/* ---------------------------------------------------------------------- actions */

function onClick(ev) {
  const dot = ev.target.closest("circle[data-session]");
  if (dot) { hooks.openSession(dot.dataset.session); return; }
  const button = ev.target.closest("button[data-act=record]");
  if (!button) return;
  const key = button.closest("tr")?.dataset.record;
  const record = (cache.data?.records || []).find((r) => r.key === key);
  if (record) hooks.openRecord(record);
}
