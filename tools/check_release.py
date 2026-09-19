#!/usr/bin/env python3
"""The release safety net: the version sites agree, and each channel is what it claims to be.

    python3 tools/check_release.py                 # the source-side checks
    python3 tools/check_release.py --binary PATH   # …and the strings check over a built app

Two things go wrong when a release is cut by hand, and both are cheap to catch and expensive
to miss (docs/engineering.md, item 4).

**The version sites drift.** A version is stamped in eight places across four implementations
and nothing compares them: the iPhone's marketing and build numbers in `ios/project.yml`, the
watch's three manifests, and the engine version in the lab, the kit, the web bundle and two
documents. `package.sh` already refuses to build three disagreeing manifests; this does the
same for the other five.

**A channel ships a door it does not have.** docs/testing.md, "Three channels", names four
greps that prove a release binary carries no beta or dev feature. They were prose. They are
this file now: the compile flags, the generated Info.plist, the channel's cut of the brand
mark, and — over a built binary — the two strings the beta and the dev doors cannot be built
without.

Stdlib only, like every other check in this repo, so it runs on a bare interpreter in CI.
Exit code 0 when everything agrees, 1 on the first disagreement (all of them are printed).
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

PROJECT = ROOT / "ios" / "project.yml"
MANIFESTS = [
    ROOT / "garmin" / "manifest.xml",
    ROOT / "garmin" / "manifest-beta.xml",
    ROOT / "garmin" / "manifest-dev.xml",
]
LAB_INIT = ROOT / "lab" / "src" / "wingfoil_lab" / "__init__.py"
BUNDLE_INIT = ROOT / "web" / "lab_bundle" / "wingfoil_lab" / "__init__.py"
KIT_ANALYSIS = ROOT / "ios" / "WingFoilKit" / "Sources" / "WingFoilKit" / "AnalysisEngine" / "SessionAnalysis.swift"
ALGORITHMS = ROOT / "docs" / "algorithms.md"
CHANNELS = ROOT / "docs" / "channels.md"
INFO_RELEASE = ROOT / "ios" / "WingFoil" / "Info-Release.plist"

# The release channel's Info.plist may not name a permission or a document type that only the
# beta or dev channel has a door for (docs/testing.md, "Three channels" — the plist check).
PLIST_FORBIDDEN = re.compile(r"NSHealth|NSLocation|NSBluetooth|gpx|tcx")

# What a built binary must not contain, and where the door it belongs to is gated. Both are
# pinned in docs/testing.md with the same `strings … | grep -c` one-liners this replaces.
BINARY_NEEDLES = [
    ("version.json", "release", "the beta's update check (#if BETA)"),
    ("Sync the library with iCloud Drive", "release, beta", "the dev iCloud Drive door (#if DEV)"),
]

failures: list[str] = []
notes: list[str] = []


def fail(check: str, message: str) -> None:
    failures.append(f"{check}: {message}")


def ok(check: str, message: str) -> None:
    print(f"  ok    {check}: {message}")


def skip(check: str, message: str) -> None:
    notes.append(f"{check}: {message}")
    print(f"  skip  {check}: {message}")


# ---------------------------------------------------------------------------- project.yml
# Read as text rather than as YAML: `project.yml` leans on anchors and merge keys, PyYAML is
# not in the standard library, and every value this file needs is a quoted scalar on a line
# of its own. A regex over the target blocks is honest here and keeps the check stdlib-only.

def project_text() -> str:
    return PROJECT.read_text(encoding="utf-8")


def target_blocks() -> dict[str, str]:
    """`targets:` split into one text block per target, keyed by target name."""
    text = project_text()
    start = re.search(r"^targets:\s*$", text, re.M)
    if not start:
        fail("ios versions", "ios/project.yml has no `targets:` block")
        return {}
    body = text[start.end():]
    # A top-level key at column 0 ends the targets section (`schemes:`, and nothing else today).
    end = re.search(r"^[A-Za-z]\w*:\s*$", body, re.M)
    if end:
        body = body[: end.start()]
    blocks: dict[str, str] = {}
    name = None
    lines: list[str] = []
    for line in body.splitlines():
        head = re.match(r"^  ([A-Za-z]\w*):\s*$", line)
        if head:
            if name:
                blocks[name] = "\n".join(lines)
            name, lines = head.group(1), []
        elif name:
            lines.append(line)
    if name:
        blocks[name] = "\n".join(lines)
    return blocks


def config_settings(block: str, key: str) -> dict[str, str]:
    """Every `<Config Name>: … <key>: <value>` inside one target's `configs:` map."""
    found: dict[str, str] = {}
    config = None
    for line in block.splitlines():
        head = re.match(r"^        ([A-Za-z][\w ]*):\s*$", line)
        if head:
            config = head.group(1)
            continue
        if re.match(r"^      \S", line):          # back out to `settings:` / `configs:` level
            config = None
        hit = re.match(rf"^\s+{re.escape(key)}:\s*\"?(.*?)\"?\s*$", line)
        if hit and config:
            found[config] = hit.group(1)
    return found


