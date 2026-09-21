import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;
import WingFoilCore;

// Turns-page metrics, file scope so the static width helpers (shared with the layout
// test) can reach them — class consts are instance-scoped in Monkey C.
const TURNS_TALLY_SEP = " · ";
// Space between the coloured flew/touchdown/swim tally and the "% flew" share that shares
// its row. Wider than the tally's own separator so the two read as two groups.
const TURNS_OK_GAP = 14;

// The tally row never goes below TEXT_FONTS[TALLY_FLOOR] = FONT_SMALL. Below it a count is
// ~21 px of digit, under the readability floor — and the session whose tally is widest (30+
// turns, three two-digit counts) is exactly the session whose tally the rider wants to read.
// When the chord cannot hold the row at that size the row drops CONTENT instead of size:
// first the session verdict, then the " · " separators. See tallyContent().
const TALLY_FLOOR = 2;
const TALLY_SEP_NARROW = " ";
const TALLY_OK = 1;
const TALLY_SEPARATORS = 2;
// The tally's captions — "flew", "touch", "fell" in FONT_XTINY after each count — shown where
// the row can afford them on top of everything else. Until 0.9.11 the three counts were three
// colours and nothing more, and colour was the only key (audit, 15 Sep 2026); the words are
// the first thing dropped when a session gets wide, so a 30-turn tally still reads as digits.
const TALLY_CAPTIONS = 4;
const TALLY_CAPTION_GAP = 3;
const TALLY_CAP_FLEW = "flew";
const TALLY_CAP_TOUCH = "touch";
const TALLY_CAP_FELL = "fell";

// ---- the LADDER ROW and its header (0.9.18, Jan's layout review of 21 September 2026) ----
//
// FOUR counts on one wide row, clean first: "★34  63 · 21 · 12". Everything the Turns page
// used to say in six rows it now says in one plus a legend — the clean jibes left their own
// row, CPH left the watch, and the "% flew" figure left because the counts already say it
// (a rider who can read "63 · 21 · 12" does not need "65 %" printed beside it, and a page
// that prints both has to be believed twice).
//
// The row is the page's WIDEST line, which is what puts it on the equator: on a round glass
// the chord is widest at the vertical centre, so the widest line belongs there and the narrow
// ones — labels, captions, the streaks — go above and below it (docs/presentation.md, "The
// widest line belongs on the equator").
//
// The header above it is the same four words in the same four inks in the same order, at
// FONT_XTINY. Colour alone was the key until 0.9.11 and the words came back then; this round
// moves them OFF the counts and into a legend, which is what buys the counts their size:
// three captions inline cost the row ~90 px on a 454 px glass, and a legend costs it nothing
// because it is a narrow line on a row that has room to spare.
const TALLY_CAP_CLEAN = "clean";
const LADDER_HEAD_SEP = " · ";
// ...and the legend SHEDS CONTENT rather than size, exactly as the tally row does, because
// FONT_XTINY is already the bottom of the ladder and a legend nobody can read explains
// nothing. Measured on a 240 px fenix 5 Plus, where FONT_XTINY is 26 px (every other watch
// draws 19): the full legend is 224 px against a 214 px chord at its own depth — ten pixels,
// and three of them are separators.
//
// The order is separators, then the mark. A separator between two words that are already in
// two different colours carries nothing; the mark carries whether the page has an axis at
// all, which is the difference between a port/starboard row that means something and one
// that is counting nothing.
const LADDER_HEAD_SEP_NARROW = " ";
const LADDER_HEAD_SEPARATORS = 1;
const LADDER_HEAD_MARK = 2;
// Between the star's group and the three outcome counts: the same wider gap the tally row
// has always used to say "two groups, not one phrase". The star's count is a SUBSET of the
// green one beside it, so the two must not read as a sequence.
const LADDER_CLEAN_GAP = TURNS_OK_GAP;
// Gap between the header's four words and the wind mark that follows them. Wider than the
// word separator for the same reason: the mark is not a fifth rung.
const LADDER_HEAD_MARK_GAP = 10;
// The rung a ladder row's counts START at, as a NUMBER_FONTS index — FONT_NUMBER_MEDIUM,
// the rung the Turns page's giant tally has always reserved. It steps down through MILD into
// the text ladder and stops at TALLY_FLOOR, like every other count on this watch.
const LADDER_FROM = 2;

// The Turns page's downward lift (0.9.18). Its five rows are one wide one with a legend over
// it and three narrow ones under it, and a stack centred on its own TOTAL leaves the wide row
// ~45 px above the equator on a 454 px glass with an empty top arc above it. The lift is
// exactly the distance that puts the ladder row's own centre on cy — capped at this share of
// the radius, because past it the page is buying the widest row a chord it already had by
// pushing the bottom row into one it has not.
const TURNS_BIAS_MAX_PCT = 20;

// ---- the MAIN page's clock (0.9.18) ----
//
// Jan's layout review, 21 September 2026: "make the clock time bigger". It is the top row of
// the page a rider spends the session on and the one thing on it he reads without wanting a
// number — and it had been a FONT_NUMBER_MILD line since 0.9.2, one rung under the band it
// sits in. It is FONT_NUMBER_MEDIUM now (~88 px of digit on a 454 px glass against MILD's 66)
// and it is fitted from that rung of the NUMBER ladder, so a glass that cannot hold MEDIUM
// steps back down to exactly the clock that shipped.
//
// THE RUNG IS PAID FOR OUT OF LEADING, not out of another row, and this is the whole trick:
// the clock's band is its INK and not its line, the same treatment the MAIN giant's band got
// in 0.9.2 and the HERO giant's before it. FONT_NUMBER_MEDIUM's line is 143 px on a 454 px
// glass and its digits are 114 of them; FONT_NUMBER_MILD's LINE — the band the clock reserved
// until this round — is 113. So a whole rung of digit costs the stack **one pixel**, and the
// four rows under it do not move.
//
// Measured, and it is the reason this is written down: banding the taller clock on its LINE
// instead cost the stack 30 px, which pushed the MAIN page's tally row deep enough into the
// arc to drop its "flew / touch / fell" captions — the words the 0.9.11 stranger audit put
// there. A bigger clock is not worth the three words under it, and on the ink it does not
// cost them.
// ---- AND ON A FENIX 8 IT DOES NOT FIT, which is worth writing down ----
//
// The clock is row 0, in the TOP ARC, which is where a round glass is narrowest. Measured on
// a 454 px fenix 8: the chord for a 114 px box at the clock's depth is 241 px and a
// FONT_NUMBER_MEDIUM "23:59" needs about 250. Nine pixels.
//
// Three ways to buy them were tried and all three were rejected:
//   * LIFT THE BLOCK, the Clock page's own trick. 20 px of lift puts the streak row's corner
//     217 px out on a 213 px radius — the bottom row falls off the glass before the top row
//     gets its rung, because this page has five rows and the Clock page has two.
//   * BAND THE CLOCK ON FONT_NUMBER_MEDIUM'S LINE (143 px against MILD's 113). That does not
//     help the fit at all — the box the glass clips is the INK either way — and it pushes the
//     four rows under it 30 px deeper for nothing.
//   * TAKE THE FIT PER TIME OF DAY. "11:49" is narrow enough for MEDIUM and "23:59" is not,
//     so the clock would change size during the session. A number that grows and shrinks on
//     its own is worse than a number that is one rung small.
//
// So the ceiling is raised and the floor is where it was: `fitByOwnInk` is asked for the
// WORST CASE the row can be handed ("23:59"), once, so the answer is stable for the whole
// session — FONT_NUMBER_MEDIUM on every font set that can hold it and the shipped
// FONT_NUMBER_MILD on the ones that cannot, which on this page is the fenix 8's own. The
// band is MEDIUM's ink, 114 px against MILD's 113 line, so the stack does not move either
// way and no other row pays for the attempt. Jan has the measurement.
const MAIN_CLOCK_FONT = Graphics.FONT_NUMBER_MEDIUM;
const MAIN_CLOCK_FROM = 2;     // NUMBER_FONTS index of MAIN_CLOCK_FONT
// The string the clock's rung is decided on. Not the live time: see above.
const MAIN_CLOCK_WORST = "23:59";

// Main-page streak row: "dry 7 / 12" — the live no-fall run and the session's best.
const STREAK_CAPTION = "dry";
const STREAK_SEP = " / ";

// The Turns page carries BOTH runs, and says so in colour rather than in words:
// "streak: 2/5  7/11", one grey caption for the row and each run in its own ladder ink. The
// two words it used to spend ("fly", "dry") are gone — see drawStreakRow2 for why the colours
// say it better than the words did.
const STREAK_ROW_CAPTION = "streak:";
const STREAK_SEP_TIGHT = "/";

// The Turns page's bottom row: "P29/S22". The words are XTINY and the numbers FONT_SMALL,
// which is what keeps this row inside a bottom-arc chord — the same caption trick the streak
// row uses. P/S is the ENTRY side, i.e. which tack he was on going in, and it is the one
// number on the page a rider can act on tomorrow.
//
// Every space in these strings was spent and then taken back: with "P " and " / " the row was
// wide enough to be dropped entirely on the 43 mm watch. It needs no spaces: the caption
// letters are XTINY and the counts FONT_SMALL, and that size break separates them far better
// than a space does.
//
// It carried a "% flew" share in front of that until 0.9.18. Jan took the figure off the page
// in his layout review of 21 September 2026: flewCount over turnCount is arithmetic on two
// numbers the ladder row above already prints, so the page was stating one fact twice.
const TURNS_PORT = "P";
const TURNS_STBD = "S";
const TURNS_SIDE_SEP = "/";
// The rung that row's VALUES start at, as a TEXT_FONTS index — FONT_MEDIUM, which is also the
// band the row reserves. It steps down from there to TALLY_FLOOR (FONT_SMALL), where every
// other count on the watch stops.
const VERDICT_FROM = 1;

// ---- the CLEAN JIBE star (0.9.5; its own row until 0.9.18) ----
// The star had a row of its own — "★ 12  4.6 CPH" — from 0.9.5 until Jan's layout review of
// 21 September 2026 took both halves of it. The RATE left the watch: CPH is a sit-down number
// and the phone computes it on a cleaner clock (docs/algorithms.md, the watch divergences).
// The COUNT moved up into the ladder row, first of the four, because that is where it belongs
// — it refines the green count beside it, and a subset printed on a row of its own is a
// number the rider has to relate to another number himself.
//
// The star is still the count's only caption on the row itself; the header above names it
// "clean" in the same ink. There is no word beside the digits, because there is no room for
// one on a 240 px glass and the mark is the vocabulary the phone and the web already teach.
//
// Gap between the star and the count it labels. Wider than GLYPH_GAP: the mark is a filled
// shape, not a letter, and it needs more air than a glyph beside a word does before the count
// starts reading as part of it.
const CLEAN_GLYPH_GAP = 7;

// ---- the TACKS & JIBES page (0.9.17; re-cut 0.9.18, see drawKindsBody) ----
//
// Jan, 21 September 2026, from a tester practising tacks: the Turns page says how the
// maneuvers went, and nothing on the watch says WHICH maneuvers they were. This page does.
//
// 0.9.17 drew it as two GIANTS with "flew N" beside each word. Jan's layout review the same
// evening re-cut it to read like the Turns page instead — one wide LADDER ROW per kind, in
// the same four inks, with the kind's small word above or below its own row:
//
//        jibes
//    ★34  39 · 8 · 5
//     24 · 13 · 4
//        tacks
//
// The two wide rows straddle the equator, where the chord is widest, and the two narrow words
// take the shallow top and the deep bottom where it is not — which is the same rule the Turns
// page's legend and streaks follow one screen back. A rider who has learned to read one of
// these rows has learned to read all four on the watch.
//
// TACKS HAVE NO CLEAN RUNG, and never will: `cleanJibeCount` counts clean JIBES, which is the
// verdict the product is named after (docs/presentation.md "Clean jibe"). A star over the tack
// row would be inventing a number the engine does not compute.
//
// Aborted turns are on neither row and are not counted on the watch at all: a sweep the
// classifier rejects is a course change (TurnDetector.rejectedCount), and the engine's
// aborted-turn count has no watch twin (docs/algorithms.md, the watch divergences).
const KINDS_JIBES = "jibes";
const KINDS_TACKS = "tacks";
// The header is GONE when the axis is known (0.9.18): it spent a whole row saying "wind ~NNE"
// on a page whose four rows are already about the split that axis makes, and the Turns page
// one screen back now carries the axis as a mark. It survives for the one state it is the
// only explanation of — no axis at all, where every turn is a generic turn, both rows are
// zeros and the page is uninformed rather than broken.
const KINDS_NO_WIND = "wind not set";

// PAUSED banner. A word, not a value, so FONT_TINY is the right rung (docs review: XTINY and
// TINY are label sizes) — and a narrower banner is what lets it sit high enough on the glass
// to clear the rings entirely instead of punching a hole in them.
const PAUSED_TEXT = "PAUSED";
// The banner's long form, used where the chord at the banner's depth has room for it: the
// rider who pressed START expecting to finish is looking at exactly this word, and it is the
// one moment the key he actually needs can be named (audit, 15 Sep 2026). MAIN's own top row
// keeps the short word — that row is the clock's width.
const PAUSED_TEXT_LONG = "PAUSED · BACK saves";
const PAUSED_FONT_IDX = 3;

// Cell geometry. The column offset is NOT a constant: the round display narrows fast below
// the equator, so each cell row splits the chord available at its own depth and only falls
// back to CELL_DX_MAX where there is room to spare.
const CELL_DX_MAX = 105;
const CELL_GUTTER = 10;

// Gap between a cell's glyph and the word beside it.
const GLYPH_GAP = 4;

// Bezel decorations, AS AUTHORED ON A 454 px GLASS. Every one of these is read through
// RecordingView.scaled(), never used raw, because they are ring geometry expressed as
// fractions of a radius: a 10 px ring is 4.4 % of the radius on a 454 px fenix 8 and 7.7 % on
// a 260 px fenix 8 Solar, so taken literally the narrow glass gives up nearly twice the share
// of its width — and it is the glass that can least afford it, because fitRadius now (rightly)
// refuses to draw text underneath any of it.
const REF_PX = 454;

// Foil-% bezel arc: pen width, and how far the arc's CENTRE line sits inside the glass.
// 5 + a pen of 6 puts the outer edge 2 px in — the same FIT_MARGIN the text respects.
const BEZEL_PEN = 6;
const BEZEL_INSET = 5;

// The flight-state ring on a HERO/MAIN page. It normally owns the bezel; when the page also
// asks for the foil-% arc it steps inside so the two nest instead of painting over each other.
const RING_INSET = 7;
const RING_PEN = 10;
const RING_INSET_NESTED = 16;
const RING_PEN_NESTED = 6;

// Safety margin inside the glass, in pixels, used by every fit. 2 px is deliberately tight:
// the shipped Clock page puts "23:59" in FONT_NUMBER_THAI_HOT within a few pixels of the
// bezel and it reads well, so anything more forgiving would shrink screens that are fine.
const FIT_MARGIN = 2;

// The GRID4 block sits this far above centre, as authored on a GRID_REF_PX glass. A 2x2 of
// FONT_LARGE cells plus a giant number is more content than a 454 px circle holds when
// centred — the bottom row's outer corners go off the glass. Lifting the block trades unused
// space at the top, where nothing is drawn, for cell width at the bottom, where the chord is
// the binding constraint.
//
// It is a RATIO, not a pixel count: 20 px was 4.4 % of the height it was authored at and
// 8.3 % of a 240 px fenix 7S — shoving the block furthest off centre on the narrow glass
// that can least afford it. RecordingView.gridBias() scales it, the way Glyphs.size() and
// StartView.dotRadius() already scale theirs.
//
// It grew from 20 to 28 when fitRadius learned about the foil-% arc: the shipped Session page
// carries foil %, so it DRAWS that arc, and the 11 px of radius the arc costs came straight
// out of the bottom row's chord — enough to push a "199:59" flight timer below FONT_MEDIUM.
// The lift buys those pixels back from the empty top of the screen.
const GRID_BIAS = 28;
const GRID_REF_PX = 454;

// The CLOCK page's lift, in the other direction — see drawClockPage. Same reference glass.
const CLOCK_BIAS = 32;

// Font ladders, largest first. Giant slots walk the number fonts, everything else the text
// fonts; fitFont() picks the first that fits the chord it has been given.
var NUMBER_FONTS as Array<Graphics.FontType> = [
    Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT,
    Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD
];
var TEXT_FONTS as Array<Graphics.FontType> = [
    Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
    Graphics.FONT_TINY, Graphics.FONT_XTINY
];

// The GRID4 pair band's ladder (see drawPairBand): the single giant's own font first, then the
// two text rungs a VALUE is allowed to use. PAIR_FLOOR is the last of them — FONT_MEDIUM, the
// readability floor for a number — and it is an index into this array, not into TEXT_FONTS.
var PAIR_FONTS as Array<Graphics.FontType> = [
    Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE, Graphics.FONT_MEDIUM
];
const PAIR_FLOOR = 2;

// The large set's probed giant, one per stack shape — [two-row, three-row]. `null` after the
// probe means "this device has no face that beats the bitmap ladder", which is the answer on
// every CIQ 3.x product and on the narrow glasses. Probed once (see VEC_FACES above) and
// never again for the life of the app; `_vecProbed` is what says the probe has run, because
// `null` is a real answer and cannot say it itself.
var _vecGiant as Array<Graphics.FontType?> = [null, null];
var _vecProbed as Boolean = false;

// The ladder row's four counts, [clean, flew, touch, fell]. A module-level scratch filled in
// place by `ladderOf`, the same no-allocation contract Glyphs' triangle and star scratches
// keep: the Tacks & jibes page draws two of these a frame and the fitter measures each of
// them twice, and a fresh array per call would be the only allocation on the page.
var _ladder as Array<Number> = [0, 0, 0, 0];

// Slots in the `texts` array pairFits takes the band's four strings in. They ride
// as one array because Monkey C caps a function at nine arguments on CIQ 3.x and the
// spelled-out left/right value/caption form made pairFits the app's only ten-argument call.
const PAIR_LV = 0;   // left value
const PAIR_LC = 1;   // left caption
const PAIR_RV = 2;   // right value
const PAIR_RC = 3;   // right caption

// ---- the LARGE page set (0.9.16, see drawBigPage) ----
//
// One giant, one word, and on the turns page one tally. Two things make it bigger than the
// HERO page it looks like rather than merely emptier:
//
//   * the GIANT gets the whole stack. HERO spends an XTINY unit line and up to two sub-rows
//     under its number, so the number's own row sits above the equator and its chord is the
//     one at that depth. BIG has two rows, so the giant straddles the centre — which is
//     where the chord is widest — and a value that stepped down a rung on HERO does not
//     step down here.
//   * the WORD is FONT_LARGE and not FONT_XTINY. That is the rung up this whole set exists
//     for: a number nobody can name is not readable however big it is, and a set for a rider
//     without his glasses must not answer "24.3 what?" in six-pixel letters. It steps down
//     the ordinary text ladder when the chord is narrower, like every other row on the watch.
//
// No state ring and no flight ring: a ring costs 10-16 px of every radius, i.e. ~7 % of the
// digits on a 240 px glass, and this set's whole trade is radius for digit height. The foil-%
// page keeps the ARC, because it earns it the ordinary way (pageDrawsFoilArc) and the arc is
// the same number the page's giant already is — a sweep, read without reading.
//
// 0.9.18 re-ordered the stack and moved a rung from the word to the number. Jan's layout
// review: **numbers larger, words smaller** — a label has to be found once, a number is read
// every glance. So the word is FONT_MEDIUM rather than FONT_LARGE, it sits at the BOTTOM of
// the page rather than directly under the giant, and what it gives up in band the giant takes
// (see bigGiantFont, which also leaves the bitmap ladder where the device has a vector face).
// It is still two rungs above every caption on the standard pages, which is what the set is
// for: a number nobody can name is not readable however big it is.
const BIG_WORD_FONT = 1;      // TEXT_FONTS index: FONT_MEDIUM
// The outcome row under the turns and kind screens' giants starts at FONT_MEDIUM, the rung
// the MAIN page's own tally row reserves, and sheds size and then content from there.
const BIG_TALLY_FROM = 1;

