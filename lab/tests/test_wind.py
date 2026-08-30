"""Wind-axis estimation on constructed reach patterns, plus a real-fixture smoke test."""

from dataclasses import replace
from pathlib import Path

import numpy as np
import pytest

from wingfoil_lab.filters import clean, clean_from_arrays
from wingfoil_lab.flight import segment_flights
from wingfoil_lab.parse import parse_fit
from wingfoil_lab.turns import (JIBE, TACK, classify_sweep, detect_turns, summarize_turns,
                                turn_sweeps)
from wingfoil_lab.wind import (_blend, _Prior, _wrap180, WindConfig, circular_histogram,
                               estimate_wind, turn_type_votes)

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


# --- default turn type: the rider's habit as 180 deg evidence ------------------------
# docs/algorithms.md "Default turn type". The blend is exercised twice over: as pure
# arithmetic (`_blend`, `turn_type_votes`) and end to end on a constructed track.


def _steps_to_course(steps):
    """(kind, arg, arg) steps -> a per-second unwrapped COG array.

    ``("hold", deg, seconds)`` sails a straight leg; ``("turn", deg, deg_per_s)`` sweeps to
    a new unwrapped course at a fixed rate, so the turn detector sees a real peak rate and
    a real carved arc rather than an instantaneous heading flip.
    """
    out, cur = [], None
    for kind, a, b in steps:
        if kind == "hold":
            cur = a
            out.extend([a] * int(b))
        else:
            n = int(abs(a - cur) / b)
            out.extend(np.linspace(cur, a, n, endpoint=False).tolist())
            cur = a
    return np.array(out, float)


def _course_track(cog_deg, speed=6.0):
    t = np.arange(len(cog_deg), dtype=float)
    v = np.full(len(cog_deg), float(speed))
    dx, dy = np.sin(np.radians(cog_deg)) * v, np.cos(np.radians(cog_deg)) * v
    x = np.concatenate([[0.0], np.cumsum(dx)[:-1]])
    y = np.concatenate([[0.0], np.cumsum(dy)[:-1]])
    return clean_from_arrays(t, v, x=x, y=y)


def _misread_cone_track():
    """A session the no-go cone reads one way and the turn types read the other.

    Two reaches at COG 100 and 260 with every transit taken through 0 (so each sweep
    crosses one end of the axis, never the other), plus a long straight leg at 180 entered
    and left at 4 deg/s -- too slow for `turnPeakRate`, so it adds cone mass without adding
    a turn. The 180 leg is what makes the cone pick the *other* end than the sweeps do:
    the cone lands on ~0, under which all twelve sweeps are tacks, while a rider who
    declares "mostly jibes" is pointing at ~180.
    """
    steps = [("hold", 100.0, 60)]
    for _ in range(6):
        steps += [("turn", -100.0, 30), ("hold", -100.0, 60),
                  ("turn", 100.0, 30), ("hold", 100.0, 60)]
    steps += [("turn", 180.0, 4), ("hold", 180.0, 120),
              ("turn", 100.0, 4), ("hold", 100.0, 60)]
    return _course_track(_steps_to_course(steps))


def test_flipping_the_wind_180_swaps_every_tack_and_jibe():
    """The geometric fact the whole prior rests on, asserted directly."""
    ct = _misread_cone_track()
    sweeps = turn_sweeps(ct, segment_flights(ct))
    assert len(sweeps) == 12
    for cog_in, cog_out in sweeps:
        here = classify_sweep(cog_in, cog_out, 0.0)[0]
        there = classify_sweep(cog_in, cog_out, 180.0)[0]
        assert {here, there} == {TACK, JIBE}


def test_turn_type_votes_ignore_sweeps_that_are_not_maneuvers_under_both_ends():
    """Only a sweep that is a tack-or-jibe under *both* ends of the axis may vote."""
    jibe = (135.0, 225.0)          # crosses 180: jibe at wind-from 0, tack at wind-from 180
    tack = (315.0, 405.0)          # crosses 0:   tack at wind-from 0, jibe at wind-from 180
    bear_away = (45.0, 135.0)      # crosses neither end, whichever way the wind blows
    sweeps = [jibe, jibe, jibe, tack, bear_away, bear_away]

    assert turn_type_votes(sweeps, 0.0, "jibes") == (3, 1)      # the bear-aways abstain
    assert turn_type_votes(sweeps, 0.0, "tacks") == (1, 3)      # same electorate, mirrored
    # The other end of the axis names every voting sweep the opposite way, by construction.
    assert turn_type_votes(sweeps, 180.0, "jibes") == (1, 3)


