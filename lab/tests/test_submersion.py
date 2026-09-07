"""Submersion episodes (engine 0.16.0, docs/algorithms.md "Submersion episodes").

The mask itself is old and tested through the outcome ladder; what is new is reading it as
*events*. So these cases are about the three decisions that turns a boolean array into a
list a map can draw: where a run starts and stops, what a gap does to it, and what the
episode is said to have happened during.
"""

from pathlib import Path

import numpy as np

from wingfoil_lab.evidence import (SUBMERSION_MERGE_S, Submersion, attribute_submersions,
                                   submerged_mask, submerged_reference, submersion_runs)
from wingfoil_lab.goldens import analyze

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
TODAY = FIXTURES / "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"

DROP_M = 25.0


def _runs(alt, hz=1.0, gap=None, merge_s=SUBMERSION_MERGE_S):
    """Episodes for a bare altitude series, on a regular clock with no gaps by default."""
    alt = np.asarray(alt, float)
    t = np.arange(len(alt), dtype=float) / hz
    gap = np.zeros(len(alt), bool) if gap is None else np.asarray(gap, bool)
    return submersion_runs(t, gap, submerged_mask(alt, DROP_M), alt, merge_s=merge_s)


def test_reference_is_the_median_the_mask_uses():
    alt = np.array([0.0, 1.0, 2.0, 3.0, -300.0])
    assert submerged_reference(alt) == 1.0
    # And every masked sample is at least `DROP_M` under it, so `drop_m` can never be less.
    (run,) = _runs(alt)
    assert run.drop_m >= DROP_M


def test_no_altitude_channel_yields_no_episodes():
    assert _runs([np.nan] * 20) == []


def test_a_flat_channel_yields_no_episodes():
    """A source with a constant altitude -- or none -- must not invent a dunk."""
    assert _runs([12.0] * 40) == []


def test_one_run_is_one_episode_at_its_first_sample():
    alt = np.array([0.0] * 10 + [-200.0] * 4 + [0.0] * 10)
    (run,) = _runs(alt)
    assert (run.start_t, run.end_t, run.duration_s) == (10.0, 13.0, 3.0)
    assert run.turn_index is None and run.flight_end_index is None


def test_drop_is_the_deepest_sample_below_the_reference():
    alt = np.array([0.0] * 10 + [-100.0, -347.0, -100.0] + [0.0] * 10)
    (run,) = _runs(alt)
    assert run.drop_m == 347.0


def test_two_runs_far_apart_stay_two():
    alt = np.array([0.0] * 5 + [-200.0] * 2 + [0.0] * 10 + [-200.0] * 2 + [0.0] * 5)
    assert len(_runs(alt)) == 2


def test_runs_closer_than_the_merge_window_become_one():
    """A dunk and the wave after it. At 4 Hz two runs 1 s apart are one episode."""
    alt = np.array([0.0] * 8 + [-200.0] * 4 + [0.0] * 4 + [-200.0] * 4 + [0.0] * 8)
    assert len(_runs(alt, hz=4.0)) == 1
    # ... and are two the moment the merge window is closed.
    assert len(_runs(alt, hz=4.0, merge_s=0.0)) == 2


def test_a_recording_gap_always_breaks_a_run():
    """Even mid-submersion: the samples either side of a gap are not evidence about one
    another, which is the rule every other window in `evidence` obeys."""
    alt = np.array([0.0] * 4 + [-200.0] * 6 + [0.0] * 4)
    gap = np.zeros(len(alt), bool)
    gap[7] = True
    runs = _runs(alt, gap=gap)
    assert [(r.start_t, r.end_t) for r in runs] == [(4.0, 6.0), (7.0, 9.0)]


def test_a_gap_is_never_merged_across():
    alt = np.array([0.0] * 4 + [-200.0] * 2 + [0.0] + [-200.0] * 2 + [0.0] * 4)
    gap = np.zeros(len(alt), bool)
    gap[7] = True
    assert len(_runs(alt, gap=gap, hz=4.0)) == 2


