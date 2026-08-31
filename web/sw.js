/* Service worker: make a revisit work with no network at all.
 *
 * Two caches, on purpose:
 *
 *   SHELL    the app itself — HTML, CSS, JS, icons, and every file under lab_bundle/.
 *            Precached at install, replaced wholesale when VERSION changes. The
 *            lab_bundle list is read from lab_bundle/FILES.json (the same list the worker
 *            mounts), so adding a lab module never needs an edit here.
 *   RUNTIME  the Pyodide CDN and the PyPI wheel — ~12 MB that never changes for a pinned
 *            Pyodide version. Cached the first time they are fetched, then served from
 *            cache forever. This is what makes the app work offline.
 *
 * Privacy: this file never adds a request. It only stores responses the page was already
 * making, and only from the Pyodide CDN, PyPI and this site's own origin. Nothing is ever
 * sent anywhere, and intervals.icu is explicitly excluded — a cached activity list is not
 * something a privacy-first app should leave lying around.
 *
 * Bump VERSION whenever anything under web/ changes; the old caches are deleted on
 * activate, and the page shows an "update available" prompt (see js/app.js) rather than
 * swapping the worker under a running analysis.
 */

const VERSION = "v10";     // v10: homepage at the root, analyzer moved to /app/
const SHELL = `wingfoil-shell-${VERSION}`;
const RUNTIME = `wingfoil-runtime-${VERSION}`;

/** The analyzer's directory, relative to this worker's root scope. See APP_SHELL. */
const APP_DIR = "app/";

const APP_SHELL = [
  // Two documents now, both inside this worker's root scope: the project homepage at "/"
  // and the analyzer at "/app/". The homepage is 6 KB of HTML plus one stylesheet, so
  // precaching it costs nothing and buys the offline visitor a way back out of the app.
  "./",
  "index.html",
  "app/",
  "app/index.html",
  "app/manifest.webmanifest",
  "css/tokens.css",
  "css/style.css",
  "css/home.css",
  "js/app.js",
  "js/icu.js",
  "js/library.js",
  "js/render.js",
  "js/rpc.js",
  "js/sections.js",
  "js/session.js",
  "js/store.js",
  "js/tokens.js",
  "js/trends.js",
  "js/viz.js",
  "js/worker.js",
  "icons/icon.svg",
  "icons/icon-192.png",
  "icons/icon-512.png",
  "icons/icon-maskable-512.png",
  "icons/apple-touch-icon.png",
  // The bundled example (942 KB). Precached with the shell rather than fetched on demand,
  // because the whole point of it is the visitor who has nothing else to open — including
  // the one who opened the installed app on a train. It is the same file the iOS app
  // ships; see docs/testing.md "The bundled example session".
  "example/ExampleSession.fit",
  "lab_bundle/FILES.json",
  "lab_bundle/MANIFEST.json",
];

/** Hosts whose responses are worth keeping: the Python runtime and the one wheel. */
const RUNTIME_HOSTS = [
  "cdn.jsdelivr.net",
  "files.pythonhosted.org",
  "pypi.org",
];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL);
    // lab_bundle/*.py is generated; ask the manifest rather than hard-coding the list.
    let lab = [];
    try {
      const res = await fetch("lab_bundle/FILES.json", { cache: "reload" });
      lab = (await res.json()).map((rel) => `lab_bundle/${rel}`);
    } catch { /* precache what we can; the runtime cache still fills in on first use */ }
    await Promise.all([...APP_SHELL, ...lab].map(async (url) => {
      try {
        await cache.add(new Request(url, { cache: "reload" }));
      } catch { /* one missing file must not fail the whole install */ }
    }));
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keep = new Set([SHELL, RUNTIME]);
    await Promise.all((await caches.keys())
      .filter((k) => k.startsWith("wingfoil-") && !keep.has(k))
      .map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

// The page asks for the swap explicitly, from the "update available" banner.
self.addEventListener("message", (event) => {
  if (event.data?.type === "skipWaiting") self.skipWaiting();
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  if (RUNTIME_HOSTS.includes(url.hostname)) {
    event.respondWith(cacheFirst(req, RUNTIME));
    return;
  }
  if (url.origin !== self.location.origin) return;      // e.g. intervals.icu: never cached
  event.respondWith(staleWhileRevalidate(req, SHELL));
});

/**
 * The Pyodide runtime and the wheel: pinned versions at immutable URLs, so once we have
 * a copy there is no reason to ask again. This is the whole offline story — ~12 MB that
 * would otherwise have to come down the wire on every cold start.
 */
async function cacheFirst(request, cacheName) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(request, { ignoreVary: true });
  if (hit) return hit;
  const res = await fetch(request);
  // `opaque` responses (a CDN without CORS headers) are useless to store: they read back
  // as failures. jsdelivr and PyPI both send CORS headers, so this normally passes.
  if (res.ok && res.type !== "opaque") cache.put(request, res.clone());
  return res;
}

/**
 * Same-origin files: answer from cache instantly, then refresh in the background so the
 * next load has the new bytes and the update banner can offer them. Falls back to the
 * cache when the network is gone, and to the shell for a navigation (the app is a single
 * page with hash routes).
 */
async function staleWhileRevalidate(request, cacheName) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(request, { ignoreSearch: request.mode === "navigate" });
  const network = fetch(request).then((res) => {
    if (res.ok) cache.put(request, res.clone());
    return res;
  }).catch(() => null);

  if (hit) return hit;
  const res = await network;
  if (res) return res;
  if (request.mode === "navigate") {
    // Two shells since the restructure: a navigation under /app/ falls back to the
    // analyzer (it is the single page with the hash routes), anything else to the
    // homepage. Falling back to the wrong one would show a visitor the front door when
    // they asked for #/library.
    const path = new URL(request.url).pathname;
    const inApp = path.includes(`/${APP_DIR}`);
    const shell = await cache.match(inApp ? `${APP_DIR}index.html` : "index.html");
    if (shell) return shell;
  }
  return new Response("Offline, and this file is not in the cache.",
                      { status: 503, statusText: "Offline" });
}
