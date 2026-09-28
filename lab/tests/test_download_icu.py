"""The intervals.icu watersport filter (tools/download_icu.py), 28 Sep 2026.

Jan's Berlin Marathon (a Run) and "9 5 4 Supporting Robert" came in as wingfoil sessions:
the name rescue matched "sup" inside "Supporting" and applied to every type. It now applies
only to a type that could be a watersport, and only to whole words. Twin of the kit's
`IcuClientTests` and web/js/icu.js.
"""

import importlib.util
from pathlib import Path

import pytest

_PATH = Path(__file__).resolve().parents[1] / "tools" / "download_icu.py"
_spec = importlib.util.spec_from_file_location("download_icu", _PATH)
download_icu = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(download_icu)


@pytest.mark.parametrize("type_, name", [
    ("Windsurf", "Morning Run"),                 # the type alone decides
    ("Walk", "Wingfoiling"),                     # the CIQ mis-type, rescued
    ("Walk", "Wing foil Torbole"),
    ("Walk", "foiling at Garda"),
    ("Walk", "Wingfoilen am Gardasee"),
    ("Walk", "SUP"),
    ("Walk", "SUP-Tour"),
    ("Walk", "wing_foil"),
    ("Walk", "FoilMotion session"),
    ("Walk", "Kiten"),
    ("Workout", "Wingfoil Torbole"),
    (None, "Windsurfen"),
    ("", "kitesurfing"),
    ("SomeFutureType", "wingfoil"),              # a type icu adds later is unknown, so rescuable
])
def test_a_watersport_is_kept(type_, name):
    assert download_icu.is_watersport({"type": type_, "name": name})


@pytest.mark.parametrize("type_, name", [
    ("Run", "BMW BERLIN-MARATHON"),              # Jan, 28 Sep 2026
    ("Run", "9 5 4 Supporting Robert"),          # likewise
    ("Walk", "9 5 4 Supporting Robert"),         # "sup" inside a word is no SUP
    ("Walk", "super walk"),
    ("Ride", "Ride to the wingfoil spot"),       # a known land type is never rescued
    ("Hike", "Surf-Hütte hike"),
    ("Swim", "SUP rescue practice"),
    ("EBikeRide", "kite shop"),
    ("TrailRun", "foil"),
    ("Walk", "Evening walk"),
    (None, None),
])
def test_everything_else_is_not(type_, name):
    assert not download_icu.is_watersport({"type": type_, "name": name})
