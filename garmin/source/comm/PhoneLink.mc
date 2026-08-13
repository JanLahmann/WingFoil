import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import WingFoilCore;

// The watch half of the phase-5 companion link (docs/plan.md §"Phase 5 — Companion link").
//
// WHAT THIS IS FOR. A saved session reaches the phone twice. The FIT is authoritative but
// slow: it waits for a Garmin Connect sync, and on a beach with one bar that can be an hour.
// This module sends the *card* — the twenty numbers the phone's session list wants to draw
// immediately — over the BLE link to the companion app, seconds after the rider presses Save.
// The FIT still arrives later and still wins on every number it carries.
//
// WHY IT IS TINY. Communications.transmit is a notification channel, not a transport. Garmin's
// own guidance is to keep messages as small as possible; the plan's 10 KB is the ceiling the
// radio tolerates, not a budget to spend. So: integer values only (speeds in cm/s, times in
// whole seconds, percentages 0-100), two-character keys, no strings, no floats. A realistic
// full session encodes to roughly 200 bytes. The FIT carries everything else.
//
// WHY FAILURE IS THE NORMAL CASE. transmit only succeeds when the phone is in range AND the
// companion app is alive to receive. The phone in a car at the top of the beach, the app
// swiped away, Bluetooth off after a flight — all routine. So a send that fails is not an
// error to log and forget: the payload stays in Storage and is retried at app start and on the
// edge where the phone becomes reachable again.
//
// WHY ONE PENDING SLOT AND NOT A QUEUE. A rider who does three sessions with the phone in the
// car should get the newest card when the link comes back, not three cards replayed oldest
// first with the interesting one last. Newest wins: a new summary overwrites the slot. The
// older sessions are not lost — their FITs sync as usual and the phone builds the real cards
// from those. The slot is a shortcut, and a shortcut nobody took is worth nothing.
module PhoneLink {

    // Bump when a key's meaning changes. The phone refuses payloads it does not know how to
    // read, so an old app paired with a new watch shows nothing rather than wrong numbers.
    const SCHEMA = 1;

    // Single pending slot (see the header). Storage, not Properties: this is app state, not a
    // user setting, and it must not appear in Garmin Connect.
    const STORE_PENDING = "plPend";

    // ---- payload keys ----
    // Two characters each, except the schema tag, which is the one single-character key and
    // is reserved that shape so a reader can pick it out at a glance.
    //
    // It is written first in the literal below, but do NOT rely on it arriving first:
    // Monkey C Dictionary.keys() returns hash order, not insertion order, and the payload is
    // handed to the iOS companion as an unordered dictionary regardless. Key order is not
    // something either side can observe, so the phone reads the version BY KEY before it
    // interprets anything else, and refuses a schema it does not know.
    const KEY_VERSION = "v";
    // THE DEDUPE KEY: start time + duration.
    //
    // The phone reconciles this card with the real FIT when it finally syncs, by matching
    // these two numbers against the FIT session message. They must therefore mean EXACTLY what
    // the FIT means, or reconciliation misses and the rider sees the same session twice —
    // silently, because nothing on either side can tell a duplicate from two back-to-back
    // sessions.
    //   KEY_START = FIT session start_time, as UNIX epoch seconds. Sampled by
    //               SessionController the moment ActivityRecording.Session.start() is called,
    //               which is the instant the FIT stamps.
    //   KEY_DUR   = FIT session total_elapsed_time, in whole seconds: wall-clock start to
    //               save, INCLUDING paused time. Not total_timer_time, and not the engine's
    //               timerS (which is timer time and stops on pause). SessionController reads
    //               it from Activity.Info.elapsedTime at save.
    // Change either side of that and you must change the other one with it.
    const KEY_START = "st";
    const KEY_DUR = "du";
    const KEY_FOIL_TIME = "ft";
    const KEY_FOIL_PCT = "fp";
    const KEY_FLIGHTS = "fc";
    const KEY_LONGEST_S = "ls";
    const KEY_LONGEST_M = "lm";
    const KEY_DIST_M = "ds";
    const KEY_BEST_2S = "b2";
    const KEY_BEST_10S = "bt";
    const KEY_TURNS = "tn";
    const KEY_TACKS = "tk";
    const KEY_JIBES = "jb";
    const KEY_FLEW = "of";
    const KEY_TOUCHDOWN = "ot";
    const KEY_FELL = "ox";
    const KEY_TAKEOFF_ATT = "ka";
    const KEY_TAKEOFF_OK = "ks";
    const KEY_WIND = "wd";
    const KEY_APP = "av";

