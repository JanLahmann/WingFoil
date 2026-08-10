/* Optional intervals.icu panel.
 *
 * Privacy contract, and the only reason this file is allowed to exist:
 *   - the API key lives in localStorage on this device and nowhere else;
 *   - it is attached ONLY to requests whose origin is https://intervals.icu;
 *   - it is never posted to the host serving this page, never logged, never in a URL.
 *
 * intervals.icu does not publish CORS headers for its API, so a browser will usually
 * refuse these calls. That is expected and cannot be fixed from here — a zero-server app
 * has no proxy to route through. We feature-detect the failure and fall back to telling
 * the user how to export the FIT by hand, which is the supported path.
 */

const BASE = "https://intervals.icu/api/v1";
const LS_KEY = "wingfoil.icu.key";
const LS_ATHLETE = "wingfoil.icu.athlete";
const WATERSPORTS = /wing|foil|windsurf|kite|surf|sup/i;

const el = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

export function mountIcu({ analyzeBuffer }) {
  const panel = el("icu-panel");
  const keyInput = el("icu-key");
  const athleteInput = el("icu-athlete");

  keyInput.value = localStorage.getItem(LS_KEY) || "";
  athleteInput.value = localStorage.getItem(LS_ATHLETE) || "0";

  el("icu-toggle").addEventListener("click", (ev) => {
    panel.hidden = !panel.hidden;
    ev.currentTarget.setAttribute("aria-expanded", String(!panel.hidden));
  });

  el("icu-forget").addEventListener("click", () => {
    localStorage.removeItem(LS_KEY);
    keyInput.value = "";
    el("icu-results").innerHTML = "";
    say("Key removed from this browser.");
  });

  el("icu-list").addEventListener("click", async () => {
    const key = keyInput.value.trim();
    const athlete = athleteInput.value.trim() || "0";
    if (!key) return say("Paste your intervals.icu API key first.", true);
    localStorage.setItem(LS_KEY, key);
    localStorage.setItem(LS_ATHLETE, athlete);
    await listActivities(key, athlete, analyzeBuffer);
  });
}

function say(text, bad = false) {
  const node = el("icu-status");
  node.textContent = text;
  node.classList.toggle("bad", bad);
}

const authHeader = (key) => `Basic ${btoa(`API_KEY:${key}`)}`;

function isoDaysAgo(days) {
  const d = new Date(Date.now() - days * 86400000);
  return d.toISOString().slice(0, 10);
}

async function listActivities(key, athlete, analyzeBuffer) {
  say("Contacting intervals.icu…");
  el("icu-results").innerHTML = "";
  const url = `${BASE}/athlete/${encodeURIComponent(athlete)}/activities` +
              `?oldest=${isoDaysAgo(120)}&newest=${isoDaysAgo(-1)}`;
  let activities;
  try {
    const res = await fetch(url, { headers: { Authorization: authHeader(key) } });
    if (res.status === 401 || res.status === 403) {
      return say("intervals.icu rejected the key (401/403). Check it and try again.", true);
    }
    if (!res.ok) return say(`intervals.icu returned HTTP ${res.status}.`, true);
    activities = await res.json();
  } catch (err) {
    return corsFallback(err);
  }

  const water = activities.filter((a) => WATERSPORTS.test(`${a.type || ""} ${a.name || ""}`));
  if (!water.length) return say("No wing/foil/windsurf activities in the last 120 days.");

  say(`${water.length} watersport activities found. Everything below is fetched straight ` +
      `from intervals.icu to this tab.`);
  el("icu-results").innerHTML = `<div class="icu-list">${water.slice(0, 40).map((a) => `
    <div class="icu-row">
      <div>
        <div>${esc(a.name || a.id)}</div>
        <div class="meta">${esc(a.start_date_local || "").replace("T", " ").slice(0, 16)} ·
          ${esc(a.type || "?")} · ${((a.distance || 0) / 1000).toFixed(1)} km</div>
      </div>
      <button class="ghost" type="button" data-id="${esc(a.id)}"
              data-name="${esc(a.name || a.id)}">Analyze</button>
    </div>`).join("")}</div>`;

  for (const btn of el("icu-results").querySelectorAll("button[data-id]")) {
    btn.addEventListener("click", () => fetchAndAnalyze(key, btn.dataset.id, btn.dataset.name,
                                                        analyzeBuffer));
  }
}

async function fetchAndAnalyze(key, id, name, analyzeBuffer) {
  say(`Downloading the original file for “${name}”…`);
  try {
    const res = await fetch(`${BASE}/activity/${encodeURIComponent(id)}/file`,
                            { headers: { Authorization: authHeader(key) } });
    if (!res.ok) return say(`Download failed: HTTP ${res.status}.`, true);
    const buffer = await res.arrayBuffer();
    say(`Loaded ${(buffer.byteLength / 1024).toFixed(0)} KB — analyzing locally.`);
    // web_entry unwraps gzip/zip itself, so hand the bytes over untouched.
    analyzeBuffer(buffer, `${id}.fit`);
  } catch (err) {
    corsFallback(err);
  }
}

/** The expected failure: the browser blocked the cross-origin call. */
function corsFallback(err) {
  say("intervals.icu could not be reached from the browser.", true);
  el("icu-results").innerHTML = `
    <p class="note" style="margin-top:12px">
      This is almost certainly <strong>CORS</strong>: intervals.icu does not allow its API to be
      called from another website, and a zero-server app has no proxy to route the call through.
      Your key was not sent anywhere else, and nothing was uploaded.
      <br><br>
      <strong>Do this instead — it takes 20 seconds:</strong>
    </p>
    <ol class="note" style="margin-top:8px">
      <li>Open the activity on <a href="https://intervals.icu/" rel="noopener" target="_blank">intervals.icu</a>.</li>
      <li>Use the <em>⋯</em> menu → <em>Download original file</em> (the FIT the watch recorded — not the CSV or GPX).</li>
      <li>Drop that file onto the drop zone at the top of this page.</li>
    </ol>
    <p class="note" style="margin-top:8px">The original FIT is what this engine needs: only it
      carries the developer fields and the wrist accelerometer stream.</p>
    <p class="note" style="margin-top:8px">Browser said: <code>${esc(err?.message || err)}</code></p>`;
}
