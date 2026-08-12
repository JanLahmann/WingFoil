"""Jump detection + height estimation (docs/algorithms.md "Jumps (theoretical, uncalibrated)").

There is no labelled jump anywhere in the corpus, so every accuracy assertion here is against
the synthetic generator in `jump.py`. The tests that matter most are therefore the *negative*
ones: a pump burst, chop and a fall must never come back as a jump, because those are the only
signals the real corpus actually contains.
"""

from pathlib import Path

import numpy as np
import pytest

from wingfoil_lab import jump as J
from wingfoil_lab.filters import clean
from wingfoil_lab.flight import segment_flights
from wingfoil_lab.parse import parse_fit

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
CIQ = FIXTURES / "sessions" / "ciq" / "2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"

NOISE_FREE = J.NoiseModel(accel_sigma_g=0.0, accel_rate_hz=100.0, accel_rest_mean_g=1.0,
                          alt_sigma_m=0.0, alt_quantum_m=0.2, alt_rate_hz=1.0)


# --------------------------------------------------------------------------------------
# physics of the generator itself (if this is wrong, nothing else means anything)
# --------------------------------------------------------------------------------------

def test_airtime_matches_textbook_when_unsupported():
    """s = 0 must reproduce T = 2 sqrt(2h/g) exactly -- the generator has no free knobs."""
    for h in (0.5, 1.0, 3.0):
        T, _ = J.airtime_for(h, J.support_profile("const", 0.0))
        assert T == pytest.approx(2.0 * np.sqrt(2.0 * h / J.G), rel=1e-4)


@pytest.mark.parametrize("s", [0.0, 0.2, 0.4, 0.6, 0.7])
def test_support_stretches_airtime_by_one_over_sqrt(s):
    """Constant support scales airtime by 1/sqrt(1-s) -- the root of the naive overestimate."""
    T0, _ = J.airtime_for(1.0, J.support_profile("const", 0.0))
    T, _ = J.airtime_for(1.0, J.support_profile("const", s))
    assert T / T0 == pytest.approx(1.0 / np.sqrt(1.0 - s), rel=1e-3)


def test_generated_trajectory_returns_to_the_water():
    sj = J.simulate_jump(2.0, 0.4, "const", noise=NOISE_FREE)
    dense = np.linspace(sj.t0, sj.t1, 501)
    z = J._trajectory(dense, sj.t0, sj.airtime_true_s, J.support_profile("const", 0.4))
    assert z[0] == pytest.approx(0.0, abs=1e-6)
    assert z[-1] == pytest.approx(0.0, abs=1e-3)
    assert z.max() == pytest.approx(2.0, rel=1e-3)


# --------------------------------------------------------------------------------------
# detection
# --------------------------------------------------------------------------------------

@pytest.mark.parametrize("h", [0.5, 1.0, 2.0, 3.0])
@pytest.mark.parametrize("s", [0.0, 0.2, 0.4, 0.6])
def test_clean_jump_detected_once(h, s):
    sj = J.simulate_jump(h, s, "const", noise=NOISE_FREE)
    res = J.detect_jumps_from_arrays(sj.t, sj.mag)
    assert len(res.jumps) == 1
    j = res.jumps[0]
    assert j.t_start == pytest.approx(sj.t0, abs=0.03)
    assert j.t_end == pytest.approx(sj.t1, abs=0.03)


def test_pump_burst_is_not_a_jump():
    """A 1 Hz pump swings |a| by +-0.5 g -- deep, but never for `jumpMinAirtime`.

    This is the gate that keeps the detector honest on Jan's actual sessions, which are made
    almost entirely of pumping: the trough of a 1 Hz stroke sits below 0.75 g for 0.33 s,
    which is under the 0.4 s floor, so an eight-stroke burst yields no window at all.
    """
    t = np.arange(0.0, 12.0, 0.01)
    mag = 1.0 + 0.5 * np.sin(2 * np.pi * 1.0 * t)
    res = J.detect_jumps_from_arrays(t, mag)
    assert res.jumps == []
    assert res.candidates == []