    // Inbound: the phone's wind push. Same encoding as KEY_WIND — degrees the wind blows
    // FROM, or -1 to clear.
    const KEY_IN_WIND = "wd";

    // What the radio is allowed to cost. Garmin's ceiling is far higher; this is the number
    // that keeps the message a notification. estimateBytes() is asserted against it in tests,
    // computed from the actual payload, so adding a key that blows the budget fails the build
    // rather than a rider's Bluetooth stack.
    const BUDGET_BYTES = 1024;

    // ---- the transmit seam ----
    // Communications.transmit needs a paired phone running the companion app, which no test
    // rig has and no simulator provides. Everything above the radio — payload shape, budget,
    // the pending slot, the success/failure branches — is the part that can actually be wrong,
    // so the one line that touches the radio lives behind this object and tests swap in a
    // stand-in that reports success or failure on demand. The seam is one virtual call on a
    // path that runs once per session; it costs nothing and it is the difference between this
    // module being tested and being hoped about.
    class Radio {
        function initialize() {
        }

        function send(payload as Dictionary, listener as Communications.ConnectionListener)
                as Void {
            Communications.transmit(payload, null, listener);
        }
    }

    var radio as Radio = new Radio();

    // Outcome of the last send attempt. lastSendOk is the one tests and callers ask about;
    // lastError keeps the raw Communications constant (UNKNOWN_ERROR, BLE_ERROR,
    // BLE_HOST_TIMEOUT, ...) beside it, which is diagnostic only — those constants include a
    // zero, so "no error" is not a value you can read off a number.
    var lastSendOk as Boolean = false;
    var lastError as Number = 0;

    // Last known link state, for the connected-edge retry. Module scope, not `hidden`:
    // Monkey C only accepts `hidden` on class members, not on module variables.
    var _wasConnected as Boolean = false;

    // ---- registration ----

    // TWO PLATFORM TRAPS ARE FROZEN INTO THE SHAPE OF THIS CLASS. Both were found by the
    // fenix 7 build of the unit-test suite refusing to start at all — no exception, no log
    // line, no first view, just a simulator that stops answering. Neither is visible on
    // fenix 8, which is the machine this app is developed on.
    //
    // 1. THE CALLBACK MUST BELONG TO AN OBJECT, NOT TO THIS MODULE. `method(:x)` is
    //    class-scoped in Monkey C and does not exist inside a module, so the obvious way to
    //    hand a module function to Communications is `new Lang.Method(PhoneLink, :onPhone-
    //    Message)`. That compiles clean and works on fenix 8; on the fenix 7 family it wedges
    //    the runtime. Bound to a class instance it is fine everywhere. Hence this class.
    //
    // 2. registerForPhoneAppMessageErrors IS NOT CALLED AT ALL. It is documented, it is
    //    present in the API, it compiles — and on the fenix 7 family that single call is
    //    enough on its own to stop the app from ever starting (isolated: registering ONLY the
    //    error callback reproduces it; registering ONLY the message callback does not).
    //    `Communications has :registerForPhoneAppMessageErrors` is TRUE on those devices, so
    //    a capability guard would not have saved anything.
    //
    //    Nothing is lost by dropping it. That callback reports trouble on the INBOUND
    //    channel, which the watch can do nothing about anyway; the failure that actually
    //    matters — a summary that did not reach the phone — arrives on
    //    ConnectionListener.onError below, and that is what keeps the pending slot alive.
    class Callbacks {
        function initialize() {
        }