def test_blend_is_the_documented_formula():
    """`e = eCone + w * mTurn`; the sign of `e` is the call, `|e|` clipped is the certainty."""
    cfg = WindConfig()                                   # turn_prior_weight 0.5
    # Weak cone (0.2), unanimous majority against it: 0.2 - 0.5 = -0.3 -> flip.
    flipped = _blend(0.2, 0, 10, 90.0, cfg)
    assert flipped.flipped is True
    assert flipped.certainty == pytest.approx(0.3)
    assert flipped.margin == pytest.approx(1.0)
    assert flipped.favoured_deg == pytest.approx(270.0)
    assert flipped.votes == 10
    # The same cone with the majority behind it: 0.2 + 0.5 = 0.7, and it keeps its pick.
    agreed = _blend(0.2, 10, 0, 90.0, cfg)
    assert agreed.flipped is False
    assert agreed.certainty == pytest.approx(0.7)
    assert agreed.favoured_deg == pytest.approx(90.0)
    # 0.5 is exactly the weight, so a unanimous majority cannot quite overturn it.
    assert _blend(0.5, 0, 10, 90.0, cfg).flipped is False
    # A 60/40 split moves 0.2 by 0.5 * 0.2 = 0.1, not enough to flip a 0.2 cone.
    assert _blend(0.2, 4, 6, 90.0, cfg) == _Prior(certainty=pytest.approx(0.1), flipped=False,
                                                  margin=pytest.approx(0.2),
                                                  favoured_deg=270.0, votes=10)


def test_an_even_split_and_an_empty_electorate_contribute_nothing():
    cfg = WindConfig()
    for prior in (_blend(0.3, 5, 5, 90.0, cfg), _blend(0.3, 0, 0, 90.0, cfg)):
        assert prior.certainty == pytest.approx(0.3)    # the bare cone factor
        assert prior.flipped is False
        assert prior.margin == 0.0
        assert prior.favoured_deg is None


def test_weak_cone_and_a_jibe_majority_flips_the_180_call():
    """The motivating case: the cone cannot tell, and "I mostly jibe" decides.

    `full_margin` is raised to 3.0 to say the cone's 0.6 asymmetry is *not* certain -- which
    is exactly what that parameter means. The twelve sweeps are tacks under the cone's pick
    and jibes under the other end, so a rider who declares "jibes" turns the call over.
    """
    ct = _misread_cone_track()
    fl = segment_flights(ct)
    # `min_confidence` is dropped so the labels are readable on both sides of the flip:
    # the point here is *which* wind was chosen, not whether it clears the shipped bar.
    cfg = WindConfig(full_margin=3.0, min_confidence=0.1)

    cone_only = estimate_wind(ct, fl, replace(cfg, default_turn_type="balanced"))
    assert abs(_wrap180(cone_only.dir_deg - 0.0)) < 5.0
    assert summarize_turns(detect_turns(ct, fl, cone_only)).tacks == 12

    est = estimate_wind(ct, fl, cfg)                     # default_turn_type = "jibes"
    assert est.prior_flipped is True
    assert abs(_wrap180(est.dir_deg - 180.0)) < 5.0
    assert est.turn_type_votes == 12 and est.turn_type_margin == pytest.approx(1.0)
    assert abs(_wrap180(est.turn_type_dir_deg - est.dir_deg)) < 1e-9
    # e = 0.598/3 - 0.5 = -0.301, and the labels follow the wind that was chosen.
    assert est.confidence == pytest.approx(est.axis_confidence * 0.301, abs=0.01)
    assert summarize_turns(detect_turns(ct, fl, est)).jibes == 12

    # The declared habit pointing *with* the cone leaves the call alone and only raises it.
    agreeing = estimate_wind(ct, fl, replace(cfg, default_turn_type="tacks"))
    assert agreeing.prior_flipped is False
    assert agreeing.dir_deg == pytest.approx(cone_only.dir_deg)
    assert agreeing.confidence > cone_only.confidence


def test_a_decisive_cone_is_untouchable_by_the_prior():
    """At the shipped `full_margin` the same session's cone is certain, so nothing moves."""
    ct = _misread_cone_track()
    fl = segment_flights(ct)
    est = estimate_wind(ct, fl)                          # default: jibes, full_margin 0.4
    assert est.ambiguity_margin > WindConfig().full_margin
    assert est.prior_flipped is False
    assert (est.turn_type_votes, est.turn_type_margin, est.turn_type_dir_deg) == (0, 0.0, None)
    assert summarize_turns(detect_turns(ct, fl, est)).tacks == 12
    # ... and it is the *same* estimate the prior-free engine produces, field for field.
    assert est == estimate_wind(ct, fl, WindConfig(default_turn_type="balanced"))


def test_balanced_reproduces_the_pre_prior_confidence_exactly():
    """`balanced` is the engine as it was: confidence = axis confidence x cone certainty."""
    ct = _misread_cone_track()
    fl = segment_flights(ct)
    for full_margin in (0.4, 3.0):
        cfg = WindConfig(full_margin=full_margin, default_turn_type="balanced")
        est = estimate_wind(ct, fl, cfg)
        expected = est.axis_confidence * min(est.ambiguity_margin / full_margin, 1.0)
        assert est.confidence == pytest.approx(expected)
        assert est.turn_type_votes == 0 and est.turn_type_dir_deg is None
