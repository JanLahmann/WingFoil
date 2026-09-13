"""Discipline presets — wingfoil is untouched, windsurf is the same engine minus the wing.

The contract this file holds (docs/algorithms.md "Disciplines"):

1. **wingfoil is not merely equal to today, it is today.** The preset is not applied at all,
   so the committed corpus golden is reproduced byte-for-byte and nothing in the config echo
   announces that a preset layer exists.
2. **Both windsurf presets switch the pump channel off** — no episodes, no stroke counts, no
   `pumped` flag, no pump rung — and switch nothing else about turns.
3. **windsurfFin, and only windsurfFin, moves the two speeds**, into all four configs that
   carry them, which is what makes "on the foil" read as "planing".
4. The two goldens under `fixtures/goldens/discipline/` are frozen so the Swift kit can be
   cross-checked against the lab on the same recording.
"""

import json
from pathlib import Path

import pytest

from wingfoil_lab.discipline import Discipline, resolve
from wingfoil_lab.goldens import analyze, build_golden, golden_path, load_golden
from wingfoil_lab.turns import TurnConfig

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
#: The cross-check recording — see `tools/make_goldens.py:DISCIPLINE_CROSSCHECK`.
CIQ = FIXTURES / "sessions" / "ciq" / "2026-08-30-1407_nago-torbole-windsurfen_ciq.fit"

pytestmark = pytest.mark.skipif(not CIQ.exists(), reason="raw recording not committed")


@pytest.fixture(scope="module")
def runs() -> dict[Discipline, dict]:
    return {d: build_golden(analyze(CIQ, discipline=d)) for d in Discipline}


# --- 1. wingfoil is byte-identical -------------------------------------------------------

def test_wingfoil_reproduces_the_committed_golden(runs):
    assert runs[Discipline.WINGFOIL] == load_golden(golden_path(CIQ, FIXTURES / "goldens"))


def test_the_preset_layer_is_invisible_on_a_wingfoil_document(runs):
    """No `discipline` key at all — absent, never `"wingfoil"`.

    Same rule the 360 detector follows: the config block records what produced *this*
    document, and a key printed on every golden would be an announcement of a layer that,
    for the default, is not even reached.
    """
    assert "discipline" not in runs[Discipline.WINGFOIL]["config"]
    assert runs[Discipline.WINDSURF_FOIL]["config"]["discipline"] == "windsurfFoil"
    assert runs[Discipline.WINDSURF_FIN]["config"]["discipline"] == "windsurfFin"


def test_an_explicit_wingfoil_preset_never_overrides_a_tuned_config():
    """The preset is skipped for wingfoil, so a caller's own thresholds survive it."""
    tuned = TurnConfig(foil_exit_speed_kmh=6.5)
    a = analyze(CIQ, turn_config=tuned, discipline=Discipline.WINGFOIL)
    assert a.turn_config.foil_exit_speed_kmh == 6.5


# --- 2. pumping is off, and nothing else about the turns moves ---------------------------

@pytest.mark.parametrize("disc", [Discipline.WINDSURF_FOIL, Discipline.WINDSURF_FIN])
def test_pumping_is_absent_not_zero(runs, disc):
    g = runs[disc]
    assert g["pumpEpisodes"] == []
    # Absent, not zero: a windsurfer did not pump nought times, the question was not asked.
    assert g["summary"]["takeoff"]["totalPumpStrokes"] is None
    assert g["summary"]["takeoff"]["avgPumpsToTakeoff"] is None
    assert g["summary"]["takeoff"]["inFlightPumpStrokes"] is None
    assert all(t["pumps"] is None for t in g["takeoffs"])
    assert all(f["takeoffPumps"] is None for f in g["flights"])
    assert not any(t["pumped"] for t in g["turns"])
    assert not any(e["pumped"] for e in g["flightEnds"])
    assert g["config"]["turnPumpedOutIsTouchdown"] is False
    # No turn may be explained by a rung that was never asked.
    assert not any(t["outcomeReason"] == "pumped_marginal" for t in g["turns"])


