import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;
import WingFoilCore;

// The visual half of the on-water alerts (0.9.11, Jan: "neben dem haptischen Feedback auch
// eine visuelle Rückmeldung").
//
// A buzz through a wetsuit hood is easy to miss and impossible to re-read. So every event
// that buzzes also paints: a FLASH — the whole glass takes the event's colour for 1.5 s with
// one glyph and one word on it, pulsing like the PB flash — and then an AFTERGLOW, a strip at
// the top of whatever page is up that keeps the last verdict readable for 20 s. A rider who
// looks down five seconds after the tick still sees "JIBE · flew".
//
// Which events, and how (docs/presentation/watch.md, "The watch's event flash"):
//
//   a resolved turn      flew / touch / fell     full flash, the ladder's own colours
//   a clean jibe         clean                   full flash in the clean-jibe ink; the star
//                                                stays in the strip
//   a dry-streak mark    5, 10, 20, 30 ...       full flash with the number
//   a pumped takeoff     ring only, 0.7 s        frequent, so no word and no afterglow
//   a new longest flight full flash, the duration
//   a speed PB           stays PbFlash's         (effort orange, the value)
//
// NOT here on purpose: straight-line flight ends (the Timeline page shows them), interval
// alerts and the wind lock. Frequent things flashing would turn the glass into noise.
//
// Colour AND shape carry every event — the glyph is the outcome symbol the Turns page already
// uses, the star is the clean jibe's, a number is a number — so it reads on a MIP palette and
// to a rider who cannot tell the ladder's green from its red.
//
// Frame-driven like PbFlash: the position callback is 1 Hz, so a flash living on
// requestUpdate() alone would be one still card. One Timer, allocated once, re-armed rather
// than re-created. State is module-level so paging on and off the map cannot kill it.
//
// One flash at a time: a new event simply restarts the walk with the new kind, which is what
// the rider wants — the newest verdict, not a queue of old ones.
module EventFlash {
    // Between the kind of sweep and its verdict on the afterglow strip. A separator, not a
    // word: docs/copy/watch.json holds the words and this holds the gap between two of them.
    const FLASH_SEP = " · ";

    const FRAME_MS = 100;
    const FRAMES_FULL = 15;        // 15 x 100 ms = 1.5 s
    const FRAMES_RING = 7;         // 0.7 s, the takeoff ring
    const AFTERGLOW_MS = 20000;    // how long the strip keeps the last event

    // Event kinds. Append only — the tests name them.
    enum {
        EV_NONE = 0,
        EV_FLEW = 1,
        EV_TOUCH = 2,
        EV_FELL = 3,
        EV_CLEAN = 4,
        EV_STREAK = 5,
        EV_TAKEOFF = 6,
        EV_LONGEST = 7
    }

    // The flash being drawn.
    var kind as Number = EV_NONE;
    var frame as Number = -1;                          // -1 = idle
    var turnKind as Number = TurnDetector.KIND_NONE;   // jibe / tack / turn, for the strip
    var value as Number = 0;                           // streak count, or longest-flight seconds

    // The afterglow: the last full event, and when it landed.
    var lastKind as Number = EV_NONE;
    var lastTurnKind as Number = TurnDetector.KIND_NONE;
    var lastValue as Number = 0;
    var lastAtMs as Number = 0;

    var _timer as EventFlashTimer? = null;

    // ---- entry points (AlertManager calls these beside the buzzes) ----

    // A resolved turn. A clean jibe is also a fly-through; the clean flash replaces the
    // plain one, exactly as its buzz does.
    function fireTurn(outcome as Number, cleanJibe as Boolean, tKind as Number) as Void {
        var k = EV_FELL;
        if (cleanJibe) {
            k = EV_CLEAN;
        } else if (outcome == TurnDetector.OUTCOME_FLEW) {
            k = EV_FLEW;
        } else if (outcome == TurnDetector.OUTCOME_TOUCHDOWN) {
            k = EV_TOUCH;
        }
        _start(k, tKind, 0);
    }

    function fireStreak(dry as Number) as Void {
        _start(EV_STREAK, TurnDetector.KIND_NONE, dry);
    }

    function fireTakeoff() as Void {
        _start(EV_TAKEOFF, TurnDetector.KIND_NONE, 0);
    }

    function fireLongest(seconds as Number) as Void {
        _start(EV_LONGEST, TurnDetector.KIND_NONE, seconds);
    }

    // Which dry-streak counts are worth a flash: 5, then every ten. Pure, so it is testable.
    function dryMilestone(dry as Number) as Boolean {
        return dry == 5 || (dry >= 10 && dry % 10 == 0);
    }

    function _start(k as Number, tKind as Number, v as Number) as Void {
        if (!AppSettings.visualAlerts) {
            return;
        }
        kind = k;
        turnKind = tKind;
        value = v;
        frame = 0;
        if (k != EV_TAKEOFF) {
            lastKind = k;
            lastTurnKind = tKind;
            lastValue = v;
            lastAtMs = System.getTimer();
        }
        if (_timer == null) {
            _timer = new EventFlashTimer();
        }
        (_timer as EventFlashTimer).arm(FRAME_MS);
        WatchUi.requestUpdate();
    }

