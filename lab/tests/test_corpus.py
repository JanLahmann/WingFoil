"""Corpus smoke: re-run the pipeline for every golden and assert equality within
docs/testing.md tolerances (guards refactors), plus physical sanity checks.

Counts exact | timestamps +-1 s | record speeds +-0.05 kn (alpha +-0.1) | foil time +-2 %.
"""

from pathlib import Path

import pytest

from wingfoil_lab.goldens import analyze, build_golden, load_golden

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
GOLDENS = sorted((FIXTURES / "goldens").glob("*.expected.json"))

RECORD_TOL = {"best2sKn": 0.05, "best10sKn": 0.05, "best5x10sKn": 0.05,
              "best100mKn": 0.05, "best250mKn": 0.05, "best500mKn": 0.05,
              "bestNmKn": 0.05, "bestHourKn": 0.05, "alpha500Kn": 0.1}


def _fixture_for(stem: str) -> Path | None:
    for sub in ("sessions", "synthetic"):
        hits = sorted((FIXTURES / sub).rglob(f"{stem}.fit"))
        if hits:
            return hits[0]
    return None


if not GOLDENS:
    pytest.skip("no goldens yet -- run `uv run python tools/make_goldens.py`",
                allow_module_level=True)


@pytest.mark.parametrize("gpath", GOLDENS, ids=lambda p: p.name.removesuffix(".expected.json"))
def test_golden_self_consistency(gpath):
    gold = load_golden(gpath)
    fit = _fixture_for(gpath.name.removesuffix(".expected.json"))
    assert fit is not None, f"no fixture found for {gpath.name}"
    new = build_golden(analyze(fit))

    assert new["engineVersion"] == gold["engineVersion"]
    assert new["config"] == gold["config"]
    assert new["capabilities"] == gold["capabilities"]

    # counts exact
    assert new["summary"]["flightCount"] == gold["summary"]["flightCount"]
    assert len(new["flights"]) == len(gold["flights"])

    # flights: timestamps +-1 s, speeds +-0.05 kn
    for fn, fo in zip(new["flights"], gold["flights"]):
        assert abs(fn["startTs"] - fo["startTs"]) <= 1.0
        assert abs(fn["endTs"] - fo["endTs"]) <= 1.0
        assert fn["maxKn"] == pytest.approx(fo["maxKn"], abs=0.05)

    # records within tolerance
    for key, tol in RECORD_TOL.items():
        assert new["records"][key] == pytest.approx(gold["records"][key], abs=tol), key

    # foil time +-2 %
    ft_gold = gold["summary"]["foilTimeS"]
    assert abs(new["summary"]["foilTimeS"] - ft_gold) <= max(0.02 * ft_gold, 0.5)

    # distance stable
    assert new["summary"]["distanceKm"] == pytest.approx(
        gold["summary"]["distanceKm"], rel=0.01, abs=0.01)


@pytest.mark.parametrize("gpath", GOLDENS, ids=lambda p: p.name.removesuffix(".expected.json"))
def test_golden_sanity(gpath):
    g = load_golden(gpath)
    s, r = g["summary"], g["records"]
    assert 0.0 <= s["foilPct"] <= 100.0
    assert r["best2sKn"] >= r["best10sKn"] - 1e-9
    assert r["best10sKn"] >= r["best5x10sKn"] - 1e-9
    for key in RECORD_TOL:
        assert 0.0 <= r[key] < 45.0, key
    for f in g["flights"]:
        assert 0.0 < f["maxKn"] < 45.0
        assert f["endTs"] > f["startTs"]
    assert s["flightCount"] == len(g["flights"])
    assert s["foilTimeS"] == pytest.approx(
        sum(f["endTs"] - f["startTs"] for f in g["flights"]), abs=0.5)
    if g["flights"]:
        assert s["longestFlightS"] == pytest.approx(
            max(f["endTs"] - f["startTs"] for f in g["flights"]), abs=0.2)
