import Toybox.Lang;

// What the takeoff you just did cost in heartbeats.
// Watch twin of lab/src/wingfoil_lab/hrcost.py (docs/algorithms.md "HR cost"), and the same
// kind of cheap live approximation every other watch metric is: the phone joins the whole
// heart_rate channel to the takeoff runs after the fact, this follows one window at a time,
// forward, at 1 Hz, and keeps exactly one number.
//
// The anchor is the START OF THE EFFORT — the instant PumpDetector opens an attempt — not the
// moment he got up. Anchoring on the flight start would read a baseline taken *during* the
// pumping (already elevated) and then charge the takeoff for the first half-minute of flying;
// the lab measures 7.9 bpm that way against 6.9 from the effort anchor, and only the second
// number answers "what did this attempt cost".
//
// Deviations from the lab, all of them in the direction of showing a dash rather than a guess:
//   * the baseline is the single sample at the anchor, not the median of the 10 s before it —
//     there is no ring buffer of past HR here, and a watch that has to choose between one
//     sample and no metric shows the one sample.
//   * coverage is not computed. A hole inside the window can only hide a HIGHER peak than the
//     one seen, so a cost read across a dropout is biased low, never high — it under-sells the
//     takeoff, which is the harmless direction.
//   * the window is 30 s of ACTIVITY time: a GPS gap freezes MetricsEngine's whole tick, so
//     the clock stops with it rather than expiring the window while the record is broken.
const HR_COST_PEAK_WINDOW_S = 30.0;   // hrCostPeakWindow: optical HR trails effort 10-20 s
const HR_COST_MIN_RISE_BPM = 5;       // hrMinRise: below this there was no rise to charge for
const HR_COST_MIN_BPM = 30;           // hrMinBpm
const HR_COST_MAX_BPM = 220;          // hrMaxBpm: outside the band is sensor garbage, not a heart

class HrCostTracker {
    // Last measured takeoff cost, bpm. -1 = nothing measurable yet, the same "no value"
    // sentinel PumpDetector.lastPumpsToTakeoff uses; PageModel turns it into "--".
    // A published value is always >= HR_COST_MIN_RISE_BPM, so no real cost can look like it.
    var lastCostBpm as Number = -1;

    hidden var _open as Boolean = false;      // a window is being followed
    hidden var _wasEffort as Boolean = false; // effort state at the previous tick
    hidden var _elapsedS as Float = 0.0;      // activity seconds since the anchor
    hidden var _startBpm as Number = 0;       // HR he brought into the effort
    hidden var _peakBpm as Number = 0;        // highest plausible HR since
    hidden var _succeeded as Boolean = false; // this effort produced a confirmed flight

    // One 1 Hz sample, from MetricsEngine.
    //   hr          Activity.Info.currentHeartRate — null whenever the optical sensor, under a
    //               wetsuit sleeve in cold water, has lost the wrist. That is not rare.
    //   effortOpen  PumpDetector.attemptOpen(): the rider is pumping and has not got up yet.
    //   takeoff     this tick carried PumpDetector.EVENT_TAKEOFF.
    function tick(dt as Float, hr as Number?, effortOpen as Boolean,
            takeoff as Boolean) as Void {
        var bpm = _plausible(hr) ? hr as Number : 0;

        // A fresh effort re-anchors. If the previous window had already got its flight, it is
        // finalised with the peak seen so far rather than thrown away: he is pumping again, so
        // whatever his heart does from here belongs to the NEXT attempt.
        if (effortOpen && !_wasEffort) {
            _finish();
            _open = bpm > 0;      // no heart rate at the anchor, no baseline, no metric
            _elapsedS = 0.0;
            _startBpm = bpm;
            _peakBpm = bpm;
            _succeeded = false;
        }
        _wasEffort = effortOpen;

        if (!_open) {
            return;
        }
        if (takeoff) {
            _succeeded = true;
        }
        if (bpm > _peakBpm) {
            _peakBpm = bpm;
        }
        // The window deliberately keeps running past the takeoff: the peak that the pumping
        // produced arrives 10-20 s after it (measured median lag 20.5 s), so publishing at
        // ON_FOIL would price every takeoff at close to nothing.
        _elapsedS += dt;
        if (_elapsedS >= HR_COST_PEAK_WINDOW_S) {
            _finish();
        }
    }

    // Closes the window. Only a SUCCESSFUL effort with a real rise leaves a number behind — a
    // failed attempt is not a takeoff, and a rise under hrMinRise is sensor noise wearing a
    // takeoff's clothes.
    hidden function _finish() as Void {
        if (_open && _succeeded) {
            var rise = _peakBpm - _startBpm;
            if (rise >= HR_COST_MIN_RISE_BPM) {
                lastCostBpm = rise;
            }
        }
        _open = false;
        _succeeded = false;
    }

    hidden function _plausible(hr as Number?) as Boolean {
        if (hr == null) {
            return false;
        }
        var b = hr as Number;
        return b >= HR_COST_MIN_BPM && b <= HR_COST_MAX_BPM;
    }

    // True while a window is still following the peak — the display never needs it, but a
    // test does, and so does anyone wondering why the number has not moved yet.
    function windowOpen() as Boolean {
        return _open;
    }
}
