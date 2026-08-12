#!/usr/bin/env python3
"""Invite-beta unlock keys for the WingFoil Connect IQ device app.

Connect IQ "beta app" listings are visible only to the developer account, so external
testers can only be reached through a PUBLIC store listing. The invite build
(`garmin/monkey-invite.jungle`, own UUID, "WingFoil - Invite Beta") is therefore a public
listing whose app is *locked* until an individual key is entered in Garmin Connect. This
tool mints those keys.

Scheme (see docs/decisions.md ADR-012 — obfuscation-grade, NOT DRM)
------------------------------------------------------------------
    pepper  P  = SHA256("wingfoil-unlock-pepper-v1" + UNLOCK_SECRET)[:8]   (8 bytes)
    request R  = B32_40(FNV1a64(utf8(device_id)))                          (8 chars)
    unlock  K  = B32_40(FNV1a64(P || utf8(R)))                             (8 chars)

`B32_40` is the top 40 bits of the 64-bit FNV-1a digest rendered in Crockford's base32
(no I/L/O/U — the code has to be read off a watch face and typed on a phone).

The watch computes R from `System.getDeviceSettings().uniqueIdentifier` and K from the
pepper compiled into the invite build, then compares. Both halves are the *same* pure
integer function here and in `garmin/source/lock/LockGate.mc`; `--check` asserts that with
shared test vectors, and the Monkey C unit test `unlockKeyMatchesKeygenVectors` asserts the
other side of the same vectors.

Why not HMAC: the watch cannot hold the secret (a .prg is trivially unpacked) and cannot
compute HMAC-SHA256 cheaply, so any scheme the watch can verify offline is by construction
forgeable by whoever extracts the pepper. Rather than pretend otherwise, the pepper *is*
the whole secret, it never enters git, and the threat model is "a handful of invited
testers", not piracy.

The UNLOCK_SECRET lives in the gitignored `lab/.env` and is never printed by this tool.

Usage
-----
    python lab/tools/make_unlock.py --check              # algorithm self-test, no secret
    python lab/tools/make_unlock.py --emit-pepper        # write garmin/gen/UnlockPepper.mc
    python lab/tools/make_unlock.py ABCD1234             # request code -> unlock key
    python lab/tools/make_unlock.py --request-code <id>  # device id -> request code (debug)

Per tester (the whole loop)
---------------------------
  1. Tester installs "WingFoil - Invite Beta" from the store and opens it. The app shows a
     lock screen with an 8-character REQUEST CODE and sends it to you.
  2. `python lab/tools/make_unlock.py <THEIR CODE>` -> the unlock key.
  3. Mail the key back. They enter it under Garmin Connect > the app > Settings >
     "Unlock key", and the app opens as soon as the phone pushes the setting across.
That key works on that one watch forever, including after a reinstall, and on no other.

Once per machine (not per tester)
---------------------------------
  `--emit-pepper` before building the invite jungle. The generated file is gitignored, so a
  fresh clone needs it re-emitted — from the same UNLOCK_SECRET, which keeps every key
  already issued valid.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ENV_PATH = REPO / "lab" / ".env"
GEN_PATH = REPO / "garmin" / "gen" / "UnlockPepper.mc"

# Crockford base32: no I, L, O, U. Keep in lockstep with LockGate.ALPHABET.
ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
CODE_LEN = 8

PEPPER_DOMAIN = "wingfoil-unlock-pepper-v1"
PEPPER_BYTES = 8

# FNV-1a 64-bit, held as two 32-bit halves. The halves are not decoration: Monkey C's Long
# is 64-bit and its overflow behaviour on multiply is undocumented, so LockGate multiplies
# through the same halves, where every intermediate stays below 2^42 and no wrap-around can
# happen. This mirror keeps the two implementations line-for-line comparable.
MASK32 = 0xFFFFFFFF
OFFSET_HI, OFFSET_LO = 0xCBF29CE4, 0x84222325  # 0xcbf29ce484222325
PRIME_HI, PRIME_LO = 0x100, 0x1B3  # 0x100000001b3


def fnv1a64(data: bytes) -> tuple[int, int]:
    """FNV-1a 64-bit over `data`, returned as (hi32, lo32)."""
    hi, lo = OFFSET_HI, OFFSET_LO
    for b in data:
        lo ^= b
        t = lo * PRIME_LO  # < 2^41
        nlo = t & MASK32
        carry = t >> 32  # <= 0x1b3
        nhi = (hi * PRIME_LO + lo * PRIME_HI + carry) & MASK32
        hi, lo = nhi, nlo
    return hi, lo


def base32_40(hi: int, lo: int) -> str:
    """Top 40 bits of the digest as 8 Crockford-base32 characters."""
    v = (hi << 8) | (lo >> 24)
    return "".join(ALPHABET[(v >> (35 - 5 * i)) & 31] for i in range(CODE_LEN))


def digest(data: bytes) -> str:
    return base32_40(*fnv1a64(data))


def request_code(device_id: str) -> str:
    """What the watch shows on its lock screen for this device."""
    return digest(device_id.encode("utf-8"))


def unlock_key(pepper: bytes, code: str) -> str:
    """The key that unlocks `code` on a build carrying `pepper`."""
    return digest(bytes(pepper) + normalize(code).encode("utf-8"))


def normalize(raw: str) -> str:
    """Same forgiving read as the watch: upper-case, I/L->1, O->0, drop everything else."""
    out = []
    for ch in raw.upper():
        if ch in "IL":
            ch = "1"
        elif ch == "O":
            ch = "0"
        if ch in ALPHABET:
            out.append(ch)
    return "".join(out)


def pepper_from_secret(secret: str) -> bytes:
    return hashlib.sha256((PEPPER_DOMAIN + secret).encode("utf-8")).digest()[:PEPPER_BYTES]


def read_secret() -> str:
    """UNLOCK_SECRET out of lab/.env. Never echoed anywhere."""
    if not ENV_PATH.exists():
        sys.exit(f"missing {ENV_PATH} — see docs/decisions.md ADR-012")
    for line in ENV_PATH.read_text().splitlines():
        line = line.strip()
        if line.startswith("UNLOCK_SECRET="):
            secret = line.split("=", 1)[1].strip().strip("'\"")
            if len(secret) < 32:
                sys.exit("UNLOCK_SECRET in lab/.env is too short (want >= 32 hex chars)")
            return secret
    sys.exit(
        "no UNLOCK_SECRET in lab/.env — add one with:\n"
        '  python -c "import secrets;print(\'UNLOCK_SECRET=\'+secrets.token_hex(32))"'
        " >> lab/.env"
    )


# ---------------------------------------------------------------- shared test vectors
# Hard-coded on BOTH sides of the port. The identical table lives in
# garmin/tests/WingfoilTests.mc (unlockKeyMatchesKeygenVectors); if either implementation
# drifts, one of the two suites goes red. Pepper and codes are arbitrary constants, not
# derived from any real secret.
VECTOR_PEPPER = bytes([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
VECTORS = [
    # (device id, expected request code, expected unlock key for VECTOR_PEPPER)
    ("wingfoil", "PTMDBDNY", "MWTSPKVB"),
    ("ac915d426451c88e8ea691fa412f9af9c21b4d12", "N3J986JP", "MJFJ4PD4"),
    ("", "SFS9SS44", "1PT5WKZK"),
]


def self_check() -> int:
    ok = True
    for device_id, want_code, want_key in VECTORS:
        got_code = request_code(device_id)
        got_key = unlock_key(VECTOR_PEPPER, got_code)
        code_ok = got_code == want_code
        key_ok = got_key == want_key
        ok = ok and code_ok and key_ok
        print(
            f"  id={device_id!r:44s} code={got_code} "
            f"{'ok ' if code_ok else 'WANT ' + want_code} "
            f"key={got_key} {'ok' if key_ok else 'WANT ' + want_key}"
        )
    # Structural invariants the watch relies on.
    assert len(ALPHABET) == 32 and len(set(ALPHABET)) == 32
    assert not (set("ILOU") & set(ALPHABET))
    for _, code, key in VECTORS:
        assert len(code) == CODE_LEN and len(key) == CODE_LEN
    # A one-bit change in the request code must not leave the key alone.
    assert unlock_key(VECTOR_PEPPER, "PTMDBDNY") != unlock_key(VECTOR_PEPPER, "PTMDBDNZ")
    # A different pepper must mint different keys (that is the whole gate).
    assert unlock_key(bytes(8), "PTMDBDNY") != unlock_key(VECTOR_PEPPER, "PTMDBDNY")
    # The forgiving reader must not change what a well-formed code means.
    assert normalize(" ptm-dbdny ") == "PTMDBDNY"
    assert normalize("i0lo") == "1010"
    print("self-check: PASS" if ok else "self-check: FAIL")
    return 0 if ok else 1


# ---------------------------------------------------------------- pepper emission
GEN_HEADER = """// GENERATED by lab/tools/make_unlock.py --emit-pepper — DO NOT COMMIT, DO NOT EDIT.
//
// The invite-beta pepper (docs/decisions.md ADR-012). Only monkey-invite.jungle puts this
// directory on the source path; monkey.jungle / monkey-beta.jungle compile the all-zero
// stub in garmin/source-nopepper/ instead, which disables the gate entirely.
//
// This file is derived from UNLOCK_SECRET in lab/.env and is gitignored. Losing it is
// harmless — re-emit it from the same secret and every already-issued key still works.
import Toybox.Lang;

