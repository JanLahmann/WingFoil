import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// The CleanJibe mark on the glass.
//
// It is drawn on exactly two screens, and both were picked for the same reason: they are the
// two moments the rider is NOT reading a number. The start page is the wait for a GPS fix,
// and the post-save verdict page is the walk back up the beach. Every screen between them is
// a screen he is glancing at one-handed on the water, and a logo on one of those is ink spent
// where attention is not idle.
//
// WHY A BITMAP AND NOT PRIMITIVES. The mark is the launcher icon's own artwork
// (brand/icon-tile.svg) — one gradient stroke that draws a jibe, and a filled wing. Redrawing it
// with Dc calls would be a second, drifting copy of the brand, and the app already has one
// generated-from-the-source rule for exactly that reason (DesignTokens.mc). It ships as a
// cut of the master instead, made by garmin/tools/make_brand_mark.py.
//
// ONE CUT PER RESOURCE DIRECTORY, because a bitmap does not scale. The jungle already maps
// every product to a launcher-icon qualifier directory, and that mapping happens to be
// exactly the partition the mark needs: the six 454 px AMOLED products take the base
// `resources/` cut, `resources-icon60`/`-icon54` hold the smaller AMOLED cut for the 390 px
// members of their families, and `resources-icon40`'s audience is precisely the thirteen
// 8 bpp MIP products — where the cut is flat, quantised to {00,55,AA,FF}^3 in the generator
// rather than on the watch (ADR: the generator's own header carries the palette reasoning).
//
// EACH CUT IS SIZED BY ITS HEIGHT, not its width: the artwork is very nearly square since
// the mark learned to jibe, and the vertical air is the dimension both pages are short of.
//
// NOTHING HERE ASSUMES THE MARK FITS. Both callers ask `fits()` first and simply do not draw
// it when the answer is no — the same "drop content, never size" rule the text rows follow.
// The layout suite asserts the answer is yes on the documented device matrix, so a "no" on a
// device would be a missing logo rather than a logo drawn over a line of text.
module Brand {

    // TWO CUTS, because the two screens want different weights and a bitmap does not scale.
    // The MARK is the start page's, sized to the air above the wordmark. The BADGE is the
    // verdict page's, sized to the SAVED eyebrow it rides beside, so the pair reads as one
    // piece of ink at the height of the word rather than as a logo that has wandered into
    // the giant's space — measured on the fenix 8, the 46 px mark centred on that eyebrow
    // reaches the top of the digits and the 19 px badge sits inside the word's own band.
    //
    // Each is loaded on first use and given back when its page goes away, because the pages
    // that draw NEITHER are the long-running ones: a recording session should not carry a few
    // KB of decoration it will not use again until the rider presses save.
    var _mark as WatchUi.BitmapResource? = null;
    var _badge as WatchUi.BitmapResource? = null;

    function mark() as WatchUi.BitmapResource {
        if (_mark == null) {
            _mark = WatchUi.loadResource(Rez.Drawables.BrandMark) as WatchUi.BitmapResource;
        }
        return _mark as WatchUi.BitmapResource;
    }

    function badge() as WatchUi.BitmapResource {
        if (_badge == null) {
            _badge = WatchUi.loadResource(Rez.Drawables.BrandBadge) as WatchUi.BitmapResource;
        }
        return _badge as WatchUi.BitmapResource;
    }

    function release() as Void {
        _mark = null;
        _badge = null;
    }

    function w() as Number {
        return mark().getWidth();
    }

    function h() as Number {
        return mark().getHeight();
    }

    function badgeW() as Number {
        return badge().getWidth();
    }

    function badgeH() as Number {
        return badge().getHeight();
    }

    // The furthest corner of a `bw` x `bh` box centred at (cx + dx, cy + dy), as a radius from
    // the centre of the glass. Same measurement the layout suite makes of a row of text, and
    // deliberately the same shape of function, so the mark is held to the chord rule the rows
    // are held to rather than to a rule of its own.
    function cornerR(bw as Number, bh as Number, dx as Number, dy as Number) as Float {
        var ax = dx.abs() + bw / 2.0;
        var ay = dy.abs() + bh / 2.0;
        return Math.sqrt(ax * ax + ay * ay);
    }

    // Does a box of the mark's size, centred `dx`/`dy` from the middle of the glass, sit
    // inside the page's own radius AND inside the glass at all? The second half is not
    // implied by the first: `radius` is measured from the centre, and a box that clears the
    // chord can still have been placed with its top edge off the top of the screen.
    function fits(dc as Dc, radius as Number, dx as Number, dy as Number) as Boolean {
        var bh = h();
        if (dc.getHeight() / 2 + dy - bh / 2 < 0) {
            return false;
        }
        return cornerR(w(), bh, dx, dy) <= radius.toFloat();
    }

    // Centred on (x, y).
    function draw(dc as Dc, x as Number, y as Number) as Void {
        var b = mark();
        dc.drawBitmap(x - b.getWidth() / 2, y - b.getHeight() / 2, b);
    }

    function drawBadge(dc as Dc, x as Number, y as Number) as Void {
        var b = badge();
        dc.drawBitmap(x - b.getWidth() / 2, y - b.getHeight() / 2, b);
    }
}
