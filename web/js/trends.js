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
import { sportCorrected } from "./cardstats.js";
import { C, esc, figureWidth, hideTip, hms, int, isNarrow, nf, showTip, svg,
         zonedFormat } from "./render.js";

const el = (id) => document.getElementById(id);

/** What a session is called in a record row or a chart tooltip. The digest's `spot` is
 *  derived from the filename, so it needs the same one correction the library list and the
 *  share card's headline apply — see `sportCorrected`. */
const sessionLabel = (s, ...fallbacks) =>
  sportCorrected(s?.spot || "") || fallbacks.find((f) => f) || "";

// A line's `role` (set in lab_bundle/library.py) picks its ink. `primary`/`secondary` are
// the app's own two blues for a metric with no vocabulary of its own; the two `side.*`
// roles exist because a chart about ENTRY TACK must not borrow one that means something
// else — see docs/presentation.md "Entry tack" and app-ui-review.md §5.2.
const ROLE = {
  primary: { color: C.foil, dash: null, width: 1.9 },
  secondary: { color: C.tint, dash: "5 3", width: 1.7 },
  sidePort: { color: C.sidePort, dash: null, width: 1.9 },
  sideStarboard: { color: C.sideStarboard, dash: "5 3", width: 1.7 },
};

let hooks = { openRecord: () => {}, openSession: () => {}, openPeriodCard: () => {} };
let cache = { signature: null, data: null };
/** The stored digests this view is currently showing. Kept because the custom range is the
 *  one question Python has to be asked again for, and it needs the same input the aggregate
 *  was given — not a second, subtly different list. */
let entries = [];
/** The last range the rider asked for, so its "Share card" button has something to open,
 *  and the two dates he typed, so a resize does not throw them away — `redrawTrends` lays
 *  the whole view out again, and a form that empties itself on a rotation is a form. */
let customPeriod = null;
let rangeFrom = "";
let rangeTo = "";

export function mountTrends(options) {
  hooks = { ...hooks, ...options };
  el("trends-body").addEventListener("click", onClick);
}

/**
 * (Re)build the view from the library index. `entries` are the stored digests — they go
 * to Python untouched, and everything drawn below comes back from it.
 */
