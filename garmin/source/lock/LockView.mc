import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The invite-beta lock screen. Only ever reached in the invite build (LockGate.enabled());
// the public app and the beta build go straight to StartView.
//
// Everything a tester needs is on one screen: which app this is, that it is an invite beta
// rather than broken, the request code to send, and where the key goes. The request code is
// the only thing anyone has to transcribe, so it gets the biggest font that fits the round
// glass — measured through the same chord helpers the recording pages use, and asserted by
// lockScreenFitsRoundDisplay in the unit suite.
class LockView extends WatchUi.View {
    // Vector faces to try, best first; getVectorFont returns null for anything a device does
    // not have, which drops us onto the bitmap ladder below.
    //
    // They are tried ONE AT A TIME rather than handed to getVectorFont as a preference list,
    // because "the device has a face by this name" and "that face can draw this string" are
    // different questions. On the epix 2 / epix 2 Pro / MARQ 2 / Descent Mk3 families the
    // face named `BionicBold` is `Bionic_Bold_Number_Only` — a DIGITS-ONLY cut. Ask it for
    // the width of "WWWWWWWW" and it answers 0, which every width test in a fitter reads as
    // "fits comfortably", so the fitter would hand back the largest size on the list and the
    // lock screen would draw the tester's request code with its five letters missing. The
    // request code is the one string a human has to transcribe, so a face is only accepted
    // if it can draw every character LockGate.ALPHABET can produce (see coversAlphabet).
    static const VEC_FACES = ["BionicBold", "BionicMedium", "RobotoCondensedBold"];
    static const VEC_MAX = 84;
    static const VEC_MIN = 42;
    static const VEC_STEP = 6;
    // Fit the code to this percentage of the chord rather than all of it. Fitting to 100 %
    // lands the corners exactly ON the glass edge, which is inside the test but not inside
    // a bezel, a screen protector or the 43 mm face's rounding.
    static const CODE_FIT_PCT = 90;

    // Rows as fractions of screen height (x1000), so the layout survives the 416 px 43 mm
    // face and the 454 px 47 mm one without a per-device table.
    static const ROWS = [190, 302, 452, 618, 712, 800];
    static const ROW_TITLE = 0;
    static const ROW_KIND = 1;
    static const ROW_CODE = 2;
    static const ROW_STATUS = 3;
    static const ROW_HINT1 = 4;
    static const ROW_HINT2 = 5;

    function initialize() {
        View.initialize();
    }

    // Vertical centre of a row on a screen `h` pixels tall.
    static function rowY(h as Number, row as Number) as Number {
        return h * ROWS[row] / 1000;
    }

    static function ladder() as Array<Graphics.FontType> {
        return [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
            Graphics.FONT_XTINY] as Array<Graphics.FontType>;
    }

    // Largest font that renders the 8-character code inside the chord at its row.
    //
    // The bitmap ladder is the FLOOR, not just the no-vector-fonts fallback. On the fenix 8
    // family the vector faces beat it comfortably, but on the fenix 7 family (240-280 px) the
    // widest vector size that fits an 8-character code is 42 px, which is SHORTER than that
    // variant's FONT_LARGE — taking the vector font there would have shrunk the one string a
    // tester has to transcribe. So: measure the ladder first, then only accept a vector size
    // that is genuinely taller.
    static function codeFont(dc as Dc, code as String) as Graphics.FontType {
        var radius = RecordingView.fitRadius(dc, false, false);
        var dy = (rowY(dc.getHeight(), ROW_CODE) - dc.getHeight() / 2).abs();
        var l = ladder();
        var best = RecordingView.fitFont(dc, l, 0, code,
            RecordingView.rowBudget(radius, dy, dc.getFontHeight(l[0])) * CODE_FIT_PCT / 100);
        if (Graphics has :getVectorFont) {
            var floor = dc.getFontHeight(best);
            for (var size = VEC_MAX; size >= VEC_MIN; size -= VEC_STEP) {
                var anyTaller = false;
                for (var i = 0; i < VEC_FACES.size(); i++) {
                    var vf = Graphics.getVectorFont(
                        {:face => VEC_FACES[i], :size => size});
                    if (vf == null) {
                        continue;   // this device does not have that face
                    }
                    // FULL font height, not the ink height the recording pages fit on: this
                    // row has one job and can afford the margin, and it keeps the fitter and
                    // lockScreenFitsRoundDisplay measuring the same box.
                    var h = dc.getFontHeight(vf);
                    if (h <= floor) {
                        continue;   // the ladder already beats this face at this size
                    }
                    anyTaller = true;
                    if (!coversAlphabet(dc, vf)) {
                        continue;   // a number-only cut — see VEC_FACES
                    }
                    if (dc.getTextWidthInPixels(code, vf)
                            <= RecordingView.rowBudget(radius, dy, h) * CODE_FIT_PCT / 100) {
                        return vf;
                    }
                }
                if (!anyTaller) {
                    break;      // every face here is shorter than the ladder, and smaller
                                // sizes only get shorter
                }
            }
        }
        return best;
    }

    // Can `f` actually draw a request code? A font a device does not have the glyphs for
    // measures its missing characters at zero width, and zero width sails through every fit
    // test there is — so the fitter has to ask the question outright, one character of
    // LockGate.ALPHABET at a time, and bail at the first one that comes back empty. A
    // digits-only face fails on 'A', the eleventh character, so this costs eleven width
    // lookups on the devices it exists for, on a screen that is drawn once.
    static function coversAlphabet(dc as Dc, f as Graphics.VectorFont) as Boolean {
        var a = LockGate.ALPHABET;
        for (var i = 0; i < a.length(); i++) {
            if (dc.getTextWidthInPixels(a.substring(i, i + 1), f) <= 0) {
                return false;
            }
        }
        return true;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var code = LockGate.requestCode();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        centered(dc, cx, rowY(h, ROW_TITLE), Graphics.FONT_SMALL, "WingFoil");

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        centered(dc, cx, rowY(h, ROW_KIND), Graphics.FONT_XTINY, "INVITE BETA");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        centered(dc, cx, rowY(h, ROW_CODE), codeFont(dc, code), code);

        if (LockGate.rejected()) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            centered(dc, cx, rowY(h, ROW_STATUS), Graphics.FONT_XTINY, "key not valid");
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            centered(dc, cx, rowY(h, ROW_STATUS), Graphics.FONT_XTINY, "send this code");
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        centered(dc, cx, rowY(h, ROW_HINT1), Graphics.FONT_XTINY, "key goes in Garmin");
        centered(dc, cx, rowY(h, ROW_HINT2), Graphics.FONT_XTINY, "Connect app settings");
    }

    hidden function centered(dc as Dc, cx as Number, y as Number, font as Graphics.FontType,
            text as String) as Void {
        dc.drawText(cx, y, font, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// No way past this screen: START re-reads the setting (so a tester who typed the key while
// the app was open does not have to guess whether it took), BACK leaves the app.
class LockDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        if (LockGate.refresh()) {
            getApp().unlockedNow();
        } else {
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onBack() as Boolean {
        System.exit();
    }
}
