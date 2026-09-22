import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The link probe — the first experiment of docs/direct-transfer.md, dev stream only.
//
// Question: how fast does Communications.transmit move a page of bytes from the watch to
// the phone, and where does a single message stop being accepted? Nobody has published a
// number, and the whole "hold the session, send it on land" design stands on it. So the
// dev build carries one hidden menu (Wind from → Link probe) that sends a payload of 1, 4,
// 8 or 16 KB, or three 8 KB pages back to back, and writes the wall-clock time of each
// onComplete into a small log the next menu item shows.
//
// Three encodings, because Communications.transmit takes a ByteArray only from API 6.0.0
// (fenix 8) and 30 of the 42 products we ship are older. Those send the same bytes as an
// Array of Numbers, and there the choice is one byte per Number — which `estimateBytes`
// prices at five wire bytes each, so an 8 KB page costs 40 KB and no 5 Plus was ever going
// to carry one — or FOUR bytes per Number, the same five wire bytes for four payload bytes
// and a page that costs 10 KB (0.9.18-dev1, docs/transfer-format.md §3). The log names
// which one was used and how many milliseconds it took, which is the whole of what a
// 5 Plus probe run is there to read.
//
// Nothing here is rider-facing, nothing is in the beta or release jungles (they exclude the
// `dev` annotation), and the shipped code touches it through two one-line hooks in the wind
// menu that compile to no-ops there.
module LinkProbe {

    const STORE_LOG = "prLog";
    const KEY_PROBE = "pr";     // payload size in bytes
    const KEY_SEQ = "q";        // 1..3 within a burst
    const KEY_BYTES = "b";      // the page
    const LOG_MAX = 16;

    (:notdev)
    function addMenuItem(menu as WatchUi.Menu2) as Void {
    }

    (:notdev)
    function handleMenu(id as Object?) as Boolean {
        return false;
    }

    (:dev)
    function addMenuItem(menu as WatchUi.Menu2) as Void {
        menu.addItem(new WatchUi.MenuItem("Link probe", "dev", :probe, null));
    }

    (:dev)
    function handleMenu(id as Object?) as Boolean {
        if (id != :probe) {
            return false;
        }
        WatchUi.pushView(buildMenu(), new ProbeMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

    (:dev)
    function buildMenu() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Link probe"});
        menu.addItem(new WatchUi.MenuItem("1 KB", null, 1024, null));
        menu.addItem(new WatchUi.MenuItem("4 KB", null, 4096, null));
        menu.addItem(new WatchUi.MenuItem("8 KB", null, 8192, null));
        menu.addItem(new WatchUi.MenuItem("8 KB x3", "back to back", :burst, null));
        // Only where it means anything: an API-6 watch sends a ByteArray and has no second
        // mode to compare against.
        if (System.getDeviceSettings().monkeyVersion[0] < 6) {
            menu.addItem(new WatchUi.MenuItem("8 KB plain", "1 byte / Number", :plain8k, null));
        }
        menu.addItem(new WatchUi.MenuItem("Results", null, :results, null));
        menu.addItem(new WatchUi.MenuItem("Clear log", null, :clear, null));
        return menu;
    }

    (:dev)
    var _seq as Number = 0;
    // The one-byte-per-Number payload, for the comparison run only. The transfer itself
    // always packs four.
    (:dev)
    var _plain as Boolean = false;

    // ByteArray on API 6+, an Array of Numbers below it — four bytes per Number unless
    // `_plain` asks for the old shape. A page of n bytes, content i & 0xFF, so a corrupted
    // delivery would be visible on the phone.
    (:dev)
    function payload(n as Number) as Object {
        var mv = System.getDeviceSettings().monkeyVersion;
        if (mv[0] >= 6) {
            var ba = new [n]b;
            for (var i = 0; i < n; i++) {
                ba[i] = i & 0xFF;
            }
            return ba;
        }
        if (_plain) {
            var arr = new [n];
            for (var i = 0; i < n; i++) {
                arr[i] = i & 0xFF;
            }
            return arr;
        }
        var words = (n + 3) / 4;
        var packedArr = new [words];
        for (var w = 0; w < words; w++) {
            var o = w * 4;
            var v = o < n ? (o & 0xFF) : 0;
            if (o + 1 < n) { v = v | (((o + 1) & 0xFF) << 8); }
            if (o + 2 < n) { v = v | (((o + 2) & 0xFF) << 16); }
            if (o + 3 < n) { v = v | (((o + 3) & 0xFF) << 24); }
            packedArr[w] = v;
        }
        return packedArr;
    }

    (:dev)
    function encodingName() as String {
        if (System.getDeviceSettings().monkeyVersion[0] >= 6) {
            return "bytes";
        }
        return _plain ? "plain1" : "pack4";
    }

    (:dev) var _chainLeft as Number = 0;
    (:dev) var _chainN as Number = 0;

    // `count` pages of n bytes, one at a time: the next leaves from onComplete.
    (:dev)
    function chain(n as Number, count as Number) as Void {
        _chainN = n;
        _chainLeft = count - 1;
        send(n, 1);
    }

    (:dev)
    function chainNext(seq as Number) as Void {
        if (_chainLeft <= 0) {
            return;
        }
        _chainLeft -= 1;
        send(_chainN, seq + 1);
    }

    // One page onto the radio, timed from here to the listener's onComplete.
    (:dev)
    function send(n as Number, seq as Number) as Void {
        _seq += 1;
        var t0 = System.getTimer();
        try {
            var p = payload(n);
            var msg = {KEY_PROBE => n, KEY_SEQ => seq, KEY_BYTES => p};
            Communications.transmit(msg, null, new ProbeListener(n, seq, t0));
            append(label(n, seq) + " sent " + encodingName());
        } catch (e) {
            append(label(n, seq) + " refused " + e.getErrorMessage());
        }
    }

    (:dev)
    function label(n as Number, seq as Number) as String {
        return (n / 1024).toString() + "K#" + seq.toString();
    }

    (:dev)
    function record(n as Number, seq as Number, t0 as Number, ok as Boolean) as Void {
        var ms = System.getTimer() - t0;
        append(label(n, seq) + (ok ? " ok " : " ERR ") + ms.toString() + " ms");
    }

    (:dev)
    function readLog() as Array<String> {
        try {
            var v = Storage.getValue(STORE_LOG);
            if (v instanceof Lang.Array) {
                return v as Array<String>;
            }
        } catch (e) {
        }
        return [] as Array<String>;
    }

    (:dev)
    function append(line as String) as Void {
        var log = readLog();
        log.add(line);
        while (log.size() > LOG_MAX) {
            log = log.slice(1, null);
        }
        try {
            Storage.setValue(STORE_LOG, log);
        } catch (e) {
        }
        WatchUi.requestUpdate();
    }

    (:dev)
    function clearLog() as Void {
        try {
            Storage.deleteValue(STORE_LOG);
        } catch (e) {
        }
    }
}

(:dev)
class ProbeListener extends Communications.ConnectionListener {
    hidden var _n as Number;
    hidden var _seq as Number;
    hidden var _t0 as Number;

