import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// THE PHONE-RENDERED GROUND (device app 0.9.10, docs/watch-map-snapshot.md, GitHub #4).
//
// The firmware's map view kills this app on the fenix 8, recording or not (0.9.0, 0.9.1 and
// the 0.9.9 post-save trial, SW 23.31). So the watch never asks the firmware for a map. What
// it draws under the breadcrumb is a picture the PHONE made of the rider's spot: a 120 x 120
// mask of water / land / road, a few kilobytes, pushed once over the companion link and kept
// in Storage. Two slots, because a rider has a home spot and a holiday spot and not a
// collection; a third spot evicts the older slot.
//
// Nothing here touches a native view. The mask is decoded ONCE into a BufferedBitmap with a
// three-colour palette and blitted every frame; the breadcrumb is drawn over it with the same
// projection, clipped to the square. Without a snapshot for the rider's position the pages
// draw exactly as 0.9.9 does.
module MapSnapshot {
    const SCHEMA = 1;
    const MAX_CELLS = 120;
    const SLOTS = ["mapA", "mapB"];
    const STORE_NEXT = "mapNext";        // which slot the next new spot overwrites

    // payload keys (docs/watch-map-snapshot.md)
    const K_SCHEMA = "mv";
    const K_ID = "mi";
    const K_NAME = "mn";
    const K_LAT_S = "la";
    const K_LON_W = "lo";
    const K_LAT_N = "lh";
    const K_LON_E = "lx";
    const K_W = "mw";
    const K_H = "mh";
    const K_MASK = "mp";

    // mask classes
    const WATER = 0;
    const LAND = 1;
    const ROAD = 2;

    // The decoded bitmap for the slot last drawn, and which slot it was built from.
    var _bitmap as Graphics.BufferedBitmapReference? = null;
    var _bitmapSlot as String? = null;
    var _bitmapSide as Number = 0;

    // ---- inbound ----

    // Validate and store one snapshot. Untrusted input from another process: every field is
    // type-checked, the box has to be a box, the grid has to fit, and the mask has to decode
    // to exactly `mw` cells per row — or the whole thing is dropped. Returns whether it was
    // kept.
    function store(d as Dictionary) as Boolean {
        if (!(d[K_SCHEMA] instanceof Lang.Number) || (d[K_SCHEMA] as Number) != SCHEMA) {
            return false;
        }
        var id = d[K_ID];
        var la = d[K_LAT_S]; var lo = d[K_LON_W]; var lh = d[K_LAT_N]; var lx = d[K_LON_E];
        var w = d[K_W]; var h = d[K_H]; var mask = d[K_MASK];
        if (!(id instanceof Lang.Number) || !(la instanceof Lang.Number)
                || !(lo instanceof Lang.Number) || !(lh instanceof Lang.Number)
                || !(lx instanceof Lang.Number) || !(w instanceof Lang.Number)
                || !(h instanceof Lang.Number) || !(mask instanceof Lang.ByteArray)) {
            return false;
        }
        if ((la as Number) >= (lh as Number) || (lo as Number) >= (lx as Number)
                || (lh as Number) > 9000000 || (la as Number) < -9000000
                || (lx as Number) > 18000000 || (lo as Number) < -18000000) {
            return false;
        }
        if ((w as Number) < 8 || (w as Number) > MAX_CELLS
                || (h as Number) < 8 || (h as Number) > MAX_CELLS) {
            return false;
        }
        if (!rowsSum(mask as ByteArray, w as Number, h as Number)) {
            return false;
        }
        var name = d[K_NAME];
        var entry = {
            K_ID => id, K_NAME => (name instanceof Lang.String ? name : ""),
            K_LAT_S => la, K_LON_W => lo, K_LAT_N => lh, K_LON_E => lx,
            K_W => w, K_H => h, K_MASK => mask
        };
        var slot = slotFor(id as Number);
        try {
            Storage.setValue(slot, entry);
        } catch (e) {
            return false;
        }
        if (_bitmapSlot != null && _bitmapSlot.equals(slot)) {
            _bitmap = null;             // rebuilt from the new mask on the next draw
            _bitmapSlot = null;
        }
        return true;
    }

    // Every row must decode to exactly `w` cells, and the runs must use up the whole array.
    function rowsSum(mask as ByteArray, w as Number, h as Number) as Boolean {
        var i = 0;
        var n = mask.size();
        for (var row = 0; row < h; row++) {
            var cells = 0;
            while (cells < w) {
                if (i >= n) {
                    return false;
                }
                cells += (mask[i] & 0x3F) + 1;
                i++;
            }
            if (cells != w) {
                return false;
            }
        }
        return i == n;
    }

