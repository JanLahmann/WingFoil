import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// The direct transfer, watch side (0.9.18-dev1). docs/transfer-format.md is the contract;
// lab/tools/cjr_ref.py is the reference the bytes are tested against. Dev stream only: the
// (:notdev) stubs below are what the beta and the release compile.
//
// Three things live here. The RECORD ENCODER turns every GPS fix of a recording into a
// record of the `rec.v1` stream — a 22-byte keyframe or a 13-byte delta — and closes a page
// whenever the next record would not fit in 8 000 bytes. The WRIST ENCODER takes the same
// 25 Hz magnitudes `PumpDetector` filters and writes the flagged stretches of them as
// `wrist.v1`, stream 1 (ADR-031). The SENDER moves closed pages to the phone one at a time:
// transmit, wait for `onComplete`, wait for the phone's `cjrAck`, next — stream 0 whole
// first, then stream 1, because Jan's call was "send it later, not first".
//
// The probe of 19 September 2026 fixed two of the sender's rules by crashing the app on a
// 16 KB page and on two pages in flight (docs/direct-transfer.md §5); nothing here is
// allowed to forget them.
//
// Memory. Pages stay resident, acknowledged or not, until the phone's empty `cjrNeed` says
// the stream is whole — a two-hour session is thirteen pages, 104 KB, of the 786 KB heap.
// The two page buffers are allocated once at start and sliced on close. The wrist stream is
// held to a fixed byte budget it can never exceed (`_wBudget`); when it fills, half the
// pages it already holds are dropped and it admits half as many windows from then on, so
// what survives is thinner rather than shorter.
module DirectSend {

    const PAGE_BYTES = 8000;
    const KEYFRAME_EVERY = 60;
    const DT_MAX = 254;
    const KEYFRAME_TAG = 0xFF;
    const ALT_NONE = 0x7FFF;
    const SCHEMA = 2;                // the stream: 2 since the header carries the clock offset
    const MSG_SCHEMA = 1;            // the page message (docs/transfer-format.md §3), unchanged
    const STREAM_RECORD = 0;
    const STREAM_WRIST = 1;          // `wrist.v1`, 0.9.18-dev1
    const HEADER_BYTES = 20;
    const UTC_OFFSET_NONE = 0x7FFF;
    const KEYFRAME_BYTES = 22;
    const DELTA_BYTES = 13;
    const ACK_TIMEOUT_MS = 6000;
    const RETRIES = 3;
    const PERSIST_MAX = 10;
    const STUCK_MS = 15000;          // a transmit that answers neither way is dropped after this
    const PACE_MS = 20000;           // while pages wait: retries reopen this often

    // ---- stream 1, `wrist.v1` (docs/transfer-format.md §2b, ADR-031) ----
    const WRIST_HZ = 25;             // PumpDetector.GRID_HZ; a watch off this grid sends nothing
    const WRIST_STEP_MS = 40;        // 1000 / WRIST_HZ, exact
    const WINDOW_TAG = 0xFF;
    const ESCAPE_TAG = 0xFE;
    const WINDOW_HEADER_BYTES = 9;
    const DELTA_BIAS = 126;          // byte v (0x00..0xFD) is the delta v - DELTA_BIAS
    const DELTA_MIN = -126;
    const DELTA_MAX = 127;
    const MAG_MAX = 65535;           // centi-g
    const WINDOW_MAX_SAMPLES = 250;  // 10 s; a longer flagged stretch becomes several windows
    const WINDOW_SCRATCH = 768;      // WINDOW_HEADER_BYTES + 250 escapes, rounded up
    const WRIST_LEAD = 25;           // 1 s of look-back: the phone's FIR group delay
    const WRIST_TAIL_MS = 1000;      // and 1 s after the flag clears, for the same reason
    // What the wrist stream may hold, in bytes of closed page. The binding watches are the
    // fr255 (507.7 kB total, ~119 kB of it already the app) and the fenix 5 Plus family
    // (1275.4 kB, ~155 kB). 60 000 B is about 38 minutes of covered riding at ~26 B/s and
    // eight pages; 24 000 B is about 15 minutes and three. Chosen off `totalMemory` rather
    // than off free memory so a device always gets the same answer and a test can assert it.
    //
    // `totalMemory` is the app's own limit on a watch and the SIMULATOR'S 8 MB in the
    // simulator, so every simulated device takes the big budget and only a real fr255 takes
    // the small one. That is the ordinary sim-versus-device split (docs/testing.md), and it
    // is safe in the direction that matters: the simulator over-allocates, the watch does
    // not. What the suite proves is the ceiling, which holds at either value.
    const WRIST_BUDGET_BIG = 60000;
    const WRIST_BUDGET_SMALL = 24000;
    const WRIST_BUDGET_MEM = 700000;