def test_windsurf_foil_is_the_wingfoil_reading_minus_the_wing(runs):
    """Every threshold identical ⇒ every flight, every sweep and every verdict identical."""
    wing, foil = runs[Discipline.WINGFOIL], runs[Discipline.WINDSURF_FOIL]
    assert [f["startTs"] for f in foil["flights"]] == [f["startTs"] for f in wing["flights"]]
    assert foil["summary"]["foilTimeS"] == wing["summary"]["foilTimeS"]
    assert foil["summary"]["turns"] == wing["summary"]["turns"]
    assert foil["summary"]["flightEnds"] == wing["summary"]["flightEnds"]
    assert foil["records"] == wing["records"]
    strip = ("pumped", "outcomeReason")
    for a, b in zip(foil["turns"], wing["turns"], strict=True):
        assert {k: v for k, v in a.items() if k not in strip} \
            == {k: v for k, v in b.items() if k not in strip}
    # Every speed the ladders are judged against is the wingfoil one.
    for key in ("foilEntrySpeed", "foilExitSpeed", "turnSuccessPct", "turnFallStop"):
        assert foil["config"][key] == wing["config"][key]


# --- 3. windsurfFin plans instead of flying ----------------------------------------------

def test_windsurf_fin_moves_the_two_speeds_and_only_them(runs):
    wing, fin = runs[Discipline.WINGFOIL], runs[Discipline.WINDSURF_FIN]
    assert fin["config"]["foilEntrySpeed"] == 20.0     # PROVISIONAL, issue #6
    assert fin["config"]["foilExitSpeed"] == 15.0      # PROVISIONAL, issue #6
    moved = {"discipline", "foilEntrySpeed", "foilExitSpeed", "turnPumpedOutIsTouchdown"}
    assert {k for k in fin["config"] if fin["config"][k] != wing["config"].get(k)} == moved
    # A higher exit speed cannot lengthen a run.
    assert fin["summary"]["foilTimeS"] <= wing["summary"]["foilTimeS"]


def test_the_fin_speeds_reach_all_four_configs():
    """The seam that would break silently: the evidence object is shared only while the
    turn, flight-end and takeoff configs agree with each other on the exit speed."""
    a = analyze(CIQ, discipline=Discipline.WINDSURF_FIN)
    assert a.flight_config.foil_entry_speed_kmh == 20.0
    assert a.turn_config.foil_entry_speed_kmh == 20.0
    assert a.flight_end_config.foil_entry_speed_kmh == 20.0
    for cfg in (a.flight_config, a.turn_config, a.flight_end_config, a.takeoff_config):
        assert cfg.foil_exit_speed_kmh == 15.0


# --- 4. the frozen cross-check goldens ---------------------------------------------------

@pytest.mark.parametrize("disc", [Discipline.WINDSURF_FOIL, Discipline.WINDSURF_FIN])
def test_the_discipline_goldens_are_frozen(runs, disc):
    path = golden_path(CIQ, FIXTURES / "goldens", disc)
    assert path.parent.name == "discipline"     # out of every corpus glob's way
    assert runs[disc] == json.loads(path.read_text())


# --- the tag → preset map ----------------------------------------------------------------

@pytest.mark.parametrize("tag,expected", [
    (None, Discipline.WINGFOIL),
    ("wingfoil", Discipline.WINGFOIL),
    ("", Discipline.WINGFOIL),
    ("nonsense", Discipline.WINGFOIL),
    ("windsurf", Discipline.WINDSURF_FOIL),
    ("windsurfing", Discipline.WINDSURF_FOIL),
    ("windsurf_foil", Discipline.WINDSURF_FOIL),
    ("Windsurf Fin", Discipline.WINDSURF_FIN),
    ("windsurfFin", Discipline.WINDSURF_FIN),
])
def test_resolve_reads_the_discipline_tag(tag, expected):
    assert resolve(tag) == expected


def test_the_riders_override_wins():
    assert resolve("wingfoil", "windsurfFin") == Discipline.WINDSURF_FIN
    assert resolve("windsurf", "wingfoil") == Discipline.WINGFOIL


def test_a_windsurf_profile_recording_stays_wingfoil():
    """ADR-004 records FIT **sport 43 (windsurfing)** for a wingfoil session, so the sport
    code alone must never switch the preset — only the dev-field tag or the rider does.
    `resolve` is never handed a sport code, which is how that is enforced."""
    assert resolve("wingfoil") == Discipline.WINGFOIL
    assert resolve(None) == Discipline.WINGFOIL
