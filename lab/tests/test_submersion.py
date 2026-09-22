"""The wrist-under mask and its episodes (docs/algorithms/pumping.md "Turn outcome" step 2 and
"Submersion episodes").

Two halves. The **mask** (engine 0.22.0, ADR-029) reads a local, causal baseline rather than
the session median, and the cases below are the four traces that rule was written from: the
fenix 8 dunk that crawls back, the fenix 5X Plus dunk that re-anchors, the slow drift that is
not a dunk at all, and the recording gap. The **episodes** turn that boolean array into a
list a map can draw, and those cases are about where a run starts and stops, what a gap does
to it, and what the episode is said to have happened during.
"""

from pathlib import Path

import numpy as np

from wingfoil_lab.evidence import (BARO_SETTLE_M, BARO_SETTLE_S, SUBMERSION_MERGE_S,
                                   Submersion, attribute_submersions, submerged_mask,
                                   submerged_trace, submersion_runs)
from wingfoil_lab.goldens import analyze

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
TODAY = FIXTURES / "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"

DROP_M = 25.0


def _runs(alt, hz=1.0, gap=None, merge_s=SUBMERSION_MERGE_S):
    """Episodes for a bare altitude series, on a regular clock with no gaps by default."""
    alt = np.asarray(alt, float)
    t = np.arange(len(alt), dtype=float) / hz
    gap = np.zeros(len(alt), bool) if gap is None else np.asarray(gap, bool)
    mask, base = submerged_trace(alt, t, gap, DROP_M)
    return submersion_runs(t, gap, mask, alt, base, merge_s=merge_s)


def _mask(alt, hz=1.0, gap=None):
    """The wrist-under mask for a bare altitude series, on a regular clock."""
    alt = np.asarray(alt, float)
    t = np.arange(len(alt), dtype=float) / hz
    gap = np.zeros(len(alt), bool) if gap is None else np.asarray(gap, bool)
    return submerged_mask(alt, t, gap, DROP_M)


def _episodes(mask, alt, hz=1.0, gap=None, merge_s=SUBMERSION_MERGE_S):
    """Episodes for a mask written by hand, against a baseline of zero.

    Three cases below are about `submersion_runs`' **own** gap rule rather than the mask's,
    and since engine 0.22.0 the mask can no longer produce the shape they test: a gap
    restarts the baseline, so the first sample after one is dry by construction. The two are
    separate decisions and the run rule still has to hold on its own, so it is asserted on a
    mask handed in directly.
    """
    alt = np.asarray(alt, float)
    t = np.arange(len(alt), dtype=float) / hz
    gap = np.zeros(len(alt), bool) if gap is None else np.asarray(gap, bool)
    return submersion_runs(t, gap, np.asarray(mask, bool), alt, np.zeros(len(alt)),
                           merge_s=merge_s)


# ----------------------------------------------------------------------------- the mask


def test_a_fenix_8_dunk_flags_all_the_way_back_up():
    """Jan's watch: ~250 m of apparent drop, then a slew-limited crawl back over minutes.

    The crawl moves far more than `BARO_SETTLE_M` in `BARO_SETTLE_S`, so it is never a
    level -- the wrist is flagged for the whole time the altimeter is still recovering,
    which is what it was flagged for before the baseline became local.
    """
    dry_before = [0.0] * 120
    crawl = list(np.linspace(-250.0, 0.0, 251))     # 250 m over 250 s: 20 m per settle window
    m = _mask(dry_before + crawl + [0.0] * 60)
    assert not m[:120].any()
    assert m[120]                                    # the dunk itself
    assert m[120:120 + 200].all()                    # and every sample still under the line
    assert not m[-60:].any()


def test_a_fenix_5x_plus_dunk_that_re_anchors_flags_the_spike_and_then_stops():
    """A tester's fenix 5X Plus (20 Sep 2026) dunks and then sits at a *new* level.

    The spike is a fall and reads as one. The level that follows is not a fall, and the
    settle release says so: `BARO_SETTLE_S` of samples within `BARO_SETTLE_M` are accepted
    as the new baseline, and the rest of the afternoon is dry. Against a session median the
    whole of it read as one very long swim.
    """
    level = -100.0                       # the new anchor, well under +/-BARO_SETTLE_M of 0
    assert abs(level) > BARO_SETTLE_M + DROP_M
    m = _mask([0.0] * 120 + [-65.0, -134.0, -173.0] + [level] * 600)
    assert not m[:120].any()
    assert m[120:123].all(), "the dunk is still a dunk"
    settled = 123 + int(BARO_SETTLE_S)
    assert m[123:settled].all(), "the level is not accepted before it has held"
    assert not m[settled:].any(), "and every sample after that is riding, not swimming"


def test_a_slow_drift_is_never_a_dunk():
    """100 m over ten minutes -- weather, not water. The baseline walks with it."""
    assert not _mask(list(np.linspace(0.0, -100.0, 600))).any()


def test_a_recording_gap_restarts_the_baseline():
    """The samples either side of a gap are not evidence about one another, so the level
    after one is the level, not a 200 m fall."""
    alt = [0.0] * 60 + [-200.0] * 30
    assert _mask(alt)[60:].any(), "with no gap it is a dunk"
    gap = np.zeros(len(alt), bool)
    gap[60] = True
    assert not _mask(alt, gap=gap).any(), "across a gap it is a new baseline"


def test_no_altitude_channel_is_all_false():
    assert not _mask([np.nan] * 40).any()


# --------------------------------------------------------------------------- the episodes


def test_the_drop_is_measured_against_the_line_the_mask_crossed():
    """`drop_m` reads against the baseline in force at the run's first wet sample -- the
    same line the mask crossed to open it, so it can never be less than `DROP_M`."""
    alt = np.array([0.0, 1.0, 2.0, 3.0, -300.0])
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
    mask = np.zeros(len(alt), bool)
    mask[4:10] = True
    gap = np.zeros(len(alt), bool)
    gap[7] = True
    runs = _episodes(mask, alt, gap=gap)
    assert [(r.start_t, r.end_t) for r in runs] == [(4.0, 6.0), (7.0, 9.0)]


def test_a_gap_is_never_merged_across():
    alt = np.array([0.0] * 4 + [-200.0] * 2 + [0.0] + [-200.0] * 2 + [0.0] * 4)
    mask = np.zeros(len(alt), bool)
    mask[[4, 5, 7, 8]] = True
    gap = np.zeros(len(alt), bool)
    gap[7] = True
    assert len(_episodes(mask, alt, gap=gap, hz=4.0)) == 2


def test_a_gap_mid_submersion_splits_the_span_rather_than_timing_across_it():
    """A three-minute recording hole inside one dunk is not three minutes under water."""
    t = np.arange(11, dtype=float)
    t[3:] += 197.0                       # a 197 s recording hole, mid-dunk
    gap = np.zeros(11, bool)
    gap[3] = True
    alt = np.array([-200.0] * 5 + [0.0] * 6)
    mask = np.zeros(11, bool)
    mask[:5] = True
    runs = submersion_runs(t, gap, mask, alt, np.zeros(11))
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
