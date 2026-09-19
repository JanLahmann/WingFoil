import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// The direct transfer, watch side (0.9.14-dev2). docs/transfer-format.md is the contract;
// lab/tools/cjr_ref.py is the reference the bytes are tested against. Dev stream only: the
// (:notdev) stubs below are what the beta and the release compile.
//
// Two things live here. The ENCODER turns every GPS fix of a recording into a record of the
// `rec.v1` stream — a 22-byte keyframe or a 13-byte delta — and closes a page whenever the
// next record would not fit in 8 000 bytes. The SENDER moves closed pages to the phone one
// at a time: transmit, wait for `onComplete`, wait for the phone's `cjrAck`, next. The probe
// of 19 September 2026 fixed those two rules by crashing the app on a 16 KB page and on two
// pages in flight (docs/direct-transfer.md §5); nothing here is allowed to forget them.
//
// Memory. Pages stay resident, acknowledged or not, until the phone's empty `cjrNeed` says
// the stream is whole — a two-hour session is thirteen pages, 104 KB, of the 786 KB heap.
// The one page buffer is allocated once at start and sliced on close.
module DirectSend {

    const PAGE_BYTES = 8000;
    const KEYFRAME_EVERY = 60;
    const DT_MAX = 254;
    const KEYFRAME_TAG = 0xFF;
    const ALT_NONE = 0x7FFF;
    const SCHEMA = 1;
    const STREAM_RECORD = 0;
    const HEADER_BYTES = 16;
    const KEYFRAME_BYTES = 22;
    const DELTA_BYTES = 13;
    const ACK_TIMEOUT_MS = 6000;
    const RETRIES = 3;
    const PERSIST_MAX = 10;

    const KEY_MSG = "cjr";
    const KEY_SID = "sid";
    const KEY_STREAM = "st";
    const KEY_PAGE = "p";
    const KEY_COUNT = "n";
    const KEY_END = "e";
    const KEY_BYTES = "b";
    const KEY_ACK = "cjrAck";
    const KEY_NEED = "cjrNeed";

    const STORE_IDX = "cjrIdx";
    const STORE_PAGE = "cjrP";

    // ---- the stubs every other build compiles ----

    (:notdev)
    function begin(startEpochS as Number, windDir as Number) as Void {
    }

    (:notdev)
    function record(info as Position.Info, speedMps as Float, hr as Number?,
                    foil as Number, cadence as Number, marker as Number,
                    tick as Number) as Void {
    }

    (:notdev)
    function finish() as Void {
    }

    (:notdev)
    function pump() as Void {
    }

    (:notdev)
    function applyMessage(d as Dictionary) as Boolean {
        return false;
    }

    (:notdev)
    function persist() as Void {
    }

    (:notdev)
    function restore() as Void {
    }

    (:notdev)
    function statusLine() as String? {
        return null;
    }

    (:notdev)
    function discard() as Void {
    }

    // ---- state (dev) ----

    (:dev) var _buf as ByteArray?;           // the open page
    (:dev) var _len as Number = 0;
    (:dev) var _pages as Array<ByteArray> = [] as Array<ByteArray>;   // closed, index = page
    (:dev) var _acked as Array<Boolean> = [] as Array<Boolean>;
    (:dev) var _sid as Number = 0;
    (:dev) var _ended as Boolean = false;
    (:dev) var _recording as Boolean = false;
    (:dev) var _sinceKey as Number = KEYFRAME_EVERY;
    (:dev) var _qlat as Number = 0;          // 1e-7 degrees, the tracked state
    (:dev) var _qlon as Number = 0;
    (:dev) var _prevT as Number = 0;
    (:dev) var _prevAlt as Number = ALT_NONE;
    (:dev) var _inFlight as Number = -1;     // page index on the radio, -1 = none
    (:dev) var _awaitingAck as Boolean = false;
    (:dev) var _attempts as Number = 0;
    (:dev) var _timer as Timer.Timer?;
    (:dev) var _sentOk as Number = 0;        // pages the phone acknowledged, for the status line
    (:dev) var _lastMs as Number = 0;
    (:dev) var _partial as Boolean = false;  // persisted with pages dropped
    (:dev) var reachableOverride as Boolean? = null;   // tests: the simulator has no phone

    // ---- the encoder ----