def check_ios_versions() -> None:
    """Every target carries the same build number, and one marketing line per channel."""
    text = project_text()
    builds = set(re.findall(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text))
    if len(builds) == 1:
        ok("ios build", f"CURRENT_PROJECT_VERSION {builds.pop()} at every site")
    else:
        fail("ios build", f"CURRENT_PROJECT_VERSION disagrees across ios/project.yml: {sorted(builds)}")

    blocks = target_blocks()
    release_marketing = set(re.findall(r'MARKETING_VERSION:\s*"([^"]+)"', blocks.get("WingFoilRelease", "")))
    shared = set(re.findall(r'MARKETING_VERSION:\s*"([^"]+)"', text)) - release_marketing
    if len(release_marketing) > 1:
        fail("ios marketing", f"the release target stamps more than one MARKETING_VERSION: {sorted(release_marketing)}")
    elif len(shared) == 1:
        rel = next(iter(release_marketing), "(none — inherits)")
        ok("ios marketing", f"release {rel}, every other target {shared.pop()}")
    else:
        fail("ios marketing", f"MARKETING_VERSION disagrees outside the release target: {sorted(shared)}")


def check_garmin_versions() -> None:
    """package.sh refuses to build three disagreeing manifests; say so before it is run."""
    seen: dict[str, str] = {}
    for path in MANIFESTS:
        if not path.exists():
            fail("watch version", f"{path.relative_to(ROOT)} is missing")
            continue
        root = ET.parse(path).getroot()
        app = next((el for el in root.iter() if el.tag.endswith("}application") or el.tag == "application"), None)
        if app is None or "version" not in app.attrib:
            fail("watch version", f"{path.relative_to(ROOT)} has no application version attribute")
            continue
        seen[path.name] = app.attrib["version"]
    if seen and len(set(seen.values())) == 1:
        ok("watch version", f"{next(iter(set(seen.values())))} in all three manifests")
    elif seen:
        fail("watch version", f"the three manifests disagree: {seen}")


def scrape(path: Path, pattern: str, label: str) -> str | None:
    if not path.exists():
        fail("engine version", f"{path.relative_to(ROOT)} is missing")
        return None
    hit = re.search(pattern, path.read_text(encoding="utf-8"), re.M)
    if not hit:
        fail("engine version", f"no engine version found in {path.relative_to(ROOT)} ({label})")
        return None
    return hit.group(1)


def check_engine_version() -> None:
    """One number, six homes: the lab is the source and everything else quotes it."""
    sites = {
        "lab/src/wingfoil_lab/__init__.py": scrape(LAB_INIT, r'^ENGINE_VERSION\s*=\s*"([^"]+)"', "ENGINE_VERSION"),
        "web/lab_bundle/…/__init__.py": scrape(BUNDLE_INIT, r'^ENGINE_VERSION\s*=\s*"([^"]+)"', "bundle stamp"),
        "kit SessionAnalysis.swift": scrape(KIT_ANALYSIS, r'static let version\s*=\s*"([^"]+)"', "AnalysisEngine.version"),
        "docs/algorithms.md": scrape(ALGORITHMS, r'`ENGINE_VERSION`:\s*\*\*([0-9][^*]*)\*\*', "the contract's head"),
        "docs/channels.md": scrape(CHANNELS, r'^\|\s*Engine\s+([0-9][0-9.]*)[:,]', "the analysis table"),
    }
    values = {k: v for k, v in sites.items() if v}
    if values and len(set(values.values())) == 1:
        ok("engine version", f"{next(iter(set(values.values())))} at all {len(values)} sites")
    elif values:
        fail("engine version", "the sites disagree: " + ", ".join(f"{k} {v}" for k, v in sorted(values.items())))


# ------------------------------------------------------------------ the four channel checks

def check_flags() -> None:
    """1/4 — the compile flags. Release none, beta BETA, dev BETA DEV TUNING."""
    blocks = target_blocks()
    release = blocks.get("WingFoilRelease", "")
    if "SWIFT_ACTIVE_COMPILATION_CONDITIONS" in release:
        fail("flags", "the release target defines SWIFT_ACTIVE_COMPILATION_CONDITIONS; it must inherit and nothing more")
    conditions = config_settings(blocks.get("WingFoil", ""), "SWIFT_ACTIVE_COMPILATION_CONDITIONS")
    expected = {
        "Beta Debug": "$(inherited) BETA",
        "Beta Release": "$(inherited) BETA",
        "Dev Debug": "$(inherited) BETA DEV TUNING",
        "Dev Release": "$(inherited) BETA DEV TUNING",
    }
    for config, want in expected.items():
        got = conditions.get(config)
        if got != want:
            fail("flags", f"WingFoil / {config}: expected {want!r}, found {got!r}")
    if not any(f.startswith("flags") for f in failures):
        ok("flags", "release inherits only; beta BETA; dev BETA DEV TUNING")


