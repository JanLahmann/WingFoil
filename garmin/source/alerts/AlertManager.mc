import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import WingFoilCore;

// Vibration alerts (primary on-water channel — tones are inaudible in wind).
// Per-CHANNEL debounce plus a short global floor; per-alert enables live in AppSettings.
//
// This used to be one module-level timestamp shared by every alert type, and that quietly
// destroyed the thing the vibe patterns were designed for. The three turn-outcome rhythms
// (`turnOutcome` below: one crisp tick / two soft ticks / three hard ticks) are the only way
// a rider learns his verdict without looking — and a speed PB four seconds before the jibe
// swallowed the verdict entirely. Coming out of a fast jibe, a PB and a turn outcome landing
// within five seconds of each other is not an edge case, it is the normal case.
//
// So: each channel keeps its own 5 s window, which is what "don't repeat yourself" was ever
// meant to say, and a 1 s global floor keeps two different alerts from overlapping into
// mush. Total vibes stay bounded — at most one per second, at most one per channel per five.
module AlertManager {
    const DEBOUNCE_MS = 5000;
    // Nothing buzzes within this of anything else, whatever channel it is on: two profiles
    // playing at once is one unreadable buzz, not two alerts.
    const GLOBAL_FLOOR_MS = 1000;

    // Channels. Append only — the array below is indexed by these.
    enum {
        CH_PB = 0,
        CH_FLIGHT = 1,
        CH_INTERVAL = 2,
        CH_TAKEOFF = 3,
        CH_TURN = 4,
        CH_WIND = 5,
        CH_COUNT = 6
    }

    var _lastMs as Array<Number> = [0, 0, 0, 0, 0, 0];
    var _lastAnyMs as Number = 0;

    // Pure decision half, so the debounce rules are testable without a vibration motor.
    // `lastCh` / `lastAny` are the two timestamps; returns true when the alert may play.
    function allows(now as Number, lastCh as Number, lastAny as Number) as Boolean {
        return now - lastCh >= DEBOUNCE_MS && now - lastAny >= GLOBAL_FLOOR_MS;
    }

    function _fire(ch as Number, profiles as Array) as Void {
        var now = System.getTimer();
        // A fresh boot reads 0 for every channel, which `allows` would treat as "buzzed at
        // t=0" — harmless, because System.getTimer() starts well past DEBOUNCE_MS.
        if (!allows(now, _lastMs[ch], _lastAnyMs)) {
            return;
        }
        _lastMs[ch] = now;
        _lastAnyMs = now;
        if (Attention has :vibrate) {
            Attention.vibrate(profiles as Array<Attention.VibeProfile>);
        }
    }

    // Test seam: the suite drives the channels without waiting five real seconds.
    function reset() as Void {
        for (var i = 0; i < CH_COUNT; i++) {
            _lastMs[i] = 0;
        }
        _lastAnyMs = 0;
    }

    // New 2 s / 10 s speed PB: double short buzz
    function speedPb() as Void {
        if (AppSettings.alertPb) {
            _fire(CH_PB, [
                new Attention.VibeProfile(100, 200),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(100, 200)
            ]);
        }
    }

    // New longest flight: one long buzz
    function longestFlight() as Void {
        if (AppSettings.alertFlight) {
            _fire(CH_FLIGHT, [new Attention.VibeProfile(100, 600)]);
        }
    }

    // Time/distance interval reached: one medium buzz, distinct from the PB double and the
    // longest-flight long buzz.
    function interval() as Void {
        _fire(CH_INTERVAL, [new Attention.VibeProfile(75, 300)]);
    }

    // A pumped takeoff attempt just worked: short-then-long, the "up and away" shape. Only
    // fires for attempts (>= pumpMinStrokes of real pumping) — a free takeoff in enough wind
    // is not an achievement the rider needs told about, and buzzing every flight would make
    // the channel noise.
    function takeoff() as Void {
        if (AppSettings.alertTakeoff) {
            _fire(CH_TAKEOFF, [
                new Attention.VibeProfile(50, 150),
                new Attention.VibeProfile(0, 80),
                new Attention.VibeProfile(100, 350)
            ]);
        }
    }

    // The watch worked out the wind axis for itself and adopted it: two rising ticks, the
    // "something is now known" shape, on a channel of its own so it can never be swallowed by
    // a turn verdict or a PB landing in the same five seconds (the reason channels exist at
    // all — see the header). It fires ONCE per session by construction: only the first lock
    // sends EV_LOCK, and every later re-evaluation is a silent update.
    //
    // Deliberately not behind a toggle: `autoWind` already is the toggle, and a rider who
    // leaves it on wants to know the moment the Turns page starts saying tack and jibe.
    function autoWindLocked() as Void {
        _fire(CH_WIND, [
            new Attention.VibeProfile(50, 120),
            new Attention.VibeProfile(0, 90),
            new Attention.VibeProfile(100, 200)
        ]);
    }

    // Turn outcome resolved. Distinct rhythms so the verdict is readable without looking:
    // flew through = one crisp tick, touchdown = two soft ticks, fell in = three hard ticks.
    function turnOutcome(outcome as Number) as Void {
        if (!AppSettings.alertTurn) {
            return;
        }
        if (outcome == TurnDetector.OUTCOME_FLEW) {
            _fire(CH_TURN, [new Attention.VibeProfile(75, 120)]);
        } else if (outcome == TurnDetector.OUTCOME_TOUCHDOWN) {
            _fire(CH_TURN, [
                new Attention.VibeProfile(50, 100),
                new Attention.VibeProfile(0, 120),
                new Attention.VibeProfile(50, 100)
            ]);
        } else {
            _fire(CH_TURN, [
                new Attention.VibeProfile(100, 150),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 150),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 150)
            ]);
        }
    }
}