    // ---- state the view reads ----

    function active() as Boolean {
        return frame >= 0;
    }

    // The takeoff draws a ring at the bezel and nothing else.
    function isRing() as Boolean {
        return kind == EV_TAKEOFF;
    }

    function frames() as Number {
        return kind == EV_TAKEOFF ? FRAMES_RING : FRAMES_FULL;
    }

    // Is the afterglow strip due at `now` (System.getTimer() ms)?
    function stripActive(now as Number) as Boolean {
        return lastKind != EV_NONE && now - lastAtMs < AFTERGLOW_MS;
    }

    // One frame older. Auto-clears so a flash can never get stuck on screen.
    function tick() as Void {
        if (frame < 0) {
            return;
        }
        frame++;
        if (frame >= frames()) {
            stop();
        }
        WatchUi.requestUpdate();
    }

    // Idempotent: safe from the save/discard path and from the timer itself.
    function stop() as Void {
        frame = -1;
        kind = EV_NONE;
        if (_timer != null) {
            (_timer as EventFlashTimer).disarm();
        }
    }

    // Save and discard end the session's story: the strip goes with it.
    function clearAll() as Void {
        stop();
        lastKind = EV_NONE;
    }

    // ---- colour and words ----

    // The event's own ink: the outcome ladder for the three verdicts (the one place outside
    // the Turns page that may borrow it, because these ARE turn outcomes), the clean-jibe ink
    // for a clean jibe, the phase teal for the two flight events (a takeoff and a longest
    // flight are phase, not verdict), and the ladder's green for a dry streak, which is a run
    // of verdicts.
    function baseColor(k as Number) as Number {
        if (k == EV_FLEW || k == EV_STREAK) {
            return Ink.ladderFlew();
        } else if (k == EV_TOUCH) {
            return Ink.ladderTouchdown();
        } else if (k == EV_FELL) {
            return Ink.ladderFellIn();
        } else if (k == EV_CLEAN) {
            return Ink.cleanJibe();
        }
        return Ink.phaseFlying();
    }

    // Frame parity dims every other frame — the same half-brightness derivation PbFlash uses,
    // so the pulse is one token and its shadow, never a second colour.
    function color() as Number {
        var c = baseColor(kind);
        return frame % 2 == 0 ? c : (c >> 1) & 0x7F7F7F;
    }

    // The word on the flash. Short enough for FONT_LARGE on the narrowest glass.
    // Every word here is docs/copy/watch.json's, loaded once into the globals below.
    function word(k as Number, v as Number) as String {
        if (k == EV_FLEW) {
            return Words.FLASH_FLEW;
        } else if (k == EV_TOUCH) {
            return Words.FLASH_TOUCH;
        } else if (k == EV_FELL) {
            return Words.FLASH_FELL;
        } else if (k == EV_CLEAN) {
            return Words.FLASH_CLEAN;
        } else if (k == EV_STREAK) {
            return v.toString() + Words.FLASH_DRY;
        } else if (k == EV_LONGEST) {
            return Words.FLASH_LONGEST;
        }
        return "";
    }

    function turnLabel(tKind as Number) as String {
        if (tKind == TurnDetector.KIND_JIBE) {
            return Words.FLASH_JIBE;
        } else if (tKind == TurnDetector.KIND_TACK) {
            return Words.FLASH_TACK;
        }
        return Words.FLASH_TURN;
    }

    // The afterglow line: the turn kind with its verdict, or the event by name. The verdict
    // half is the Main page's own tally caption, so one word covers both surfaces.
    function stripText(k as Number, tKind as Number, v as Number) as String {
        if (k == EV_FLEW) {
            return turnLabel(tKind) + FLASH_SEP + Words.TALLY_CAP_FLEW;
        } else if (k == EV_TOUCH) {
            return turnLabel(tKind) + FLASH_SEP + Words.TALLY_CAP_TOUCH;
        } else if (k == EV_FELL) {
            return turnLabel(tKind) + FLASH_SEP + Words.TALLY_CAP_FELL;
        } else if (k == EV_CLEAN) {
            return Words.FLASH_CLEAN_JIBE;
        } else if (k == EV_STREAK) {
            return v.toString() + Words.FLASH_DRY;
        } else if (k == EV_LONGEST) {
            return Words.FLASH_LONGEST + " " + mmss(v);
        }
        return "";
    }

    function mmss(seconds as Number) as String {
        var m = seconds / 60;
        var s = seconds % 60;
        return m.toString() + ":" + s.format("%02d");
    }
}

// Owns the one Timer. A class, because `method(:sym)` binds to `self` and a module is not a
// reliable `self` for a Timer callback (same shape as PbFlashTimer).
class EventFlashTimer {
    hidden var _t as Timer.Timer;

    function initialize() {
        _t = new Timer.Timer();
    }

    function arm(ms as Number) as Void {
        _t.stop();
        _t.start(method(:onFrame), ms, true);
    }

    function disarm() as Void {
        _t.stop();
    }

    function onFrame() as Void {
        EventFlash.tick();
    }
}
