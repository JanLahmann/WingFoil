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

const VERSION = "v54";     // v54: whats-new gets builds 51 and 53 (v53: light theme, the card takes the fold, /learn/, Android share target)
// The cache *names* keep the historical prefix on purpose: the activate handler below
// deletes every cache starting with it, so renaming the prefix would strand every v1–v13
// cache on every device that ever visited, forever. Nobody sees these strings.
const SHELL = `wingfoil-shell-${VERSION}`;
const RUNTIME = `wingfoil-runtime-${VERSION}`;

/** The analyzer's directory, relative to this worker's root scope. See APP_SHELL. */
const APP_DIR = "app/";

/* ------------------------------------------------------- Android's share sheet
 *
 * GitHub issue #9, "Will this provide a share in / open in capability on android?" — yes,
 * and this is the whole of it. An installed web app that declares `share_target` in its
 * manifest appears in Android's share sheet like any other app; when a rider picks it,
 * Android POSTs a multipart form to the declared action. That POST never reaches a server
 * (there isn't one) — it reaches THIS worker, which is the only reason the feature can
 * exist on a site that uploads nothing.
 *
 * The dance, and why it is a dance: a POST cannot hand a File to a page. So the worker
 * takes the file out of the form, parks it in a cache of its own under one fixed key, and
 * answers with a 303 to `app/?shared=1`. The analyzer reads the key on load, deletes it,
 * and feeds the file to the same intake a drop or a picker uses (js/app.js). One file at a
 * time, deliberately: the intake analyses one session, and a second parked file would be a
 * queue nobody asked for.
 *
 * PRIVACY IS UNCHANGED. The bytes go from Android's share sheet into this browser's own
 * cache and out again into the tab next door. Nothing is fetched, nothing is posted
 * anywhere, and the slot is emptied by the page that reads it — and by `activate`, below,
 * on the next version bump.
 */
const SHARE_CACHE = "wingfoil-share";
/** The action the manifest declares, as this worker sees it. */
const SHARE_TARGET_PATH = new URL(`${APP_DIR}share-target`, self.location).pathname;
/** The one key a shared file is parked under. Absolute, because the page resolves the same
 *  string against its own URL and the two have to agree. */
const SHARE_SLOT = new URL(`${APP_DIR}__shared__`, self.location).href;