// ---- the LARGE giant leaves the bitmap ladder (0.9.18) ----
//
// Jan measured it off a sheet: "33.8" in FONT_NUMBER_THAI_HOT fills about 55 % of a 454 px
// glass, and THAI_HOT is the TOP of the bitmap ladder — the fitter had nowhere left to go, so
// "as large as the fitter allows" was already true and still too small. The way up is the
// firmware's VECTOR faces, and the app already has a worked example of using them safely:
// LockView.codeFont, which fits the invite code the same way.
//
// Three rules carried over from there verbatim, because each of them is a bug that was found
// the hard way:
//   * the BITMAP ladder is the FLOOR, not the fallback. A vector size is taken only where it
//     genuinely beats the ladder; on a 240 px fenix the widest vector that fits is shorter
//     than FONT_NUMBER_THAI_HOT, and taking it would SHRINK the one number the page is.
//   * a face is only accepted if it can draw every character of the string. On the epix 2 /
//     MARQ 2 / Descent Mk3 families `BionicBold` is a DIGITS-ONLY cut: ask it for the width
//     of "%" and it answers 0, which every width test reads as "fits comfortably" — so a
//     "56%" would be drawn as "56" and a "33.8" as "338".
//   * `Graphics has :getVectorFont` guards the whole block, so CIQ 3.x devices (the fenix 5
//     Plus family, the tight one) never enter it and pay nothing but the branch.
//
// And one rule that is this page's own: the size is PROBED ONCE PER SHAPE and cached. The
// giant is redrawn every second and a live speed changes every second, so a per-frame probe
// would be ~60 getVectorFont calls a second AND a number whose size flickered as its value
// changed. The probe fits the set's own WORST-CASE string instead, per stack shape — the two
// shapes are "giant + word" and "giant + outcome row + word" — so all five screens of the set
// are drawn at one of two sizes and neither of them moves for the rest of the session.
const VEC_FACES = ["BionicBold", "BionicMedium", "RobotoCondensedBold", "RobotoRegular"];
// The probe walks DOWN from this share of the glass height, in steps, until the worst case
// fits. 62 % of a 454 px glass is 281 px of line, comfortably past anything that will fit.
const VEC_MAX_PCT = 62;
const VEC_STEP = 6;
// Every character a large-set value can be made of. Probed one at a time against a candidate
// face, for the digits-only reason above.
const VEC_ALPHABET = "0123456789.:%";
// The widest string each stack shape has to hold: "100%" for the two-row screens (speed and
// the foil share) and "999" for the three-row ones (turns, jibes, tacks). Taken from
// PageModel.worstValue, which is where every other worst case on this watch comes from.
const VEC_WORST_2ROW = "100%";
const VEC_WORST_3ROW = "999";

// ---- the FOIL page's table (see drawFoilPage) ----
// A titled 3x2: one header, two column headers, three rows of two numbers. Everything on it
// is a foil number, so the word "foil" is said ONCE, at the top, instead of six times in six
// cell labels — which is the whole reason the page is a table and not a grid of cells.
//
// The column headers name what the column counts. "min" became "time" in 0.9.2 (the rider's
// call): the column holds m:ss and h:mm strings, so "min" was naming a unit the cells do not
// actually print, and the word beside "km" reads as the pair it is — time and distance, the
// same session asked twice.
// It carried the flight COUNT from 0.9.16 to 0.9.18 — "foil · 47" — and Jan's layout review
// of 21 September 2026 took it off: a table of six foil numbers with a seventh number in its
// own TITLE is a title that has to be read rather than found, and the count is not a foil
// number (it was on this page until 0.9.2 for exactly that reason, and left with the
// odometer). The rows explain themselves; the word is the page's name and nothing else.
//
// Where the count went: nowhere on the watch, which is the honest answer. It is FIT session
// field 36 and it is on the phone's own session page. See docs/presentation.md.
const FOIL_TITLE = "foil";
const FOIL_COL_TIME = "time";
const FOIL_COL_DIST = "km";
// The row keys. `total` is the word — Jan, 21 September 2026: "tot" is an abbreviation the
// rider has to expand and the row it names is the most-read row on the table. It gives way to
// `tot` in exactly one case, which is the FLOOR: where the long word would push the widest
// value the table can be handed below TEXT_FONTS[FOIL_FLOOR], the readability floor every
// number on this watch keeps. Until this round it also gave way whenever the short word would
// buy the values a whole font RUNG, which is the trade that made every narrow glass say "tot".
const FOIL_KEY_TOTAL = "total";
const FOIL_KEY_TOTAL_TIGHT = "tot";
const FOIL_KEY_MAX = "max";
const FOIL_KEY_GAP = 6;
// Values never go below TEXT_FONTS[FOIL_FLOOR] = FONT_SMALL, the readability floor every
// other number on this watch keeps.
const FOIL_FLOOR = 2;

// Timeline page bands (see drawTimelinePage). The two tall ones were authored for the fenix 8
// family, whose smallest glass is TL_REF_PX; RecordingView.stripH/sparkH keep them exactly as
// written at or above that width and scale them down below it.
// The two tall bands grew in 0.9.2 (44 -> 56, 96 -> 124). The three bands and their captions
// filled 263 px of a 454 px glass, i.e. 42 % of the page was empty — on the one page whose
// content is SHAPES, where height is resolution: a sparkline 96 px tall resolves a speed run
// to about two thirds of a knot. They are paid for out of the top and bottom air, and they
// cost the outcome-dot row three of its dots (35 -> 32 on a 454 px glass), because the row is
// pushed deeper into the arc. A taller sparkline is worth more than three dots the Turns page
// also draws.
const TL_REF_PX = 416;
const TL_STRIP_H = 56;
const TL_SPARK_H = 124;
const TL_DOT_R = 6;
const TL_DOT_GAP = 4;
const TL_MARGIN = 6;

// MAP page. The margin is what the square inscribed in the glass gives up so the distance
// caption has a line to sit on under it — authored at REF_PX and read through scaled(), like
// every other bezel dimension. The waiting line is what the page says before the first fix:
// a map page that renders empty reads as a crashed map page, which on this app's history is
// exactly the wrong thing to imply.
// It grew from 34 to 52 in 0.9.18. Jan's layout review: "make the distance number larger."
// The caption was FONT_SMALL, the readability FLOOR, on a page whose only number it is — so
// the number now walks the text ladder from FONT_LARGE down to that floor, its unit rides
// beside it at FONT_XTINY (numbers larger, words smaller), and the taller line needs the
// square to give up 18 px of side to hang it under. A map you can read the scale of beats a
// map 7 % wider whose scale you cannot — the same trade SUM_TRACK_MARGIN made in 0.9.2.
const MAP_MARGIN = 52;
const MAP_WAITING = "waiting for GPS";
// The unit beside the odometer, and the gap before it. The digits are the value and "km" is
// a word about it, so they are not the same size and never have been on this watch.
const MAP_KM = "km";
const MAP_KM_GAP = GLYPH_GAP;

