import Toybox.Lang;

module WingFoilCore {

// Session distance, built from the firmware odometer but never trusting it wholesale.
//
// Activity.Info.elapsedDistance is a reading, not an increment, and it teleports: a fix
// recovered far from where it was lost books the entire gap into one tick. The simulator does
// the extreme version on every FIT replay — playback opens at the simulator's default location
// and jumps to the clip's, which put 37 986 km on the session page — and a watch does the same
// thing in miniature every time GPS returns after a swim.
//
// So the reading is used only for its step, and a step no speed could have covered is replaced
// by the Doppler integral over the same tick, which is bounded by construction. Both consumers
// (device app and data field) accumulate through this, so they cannot drift apart.
class Odometer {
    hidden var _last as Float = 0.0;
    hidden var _have as Boolean = false;

    // Distance to add for this tick. `reading` is elapsedDistance, `doppler` the speed
    // integral over the same tick. The first reading only sets the origin — an odometer that
    // is already at 9 km when we join (a clip cut out of a longer session) is not distance we
    // travelled.
    function step(reading as Float, doppler as Float, dt as Float) as Float {
        var d = _have ? gate(reading - _last, doppler, dt) : doppler;
        _last = reading;
        _have = true;
        return d;
    }

    // The pure decision, so the tests can drive every case without an activity.
    // 3x the Doppler distance leaves room for the firmware's own smoothing; the 10 m/s term
    // keeps a stationary tick from rejecting the metre the odometer really moved.
    static function gate(step as Float, doppler as Float, dt as Float) as Float {
        if (step < 0.0 || step > 3.0 * doppler + 10.0 * dt) {
            return doppler;
        }
        return step;
    }
}

}
