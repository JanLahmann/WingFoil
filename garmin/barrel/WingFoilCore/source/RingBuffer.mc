import Toybox.Lang;

module WingFoilCore {

// Fixed-size Float ring with maintained running sum -> O(1) windowed mean.
class RingBuffer {
    hidden var _buf as Array<Float>;
    hidden var _size as Number;
    hidden var _idx as Number = 0;
    hidden var _count as Number = 0;
    hidden var _sum as Float = 0.0;

    function initialize(size as Number) {
        _size = size;
        _buf = new Array<Float>[size];
        for (var i = 0; i < size; i++) {
            _buf[i] = 0.0;
        }
    }

    function push(v as Float) as Void {
        if (_count == _size) {
            _sum -= _buf[_idx];
        } else {
            _count++;
        }
        _buf[_idx] = v;
        _sum += v;
        _idx = (_idx + 1) % _size;
    }

    function isFull() as Boolean {
        return _count == _size;
    }

    function mean() as Float {
        return _count > 0 ? _sum / _count : 0.0;
    }

    function reset() as Void {
        _idx = 0;
        _count = 0;
        _sum = 0.0;
    }
}

}