export async function showTrends(saved) {
  const host = el("trends-body");
  entries = saved;
  if (!entries.length) {
    host.innerHTML = `<p class="note">No saved sessions yet. Save a couple of sessions to
      the library and your all-time records and season trends appear here.</p>`;
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
  // A saved or deleted session changes which afternoons a range holds, so the answer this
  // view is still showing for one is out of date too.
  customPeriod = null;
}

/** Redraw from the memoised aggregate — the figures are sized to their container, so a
 *  rotation or a resize has to lay them out again. No Python call, nothing recomputed. */
export function redrawTrends() {
  if (cache.data) draw(el("trends-body"), cache.data);
}

/* --------------------------------------------------------------------- drawing */

function draw(host, agg) {
  // `agg.count` is what `library.aggregate` actually aggregated, not what the library
  // holds: the bundled example and a friend's session are shown in full and counted in
  // nothing (`library.counts_towards_records`, the one place that rule lives). A library
  // made only of those has no records to draw and must say why, rather than drawing a
  // chart of zero sessions. This file does not know the rule and must not learn it.
  if (!agg.count) {
    host.innerHTML = `<p class="note">Nothing saved here counts towards your records yet —
      the example session and sessions a friend rode are kept out of them. Save one of
      your own and the records and trends fill in.</p>`;
    return;
  }
  host.innerHTML = `
    <div class="kv" id="trend-totals"></div>
    <h3 class="sub-head">All-time records</h3>
    <p class="muted small">Each record links back to the session it was set in, and to the
      exact window inside it — the provenance is in every analysis document under
      <code>records.windows</code>.</p>
    <div class="table-scroll"><table id="records-table"></table></div>
    <h3 class="sub-head">Session records</h3>
    <p class="muted small">All-time bests that are not speeds — the afternoons themselves.
      No certification applies here: a degraded recording can misreport a speed, but the
      number of jibes it holds and the minutes it lasted are not claims its speed channel
      makes.</p>
    <div class="table-scroll"><table id="session-records-table"></table></div>
    <h3 class="sub-head">Periods</h3>
    <p class="muted small">A trip, a month or a season, each with the same block of numbers.
      A trip is one spot with no gap wider than ${esc(String(GAP_DAYS))} days and at least
      two sessions — a holiday, found rather than filed. Rates over a period divide the
      period's own totals: they are not the average of the sessions' own.</p>
    <div id="period-custom"></div>
    <div id="period-groups"></div>
    <h3 class="sub-head">Session by session</h3>
    <p class="muted small">Oldest first. Click a point to open that session. A gap in a line
      is a session where the value could not be measured — not a zero.</p>
    <div id="trend-charts"></div>`;

  renderTotals(el("trend-totals"), agg.totals);
  renderRecords(el("records-table"), agg.records);
  renderSessionRecords(el("session-records-table"), agg.sessionRecords || []);
  renderPeriods(el("period-groups"), agg.periods || {});
  renderCustomRange(el("period-custom"));
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
  drawWeeks(charts, agg.trends.weeks || []);
}

function renderTotals(host, t) {
  const rows = [
    ["Sessions", int(t.sessions)],
    ["Distance", `${nf(t.distanceKm, 1)} km`],
    ["Time on foil", hms(t.foilTimeS)],
    ["On foil", `${nf(t.foilPct, 1)} %`],
    ["Flights", int(t.flightCount)],
    ["Turns counted", int(t.turnsCounted)],
    ["Clean jibes", `${int(t.turnsSuccessful)} (${nf(t.turnSuccessPct, 0)} %)`],
    ["Port / starboard entries",
     `${int(t.turnsBySide.port.entries)} / ${int(t.turnsBySide.starboard.entries)}`],
  ];
  host.innerHTML = rows
    .map(([a, b]) => `<div class="row"><span>${esc(a)}</span><span>${esc(b)}</span></div>`)
    .join("");
}

/** The mark on a record no recording could certify (engine 0.9.0, `library.py._stamp`).
 *
 *  It sits beside the *value*, not beside the session, because the value is the claim: a
 *  class-(c) session had its speed differentiated from positions rather than measured by
 *  the receiver, and a differentiated speed is noisier and can read high. The record is
 *  still shown — it is still the rider's afternoon — and it is shown marked, because an
 *  all-time best is exactly where an unverifiable number does the most damage. */
const UNCERTIFIED = ' <span class="badge" title="This session carried no speed channel — a '
  + 'GPX, or another degraded source. Its speed was differentiated from positions, which is '
  + 'noisier and can read high, so this record cannot be certified.">uncertified</span>';

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
        <td data-th="value"><strong>${nf(r.value, 2)}</strong> <span class="dim">${esc(r.unit)}</span>${
          r.certified === false ? UNCERTIFIED : ""}</td>
        <td class="l" data-th="session">${esc(sessionLabel(r, r.fileName, r.id))}</td>
        <td class="l dim" data-th="date">${esc(localDate(r) || "—")}</td>
        <td class="l stack-actions" data-th=""><button class="ghost small-btn" data-act="record"
          data-id="${esc(r.id)}">Show the window</button></td>
      </tr>`).join("")}</tbody>`;
}

/** A session record's value in the unit `library.py` gave it. The unit strings are the
 *  contract — this file still decides nothing about the number, only how it reads. */
function recordValue(r) {
  switch (r.unit) {
    case "s": return `${hms(r.value)}<span class="dim"> h:m:s</span>`;
    case "%": return `<strong>${nf(r.value, 1)}</strong> <span class="dim">%</span>`;
    case "km": return `<strong>${nf(r.value, 2)}</strong> <span class="dim">km</span>`;
    case "/h": return `<strong>${nf(r.value, 2)}</strong> <span class="dim">/ h</span>`;
    default: return `<strong>${int(r.value)}</strong>`;
  }
}

/** The second records table: bests that are not speeds.
 *
 *  Same shape as the speed table above it and deliberately so — the rider is reading one
 *  page of personal bests, not two screens with different manners. Two differences, both
 *  load-bearing: there is no `uncertified` badge, because a session record makes no claim
 *  the speed channel could get wrong; and the action opens the *session* rather than a
 *  window inside it, because the record is the whole afternoon. */
