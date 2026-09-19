/* The one door to umami, and the only file in js/ that is allowed to know its name.
 *
 * WHY A HELPER AT ALL. The counter is a third-party script: `defer`, pinned to one
 * hostname by `data-domains`, and blocked outright by a good share of real browsers. So
 * `window.umami` is simply absent on a local server, in a preview, offline, and for every
 * reader with a content blocker — and not one line of the app may care. Twelve call sites
 * each writing `window.umami?.track?.(…)` is twelve chances to forget the guard; one
 * function is none. It no-ops, it never throws, and a page with the counter blocked does
 * exactly what a page with it loaded does.
 *
 * WHAT MAY TRAVEL. Counts, a format, a source class, a page name, a card shape. Nothing
 * that describes a rider or an afternoon: no file name, no coordinate, no session title,
 * no date, no wind, no speed. `scrub` below is the mechanism rather than the promise —
 * strings are capped at 32 characters and only finite numbers and booleans pass, so a
 * caller that hands over a file name gets a truncated one rather than a leak, and a caller
 * that hands over an object gets nothing. The event map and this rule are written down in
 * docs/analytics.md.
 *
 * NAMES. Kebab-case, `app-<object>-<verb>` inside the browser app, so one umami dashboard
 * reads as one product. The site's doors keep their own declarative `data-umami-event`
 * names in the markup; nothing here touches those.
 */

/** The longest a property value may be. A format is 3 characters and a page name is 8; a
 *  value past this is something nobody meant to send. */
const MAX_LEN = 32;

/** At most this many properties on one event. umami prices an event by its payload and a
 *  counter with fifteen columns is a log, which is the thing this is not. */
const MAX_PROPS = 6;

/**
 * Only the value kinds a counter may carry, and only that much of them.
 *
 * Returns `undefined` for anything else, which drops the key rather than sending a
 * stringified object.
 */
function scrubValue(value) {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) ? value : undefined;
  if (typeof value === "string") {
    const text = value.trim();
    return text ? text.slice(0, MAX_LEN) : undefined;
  }
  return undefined;
}

/** The properties of one event, or null when there are none worth sending. */
function scrub(props) {
  if (!props || typeof props !== "object") return null;
  const out = {};
  let n = 0;
  for (const [key, value] of Object.entries(props)) {
    if (n >= MAX_PROPS) break;
    const clean = scrubValue(value);
    if (clean === undefined) continue;
    out[key] = clean;
    n += 1;
  }
  return n ? out : null;
}

/**
 * Count one named action, if there is anything listening.
 *
 * `track("app-file-analyzed", { format: "fit", source: "drop" })`. Everything is optional
 * but the name, and every failure is silent: a counter that can break a page is worse than
 * no counter.
 */
export function track(name, props = null) {
  const umami = typeof window === "undefined" ? null : window.umami;
  if (!umami || typeof umami.track !== "function") return;
  try {
    const data = scrub(props);
    if (data) umami.track(name, data);
    else umami.track(name);
  } catch {
    /* A blocked, half-loaded or stubbed counter is not a reason for anything to stop. */
  }
}
