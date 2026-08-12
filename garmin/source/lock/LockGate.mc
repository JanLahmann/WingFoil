import Toybox.Application.Properties;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// Invite-beta unlock gate (docs/decisions.md ADR-012).
//
// Connect IQ beta listings are visible only to the developer account, so external testers
// need a PUBLIC listing — and a public listing anyone can install needs a lock. This module
// is that lock: the watch shows an 8-character REQUEST CODE derived from its own device id,
// Jan runs `lab/tools/make_unlock.py <code>` and mails back an 8-character UNLOCK KEY, the
// tester types it into the app's Garmin Connect settings, and the app opens — for good, on
// that watch only.
//
// The scheme, honestly stated:
//     pepper  P = 8 bytes compiled into the invite build only (gitignored, from lab/.env)
//     request R = B32_40(FNV1a64(device id))
//     unlock  K = B32_40(FNV1a64(P || R))
// The watch verifies by recomputing K, so the pepper is the entire secret and anyone who
// unpacks the .prg can mint keys. That is unavoidable for offline per-device verification
// (a watch cannot hold an HMAC secret any better than it can hold this one) and fine for
// the threat model: a handful of invited testers on a free hobby app. It is a "please
// don't", not DRM.
//
// The same integer arithmetic lives in lab/tools/make_unlock.py; the shared test vectors in
// both suites are what keep them equal.
//
// The pepper comes from module UnlockPepper, which is supplied by exactly one source
// directory per build: garmin/source-nopepper/ (all zeros, gate off — public + beta builds)
// or garmin/gen/ (generated, gate on — invite build only).
module LockGate {
    // Crockford base32 — no I, L, O or U, because the code is read off a round watch face
    // and typed on a phone. Keep in lockstep with make_unlock.py ALPHABET.
    const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    const CODE_LEN = 8;

    const PROP_KEY = "unlockKey";       // GCM string setting the tester types into
    const STORE_OK = "unlockedFor";     // request code this watch is unlocked for
    const STORE_DEV = "lockDeviceId";   // fallback id when uniqueIdentifier is null

    // FNV-1a 64-bit held as two 32-bit halves. Monkey C's Long is 64-bit but its behaviour
    // on multiply overflow is undocumented, and a hash that silently saturates instead of
    // wrapping would disagree with the keygen on some devices and not others — the worst
    // possible failure here. Multiplying through the halves keeps every intermediate below
    // 2^42, so no overflow is possible and the result is exact by construction.
    const MASK32 = 0xffffffffl;
    const OFFSET_HI = 0xcbf29ce4l;      // 0xcbf29ce484222325
    const OFFSET_LO = 0x84222325l;
    const PRIME_HI = 0x100l;            // 0x100000001b3
    const PRIME_LO = 0x1b3l;

    var _code as String? = null;
    var _unlocked as Boolean = false;
    var _rejected as Boolean = false;

    // ---- pure hash core (unit-tested against the keygen's vectors) ----

    // FNV-1a 64 over `bytes`, returned as [hi32, lo32].
    function fnv1a64(bytes as Array<Number>) as Array<Long> {
        var hi = OFFSET_HI;
        var lo = OFFSET_LO;
        for (var i = 0; i < bytes.size(); i++) {
            lo = lo ^ (bytes[i] & 0xff).toLong();
            var t = lo * PRIME_LO;                  // < 2^41
            var nlo = t & MASK32;
            var carry = t >> 32;                    // <= 0x1b3
            var nhi = (hi * PRIME_LO + lo * PRIME_HI + carry) & MASK32;
            hi = nhi;
            lo = nlo;
        }
        return [hi, lo] as Array<Long>;
    }

    // Top 40 bits of the digest as 8 base32 characters.
    function base32_40(h as Array<Long>) as String {
        var v = (h[0] << 8) | (h[1] >> 24);         // < 2^40
        var s = "";
        for (var i = 0; i < CODE_LEN; i++) {
            var idx = ((v >> (35 - 5 * i)) & 31l).toNumber();
            var c = ALPHABET.substring(idx, idx + 1);
            s += (c != null) ? c : "0";
        }
        return s;
    }

    function digest(bytes as Array<Number>) as String {
        return base32_40(fnv1a64(bytes));
    }

    // The code shown on the lock screen for a given device id.
    function requestCodeFor(deviceId as String) as String {
        return digest(deviceId.toUtf8Array());
    }