function renderSessionRecords(table, records) {
  if (!records.length) {
    table.innerHTML = "";
    return;
  }
  const head = ["record", "value", "session", "date", ""];
  table.className = "stack-sm";
  table.innerHTML = `<thead><tr>${head.map((h, i) =>
    `<th${i !== 1 ? ' class="l"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
    <tbody>${records.map((r) => `
      <tr>
        <td class="l stack-lead" data-th="record">${esc(r.label)}${
          r.caption ? `<br><span class="dim small">${esc(r.caption)}</span>` : ""}</td>
        <td data-th="value">${recordValue(r)}</td>
        <td class="l" data-th="session">${esc(sessionLabel(r, r.fileName, r.id))}</td>
        <td class="l dim" data-th="date">${esc(localDate(r) || "—")}</td>
        <td class="l stack-actions" data-th=""><button class="ghost small-btn"
          data-act="session" data-id="${esc(r.id)}">Open the session</button></td>
      </tr>`).join("")}</tbody>`;
}

/* ---------------------------------------------------------------------- periods
 *
 * Trips, then months, then seasons, each row expanding to the one aggregate block. Every
 * number and every heading in here — the titles, the date lines, the block's labels, its
 * values as *strings* — comes out of `library.periods`. This file opens a `<details>` and
 * writes what Python said, which is the same division of labour the rest of the page keeps.
 */

/** The gap rule, printed in the explainer so the reader is told the rule the trips obey.
 *  `library.TRIP_GAP_DAYS` is where it actually lives; repeating the number in a sentence
 *  is the one thing a `<p>` can do that a Python constant cannot. */
const GAP_DAYS = 3;

const GROUPS = [
  ["trips", "Trips", "Spells at one spot — a holiday the library noticed."],
  ["months", "Months", "Calendar months, on the day the rider had."],
  ["seasons", "Seasons", "1 April to 31 March, so a February session counts "
    + "towards the winter it belongs to."],
];

/** One period's block as the same `.kv` list the totals above use — the block is a list of
 *  {label, value} pairs and the page has a way of drawing those already. */
const blockHtml = (block) => `<div class="kv">${(block || []).map((e) =>
  `<div class="row"><span>${esc(e.label)}</span><span>${esc(e.value)}</span></div>`)
  .join("")}</div>`;

/** One row: a summary line that is always readable, and the block behind a disclosure.
 *
 *  Closed by default, all of them. Fifteen numbers times a dozen periods is a page nobody
 *  reads; a heading plus "12 sessions · 31 July – 7 August 2026" is a list somebody scans,
 *  and the block is one tap away for the one period being looked for. */
function periodRow(period) {
  const spot = sportCorrected(period.spot || "");
  const title = period.kind === "trip" && spot
    ? `${spot} · ${period.spanShort}` : period.title;
  return `<details class="period" data-period="${esc(period.key)}">
    <summary>
      <span class="period-title">${esc(title)}</span>
      <span class="period-sub">${esc(period.sessions)} session${
        period.sessions === 1 ? "" : "s"} · ${esc(period.dateLine)}</span>
    </summary>
    ${blockHtml(period.block)}
    <div class="period-actions"><button class="ghost small-btn" data-act="period-card"
      data-key="${esc(period.key)}">Share card</button></div>
  </details>`;
}

function renderPeriods(host, periods) {
  const parts = [];
  for (const [key, label, note] of GROUPS) {
    const rows = periods[key] || [];
    if (!rows.length) continue;
    parts.push(`<div class="period-group"><h4>${esc(label)}</h4>
      <p class="muted small">${esc(note)}</p>
      ${rows.map(periodRow).join("")}</div>`);
  }
  host.innerHTML = parts.join("")
    || `<p class="note">No period has a date to sit on yet — a session needs a recorded
        start before it can belong to a month.</p>`;
}

/**
 * The rider's own range: two date inputs and the four spells he asks for most.
 *
 * The presets are here rather than in Python for one reason and it is not arithmetic:
 * "this week" is a question about *today*, and today is a fact about the reader's clock
 * that the stored digests cannot supply. What the buttons produce is a pair of `YYYY-MM-DD`
 * strings, and Python does everything downstream of that — including deciding which
 * afternoons fall inside them, which is emphatically not a JavaScript date comparison.
 */
function renderCustomRange(host) {
  const today = new Date();
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${
    String(d.getDate()).padStart(2, "0")}`;
  const shift = (days) => {
    const d = new Date(today);
    d.setDate(d.getDate() + days);
    return d;
  };
  // Monday-start, matching the week the histogram below buckets on (ISO-8601).
  const monday = shift(-((today.getDay() + 6) % 7));
  const presets = [
    ["This week", iso(monday), iso(today)],
    ["Last 7 days", iso(shift(-6)), iso(today)],
    ["This month", iso(new Date(today.getFullYear(), today.getMonth(), 1)), iso(today)],
  ];
  rangeFrom = rangeFrom || presets[2][1];
  rangeTo = rangeTo || iso(today);
  host.innerHTML = `<div class="period-range">
    <label>from <input type="date" id="period-from" value="${esc(rangeFrom)}"></label>
    <label>to <input type="date" id="period-to" value="${esc(rangeTo)}"></label>
    <button class="ghost small-btn" data-act="period-range">Show</button>
    ${presets.map(([label, from, to]) =>
      `<button class="ghost small-btn" data-act="period-preset" data-from="${esc(from)}"
        data-to="${esc(to)}">${esc(label)}</button>`).join("")}
  </div><div id="period-range-out"></div>`;
}

/** Ask Python for one range's block. The digests go over untouched, exactly as they do for
 *  the aggregate — this is the only period the aggregate could not have known about, because
 *  it is the only one whose input is something the rider typed. */
async function showRange(from, to) {
  const out = el("period-range-out");
  if (!out) return;
  rangeFrom = from || "";
  rangeTo = to || "";
  out.innerHTML = `<p class="note">Aggregating that range in Python…</p>`;
  try {
    const period = await ask("period", { digestsJson: JSON.stringify(entries),
                                         start: from || null, end: to || null });
    customPeriod = period;
    out.innerHTML = period.sessions
      ? `<div class="period-custom-head"><strong>${esc(period.title)}</strong>
           <span class="dim">${esc(period.sessions)} session${
             period.sessions === 1 ? "" : "s"} · ${esc(period.dateLine)}</span></div>
         ${blockHtml(period.block)}
         <div class="period-actions"><button class="ghost small-btn"
           data-act="period-card" data-key="${esc(period.key)}">Share card</button></div>`
      : `<p class="note">No session in that range.</p>`;
  } catch (err) {
    out.innerHTML = `<p class="note">Could not aggregate that range: ${esc(err.message)}</p>`;
  }
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
    t.textContent = tickLabel(s);
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
      const html = `<b>${esc(sessionLabel(s, s.id))}</b><br>${esc(localDate(s))}<br>` +
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

/** Sessions per week, as bars.
 *
 *  The one chart on this page whose x axis is *time* rather than a list of events: the
 *  per-session charts are categorical (one column per session, evenly spaced, because
 *  sessions are events), and the whole point of this one is the gaps between them. A week
 *  with no session is drawn as an empty slot rather than skipped — a season with its quiet
 *  fortnights removed is a season nobody had.
 *
 *  The buckets come from `library._weeks`: **ISO-8601 weeks, Monday start, in the session's
 *  own local time**, which is the rule iOS's `LibraryStore.weeks` follows too. This file
 *  does not bucket anything; it places rectangles. */
function drawWeeks(host, weeks) {
  if (!weeks.length) return;
  const box = document.createElement("div");
  box.className = "trend-chart";
  box.innerHTML = `<div class="trend-head"><h4>Sessions per week</h4>` +
    `<span class="trend-unit">sessions</span></div><div class="figure"></div>`;
  host.appendChild(box);
  const ridden = weeks.filter((w) => w.count > 0).length;
  const note = document.createElement("p");
  note.className = "muted small";
  note.textContent = `${ridden} of ${weeks.length} weeks on the water. `
    + "Weeks start on Monday (ISO-8601), in the session's own local time.";
  box.appendChild(note);

  const figure = box.querySelector(".figure");
  const W = figureWidth(figure);
  const narrow = isNarrow(W);
  const H = narrow ? 150 : 190;
  const L = narrow ? 26 : 40, R = 10, B = 30, T = 12;
  const plot = W - L - R;
  const top = Math.max(1, ...weeks.map((w) => w.count));
  const step = top <= 4 ? 1 : Math.ceil(top / 4);
  const yMax = Math.ceil(top / step) * step;
  const Y = (v) => H - B - (v / yMax) * (H - T - B);
  const slot = plot / weeks.length;
  const barW = Math.max(1.5, Math.min(22, slot - (slot > 6 ? 2 : 0.6)));

  const root = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img",
                            "aria-label": "Sessions per ISO week" }, figure);
  svg("rect", { width: W, height: H, fill: C.surface }, root);
  for (let v = 0; v <= yMax + 1e-9; v += step) {
    svg("line", { x1: L, x2: W - R, y1: Y(v), y2: Y(v), stroke: C.grid, "stroke-width": 1,
                  opacity: v === 0 ? 0.9 : 0.45 }, root);
    const t = svg("text", { x: L - 8, y: Y(v) + 3.5, "text-anchor": "end",
                            "font-size": 10.5, fill: C.ink3 }, root);
    t.textContent = String(Math.round(v));
  }

  // A "06 Aug" tick is ~42 units wide; keep at least that much between the ones we draw.
  const stride = Math.max(1, Math.ceil(weeks.length
    / Math.max(2, Math.floor(plot / (narrow ? 52 : 110)))));
  weeks.forEach((w, i) => {
    const x = L + i * slot + (slot - barW) / 2;
    const empty = !w.count;
    const bar = svg("rect", {
      x, y: empty ? Y(0) - 1.5 : Y(w.count), width: barW,
      height: empty ? 1.5 : Math.max(1.5, Y(0) - Y(w.count)),
      fill: C.foil, opacity: empty ? 0.22 : 0.9, rx: Math.min(2, barW / 2),
    }, root);
    const hours = w.hours >= 0.05 ? ` · ${nf(w.hours, 1)} h on the water` : "";
    const html = `<b>Week of ${esc(w.weekStart)}</b><br>` +
      (empty ? "no session" : `${int(w.count)} session${w.count === 1 ? "" : "s"}${hours}`);
    bar.addEventListener("pointerenter", (ev) => showTip(ev, html));
    bar.addEventListener("pointermove", (ev) => showTip(ev, html));
    bar.addEventListener("pointerleave", hideTip);
    if (i % stride && i !== weeks.length - 1) return;
    const last = i === weeks.length - 1;
    const t = svg("text", {
      x: last ? W - R : i === 0 ? L : x + barW / 2,
      y: H - B + 16,
      "text-anchor": last ? "end" : i === 0 ? "start" : "middle",
      "font-size": 10.5, fill: C.ink3,
    }, root);
    t.textContent = weekTick(w.weekStart);
  });
}