    (:dev)
    function begin(startEpochS as Number, windDir as Number) as Void {
        if (!AppSettings.phonePush) {
            _recording = false;
            return;
        }
        _stopTimer();
        _pages = [] as Array<ByteArray>;
        _acked = [] as Array<Boolean>;
        _sid = startEpochS;
        _ended = false;
        _partial = false;
        _recording = true;
        _sinceKey = KEYFRAME_EVERY;
        _inFlight = -1;
        _awaitingAck = false;
        _attempts = 0;
        _sentOk = 0;
        _buf = new [PAGE_BYTES]b;
        _len = 0;
        _header(windDir);
    }

    (:dev)
    function _header(windDir as Number) as Void {
        var b = _buf as ByteArray;
        b[0] = 0x43; b[1] = 0x4A; b[2] = 0x52; b[3] = 0x31;      // "CJR1"
        b[4] = SCHEMA;
        b[5] = STREAM_RECORD;
        _u16(6, FitSchema.APP_MINOR * 256 + FitSchema.SCHEMA_VERSION);
        _u32(8, _sid);
        _s16(12, windDir);
        b[14] = 0;
        b[15] = 0;
        _len = HEADER_BYTES;
    }

    (:dev) function _u8(off as Number, v as Number) as Void {
        (_buf as ByteArray)[off] = v & 0xFF;
    }
    (:dev) function _u16(off as Number, v as Number) as Void {
        (_buf as ByteArray).encodeNumber(v, Lang.NUMBER_FORMAT_UINT16,
            {:offset => off, :endianness => Lang.ENDIAN_LITTLE});
    }
    (:dev) function _s16(off as Number, v as Number) as Void {
        (_buf as ByteArray).encodeNumber(v, Lang.NUMBER_FORMAT_SINT16,
            {:offset => off, :endianness => Lang.ENDIAN_LITTLE});
    }
    (:dev) function _u32(off as Number, v as Number) as Void {
        (_buf as ByteArray).encodeNumber(v, Lang.NUMBER_FORMAT_UINT32,
            {:offset => off, :endianness => Lang.ENDIAN_LITTLE});
    }
    (:dev) function _s32(off as Number, v as Number) as Void {
        (_buf as ByteArray).encodeNumber(v, Lang.NUMBER_FORMAT_SINT32,
            {:offset => off, :endianness => Lang.ENDIAN_LITTLE});
    }

    // Degrees to integer units, half away from zero — `_q` in cjr_ref.py. Double in, so a
    // fix at 45.8710050° keeps its seventh decimal; a 32-bit Float would not.
    (:dev)
    function quantize(deg as Double, scale as Double) as Number {
        var x = deg * scale;
        return (x >= 0 ? x + 0.5 : x - 0.5).toNumber();
    }

    // The tracked 1e-7 position as the 1e-6 base of a delta — `_base6` in cjr_ref.py.
    (:dev)
    function base6(q7 as Number) as Number {
        return (q7 >= 0 ? q7 + 5 : q7 - 5) / 10;
    }

    // One fix. Called from SessionController.onPosition while recording, after the engine
    // ticked, with the same four developer values the FIT record gets.
    (:dev)
    function record(info as Position.Info, speedMps as Float, hr as Number?,
                    foil as Number, cadence as Number, marker as Number,
                    tick as Number) as Void {
        if (!_recording || _buf == null) {
            return;
        }
        var loc = info.position;
        if (loc == null) {
            return;
        }
        var d = (loc as Position.Location).toDegrees();
        var spd = (speedMps * 100.0 + 0.5).toNumber();
        var alt = ALT_NONE;
        if (info.altitude != null) {
            alt = (info.altitude as Float).toNumber();
        }
        recordFix(d[0], d[1], Time.now().value(), spd, alt, hr == null ? 0 : (hr as Number),
            devPack(foil, cadence, marker, tick));
    }

    // The four developer values in one Number: older runtimes allow nine arguments to a
    // function, and the fix needs ten.
    (:dev)
    function devPack(foil as Number, cadence as Number, marker as Number, tick as Number)
            as Number {
        return (foil & 0xFF) | ((cadence & 0xFF) << 8) | ((marker & 0xFF) << 16)
            | ((tick & 0xFF) << 24);
    }