def test_075g_is_where_the_pump_stops_clearing_the_airtime_floor():
    """The reason `jumpAirborneMaxG` is 0.75 g and not 0.9 g, asserted rather than asserted-at.

    A 1 Hz +-0.5 g pump stroke sits below 0.75 g for 0.33 s (under `jumpMinAirtime`, rejected
    outright) but below 0.9 g for 0.44 s (over it, so every stroke of every burst would reach
    the spike gates). 0.75 g is the last threshold at which the airtime floor alone does the
    work -- which is also the highest support fraction the detector can see.
    """
    t = np.arange(0.0, 3.0, 0.0005)
    mag = 1.0 + 0.5 * np.sin(2 * np.pi * 1.0 * t)
    floor = J.JumpConfig().min_airtime_s

    def longest_below(level: float) -> float:
        runs = J._runs(mag < level)
        return max((t[b] - t[a] for a, b in runs), default=0.0)

    assert longest_below(0.75) == pytest.approx(0.33, abs=0.01)
    assert longest_below(0.75) < floor
    assert longest_below(0.90) == pytest.approx(0.44, abs=0.01)
    assert longest_below(0.90) > floor


def test_slow_deep_pump_is_a_candidate_never_a_jump():
    """Belt and braces: a 0.7 Hz, +-0.65 g pump *does* clear the airtime floor.

    It is then stopped by the impact gate -- a pump has no landing. If a future tuning ever
    relaxes `jumpImpactMinG`, this test is the one that fails.
    """
    t = np.arange(0.0, 12.0, 0.01)
    mag = 1.0 + 0.65 * np.sin(2 * np.pi * 0.7 * t)
    res = J.detect_jumps_from_arrays(t, mag)
    assert res.jumps == []
    assert res.candidates, "the airtime floor alone should not have rejected this"
    assert {c.reason for c in res.candidates} <= {"no_takeoff_spike", "no_landing_impact"}


def test_chop_hop_below_min_airtime_is_rejected():
    """A 0.2 s unweighting off a chop, with a real impact, is still not a jump."""
    sj = J.simulate_jump(0.05, 0.0, "const", noise=NOISE_FREE)   # T ~ 0.20 s
    assert sj.airtime_true_s < J.JumpConfig().min_airtime_s
    res = J.detect_jumps_from_arrays(sj.t, sj.mag)
    assert res.jumps == []
    assert res.candidates == []


def test_refractory_suppresses_a_double_count():
    """Two jumps 1 s apart (< `jumpRefractory`) count once, with the second as a candidate."""
    gap = 1.0                                  # < jumpRefractory (2 s)
    one = J.simulate_jump(1.0, 0.2, "const", noise=NOISE_FREE, context_s=3.0)
    keep_a = one.t <= one.t1 + gap / 2.0       # first trace, cut mid-gap
    keep_b = one.t >= one.t0 - gap / 2.0       # second trace, picked up mid-gap
    t = np.concatenate([one.t[keep_a],
                        one.t[keep_b] + (one.t1 + gap / 2.0) - (one.t0 - gap / 2.0)
                        + 1.0 / 100.0])
    mag = np.concatenate([one.mag[keep_a], one.mag[keep_b]])
    res = J.detect_jumps_from_arrays(t, mag)
    assert len(res.jumps) == 1
    assert any(c.reason == "refractory" for c in res.candidates)


def test_sensor_gap_voids_the_window():
    sj = J.simulate_jump(1.0, 0.2, "const", noise=NOISE_FREE)
    mid = 0.5 * (sj.t0 + sj.t1)
    keep = ~((sj.t > mid - 0.15) & (sj.t < mid + 0.15))
    res = J.detect_jumps_from_arrays(sj.t[keep], sj.mag[keep])
    assert res.jumps == []
    assert [c.reason for c in res.candidates] == ["gap_in_window"]


def test_support_above_the_threshold_is_structurally_invisible():
    """`jumpAirborneMaxG` is a hard ceiling on the support a jump may carry, not a soft one.

    At the suggested 0.6 g a wing carrying 0.7 g of the rider's weight produces a window the
    detector never sees -- which is exactly why the default is 0.75 g.
    """
    sj = J.simulate_jump(1.0, 0.7, "const", noise=NOISE_FREE)
    tight = J.detect_jumps_from_arrays(sj.t, sj.mag, J.JumpConfig(airborne_max_g=0.6))
    assert tight.jumps == [] and tight.candidates == []
    assert len(J.detect_jumps_from_arrays(sj.t, sj.mag).jumps) == 1


# --------------------------------------------------------------------------------------
# estimator accuracy on noise-free synthetics
# --------------------------------------------------------------------------------------

