import Toybox.Lang;

// Live 2 s / 10 s peak speeds from 1 Hz Doppler samples (W1 scope; 5x10s/500m/alpha in phase 3).
class SpeedRecords {
    enum {
        PB_NONE = 0,
        PB_2S = 1,
        PB_10S = 2
    }

    hidden var _win2 as RingBuffer;
    hidden var _win10 as RingBuffer;
    var best2sMps as Float = 0.0;
    var best10sMps as Float = 0.0;

    function initialize() {
        _win2 = new RingBuffer(2);
        _win10 = new RingBuffer(10);
    }

    // Returns bitmask of PB_* events for this sample.
    function tick(speedMps as Float) as Number {
        var events = PB_NONE;
        _win2.push(speedMps);
        _win10.push(speedMps);
        if (_win2.isFull()) {
            var m = _win2.mean();
            if (m > best2sMps) {
                best2sMps = m;
                events |= PB_2S;
            }
        }
        if (_win10.isFull()) {
            var m = _win10.mean();
            if (m > best10sMps) {
                best10sMps = m;
                events |= PB_10S;
            }
        }
        return events;
    }

    // GPS gap / pause: windows must not average across the discontinuity.
    function onGap() as Void {
        _win2.reset();
        _win10.reset();
    }
}
