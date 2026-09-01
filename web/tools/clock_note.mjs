/* The session page's clock note, dumped as JSON for `verify_presentation.py` §4.
 *
 * Every time on a session page is drawn in the session's own zone, and since engine 0.9.1
 * the note under the title says how well that zone is *known* (docs/presentation.md
 * "Session time"). The rule is one `switch` over `meta.utcOffsetSource`, and the sentence
 * it picks is the only place the page tells a reader whether to trust a clock — so it is
 * asserted from the outside rather than trusted to a comment, in the same spirit as
 * `card_parity.mjs`: the string this prints is the string the browser prints, because it
 * comes out of the same function.
 *
 * Run from the repo root:
 *
 *     node web/tools/clock_note.mjs
 *
 * `js/session.js` installs a pointer-move listener at import time, so the one method it
 * calls is stubbed — the same stub `card_parity.mjs` uses, for the same reason.
 */

globalThis.window = { addEventListener() {} };

const { clockNoteFor } = await import(new URL("../js/render.js", import.meta.url).href);

/** One case per rung of the ladder, plus the two shapes a document can be missing it in. */
const CASES = {
  activity: { startUtc: "2026-08-07T05:54:35+00:00", utcOffsetS: 7200,
              utcOffsetSource: "activity" },
  icu: { startUtc: "2026-08-07T05:54:35+00:00", utcOffsetS: 7200, utcOffsetSource: "icu" },
  longitude: { startUtc: "2026-08-07T05:54:35+00:00", utcOffsetS: 3600,
               utcOffsetSource: "longitude" },
  device: { startUtc: "2026-08-07T05:54:35+00:00", utcOffsetS: null,
            utcOffsetSource: "device" },
  // A document from before 0.9.1: an offset, and nothing that says where it came from.
  unrecorded: { startUtc: "2026-08-07T05:54:35+00:00", utcOffsetS: 7200 },
  // No offset at all, however it is spelled.
  absent: { startUtc: "2026-08-07T05:54:35+00:00", utcOffsetS: null },
};

const out = {};
for (const [name, meta] of Object.entries(CASES)) out[name] = clockNoteFor(meta);
process.stdout.write(JSON.stringify(out));