const APP_SHELL = [
  // Two documents now, both inside this worker's root scope: the project homepage at "/"
  // and the analyzer at "/app/". The homepage is 6 KB of HTML plus one stylesheet, so
  // precaching it costs nothing and buys the offline visitor a way back out of the app.
  "./",
  "index.html",
  // /learn/ joined them on 14 September 2026, when the homepage's long half moved there.
  // It is the ONE outbound link the front door now offers a reader who wants more than the
  // card and the three names, and an offline visitor who followed it into a 503 would be
  // reading a page whose only invitation is broken. ~30 KB of HTML, no pictures of its own
  // above the fold, and the four it does carry are lazy and excluded below like the rest.
  "learn/",
  "learn/index.html",
  "app/",
  "app/index.html",
  "app/manifest.webmanifest",
  "css/tokens.css",
  "css/style.css",
  "css/home.css",
  "js/app.js",
  "js/cardmap.js",
  "js/cardstats.js",
  "js/icu.js",
  "js/library.js",
  "js/render.js",
  "js/rider.js",
  "js/rpc.js",
  "js/sections.js",
  "js/session.js",
  "js/sharecard.js",
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
  // Drawn onto the share card, so a rider on a beach with no signal still gets a
  // scannable one.
  "icons/qr-cleanjibe.png",
  // The dropzone's "what you get" strip, ~58 KB for the three. Precached because they are
  // on the analyzer's FIRST screen: the offline visitor who opened the installed app is
  // exactly the one who has nothing else to look at, and three broken image frames is a
  // worse empty state than the one they replaced.
  //
  // The site's four pictures are deliberately NOT here. Three of them (img/watch-main,
  // img/phone-session, img/web-report, ~97 KB) are on /learn/ now rather than on the front
  // page, all three below its fold, all three `loading="lazy"`, and the boxes they sit in
  // are sized by `aspect-ratio` — so offline they leave tidy empty plates rather than a
  // broken layout, and nobody pays for them on install.
  //
  // img/share-card.png is the exception worth naming, because it moved twice: it is the
  // HOMEPAGE'S HERO, above the fold and `loading="eager"`, and since 14 Sep 2026 it carries
  // its map background. It stays out anyway, on the argument that always did the real work —
  // the person paying for it on install is the one installing the ANALYZER, who reaches the
  // homepage only on the way back out and reaches it online. (It is also 28 KB now, a third
  // of what it was: the map made the picture, and an octree quantize made the file.) Its box
  // is still reserved by `aspect-ratio`, so offline the hero is one tidy empty plate beside
  // a headline that says the same thing in words.
  // /invite/ is not precached either: it is read once, at a desk, next to a watch. Nor is
  // /privacy/, for the same reason and more so — it is read once, before an install, by a
  // person deciding whether to trust the thing, which is not a decision anyone makes on a
  // train with no signal. Neither is the umami script — it is a third-party URL, nothing
  // calls into it, and an offline page renders whole without it.
  "img/peek-track.png",
  "img/peek-speed.png",
  "img/peek-turns.png",
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
    // SHARE_CACHE is version-less on purpose: a file parked by the old worker seconds before
    // an update must still be there for the page that was opened to fetch it. It is kept,
    // not deleted, and the page empties it as soon as it has read it.
    const keep = new Set([SHELL, RUNTIME, SHARE_CACHE]);
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
  // Android's share sheet, before the GET guard below: this is the one POST this worker
  // answers, and nothing on the network ever sees it.
  if (req.method === "POST" && new URL(req.url).pathname === SHARE_TARGET_PATH) {
    event.respondWith(stashShared(req));
    return;
  }
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  if (RUNTIME_HOSTS.includes(url.hostname)) {
    event.respondWith(cacheFirst(req, RUNTIME));
    return;
  }
  // Everything else third-party is passed straight through, never stored: intervals.icu
  // (a cached activity list is not something a privacy-first app should keep),
  // cloud.umami.is (nothing depends on it, so offline it is simply allowed to fail), and
  // tile.openstreetmap.org — the share card's optional map background, which the browser's
  // own HTTP cache handles perfectly well and which this worker has no business keeping a
  // second copy of. Offline the tiles simply fail and the card comes out plain.
  if (url.origin !== self.location.origin) return;
  event.respondWith(staleWhileRevalidate(req, SHELL));
});

/**
 * Take the shared file out of Android's multipart POST, park it, and send the rider to the
 * analyzer.
 *
 * A 303 rather than a 302: the browser must follow it with a GET, and only 303 says so for
 * a POST. Every failure lands in the same place — the analyzer's ordinary front screen with
 * its drop zone — because a rider who shared a file and got an error page would have no way
 * to try the other thing.
 */
async function stashShared(request) {
  const home = new URL(APP_DIR, self.location);
  try {
    const form = await request.formData();
    // `getAll` rather than `get`: a sender may attach several, and the intake analyses one
    // session. The first File wins; a text part under the same name is skipped.
    const file = form.getAll("files").find((part) => part && typeof part !== "string");
    if (!file) return Response.redirect(home.href, 303);
    const cache = await caches.open(SHARE_CACHE);
    await cache.put(SHARE_SLOT, new Response(file, {
      headers: {
        "content-type": file.type || "application/octet-stream",
        // The name is what the intake sniffs the format from and what the library row is
        // called, and Android sends names with spaces and umlauts in them — a header value
        // may hold neither, so it travels percent-encoded and the page decodes it.
        "x-shared-name": encodeURIComponent(file.name || "session.fit"),
      },
    }));
    const target = new URL(APP_DIR, self.location);
    target.search = "?shared=1";
    return Response.redirect(target.href, 303);
  } catch {
    return Response.redirect(home.href, 303);
  }
}

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
