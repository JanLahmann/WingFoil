import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

// The watch's half of the presentation contract (docs/presentation.md).
//
// `DesignTokens.mc` next door is GENERATED from design/tokens.json and holds nothing but
// literals. This file is the hand-written layer that decides WHICH literal a given watch
// gets, and it exists because the shipped products are not one display family:
//
//   fenix 8 43/47 mm       454 / 416 px, 16 bpp AMOLED, true black
//   fenix 8 Solar 47/51    260 / 280 px, 8 bpp MIP, reflective, no true black
//   fenix 7 / 7S / 7X ...  240-280 px, 8 bpp MIP
//
// The 8 bpp products quantise every colour to {00,55,AA,FF}^3 themselves, so passing the
// AMOLED literal would render correctly anyway — the point of choosing here is that the
// value the code names is the value the glass shows, and that the substitution is a
// reviewable line in a generated file rather than firmware behaviour nobody wrote down.
//
// The second job is contrast. On AMOLED, COLOR_DK_GRAY over true black is a legible ~20 %
// step. On a reflective MIP in sun the background is already mid-grey, and every element the
// app draws in dark grey to mean "this is the OFF half" (the off-foil ring, the unfilled
// foil arc, the sparkline reference, the tally separators) approaches invisible in exactly
// the conditions the app is for. `dim()` is the one place that trade is made.
module Ink {

    // Below this width every product in the manifest is an 8 bpp MIP; at or above it, a
    // 16-bit AMOLED. Read once — getDeviceSettings() allocates, and this is asked for on
    // every drawn row.
    const AMOLED_MIN_PX = 416;

    // Module variables cannot be `hidden` in Monkey C; the leading underscore is the
    // convention this codebase uses for "nothing outside this module reads it".
    var _mip as Boolean = false;
    var _probed as Boolean = false;

    function isMip() as Boolean {
        if (!_probed) {
            _probed = true;
            _mip = System.getDeviceSettings().screenWidth < AMOLED_MIN_PX;
        }
        return _mip;
    }

    // Test seam: the layout suite runs on one device but reasons about both palettes.
    function forceMip(mip as Boolean) as Void {
        _probed = true;
        _mip = mip;
    }

    function reset() as Void {
        _probed = false;
    }

    // ---- the vocabulary ----
    // Phase: "is he on the foil". Teal, NEVER the ladder's green — the Timeline page draws
    // foil bars and outcome dots six rows apart, and one green for both made the page lie.
    function phaseFlying() as Number {
        return isMip() ? DesignTokens.PHASE_FLYING_MIP : DesignTokens.PHASE_FLYING;
    }

    function phaseOffFoil() as Number {
        return isMip() ? DesignTokens.PHASE_OFF_FOIL_MIP : DesignTokens.PHASE_OFF_FOIL;
    }

    // The outcome ladder: a verdict scale, and nothing outside a maneuver outcome may
    // borrow it (docs/presentation.md).
    function ladderFlew() as Number {
        return isMip() ? DesignTokens.OUTCOME_FLEW_MIP : DesignTokens.OUTCOME_FLEW;
    }

    function ladderTouchdown() as Number {
        return isMip() ? DesignTokens.OUTCOME_TOUCHDOWN_MIP : DesignTokens.OUTCOME_TOUCHDOWN;
    }

    function ladderFellIn() as Number {
        return isMip() ? DesignTokens.OUTCOME_FELL_IN_MIP : DesignTokens.OUTCOME_FELL_IN;
    }

    // No verdict yet / a course change. Grey on purpose: it is the absence of a rung.
    function ladderNone() as Number {
        return isMip()
            ? DesignTokens.OUTCOME_COURSE_CHANGE_MIP : DesignTokens.OUTCOME_COURSE_CHANGE;
    }

    // The clean jibe. A STRICTER question than the ladder's top rung — score carried AND the
    // foil never lost across the scored window — so it gets an ink of its own and may not
    // borrow `ladderFlew()`. If it did, the Turns page would draw one green for "flew through"
    // and the same green for "flew through and carried it", which is the whole distinction the
    // metric exists to make (docs/presentation.md "Clean jibe").
    function cleanJibe() as Number {
        return isMip() ? DesignTokens.CLEAN_JIBE_MIP : DesignTokens.CLEAN_JIBE;
    }

    // Effort, not verdict: a record is something he DID, not something that went well.
    // The PB flash and the record numbers use this, so green never means "personal best".
    function effortWindow() as Number {
        return isMip() ? DesignTokens.EFFORT_WINDOW_MIP : DesignTokens.EFFORT_WINDOW;
    }

    // Pumping / heart-rate ink. Heart rate is not a verdict either, so it stops being the
    // ladder's red the moment a page carries both a pulse and a swim.
    function effortPumping() as Number {
        return isMip() ? DesignTokens.EFFORT_PUMPING_MIP : DesignTokens.EFFORT_PUMPING;
    }

    // ---- contrast ----
    // "Drawn, but subordinate": the off half of a two-state mark. Dark grey on AMOLED,
    // the phase grey on MIP, where dark grey over a reflective mid-grey ground is nothing.
    function dim() as Number {
        return isMip() ? DesignTokens.PHASE_OFF_FOIL_MIP : Graphics.COLOR_DK_GRAY;
    }
}