/** "06 Aug" from a `YYYY-MM-DD` Monday. The bucket is already a calendar date in the
 *  rider's own time, so it is formatted as text and never re-parsed into an instant — a
 *  `new Date("2026-08-03")` would be midnight *UTC* and could print the day before. */
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function weekTick(day) {
  const [, m, d] = String(day).split("-");
  return `${d} ${MONTHS[Number(m) - 1] || "?"}`;
}

/** An x-axis tick: the day the *rider* had, not the day UTC had. `s` is the session stamp
 *  (`library._stamp`), which carries the instant and the offset it was recorded at. */
const tickLabel = (s) => (s && s.startUtc
  ? zonedFormat(s.startUtc, s.utcOffsetS, { month: "short", day: "2-digit" })
  : "—");

/** The calendar date a row or a tooltip names. `dateLocal` is the session's own day
 *  (library.py, engine 0.8.2); `dateUtc` is the fallback for a digest saved before that
 *  field existed, and is the UTC day — right for most sessions, a day out for one either
 *  side of midnight. */
const localDate = (s) => (s && (s.dateLocal || s.dateUtc)) || "";

/* ---------------------------------------------------------------------- actions */

function onClick(ev) {
  const dot = ev.target.closest("circle[data-session]");
  if (dot) { hooks.openSession(dot.dataset.session); return; }
  const preset = ev.target.closest("button[data-act=period-preset]");
  if (preset) {
    el("period-from").value = preset.dataset.from;
    el("period-to").value = preset.dataset.to;
    showRange(preset.dataset.from, preset.dataset.to);
    return;
  }
  if (ev.target.closest("button[data-act=period-range]")) {
    showRange(el("period-from").value, el("period-to").value);
    return;
  }
  const card = ev.target.closest("button[data-act=period-card]");
  if (card) { hooks.openPeriodCard(findPeriod(card.dataset.key), entries); return; }
  // A session record is the whole afternoon, so its row opens the session itself — there
  // is no window inside it to highlight.
  const open = ev.target.closest("button[data-act=session]");
  if (open) { hooks.openSession(open.dataset.id); return; }
  const button = ev.target.closest("button[data-act=record]");
  if (!button) return;
  const key = button.closest("tr")?.dataset.record;
  const record = (cache.data?.records || []).find((r) => r.key === key);
  if (record) hooks.openRecord(record);
}

/** The period one button belongs to, by the key Python gave it. The custom range is not in
 *  the aggregate — it was asked for separately — so it is checked first and by identity. */
function findPeriod(key) {
  if (customPeriod && customPeriod.key === key) return customPeriod;
  const groups = cache.data?.periods || {};
  for (const list of Object.values(groups)) {
    const found = (list || []).find((p) => p.key === key);
    if (found) return found;
  }
  return null;
}