    // The fix as numbers, the part a test can drive: degrees as Doubles, epoch seconds,
    // cm/s, metres (ALT_NONE for none), bpm (0 for none), and the four developer values
    // packed by devPack.
    (:dev)
    function recordFix(latDeg as Double, lonDeg as Double, t as Number, spd as Number,
                       alt as Number, h as Number, dev as Number) as Void {
        if (!_recording || _buf == null) {
            return;
        }
        var foil = dev & 0xFF;
        var cadence = (dev >> 8) & 0xFF;
        var marker = (dev >> 16) & 0xFF;
        var tick = (dev >> 24) & 0xFF;
        var d = [latDeg, lonDeg];
        if (spd < 0) { spd = 0; }
        if (spd > 65535) { spd = 65535; }
        if (alt != ALT_NONE) {
            if (alt > 32000) { alt = 32000; }
            if (alt < -32000) { alt = -32000; }
        }
        if (h < 0) { h = 0; }
        if (h > 255) { h = 255; }
        var key = _sinceKey >= KEYFRAME_EVERY;
        var dt = t - _prevT;
        var dlat = 0;
        var dlon = 0;
        var dalt = 0;
        if (!key) {
            if (dt < 1 || dt > DT_MAX) {
                key = true;
            } else {
                dlat = quantize(d[0], 1000000.0d) - base6(_qlat);
                dlon = quantize(d[1], 1000000.0d) - base6(_qlon);
                if (dlat < -32768 || dlat > 32767 || dlon < -32768 || dlon > 32767) {
                    key = true;
                } else if ((alt == ALT_NONE) != (_prevAlt == ALT_NONE)) {
                    key = true;
                } else if (alt != ALT_NONE) {
                    dalt = alt - _prevAlt;
                    if (dalt < -128 || dalt > 127) {
                        key = true;
                    }
                }
            }
        }
        var need = key ? KEYFRAME_BYTES : DELTA_BYTES;
        if (_len + need > PAGE_BYTES) {
            _closePage(false);
            key = true;
        }
        if (key) {
            _qlat = quantize(d[0], 10000000.0d);
            _qlon = quantize(d[1], 10000000.0d);
            var o = _len;
            _u8(o, KEYFRAME_TAG);
            _u32(o + 1, t);
            _s32(o + 5, _qlat);
            _s32(o + 9, _qlon);
            _u16(o + 13, spd);
            _s16(o + 15, alt);
            _u8(o + 17, h);
            _u8(o + 18, foil);
            _u8(o + 19, cadence);
            _u8(o + 20, marker);
            _u8(o + 21, tick);
            _len += KEYFRAME_BYTES;
            _sinceKey = 0;
        } else {
            _qlat += dlat * 10;
            _qlon += dlon * 10;
            var o = _len;
            _u8(o, dt);
            _s16(o + 1, dlat);
            _s16(o + 3, dlon);
            _u16(o + 5, spd);
            _u8(o + 7, dalt & 0xFF);
            _u8(o + 8, h);
            _u8(o + 9, foil);
            _u8(o + 10, cadence);
            _u8(o + 11, marker);
            _u8(o + 12, tick);
            _len += DELTA_BYTES;
        }
        _sinceKey += 1;
        _prevT = t;
        _prevAlt = alt;
    }

    (:dev)
    function _closePage(last as Boolean) as Void {
        if (_buf == null || _len == 0) {
            return;
        }
        _pages.add((_buf as ByteArray).slice(0, _len));
        _acked.add(false);
        _len = 0;
        _sinceKey = KEYFRAME_EVERY;   // the next page opens with a keyframe
        if (!last) {
            pump();
        }
    }

    // Save: the open page closes as the last one, and sending goes on while the SAVED
    // screen is up. Nothing is transmitted from here that was not already queued.
    (:dev)
    function finish() as Void {
        if (!_recording) {
            return;
        }
        _closePage(true);
        _recording = false;
        _ended = true;
        _buf = null;
        pump();
    }

    // ---- the sender ----

    (:dev)
    function pump() as Void {
        if (_inFlight >= 0 || _pages.size() == 0) {
            return;
        }
        var reachable = reachableOverride != null ? (reachableOverride as Boolean)
                                                  : PhoneLink.phoneReachable();
        if (!AppSettings.phonePush || !reachable) {
            return;
        }
        var i = _nextUnacked();
        if (i < 0) {
            return;
        }
        _send(i);
    }

    (:dev)
    function _nextUnacked() as Number {
        for (var i = 0; i < _pages.size(); i++) {
            if (!_acked[i]) {
                return i;
            }
        }
        return -1;
    }

    (:dev)
    function _send(i as Number) as Void {
        var last = _ended && i == _pages.size() - 1;
        var msg = {
            KEY_MSG => SCHEMA,
            KEY_SID => _sid,
            KEY_STREAM => STREAM_RECORD,
            KEY_PAGE => i,
            KEY_COUNT => _ended ? _pages.size() : 0,
            KEY_BYTES => wire(_pages[i])
        } as Dictionary<String, Object>;
        if (last) {
            msg[KEY_END] = 1;
        }
        _inFlight = i;
        _awaitingAck = false;
        _lastMs = System.getTimer();
        try {
            PhoneLink.radio.send(msg, new PageListener(i));
        } catch (e) {
            _inFlight = -1;
            _attempts += 1;
        }
    }