def check_plist() -> None:
    """2/4 — the generated Info.plist. It exists only after `xcodegen generate`."""
    if not INFO_RELEASE.exists():
        skip("plist", "ios/WingFoil/Info-Release.plist is generated — run `make ios-project` first")
        return
    hits = [
        f"{n}: {line.strip()}"
        for n, line in enumerate(INFO_RELEASE.read_text(encoding="utf-8").splitlines(), 1)
        if PLIST_FORBIDDEN.search(line)
    ]
    if hits:
        fail("plist", "the release Info.plist names a beta-only permission or document type: " + "; ".join(hits))
    else:
        ok("plist", "no NSHealth / NSLocation / NSBluetooth / gpx / tcx in the release Info.plist")


def check_marks() -> None:
    """3/4 — each channel wears its own cut of the brand mark."""
    blocks = target_blocks()
    release = blocks.get("WingFoilRelease", "")
    for key, want in (("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"), ("CJ_SPLASH_MARK", "SplashMark")):
        overrides = set(re.findall(rf'{key}:\s*"?([\w-]+)"?', release))
        if overrides - {want}:
            fail("marks", f"the release target overrides {key} to {sorted(overrides)}; it must stay {want}")
    app = blocks.get("WingFoil", "")
    for key, suffix in (("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"), ("CJ_SPLASH_MARK", "SplashMark")):
        marks = config_settings(app, key)
        for config, value in marks.items():
            channel = "Beta" if config.startswith("Beta") else "Dev" if config.startswith("Dev") else None
            if channel and value != f"{suffix}-{channel}":
                fail("marks", f"WingFoil / {config}: {key} is {value!r}, expected {suffix}-{channel!r}")
    if not any(f.startswith("marks") for f in failures):
        ok("marks", "release AppIcon/SplashMark, beta -Beta, dev -Dev")


def check_binary(binary: Path | None) -> None:
    """4/4 — the strings check: a door a channel lacks leaves no word of itself behind."""
    if binary is None:
        skip("strings", "no --binary given; the gates are checked in the sources instead")
        # The source-side stand-in: the kit compiles everything in every channel (CLAUDE.md),
        # so a `#if` inside WingFoilKit would be a door the release build cannot be trusted
        # to lack. The gates belong to the app target alone.
        kit = ROOT / "ios" / "WingFoilKit" / "Sources"
        stray = []
        for path in sorted(kit.rglob("*.swift")):
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if re.match(r"\s*#if\s+!?(BETA|DEV|TUNING)\b", line):
                    stray.append(f"{path.relative_to(ROOT)}:{n}")
        if stray:
            fail("gates", "WingFoilKit carries a channel gate; the kit compiles everything (CLAUDE.md): "
                 + ", ".join(stray))
        else:
            ok("gates", "every #if BETA / DEV / TUNING is in the app target, none in the kit")
        return
    if not binary.exists():
        fail("strings", f"{binary} does not exist")
        return
    try:
        blob = subprocess.run(["strings", str(binary)], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        fail("strings", f"could not run `strings` on {binary}: {exc}")
        return
    for needle, channels, why in BINARY_NEEDLES:
        if needle in blob:
            fail("strings", f"{binary.name} contains {needle!r} — {why}, absent from: {channels}")
    if not any(f.startswith("strings") for f in failures):
        ok("strings", f"{binary.name} carries none of the {len(BINARY_NEEDLES)} beta/dev door strings")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--binary", type=Path, default=None,
                        help="a built release binary; runs the strings check over it "
                             "(e.g. ios/build/exportRelease/WingFoil.app/WingFoil)")
    args = parser.parse_args(argv)

    print("version sites")
    check_ios_versions()
    check_garmin_versions()
    check_engine_version()
    print("channels (docs/testing.md, \"Three channels\")")
    check_flags()
    check_plist()
    check_marks()
    check_binary(args.binary)

    print()
    if failures:
        for line in failures:
            print(f"FAILED  {line}")
        return 1
    tail = f" ({len(notes)} check{'s' if len(notes) != 1 else ''} skipped)" if notes else ""
    print(f"PASSED — the version sites agree and every channel is what it claims to be{tail}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