    // The slot this spot already lives in, else the slot marked next (round robin).
    function slotFor(id as Number) as String {
        for (var s = 0; s < SLOTS.size(); s++) {
            var v = Storage.getValue(SLOTS[s]);
            if (v instanceof Lang.Dictionary && (v as Dictionary)[K_ID] == id) {
                return SLOTS[s];
            }
        }
        var next = Storage.getValue(STORE_NEXT);
        var k = next instanceof Lang.Number ? (next as Number) % SLOTS.size() : 0;
        Storage.setValue(STORE_NEXT, (k + 1) % SLOTS.size());
        return SLOTS[k];
    }

    // ---- lookup ----

    // The slot whose box contains the point, or null. Both slots are read from Storage on
    // every call; they are tiny dictionaries and the caller asks once per frame at 1 Hz.
    function slotForPosition(lat as Float, lon as Float) as String? {
        var la = (lat * 100000.0).toNumber();
        var lo = (lon * 100000.0).toNumber();
        for (var s = 0; s < SLOTS.size(); s++) {
            var v = Storage.getValue(SLOTS[s]);
            if (!(v instanceof Lang.Dictionary)) {
                continue;
            }
            var e = v as Dictionary;
            if (la >= (e[K_LAT_S] as Number) && la <= (e[K_LAT_N] as Number)
                    && lo >= (e[K_LON_W] as Number) && lo <= (e[K_LON_E] as Number)) {
                return SLOTS[s];
            }
        }
        return null;
    }

    function entry(slot as String) as Dictionary? {
        var v = Storage.getValue(slot);
        return v instanceof Lang.Dictionary ? (v as Dictionary) : null;
    }

    function name(slot as String) as String {
        var e = entry(slot);
        if (e == null) {
            return "";
        }
        var n = e[K_NAME];
        return n instanceof Lang.String ? (n as String) : "";
    }

    function clearAll() as Void {
        for (var s = 0; s < SLOTS.size(); s++) {
            Storage.deleteValue(SLOTS[s]);
        }
        _bitmap = null;
        _bitmapSlot = null;
    }

    // ---- the frame ----

    // The snapshot's box as the drawing frame: (latS, lonW, latN, lonE) in degrees plus the
    // squeeze and scale that put it into a square of side `box`, the same arithmetic
    // TrackDraw uses for a track. Returned as [latS, lonW, latN, lonE, squeeze, scale].
    function frame(slot as String, box as Number) as Array<Float>? {
        var e = entry(slot);
        if (e == null) {
            return null;
        }
        var latS = (e[K_LAT_S] as Number) / 100000.0;
        var lonW = (e[K_LON_W] as Number) / 100000.0;
        var latN = (e[K_LAT_N] as Number) / 100000.0;
        var lonE = (e[K_LON_E] as Number) / 100000.0;
        var squeeze = Math.cos((latS + latN) / 2.0 * 0.017453292);
        var s = TrackDraw.scale(box, (lonE - lonW) * squeeze, latN - latS);
        return [latS, lonW, latN, lonE, squeeze, s];
    }

    // ---- the picture ----

    // The mask as a bitmap of side `side` (the square the frame fills), built once per slot
    // and side and kept until the slot changes. Null when the runtime cannot make one — an
    // older device, or memory — in which case the caller draws no ground and nothing else
    // changes.
    function bitmap(slot as String, side as Number) as Graphics.BufferedBitmapReference? {
        if (_bitmap != null && _bitmapSlot != null && _bitmapSlot.equals(slot)
                && _bitmapSide == side) {
            return _bitmap;
        }
        var e = entry(slot);
        if (e == null || side < 8 || !(Graphics has :createBufferedBitmap)) {
            return null;
        }
        var w = e[K_W] as Number;
        var h = e[K_H] as Number;
        var mask = e[K_MASK] as ByteArray;
        var water = Ink.mapWater();
        var land = Ink.mapLand();
        var road = Ink.mapRoad();
        var ref;
        try {
            ref = Graphics.createBufferedBitmap({
                :width => side, :height => side,
                :palette => [water, land, road]
            });
        } catch (ex) {
            return null;
        }
        var bmp = ref.get();
        if (bmp == null) {
            return null;
        }
        var dc = (bmp as Graphics.BufferedBitmap).getDc();
        dc.setColor(water, water);
        dc.clear();
        // Rows are north first, which is the top of the picture: y grows southward on both.
        var i = 0;
        var n = mask.size();
        for (var row = 0; row < h && i < n; row++) {
            var y0 = row * side / h;
            var y1 = (row + 1) * side / h;
            var cells = 0;
            while (cells < w && i < n) {
                var b = mask[i];
                i++;
                var cls = (b >> 6) & 0x3;
                var len = (b & 0x3F) + 1;
                if (cls != WATER) {
                    var x0 = cells * side / w;
                    var x1 = (cells + len) * side / w;
                    dc.setColor(cls == ROAD ? road : land, Graphics.COLOR_TRANSPARENT);
                    dc.fillRectangle(x0, y0, x1 - x0, y1 - y0 > 0 ? y1 - y0 : 1);
                }
                cells += len;
            }
        }
        _bitmap = ref;
        _bitmapSlot = slot;
        _bitmapSide = side;
        return ref;
    }
}