    // ByteArray on API 6+, one byte per Number below it (docs/transfer-format.md §3; dev3
    // packs four).
    (:dev)
    function wire(page as ByteArray) as Object {
        var mv = System.getDeviceSettings().monkeyVersion;
        if (mv[0] >= 6) {
            return page;
        }
        var arr = new [page.size()];
        for (var k = 0; k < page.size(); k++) {
            arr[k] = page[k];
        }
        return arr;
    }

    (:dev)
    function onRadioComplete(i as Number) as Void {
        if (_inFlight != i) {
            return;
        }
        _awaitingAck = true;
        _startTimer();
    }

    (:dev)
    function onRadioError(i as Number) as Void {
        if (_inFlight != i) {
            return;
        }
        LinkProbe.append("cjr p" + i + " ERR");
        _inFlight = -1;
        _retryOrWait();
    }

    (:dev)
    function _retryOrWait() as Void {
        _attempts += 1;
        if (_attempts <= RETRIES) {
            pump();
        }
        // else: wait for the connected edge (PhoneLink.pollLink → pump) or a cjrNeed
    }

    // The timer callback belongs to an object, never to this module: PhoneLink's header
    // records the fenix 7 runtime wedging on a module-scoped `method()`.
    (:dev) var _ackTimer as AckTimer = new AckTimer();

    (:dev)
    function _startTimer() as Void {
        _stopTimer();
        var t = new Timer.Timer();
        _timer = t;
        t.start(_ackTimer.method(:fire), ACK_TIMEOUT_MS, false);
    }

    (:dev)
    function _stopTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    (:dev)
    function onAckTimeout() as Void {
        _timer = null;
        if (_inFlight < 0 || !_awaitingAck) {
            return;
        }
        LinkProbe.append("cjr p" + _inFlight + " no ack");
        _inFlight = -1;
        _awaitingAck = false;
        _retryOrWait();
    }

    // Phone → watch. Untrusted, like everything in PhoneLink.applyMessage: a malformed
    // ack is ignored, never believed.
    (:dev)
    function applyMessage(d as Dictionary) as Boolean {
        var ack = d[KEY_ACK];
        if (ack instanceof Lang.Array) {
            return _onAck(ack as Array);
        }
        var need = d[KEY_NEED];
        if (need instanceof Lang.Array) {
            return _onNeed(need as Array);
        }
        return false;
    }

    (:dev)
    function _onAck(a as Array) as Boolean {
        if (a.size() != 3 || !(a[0] instanceof Lang.Number) || !(a[2] instanceof Lang.Number)) {
            return false;
        }
        if (a[0] != _sid || a[1] != STREAM_RECORD) {
            return false;
        }
        var p = a[2] as Number;
        if (p < 0 || p >= _pages.size()) {
            return false;
        }
        if (!_acked[p]) {
            _acked[p] = true;
            _sentOk += 1;
            // The probe's Results page is the dev build's log: one line per page landed.
            LinkProbe.append("cjr " + _sentOk + "/" + _pages.size() + " ok");
        }
        if (_inFlight == p) {
            _stopTimer();
            _inFlight = -1;
            _awaitingAck = false;
            _attempts = 0;
        }
        pump();
        WatchUi.requestUpdate();
        return true;
    }

    (:dev)
    function _onNeed(a as Array) as Boolean {
        if (a.size() != 3 || a[0] != _sid || a[1] != STREAM_RECORD
                || !(a[2] instanceof Lang.Array)) {
            return false;
        }
        var list = a[2] as Array;
        if (list.size() == 0) {
            // The stream is whole on the phone. Free it.
            LinkProbe.append("cjr whole");
            _stopTimer();
            _pages = [] as Array<ByteArray>;
            _acked = [] as Array<Boolean>;
            _inFlight = -1;
            _awaitingAck = false;
            _clearStore();
            WatchUi.requestUpdate();
            return true;
        }
        for (var k = 0; k < list.size(); k++) {
            var p = list[k];
            if (p instanceof Lang.Number && p >= 0 && p < _pages.size()) {
                _acked[p as Number] = false;
            }
        }
        _attempts = 0;
        pump();
        return true;
    }

    // ---- across an app exit ----