    // The key that opens `code` on a build carrying `pepper`. Pepper is a parameter rather
    // than a global read so the tests can drive this with a known one.
    function keyFor(pepper as Array<Number>, code as String) as String {
        var bytes = [] as Array<Number>;
        bytes.addAll(pepper);
        bytes.addAll(normalize(code).toUtf8Array());
        return digest(bytes);
    }

    // Forgiving read of what a tester typed: upper-cases, folds the base32 look-alikes
    // (I/L -> 1, O -> 0) and drops spaces, dashes and anything else. Mirrors make_unlock.py.
    function normalize(raw as String) as String {
        var chars = raw.toUpper().toCharArray();
        var out = "";
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i];
            if (ch == 'I' || ch == 'L') {
                ch = '1';
            } else if (ch == 'O') {
                ch = '0';
            }
            var s = ch.toString();
            if (ALPHABET.find(s) != null) {
                out += s;
            }
        }
        return out;
    }

    function matches(pepper as Array<Number>, code as String, entered as String) as Boolean {
        return normalize(entered).equals(keyFor(pepper, code));
    }

    // ---- build wiring ----

    function isZero(pepper as Array<Number>) as Boolean {
        for (var i = 0; i < pepper.size(); i++) {
            if (pepper[i] != 0) {
                return false;
            }
        }
        return true;
    }

    // False in the public app and the beta build (zero pepper), true in the invite build.
    // Every gate entry point short-circuits on this, so the shipped app pays one array scan
    // at startup and nothing else.
    function enabled() as Boolean {
        return !isZero(UnlockPepper.bytes());
    }

    // ---- device identity ----

    // `uniqueIdentifier` is a per-app, per-device alphanumeric that survives uninstall and
    // reinstall (verified present on fenix847mm in the SDK 9.2 api.debug.xml) — exactly the
    // stability a request code needs, and no more identifying than a random number since it
    // differs per app id. It is documented as nullable, so a first-run random id persisted
    // in Storage backs it up; that one only survives while the app is installed, which for a
    // tester means a reinstall costs one new key.
    function deviceId() as String {
        var uid = System.getDeviceSettings().uniqueIdentifier;
        if (uid != null && uid.length() > 0) {
            return uid;
        }
        var stored = null;
        try {
            stored = Storage.getValue(STORE_DEV);
        } catch (e) {
        }
        if (stored instanceof Lang.String && (stored as String).length() > 0) {
            return stored as String;
        }
        var gen = Time.now().value().toString() + "-" + System.getTimer().toString() + "-"
            + Math.rand().toString();
        try {
            Storage.setValue(STORE_DEV, gen);
        } catch (e) {
        }
        return gen;
    }

    // Cached: the hash is cheap but the device id read is not free, and the lock screen
    // redraws once a second.
    function requestCode() as String {
        if (_code == null) {
            _code = requestCodeFor(deviceId());
        }
        return _code as String;
    }

    // ---- gate state ----

    function isUnlocked() as Boolean {
        return _unlocked;
    }

    // True once a non-empty key has been entered that did not open the gate — the lock
    // screen says so rather than looking like nothing happened.
    function rejected() as Boolean {
        return _rejected;
    }

    // Re-reads the stored unlock and the GCM setting. Called at startup and from
    // onSettingsChanged, which is what makes the key take effect without a restart.
    function refresh() as Boolean {
        if (!enabled()) {
            _unlocked = true;
            return true;
        }
        if (_unlocked) {
            return true;
        }
        var code = requestCode();
        var saved = null;
        try {
            saved = Storage.getValue(STORE_OK);
        } catch (e) {
        }
        // Bound to the request code, so a settings backup restored onto a different watch
        // does not carry the unlock with it.
        if (saved instanceof Lang.String && (saved as String).equals(code)) {
            _unlocked = true;
            return true;
        }
        var entered = null;
        try {
            entered = Properties.getValue(PROP_KEY);
        } catch (e) {
        }
        if (entered instanceof Lang.String) {
            var typed = normalize(entered as String);
            if (typed.length() > 0) {
                if (matches(UnlockPepper.bytes(), code, typed)) {
                    _unlocked = true;
                    _rejected = false;
                    try {
                        Storage.setValue(STORE_OK, code);
                    } catch (e) {
                    }
                } else {
                    _rejected = true;
                }
            }
        }
        return _unlocked;
    }
}