@pytest.mark.parametrize("h", [0.5, 1.0, 2.0, 3.0, 5.0])
@pytest.mark.parametrize("s", [0.0, 0.2, 0.4, 0.6, 0.7])
def test_noise_free_accuracy_within_two_percent(h, s):
    sj = J.simulate_jump(h, s, "const", noise=NOISE_FREE)
    res = J.detect_jumps_from_arrays(sj.t, sj.mag)
    assert len(res.jumps) == 1
    e = res.jumps[0].height
    assert e.integrated_m == pytest.approx(h, rel=0.02)
    assert e.closed_form_m == pytest.approx(h, rel=0.02)


@pytest.mark.parametrize("s", [0.0, 0.2, 0.4, 0.6, 0.7])
def test_naive_overestimates_by_exactly_one_over_one_minus_s(s):
    """The headline. Jan's claim, made quantitative: naive/true = 1/(1-s), to 2 %."""
    sj = J.simulate_jump(1.0, s, "const", noise=NOISE_FREE)
    res = J.detect_jumps_from_arrays(sj.t, sj.mag)
    e = res.jumps[0].height
    assert e.naive_m / 1.0 == pytest.approx(1.0 / (1.0 - s), rel=0.02)
    assert e.naive_ratio == pytest.approx(1.0 / (1.0 - s), rel=0.03)


@pytest.mark.parametrize("s", [0.0, 0.2, 0.4, 0.6])
def test_closed_form_equals_integrated_for_constant_support(s):
    """They are the same estimator when s is constant -- a theorem, so assert it tightly."""
    sj = J.simulate_jump(2.0, s, "const", noise=NOISE_FREE)
    e = J.detect_jumps_from_arrays(sj.t, sj.mag).jumps[0].height
    assert e.integrated_m == pytest.approx(e.closed_form_m, rel=0.005)


@pytest.mark.parametrize("s", [0.2, 0.3, 0.35])
def test_integrated_beats_closed_form_on_descent_only_support(s):
    """Asymmetric support is where the primary estimator earns its keep.

    Support all in the descent half: the mean is unchanged, so the closed form cannot see
    the difference and reads low, while the integral follows the profile.
    """
    sj = J.simulate_jump(2.0, s, "descent", noise=NOISE_FREE)
    e = J.detect_jumps_from_arrays(sj.t, sj.mag).jumps[0].height
    err_int = abs(e.integrated_m - 2.0)
    err_cf = abs(e.closed_form_m - 2.0)
    assert err_int == pytest.approx(0.0, abs=0.06)
    assert err_cf > err_int


def test_uncertainty_is_dominated_by_the_support_profile_not_the_sensor():
    """The design conclusion: this estimator is systematics-limited, so a better accelerometer
    would buy nothing. Only a torso-mounted sensor (or a real calibration) would."""
    sj = J.simulate_jump(1.0, 0.3, "const", rate_hz=100.0, rng=np.random.default_rng(3))
    e = J.detect_jumps_from_arrays(sj.t, sj.mag).jumps[0].height
    assert e.sigma_profile_m > 5 * e.sigma_noise_m
    assert e.sigma_profile_m > 5 * e.sigma_timing_m
    assert e.sigma_m == pytest.approx(
        np.hypot(np.hypot(e.sigma_noise_m, e.sigma_profile_m), e.sigma_timing_m), rel=1e-6)


def test_height_estimates_are_never_negative():
    """A window that is fully supported (s = 1) must read 0 m, not a negative height."""
    t = np.linspace(0.0, 1.0, 101)
    e = J.estimate_height(t, np.ones_like(t), airtime_s=1.0)
    assert e.integrated_m == 0.0 and e.closed_form_m == 0.0
    assert e.naive_m > 0.0                     # the naive one still cheerfully reports 1.2 m


# --------------------------------------------------------------------------------------
# baro secondary
# --------------------------------------------------------------------------------------

def test_baro_reports_insufficient_samples_for_a_short_hop():
    """0.64 s of airtime cannot hold two 1 Hz samples often enough to be worth a number."""
    sj = J.simulate_jump(0.5, 0.0, "const", noise=NOISE_FREE, alt_phase=0.5)
    fit = J.fit_baro(sj.alt_t, sj.alt_m, sj.t0, sj.t1)
    assert fit.status == "insufficient_samples"
    assert fit.height_m is None


