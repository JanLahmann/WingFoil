import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import WingFoilCore;

// Vibration alerts (primary on-water channel — tones are inaudible in wind).
// Global 5 s debounce; per-alert enables live in AppSettings.
module AlertManager {
    const DEBOUNCE_MS = 5000;
    var _lastMs as Number = 0;

    function _fire(profiles as Array) as Void {
        var now = System.getTimer();
        if (now - _lastMs < DEBOUNCE_MS) {
            return;
        }
        _lastMs = now;
        if (Attention has :vibrate) {
            Attention.vibrate(profiles as Array<Attention.VibeProfile>);
        }
    }

    // New 2 s / 10 s speed PB: double short buzz
    function speedPb() as Void {
        if (AppSettings.alertPb) {
            _fire([
                new Attention.VibeProfile(100, 200),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(100, 200)
            ]);
        }
    }

    // New longest flight: one long buzz
    function longestFlight() as Void {
        if (AppSettings.alertFlight) {
            _fire([new Attention.VibeProfile(100, 600)]);
        }
    }

    // Time/distance interval reached: one medium buzz, distinct from the PB double and the
    // longest-flight long buzz.
    function interval() as Void {
        _fire([new Attention.VibeProfile(75, 300)]);
    }

    // A pumped takeoff attempt just worked: short-then-long, the "up and away" shape. Only
    // fires for attempts (>= pumpMinStrokes of real pumping) — a free takeoff in enough wind
    // is not an achievement the rider needs told about, and buzzing every flight would make
    // the channel noise.
    function takeoff() as Void {
        if (AppSettings.alertTakeoff) {
            _fire([
                new Attention.VibeProfile(50, 150),
                new Attention.VibeProfile(0, 80),
                new Attention.VibeProfile(100, 350)
            ]);
        }
    }

    // Turn outcome resolved. Distinct rhythms so the verdict is readable without looking:
    // flew through = one crisp tick, touchdown = two soft ticks, fell in = three hard ticks.
    function turnOutcome(outcome as Number) as Void {
        if (!AppSettings.alertTurn) {
            return;
        }
        if (outcome == TurnDetector.OUTCOME_FLEW) {
            _fire([new Attention.VibeProfile(75, 120)]);
        } else if (outcome == TurnDetector.OUTCOME_TOUCHDOWN) {
            _fire([
                new Attention.VibeProfile(50, 100),
                new Attention.VibeProfile(0, 120),
                new Attention.VibeProfile(50, 100)
            ]);
        } else {
            _fire([
                new Attention.VibeProfile(100, 150),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 150),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 150)
            ]);
        }
    }
}