    const KEY_MSG = "cjr";
    const KEY_SID = "sid";
    const KEY_STREAM = "st";
    const KEY_PAGE = "p";
    const KEY_COUNT = "n";
    const KEY_END = "e";
    const KEY_BYTES = "b";
    const KEY_FLAGS = "f";           // bit 0: the payload is packed four bytes per Number
    const KEY_LEN = "bl";            // and this is its true length in bytes
    const FLAG_PACKED = 1;
    const KEY_ACK = "cjrAck";
    const KEY_NEED = "cjrNeed";
    const KEY_ANSWER_SID = "cjrSid";
    const KEY_ANSWER_STREAM = "cjrSt";

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

    // The 25 Hz grid, from PumpDetector._pushGrid. A no-op here, so the release and the beta
    // pay one empty call per sample and carry no wrist encoder at all.
    (:notdev)
    function wrist(magG as Float, tMs as Number) as Void {
    }

    (:notdev)
    function wristFlag(open as Boolean) as Void {
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

    (:notdev)
    function reopen() as Void {
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
    (:dev) var utcOffsetOverride as Number? = null;   // tests: minutes east of UTC
    (:dev) var packedOverride as Boolean? = null;     // tests: the pre-6.0.0 wire, on any device
    (:dev) var _pacer as Timer.Timer?;
    (:dev) var _paceTimer as PaceTimer = new PaceTimer();
    (:dev) var _stream as Number = STREAM_RECORD;    // the stream the sender is working on

    // ---- stream 1's state ----
    (:dev) var _wPages as Array<ByteArray> = [] as Array<ByteArray>;  // page 0 is the header
    (:dev) var _wAcked as Array<Boolean> = [] as Array<Boolean>;
    (:dev) var _wBuf as ByteArray?;          // the open page
    (:dev) var _wLen as Number = 0;
    (:dev) var _wWin as ByteArray?;          // the open window, closed whole into a page
    (:dev) var _wWinLen as Number = 0;
    (:dev) var _wWinN as Number = 0;
    (:dev) var _wPrevMag as Number = -1;     // centi-g of the window's previous sample
    (:dev) var _wLeadMag as Array<Number> = [] as Array<Number>;   // the look-back ring
    (:dev) var _wLeadMs as Array<Number> = [] as Array<Number>;
    (:dev) var _wLeadPos as Number = 0;
    (:dev) var _wLeadN as Number = 0;
    (:dev) var _wFlag as Boolean = false;    // the 1 Hz flag SessionController sets
    (:dev) var _wFlagMs as Number = 0;       // the last time it was true
    (:dev) var _wBytes as Number = 0;        // closed wrist pages, header page excluded
    (:dev) var _wBudget as Number = WRIST_BUDGET_SMALL;
    (:dev) var _wThin as Number = 1;         // admit one window in _wThin
    (:dev) var _wSeen as Number = 0;
    (:dev) var _wThinned as Number = 0;      // how often the budget bit, for the probe log
    (:dev) var _wOn as Boolean = false;      // the wrist encoder is recording
    (:dev) var _wSentOk as Number = 0;
    (:dev) var _wWhole as Boolean = false;
    (:dev) var _wAnchorEpoch as Number = 0;   // epoch seconds of the last 1 Hz fix
    (:dev) var _wAnchorMs as Number = 0;      // System.getTimer() at that fix
    (:dev) var _wLastMs as Number = 0;        // the last grid sample's timer ms
    (:dev) var _wHaveLast as Boolean = false;
    (:dev) var _modeLogged as Number = -1;    // the stream whose wire encoding is in the log

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
        _stream = STREAM_RECORD;
        _header(windDir);
        _wBegin(windDir);
    }

    // Stream 1 opens with the record stream and is written all session; it is only SENT once
    // stream 0 is whole. Its header is page 0 on its own — twenty bytes and one message —
    // because the pages after it are dropped under budget pressure and their indices are not
    // fixed until save, so the header cannot ride on a page that might not survive.
    (:dev)
    function _wBegin(windDir as Number) as Void {
        _wPages = [] as Array<ByteArray>;
        _wAcked = [] as Array<Boolean>;
        _wBuf = null;
        _wLen = 0;
        _wWin = null;
        _wWinLen = 0;
        _wWinN = 0;
        _wPrevMag = -1;
        _wLeadMag = new [WRIST_LEAD] as Array<Number>;
        _wLeadMs = new [WRIST_LEAD] as Array<Number>;
        _wLeadPos = 0;
        _wLeadN = 0;
        _wFlag = false;
        _wFlagMs = 0;
        _wLastMs = 0;
        _wHaveLast = false;
        _wBytes = 0;
        _wThin = 1;
        _wSeen = 0;
        _wThinned = 0;
        _wSentOk = 0;
        _wWhole = false;
        _wOn = false;
        var total = 0;
        try {
            total = System.getSystemStats().totalMemory;
        } catch (e) {
            total = 0;
        }
        _wBudget = total >= WRIST_BUDGET_MEM ? WRIST_BUDGET_BIG : WRIST_BUDGET_SMALL;
        // The pump detector is the only source of the 25 Hz grid. With it off there is no
        // wrist stream at all — and no 60 kB of buffers for one that will never be written.
        if (!AppSettings.pumpDetection) {
            return;
        }
        try {
            _wPages.add(_wristHeader(windDir));
            _wAcked.add(false);
            _wBuf = new [PAGE_BYTES]b;
            _wWin = new [WINDOW_SCRATCH]b;
            _wOn = true;
        } catch (e) {
            _wPages = [] as Array<ByteArray>;
            _wAcked = [] as Array<Boolean>;
            _wBuf = null;
            _wWin = null;
            _wOn = false;
        }
    }

    // The same twenty bytes as stream 0's header with `stream` = 1. The wind axis and the
    // discipline are repeated rather than zeroed: a stream that arrives on its own still
    // says which afternoon and which sport it belongs to.
    (:dev)
    function _wristHeader(windDir as Number) as ByteArray {
        var b = new [HEADER_BYTES]b;
        b[0] = 0x43; b[1] = 0x4A; b[2] = 0x52; b[3] = 0x31;      // "CJR1"
        b[4] = SCHEMA;
        b[5] = STREAM_WRIST;
        b.encodeNumber(FitSchema.APP_MINOR * 256 + FitSchema.SCHEMA_VERSION,
            Lang.NUMBER_FORMAT_UINT16, {:offset => 6, :endianness => Lang.ENDIAN_LITTLE});
        b.encodeNumber(_sid, Lang.NUMBER_FORMAT_UINT32,
            {:offset => 8, :endianness => Lang.ENDIAN_LITTLE});
        b.encodeNumber(windDir, Lang.NUMBER_FORMAT_SINT16,
            {:offset => 12, :endianness => Lang.ENDIAN_LITTLE});
        b[14] = 0;
        b[15] = 0;
        b.encodeNumber(_utcOffset(), Lang.NUMBER_FORMAT_SINT16,
            {:offset => 16, :endianness => Lang.ENDIAN_LITTLE});
        b.encodeNumber(0, Lang.NUMBER_FORMAT_UINT16,
            {:offset => 18, :endianness => Lang.ENDIAN_LITTLE});
        return b;
    }

    (:dev)
    function _utcOffset() as Number {
        var off = utcOffsetOverride;
        if (off == null) {
            try {
                off = System.getClockTime().timeZoneOffset / 60;
            } catch (e) {
                off = UTC_OFFSET_NONE;
            }
        }
        return off as Number;
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
        // The watch's clock offset, minutes east of UTC. The first direct session landed an
        // hour off (19 September 2026) because the phone had only the longitude to guess by.
        _s16(16, _utcOffset());
        _u16(18, 0);
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
        // The wrist stream's clock rides on this one: a window header states epoch
        // milliseconds and the sensor callback only ever knows `System.getTimer()`.
        // Re-anchored on every fix, so the two never drift more than a second apart.
        _wAnchorEpoch = t;
        _wAnchorMs = System.getTimer();
    }

    // ---- the wrist encoder, stream 1 (`wrist.v1`) ----

    // The flag: SessionController raises it once a second while the rider is off the foil,
    // a turn window is open, or the live detector picked a stroke recently — the three
    // states the phone's pump chain has anything to find in. Everything else is left off the
    // wire, which is the whole of ADR-031.
    (:dev)
    function wristFlag(open as Boolean) as Void {
        _wFlag = open;
        if (open) {
            _wFlagMs = System.getTimer();
        }
    }

    // One sample of the 25 Hz grid, in g, from PumpDetector._pushGrid — the single point
    // every magnitude the watch's own detector sees passes through, so the phone is handed
    // exactly the numbers the watch filtered and not a second reading of the sensor.
    (:dev)
    function wrist(magG as Float, tMs as Number) as Void {
        // No fix yet means no clock: a window header states an epoch and the sensor
        // callback only ever knows the milliseconds since boot.
        if (!_wOn || !_recording || _wAnchorEpoch <= 0) {
            return;
        }
        var mag = (magG * 100.0 + 0.5).toNumber();     // centi-g, half away from zero
        if (mag < 0) { mag = 0; }
        if (mag > MAG_MAX) { mag = MAG_MAX; }
        // Off the grid — a filter reset, a stalled listener, a pause. The window cannot
        // span it (its samples have no times of their own) so it closes and the look-back
        // starts again.
        var contiguous = _wHaveLast && (tMs - _wLastMs - WRIST_STEP_MS).abs() <= 20;
        if (!contiguous) {
            _wCloseWindow();
            _wLeadN = 0;
            _wLeadPos = 0;
        }
        _wLastMs = tMs;
        _wHaveLast = true;
        if (_wWinN > 0) {
            var stale = !_wFlag && System.getTimer() - _wFlagMs > WRIST_TAIL_MS;
            if (stale || _wWinN >= WINDOW_MAX_SAMPLES) {
                _wCloseWindow();
            }
        }
        if (_wWinN > 0) {
            _wPushSample(mag);
            return;
        }
        // No window open. Keep the sample in the look-back ring; open on the flag, with the
        // ring in front so the phone's 51-tap band-pass has a second to warm on.
        if (_wFlag) {
            _wOpenWindow(tMs, mag);
            return;
        }
        _wLeadMag[_wLeadPos] = mag;
        _wLeadMs[_wLeadPos] = tMs;
        _wLeadPos = (_wLeadPos + 1) % WRIST_LEAD;
        if (_wLeadN < WRIST_LEAD) {
            _wLeadN += 1;
        }
    }

    // Opens a window at the oldest look-back sample and writes the ring into it, then this
    // sample. The window's own header is written first, with the epoch time of that oldest
    // sample; every sample after it is one WRIST_STEP_MS later by construction.
    (:dev)
    function _wOpenWindow(tMs as Number, mag as Number) as Void {
        var k = _wLeadN;
        var firstMs = k > 0 ? _wLeadMs[(_wLeadPos - k + WRIST_LEAD) % WRIST_LEAD] : tMs;
        var d = firstMs - _wAnchorMs;
        var secs = _wAnchorEpoch + (d >= 0 ? d / 1000 : -((-d + 999) / 1000));
        var ms = d - (secs - _wAnchorEpoch) * 1000;
        var w = _wWin as ByteArray;
        w[0] = WINDOW_TAG;
        w.encodeNumber(secs, Lang.NUMBER_FORMAT_UINT32,
            {:offset => 1, :endianness => Lang.ENDIAN_LITTLE});
        w.encodeNumber(ms, Lang.NUMBER_FORMAT_UINT16,
            {:offset => 5, :endianness => Lang.ENDIAN_LITTLE});
        w.encodeNumber(0, Lang.NUMBER_FORMAT_UINT16,      // the count, patched on close
            {:offset => 7, :endianness => Lang.ENDIAN_LITTLE});
        _wWinLen = WINDOW_HEADER_BYTES;
        _wWinN = 0;
        _wPrevMag = -1;
        for (var i = 0; i < k; i++) {
            _wPushSample(_wLeadMag[(_wLeadPos - k + i + WRIST_LEAD) % WRIST_LEAD]);
        }
        _wLeadN = 0;
        _wLeadPos = 0;
        _wPushSample(mag);
    }

    // One magnitude: an 8-bit delta where it holds, a two-byte escape where it does not.
    // The first sample of a window always escapes, so the window decodes on its own.
    (:dev)
    function _wPushSample(mag as Number) as Void {
        if (_wWinLen + 3 > WINDOW_SCRATCH || _wWinN >= WINDOW_MAX_SAMPLES) {
            return;
        }
        var w = _wWin as ByteArray;
        var d = _wPrevMag < 0 ? DELTA_MAX + 1 : mag - _wPrevMag;
        if (d >= DELTA_MIN && d <= DELTA_MAX) {
            w[_wWinLen] = d + DELTA_BIAS;
            _wWinLen += 1;
        } else {
            w[_wWinLen] = ESCAPE_TAG;
            w.encodeNumber(mag, Lang.NUMBER_FORMAT_UINT16,
                {:offset => _wWinLen + 1, :endianness => Lang.ENDIAN_LITTLE});
            _wWinLen += 3;
        }
        _wPrevMag = mag;
        _wWinN += 1;
    }

    // Patches the sample count in and admits the window — or drops it, because the budget
    // has bitten and this is one of the windows the thinning skips.
    (:dev)
    function _wCloseWindow() as Void {
        if (_wWinN <= 0) {
            _wWinLen = 0;
            _wWinN = 0;
            _wPrevMag = -1;
            return;
        }
        var w = _wWin as ByteArray;
        w.encodeNumber(_wWinN, Lang.NUMBER_FORMAT_UINT16,
            {:offset => 7, :endianness => Lang.ENDIAN_LITTLE});
        var len = _wWinLen;
        var keep = _wSeen % _wThin == 0;
        _wSeen += 1;
        _wWinLen = 0;
        _wWinN = 0;
        _wPrevMag = -1;
        if (!keep || _wBuf == null) {
            return;
        }
        // A window never straddles a page, so every page opens with a window header and
        // decodes on its own — the rule §1 states for stream 0.
        if (_wLen + len > PAGE_BYTES) {
            _wClosePage();
        }
        var buf = _wBuf as ByteArray;
        for (var i = 0; i < len; i++) {
            buf[_wLen + i] = w[i];
        }
        _wLen += len;
    }

    (:dev)
    function _wClosePage() as Void {
        if (_wBuf == null || _wLen == 0) {
            return;
        }
        _wPages.add((_wBuf as ByteArray).slice(0, _wLen));
        _wAcked.add(false);
        _wBytes += _wLen;
        _wLen = 0;
        while (_wBytes > _wBudget && _wPages.size() > 2) {
            _wThinPages();
        }
    }

    // The budget has bitten. Half of what is held goes — every second page after the header
    // and the first — and half of what would arrive goes with it, so the coverage that
    // survives is spread across the whole session rather than being its first twenty
    // minutes. Geometric, so a six-hour session thins four times and stops.
    (:dev)
    function _wThinPages() as Void {
        var kept = [_wPages[0], _wPages[1]] as Array<ByteArray>;
        var bytes = _wPages[1].size();
        for (var i = 2; i < _wPages.size(); i++) {
            if (i % 2 == 0) {
                kept.add(_wPages[i]);
                bytes += _wPages[i].size();
            }
        }
        _wPages = kept;
        _wAcked = new [kept.size()] as Array<Boolean>;
        for (var i = 0; i < kept.size(); i++) {
            _wAcked[i] = false;
        }
        _wBytes = bytes;
        _wThin *= 2;
        _wThinned += 1;
        LinkProbe.append("cjr wrist thin " + _wThin);
    }

    // Save: the open window and the open page close, and the stream is ready to go the
    // moment stream 0 is whole. A stream with nothing but its header is not sent at all.
    (:dev)
    function _wFinish() as Void {
        if (!_wOn) {
            return;
        }
        _wCloseWindow();
        _wClosePage();
        _wBuf = null;
        _wWin = null;
        _wOn = false;
        if (_wPages.size() <= 1) {
            _wPages = [] as Array<ByteArray>;
            _wAcked = [] as Array<Boolean>;
        }
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
        // A recording without a single fix is a header and nothing else: the phone would
        // refuse it (19 September 2026, "no position fixes"), so it is not sent at all.
        if (_pages.size() == 0 && _len <= HEADER_BYTES) {
            discard();
            return;
        }
        _closePage(true);
        _recording = false;
        _ended = true;
        _buf = null;
        _attempts = 0;
        _wFinish();
        pump();
    }

    // ---- the sender ----

    // The pages of whichever stream the sender is working on. Stream 0 crosses whole first
    // and stream 1 follows — Jan's call, 19 September 2026: "Send it later, not first."
    (:dev)
    function _curPages() as Array<ByteArray> {
        return _stream == STREAM_WRIST ? _wPages : _pages;
    }

    (:dev)
    function _curAcked() as Array<Boolean> {
        return _stream == STREAM_WRIST ? _wAcked : _acked;
    }

    (:dev)
    function pump() as Void {
        if (_curPages().size() == 0) {
            _stopPacer();
            return;
        }
        _startPacer();
        // A transmit that answered neither onComplete nor onError: the field test of
        // 19 September 2026 showed a sender that could wait forever on one. Dropped, retried.
        if (_inFlight >= 0 && !_awaitingAck && System.getTimer() - _lastMs > STUCK_MS) {
            LinkProbe.append("cjr p" + _inFlight + " stuck");
            _inFlight = -1;
        }
        if (_inFlight >= 0) {
            return;
        }
        // Three tries, then the pacer, the connected edge, save or a need list reopen them:
        // a phone in the car is not worth a transmit every time a page closes.
        if (_attempts > RETRIES) {
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
        var acked = _curAcked();
        for (var i = 0; i < acked.size(); i++) {
            if (!acked[i]) {
                return i;
            }
        }
        return -1;
    }

    (:dev)
    function _send(i as Number) as Void {
        var pages = _curPages();
        // Stream 1 is never open: it is only sent once the recording is saved.
        var ended = _stream == STREAM_WRIST ? true : _ended;
        var last = ended && i == pages.size() - 1;
        var page = pages[i];
        var msg = {
            KEY_MSG => MSG_SCHEMA,
            KEY_SID => _sid,
            KEY_STREAM => _stream,
            KEY_PAGE => i,
            KEY_COUNT => ended ? pages.size() : 0,
            KEY_BYTES => wire(page)
        } as Dictionary<String, Object>;
        if (last) {
            msg[KEY_END] = 1;
        }
        if (packed()) {
            // The payload is four bytes to a Number, and only the message can say so: the
            // stream header is INSIDE the payload, so a phone that had to read it first
            // could not unpack the page it is in.
            msg[KEY_FLAGS] = FLAG_PACKED;
            msg[KEY_LEN] = page.size();
        }
        // Once per stream, the wire encoding, so the probe's Results page says which mode
        // the numbers under it were measured in.
        if (_modeLogged != _stream) {
            _modeLogged = _stream;
            LinkProbe.append("cjr s" + _stream + " " + (packed() ? "pack4" : "bytes"));
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

    // Can this watch put a ByteArray on the radio? Only from Connect IQ 6.0.0 — the fenix 8,
    // the fr970 and the enduro 3 can, the fenix 7 (5.2.0) and the fenix 5 Plus (3.3.3)
    // cannot. A capability probe and not a family list, because the answer is the API's.
    (:dev)
    function packed() as Boolean {
        if (packedOverride != null) {
            return packedOverride as Boolean;
        }
        var mv = System.getDeviceSettings().monkeyVersion;
        return mv[0] < 6;
    }

    // ByteArray on API 6+, an Array of Numbers below it — FOUR payload bytes per 32-bit
    // Number, little-endian within the word (docs/transfer-format.md §3).
    //
    // One byte per Number is what 0.9.14-dev2 sent, and `PhoneLink.estimateBytes` prices a
    // Number at five wire bytes: an 8 000 B page cost 40 KB and the pre-6.0.0 fleet could
    // never have carried one. Four to a Number costs the same five bytes for four, so the
    // page costs 10 KB and the 5 Plus family is back in. The last word is zero-filled and
    // `bl` on the message carries the true length.
    (:dev)
    function wire(page as ByteArray) as Object {
        if (!packed()) {
            return page;
        }
        var n = page.size();
        var words = (n + 3) / 4;
        var arr = new [words];
        for (var w = 0; w < words; w++) {
            var o = w * 4;
            var v = page[o];
            if (o + 1 < n) { v = v | (page[o + 1] << 8); }
            if (o + 2 < n) { v = v | (page[o + 2] << 16); }
            if (o + 3 < n) { v = v | (page[o + 3] << 24); }
            arr[w] = v;
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
        pump();      // bounded by RETRIES inside; the pacer reopens it
    }

    // The pacer: while pages wait, every PACE_MS the retry budget is reset and the sender
    // tries again — the moment the rider opens the phone app is not an event the watch can
    // see, so it looks every twenty seconds instead.
    (:dev)
    function _startPacer() as Void {
        if (_pacer != null) {
            return;
        }
        var t = new Timer.Timer();
        _pacer = t;
        t.start(_paceTimer.method(:fire), PACE_MS, true);
    }

    (:dev)
    function _stopPacer() as Void {
        if (_pacer != null) {
            (_pacer as Timer.Timer).stop();
            _pacer = null;
        }
    }

    (:dev)
    function onPace() as Void {
        if (_pages.size() == 0) {
            _stopPacer();
            return;
        }
        _attempts = 0;
        pump();
    }

    // The connected edge and a settings change from the phone (PhoneLink): the budget
    // reopens, because both mean a phone that was not there a moment ago.
    (:dev)
    function reopen() as Void {
        _attempts = 0;
        pump();
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
    // Two shapes are taken. The flat one — three keys, integers and a comma-joined
    // string — is what the phone sends since the field test of 19 September 2026 showed
    // that a nested array never leaves Garmin's phone SDK; the array one stays readable.
    (:dev)
    function applyMessage(d as Dictionary) as Boolean {
        var ack = d[KEY_ACK];
        if (ack instanceof Lang.Array) {
            return _onAck(ack as Array);
        }
        if (ack instanceof Lang.Number) {
            return _onAck([d[KEY_ANSWER_SID], d[KEY_ANSWER_STREAM], ack] as Array);
        }
        var need = d[KEY_NEED];
        if (need instanceof Lang.Array) {
            return _onNeed(need as Array);
        }
        if (need instanceof Lang.String) {
            return _onNeed([d[KEY_ANSWER_SID], d[KEY_ANSWER_STREAM],
                            _pageList(need as String)] as Array);
        }
        return false;
    }

    // "1,4,7" → [1, 4, 7]; "" → []. Anything that is not a number is dropped.
    //
    // The string is the PHONE'S, so its length is not ours to assume: a 20 KB value of commas
    // is twenty thousand substrings inside one radio callback. A need list can name at most
    // one page per page we hold, and the longest honest one is a few hundred bytes.
    (:dev)
    const NEED_MAX_CHARS = 1024;

    (:dev)
    function _pageList(s as String) as Array<Number> {
        var out = [] as Array<Number>;
        if (s.length() > NEED_MAX_CHARS) {
            LinkProbe.append("cjr need too long");
            return out;
        }
        var rest = s;
        while (rest.length() > 0) {
            var i = rest.find(",");
            var part = i == null ? rest : rest.substring(0, i);
            rest = i == null ? "" : rest.substring((i as Number) + 1, rest.length());
            var n = part.toNumber();
            if (n != null) {
                out.add(n as Number);
            }
        }
        return out;
    }

    (:dev)
    function _onAck(a as Array) as Boolean {
        if (a.size() != 3 || !(a[0] instanceof Lang.Number) || !(a[2] instanceof Lang.Number)
                || !(a[1] instanceof Lang.Number)) {
            LinkProbe.append("cjr ack odd");
            return false;
        }
        var st = a[1] as Number;
        if (a[0] != _sid || (st != STREAM_RECORD && st != STREAM_WRIST)) {
            LinkProbe.append("cjr ack sid?");
            return false;
        }
        var pages = st == STREAM_WRIST ? _wPages : _pages;
        var acked = st == STREAM_WRIST ? _wAcked : _acked;
        var p = a[2] as Number;
        if (p < 0 || p >= pages.size()) {
            return false;
        }
        if (!acked[p]) {
            acked[p] = true;
            var n = 0;
            if (st == STREAM_WRIST) {
                _wSentOk += 1;
                n = _wSentOk;
            } else {
                _sentOk += 1;
                n = _sentOk;
            }
            // The probe's Results page is the dev build's log: one line per page landed,
            // with the wall clock from the transmit to this acknowledgement — the number
            // the 5 Plus probe run is there to read (docs/direct-transfer.md §5).
            LinkProbe.append("cjr s" + st + " " + n + "/" + pages.size() + " "
                + (System.getTimer() - _lastMs) + "ms");
        }
        if (_stream == st && _inFlight == p) {
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
        if (a.size() != 3 || a[0] != _sid || !(a[1] instanceof Lang.Number)
                || !(a[2] instanceof Lang.Array)) {
            return false;
        }
        var st = a[1] as Number;
        if (st != STREAM_RECORD && st != STREAM_WRIST) {
            return false;
        }
        var list = a[2] as Array;
        if (list.size() == 0) {
            return _onWhole(st);
        }
        var acked = st == STREAM_WRIST ? _wAcked : _acked;
        for (var k = 0; k < list.size(); k++) {
            var p = list[k];
            if (p instanceof Lang.Number && p >= 0 && p < acked.size()) {
                acked[p as Number] = false;
            }
        }
        _attempts = 0;
        pump();
        return true;
    }

    // A stream is whole on the phone: free it. Stream 0 hands over to the wrist stream if
    // there is one; the buzz and "phone ok" wait for the LAST stream, because one short
    // tick means "you can walk away" and that is only true when everything has crossed.
    (:dev)
    function _onWhole(st as Number) as Boolean {
        LinkProbe.append("cjr s" + st + " whole");
        _stopTimer();
        _inFlight = -1;
        _awaitingAck = false;
        if (st == STREAM_WRIST) {
            _wPages = [] as Array<ByteArray>;
            _wAcked = [] as Array<Boolean>;
            _wWhole = true;
        } else {
            _pages = [] as Array<ByteArray>;
            _acked = [] as Array<Boolean>;
        }
        _clearStore();
        if (st == STREAM_RECORD && _wPages.size() > 1) {
            _stream = STREAM_WRIST;
            _attempts = 0;
            pump();
            WatchUi.requestUpdate();
            return true;
        }
        _stopPacer();
        AlertManager.phoneStreamWhole();
        WatchUi.requestUpdate();
        return true;
    }

    // ---- across an app exit ----

    // Storage takes 8 KB a value; ten pages is the budget the map slots and the card leave.
    //
    // The stream the sender is WORKING ON is the one that is persisted — stream 0 while the
    // recording is still crossing, stream 1 once it has. The other one is lost, and that is
    // the honest trade: two streams of ten pages would be twice the Storage this app has,
    // and a wrist stream whose record stream never landed has nothing to attach to anyway.
    (:dev)
    function persist() as Void {
        _stopTimer();
        var pages = _curPages();
        var acked = _curAcked();
        var keep = [] as Array<Number>;
        for (var i = 0; i < pages.size() && keep.size() < PERSIST_MAX; i++) {
            if (!acked[i]) {
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
        for (var i = 0; i < pages.size(); i++) {
            if (!acked[i] && keep.indexOf(i) < 0) {
                dropped += 1;
            }
        }
        try {
            for (var k = 0; k < keep.size(); k++) {
                Storage.setValue(STORE_PAGE + k, pages[keep[k]]);
            }
            Storage.setValue(STORE_IDX, {
                "sid" => _sid, "n" => pages.size(), "pages" => keep, "dropped" => dropped,
                "st" => _stream
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
        var sid = d["sid"];
        var dropped = d["dropped"];
        // Storage outlives the build that wrote it. An index left by a version with a
        // different key set gives `null > 0` — an UnexpectedTypeException on the first line
        // of onStart, before a view exists — and an `n` of a hundred thousand allocates two
        // arrays the heap cannot hold. Both are the store's word, so neither is believed.
        if (!(n instanceof Lang.Number) || !(keep instanceof Lang.Array)
                || !(sid instanceof Lang.Number)
                || (n as Number) < 0 || (n as Number) > 4096) {
            _clearStore();
            return;
        }
        // The stream number is the store's word too, and an index written by a build that
        // had only one stream carries none: absent or odd means stream 0.
        var st = d["st"];
        _stream = st instanceof Lang.Number && (st as Number) == STREAM_WRIST
            ? STREAM_WRIST : STREAM_RECORD;
        _sid = sid as Number;
        _ended = true;
        _recording = false;
        _wOn = false;
        _partial = dropped instanceof Lang.Number && (dropped as Number) > 0;
        var pages = new [n as Number] as Array<ByteArray>;
        var acked = new [n as Number] as Array<Boolean>;
        for (var i = 0; i < (n as Number); i++) {
            pages[i] = new [0]b;
            acked[i] = true;          // everything not restored counts as gone
        }
        var list = keep as Array;
        for (var k = 0; k < list.size() && k < PERSIST_MAX; k++) {
            var entry = list[k];
            if (!(entry instanceof Lang.Number)) {
                continue;
            }
            var i = entry as Number;
            var page = null;
            try {
                page = Storage.getValue(STORE_PAGE + k);
            } catch (e) {
            }
            if (page instanceof Lang.ByteArray && i >= 0 && i < pages.size()) {
                pages[i] = page as ByteArray;
                acked[i] = false;
            }
        }
        if (_stream == STREAM_WRIST) {
            _wPages = pages;
            _wAcked = acked;
        } else {
            _pages = pages;
            _acked = acked;
        }
        _clearStore();
        _attempts = 0;
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

    // One line for the SAVED screen, the START screen and the probe results: "phone 4/13"
    // while the recording's pages are crossing, "wrist 2/8" while the wrist stream follows
    // it, "phone ok" when everything is across, null when there is nothing to say.
    //
    // Two words rather than one counter over both streams, because they are two waits and
    // the second one starts after the rider has already been told the first is done. "wrist"
    // is the word the app uses for the accelerometer everywhere else.
    //
    // It is drawn in the eyebrow font under the SAVED pill (SummaryView.drawPhoneLine) and,
    // because `restore()` brings an unfinished stream back across an app exit, on the START
    // screen too — a rider who walked away mid-transfer and opened the app again the next
    // morning is looking at the one screen that can tell him yesterday's session is still
    // in the queue. Null on both when there is nothing waiting, so neither screen grows a
    // row it does not need.
    (:dev)
    function statusLine() as String? {
        if (_stream == STREAM_WRIST && _wPages.size() > 0) {
            return "wrist " + _wSentOk + "/" + _wPages.size();
        }
        if (_pages.size() > 0) {
            return "phone " + _sentOk + "/" + _pages.size();
        }
        return _ended && (_sentOk > 0 || _wSentOk > 0) ? "phone ok" : null;
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

    (:dev)
    function wristPageCount() as Number {
        return _wPages.size();
    }

    (:dev)
    function wristPage(i as Number) as ByteArray {
        return _wPages[i];
    }

    (:dev)
    function wristBudget() as Number {
        return _wBudget;
    }

    (:dev)
    function wristThin() as Number {
        return _wThin;
    }

    // The tests' clock. On a watch this is set by every 1 Hz fix; a test has no fixes and
    // no control over `System.getTimer()`, so it says what the mapping is.
    (:dev)
    function wristAnchor(epochS as Number, timerMs as Number) as Void {
        _wAnchorEpoch = epochS;
        _wAnchorMs = timerMs;
    }

    // Discard, and the tests' reset: everything of both streams goes.
    (:dev)
    function discard() as Void {
        _stopTimer();
        _stopPacer();
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
        _stream = STREAM_RECORD;
        _modeLogged = -1;
        _wPages = [] as Array<ByteArray>;
        _wAcked = [] as Array<Boolean>;
        _wBuf = null;
        _wWin = null;
        _wLen = 0;
        _wWinLen = 0;
        _wWinN = 0;
        _wPrevMag = -1;
        _wLeadN = 0;
        _wLeadPos = 0;
        _wLastMs = 0;
        _wHaveLast = false;
        _wFlag = false;
        _wBytes = 0;
        _wThin = 1;
        _wSeen = 0;
        _wThinned = 0;
        _wSentOk = 0;
        _wWhole = false;
        _wOn = false;
    }
}

(:dev)
class PaceTimer {
    function initialize() {
    }

    function fire() as Void {
        DirectSend.onPace();
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