module UnlockPepper {
    function bytes() as Array<Number> {
        return [%s] as Array<Number>;
    }
}
"""


def emit_pepper(pepper: bytes) -> None:
    GEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    body = ", ".join(str(b) for b in pepper)
    GEN_PATH.write_text(GEN_HEADER % body)
    print(f"wrote {GEN_PATH.relative_to(REPO)} ({len(pepper)} pepper bytes, not shown)")
    _warn_if_tracked(GEN_PATH)


def _warn_if_tracked(path: Path) -> None:
    import subprocess

    try:
        r = subprocess.run(
            ["git", "check-ignore", "-q", str(path)], cwd=REPO, capture_output=True
        )
    except OSError:
        return
    if r.returncode != 0:
        print(
            f"WARNING: {path.relative_to(REPO)} is NOT gitignored — fix .gitignore before"
            " committing anything",
            file=sys.stderr,
        )


def main() -> int:
    ap = argparse.ArgumentParser(
        description="WingFoil invite-beta unlock keys",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Usage\n-----\n", 1)[1],
    )
    ap.add_argument("code", nargs="?", help="request code shown on the tester's watch")
    ap.add_argument("--check", action="store_true", help="algorithm self-test (no secret)")
    ap.add_argument(
        "--emit-pepper",
        action="store_true",
        help="write garmin/gen/UnlockPepper.mc for the invite build",
    )
    ap.add_argument(
        "--request-code",
        metavar="DEVICE_ID",
        help="compute the request code for a device id (debugging)",
    )
    args = ap.parse_args()

    if args.check:
        return self_check()

    if args.request_code is not None:
        print(request_code(args.request_code))
        return 0

    if args.emit_pepper:
        emit_pepper(pepper_from_secret(read_secret()))
        if args.code is None:
            return 0

    if args.code is None:
        ap.print_help()
        return 2

    code = normalize(args.code)
    if len(code) != CODE_LEN or not re.fullmatch(f"[{ALPHABET}]{{{CODE_LEN}}}", code):
        sys.exit(f"request code must be {CODE_LEN} base32 characters, got {args.code!r}")
    key = unlock_key(pepper_from_secret(read_secret()), code)
    print(f"request code : {code}")
    print(f"unlock key   : {key}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
