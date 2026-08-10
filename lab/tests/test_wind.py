"""Wind-axis estimation on constructed reach patterns, plus a real-fixture smoke test."""

from pathlib import Path

import numpy as np
import pytest

from wingfoil_lab.filters import clean, clean_from_arrays
from wingfoil_lab.flight import segment_flights
from wingfoil_lab.parse import parse_fit
from wingfoil_lab.wind import WindConfig, circular_histogram, estimate_wind

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
TODAY = FIXTURES / "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"


def _sail(legs, wind_from=0.0, speed=6.0):
    """Build a track from (twa_deg, n_samples) legs sailed at `speed` in `wind_from`."""
    course = np.concatenate([np.full(n, wind_from + twa) for twa, n in legs])
    t = np.arange(len(course), dtype=float)
    v = np.full(len(course), float(speed))
    dx = np.sin(np.radians(course)) * v
    dy = np.cos(np.radians(course)) * v
    x = np.concatenate([[0.0], np.cumsum(dx)[:-1]])
    y = np.concatenate([[0.0], np.cumsum(dy)[:-1]])
    return clean_from_arrays(t, v, x=x, y=y)


def _estimate(legs, wind_from=0.0, **kw):
    ct = _sail(legs, wind_from, **kw)
    return estimate_wind(ct, segment_flights(ct))


# two beam reaches (never exactly opposed) plus a downwind run that fills the lee cone
REACHES = [(100.0, 60), (-100.0, 60), (100.0, 60), (-100.0, 60), (170.0, 40), (-100.0, 60)]


@pytest.mark.parametrize("wind_from", [0.0, 90.0, 215.0, 350.0])
def test_axis_recovered_for_any_wind_direction(wind_from):
    est = _estimate(REACHES, wind_from)
    assert est.source == "estimate" and est.usable
    assert abs((est.dir_deg - wind_from + 180.0) % 360.0 - 180.0) <= 10.0
    assert est.separation_deg == pytest.approx(160.0, abs=10.0)
    assert est.ambiguity_margin > 0.5      # lee cone populated, no-go cone empty


def test_180_ambiguity_uses_the_no_go_zone_not_speed():
    """The lee cone decides, even when the *upwind* reaches are the faster ones.

    Real corpus behaviour: on a foil, speed rises toward the wind, so a speed-asymmetry
    rule would flip the answer. Sail the close reaches fast and the broad reaches slow.
    """
    legs = [(60.0, 60), (-60.0, 60), (150.0, 50), (60.0, 60), (-60.0, 60), (-150.0, 50)]
    course = np.concatenate([np.full(n, twa) for twa, n in legs])
    v = np.where(np.abs(course) < 90.0, 7.0, 4.0)          # upwind fast, downwind slow
    t = np.arange(len(course), dtype=float)
    dx, dy = np.sin(np.radians(course)) * v, np.cos(np.radians(course)) * v
    x = np.concatenate([[0.0], np.cumsum(dx)[:-1]])
    y = np.concatenate([[0.0], np.cumsum(dy)[:-1]])
    ct = clean_from_arrays(t, v, x=x, y=y)
    est = estimate_wind(ct, segment_flights(ct))
    assert abs((est.dir_deg + 180.0) % 360.0 - 180.0) <= 15.0   # ~0, not ~180
    assert est.speed_asymmetry > 0                              # the diagnostic that lies


def test_single_reach_has_no_second_lobe():
    est = _estimate([(90.0, 200)])
    assert est.dir_deg is None and est.confidence == 0.0 and est.source == "none"


def test_exactly_opposed_lobes_are_rejected():
    # pure beam-reach out-and-back: the true axis is perpendicular, no bisector can find it
    est = _estimate([(90.0, 100), (-90.0, 100), (90.0, 100), (-90.0, 100)])
    assert est.dir_deg is None
    assert est.separation_deg == pytest.approx(180.0, abs=1.0)


def test_too_little_foiling_gives_no_estimate():
    est = _estimate([(100.0, 20), (-100.0, 20)])       # ~480 m < minDistance 500 m
    assert est.dir_deg is None and est.distance_m < WindConfig().min_distance_m


def test_off_foil_samples_are_excluded():
    # same reach pattern but at 1.5 m/s: never flying, nothing to build a histogram from
    est = _estimate(REACHES, speed=1.5)
    assert est.dir_deg is None


def test_usable_honours_the_caller_supplied_min_confidence():
    """`usable` is judged against the config the estimate was built with, not the default.

    The lobes here are deliberately lopsided (one reach sailed three times as far as the
    other), which drops `axis_confidence` to ~0.66: comfortably usable at the default 0.5,
    and not usable at all once the caller raises the bar past it.
    """
    legs = [(100.0, 120), (-100.0, 40), (170.0, 40), (100.0, 120), (-100.0, 40)]
    ct = _sail(legs)
    flights = segment_flights(ct)

    default = estimate_wind(ct, flights)
    assert default.dir_deg is not None
    assert 0.5 < default.confidence < 1.0        # strictly between the two bars below
    assert default.usable

    lenient = estimate_wind(ct, flights, WindConfig(min_confidence=0.5))
    strict = estimate_wind(ct, flights, WindConfig(min_confidence=0.9))
    assert lenient.confidence == strict.confidence == default.confidence
    assert lenient.usable is True
    assert strict.usable is False                # the bug returned True here


def test_circular_histogram_wraps_and_weights():
    cog = np.array([5.0, 355.0, 180.0])
    centers, hist = circular_histogram(cog, np.array([1.0, 1.0, 2.0]), 10.0, 0.0)
    assert len(centers) == 36 and centers[0] == 5.0
    assert hist[0] == pytest.approx(1.0)      # 5 deg
    assert hist[35] == pytest.approx(1.0)     # 355 deg
    assert hist[18] == pytest.approx(2.0)     # 180 deg, distance-weighted
    assert hist.sum() == pytest.approx(4.0)


@pytest.mark.skipif(not TODAY.exists(), reason="ciq fixture missing")
def test_real_session_wind_axis_smoke():
    """2026-08-07 07:54 Torbole: a morning session, so the Peler blows from the north."""
    ct = clean(parse_fit(TODAY))
    est = estimate_wind(ct, segment_flights(ct))
    assert est.usable and est.source == "estimate"
    assert 0.0 <= est.dir_deg <= 70.0
    assert est.axis_deg == pytest.approx(est.dir_deg % 180.0)
    assert est.lobe_mass[0] > 0.2 and est.lobe_mass[1] > 0.2
    assert est.distance_m > 5000.0