    function initialize(n as Number, seq as Number, t0 as Number) {
        ConnectionListener.initialize();
        _n = n;
        _seq = seq;
        _t0 = t0;
    }

    function onComplete() as Void {
        LinkProbe.record(_n, _seq, _t0, true);
        LinkProbe.chainNext(_seq);
    }

    function onError() as Void {
        LinkProbe.record(_n, _seq, _t0, false);
    }
}

(:dev)
class ProbeMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Lang.Number) {
            LinkProbe._plain = false;
            LinkProbe.send(id as Number, 1);
            WatchUi.pushView(new ProbeView(), new ProbeViewDelegate(), WatchUi.SLIDE_UP);
        } else if (id == :plain8k) {
            // The comparison the 5 Plus run exists to make: the same 8 KB, one byte to a
            // Number, against the packed page above it. Read the two `ms` off Results.
            LinkProbe._plain = true;
            LinkProbe.send(8192, 1);
            LinkProbe._plain = false;
            WatchUi.pushView(new ProbeView(), new ProbeViewDelegate(), WatchUi.SLIDE_UP);
        } else if (id == :burst) {
            LinkProbe._plain = false;
            // A chain, not a burst: the second page goes when the first completes. Three
            // in flight crashed the app on the fenix 8 (19 September 2026), and 16 KB did
            // too, so that item is gone — 8 KB is the page (docs/direct-transfer.md §5).
            LinkProbe.chain(8192, 3);
            WatchUi.pushView(new ProbeView(), new ProbeViewDelegate(), WatchUi.SLIDE_UP);
        } else if (id == :results) {
            WatchUi.pushView(new ProbeView(), new ProbeViewDelegate(), WatchUi.SLIDE_UP);
        } else if (id == :clear) {
            LinkProbe.clearLog();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

// The log, newest at the bottom, in the smallest font. A probe result lands here through
// requestUpdate the moment the listener fires, so the rider watches the number arrive.
(:dev)
class ProbeView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        CrashBreadcrumb.view(CrashBreadcrumb.V_PROBE);
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var lines = LinkProbe.readLog();
        var h = dc.getFontHeight(Graphics.FONT_XTINY);
        var cx = dc.getWidth() / 2;
        var y = dc.getHeight() / 2 - (lines.size() * h) / 2;
        if (lines.size() == 0) {
            dc.drawText(cx, dc.getHeight() / 2, Graphics.FONT_SMALL, "no probes yet",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, y + i * h, Graphics.FONT_XTINY, lines[i],
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

(:dev)
class ProbeViewDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }
}