def test_baro_fits_a_big_jump_when_samples_exist():
    sj = J.simulate_jump(5.0, 0.0, "const", noise=NOISE_FREE, alt_phase=0.0)
    fit = J.fit_baro(sj.alt_t, sj.alt_m, sj.t0, sj.t1)
    assert fit.status == "fit"
    assert fit.n_in_window >= 2
    assert fit.height_m == pytest.approx(5.0, rel=0.15)


def test_baro_without_a_channel_says_so():
    fit = J.fit_baro(None, None, 1.0, 2.0)
    assert fit.status == "no_channel" and fit.height_m is None


# --------------------------------------------------------------------------------------
# noise model measured from the real corpus
# --------------------------------------------------------------------------------------

@pytest.mark.skipif(not CIQ.exists(), reason="ciq fixture missing")
def test_noise_model_is_physically_sane():
    track = parse_fit(CIQ)
    spans = [(f.start_t, f.end_t) for f in segment_flights(clean(track)).flights]
    nm = J.measure_noise_model(track, flight_spans=spans)
    assert nm is not None
    assert nm.accel_rate_hz == pytest.approx(100.0, rel=0.01)
    assert 0.02 < nm.accel_sigma_g < 0.30                 # a wrist on a foil, not a bench
    assert nm.accel_rest_mean_g == pytest.approx(1.0, abs=0.15)
    assert nm.alt_rate_hz == pytest.approx(1.0, rel=0.05)
    assert nm.alt_quantum_m == pytest.approx(0.2, abs=0.01)
    assert 0.0 < nm.alt_sigma_m < 1.0
    assert nm.n_accel_samples > 100


def test_noise_model_needs_an_accel_stream():
    native = sorted((FIXTURES / "sessions" / "windsurf-native").glob("*.fit"))
    if not native:
        pytest.skip("no native fixture")
    assert J.measure_noise_model(parse_fit(native[0])) is None


# --------------------------------------------------------------------------------------
# corpus smoke
# --------------------------------------------------------------------------------------

def test_sources_without_accel_return_none():
    for sub in ("windsurf-native", "other-apps"):
        for p in sorted((FIXTURES / "sessions" / sub).glob("*.fit")):
            assert J.detect_jumps(parse_fit(p)) is None, p.name


@pytest.mark.skipif(not CIQ.exists(), reason="ciq fixture missing")
def test_corpus_smoke_finds_no_plausible_jump():
    """Jan does not jump, so anything the detector finds here is a false positive.

    The session yields a handful of jump-shaped signatures, and they sit on flight ends --
    a fall unweights the wrist and then slaps the water, which is the same shape as a jump
    seen through this sensor. The assertion is deliberately weak (a handful, all tiny): it
    guards against a tuning that suddenly calls the session's 23 flights 23 jumps.
    """
    res = J.detect_jumps(parse_fit(CIQ))
    assert res is not None
    assert res.sample_rate_hz == pytest.approx(100.0, rel=0.01)
    assert len(res.jumps) <= 3, "the detector should not be finding jumps in a no-jump session"
    for j in res.jumps:
        assert j.uncalibrated
        assert 0.0 <= j.height.integrated_m < 1.0        # chop/fall artefacts, not air
        assert j.height.naive_m >= j.height.integrated_m
        assert j.impact_g >= J.JumpConfig().impact_min_g
    for c in res.candidates:
        assert c.reason


@pytest.mark.skipif(not CIQ.exists(), reason="ciq fixture missing")
def test_raising_the_threshold_to_09_floods_the_session():
    """Why `jumpAirborneMaxG` is not simply set high enough to see every support fraction."""
    track = parse_fit(CIQ)
    loose = J.detect_jumps(track, J.JumpConfig(airborne_max_g=0.9, bridge_max_g=1.05))
    default = J.detect_jumps(track)
    assert len(default.candidates) < 20
    assert len(loose.candidates) > 100
    assert len(loose.candidates) > 10 * len(default.candidates)


# --------------------------------------------------------------------------------------
# validation grid plumbing
# --------------------------------------------------------------------------------------

def test_validation_grid_shape_and_headline():
    rows = J.validation_grid(heights=(1.0,), supports=(0.0, 0.4), profiles=("const",),
                             reps=3, noise=NOISE_FREE)
    assert len(rows) == 2
    for r in rows:
        assert r["detect_rate"] == 1.0
        assert r["integrated_mean"] == pytest.approx(1.0, rel=0.03)
        assert r["naive_ratio"] == pytest.approx(1.0 / (1.0 - r["s"]), rel=0.03)