        // Registers itself, because `method(:x)` must be evaluated inside the class that
        // owns the function for the binding the fenix 7 runtime accepts.
        function register() as Void {
            try {
                Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
            } catch (e) {
            }
        }

        // Untrusted input from another process on another device: nothing is believed, and a
        // malformed push is dropped in silence. The deciding is done by applyMessage below,
        // which a test can call; this is one property read and a hand-off.
        function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
            try {
                applyMessage(msg.data);
            } catch (e) {
            }
        }
    }

    var callbacks as Callbacks = new Callbacks();

    // Called once at app start. Both callbacks are cheap to hold and there is no unregister
    // worth doing: the app owning them is the app being killed.
    function register() as Void {
        callbacks.register();
        _wasConnected = phoneReachable();
    }

    // ---- outbound ----

    // The card, built on demand and never held: it is handed straight to Storage and the
    // reference dropped. Twenty-one Numbers is nothing, but the device app already carries
    // detectors, a 256-slot history and a 128-point track in 768 KB, and a summary kept live
    // "in case" would be pure waste.
    //
    // Every value is a Lang.Number. Floats are converted at the boundary here, once, so the
    // phone never has to guess whether 12.0 meant 12 or 12.04.
    function summary(c as SessionController) as Dictionary {
        var e = c.engine;
        var d = e.detector;
        var t = e.turns;
        var p = e.pump;
        var pct = c.elapsedS > 0 ? (d.foilTimeS / c.elapsedS * 100.0).toNumber() : 0;
        if (pct > 100) {
            pct = 100;
        }
        if (pct < 0) {
            pct = 0;
        }
        return {
            KEY_VERSION => SCHEMA,
            KEY_START => c.startEpochS,
            KEY_DUR => c.elapsedS,
            KEY_FOIL_TIME => d.foilTimeS.toNumber(),
            KEY_FOIL_PCT => pct,
            KEY_FLIGHTS => d.flightCount,
            KEY_LONGEST_S => d.longestS.toNumber(),
            KEY_LONGEST_M => d.longestM.toNumber(),
            KEY_DIST_M => e.distM.toNumber(),
            KEY_BEST_2S => (e.records.best2sMps * 100.0).toNumber(),
            KEY_BEST_10S => (e.records.best10sMps * 100.0).toNumber(),
            KEY_TURNS => t.turnCount,
            KEY_TACKS => t.tackCount,
            KEY_JIBES => t.jibeCount,
            KEY_FLEW => t.flewCount,
            KEY_TOUCHDOWN => t.touchdownCount,
            KEY_FELL => t.fellCount,
            KEY_TAKEOFF_ATT => p.attempts(),
            KEY_TAKEOFF_OK => p.successes,
            KEY_WIND => AppSettings.cfg.windDirection,
            KEY_APP => FitSchema.APP_MINOR * 256 + FitSchema.SCHEMA_VERSION
        } as Dictionary;
    }

    // Encoded size of a payload, in bytes, as the message encoder would spend them: a type
    // byte plus a length byte plus the characters for each key, a type byte plus a 32-bit
    // integer for each value, and a small container header. Deliberately an over-estimate —
    // the point is a ceiling that cannot be crossed by accident, not a byte-exact figure.
    function estimateBytes(payload as Dictionary) as Number {
        var keys = payload.keys();
        var n = 4;                          // container tag + entry count
        for (var i = 0; i < keys.size(); i++) {
            var k = keys[i];
            n += 2 + (k instanceof Lang.String ? (k as String).length() : 8);
            var v = payload[k];
            n += v instanceof Lang.Number ? 5 : 16;   // 16 = "not a Number", i.e. expensive
        }
        return n;
    }

    // Called after a session is saved. Stashes the card in the pending slot (newest wins) and
    // tries the radio once. A false return means "not on the phone yet", which is a normal
    // Tuesday, not a failure the rider needs to hear about.
    function sendSummary(c as SessionController) as Boolean {
        if (!AppSettings.phonePush) {
            return false;
        }
        stash(summary(c));
        return send();
    }

    // Transmit whatever is in the pending slot. Safe to call at any time: no slot, push
    // disabled or no phone means it returns false without touching the radio.
    function send() as Boolean {
        if (!AppSettings.phonePush) {
            return false;
        }
        var p = pending();
        if (p == null) {
            return false;
        }
        try {
            radio.send(p as Dictionary, new PhoneLink.Listener());
            return true;
        } catch (e) {
            // The radio refused outright (BLE off, no companion registered). The slot stays.
            onSendFail(Communications.UNKNOWN_ERROR);
            return false;
        }
    }

    // The link came back. Called on the connected edge rather than every second, so a rider
    // sitting on the start screen with no phone costs one Boolean compare per position fix.
    function pollLink() as Void {
        var now = phoneReachable();
        if (now && !_wasConnected) {
            send();
        }
        _wasConnected = now;
    }

    function phoneReachable() as Boolean {
        try {
            var s = System.getDeviceSettings();
            return s.phoneConnected;
        } catch (e) {
            return false;
        }
    }

    // ---- the pending slot ----

    function pending() as Dictionary? {
        try {
            var v = Storage.getValue(STORE_PENDING);
            return v instanceof Lang.Dictionary ? v as Dictionary : null;
        } catch (e) {
            return null;
        }
    }

    // Newest wins: one key, overwritten. See the module header for why this is not a queue.
    function stash(payload as Dictionary) as Void {
        try {
            Storage.setValue(STORE_PENDING, payload);
        } catch (e) {
        }
    }

    function clearPending() as Void {
        try {
            Storage.deleteValue(STORE_PENDING);
        } catch (e) {
        }
    }

    // ---- send outcome ----

    function onSendOk() as Void {
        lastSendOk = true;
        lastError = 0;
        clearPending();     // the phone has it; the shortcut has done its job
    }

    function onSendFail(err as Number) as Void {
        lastSendOk = false;
        lastError = err;
        // Slot deliberately untouched: retried at next app start or on the connected edge.
    }

    class Listener extends Communications.ConnectionListener {
        function initialize() {
            ConnectionListener.initialize();
        }

        function onComplete() as Void {
            PhoneLink.onSendOk();
        }

        function onError() as Void {
            PhoneLink.onSendFail(Communications.UNKNOWN_ERROR);
        }
    }

    // ---- inbound: the phone's wind push ----

    // The message body, split from Callbacks.onPhoneMessage because
    // Communications.PhoneAppMessage has no public constructor and so cannot be fabricated in
    // a test. Everything that decides anything lives here; the callback is one property read.
    function applyMessage(data as Object?) as Boolean {
        if (!(data instanceof Lang.Dictionary)) {
            return false;
        }
        return applyWind((data as Dictionary)[KEY_IN_WIND]);
    }

    // The validation, split out so it can be driven without a Message: the phone may only set
    // an integer bearing 0..359, or -1 to clear. A Float, a String, a Boolean, null, 360, -2 —
    // all rejected, because a bad wind axis does not fail loudly, it just relabels every tack
    // as a jibe for the rest of the session.
    //
    // Accepted values go through AppSettings.storeWindDirection, the SAME path the on-water
    // wind menu uses (RecordingDelegate -> WindMenu), so the push lands in WingFoilCore.Config
    // for the live TurnDetector, in the FIT's session wind field, and in Properties so it
    // survives a restart. Returns whether it was taken.
    function applyWind(v as Object?) as Boolean {
        if (!(v instanceof Lang.Number)) {
            return false;
        }
        var deg = v as Number;
        if (deg < -1 || deg > 359) {
            return false;
        }
        AppSettings.storeWindDirection(deg);
        return true;
    }

}