// The on-water screens. Which screens exist, in what order, is PageModel's business — this
// class only knows how to paint a layout. Fonts are deliberately large: spray + chop make
// small text unreadable on the water. All vertical positions are stacked from
// dc.getFontHeight() so blocks can never overlap, on any fenix 8 variant, and the row-Y maths
// lives in static helpers the layout tests measure against the round glass.
class RecordingView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    // Paging no longer swaps the view (PageNav.step is an index and a repaint), so this fires
    // once per entry to the recording UI. CrashBreadcrumb.view dedupes anyway.
    function onShow() as Void {
        CrashBreadcrumb.view(CrashBreadcrumb.V_RECORDING);
    }

    // Paging swaps the whole View, which fires onHide — so cancelling the celebration here
    // is precisely what PbFlash's module-level state exists to prevent (see its header). The
    // flash clears itself at FRAMES, which is what makes it safe to leave running; the
    // explicit stop() calls that matter are on the save/discard path in SessionController.
    function onHide() as Void {
    }

    function onUpdate(dc as Dc) as Void {
        var c = getApp().controller;
        var i = PageNav.index;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        // A page that shows foil % anywhere gets it a second time as an arc round the glass —
        // the one number the rider glances at without reading.
        var foilArc = PageModel.pageDrawsFoilArc(i);
        var layout = PageModel.layoutAt(i);
        // Pages that paint the flight-state ring, and therefore have less room for text.
        var ring = layout == PageModel.LAYOUT_HERO || layout == PageModel.LAYOUT_MAIN;
        if (layout == PageModel.LAYOUT_MAIN) {
            drawMainPage(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_HERO) {
            drawHeroPage(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_BIG) {
            drawBigPage(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_FOIL) {
            drawFoilPage(dc, c, foilArc);
        } else if (layout == PageModel.LAYOUT_GRID4) {
            drawGridPage(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_CELLS2) {
            drawCells2Page(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_RECORDS) {
            drawRecordsBody(dc, c);
        } else if (layout == PageModel.LAYOUT_TURNS) {
            drawTurnsPage(dc, c);
        } else if (layout == PageModel.LAYOUT_KINDS) {
            drawKindsPage(dc, c);
        } else if (layout == PageModel.LAYOUT_TIMELINE) {
            drawTimelinePage(dc, c);
        } else if (layout == PageModel.LAYOUT_CLOCK) {
            drawClockPage(dc, c, i, foilArc);
        } else if (layout == PageModel.LAYOUT_MAP) {
            drawMapPage(dc, c, foilArc);
        } else {
            // a property the firmware handed us out of range — fall back to something readable
            drawHeroPage(dc, c, i, foilArc);
            ring = true;
        }
        if (foilArc) {
            drawFoilBezel(dc, c);
        }
        // The celebration paints over the page, so it goes on before the PAUSED banner and
        // never after: a rider who pauses mid-flash must still see that he is paused, which is
        // why the banner carries its own opaque background rather than trusting the backdrop.
        if (PbFlash.active()) {
            drawPbFlash(dc);
        }
        // The event flash paints over the PB flash if the two ever coincide: a verdict is
        // the newer fact. The takeoff variant is a ring and leaves the page readable.
        if (EventFlash.active()) {
            drawEventFlash(dc, fitRadius(dc, ring, foilArc));
        }
        // MAIN says PAUSED in its own top row — it is the only layout whose first row sits
        // where the banner wants to be, and a state word beats the time of day. Every other
        // page gets the banner, the map page included: that it could NOT was the whole reason
        // the map used to be skipped while paused (PageNav), and drawing it ourselves is what
        // gave the banner back.
        if (c.state == SessionController.STATE_PAUSED && layout != PageModel.LAYOUT_MAIN) {
            drawPausedBanner(dc, fitRadius(dc, ring, foilArc));
        } else if (layout != PageModel.LAYOUT_MAIN && !EventFlash.active()
                && EventFlash.stripActive(System.getTimer())) {
            // The afterglow: the last verdict, where the banner would be. MAIN carries it in
            // its own top row, as it carries PAUSED. Never under a running flash, and never
            // instead of PAUSED — a paused session is the more urgent fact.
            drawEventStrip(dc, fitRadius(dc, ring, foilArc));
        }
    }

    // ---- the event flash and its afterglow (EventFlash, 0.9.11) ----
    // Full: the glass takes the event's ink, one glyph and one word in black on it. Colour
    // and shape both carry the event, so it reads on a MIP palette and to a rider who cannot
    // tell the ladder's green from its red. Ring: the takeoff's, a thick circle inside the
    // bezel, the page left as it is.
    hidden function drawEventFlash(dc as Dc, radius as Number) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var col = EventFlash.color();
        if (EventFlash.isRing()) {
            var pen = bezelPen(dc) * 3;
            dc.setPenWidth(pen);
            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, cx - bezelInset(dc) - pen / 2);
            dc.setPenWidth(1);
            return;
        }
        dc.setColor(col, col);
        dc.clear();
        var k = EventFlash.kind;
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var s = radius * 5 / 6;                    // the glyph box, ~40 % of the glass
        var gy = cy - hL / 2;                      // glyph centre, above the word
        var wy = gy + s / 2 + hL / 2;              // the word, under the glyph
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (k == EventFlash.EV_FLEW || k == EventFlash.EV_TOUCH || k == EventFlash.EV_FELL) {
            var o = k == EventFlash.EV_FLEW ? TurnDetector.OUTCOME_FLEW
                : (k == EventFlash.EV_TOUCH ? TurnDetector.OUTCOME_TOUCHDOWN
                    : TurnDetector.OUTCOME_FELL);
            Glyphs.drawOutcome(dc, o, cx, gy, s, Graphics.COLOR_BLACK);
        } else if (k == EventFlash.EV_CLEAN) {
            Glyphs.drawStar(dc, cx, gy, s);
        } else {
            // a streak count or a duration: digits are the glyph
            var v = k == EventFlash.EV_STREAK ? EventFlash.value.toString()
                : EventFlash.mmss(EventFlash.value);
            dc.drawText(cx, gy, fitFont(dc, NUMBER_FONTS, 0, v,
                rowBudget(radius, gy - cy, inkH(dc, Graphics.FONT_NUMBER_HOT))), v, CV);
        }
        var word = EventFlash.word(k, EventFlash.value);
        dc.drawText(cx, wy, fitFont(dc, TEXT_FONTS, 0, word,
            rowBudget(radius, wy - cy, inkH(dc, Graphics.FONT_LARGE))), word, CV);
    }

    // The strip: the last event's line, black on its ink, sitting where the pause banner
    // sits — the one derived position on a page that is not part of a row stack.
    hidden function drawEventStrip(dc as Dc, radius as Number) as Void {
        var font = TEXT_FONTS[PAUSED_FONT_IDX];
        var text = EventFlash.stripText(EventFlash.lastKind, EventFlash.lastTurnKind,
            EventFlash.lastValue);
        var w = dc.getTextWidthInPixels(text, font);
        dc.setColor(Graphics.COLOR_BLACK, EventFlash.baseColor(EventFlash.lastKind));
        dc.drawText(dc.getWidth() / 2, pausedBannerY(dc, w, radius), font, text, CV);
    }

    // The banner is the only thing on a recording page that is not part of a row stack, so
    // its position has to be DERIVED. It used to be `y = 18` with an opaque background, which
    // painted a black box from y 18 to 71 — straight across the flight ring, the nested ring
    // and the foil-% arc, so pausing bit a ~30 deg hole out of whichever ring the page was
    // showing, including the start of the arc, which is the one place a sweep is read from.
    //
    // Now the box is placed at the deepest y whose top corners still clear `radius` — the
    // same radius the page's text is fitted to, i.e. inside every ring the page draws. The
    // opaque background stays: it is what makes the word survive the PB flash painting over
    // the page underneath it.
    hidden function drawPausedBanner(dc as Dc, radius as Number) as Void {
        var font = TEXT_FONTS[PAUSED_FONT_IDX];
        var text = pausedText(dc, font, radius);
        var w = dc.getTextWidthInPixels(text, font);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, pausedBannerY(dc, w, radius), font, text, CV);
    }

    // The long banner where the glass at the banner's own depth can take it, the word alone
    // where it cannot. Public for the layout test.
    static function pausedText(dc as Dc, font as Graphics.FontType, radius as Number) as String {
        // pausedBannerY drops a wider box until its corners clear the glass; the long form
        // is used only while that still leaves it in the top third, a banner and not a
        // headline over the page.
        var w = dc.getTextWidthInPixels(PAUSED_TEXT_LONG, font);
        var y = pausedBannerY(dc, w, radius);
        return y <= dc.getHeight() / 2 - radius / 3 ? PAUSED_TEXT_LONG : PAUSED_TEXT;
    }

    // Ink centre of that banner. Shared with the layout test, which asserts the box corner
    // lands inside the ring rather than on it.
    static function pausedBannerY(dc as Dc, w as Number, radius as Number) as Number {
        var cy = dc.getHeight() / 2;
        var h = dc.getFontHeight(TEXT_FONTS[PAUSED_FONT_IDX]);
        var half = w / 2;
        var v = radius * radius - half * half;
        var dy = v > 0 ? Math.sqrt(v.toFloat()).toNumber() : 0;
        var y = cy - dy + h / 2;
        return y > cy ? cy : y;
    }

    // ---- foil-% bezel arc ----
    // 12 o'clock, clockwise, the phase teal over a dimmed track, hugging the inside of the
    // bezel. Teal and not green: this arc is "how much of the session was on the foil", a
    // PHASE, and green on this app means "that turn flew through" (docs/presentation.md).
    // Garmin's arc angles run COUNTER-clockwise from 3 o'clock, so 12 o'clock is 90 deg and
    // sweeping clockwise subtracts. Two primitive calls and integer maths: nothing allocates.
    // Public: the post-save Verdict page opens on this same arc, so the rider lands on a
    // shape he has been reading all session.
    function drawFoilBezel(dc as Dc, c as SessionController) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var pen = bezelPen(dc);
        var r = cx - bezelInset(dc) - pen / 2;
        dc.setPenWidth(pen);
        dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        var pct = c.engine.foilPct().toNumber();
        if (pct > 0) {
            dc.setColor(Ink.phaseFlying(), Graphics.COLOR_TRANSPARENT);
            if (pct >= 100) {
                dc.drawCircle(cx, cy, r);
            } else {
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 90, bezelEndDeg(pct));
            }
        }
        dc.setPenWidth(1);
    }

    // End angle of a `pct` sweep that starts at 12 o'clock and runs clockwise, normalised
    // into 0..359. Shared with the layout test.
    static function bezelEndDeg(pct as Number) as Number {
        var end = 90 - pct * 360 / 100;
        while (end < 0) {
            end += 360;
        }
        return end % 360;
    }

    // ---- PB celebration ----
    // The whole screen goes the effort orange for ~700 ms with the new best on it. Frame
    // parity picks the shade, which is what turns a flash into a pulse (see PbFlash). Orange
    // and not green: a record is an EFFORT event, not a verdict, and green on this app is the
    // outcome ladder's "flew through" (docs/presentation.md).
    hidden function drawPbFlash(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var col = PbFlash.color();
        dc.setColor(col, col);
        dc.clear();
        var hHot = dc.getFontHeight(Graphics.FONT_NUMBER_HOT);
        var hS = dc.getFontHeight(Graphics.FONT_SMALL);
        var radius = fitRadius(dc, false, false);
        var v = AppSettings.speedToDisplay(PbFlash.best2sMps).format("%.1f");
        var y = cy - (hHot + hS) / 2 + hS + hHot / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (hHot + hS) / 2 + hS / 2, Graphics.FONT_SMALL, "NEW PB", CV);
        // fitted like every other giant: the overlay happens to fit on every shipped variant,
        // but "happens to" is what finding 1.1 was made of.
        dc.drawText(cx, y, fitFont(dc, NUMBER_FONTS, 1, v,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_NUMBER_HOT))), v, CV);
        dc.drawText(cx, cy + (hHot + hS) / 2 + hS / 2, Graphics.FONT_SMALL,
            AppSettings.speedLabel(), CV);
    }

    const CV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    // ---- chord fitting ----
    // Garmin's font heights are LINE heights: leading above and below the glyphs. Stacking
    // uses the full line height, because that is what keeps two rows from touching. Fitting
    // uses the ink — about three quarters of it — because that is what the round glass
    // actually clips. Both numbers come from the same dc, so every variant gets its own.

    // 0.9.13: measured, not assumed. Three quarters of the line was written for font sets
    // where a number line carries a quarter of leading (fenix 8: THAI_HOT 210 px line,
    // 153 px ascent; fenix 7S: 105 / 76). The fenix 5 Plus family's Chronos number fonts
    // carry NONE — ascent 58 of a 58 px line, descent 0 — so every band stacked on 3/4 was a
    // quarter of a number line short there: the clock sat on the giant's unit, "best 2s" on
    // its record, SAVED on the verdict (Leo, fenix 5X Plus, 17 Sep 2026). The ascent is the
    // firmware's own word for where the ink reaches; the 3/4 floor keeps every other glass
    // exactly where it was (their ascents are a few px under it).
    //
    // Number fonts only. Digits fill the ascent (no descenders, cap-height glyphs); a text
    // font's ascent leaves room for accents above a row of words that never uses it, and
    // taking it would shrink every text chord on every glass by 2-3 px for nothing — the
    // Turns page's port/starboard row on a fenix 8 fits its 302 px by 2.
    static function inkH(dc as Dc, font as Graphics.FontType) as Number {
        var line = dc.getFontHeight(font) * 3 / 4;
        if (!isNumberFont(font)) {
            return line;
        }
        var asc = Graphics.getFontAscent(font);
        return asc > line ? asc : line;
    }

    static function isNumberFont(font as Graphics.FontType) as Boolean {
        for (var i = 0; i < NUMBER_FONTS.size(); i++) {
            if (font == NUMBER_FONTS[i]) {
                return true;
            }
        }
        return false;
    }

    // Half the chord available to a box of ink height `h` whose centre is `dy` from the middle.
    static function chordHalf(radius as Number, dy as Number, h as Number) as Number {
        // (h + 1) / 2, not h / 2: an odd ink height rounded DOWN put the box's corner half a
        // pixel outside the chord the fitter thought it had, and on the Venu 3's font set
        // (0.9.10) that half pixel was the whole margin — the hero giant landed 0.4 px over
        // the fit radius. Rounding up keeps the fitter on the safe side of the test's own
        // corner arithmetic on every glass.
        var d = dy.abs() + (h + 1) / 2;
        var v = radius * radius - d * d;
        return v > 0 ? Math.sqrt(v.toFloat()).toNumber() : 0;
    }

    // Widest text the row at `dy` can hold for a box of ink height `h`.
    static function rowBudget(radius as Number, dy as Number, h as Number) as Number {
        return 2 * chordHalf(radius, dy, h);
    }

    // Largest NUMBER font at or after `from` that renders `text` inside the chord AT ITS OWN
    // INK HEIGHT, falling into the text ladder when none does.
    //
    // `fitGiant` measures every candidate against ONE budget — the chord for the top
    // candidate's box — which is right for a row whose band is reserved for the top rung and
    // wrong for a row near an arc, where the box height is most of what decides the chord. On
    // the MAIN page's clock row the difference is the whole question: a FONT_NUMBER_MEDIUM
    // "23:59" needs a 114 px box, and the chord for a 114 px box at that depth on a 454 px
    // glass is narrower than the one for FONT_NUMBER_MILD's 85 px box by enough to matter. A
    // fitter blind to that answers "nothing fits, take a text font" and hands a rider a
    // FONT_LARGE time of day — smaller than the clock that shipped.
    //
    // Only ever finds a font `fitGiant` would also have accepted or a LARGER one, never a
    // smaller: each candidate is checked against a chord at least as wide as the one
    // `fitGiant` would have used for it.
    static function fitByOwnInk(dc as Dc, text as String, from as Number, radius as Number,
            y as Number, cy as Number) as Graphics.FontType {
        if (hasLetters(text)) {
            return fitFont(dc, TEXT_FONTS, 0, text,
                rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[0])));
        }
        for (var i = from; i < NUMBER_FONTS.size(); i++) {
            var f = NUMBER_FONTS[i];
            if (dc.getTextWidthInPixels(text, f) <= rowBudget(radius, y - cy, inkH(dc, f))) {
                return f;
            }
        }
        for (var i = 0; i < TEXT_FONTS.size() - 1; i++) {
            var f = TEXT_FONTS[i];
            if (dc.getTextWidthInPixels(text, f) <= rowBudget(radius, y - cy, inkH(dc, f))) {
                return f;
            }
        }
        return TEXT_FONTS[TEXT_FONTS.size() - 1];
    }

    // Largest font in `ladder` at or after `from` that renders `text` within `maxW`.
    // Falls back to the last (smallest) entry rather than returning nothing.
    // A font set where the NUMBER ladder is shorter than the text ladder: the fenix 5 Plus
    // family draws FONT_NUMBER_MILD at 26 px under a 29 px FONT_SMALL (the fenix 7S, same
    // 240 px glass, has 55 under 29). Every "a value must not fall below a label font" floor
    // in this file and in the layout suite was written for sets where numbers are the tall
    // half; on this one the floor is the number ladder's own bottom rung, and the pair band
    // grows to hold its value font the way it does on the Forerunners (giantBand).
    static function numberLadderIsSmall(dc as Dc) as Boolean {
        return dc.getFontHeight(Graphics.FONT_NUMBER_MILD) < dc.getFontHeight(Graphics.FONT_SMALL);
    }

    static function fitFont(dc as Dc, ladder as Array<Graphics.FontType>, from as Number,
            text as String, maxW as Number) as Graphics.FontType {
        for (var i = from; i < ladder.size() - 1; i++) {
            if (dc.getTextWidthInPixels(text, ladder[i]) <= maxW) {
                return ladder[i];
            }
        }
        return ladder[ladder.size() - 1];
    }

    // The radius text may use. It is NOT simply the glass: a page that paints the flight ring
    // or the foil-% arc has already spent the outer 10-16 px of every radius on it, and a
    // fitter blind to that fills right up to the ring's inner edge — measured, the hero
    // giant's corner landed 0.1 px inside the ring on the 47 mm and 2.3 px OVER it on the
    // 43 mm, i.e. the speed number was drawn on top of the state ring. Every layout test
    // asserts against this function, so they inherit the correction for free.
    //
    // When a page carries both, the ring nests INSIDE the arc (RING_INSET_NESTED), so the
    // ring's inner edge is the binding constraint and the arc's is not.
    // A giant that has run out of NUMBER fonts. Every other giant on every other page starts
    // high enough in NUMBER_FONTS to have somewhere to step down to; the GRID4 giant does not
    // — its band is already FONT_NUMBER_MILD, the smallest of them — so when the chord is
    // narrower than MILD (a "199:59" timer on a page that also draws the foil-% arc) the only
    // honest answers are "clip" or "leave the number ladder". It leaves the ladder: a smaller
    // number is readable, a clipped one is not, and the row's band is unchanged either way.
    static function fitGiant(dc as Dc, text as String, from as Number,
            maxW as Number) as Graphics.FontType {
        // A WORD never walks the number ladder: the number fonts have no letters, and on a
        // set where the ladder's bottom rung is narrow enough to "fit" PAUSED (fenix 5 Plus:
        // MILD is 26 px) the rider got six empty boxes where the banner should be. The width
        // test alone was the guard, and it held only where the number fonts are big.
        if (hasLetters(text)) {
            return fitFont(dc, TEXT_FONTS, 0, text, maxW);
        }
        for (var i = from; i < NUMBER_FONTS.size(); i++) {
            if (dc.getTextWidthInPixels(text, NUMBER_FONTS[i]) <= maxW) {
                return NUMBER_FONTS[i];
            }
        }
        return fitFont(dc, TEXT_FONTS, 0, text, maxW);
    }

    // The first TEXT_FONTS rung whose ink fits a band `h` tall — the last rung when none does.
    static function textFontFrom(dc as Dc, h as Number) as Number {
        for (var i = 0; i < TEXT_FONTS.size(); i++) {
            if (inkH(dc, TEXT_FONTS[i]) <= h) {
                return i;
            }
        }
        return TEXT_FONTS.size() - 1;
    }

    // True when `text` carries a letter — anything a number font cannot draw. Shared with
    // the layout test. Digits, ':', '.', '/', '%', '+' and '-' are the number ladder's own.
    static function hasLetters(text as String) as Boolean {
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
                return true;
            }
        }
        return false;
    }

    // A 454-authored bezel dimension on THIS glass, never below 1 px. Same treatment
    // Glyphs.size() and StartView.dotRadius() already give theirs.
    static function scaled(dc as Dc, authored as Number) as Number {
        var v = dc.getWidth() * authored / REF_PX;
        return v < 1 ? 1 : v;
    }

    static function ringInset(dc as Dc, nested as Boolean) as Number {
        return scaled(dc, nested ? RING_INSET_NESTED : RING_INSET);
    }

    static function ringPen(dc as Dc, nested as Boolean) as Number {
        return scaled(dc, nested ? RING_PEN_NESTED : RING_PEN);
    }

    static function bezelInset(dc as Dc) as Number {
        return scaled(dc, BEZEL_INSET);
    }

    static function bezelPen(dc as Dc) as Number {
        return scaled(dc, BEZEL_PEN);
    }

    static function fitRadius(dc as Dc, ring as Boolean, arc as Boolean) as Number {
        var cx = dc.getWidth() / 2;
        var r = cx - FIT_MARGIN;
        if (ring) {
            var inner = cx - ringInset(dc, arc) - ringPen(dc, arc) / 2 - FIT_MARGIN;
            if (inner < r) {
                r = inner;
            }
        }
        if (arc) {
            var a = cx - bezelInset(dc) - bezelPen(dc) - FIT_MARGIN;
            if (a < r) {
                r = a;
            }
        }
        return r;
    }

    // Column offset and per-cell half width for a cell row whose deepest ink is `dy` below the
    // centre: split that chord in two with a gutter, then cap the spread so a roomy row still
    // looks like the two-column grid it is. Returns [dx, halfWidth].
    static function cellColumns(radius as Number, dy as Number, h as Number)
            as Array<Number> {
        // each cell lives in ONE half of the chord, so the half-chord is the budget to split
        var w = (chordHalf(radius, dy, h) - CELL_GUTTER) / 2;
        var dx = CELL_GUTTER / 2 + w;
        if (dx > CELL_DX_MAX) {
            dx = CELL_DX_MAX;
            w = CELL_DX_MAX - CELL_GUTTER / 2;
        }
        return [dx, w];
    }

    // The flight-state ring: the phase teal while flying, a visible dim ink off foil. It
    // steps inside when the page also carries the foil-% arc, so the bezel holds exactly one
    // ring at a time. Teal rather than green — the ring is a PHASE, and green on this app is
    // the outcome ladder's "flew through" (docs/presentation.md).
    hidden function drawStateRing(dc as Dc, c as SessionController, foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var flying = c.engine.detector.state == FlightDetector.STATE_ON;
        dc.setPenWidth(ringPen(dc, foilArc));
        dc.setColor(flying ? Ink.phaseFlying() : Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, dc.getHeight() / 2, cx - ringInset(dc, foilArc));
        dc.setPenWidth(1);
    }

    // ---- MAIN: the default page 1 ----
    //
    // Five rows, and every one of them answers a question the rider actually asks between two
    // jibes: how fast did that run go, how are the turns going, am I still dry, and what time
    // is it. Deliberately NOT on this page: the session duration (he can see the sun) and the
    // flight timer (it is over by the time he looks). Both remain catalog metrics for any
    // other page's slots.
    //
    // THE GIANT IS NOT LIVE SPEED. A rider looks at his watch when he is NOT moving — coming
    // off a run, sitting on the board, sailing back — and at that moment the live number reads
    // 4 km/h and tells him nothing about the run he just did. The slot therefore defaults to
    // the best 10 s, and it is a CONFIGURABLE slot (pg1s1) like any HERO giant: a rider who
    // wants the live number back sets M_SPEED in Garmin Connect, and no code knows the
    // difference. That is also why the giant now carries a small caption — "best 10s" is not
    // self-evident the way a live speedometer was.
    //
    // The clock is a rung LARGER than it was and the giant a band SMALLER (FONT_NUMBER_MEDIUM,
    // ~88 px of digit — still three times the readability floor and by far the biggest thing
    // on the glass), and the unit that used to own a whole row now sits INLINE behind the
    // digits. Between them those two changes bought the outcome-dot strip its row without
    // anything else moving.
    //
    // 0.9.2 made the clock bigger again, and paid for it out of leading rather than out of any
    // other row. Two changes, worth 42 px between them and costing 3:
    //   * the clock's band is FONT_NUMBER_MILD, not FONT_LARGE — ~66 px of digit against 41 —
    //     and it is fitted through the NUMBER ladder, so PAUSED (which is a word, and wider)
    //     still steps down into the text fonts and lands on FONT_LARGE exactly as before;
    //   * the GIANT's band is its INK height, not FONT_NUMBER_MEDIUM's line height. The 39 px
    //     difference is leading: air above and below the digits that nothing is drawn in. The
    //     rows below it move up by half of that and gain chord, and the stack as a whole is
    //     three pixels taller than it was.
    hidden function drawMainPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, true, foilArc);
        var hC = inkH(dc, MAIN_CLOCK_FONT);
        var hN = mainGiantBand(dc, mainGiantId(page));
        var hO = dc.getFontHeight(Graphics.FONT_LARGE);
        var hD = stripBandH(dc);
        var hK = dc.getFontHeight(Graphics.FONT_MEDIUM);

        drawStateRing(dc, c, foilArc);

        // row 0 — time of day, or PAUSED. This is the one layout whose top row sits exactly
        // where the pause banner wants to be, so it carries the state itself: a paused
        // session is more urgent than the time, and the swap costs no pixels.
        var paused = c.state == SessionController.STATE_PAUSED;
        // ... or the last verdict (EventFlash's afterglow), for 20 s after it landed: on
        // MAIN the strip IS this row, in the event's ink, so the clock gives way to it the
        // way it gives way to PAUSED. Letters need the text ladder, not the number one.
        var glow = !paused && EventFlash.stripActive(System.getTimer());
        var y = mainRowY(cy, hC, hN, hD, hO, hK, 0);
        if (glow) {
            var line = EventFlash.stripText(EventFlash.lastKind, EventFlash.lastTurnKind,
                EventFlash.lastValue);
            dc.setColor(EventFlash.baseColor(EventFlash.lastKind), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, fitFont(dc, TEXT_FONTS, PAUSED_FONT_IDX, line,
                rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[PAUSED_FONT_IDX]))), line, CV);
        } else {
            var top = paused ? PAUSED_TEXT : PageModel.clockString();
            dc.setColor(paused ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE,
                Graphics.COLOR_TRANSPARENT);
            // The word takes the text ladder from the rung that fits the clock's BAND: on
            // the fenix 5 Plus family FONT_LARGE's ink is taller than the clock font's band,
            // so PAUSED there steps down a rung and on every other glass it is FONT_LARGE as
            // before. The CLOCK is fitted against each candidate's own ink (fitByOwnInk),
            // because this row sits in the top arc where the box height is most of what
            // decides the chord. Shared with the layout test.
            dc.drawText(cx, y, paused
                ? fitFont(dc, TEXT_FONTS, textFontFrom(dc, hC), top,
                    rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[textFontFrom(dc, hC)])))
                : mainClockFont(dc, radius, y, cy), top, CV);
        }

        // row 1 — the giant, with its unit and caption inline behind the digits
        drawMainGiant(dc, c, page, cx, cy, radius, mainRowY(cy, hC, hN, hD, hO, hK, 1));

        // row 2 — every counted turn as one dot, oldest left. It sits DIRECTLY under the
        // giant, straddling the equator with it, because it is the widest thing on the page
        // and the equator is where the chord is widest: a dot strip pushed to the bottom arc
        // loses half its dots to the glass. The counts say how many; the strip says how they
        // arrived — three swims in a row is a different session from three swims in an hour,
        // and no count can tell them apart.
        y = mainRowY(cy, hC, hN, hD, hO, hK, 2);
        drawOutcomeStrip(dc, cx, y, rowBudget(radius, y - cy, hD), e.history);

        // row 3 — the outcome ladder as three counts. Colour AND position carry the verdict,
        // so it reads before the digits are in focus: green flew, orange touched, red swam.
        drawTally(dc, cx, mainRowY(cy, hC, hN, hD, hO, hK, 3), cy, radius, e.turns, "", 0);

        // row 4 — the dry run: how many turns since he last went in, and the session's best.
        drawStreakRow(dc, cx, mainRowY(cy, hC, hN, hD, hO, hK, 4), cy, radius, e.turns);
    }

    // The rung the clock is drawn at: decided once on the WORST CASE the row can be handed,
    // never on the live time, so a session's clock does not change size at 23:00. Shared with
    // the layout test. See MAIN_CLOCK_FONT for why this row has a ceiling it often cannot
    // reach.
    static function mainClockFont(dc as Dc, radius as Number, y as Number,
            cy as Number) as Graphics.FontType {
        return fitByOwnInk(dc, MAIN_CLOCK_WORST, MAIN_CLOCK_FROM, radius, y, cy);
    }

    // The MAIN giant: a catalog metric in the page's s1 slot, its value in the number ladder
    // and its unit + caption as two XTINY lines wedged in beside the digits, bottom-aligned on
    // the digits' own baseline. The unit used to be a whole row of its own; inline it costs
    // nothing vertically and reads as part of the same number.
    // The MAIN giant's slot: page 1's first cell, best 10 s when the rider emptied it.
    static function mainGiantId(page as Number) as Number {
        var id = PageModel.slotAt(page, 0);
        return id == PageModel.M_NONE ? PageModel.M_BEST_10S : id;   // a page 1 with no giant is not a page 1
    }

    // The MAIN giant's band: its digits' ink, or the two XTINY suffix lines beside them when
    // those are the taller box. On every glass since 0.9.2 the ink wins by a wide margin
    // (fenix 8: 115 px against 74). On the fenix 5 Plus family it does not — MEDIUM's ink is
    // 36 px and two XTINY lines are 52 — and a suffix block bottom-aligned on the digits'
    // baseline reached 16 px above the ink, into the clock row (0.9.13). The block that is
    // the taller box owns the band, and suffixLineY centres it there instead.
    static function mainGiantBand(dc as Dc, id as Number) as Number {
        var ink = inkH(dc, Graphics.FONT_NUMBER_MEDIUM);
        var lines = (PageModel.unitOf(id).equals("") ? 0 : 1)
            + (PageModel.caption(id).equals("") ? 0 : 1);
        var block = lines * dc.getFontHeight(Graphics.FONT_XTINY);
        return block > ink ? block : ink;
    }

    hidden function drawMainGiant(dc as Dc, c as SessionController, page as Number,
            cx as Number, cy as Number, radius as Number, y as Number) as Void {
        var id = mainGiantId(page);
        var v = PageModel.value(id, c);
        var unit = PageModel.unitOf(id);
        var cap = PageModel.caption(id);
        var sufW = giantSuffixWidth(dc, unit, cap);
        var f = fitGiant(dc, v, 2,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_NUMBER_MEDIUM)) - sufW);
        var wv = dc.getTextWidthInPixels(v, f);
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = cx - (wv + sufW) / 2;
        dc.setColor(PageModel.color(id, c), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, v, LV);
        x += wv + GLYPH_GAP;
        var lines = (unit.equals("") ? 0 : 1) + (cap.equals("") ? 0 : 1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (!unit.equals("")) {
            dc.drawText(x, suffixLineY(dc, y, f, 0, lines), Graphics.FONT_XTINY, unit, LV);
        }
        if (!cap.equals("")) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, suffixLineY(dc, y, f, 1, lines), Graphics.FONT_XTINY, cap, LV);
        }
    }

    // Width the inline suffix block takes from the giant's row budget: the wider of the two
    // XTINY lines, plus the gap that separates it from the digits. Shared with the layout test.
    static function giantSuffixWidth(dc as Dc, unit as String, cap as String) as Number {
        var wu = unit.equals("") ? 0 : dc.getTextWidthInPixels(unit, Graphics.FONT_XTINY);
        var wc = cap.equals("") ? 0 : dc.getTextWidthInPixels(cap, Graphics.FONT_XTINY);
        var w = wu > wc ? wu : wc;
        return w == 0 ? 0 : w + GLYPH_GAP;
    }

    // Ink centre of suffix line `line` (0 = unit, 1 = caption) of a `lines`-line block whose
    // bottom sits on the digits' baseline — approximated, as everywhere else in this file, by
    // the ink half-height below the row centre.
    //
    // Bottom-aligned on the baseline while the block is shorter than the digits; centred on
    // the row when it is the taller box (fenix 5 Plus, see mainGiantBand), so it never leaves
    // the band the row was stacked with.
    static function suffixLineY(dc as Dc, y as Number, f as Graphics.FontType, line as Number,
            lines as Number) as Number {
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var ink = inkH(dc, f);
        var block = lines * hT;
        var base = y + (block > ink ? block : ink) / 2 - hT / 2;
        return lines == 2 && line == 0 ? base - hT : base;
    }

    // Row centres for MAIN: 0 clock/state · 1 giant · 2 outcome dots · 3 outcome counts ·
    // 4 streak. Stacked from font heights only, like every other page, so the rows can never
    // overlap on any variant. Shared with the layout test.
    //
    // `hN` is the giant's INK height, not its line height (0.9.2): the giant is the only row
    // whose font is pinned at the top of its own ladder, so the leading around it is knowable
    // dead space rather than the safety margin it is everywhere else. The row below it is
    // stacked against the ink, which is what it visually sits under.
    static function mainRowY(cy as Number, hC as Number, hN as Number, hD as Number,
            hO as Number, hK as Number, row as Number) as Number {
        var y = cy - (hC + hN + hD + hO + hK) / 2;
        if (row == 0) { return y + hC / 2; }
        if (row == 1) { return y + hC + hN / 2; }
        if (row == 2) { return y + hC + hN + hD / 2; }
        if (row == 3) { return y + hC + hN + hD + hO / 2; }
        return y + hC + hN + hD + hO + hK / 2;
    }

    // "dry 7 / 12" — the live no-fall run beside the session's longest (docs/algorithms.md
    // "Turn streaks"). Neutral ink on purpose: a run of not-falling is not a verdict on any
    // one turn, so it must not borrow the outcome ladder's green.
    hidden function drawStreakRow(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, t as TurnDetector) as Void {
        var now = t.dryStreak.toString();
        var best = t.bestDryStreak.toString();
        var f = streakFont(dc, now, best,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_MEDIUM)), 1);
        drawStreakPair(dc, cx - streakWidth(dc, now, best, f) / 2, y, STREAK_CAPTION, now,
            best, f, true);
    }

    // One "<caption> now / best" group, drawn from its LEFT edge and returning the x it ended
    // at, so a row can carry two of them. `showNow` off draws the best alone, which is what a
    // post-save page wants: "the current run" stops meaning anything once the rider is ashore.
    function drawStreakPair(dc as Dc, x as Number, y as Number, caption as String,
            now as String, best as String, f as Graphics.FontType,
            showNow as Boolean) as Number {
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        // Every glyph in this row is white since 0.9.2 (the rider's call: grey text is not
        // text on the water). The caption and the separator are XTINY and the two numbers are
        // `f`, so SIZE is what separates the word from the values now — it was carrying most
        // of that job already, and it is the half that survives spray and low brightness.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, caption, LV);
        x += dc.getTextWidthInPixels(caption, Graphics.FONT_XTINY) + GLYPH_GAP;
        if (showNow) {
            dc.drawText(x, y, f, now, LV);
            x += dc.getTextWidthInPixels(now, f);
            dc.drawText(x, y, Graphics.FONT_XTINY, STREAK_SEP, LV);
            x += dc.getTextWidthInPixels(STREAK_SEP, Graphics.FONT_XTINY);
        }
        dc.drawText(x, y, f, best, LV);
        return x + dc.getTextWidthInPixels(best, f);
    }

    // Width of that block: an XTINY caption and separator around two numbers in `f`. Shared
    // with the layout test, which measures it at "99 / 99".
    static function streakWidth(dc as Dc, now as String, best as String,
            f as Graphics.FontType) as Number {
        return pairWidth(dc, STREAK_CAPTION, now, best, f, true);
    }

    static function pairWidth(dc as Dc, caption as String, now as String, best as String,
            f as Graphics.FontType, showNow as Boolean) as Number {
        var w = dc.getTextWidthInPixels(caption, Graphics.FONT_XTINY) + GLYPH_GAP
            + dc.getTextWidthInPixels(best, f);
        if (showNow) {
            w += dc.getTextWidthInPixels(now, f)
                + dc.getTextWidthInPixels(STREAK_SEP, Graphics.FONT_XTINY);
        }
        return w;
    }

    // The numbers step down from TEXT_FONTS[from] — the row's reserved band — and no further
    // than FONT_SMALL, which is the floor for anything carrying a digit.
    static function streakFont(dc as Dc, now as String, best as String,
            budget as Number, from as Number) as Graphics.FontType {
        for (var i = from; i < TALLY_FLOOR; i++) {
            if (streakWidth(dc, now, best, TEXT_FONTS[i]) <= budget) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // ---- HERO: one giant number, its unit line, and up to two rows under it ----
    // A fully configurable page: slot 1 is the giant, slots 2-3 the rows under it. The
    // foil-state ring is part of the hero style: on the water the colour, not the number, is
    // what you read first.
    hidden function drawHeroPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, true, foilArc);
        var hN = inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);
        var hM = dc.getFontHeight(Graphics.FONT_MEDIUM);

        drawStateRing(dc, c, foilArc);

        // sub-rows compact upward, so leaving slot 2 empty does not leave a hole
        var sub1 = PageModel.slotAt(page, 1);
        var sub2 = PageModel.slotAt(page, 2);
        if (sub1 == PageModel.M_NONE) {
            sub1 = sub2;
            sub2 = PageModel.M_NONE;
        }
        var nSub = (sub1 != PageModel.M_NONE ? 1 : 0) + (sub2 != PageModel.M_NONE ? 1 : 0);

        var giant = PageModel.slotAt(page, 0);
        var gv = PageModel.value(giant, c);
        var y = heroRowY(cy, hN, hT, hL, hM, 0, nSub);
        var gFont = fitFont(dc, NUMBER_FONTS, 0, gv,
            rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_NUMBER_THAI_HOT)));
        dc.setColor(PageModel.color(giant, c), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, gFont, gv, CV);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, heroRowY(cy, hN, hT, hL, hM, 1, nSub), Graphics.FONT_XTINY,
            PageModel.label(giant), CV);
        if (sub1 != PageModel.M_NONE) {
            drawFittedRow(dc, cx, cy, radius, heroRowY(cy, hN, hT, hL, hM, 2, nSub), 0,
                PageModel.value(sub1, c) + PageModel.suffix(sub1), PageModel.color(sub1, c));
        }
        if (sub2 != PageModel.M_NONE) {
            drawFittedRow(dc, cx, cy, radius, heroRowY(cy, hN, hT, hL, hM, 3, nSub), 1,
                PageModel.value(sub2, c) + PageModel.suffix(sub2), PageModel.color(sub2, c));
        }
    }

    // A centred text row that steps down the text ladder (starting at `from`) until it fits.
    hidden function drawFittedRow(dc as Dc, cx as Number, cy as Number, radius as Number,
            y as Number, from as Number, text as String, col as Number) as Void {
        var font = fitFont(dc, TEXT_FONTS, from, text,
            rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[from])));
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, font, text, CV);
    }

    // Row centres for HERO: 0 = giant number, 1 = unit line, 2 = first sub-row (LARGE),
    // 3 = second sub-row (MEDIUM). The block is centred on the rows it actually has, and the
    // giant's BAND is always the biggest number font's INK height whatever font lands in it —
    // so the stack is deterministic and the fit can shrink the number without moving anything.
    //
    // Ink, not line height, since 0.9.2. THAI_HOT's line is 210 px on a 454 px glass and its
    // digits are 157 of them; the 53 px difference is leading, and it was being spent twice —
    // once above the giant, where the top of the glass is empty anyway, and once below it,
    // where it pushed the two sub-rows 26 px deeper into the narrowing chord than the digits
    // they sit under. The giant does not move (the block is centred on its total); the unit
    // line and both sub-rows come up and get their width back.
    static function heroRowY(cy as Number, hN as Number, hT as Number, hL as Number,
            hM as Number, row as Number, nSub as Number) as Number {
        var total = hN + hT + (nSub >= 1 ? hL : 0) + (nSub >= 2 ? hM : 0);
        var y = cy - total / 2;
        if (row == 0) {
            return y + hN / 2;
        }
        if (row == 1) {
            return y + hN + hT / 2;
        }
        if (row == 2) {
            return y + hN + hT + hL / 2;
        }
        return y + hN + hT + hL + hM / 2;
    }

    // ---- BIG: the LARGE set's one layout ----
    // See the constants above for why this is not simply a HERO page with the rows left out.
    hidden function drawBigPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, foilArc);
        var id = bigId(page);
        // The three TURN screens carry a row between the giant and the word: the session's
        // own ladder on the turns screen, the kind's on the two kind screens. A count of
        // jibes without a verdict on them is the one number on this set that says nothing on
        // its own. The other two screens (speed, foil share) are giant + word and nothing.
        var rows = bigHasRow(id) ? 3 : 2;
        var v = PageModel.value(id, c);
        var f = bigGiantFont(dc, v, radius, rows);
        var hN = bigBand(dc, f);
        var hW = dc.getFontHeight(TEXT_FONTS[BIG_WORD_FONT]);
        var hK = rows == 3 ? dc.getFontHeight(TEXT_FONTS[BIG_TALLY_FROM]) : 0;

        // row 0 — the giant
        var y = bigRowY(cy, hN, hK, hW, 0);
        dc.setColor(PageModel.color(id, c), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, f, v, CV);

        // row 1 — the outcome ladder, session-wide or for this kind. Same renderer and same
        // four inks as the Turns and Tacks & jibes pages: one vocabulary, one function.
        if (rows == 3) {
            drawLadderRow(dc, cx, bigRowY(cy, hN, hK, hW, 1), cy, radius,
                bigLadder(id, c.engine.turns), BIG_TALLY_FROM);
        }

        // row 2 — the word, with its unit in it (PageModel.bigWord). It is LAST since 0.9.18:
        // a label is found once and a number is read every glance, so the number takes the
        // top of the page and the middle of the glass and the word takes the bottom arc.
        var word = PageModel.bigWord(id);
        y = bigRowY(cy, hN, hK, hW, 2);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fitFont(dc, TEXT_FONTS, BIG_WORD_FONT, word,
            rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[BIG_WORD_FONT]))), word, CV);
    }

    // Does this metric's large screen carry an outcome row? The three turn screens do.
    static function bigHasRow(id as Number) as Boolean {
        return id == PageModel.M_TURNS || PageModel.isKind(id);
    }

    // The four counts that row draws, as [clean, flew, touch, fell]. A negative clean means
    // "this ladder has no star" — the session's own does (its clean JIBES), the tack screen
    // does not. Fills the shared scratch rather than allocating: this is a per-frame call.
    hidden function bigLadder(id as Number, t as TurnDetector) as Array<Number> {
        if (PageModel.isKind(id)) {
            return ladderOf(PageModel.kindClean(id, t), PageModel.kindFlew(id, t),
                PageModel.kindTouch(id, t), PageModel.kindFell(id, t));
        }
        return ladderOf(t.cleanJibeCount, t.flewCount, t.touchdownCount, t.fellCount);
    }

    // The BIG giant's slot, with live speed as the answer to an emptied one — the same
    // never-a-blank-page rule mainGiantId keeps.
    static function bigId(page as Number) as Number {
        var id = PageModel.slotAt(page, 0);
        return id == PageModel.M_NONE ? PageModel.M_SPEED : id;
    }

    // Row centres for BIG: 0 giant · 1 the outcome row, whose band is 0 on the two screens
    // that do not carry it · 2 word. `hN` is the giant's BAND — its ink on the bitmap ladder,
    // its whole line on a vector face (see bigBand). Shared with the layout test.
    static function bigRowY(cy as Number, hN as Number, hK as Number, hW as Number,
            row as Number) as Number {
        var y = cy - (hN + hK + hW) / 2;
        if (row == 0) { return y + hN / 2; }
        if (row == 1) { return y + hN + hK / 2; }
        return y + hN + hK + hW / 2;
    }

    // The band a giant font reserves. The bitmap ladder is stacked on its INK, as every giant
    // on this watch has been since 0.9.2; a VECTOR face is stacked on its whole LINE, because
    // nothing here knows that face's ascent and a row with one job can afford the leading —
    // the same trade LockView.codeFont makes for the invite code. Shared with the layout test.
    static function bigBand(dc as Dc, f as Graphics.FontType) as Number {
        return isLadderFont(f) ? inkH(dc, f) : dc.getFontHeight(f);
    }

    // Is `f` one of the firmware's bitmap fonts this file knows the metrics of?
    static function isLadderFont(f as Graphics.FontType) as Boolean {
        if (isNumberFont(f)) {
            return true;
        }
        for (var i = 0; i < TEXT_FONTS.size(); i++) {
            if (f == TEXT_FONTS[i]) {
                return true;
            }
        }
        return false;
    }

    // The giant's font: the probed vector face where this device has one that beats the
    // bitmap ladder AND this value fits it, the ladder otherwise. `rows` is the stack shape,
    // 2 or 3 — see the VEC_ constants for why the probe is per shape and cached.
    //
    // The per-frame cost is one width lookup: the probe has already answered the hard
    // questions (which face, what size, does it cover the alphabet) once.
    static function bigGiantFont(dc as Dc, v as String, radius as Number,
            rows as Number) as Graphics.FontType {
        var cy = dc.getHeight() / 2;
        var hW = dc.getFontHeight(TEXT_FONTS[BIG_WORD_FONT]);
        var hK = rows == 3 ? dc.getFontHeight(TEXT_FONTS[BIG_TALLY_FROM]) : 0;
        var hN = inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
        var yb = bigRowY(cy, hN, hK, hW, 0);
        var bitmap = fitGiant(dc, v, 0, rowBudget(radius, yb - cy, hN));
        // A value carrying a LETTER never walks a digit ladder: the number fonts have no
        // letters and a digits-cut vector face has none either.
        if (hasLetters(v)) {
            return bitmap;
        }
        var vec = vecGiant(dc, radius, rows);
        if (vec == null) {
            return bitmap;
        }
        var f = vec as Graphics.FontType;
        var band = bigBand(dc, f);
        var y = bigRowY(cy, band, hK, hW, 0);
        var w = dc.getTextWidthInPixels(v, f);
        // Two conditions, and the second is the one that matters. The face has to FIT this
        // value's own chord, and it has to draw it WIDER than the bitmap ladder would — which
        // is not implied by being taller, because these faces are condensed: a vector cut that
        // clears THAI_HOT's ink height can still set "99.9" narrower than THAI_HOT does, and
        // taking it would shrink the number this whole round exists to grow.
        return w <= rowBudget(radius, y - cy, band)
            && w >= dc.getTextWidthInPixels(v, bitmap) ? f : bitmap;
    }

    // The probe. Runs at most once per app run, fills `_vecGiant` for both stack shapes, and
    // answers null for every device and every shape where the bitmap ladder already wins.
    static function vecGiant(dc as Dc, radius as Number, rows as Number) as Graphics.FontType? {
        if (!_vecProbed) {
            _vecProbed = true;
            if (Graphics has :getVectorFont) {
                _vecGiant[0] = probeVecGiant(dc, radius, 2, VEC_WORST_2ROW);
                _vecGiant[1] = probeVecGiant(dc, radius, 3, VEC_WORST_3ROW);
            }
        }
        return _vecGiant[rows == 3 ? 1 : 0];
    }

    // Largest vector face that draws `worst` inside the chord its OWN stack puts the giant in,
    // and that draws it BIGGER than the bitmap ladder would — taller AND wider, both measured
    // against the font `fitGiant` would actually have chosen for the same string.
    //
    // Width is the binding half and the reason this is not LockView's test verbatim. These
    // faces are condensed: a cut that clears FONT_NUMBER_THAI_HOT's ink height can still set
    // "100%" narrower than THAI_HOT does, and a number that is taller and thinner is not the
    // bigger number Jan asked for — it is the same number rotated into a shape that reads
    // worse in spray.
    //
    // Null when nothing qualifies, which is the answer on every CIQ 3.x product (the `has`
    // guard above never lets them in) and on the narrow glasses, where the widest vector that
    // fits is smaller than the ladder's top rung. Null is not a failure; it is the floor
    // holding, and the page is then exactly the page that shipped.
    static function probeVecGiant(dc as Dc, radius as Number, rows as Number,
            worst as String) as Graphics.FontType? {
        var cy = dc.getHeight() / 2;
        var hW = dc.getFontHeight(TEXT_FONTS[BIG_WORD_FONT]);
        var hK = rows == 3 ? dc.getFontHeight(TEXT_FONTS[BIG_TALLY_FROM]) : 0;
        var hN = inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
        var yb = bigRowY(cy, hN, hK, hW, 0);
        var bitmap = fitGiant(dc, worst, 0, rowBudget(radius, yb - cy, hN));
        var floorH = inkH(dc, bitmap);
        var floorW = dc.getTextWidthInPixels(worst, bitmap);
        var size = dc.getHeight() * VEC_MAX_PCT / 100;
        while (size > floorH) {
            for (var i = 0; i < VEC_FACES.size(); i++) {
                var vf = Graphics.getVectorFont({:face => VEC_FACES[i], :size => size});
                if (vf == null) {
                    continue;               // this device does not have that face
                }
                var h = dc.getFontHeight(vf);
                if (h <= floorH) {
                    continue;               // the ladder already beats this face at this size
                }
                if (!coversText(dc, vf, VEC_ALPHABET)) {
                    continue;               // a digits-only cut — see VEC_FACES
                }
                var w = dc.getTextWidthInPixels(worst, vf);
                if (w > floorW && w <= rowBudget(radius, bigRowY(cy, h, hK, hW, 0) - cy, h)) {
                    return vf;
                }
            }
            size -= VEC_STEP;
        }
        return null;
    }

    // Can `f` draw every character of `text`? A font a device has no glyph for measures that
    // character at zero width, and zero width sails through every width test there is — so a
    // "56%" drawn in a digits-only face would come out "56" and pass the fitter on the way.
    // Asked one character at a time, exactly as LockView.coversAlphabet asks it.
    static function coversText(dc as Dc, f as Graphics.FontType, text as String) as Boolean {
        for (var i = 0; i < text.length(); i++) {
            if (dc.getTextWidthInPixels(text.substring(i, i + 1), f) <= 0) {
                return false;
            }
        }
        return true;
    }

    // ---- FOIL: the session's foil numbers as a titled 3x2 table ----
    //
    // It replaced the Session grid, and what it dropped is as much of the point as what it
    // kept. The grid showed the foil shares, the foil time, the longest flight, the session
    // DISTANCE and the flight COUNT — two of which are not foil numbers at all. The odometer
    // total and the flight count are still catalog metrics for any other page's slots (and the
    // count also has its own summary screen); this page is now one question asked twice, in
    // minutes and in kilometres:
    //
    //          foil
    //      56%     61%          how much of it was flown
    //  tot 63:24   14.1         how much there was of it
    //  max  7:04    2.2         and the best single flight of it
    //      time     km
    //
    // The column headers are said ONCE and all three rows inherit them — that is what makes it
    // a table rather than three pairs of captioned cells, and it buys two rows of glass back
    // from captions that would have repeated the same two words three times.
    //
    // They sit UNDER the matrix since 0.9.2, and the block is no longer lifted. Both changes
    // are the same change: the header row used to be the second row from the top, which on a
    // lifted block is the narrowest row on the page, and it pushed all three VALUE rows further
    // from the equator where the chord is widest. Below the matrix it costs the numbers
    // nothing — a two-word label row is the cheapest thing to put where the glass is narrow —
    // and the three value rows land on -1/0/+1 bands around the centre. Measured on a 454 px
    // glass: the table's usable half-width goes 185 -> 190 px, which with the tighter row keys
    // is the difference between FONT_MEDIUM and FONT_LARGE for all six numbers.
    //
    // The distance column is ON-FOIL distance throughout (FlightDetector.foilDistM /
    // longestM), never the odometer: a "km" column whose top cell is a foil SHARE and whose
    // middle cell were the whole session would be two different denominators in one column.
    //
    // The bezel arc stays, and stays keyed to the TIME share: an arc is a sweep, a sweep can
    // only be one number, and the top-left cell is that number.
    // Not `hidden`: the post-save Foil page is this page with the session's final values in
    // it (SummaryView.drawFoil), the same way the Turns and Story pages call straight into
    // drawTurnsBody and drawTimelinePage.
    function drawFoilPage(dc as Dc, c as SessionController, foilArc as Boolean) as Void {
        var d = c.engine.detector;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, foilArc);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hV = dc.getFontHeight(Graphics.FONT_LARGE);
        var half = foilTableHalf(dc, radius, cy, hT, hV);
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        var tt = PageModel.fmtTime(d.foilTimeS);
        var td = foilKm(d.foilDistM);
        var mt = PageModel.fmtTime(d.longestS);
        var md = foilKm(d.longestM);
        var keys = foilKeys(dc, half, foilWidest(dc, [tt, td, mt, md]));
        var col = foilColumns(cx, half, foilKeyBlock(dc, keys));

        // row 0 — the page's name
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, foilRowY(cy, hT, hV, 0), Graphics.FONT_XTINY, FOIL_TITLE, CV);

        // row 1 — the two shares, teal, exactly as the pair band drew them: a PHASE tint, not
        // the outcome ladder's green (docs/presentation.md)
        var pt = PageModel.value(PageModel.M_FOIL_PCT, c);
        var pd = PageModel.value(PageModel.M_FOIL_DIST_PCT, c);
        drawFoilRow(dc, col, foilRowY(cy, hT, hV, 1), "", pt, pd,
            foilFont(dc, [pt, pd], col[3]), Ink.phaseFlying(), LV);

        // rows 2 and 3 — the totals and the bests, white, and in ONE font: they are the two
        // halves of the same table, and a row that shrank on its own would read as a different
        // kind of number rather than as the same number a session later.
        var f = foilFont(dc, [tt, td, mt, md], col[3]);
        drawFoilRow(dc, col, foilRowY(cy, hT, hV, 2), keys[0], tt, td, f,
            Graphics.COLOR_WHITE, LV);
        drawFoilRow(dc, col, foilRowY(cy, hT, hV, 3), keys[1], mt, md, f,
            Graphics.COLOR_WHITE, LV);

        // row 4 — the column headers, under the numbers they name
        var yh = foilRowY(cy, hT, hV, 4);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col[1], yh, Graphics.FONT_XTINY, FOIL_COL_TIME, CV);
        dc.drawText(col[2], yh, Graphics.FONT_XTINY, FOIL_COL_DIST, CV);
    }

    // One table row: an optional grey key at the block's left edge, then the two values on
    // their fixed columns. The key is left-justified and the values centred, which is what
    // keeps the columns lined up down the page whatever the keys measure.
    hidden function drawFoilRow(dc as Dc, col as Array<Number>, y as Number, key as String,
            a as String, b as String, f as Graphics.FontType, ink as Number,
            LV as Number) as Void {
        if (!key.equals("")) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(col[0], y, Graphics.FONT_XTINY, key, LV);
        }
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col[1], y, f, a, CV);
        dc.drawText(col[2], y, f, b, CV);
    }

    // Metres as the kilometres the column header promises. One decimal, like every other
    // distance on the watch.
    static function foilKm(metres as Float) as String {
        return (metres / 1000.0).format("%.1f");
    }

    // Row centres: 0 title · 1 shares · 2 totals · 3 bests · 4 column headers. Stacked from
    // font heights only, so no two rows can ever touch. `hV` is the band a value row reserves
    // — always FONT_LARGE's line height, whatever font the fit lands in, so shrinking a number
    // moves nothing.
    //
    // The block is CENTRED, with no bias of any kind: with the header row moved to the bottom
    // the three value rows are symmetric about the equator, which is both the widest they can
    // be and the only arrangement in which none of them is wider than the others (a table whose
    // middle row could hold a bigger font than its neighbours is still limited by its
    // neighbours). Shared with the layout test.
    static function foilRowY(cy as Number, hT as Number, hV as Number,
            row as Number) as Number {
        var y = cy - (2 * hT + 3 * hV) / 2;
        if (row == 0) { return y + hT / 2; }
        if (row == 4) { return y + hT + 3 * hV + hT / 2; }
        return y + hT + (row - 1) * hV + hV / 2;
    }

    // Half the width the TABLE may use: the narrowest of the three VALUE rows, each measured
    // at its own depth. One number for all of them, because a table whose columns move from
    // row to row is not a table.
    //
    // The title and header rows are deliberately NOT in this minimum. They sit outside the
    // matrix, at the two shallowest and deepest depths on the page, and all they carry is
    // three short words centred on columns already inside their own chords; letting them set
    // the width would hand the whole table the budget of its emptiest row. The layout test
    // measures them where they are actually drawn instead.
    static function foilTableHalf(dc as Dc, radius as Number, cy as Number, hT as Number,
            hV as Number) as Number {
        var h = 0;
        for (var row = 1; row <= 3; row++) {
            var k = chordHalf(radius, foilRowY(cy, hT, hV, row) - cy,
                inkH(dc, Graphics.FONT_LARGE));
            if (row == 1 || k < h) {
                h = k;
            }
        }
        return h;
    }

    // What one value column is wide, once the key column and the gutter are paid for.
    static function foilColWidth(half as Number, keyW as Number) as Number {
        return (2 * half - keyW - FOIL_KEY_GAP - CELL_GUTTER) / 2;
    }

    // The table's fixed geometry: [key LEFT edge, column 1 centre, column 2 centre, column
    // width]. The whole block — key column included — is centred on the glass, so the keys do
    // not push the numbers off centre; they are part of what is centred.
    static function foilColumns(cx as Number, half as Number,
            keyW as Number) as Array<Number> {
        var w = foilColWidth(half, keyW);
        var x0 = cx - half;
        var c1 = x0 + keyW + FOIL_KEY_GAP + w / 2;
        return [x0, c1, c1 + w + CELL_GUTTER, w];
    }

    // The key column's width, and with it which pair of words the page uses. ONE test since
    // 0.9.18, and it is the FLOOR: the long words are used unless they would push the worst
    // case the page can be handed ("199:59") below TEXT_FONTS[FOIL_FLOOR], the readability
    // floor every number on this watch keeps.
    //
    // There was a second test until this round — the RUNG. Above the floor, the long word
    // gave way the moment the short one would buy the matrix a whole font size: on a 454 px
    // glass "total" leaves the columns 150 px and "tot" leaves them 163, and a "63:24" in
    // FONT_LARGE is 151, so five letters cost every number on the page a rung. Jan's layout
    // review of 21 September 2026 reversed that trade for this one word. "tot" is an
    // abbreviation a rider has to expand, on the most-read row of the table, and the rung it
    // was buying is one step of a ladder that has four — a smaller number you can name beats a
    // bigger one you have to work out. The floor is what keeps "smaller" honest.
    //
    // `wide` is kept in the signature: the layout suite measures the widest value the matrix
    // is actually about to print against the columns the keys leave it.
    //
    // Shared with the layout test.
    static function foilKeyWidth(dc as Dc, half as Number, wide as String) as Number {
        return foilKeyBlock(dc, foilKeys(dc, half, wide));
    }

    static function foilKeys(dc as Dc, half as Number, wide as String) as Array<String> {
        var long = [FOIL_KEY_TOTAL, FOIL_KEY_MAX];
        var wLong = foilColWidth(half, foilKeyBlock(dc, long));
        var worst = dc.getTextWidthInPixels(PageModel.worstValue(PageModel.M_FOIL_TIME),
            TEXT_FONTS[FOIL_FLOOR]);
        return wLong < worst ? [FOIL_KEY_TOTAL_TIGHT, FOIL_KEY_MAX] : long;
    }

    // The widest of a set of values at the top of the value ladder — i.e. the one that decides
    // what rung the whole set lands on, since a table is drawn in one font.
    static function foilWidest(dc as Dc, vals as Array<String>) as String {
        var wide = vals[0];
        var w = dc.getTextWidthInPixels(wide, TEXT_FONTS[0]);
        for (var i = 1; i < vals.size(); i++) {
            var k = dc.getTextWidthInPixels(vals[i], TEXT_FONTS[0]);
            if (k > w) {
                w = k;
                wide = vals[i];
            }
        }
        return wide;
    }

    static function foilKeyBlock(dc as Dc, keys as Array<String>) as Number {
        var a = dc.getTextWidthInPixels(keys[0], Graphics.FONT_XTINY);
        var b = dc.getTextWidthInPixels(keys[1], Graphics.FONT_XTINY);
        return a > b ? a : b;
    }

    // The largest text font every one of `vals` fits its column in, floored at FONT_SMALL.
    // One font for the whole set: a table's column is one column.
    static function foilFont(dc as Dc, vals as Array<String>,
            colW as Number) as Graphics.FontType {
        for (var i = 0; i < FOIL_FLOOR; i++) {
            var fits = true;
            for (var j = 0; j < vals.size(); j++) {
                if (dc.getTextWidthInPixels(vals[j], TEXT_FONTS[i]) > colW) {
                    fits = false;
                }
            }
            if (fits) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[FOIL_FLOOR];
    }

    // ---- GRID4: optional giant number on top, then a 2x2 of label/value cells ----
    hidden function drawGridPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, foilArc);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hL = dc.getFontHeight(Graphics.FONT_LARGE);

        var giant = PageModel.slotAt(page, 0);
        var hasGiant = giant != PageModel.M_NONE;
        var partner = hasGiant ? PageModel.bandPartner(giant) : PageModel.M_NONE;
        var hG = giantBand(dc, partner != PageModel.M_NONE);
        if (hasGiant) {
            var bias = gridBias(dc);
            var yg = gridRowY(cy, hG, hT, hL, 0, hasGiant, bias);
            if (partner != PageModel.M_NONE) {
                drawPairBand(dc, c, cx, cy, radius, yg, hG, giant, partner);
            } else {
                var gv = PageModel.value(giant, c);
                var gFont = fitGiant(dc, gv, 3,
                    rowBudget(radius, yg - cy, inkH(dc, Graphics.FONT_NUMBER_MILD)));
                dc.setColor(PageModel.color(giant, c), Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, yg, gFont, gv, CV);
            }
        }
        var rowBias = gridBias(dc);
        drawCellRow(dc, c, cx, cy, radius, gridRowY(cy, hG, hT, hL, 1, hasGiant, rowBias),
            PageModel.slotAt(page, 1), PageModel.slotAt(page, 2), false);
        drawCellRow(dc, c, cx, cy, radius, gridRowY(cy, hG, hT, hL, 2, hasGiant, rowBias),
            PageModel.slotAt(page, 3), PageModel.slotAt(page, 4), false);
    }

    // ---- the paired top band ----
    //
    // The GRID4 giant band draws TWO numbers whenever the giant slot holds a metric that has a
    // partner (PageModel.bandPartner) — on the shipped Session page, the foil TIME share and
    // the foil DISTANCE share. A rider reading "56 %" alone hears "and the other 44 % I was
    // sitting there"; the distance share (61 %) says how much of the water he actually crossed
    // flying, and neither number means much without the other.
    //
    // It moves nothing on any glass that can spare the room. The band is the height the single
    // giant already reserved (hG, one FONT_NUMBER_MILD line — see giantBand, which lends it one
    // more pixel on the two Forerunners whose MILD line is too short for the floor font and
    // leaves every other watch untouched), the caption lives in that band's own SLACK, and
    // the two halves sit on the same two columns the 2x2 below them uses — so the page reads
    // as three rows of two, not as a giant with a grid under it. The slack is what picks the
    // font: a caption plus MILD's ink is taller than the band, so the pair steps one rung down
    // the ladder, which is also the rung two "100 %" need to share a chord that was sized for
    // one number. Never below FONT_MEDIUM: a value in a label font is not a value.
    //
    // The bezel arc is untouched and still keyed to foil TIME %: the arc is a sweep, and a
    // sweep can only be one number. The left half of the band is that number.
    hidden function drawPairBand(dc as Dc, c as SessionController, cx as Number, cy as Number,
            radius as Number, y as Number, band as Number, left as Number,
            right as Number) as Void {
        var lv = PageModel.value(left, c);
        var rv = PageModel.value(right, c);
        var lc = PageModel.bandCaption(left);
        var rc = PageModel.bandCaption(right);
        var f = pairFont(dc, lv, lc, rv, rc, band, radius, y, cy);
        var dx = pairColumnFor(dc, f, radius, y, cy, [lv, lc, rv, rc]);
        drawPairHalf(dc, cx - dx, y, lv, lc, f, PageModel.color(left, c));
        drawPairHalf(dc, cx + dx, y, rv, rc, f, PageModel.color(right, c));
    }

    // The band's two column centres: the SAME split the 2x2 below uses, taken at the digits'
    // own depth. Two things fall out of reusing cellColumns here, and both are why the band is
    // not simply two numbers centred as one block: the halves sit as far apart as their chord
    // allows, so the gap between them GROWS when the numbers are short (which is every real
    // session — "56%" and "61%" end up 46 px apart on a 454 px glass where a centred block
    // would leave 17), and the top row lines up with the grid under it instead of huddling.
    static function pairColumn(dc as Dc, f as Graphics.FontType, radius as Number,
            y as Number, cy as Number) as Number {
        return cellColumns(radius, pairRowY(dc, y, f, 1) - cy, inkH(dc, f))[0];
    }

    // One half of that band, centred on `x`: the word above, the number below, the pair of them
    // centred in the band. Ink heights, not line heights, because what has to fit is the band.
    hidden function drawPairHalf(dc as Dc, x as Number, y as Number, v as String,
            cap as String, f as Graphics.FontType, col as Number) as Void {
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var ink = inkH(dc, f);
        var top = y - (hT + ink) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, top + hT / 2, Graphics.FONT_XTINY, cap, CV);
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, top + hT + ink / 2, f, v, CV);
    }

    // Ink centre of each of those two rows, 0 = caption, 1 = value. Shared with the layout
    // test, which measures both boxes against the chord at their own depth.
    static function pairRowY(dc as Dc, y as Number, f as Graphics.FontType,
            row as Number) as Number {
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var ink = inkH(dc, f);
        var top = y - (hT + ink) / 2;
        return row == 0 ? top + hT / 2 : top + hT + ink / 2;
    }

    // A half is as wide as its widest line — the number, in practice, since the captions are
    // one XTINY word.
    static function pairHalfWidth(dc as Dc, v as String, cap as String,
            f as Graphics.FontType) as Number {
        var wv = dc.getTextWidthInPixels(v, f);
        var wc = dc.getTextWidthInPixels(cap, Graphics.FONT_XTINY);
        return wv > wc ? wv : wc;
    }

    // What the block is TALL: the caption's line plus the number's ink. Must fit the band the
    // single giant reserved, or the pair would push into the 2x2 below it.
    static function pairBandHeight(dc as Dc, f as Graphics.FontType) as Number {
        return dc.getFontHeight(Graphics.FONT_XTINY) + inkH(dc, f);
    }

    // How tall the GRID4 giant row is. One FONT_NUMBER_MILD line, which is what a single giant
    // number has always reserved and what the 2x2 below is positioned against — EXCEPT on a
    // glass where that line is too short to hold the pair band at its floor font, in which case
    // the band takes the pixels it needs instead of dropping a value into a label font.
    //
    // Only the Forerunner 255/955 have ever asked. Their FONT_NUMBER_MILD is 45 px on the same
    // 260 px glass where the fenix 8 Solar's is 58 — a caption (19) plus FONT_MEDIUM's ink (27)
    // is 46, one pixel over. So the page grows by that one pixel there and by nothing anywhere
    // else, which is a better trade than a 32 px "value" a rider cannot read in spray.
    static function giantBand(dc as Dc, paired as Boolean) as Number {
        var h = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
        if (!paired) {
            return h;
        }
        var need = pairBandHeight(dc, PAIR_FONTS[PAIR_FLOOR]);
        return need > h ? need : h;
    }

    // Does font `f` hold the whole block? Three constraints, and every one of them has bitten:
    // the block must fit the BAND's height (or the pair shoves the 2x2 off the glass); each
    // half must fit its own COLUMN, measured at the digits' own depth; and each caption must
    // still be inside the glass a value-height higher up, where the chord is narrower — on a
    // 454 px glass the caption row has ~70 px less of it, so a word that fits beside the digits
    // does not automatically fit above them.
    //
    // The four strings travel as ONE array — `[leftValue, leftCaption, rightValue,
    // rightCaption]` — rather than four parameters, because a Monkey C function may take at
    // most **nine** arguments on CIQ 3.x devices and the spelled-out form was exactly ten.
    // Nothing else in the app is pinned to CIQ 5.x, so this one signature was the whole
    // portability cost. `PAIR_LV`/`PAIR_LC`/`PAIR_RV`/`PAIR_RC` name the slots.
    static function pairFits(dc as Dc, texts as Array<String>, f as Graphics.FontType,
            band as Number, radius as Number, y as Number, cy as Number) as Boolean {
        if (pairBandHeight(dc, f) > band) {
            return false;
        }
        var col = cellColumns(radius, pairRowY(dc, y, f, 1) - cy, inkH(dc, f));
        var wMax = 2 * col[1];
        if (pairHalfWidth(dc, texts[PAIR_LV], texts[PAIR_LC], f) > wMax
                || pairHalfWidth(dc, texts[PAIR_RV], texts[PAIR_RC], f) > wMax) {
            return false;
        }
        // The halves sit at ±dx: the grid's own column where the captions allow it, pulled
        // inward where they do not (pairColumnFor). What is left to check is that the two
        // halves neither cross the centre line nor leave the glass at the digits' depth.
        var dx = pairColumnFor(dc, f, radius, y, cy, texts);
        var halfL = pairHalfWidth(dc, texts[PAIR_LV], texts[PAIR_LC], f);
        var halfR = pairHalfWidth(dc, texts[PAIR_RV], texts[PAIR_RC], f);
        var halfMax = halfL > halfR ? halfL : halfR;
        var valHalf = chordHalf(radius, pairRowY(dc, y, f, 1) - cy, inkH(dc, f));
        // The two halves keep the grid's own gutter between them (the layout test's rule
        // since 0.9.11; the fitter asked only for a pixel, and on the fenix 5 Plus with
        // 0.9.13's taller ink the caption row pulled the halves in until they touched).
        return dx - halfMax / 2 >= CELL_GUTTER / 2 && dx + halfMax / 2 <= valHalf;
    }

    // Where the two halves sit, given what is in them: the 2x2's own column (pairColumn) —
    // UNLESS a caption would run off the glass there. The caption row is the higher, narrower
    // one, and on a font set whose FONT_XTINY is as tall as TINY (the fenix 5 Plus: 26 px, where
    // every other watch draws 19) "foil time" at the grid's column reaches 5 px past the chord.
    // Then the halves move inward to the widest column the captions allow; on every other glass
    // the caption limit is looser than the grid's column and nothing moves.
    static function pairColumnFor(dc as Dc, f as Graphics.FontType, radius as Number,
            y as Number, cy as Number, texts as Array<String>) as Number {
        var dx = pairColumn(dc, f, radius, y, cy);
        var wl = dc.getTextWidthInPixels(texts[PAIR_LC], Graphics.FONT_XTINY);
        var wr = dc.getTextWidthInPixels(texts[PAIR_RC], Graphics.FONT_XTINY);
        var capW = wl > wr ? wl : wr;
        var capHalf = chordHalf(radius, pairRowY(dc, y, f, 0) - cy,
            inkH(dc, Graphics.FONT_XTINY));
        var need = capHalf - capW / 2;
        return need < dx ? need : dx;
    }

    // The band's own ladder: the single giant's font, then the two TEXT rungs a value may use.
    // The floor is FONT_MEDIUM, the readability floor for a number on this app — below it the
    // band would be lying about being the top of the page.
    static function pairFont(dc as Dc, lv as String, lc as String, rv as String, rc as String,
            band as Number, radius as Number, y as Number, cy as Number) as Graphics.FontType {
        var texts = [lv, lc, rv, rc];
        for (var i = 0; i < PAIR_FLOOR; i++) {
            if (pairFits(dc, texts, PAIR_FONTS[i], band, radius, y, cy)) {
                return PAIR_FONTS[i];
            }
        }
        // On a small number ladder (fenix 5 Plus) FONT_MEDIUM is WIDER than the number fonts,
        // and the floor rung can miss the column by the renderer's own rule. Two number rungs
        // below it are still values on that glass — its whole number ladder is that size.
        if (numberLadderIsSmall(dc)) {
            if (pairFits(dc, texts, Graphics.FONT_NUMBER_MEDIUM, band, radius, y, cy)) {
                return Graphics.FONT_NUMBER_MEDIUM;
            }
            if (pairFits(dc, texts, Graphics.FONT_NUMBER_MILD, band, radius, y, cy)) {
                return Graphics.FONT_NUMBER_MILD;
            }
        }
        return PAIR_FONTS[PAIR_FLOOR];
    }

    // Row centres for GRID4: 0 = giant number, 1 = top cell label, 2 = bottom cell label.
    // A cell's value sits (hT + hL) / 2 below its label. `hG` is the giant BAND — always
    // FONT_NUMBER_MILD's line height, because a 2x2 of FONT_LARGE cells plus anything taller
    // pushes the bottom row's corners off a 454 px circle. The whole block is lifted by
    // GRID_BIAS to buy that bottom row its width back.
    static function gridBias(dc as Dc) as Number {
        return dc.getHeight() * GRID_BIAS / GRID_REF_PX;
    }

    static function gridRowY(cy as Number, hG as Number, hT as Number, hL as Number,
            row as Number, hasGiant as Boolean, bias as Number) as Number {
        var cellH = hT + hL;
        var top = hasGiant ? cy - (hG + 2 * cellH) / 2 - bias : cy - cellH;
        if (row == 0) {
            return top + hG / 2;
        }
        var y = (hasGiant ? top + hG : top) + hT / 2;
        return row == 1 ? y : y + cellH;
    }

    // ---- CELLS2: two side-by-side cells, centred ----
    //
    // A whole screen for two numbers, and until 0.9.2 it spent 76 % of that screen on nothing:
    // a label line and a FONT_LARGE value came to 108 px of a 454 px glass. The value band is
    // now FONT_NUMBER_MILD and the values are fitted through the NUMBER ladder — which is what
    // "as large as reasonably possible" means on the page with the most room and the fewest
    // things to say. The fit still steps down to the text fonts for the strings that need it
    // (a "199:59" timer does not hold MILD in half a chord), so nothing clips and nothing is
    // smaller than it was.
    hidden function drawCells2Page(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hV = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);
        drawCellRow(dc, c, cx, cy, fitRadius(dc, false, foilArc), cells2RowY(cy, hT, hV),
            PageModel.slotAt(page, 0), PageModel.slotAt(page, 1), true);
    }

    // Label centre line for CELLS2; the value hangs (hT + hV) / 2 below it.
    static function cells2RowY(cy as Number, hT as Number, hV as Number) as Number {
        return cy - (hT + hV) / 2 + hT / 2;
    }

    // Two cells sharing one row's chord. The column offset comes from the depth of the row's
    // deepest ink, so the same code lays out a comfortable middle row and a tight bottom one.
    // `big` is the CELLS2 form: a FONT_NUMBER_MILD band and the number ladder under it.
    hidden function drawCellRow(dc as Dc, c as SessionController, cx as Number, cy as Number,
            radius as Number, y as Number, left as Number, right as Number,
            big as Boolean) as Void {
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hV = cellValueBand(dc, big);
        var yv = y + (hT + hV) / 2;
        var col = cellColumns(radius, yv - cy, inkH(dc, cellValueFont(big)));
        drawSlotCell(dc, c, cx - col[0], y, yv, 2 * col[1], left, big);
        drawSlotCell(dc, c, cx + col[0], y, yv, 2 * col[1], right, big);
    }

    // The band a cell's value reserves, and the font that band is named after. Shared with the
    // layout test, which measures both cell shapes.
    static function cellValueFont(big as Boolean) as Graphics.FontType {
        return big ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_LARGE;
    }

    static function cellValueBand(dc as Dc, big as Boolean) as Number {
        return dc.getFontHeight(cellValueFont(big));
    }

    // The value's own fitter: the number ladder from FONT_NUMBER_MILD down into the text fonts
    // for a `big` cell, the text ladder from FONT_LARGE for an ordinary one. Shared with the
    // layout test.
    static function cellValueFit(dc as Dc, value as String, maxW as Number,
            big as Boolean) as Graphics.FontType {
        return big ? fitGiant(dc, value, 3, maxW) : fitFont(dc, TEXT_FONTS, 0, value, maxW);
    }

    hidden function drawSlotCell(dc as Dc, c as SessionController, x as Number, y as Number,
            yv as Number, maxW as Number, id as Number, big as Boolean) as Void {
        if (id == PageModel.M_NONE) {
            return;
        }
        drawCellLabel(dc, x, y, id);
        var value = PageModel.value(id, c);
        dc.setColor(PageModel.color(id, c), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, yv, cellValueFit(dc, value, maxW, big), value, CV);
    }

    // A cell's label row: the WORD, or — when showLabels is off — the metric's glyph in its
    // place. Never both.
    //
    // They used to be drawn together, and the pair said one thing twice: a ruler beside the
    // word "km", a wing beside "flights". The glyph then had to be read as well as the word,
    // in a row that is 37 px of XTINY on a 454 px glass, and it pushed the word off the
    // column's centre for no information at all. The glyph earns its place only where the
    // word is not there — with labels off it is the entire content of the row, which is why
    // it stays for exactly that case: no cell may ever show a bare number.
    hidden function drawCellLabel(dc as Dc, x as Number, y as Number, id as Number) as Void {
        var s = Glyphs.size(dc);
        var label = AppSettings.showLabels ? PageModel.label(id) : "";
        if (label.length() > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_XTINY, label, CV);
            return;
        }
        var g = PageModel.glyph(id);
        if (g != Glyphs.G_NONE) {
            Glyphs.draw(dc, g, x, y, s, Graphics.COLOR_WHITE);
        }
    }

    // Width of that block. Shared with the layout test, which measures the label row against
    // the chord exactly as it measures the value row.
    static function cellLabelWidth(dc as Dc, id as Number, s as Number,
            label as String) as Number {
        if (label.length() > 0) {
            return dc.getTextWidthInPixels(label, Graphics.FONT_XTINY);
        }
        return PageModel.glyph(id) != Glyphs.G_NONE ? s : 0;
    }

    // ---- RECORDS: live speed records, one giant number per block ----
    //
    // This was the one page that drew a giant WITHOUT going through fitFont, and it also
    // carried a `cy + 12` bias "because the top label otherwise clips the circle edge". With
    // the real font metrics that bias put the bottom number's 229 px of ink into a 206 px
    // chord on a 454 px glass — about 11 px sliced off each end, which on "99.9" costs the
    // leading digit and the decimal point. The bias is gone (the top label at its unbiased y
    // has a 231 px chord for ~100 px of text, so it was solving a problem that had already
    // been fixed elsewhere) and both numbers now walk the same NUMBER_FONTS ladder as every
    // other giant, so a knots reading or a three-digit value steps down instead of clipping.
    //
    // Records are EFFORT, not verdict: they wear the effort orange rather than plain white,
    // the same ink the PB celebration uses (docs/presentation.md).
    //
    // Not `hidden` since 0.9.18: the post-save Records page IS this page with the session's
    // own final values (SummaryView.drawRecords), the same way the Foil, Turns, Tacks & jibes
    // and Story pages already are. Two screens showing one session's two records must not be
    // two pieces of code.
    function drawRecordsBody(dc as Dc, c as SessionController) as Void {
        var r = c.engine.records;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, false);
        var ink = inkH(dc, Graphics.FONT_NUMBER_HOT);
        var hHot = ink;
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        // unit only on the lower label, to keep the top one narrow
        var unit = " " + AppSettings.speedLabel();
        var best2s = AppSettings.speedToDisplay(r.best2sMps).format("%.1f");
        var best10s = AppSettings.speedToDisplay(r.best10sMps).format("%.1f");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, recordsRowY(cy, hHot, hT, 0), Graphics.FONT_XTINY, "best 2s", CV);
        var y = recordsRowY(cy, hHot, hT, 1);
        dc.setColor(Ink.effortWindow(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fitFont(dc, NUMBER_FONTS, 1, best2s,
            rowBudget(radius, y - cy, ink)), best2s, CV);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, recordsRowY(cy, hHot, hT, 2), Graphics.FONT_XTINY,
            "best 10s" + unit, CV);
        y = recordsRowY(cy, hHot, hT, 3);
        dc.setColor(Ink.effortWindow(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fitFont(dc, NUMBER_FONTS, 1, best10s,
            rowBudget(radius, y - cy, ink)), best10s, CV);
    }

    // Row centres for RECORDS: 0/2 = the two labels, 1/3 = the two numbers. Stacked from font
    // heights and centred on the glass, with no bias of any kind. Shared with the layout test.
    //
    // `hHot` is the numbers' INK height since 0.9.2. Two NUMBER_HOT LINE boxes and two labels
    // came to 420 px of a 454 px glass — 93 %, with a fifth of it leading — which is why this
    // page needed a magic bias in the first place. Against the ink it is 332, the bottom
    // number's chord goes from 250 px to 306 against the 229 it needs, and the two label/number
    // pairs finally read as two pairs rather than as four evenly spaced rows.
    static function recordsRowY(cy as Number, hHot as Number, hT as Number,
            row as Number) as Number {
        var y = cy - (2 * hHot + 2 * hT) / 2 + hT / 2;
        if (row == 0) { return y; }
        y += (hT + hHot) / 2;
        if (row == 1) { return y; }
        y += (hHot + hT) / 2;
        return row == 2 ? y : y + (hT + hHot) / 2;
    }

    // ---- TURNS: the outcome tally as the giant, both streaks, the dot strip, and the
    // session's verdict with its port/starboard split ----
    //
    // The hierarchy has been inverted twice now. It started with the tack/jibe COUNT as the
    // giant — a number a rider reads once an hour. It then promoted the LAST turn's score,
    // which answers "did that one count?" — but a rider looks at this page when he is sitting
    // on the board, not two seconds out of a jibe, and by then the last score is history.
    //
    // What survives that wait is the SESSION: how the day is going, three counts wide. So the
    // tally itself is the giant — three counts in the three ladder colours, colour and number
    // in one mark — and everything else on the page is the same question at a different
    // resolution: the strip is those turns in order, the streaks are how they clustered, and
    // the bottom row is what share worked and whether one side of the wind is costing him.
    //
    // The last outcome is not lost: it is the rightmost dot on the strip, in its own colour,
    // which is where a sequence naturally puts it.
    hidden function drawTurnsPage(dc as Dc, c as SessionController) as Void {
        drawTurnsBody(dc, c, true);
    }

    // `live` off is the post-save form: the streaks show the session's BESTS alone, because
    // "the run he is on" stops meaning anything the moment he is ashore. Everything else is
    // identical, which is the point — two screens showing one session's turns must not be two
    // pieces of code (the summary calls straight into this).
    function drawTurnsBody(dc as Dc, c as SessionController, live as Boolean) as Void {
        var t = c.engine.turns;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, false);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hG = inkH(dc, Graphics.FONT_NUMBER_MEDIUM);
        var hD = stripBandH(dc);
        var hK = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var hS = dc.getFontHeight(TEXT_FONTS[VERDICT_FROM]);
        var bias = turnsBias(radius, hT, hG, hD, hK, hS);

        // row 0 — the legend: the NAMES of the four counts under it, in their order and in
        // their own inks, and the wind MARK after them. It said "tack / jibe" until 0.9.11 —
        // a leftover from a giant that once counted tacks and jibes; over the outcome ladder
        // it read as 35 tacks and 12 jibes (audit, 15 Sep 2026) — and it printed the wind
        // BEARING until 0.9.18, which is not a number anybody reads off this page.
        drawLadderHeader(dc, cx, turnsRowY(cy, hT, hG, hD, hK, hS, bias, 0), cy, radius, true);

        // row 1 — THE row: clean · flew · touched · fell, in the four inks the legend named,
        // with the separators drawn as dim dots because the number fonts have no punctuation.
        // It straddles the equator, which is where the widest line on a round glass belongs.
        drawLadderRow(dc, cx, turnsRowY(cy, hT, hG, hD, hK, hS, bias, 1), cy, radius,
            ladderOf(t.cleanJibeCount, t.flewCount, t.touchdownCount, t.fellCount),
            LADDER_FROM);

        // row 2 — the same turns as row 1, one dot each, in the order they happened. It sits
        // DIRECTLY under the counts it is the texture of, the way it sits directly under the
        // giant on the MAIN page.
        var y = turnsRowY(cy, hT, hG, hD, hK, hS, bias, 2);
        drawOutcomeStrip(dc, cx, y, rowBudget(radius, y - cy, hD), c.engine.history);

        // row 3 — both streaks. The dry run says "how long since I last went in", the flew run
        // "how long since I last even touched down"; bestFlewStreak <= bestDryStreak always.
        drawStreakRow2(dc, cx, turnsRowY(cy, hT, hG, hD, hK, hS, bias, 3), cy, radius, t, live);

        // row 4 — the asymmetry. Which side of the wind he enters on is the one thing on this
        // page he can act on tomorrow.
        drawVerdictRow(dc, cx, turnsRowY(cy, hT, hG, hD, hK, hS, bias, 4), cy, radius, t);
    }

    // ---- TACKS & JIBES: the kinds page (0.9.17) ----
    //
    // Jan, 21 September 2026, from a tester practising tacks: the Turns page says how the
    // maneuvers went, and nothing on the watch says WHICH maneuvers they were. This page does,
    // in two halves: the kind's count as a giant, the kind's word under it, and under that how
    // many of that kind he flew through, in the ladder's own green.
    //
    // Five rows: the wind header, then the two halves. `drawKindsBody` is public and takes no
    // `live` flag: the after-save page IS this page (SummaryView.drawKinds) and nothing on it
    // means anything different ashore, which is the unified rule of 0.9.16 in its simplest
    // form — one piece of code, one set of numbers, two screens.
    hidden function drawKindsPage(dc as Dc, c as SessionController) as Void {
        drawKindsBody(dc, c);
    }

    function drawKindsBody(dc as Dc, c as SessionController) as Void {
        var t = c.engine.turns;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, false);
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var hG = inkH(dc, Graphics.FONT_NUMBER_MEDIUM);
        // The header row exists only where the axis does not (0.9.18): with an axis the four
        // rows below say everything the page has to say, and a row spent on a bearing nobody
        // reads here is a row the two ladder rows could have had.
        var noWind = AppSettings.cfg.windDirection < 0;

        if (noWind) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, kindsRowY(cy, hT, hG, noWind, 0), Graphics.FONT_XTINY,
                KINDS_NO_WIND, CV);
        }

        // rows 1-2 the jibes (word above its row), rows 3-4 the tacks (word below its own).
        // Jibes on top: it is the maneuver the app is named after and the one most riders do
        // most of — and it is the kind that HAS a star, so the two starred marks on the page
        // (this row's and the Turns page's) sit at the same height one swipe apart.
        var y = kindsRowY(cy, hT, hG, noWind, 1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, KINDS_JIBES, CV);
        drawLadderRow(dc, cx, kindsRowY(cy, hT, hG, noWind, 2), cy, radius,
            ladderOf(t.cleanJibeCount, t.jibeFlewCount, t.jibeTouchCount, t.jibeFellCount),
            LADDER_FROM);
        drawLadderRow(dc, cx, kindsRowY(cy, hT, hG, noWind, 3), cy, radius,
            ladderOf(-1, t.tackFlewCount, t.tackTouchCount, t.tackFellCount), LADDER_FROM);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, kindsRowY(cy, hT, hG, noWind, 4), Graphics.FONT_XTINY, KINDS_TACKS, CV);
    }

    // Row centres: 0 the no-axis line (drawn only when there is no axis, band 0 otherwise),
    // 1 the word "jibes", 2 the jibes row, 3 the tacks row, 4 the word "tacks". The block is
    // centred, so the TWO WIDE ROWS straddle the equator with a narrow word above and below
    // them — which is the shape Jan's principle asks for on a round glass. Shared with the
    // layout test.
    static function kindsRowY(cy as Number, hT as Number, hG as Number, noWind as Boolean,
            row as Number) as Number {
        var hH = noWind ? hT : 0;
        var y = cy - (hH + 2 * hT + 2 * hG) / 2;
        if (row == 0) { return y + hT / 2; }
        if (row == 1) { return y + hH + hT / 2; }
        if (row == 2) { return y + hH + hT + hG / 2; }
        if (row == 3) { return y + hH + hT + hG + hG / 2; }
        return y + hH + hT + 2 * hG + hT / 2;
    }

    // ---- THE LADDER ROW (0.9.18) ----
    //
    // "★34  63 · 21 · 12": the clean jibes behind their star, then flew · touched · fell in
    // the outcome ladder's own three inks, with the separators drawn as dim DOTS because the
    // number fonts have no punctuation — which is also what lets a separator shrink with the
    // digits instead of pinning a text font's comma beside them.
    //
    // ONE renderer for four screens: the Turns page, both halves of the Tacks & jibes page,
    // and the large set's three turn screens. The moment it was two, they would drift — and
    // this vocabulary is the one a rider learns once and then reads everywhere.
    //
    // `counts[0] < 0` is a ladder with NO star: the tack row, whose kind has no clean verdict.
    // A zero clean count still draws (`★0`) once there are turns, because on a row whose other
    // three numbers are there the missing one reads as a broken page rather than as a zero —
    // the opposite of the standalone row it replaced, where "★ 0" alone was the whole content.
    hidden function drawLadderRow(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, counts as Array<Number>, from as Number) as Void {
        var s = Glyphs.size(dc);
        var star = counts[0] >= 0;
        var f = ladderRowFont(dc, counts, s,
            rowBudget(radius, y - cy, inkH(dc, NUMBER_FONTS[from])), from);
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var sep = giantSepW(dc, f);
        var r = giantSepR(dc, f);
        var x = cx - ladderRowWidth(dc, counts, s, f) / 2;
        if (star) {
            var clean = counts[0].toString();
            dc.setColor(Ink.cleanJibe(), Graphics.COLOR_TRANSPARENT);
            Glyphs.drawStar(dc, x + s / 2, y, s);
            x += s + CLEAN_GLYPH_GAP;
            dc.drawText(x, y, f, clean, LV);
            x += dc.getTextWidthInPixels(clean, f) + LADDER_CLEAN_GAP;
        }
        var cols = [Ink.ladderFlew(), Ink.ladderTouchdown(), Ink.ladderFellIn()];
        for (var i = 1; i < 4; i++) {
            if (i > 1) {
                dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x + sep / 2, y, r);
                x += sep;
            }
            var v = counts[i].toString();
            dc.setColor(cols[i - 1], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, v, LV);
            x += dc.getTextWidthInPixels(v, f);
        }
    }

    // The four counts as one array, filled in the shared scratch. A ladder row is drawn up to
    // four times a frame on the Tacks & jibes page and a fresh array per call would be four
    // allocations a second on a page that otherwise makes none.
    static function ladderOf(clean as Number, flew as Number, touch as Number,
            fell as Number) as Array<Number> {
        _ladder[0] = clean;
        _ladder[1] = flew;
        _ladder[2] = touch;
        _ladder[3] = fell;
        return _ladder;
    }

    // Width of that row in `f`: the star group where there is one, then three counts and two
    // separator slots. Shared with the layout test, which measures it at its worst case.
    static function ladderRowWidth(dc as Dc, counts as Array<Number>, glyph as Number,
            f as Graphics.FontType) as Number {
        var w = 2 * giantSepW(dc, f);
        if (counts[0] >= 0) {
            w += glyph + CLEAN_GLYPH_GAP
                + dc.getTextWidthInPixels(counts[0].toString(), f) + LADDER_CLEAN_GAP;
        }
        for (var i = 1; i < 4; i++) {
            w += dc.getTextWidthInPixels(counts[i].toString(), f);
        }
        return w;
    }

    // NUMBER_FONTS from `from`, then down the text ladder to the FONT_SMALL floor. A count is
    // a value, and a value below FONT_SMALL is not readable at arm's length — so the row would
    // rather clip than lie about being legible, and in practice never gets there.
    static function ladderRowFont(dc as Dc, counts as Array<Number>, glyph as Number,
            budget as Number, from as Number) as Graphics.FontType {
        for (var i = from; i < NUMBER_FONTS.size(); i++) {
            if (ladderRowWidth(dc, counts, glyph, NUMBER_FONTS[i]) <= budget) {
                return NUMBER_FONTS[i];
            }
        }
        for (var i = 0; i < TALLY_FLOOR; i++) {
            if (ladderRowWidth(dc, counts, glyph, TEXT_FONTS[i]) <= budget) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // ---- the ladder row's LEGEND, and the wind mark on it ----
    //
    // The four words in the four inks, in the row's own order, at FONT_XTINY — and after them,
    // on the Turns page, the wind MARK (Glyphs.drawWind): filled where the rider set the axis,
    // hollow where the watch estimated it, hollow and dim where there is none. The page needs
    // to say only WHETHER it has an axis: without one the port/starboard row below is counting
    // nothing and the Tacks & jibes page one swipe on is all zeros.
    //
    // `mark` off draws the words alone, which is what a page with its own axis story wants.
    hidden function drawLadderHeader(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, mark as Boolean) as Void {
        var s = Glyphs.size(dc);
        var budget = rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_XTINY));
        var got = ladderHeaderContent(dc, s, budget, mark);
        var sep = (got & LADDER_HEAD_SEPARATORS) != 0
            ? LADDER_HEAD_SEP : LADDER_HEAD_SEP_NARROW;
        var showMark = (got & LADDER_HEAD_MARK) != 0;
        var caps = [TALLY_CAP_CLEAN, TALLY_CAP_FLEW, TALLY_CAP_TOUCH, TALLY_CAP_FELL];
        var cols = [Ink.cleanJibe(), Ink.ladderFlew(), Ink.ladderTouchdown(),
            Ink.ladderFellIn()];
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = cx - ladderHeaderWidth(dc, s, showMark, sep) / 2;
        for (var i = 0; i < 4; i++) {
            if (i > 0) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y, Graphics.FONT_XTINY, sep, LV);
                x += dc.getTextWidthInPixels(sep, Graphics.FONT_XTINY);
            }
            dc.setColor(cols[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_XTINY, caps[i], LV);
            x += dc.getTextWidthInPixels(caps[i], Graphics.FONT_XTINY);
        }
        if (!showMark) {
            return;
        }
        var cfg = AppSettings.cfg;
        var set = cfg.windDirection >= 0;
        dc.setColor(set ? Graphics.COLOR_WHITE : Ink.dim(), Graphics.COLOR_TRANSPARENT);
        Glyphs.drawWind(dc, x + LADDER_HEAD_MARK_GAP + s / 2, y, s, set && !cfg.windIsAuto());
    }

    // What the legend can afford at `budget`, as a bitmask. Separators go first, then the
    // mark; the four WORDS never go, because they are the legend. -1 is not a possible
    // answer here for the same reason the tally row's is rare: four XTINY words with single
    // spaces are 160 px on the narrowest glass shipped, against a 214 px chord.
    // Shared with the layout test.
    static function ladderHeaderContent(dc as Dc, glyph as Number, budget as Number,
            mark as Boolean) as Number {
        if (ladderHeaderWidth(dc, glyph, mark, LADDER_HEAD_SEP) <= budget) {
            return (mark ? LADDER_HEAD_MARK : 0) | LADDER_HEAD_SEPARATORS;
        }
        if (ladderHeaderWidth(dc, glyph, mark, LADDER_HEAD_SEP_NARROW) <= budget) {
            return mark ? LADDER_HEAD_MARK : 0;
        }
        return 0;
    }

    // Width of that legend with a given separator, with or without the mark. Shared with the
    // layout test, which measures it against the chord at the header's own depth.
    static function ladderHeaderWidth(dc as Dc, glyph as Number, mark as Boolean,
            sep as String) as Number {
        var w = 3 * dc.getTextWidthInPixels(sep, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(TALLY_CAP_CLEAN, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(TALLY_CAP_FLEW, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(TALLY_CAP_TOUCH, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(TALLY_CAP_FELL, Graphics.FONT_XTINY);
        return mark ? w + LADDER_HEAD_MARK_GAP + glyph : w;
    }

    // Separator slot and dot radius, both derived from the ink height of whatever font a
    // ladder row landed in, so the groups keep their proportions on every variant.
    static function giantSepW(dc as Dc, f as Graphics.FontType) as Number {
        return inkH(dc, f) / 3;
    }

    static function giantSepR(dc as Dc, f as Graphics.FontType) as Number {
        var r = inkH(dc, f) / 14;
        return r < 2 ? 2 : r;
    }

    // The Turns page's streak row: "streak: 2/5  7/11". One grey word for the row, then the
    // two runs in the OUTCOME LADDER's own inks — green for the run of pure fly-throughs,
    // orange for the run that survives a touchdown; falling in breaks both, which is why there
    // is no red run to draw. That is exactly the vocabulary the coloured tally two rows above
    // has already taught, so the colours do the work the words "fly" and "dry" used to do, and
    // do it before the digits are in focus.
    //
    // This is not the ladder being borrowed for something else: each run is a COUNT OF RUNGS —
    // how many turns in a row came out green, how many came out anything but red — so it is the
    // ladder measured a second way (docs/presentation.md). The MAIN page's lone dry streak
    // stays neutral for the opposite reason: with no second run beside it there is nothing to
    // tell apart, and a colour there would read as a verdict on the rider rather than on turns.
    hidden function drawStreakRow2(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, t as TurnDetector, live as Boolean) as Void {
        var fNow = t.flewStreak.toString();
        var fBest = t.bestFlewStreak.toString();
        var dNow = t.dryStreak.toString();
        var dBest = t.bestDryStreak.toString();
        var budget = rowBudget(radius, y - cy, inkH(dc, Graphics.FONT_MEDIUM));
        var f = streakRow2Font(dc, fNow, fBest, dNow, dBest, budget, live);
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = cx - streakRow2Width(dc, fNow, fBest, dNow, dBest, f, live) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, STREAK_ROW_CAPTION, LV);
        x += dc.getTextWidthInPixels(STREAK_ROW_CAPTION, Graphics.FONT_XTINY) + GLYPH_GAP;
        x = drawStreakRun(dc, x, y, fNow, fBest, f, live, Ink.ladderFlew());
        drawStreakRun(dc, x + TURNS_OK_GAP, y, dNow, dBest, f, live, Ink.ladderTouchdown());
    }

    // One run — "2/5" live, "5" once ashore — both numbers in `col`, the slash dim between
    // them. `showNow` off is the post-save form: "the run he is on" stops meaning anything the
    // moment he is out of the water, so S4 shows the two bests alone.
    function drawStreakRun(dc as Dc, x as Number, y as Number, now as String, best as String,
            f as Graphics.FontType, showNow as Boolean, col as Number) as Number {
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        if (showNow) {
            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, now, LV);
            x += dc.getTextWidthInPixels(now, f);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, STREAK_SEP_TIGHT, LV);
            x += dc.getTextWidthInPixels(STREAK_SEP_TIGHT, f);
        }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, best, LV);
        return x + dc.getTextWidthInPixels(best, f);
    }

    static function streakRunWidth(dc as Dc, now as String, best as String,
            f as Graphics.FontType, showNow as Boolean) as Number {
        var w = dc.getTextWidthInPixels(best, f);
        if (showNow) {
            w += dc.getTextWidthInPixels(now, f)
                + dc.getTextWidthInPixels(STREAK_SEP_TIGHT, f);
        }
        return w;
    }

    static function streakRow2Width(dc as Dc, fNow as String, fBest as String, dNow as String,
            dBest as String, f as Graphics.FontType, live as Boolean) as Number {
        return dc.getTextWidthInPixels(STREAK_ROW_CAPTION, Graphics.FONT_XTINY) + GLYPH_GAP
            + streakRunWidth(dc, fNow, fBest, f, live) + TURNS_OK_GAP
            + streakRunWidth(dc, dNow, dBest, f, live);
    }

    static function streakRow2Font(dc as Dc, fNow as String, fBest as String, dNow as String,
            dBest as String, budget as Number, live as Boolean) as Graphics.FontType {
        for (var i = 1; i < TALLY_FLOOR; i++) {
            if (streakRow2Width(dc, fNow, fBest, dNow, dBest, TEXT_FONTS[i], live) <= budget) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // "P 29 / S 22" — which side of the wind he entered his turns on. Values in the row's own
    // font, every word around them XTINY, exactly as the streak row does it, which is what
    // keeps the row inside a bottom-arc chord.
    //
    // It carried a "69 % flew" share in front of that until 0.9.18. Jan took it off the page:
    // the share is flewCount over turnCount and both of those numbers are on the ladder row
    // two rows up, so the page was stating one fact twice — and a page that says the same
    // thing twice has to be believed twice. The counts are the fact; the percentage was a
    // reading of it, and a reading belongs where there is room to explain itself.
    //
    // The row is DROPPED, not shrunk, when the side counts are absent (no wind axis, so no
    // side to be on) or when the chord cannot hold it even at the floor. A number that has to
    // lie about its size to fit is worse than a number that is not there.
    hidden function drawVerdictRow(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, t as TurnDetector) as Void {
        if (t.turnCount <= 0 || t.portEntryCount + t.starboardEntryCount <= 0) {
            return;                 // no turns, or no axis to have a side of
        }
        var p = t.portEntryCount.toString();
        var s = t.starboardEntryCount.toString();
        var budget = rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[VERDICT_FROM]));
        var sides = verdictWidth(dc, p, s, TEXT_FONTS[TALLY_FLOOR]) <= budget;
        if (!sides) {
            return;
        }
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var f = verdictFont(dc, p, s, budget);
        var x = cx - verdictWidth(dc, p, s, f) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, TURNS_PORT, LV);
        x += dc.getTextWidthInPixels(TURNS_PORT, Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, p, LV);
        x += dc.getTextWidthInPixels(p, f);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, TURNS_SIDE_SEP, LV);
        x += dc.getTextWidthInPixels(TURNS_SIDE_SEP, Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, TURNS_STBD, LV);
        x += dc.getTextWidthInPixels(TURNS_STBD, Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, s, LV);
    }

    // The row's font: the largest from TEXT_FONTS[VERDICT_FROM] that fits, floored at
    // FONT_SMALL like every other value on the watch.
    static function verdictFont(dc as Dc, p as String, s as String,
            budget as Number) as Graphics.FontType {
        for (var i = VERDICT_FROM; i < TALLY_FLOOR; i++) {
            if (verdictWidth(dc, p, s, TEXT_FONTS[i]) <= budget) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // Width of that row. Shared with the layout test, which measures it at "P 99 / S 99".
    static function verdictWidth(dc as Dc, p as String, s as String,
            f as Graphics.FontType) as Number {
        return dc.getTextWidthInPixels(TURNS_PORT, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(p, f)
            + dc.getTextWidthInPixels(TURNS_SIDE_SEP, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(TURNS_STBD, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(s, f);
    }

    // The outcome ladder, and nothing else on the watch may borrow it (docs/presentation.md).
    // These are the design tokens, not Graphics.COLOR_GREEN/ORANGE/RED: the phase tint used
    // to be the same COLOR_GREEN, so on the Timeline page the foil bars and the outcome dots
    // — six rows apart, on one screen — were the same ink for two different meanings.
    static function outcomeColor(outcome as Number) as Number {
        if (outcome == TurnDetector.OUTCOME_FLEW) { return Ink.ladderFlew(); }
        if (outcome == TurnDetector.OUTCOME_TOUCHDOWN) { return Ink.ladderTouchdown(); }
        if (outcome == TurnDetector.OUTCOME_FELL) { return Ink.ladderFellIn(); }
        return Ink.ladderNone();
    }

    // Row centres for the Turns page (0.9.18): 0 legend · 1 the ladder row · 2 outcome dots ·
    // 3 streaks · 4 the port/starboard split. FIVE rows, down from six — the clean jibes
    // joined the ladder row and CPH left the watch.
    //
    // `hG` is the ladder row's INK height (0.9.2, see heroRowY): 39 px of NUMBER_MEDIUM
    // leading on a 454 px glass that the rows under it were being pushed down by.
    //
    // The stack is centred on its own total AND THEN LIFTED (`turnsBias`), which is the whole
    // geometric point of the round-glass rule: one narrow legend above the wide row and three
    // narrow rows below it is not a symmetric stack, so centring the TOTAL leaves the widest
    // line high and the top arc empty. Shared with the layout test, which asserts every row
    // still clears the circle with the lift applied.
    static function turnsRowY(cy as Number, hT as Number, hG as Number, hD as Number,
            hK as Number, hS as Number, bias as Number, row as Number) as Number {
        var y = cy - (hT + hG + hD + hK + hS) / 2 + bias;
        if (row == 0) { return y + hT / 2; }
        if (row == 1) { return y + hT + hG / 2; }
        if (row == 2) { return y + hT + hG + hD / 2; }
        if (row == 3) { return y + hT + hG + hD + hK / 2; }
        return y + hT + hG + hD + hK + hS / 2;
    }

    // The lift: exactly the distance that puts the ladder row's own centre on the equator,
    // capped at TURNS_BIAS_MAX_PCT of the radius. Past the cap the page would be buying the
    // widest row a chord it already had by pushing the bottom row into one it has not — the
    // mirror of the trade GRID_BIAS makes in the other direction. Shared with the layout test.
    static function turnsBias(radius as Number, hT as Number, hG as Number, hD as Number,
            hK as Number, hS as Number) as Number {
        var want = (hT + hG + hD + hK + hS) / 2 - hT - hG / 2;
        if (want <= 0) {
            return 0;
        }
        var cap = radius * TURNS_BIAS_MAX_PCT / 100;
        return want > cap ? cap : want;
    }

    // Width of the tally row: three counts, two separators, and — when it is being shown —
    // the session verdict after a wider gap so the two groups read as two groups.
    static function tallyWidth(dc as Dc, a as String, b as String, c as String,
            ok as String, sep as String, f as Graphics.FontType) as Number {
        var w = dc.getTextWidthInPixels(a, f) + dc.getTextWidthInPixels(b, f)
            + dc.getTextWidthInPixels(c, f) + 2 * dc.getTextWidthInPixels(sep, f);
        if (!ok.equals("")) {
            w += TURNS_OK_GAP + dc.getTextWidthInPixels(ok, f);
        }
        return w;
    }

    // What the three captions add to a tally row: three words at FONT_XTINY and a gap each.
    static function captionsWidth(dc as Dc) as Number {
        return dc.getTextWidthInPixels(TALLY_CAP_FLEW, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(TALLY_CAP_TOUCH, Graphics.FONT_XTINY)
            + dc.getTextWidthInPixels(TALLY_CAP_FELL, Graphics.FONT_XTINY)
            + 3 * TALLY_CAPTION_GAP;
    }

    // What the row can afford to SHOW at font `f`, as a bitmask: TALLY_SEPARATORS for the
    // " · " between the counts, TALLY_OK for the session verdict. -1 = not even three bare
    // counts fit at this size.
    //
    // This is the "drop content, not size" rule. The old code stepped the font down instead,
    // and the measured worst case — three two-digit tallies plus "100% ok" — landed on
    // FONT_XTINY, about 21 px of digit, below the readability floor. The session that
    // produces that worst case (30+ turns) is exactly the session whose tally the rider wants
    // to read, so the row now sheds the verdict, then the separators, and only shrinks when
    // even the bare counts overflow.
    static function tallyContent(dc as Dc, a as String, b as String, c as String,
            ok as String, budget as Number, f as Graphics.FontType) as Number {
        if (tallyWidth(dc, a, b, c, ok, TURNS_TALLY_SEP, f) + captionsWidth(dc) <= budget) {
            return TALLY_SEPARATORS | TALLY_OK | TALLY_CAPTIONS;
        }
        if (tallyWidth(dc, a, b, c, ok, TURNS_TALLY_SEP, f) <= budget) {
            return TALLY_SEPARATORS | TALLY_OK;
        }
        if (tallyWidth(dc, a, b, c, "", TURNS_TALLY_SEP, f) <= budget) {
            return TALLY_SEPARATORS;
        }
        if (tallyWidth(dc, a, b, c, "", TALLY_SEP_NARROW, f) <= budget) {
            return 0;
        }
        return -1;
    }

    // The font the tally row lands in: the first from `from` at which SOME content set fits,
    // floored at TEXT_FONTS[TALLY_FLOOR] = FONT_SMALL. Below that a count is not readable at
    // arm's length, so the row would rather clip than lie about being legible — and in
    // practice it never gets there, because tallyContent has already dropped everything
    // droppable by then.
    static function tallyFont(dc as Dc, a as String, b as String, c as String, ok as String,
            budget as Number, from as Number) as Graphics.FontType {
        for (var i = from; i < TALLY_FLOOR; i++) {
            if (tallyContent(dc, a, b, c, ok, budget, TEXT_FONTS[i]) >= 0) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // "flew · touch · swim" counts in the ladder's own colours, centred as one block. `from`
    // is the TEXT_FONTS index the row's band was reserved at — 0 (FONT_LARGE) on the main
    // screen, TALLY_FLOOR (FONT_SMALL) on the Turns page — and `ok` is the session verdict,
    // empty when the caller does not want one on this row.
    // Public: the post-save Turns page draws the identical block. Two screens showing the
    // same three counts in the same three colours must not be two pieces of code.
    function drawTally(dc as Dc, cx as Number, y as Number, cy as Number,
            radius as Number, t as TurnDetector, ok as String, from as Number) as Void {
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var a = t.flewCount.toString();
        var b = t.touchdownCount.toString();
        var s = t.fellCount.toString();
        var budget = rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[from]));
        var f = tallyFont(dc, a, b, s, ok, budget, from);
        var mask = tallyContent(dc, a, b, s, ok, budget, f);
        if (mask < 0) {
            mask = 0;       // nothing fits even at the floor: draw the bare counts anyway
        }
        var sep = (mask & TALLY_SEPARATORS) != 0 ? TURNS_TALLY_SEP : TALLY_SEP_NARROW;
        var verdict = (mask & TALLY_OK) != 0 ? ok : "";
        var caps = (mask & TALLY_CAPTIONS) != 0;
        var wSep = dc.getTextWidthInPixels(sep, f);
        var w = tallyWidth(dc, a, b, s, verdict, sep, f) + (caps ? captionsWidth(dc) : 0);
        var x = cx - w / 2;
        // Each count in its ink, its caption after it in the same ink where the row carries
        // captions, the separator in white; the verdict last, in neutral white, so the three
        // coloured counts stay the thing the eye lands on.
        x = tallyCell(dc, x, y, f, a, TALLY_CAP_FLEW, caps, Ink.ladderFlew());
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, sep, LV);
        x = tallyCell(dc, x + wSep, y, f, b, TALLY_CAP_TOUCH, caps, Ink.ladderTouchdown());
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, sep, LV);
        x = tallyCell(dc, x + wSep, y, f, s, TALLY_CAP_FELL, caps, Ink.ladderFellIn());
        if (!verdict.equals("")) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + TURNS_OK_GAP, y, f, verdict, LV);
        }
    }

    // One count and, where the row carries them, its caption: the word in FONT_XTINY on the
    // same centre line, in the count's own ink. Returns the x after the cell.
    hidden function tallyCell(dc as Dc, x as Number, y as Number, f as Graphics.FontType,
            count as String, cap as String, caps as Boolean, ink as Number) as Number {
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, count, LV);
        x += dc.getTextWidthInPixels(count, f);
        if (caps) {
            x += TALLY_CAPTION_GAP;
            dc.drawText(x, y, Graphics.FONT_XTINY, cap, LV);
            x += dc.getTextWidthInPixels(cap, Graphics.FONT_XTINY);
        }
        return x;
    }

    // ---- TIMELINE: the session as a story ----
    // Three stacked bands: foil-fraction bars over the whole session, a max-speed sparkline
    // with the best-2s reference line, and the turn outcomes as coloured dots (newest right).
    // Every band is clipped to the chord at its own depth, so nothing runs off the glass; the
    // dot row simply shows as many of the most recent turns as fit.
    // Public: the post-save Story page is this page verbatim. The timeline is a
    // sit-down-with-a-coffee medium and a poor one-second glance, which is exactly the
    // right way round for a summary.
    function drawTimelinePage(dc as Dc, c as SessionController) as Void {
        var h = c.engine.history;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var hT = dc.getFontHeight(Graphics.FONT_XTINY);
        var radius = cx - TL_MARGIN;
        var strip = stripH(dc);
        var spark = sparkH(dc);

        // band 1: foil-fraction bars, between two rails.
        //
        // The rails are the whole reason this band is readable. A bar chart with one baseline
        // says "more is more" and nothing else — there was no way to know that a full-height
        // bar means "the whole of that half-minute was on the foil", so the band read as a
        // decorative sawtooth. Drawing the 100 % line as well turns it into an envelope: every
        // bar is now visibly a FRACTION of a fixed height, and the caption says which fraction.
        var top = timelineRowY(cy, hT, strip, spark, 1);
        var halfW = bandHalfWidth(radius, top, top + strip, cy);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timelineRowY(cy, hT, strip, spark, 0), Graphics.FONT_XTINY,
            "on foil %", CV);
        dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - halfW, top + strip, cx + halfW, top + strip);
        dc.drawLine(cx - halfW, top, cx + halfW, top);
        var n = h.slotCount;
        if (n > 0) {
            var w = 2 * halfW;
            var barW = w / n;
            if (barW < 1) {
                barW = 1;
            }
            // PHASE teal, not the ladder's green: these bars and the outcome dots six rows
            // below them share one screen, and one ink for both meanings made the page lie.
            dc.setColor(Ink.phaseFlying(), Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < n; i++) {
                var bh = h.foilPct[i] * strip / 100;
                if (bh > 0) {
                    dc.fillRectangle(cx - halfW + i * w / n, top + strip - bh, barW, bh);
                }
            }
        }

        // band 2: max-speed sparkline + best-2s reference
        top = timelineRowY(cy, hT, strip, spark, 3);
        halfW = bandHalfWidth(radius, top, top + spark, cy);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        // "top speed", not "speed": every point on this line is the FASTEST sample in its
        // slot, and a line labelled "speed" reads as an average — which would make the same
        // shape mean something the app never measured.
        dc.drawText(cx, timelineRowY(cy, hT, strip, spark, 2), Graphics.FONT_XTINY,
            "top speed " + AppSettings.speedLabel(), CV);
        var peak = h.peakCms();
        var ref = (c.engine.records.best2sMps * 100.0).toNumber();
        if (ref > peak) {
            peak = ref;
        }
        if (peak < 100) {
            peak = 100;
        }
        if (ref > 0) {
            var yRef = top + spark - ref * spark / peak;
            dc.setColor(Ink.dim(), Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - halfW, yRef, cx + halfW, yRef);
        }
        if (n > 1) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            var px = cx - halfW;
            var py = top + spark - h.maxCms[0] * spark / peak;
            for (var i = 1; i < n; i++) {
                var qx = cx - halfW + i * 2 * halfW / (n - 1);
                var qy = top + spark - h.maxCms[i] * spark / peak;
                dc.drawLine(px, py, qx, qy);
                px = qx;
                py = qy;
            }
            dc.setPenWidth(1);
        }

        // band 3: turn outcomes, newest on the right — and its caption UNDER it since 0.9.18.
        // Jan's layout review: the dot row is the page's widest band and the word above it
        // was pushing it one XTINY line deeper into the arc for nothing. Below the dots the
        // word sits where the chord has already collapsed, which is where a two-syllable
        // caption costs nothing, and the dots move up into the width they were giving away.
        var yDots = timelineRowY(cy, hT, strip, spark, 4);
        halfW = bandHalfWidth(radius, yDots - TL_DOT_R, yDots + TL_DOT_R, cy);
        drawOutcomeStrip(dc, cx, yDots, 2 * halfW, h);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timelineRowY(cy, hT, strip, spark, 5), Graphics.FONT_XTINY, "turns", CV);
    }

    // ---- the outcome strip ----
    // One dot per counted turn, in the order they happened, each in its verdict colour. It is
    // a TEXTURE, not a census: when there are more turns than the chord holds it shows the
    // most recent that fit and says nothing about the rest, because "how has the last while
    // gone" is the question a strip answers and a count is what answers the other one.
    //
    // Public and shared by three screens — the Timeline's bottom band, the MAIN page and the
    // Turns page (and through it the post-save Turns page). One visual language for one fact
    // means one function; the moment it was two, they would drift.
    function drawOutcomeStrip(dc as Dc, cx as Number, y as Number, avail as Number,
            h as SessionHistory) as Void {
        var shown = dotsShown(h.turnCount, avail);
        var pitch = 2 * TL_DOT_R + TL_DOT_GAP;
        var x0 = cx - (shown * pitch - TL_DOT_GAP) / 2 + TL_DOT_R;
        for (var i = 0; i < shown; i++) {
            dc.setColor(outcomeColor(h.turns[h.turnCount - shown + i]),
                Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x0 + i * pitch, y, TL_DOT_R);
        }
    }

    // The vertical band a strip reserves in a row stack: the dot plus a gap either side, so
    // the rows above and below it never sit against the ink. Shared with the layout test.
    static function stripBandH(dc as Dc) as Number {
        return 2 * TL_DOT_R + 2 * TL_DOT_GAP;
    }

    // Band heights for THIS glass. TL_STRIP_H / TL_SPARK_H were authored for the fenix 8
    // family (416-454 px) and every member of it keeps them verbatim. Taken literally on a
    // 240 px fenix 7S the three bands plus their labels fill 86 % of the height, which drives
    // every band down to a depth where the chord has collapsed — the dot row was left 88 px of
    // usable width, against 202 px once the bands scale.
    static function bandH(dc as Dc, authored as Number) as Number {
        var h = dc.getHeight();
        return h >= TL_REF_PX ? authored : h * authored / TL_REF_PX;
    }

    static function stripH(dc as Dc) as Number {
        return bandH(dc, TL_STRIP_H);
    }

    static function sparkH(dc as Dc) as Number {
        return bandH(dc, TL_SPARK_H);
    }

    // Timeline rows: 0 foil label · 1 strip TOP · 2 speed label · 3 sparkline TOP ·
    // 4 dot-row centre · 5 turns label. Stacked from font heights + the band heights, so
    // the bands can never collide on any variant.
    //
    // Rows 4 and 5 swapped in 0.9.18: the two tall bands keep their caption ABOVE them
    // (a caption over an envelope says what the envelope is before it is read), and the dot
    // row takes its caption BELOW, because the dots are the widest thing on the page and the
    // arc it was being pushed into is the narrowest part of the glass.
    static function timelineRowY(cy as Number, hT as Number, strip as Number,
            spark as Number, row as Number) as Number {
        var total = 3 * hT + strip + spark + 2 * TL_DOT_R;
        var y = cy - total / 2;
        if (row == 0) { return y + hT / 2; }
        if (row == 1) { return y + hT; }
        if (row == 2) { return y + hT + strip + hT / 2; }
        if (row == 3) { return y + 2 * hT + strip; }
        if (row == 4) { return y + 2 * hT + strip + spark + TL_DOT_R; }
        return y + 2 * hT + strip + spark + 2 * TL_DOT_R + hT / 2;
    }

    // Half the chord available to a band spanning yTop..yBot — the deeper edge decides.
    static function bandHalfWidth(radius as Number, yTop as Number, yBot as Number,
            cy as Number) as Number {
        var d = (yTop - cy).abs();
        var d2 = (yBot - cy).abs();
        if (d2 > d) {
            d = d2;
        }
        var v = radius * radius - d * d;
        return v > 0 ? Math.sqrt(v.toFloat()).toNumber() : 0;
    }

    // How many outcome dots fit in `avail` pixels (newest win; the rest fall off the left).
    static function dotsShown(count as Number, avail as Number) as Number {
        var k = (avail + TL_DOT_GAP) / (2 * TL_DOT_R + TL_DOT_GAP);
        if (k > count) {
            k = count;
        }
        return k < 0 ? 0 : k;
    }

    // ---- MAP: the session's own breadcrumb, drawn by us ----
    //
    // Until 0.9.2 this page was WatchUi.MapTrackView pushed over RecordingView, and the fenix 8
    // killed the app on it twice — a Type Error on 0.9.0's switchToView, then a silent firmware
    // kill on 0.9.1's pushView with nothing in CIQ_LOG. The trail is now ours: the same
    // renderer the post-save Track page has used since 0.8.2 (TrackDraw), which has never
    // crashed anything, plus the two things a LIVE trail owes the rider that a post-save one
    // does not — a marker on where he is now, and the PAUSED banner, which a native view could
    // not carry and which is why this page used to be skipped while paused.
    //
    // North is up. No basemap, no rotation, no zoom: what this page answers is "where have I
    // been and how far out am I", and the shape of the session's own track answers it.
    hidden function drawMapPage(dc as Dc, c as SessionController, foilArc as Boolean) as Void {
        var e = c.engine;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, foilArc);
        var box = mapBox(dc, radius);
        // The phone-rendered ground, when the rider is inside a snapshot the phone sent
        // (docs/watch-map-snapshot.md): the snapshot's box becomes the frame and the trail is
        // drawn into it. Otherwise the 0.9.9 auto-fit, unchanged.
        var slot = e.trackN > 0 && e.trackLat != null && e.trackLon != null
            ? MapSnapshot.slotForPosition(e.trackLat[e.trackN - 1], e.trackLon[e.trackN - 1])
            : null;
        var drawn;
        if (slot != null) {
            var frame = MapSnapshot.frame(slot, box);
            drawn = frame != null && TrackDraw.drawFramed(dc, e.trackLat, e.trackLon,
                e.trackFly, e.trackN, [cx, cy, box] as Array<Number>, true, frame,
                MapSnapshot.bitmap(slot, box));
        } else {
            drawn = TrackDraw.draw(dc, e.trackLat, e.trackLon, e.trackFly, e.trackN, cx, cy,
                box, true);
        }
        if (!drawn) {
            drawFittedRow(dc, cx, cy, radius, cy, 0, MAP_WAITING, Graphics.COLOR_WHITE);
            return;
        }
        // A map with no number on it is a shape. The odometer is the one number the shape
        // cannot show, so since 0.9.18 it is drawn at the size a value deserves rather than
        // at FONT_SMALL, the floor it had been pinned to: the digits walk the text ladder
        // from FONT_LARGE down to that floor and "km" stays a word at FONT_XTINY beside them.
        var km = (e.distM / 1000.0).format("%.1f");
        var y = mapCaptionY(dc, box);
        var f = mapKmFont(dc, km, rowBudget(radius, y - cy, inkH(dc, TEXT_FONTS[0])));
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawKm(dc, cx - mapKmWidth(dc, km, f) / 2, y, km, f);
    }

    // The odometer group, drawn from its LEFT edge: the digits in `f`, then "km" at
    // FONT_XTINY. Public because the post-save Track page draws the identical group — one
    // trail, one renderer, one distance, the same rule S2 to S8 keep.
    static function drawKm(dc as Dc, x as Number, y as Number, km as String,
            f as Graphics.FontType) as Void {
        var LV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.drawText(x, y, f, km, LV);
        dc.drawText(x + dc.getTextWidthInPixels(km, f) + MAP_KM_GAP, y, Graphics.FONT_XTINY,
            MAP_KM, LV);
    }

    // Side of the square the trail is drawn in, and the ink centre of the caption hung off its
    // bottom edge. Both shared with the layout test. The caption's band is FONT_LARGE's line
    // whatever rung the digits land on, so a long odometer moves nothing.
    static function mapBox(dc as Dc, radius as Number) as Number {
        return TrackDraw.boxSide(radius - scaled(dc, MAP_MARGIN));
    }

    static function mapCaptionY(dc as Dc, box as Number) as Number {
        return dc.getHeight() / 2 + box / 2 + dc.getFontHeight(TEXT_FONTS[0]) / 2;
    }

    // Width of that caption: the digits in `f`, then the gap and the unit at FONT_XTINY.
    static function mapKmWidth(dc as Dc, km as String, f as Graphics.FontType) as Number {
        return dc.getTextWidthInPixels(km, f) + MAP_KM_GAP
            + dc.getTextWidthInPixels(MAP_KM, Graphics.FONT_XTINY);
    }

    // FONT_LARGE down to TEXT_FONTS[TALLY_FLOOR] = FONT_SMALL, the readability floor every
    // value on this watch keeps — which is where this caption used to START.
    static function mapKmFont(dc as Dc, km as String, budget as Number) as Graphics.FontType {
        for (var i = 0; i < TALLY_FLOOR; i++) {
            if (mapKmWidth(dc, km, TEXT_FONTS[i]) <= budget) {
                return TEXT_FONTS[i];
            }
        }
        return TEXT_FONTS[TALLY_FLOOR];
    }

    // ---- CLOCK: giant time of day, then one configurable cell ----
    //
    // The cell under the clock is the session TIMER by default, and in 0.9.2 it stopped being a
    // FONT_LARGE cell like any other and became a MILD one, the same treatment CELLS2 got — it
    // is the only value on a page whose other content is a clock, and this page had 136 px of
    // a 454 px glass doing nothing.
    //
    // That is not free: a taller cell pushes the giant up, and the giant is a THAI_HOT "23:59"
    // that fits its chord by ONE pixel when centred. It is paid for out of the giant's own
    // leading (its band is its ink height, 157 px rather than 210) plus a downward lift of the
    // whole block — the mirror image of GRID4's, and for the mirror reason: what this page needs
    // is width at the TOP, where the giant is, and the empty space it can take it from is at the
    // bottom. Measured at 454 px: the giant's budget goes 364 -> 378 px against the 363 it
    // needs, and the timer's column 306 -> 294 against the 240 a MILD "199:59" needs.
    // 0.9.18 spent the label row on the numbers. Jan's layout review: "drop the word 'timer';
    // make both numbers larger (clock largest, timer second)." The word went because on the
    // DEFAULT page it names a value nothing could mistake — a running m:ss under a time of
    // day is the session timer and reads as one — and the row it cost was an XTINY line
    // between two numbers that both wanted it. The second number takes the band the word
    // vacated, which steps it from a FONT_NUMBER_MILD cell to a FONT_NUMBER_MEDIUM one.
    //
    // The word survives for every OTHER slot. This page's cell is configurable (`pg6s1`), and
    // a bare "148" under a clock could be a heart rate, a pump count or a flight number — so
    // `clockCellNeedsLabel` keeps the label wherever the value is not self-evidently a clock.
    hidden function drawClockPage(dc as Dc, c as SessionController, page as Number,
            foilArc as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var radius = fitRadius(dc, false, foilArc);
        var hN = inkH(dc, Graphics.FONT_NUMBER_THAI_HOT);
        var id = PageModel.slotAt(page, 0);
        var labelled = clockCellNeedsLabel(id);
        var hT = labelled ? dc.getFontHeight(Graphics.FONT_XTINY) : 0;
        var hV = clockCellBand(dc, labelled);
        var bias = clockBias(dc);

        var now = PageModel.clockString();
        var y = clockRowY(cy, hN, hT, hV, 0, bias);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fitFont(dc, NUMBER_FONTS, 0, now,
            rowBudget(radius, y - cy, hN)), now, CV);
        if (id == PageModel.M_NONE) {
            return;
        }
        // battery deliberately absent from the default cell: non-important on the water (Jan)
        var yl = clockRowY(cy, hN, hT, hV, 1, bias);
        var yv = labelled ? yl + (hT + hV) / 2 : yl;
        if (labelled) {
            drawCellLabel(dc, cx, yl, id);
        }
        var value = PageModel.value(id, c);
        dc.setColor(PageModel.color(id, c), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yv, fitGiant(dc, value, clockCellFrom(labelled),
            rowBudget(radius, yv - cy, inkH(dc, clockCellFont(labelled)))), value, CV);
    }

    // Does the cell under the clock still need its word? Only a value that is itself a clock
    // can go without one — the session timer (the shipped default) and a second time of day.
    // Shared with the layout test.
    static function clockCellNeedsLabel(id as Number) as Boolean {
        return !(id == PageModel.M_TIMER || id == PageModel.M_CLOCK
            || id == PageModel.M_FLIGHT_TIMER);
    }

    // The unlabelled cell's value font, and the NUMBER_FONTS rung it is fitted from: one rung
    // up from the labelled cell's FONT_NUMBER_MILD, paid for by the word that is not there.
    static function clockCellFont(labelled as Boolean) as Graphics.FontType {
        return labelled ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_NUMBER_MEDIUM;
    }

    static function clockCellFrom(labelled as Boolean) as Number {
        return labelled ? 3 : 2;
    }

    static function clockCellBand(dc as Dc, labelled as Boolean) as Number {
        return dc.getFontHeight(clockCellFont(labelled));
    }

    // Clock rows: 0 = giant time, 1 = the cell — its label's centre where it has one, its
    // VALUE's centre where it does not. `hN` is the giant's INK height (see heroRowY) and
    // `bias` lifts the whole block DOWNWARD. Shared with the layout test.
    static function clockRowY(cy as Number, hN as Number, hT as Number, hV as Number,
            row as Number, bias as Number) as Number {
        var y = cy - (hN + hT + hV) / 2 + bias + hN / 2;
        if (row == 0) {
            return y;
        }
        return hT > 0 ? y + hN / 2 + hT / 2 : y + hN / 2 + hV / 2;
    }

    // The clock page's downward lift, as a fraction of the glass — GRID_BIAS's opposite number,
    // and scaled the same way. 32 px at 454 sits in the middle of the [21, 52] window in which
    // both the giant keeps THAI_HOT and the timer keeps FONT_NUMBER_MILD.
    static function clockBias(dc as Dc) as Number {
        return dc.getHeight() * CLOCK_BIAS / GRID_REF_PX;
    }

    static function fmtTime(seconds as Float) as String {
        return PageModel.fmtTime(seconds);
    }
}