def test_a_gap_mid_submersion_splits_the_span_rather_than_timing_across_it():
    """A three-minute recording hole inside one dunk is not three minutes under water."""
    t = np.arange(11, dtype=float)
    t[3:] += 197.0                       # a 197 s recording hole, mid-dunk
    gap = np.zeros(11, bool)
    gap[3] = True
    alt = np.array([-200.0] * 5 + [0.0] * 6)
    runs = submersion_runs(t, gap, submerged_mask(alt, DROP_M), alt)
    assert [(r.start_t, r.end_t, r.duration_s) for r in runs] == [(0.0, 2.0, 2.0),
                                                                  (200.0, 201.0, 1.0)]


def test_attribution_prefers_a_turn_over_a_flight_end():
    subs = [Submersion(start_t=10.0, end_t=12.0, duration_s=2.0, drop_m=200.0)]
    attribute_submersions(subs, [(3, 8.0, 14.0)], [(1, 9.0, 20.0)])
    assert (subs[0].turn_index, subs[0].flight_end_index) == (3, None)


def test_attribution_falls_through_to_a_flight_end():
    subs = [Submersion(start_t=30.0, end_t=31.0, duration_s=1.0, drop_m=200.0)]
    attribute_submersions(subs, [(3, 8.0, 14.0)], [(1, 29.0, 40.0)])
    assert (subs[0].turn_index, subs[0].flight_end_index) == (None, 1)


def test_an_episode_in_no_window_is_off_foil():
    subs = [Submersion(start_t=100.0, end_t=140.0, duration_s=40.0, drop_m=300.0)]
    attribute_submersions(subs, [(3, 8.0, 14.0)], [(1, 29.0, 40.0)])
    assert subs[0].turn_index is None and subs[0].flight_end_index is None


def test_overlap_is_enough_a_containment_is_not_required():
    """A 40 s swim that *starts* inside a jibe's outcome window is that jibe's."""
    subs = [Submersion(start_t=13.0, end_t=60.0, duration_s=47.0, drop_m=300.0)]
    attribute_submersions(subs, [(2, 8.0, 14.0)], [])
    assert subs[0].turn_index == 2


def test_the_verdict_flags_are_untouched_by_the_episodes():
    """The corpus check: every turn and end the mask flagged still carries the flag, and
    every flagged one has at least one episode overlapping the window it was read from."""
    a = analyze(TODAY)
    assert a.submersions, "this fixture is the one with three wrist dunks in it"
    for i, turn in enumerate(a.turns):
        if not (turn.submerged and turn.counted):
            continue
        w0, w1 = turn.start_t, turn.end_t + turn.outcome_window_s
        assert any(s.start_t <= w1 and s.end_t >= w0 for s in a.submersions)
    for i, end in enumerate(a.flight_ends):
        if not (end.submerged and end.owned_by_turn is None and not end.truncated):
            continue
        w0, w1 = end.t, end.t + end.window_s
        assert any(s.start_t <= w1 and s.end_t >= w0 for s in a.submersions)


def test_episodes_are_in_time_order_and_disjoint():
    a = analyze(TODAY)
    for prev, nxt in zip(a.submersions, a.submersions[1:]):
        assert prev.end_t < nxt.start_t
    assert all(s.end_t >= s.start_t for s in a.submersions)
    assert all(s.drop_m >= a.turn_config.baro_drop_m for s in a.submersions)


def test_an_index_names_a_real_record():
    a = analyze(TODAY)
    for s in a.submersions:
        if s.turn_index is not None:
            assert a.turns[s.turn_index].counted
            assert s.flight_end_index is None
        if s.flight_end_index is not None:
            end = a.flight_ends[s.flight_end_index]
            assert end.owned_by_turn is None and not end.truncated
