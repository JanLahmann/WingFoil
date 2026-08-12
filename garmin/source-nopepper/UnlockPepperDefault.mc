import Toybox.Lang;

// The DISABLED pepper: eight zero bytes, which LockGate.enabled() reads as "no gate".
// This directory is on the source path of monkey.jungle and monkey-beta.jungle — the public
// app and the developer beta ship with the lock compiled in but permanently open.
//
// monkey-invite.jungle swaps this directory for garmin/gen/, which holds the real pepper
// emitted by `lab/tools/make_unlock.py --emit-pepper` and is gitignored. Exactly one of the
// two directories is ever on a source path, so module UnlockPepper is never defined twice.
module UnlockPepper {
    function bytes() as Array<Number> {
        return [0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
    }
}