    // Storage takes 8 KB a value; ten pages is the budget the map slots and the card leave.
    (:dev)
    function persist() as Void {
        _stopTimer();
        var keep = [] as Array<Number>;
        for (var i = 0; i < _pages.size() && keep.size() < PERSIST_MAX; i++) {
            if (!_acked[i]) {
                keep.add(i);
            }
        }
        if (keep.size() == 0 || !_ended) {
            // A recording that is still open is the FIT's to keep; nothing partial is
            // persisted mid-session because the phone could never complete it.
            _clearStore();
            return;
        }
        var dropped = 0;
        for (var i = 0; i < _pages.size(); i++) {
            if (!_acked[i] && keep.indexOf(i) < 0) {
                dropped += 1;
            }
        }
        try {
            for (var k = 0; k < keep.size(); k++) {
                Storage.setValue(STORE_PAGE + k, _pages[keep[k]]);
            }
            Storage.setValue(STORE_IDX, {
                "sid" => _sid, "n" => _pages.size(), "pages" => keep, "dropped" => dropped
            });
        } catch (e) {
            _clearStore();
        }
    }

    (:dev)
    function restore() as Void {
        var idx = null;
        try {
            idx = Storage.getValue(STORE_IDX);
        } catch (e) {
        }
        if (!(idx instanceof Lang.Dictionary)) {
            return;
        }
        var d = idx as Dictionary;
        var n = d["n"];
        var keep = d["pages"];
        if (!(n instanceof Lang.Number) || !(keep instanceof Lang.Array)) {
            _clearStore();
            return;
        }
        _sid = d["sid"] as Number;
        _ended = true;
        _recording = false;
        _partial = (d["dropped"] as Number) > 0;
        _pages = new [n as Number] as Array<ByteArray>;
        _acked = new [n as Number] as Array<Boolean>;
        for (var i = 0; i < (n as Number); i++) {
            _pages[i] = new [0]b;
            _acked[i] = true;          // everything not restored counts as gone
        }
        var list = keep as Array;
        for (var k = 0; k < list.size(); k++) {
            var i = list[k] as Number;
            var page = null;
            try {
                page = Storage.getValue(STORE_PAGE + k);
            } catch (e) {
            }
            if (page instanceof Lang.ByteArray && i >= 0 && i < _pages.size()) {
                _pages[i] = page as ByteArray;
                _acked[i] = false;
            }
        }
        _clearStore();
        pump();
    }

    (:dev)
    function _clearStore() as Void {
        try {
            Storage.deleteValue(STORE_IDX);
            for (var k = 0; k < PERSIST_MAX; k++) {
                Storage.deleteValue(STORE_PAGE + k);
            }
        } catch (e) {
        }
    }

    // One line for the SAVED screen and the probe results: "phone 4/13" while sending,
    // "phone ok" when the stream is whole, null when there is nothing to say.
    (:dev)
    function statusLine() as String? {
        if (_pages.size() == 0) {
            return _ended && _sentOk > 0 ? "phone ok" : null;
        }
        return "phone " + _sentOk + "/" + _pages.size();
    }

    // ---- for the tests ----

    (:dev)
    function pageCount() as Number {
        return _pages.size();
    }

    (:dev)
    function page(i as Number) as ByteArray {
        return _pages[i];
    }

    (:dev)
    function openBytes() as ByteArray? {
        return _buf == null ? null : (_buf as ByteArray).slice(0, _len);
    }

    (:dev)
    function inFlight() as Number {
        return _inFlight;
    }

    (:dev)
    function acked(i as Number) as Boolean {
        return _acked[i];
    }

    // Discard, and the tests' reset: everything of the stream goes.
    (:dev)
    function discard() as Void {
        _stopTimer();
        _pages = [] as Array<ByteArray>;
        _acked = [] as Array<Boolean>;
        _inFlight = -1;
        _awaitingAck = false;
        _attempts = 0;
        _ended = false;
        _recording = false;
        _buf = null;
        _len = 0;
        _sentOk = 0;
    }
}

(:dev)
class AckTimer {
    function initialize() {
    }

    function fire() as Void {
        DirectSend.onAckTimeout();
    }
}

(:dev)
class PageListener extends Communications.ConnectionListener {
    hidden var _i as Number;

    function initialize(i as Number) {
        ConnectionListener.initialize();
        _i = i;
    }

    function onComplete() as Void {
        DirectSend.onRadioComplete(_i);
    }

    function onError() as Void {
        DirectSend.onRadioError(_i);
    }
}
