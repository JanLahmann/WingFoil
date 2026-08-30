"""Wind-axis estimation from the course-over-ground distribution.

Contract: docs/algorithms.md "Wind axis estimation". Foiling samples only (COG is not
heading below ~2 m/s) -> distance-weighted circular COG histogram -> the two dominant
reach lobes -> the wind axis is their bisector. The axis is a *line*, so the bisector
leaves a 180 deg ambiguity, resolved by the **no-go zone**: a sailor can hold any
downwind course but none within ~45 deg of the wind, so of the two axis ends the one
whose +-45 deg cone holds (almost) no distance is the direction the wind blows from.

algorithms.md originally specified the up/downwind *speed* asymmetry here ("downwind
reaches are faster"). On the whole fixture corpus that sign is inverted -- mean speed
rises as the course turns *toward* the wind, because a foil loses apparent wind deep
downwind -- so speed is kept only as a diagnostic (`speed_asymmetry`), never as the
decision rule. The no-go-zone rule agrees with Garda's diurnal pattern (morning Peler
from N, afternoon Ora from S) on all corpus sessions.

Angles are meteorological: ``dir_deg`` is the direction the wind blows *from*, 0 = north,
clockwise. TWA is ``wrap180(cog - dir_deg)``: 0 = sailing straight upwind, +-180 = straight
downwind, positive = wind over the port bow (port tack).

The 180 deg call has a second, *rider-declared* source of evidence: the *default turn
type*. Flipping the wind 180 deg swaps every jibe and tack, so a rider's declared habit is
evidence about orientation -- "I jibe far more than I tack" says the wind blows from
whichever end makes the session's sweeps come out mostly jibes. It is a prior, not a
measurement, so it may only ever break a tie the cone could not: it is consulted only while
the cone margin is below ``full_margin``, and it can never touch a decisive cone call. See
`_turn_type_prior` for the blend.

Known limitation: when the two lobes are exactly opposite (pure beam-reach out-and-back)
the bisector is degenerate -- the true axis is then perpendicular to the lobes and no
histogram bisector can recover it. Such sessions are rejected (``dir_deg = None``).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from .filters import CleanTrack, unwrapped_cog_deg
from .flight import FlightResult

# `default_turn_type` vocabulary (docs/algorithms.md "Default turn type").
JIBES = "jibes"
TACKS = "tacks"
BALANCED = "balanced"          # prior off: the cone decides alone, as it always did
DEFAULT_TURN_TYPES = (JIBES, TACKS, BALANCED)


@dataclass
class WindConfig:
    """docs/algorithms.md "Wind axis estimation" defaults."""

    min_speed_mps: float = 2.0            # below this COG != heading (COAPS caveat)
    bin_deg: float = 10.0                 # circular histogram bin width
    smooth_deg: float = 20.0              # circular moving-average half-width on the histogram
    lobe_half_width_deg: float = 25.0     # mass window used to refine and weigh a lobe
    min_lobe_separation_deg: float = 60.0 # two modes closer than this are one lobe
    max_lobe_separation_deg: float = 179.0  # above this the bisector is degenerate
    min_distance_m: float = 500.0         # less foiling distance than this -> no estimate
    min_confidence: float = 0.5           # below this turns stay "turn" (not tack/jibe)
    no_go_half_angle_deg: float = 45.0    # cone around an axis end used for the 180 deg call
    min_cone_mass: float = 0.01           # both cones emptier than this -> call unresolved
    full_margin: float = 0.4              # cone asymmetry at/above which the call is certain
    default_turn_type: str = JIBES        # the rider's declared habit; "balanced" = no prior
    turn_prior_weight: float = 0.5        # cap on the prior's signed evidence contribution


@dataclass
class WindEstimate:
    """Wind axis plus the evidence behind it (all angles in degrees)."""

    dir_deg: float | None = None          # wind FROM direction, 0..360; None = no estimate
    confidence: float = 0.0               # [0,1]; axis_confidence x 180-deg-call certainty
    source: str = "none"                  # "estimate" | "none" (golden schema wording)
    axis_deg: float | None = None         # ambiguity-free axis line, dir_deg mod 180
    lobes_deg: tuple[float, float] | None = None      # the two reach modes
    lobe_mass: tuple[float, float] | None = None      # their share of foiled distance
    separation_deg: float | None = None
    axis_confidence: float = 0.0          # mass x balance x separation (axis line only)
    ambiguity_margin: float = 0.0         # no-go cone asymmetry backing the 180 deg call
    speed_asymmetry: float = 0.0          # diagnostic: weighted corr(cos TWA, speed); the
    #                                       corpus runs positive (upwind faster on a foil)
    turn_type_margin: float = 0.0         # |default - other| / votes, the prior's strength
    turn_type_dir_deg: float | None = None  # axis end the declared habit favours; None = the
    #                                       prior did not run (balanced / decisive cone) or
    #                                       had no votes
    turn_type_votes: int = 0              # sweeps that were tack-or-jibe under BOTH ends
    prior_flipped: bool = False           # the prior overturned the no-go-cone call
    distance_m: float = 0.0               # foiled distance the estimate is built on
    min_confidence: float = WindConfig.min_confidence   # the bar this estimate is judged at
    #                                       (carried from the WindConfig it was built with,
    #                                        so a caller-supplied threshold is honoured)

    @property
    def usable(self) -> bool:
        """Wind is trustworthy enough to label turns tack/jibe."""
        return self.dir_deg is not None and self.confidence >= self.min_confidence


def estimate_wind(clean: CleanTrack, flights: FlightResult,
                  config: WindConfig | None = None,
                  turn_config: "TurnConfig | None" = None) -> WindEstimate:   # noqa: F821
    """Estimate the wind axis from the foiling part of a track.

    Returns a `WindEstimate` with ``dir_deg = None`` and zero confidence whenever the
    COG distribution is not usefully bimodal (too little foiling, one lobe only, or an
    exactly opposed pair).

    `turn_config` is the `turns.TurnConfig` the *same* pipeline will detect turns with (its
    annotation is quoted rather than imported: `turns` imports this module, so the
    dependency has to keep running one way only). It is read only when the default-turn-type
    prior actually runs -- a weak cone margin and a declared habit -- and only to find the
    same sweeps that pipeline will report. A caller that tunes turn detection must hand its
    config in, or the prior would vote on a different set of turns than the ones the session
    ends up showing.
    """
    cfg = config or WindConfig()
    cog, weight, speed = foiling_courses(clean, flights, cfg)
    total = float(weight.sum())
    if total < cfg.min_distance_m:
        return WindEstimate(distance_m=total, min_confidence=cfg.min_confidence)

    centers, hist = circular_histogram(cog, weight, cfg.bin_deg, cfg.smooth_deg)
    lobes = _dominant_lobes(centers, hist, cfg.min_lobe_separation_deg)
    if lobes is None:
        return WindEstimate(distance_m=total, min_confidence=cfg.min_confidence)

    lobe_deg = tuple(_refine_lobe(cog, weight, c, cfg.lobe_half_width_deg) for c in lobes)
    mass = tuple(_lobe_mass(cog, weight, c, cfg.lobe_half_width_deg) / total for c in lobe_deg)
    sep = abs(_wrap180(lobe_deg[1] - lobe_deg[0]))
    if sep > cfg.max_lobe_separation_deg:
        return WindEstimate(distance_m=total, lobes_deg=lobe_deg, lobe_mass=mass,
                            separation_deg=sep, min_confidence=cfg.min_confidence)

    bisector = _circular_mean(np.array(lobe_deg), np.ones(2))
    axis_conf = _axis_confidence(mass, sep, cfg)
    cone_dir, margin = _resolve_180(cog, weight, bisector, cfg)
    prior = _turn_type_prior(clean, flights, cone_dir, margin, cfg, turn_config)
    dir_deg = cone_dir + (180.0 if prior.flipped else 0.0)
    asym = _weighted_corr(np.cos(np.radians(cog - dir_deg)), speed, weight)
    conf = axis_conf * prior.certainty
    return WindEstimate(
        dir_deg=float(dir_deg % 360.0), confidence=float(conf), source="estimate",
        axis_deg=float(dir_deg % 180.0), lobes_deg=lobe_deg, lobe_mass=mass,
        separation_deg=float(sep), axis_confidence=float(axis_conf),
        ambiguity_margin=float(margin), speed_asymmetry=float(asym),
        turn_type_margin=prior.margin, turn_type_dir_deg=prior.favoured_deg,
        turn_type_votes=prior.votes, prior_flipped=prior.flipped,
        distance_m=total, min_confidence=cfg.min_confidence,
    )


@dataclass
class _Prior:
    """What the default-turn-type prior did to one 180 deg call."""

    certainty: float                      # the [0,1] factor `confidence` is scaled by
    flipped: bool = False                 # the prior overturned the cone's pick
    margin: float = 0.0                   # |default - other| / votes, in [0,1]
    favoured_deg: float | None = None     # the axis end the declared habit points at
    votes: int = 0


def _turn_type_prior(clean: CleanTrack, flights: FlightResult, cone_dir: float,
                     cone_margin: float, cfg: WindConfig, turn_config) -> _Prior:
    """Blend the rider's declared turn habit into a *weak* 180 deg call.

    Flipping the wind 180 deg shifts every TWA by 180 deg, so every head-to-wind crossing
    becomes a dead-downwind one: the same sweep that is a tack under one end of the axis is
    a jibe under the other. A rider who declares "mostly jibes" is therefore stating a
    preference between the two ends, and on a session whose no-go cones cannot separate them
    that statement is the best evidence left.

    It is a prior, not a measurement, and the blend keeps it in its place:

    * ``e_cone = clip01(cone_margin / full_margin)`` -- the cone's own certainty, exactly the
      factor `confidence` has always been scaled by. ``e_cone >= 1`` means the cone is
      decisive and the prior is **not consulted at all**, so a strong call is untouchable and
      its numbers are bit-identical to the pre-prior engine.
    * Only sweeps that come out tack-or-jibe under **both** ends vote -- a bear-away is not
      evidence about the wind, and a sweep that is a maneuver under one end only would let
      the prior manufacture its own electorate.
    * ``m_turn = (n_default - n_other) / votes`` in [-1, 1], signed *towards the cone's pick*:
      positive means the cone's end already makes the rider's declared type the majority.
    * ``e = e_cone + turn_prior_weight * m_turn``. The call is the cone's when ``e >= 0`` and
      the opposite end when ``e < 0``, and ``certainty = clip01(|e|)`` replaces the cone
      factor in `confidence`.

    With the default weight 0.5 the prior can only overturn a cone margin below half of
    `full_margin`, and only then with a decisive turn-type majority: a 90/10 jibe split
    (``|m_turn| = 0.8``) flips a cone margin under 0.16, an even split flips nothing. With
    `default_turn_type` = ``balanced``, no votes, or an exact tie the prior contributes
    nothing and the result is the pre-prior one, to the bit.
    """
    e_cone = _clip01(cone_margin / cfg.full_margin) if cfg.full_margin > 0 else 1.0
    if cfg.default_turn_type == BALANCED or e_cone >= 1.0:
        return _Prior(certainty=e_cone)
    from .turns import turn_sweeps                       # local: turns imports this module
    n_default, n_other = turn_type_votes(turn_sweeps(clean, flights, turn_config),
                                         cone_dir, cfg.default_turn_type)
    return _blend(e_cone, n_default, n_other, cone_dir, cfg)


def turn_type_votes(sweeps: list[tuple[float, float]], cone_dir: float,
                    default_turn_type: str) -> tuple[int, int]:
    """(votes for the declared type, votes against) among `sweeps`, judged at `cone_dir`.

    A sweep votes only if it is a tack-or-jibe under **both** ends of the axis: a bear-away
    is not evidence about the wind, and a sweep that is a maneuver under one end only would
    let the prior manufacture its own electorate. The two ends give opposite names to every
    sweep that does vote, so the count against is the count the flipped orientation would
    return -- one pass over the sweeps answers for both.
    """
    from .turns import JIBE, TACK, classify_sweep        # local: turns imports this module
    wanted = JIBE if default_turn_type == JIBES else TACK
    n_default = n_other = 0
    for cog_in, cog_out in sweeps:
        here = classify_sweep(cog_in, cog_out, cone_dir)[0]
        there = classify_sweep(cog_in, cog_out, cone_dir + 180.0)[0]
        if here not in (TACK, JIBE) or there not in (TACK, JIBE):
            continue
        n_default += int(here == wanted)
        n_other += int(here != wanted)
    return n_default, n_other


def _blend(e_cone: float, n_default: int, n_other: int, cone_dir: float,
           cfg: WindConfig) -> _Prior:
    """The arithmetic of the blend (`_turn_type_prior`, and docs/algorithms.md).

    ``e = e_cone + turn_prior_weight * m_turn`` with ``m_turn`` signed towards the cone's
    own pick; the call is the cone's while ``e >= 0`` and the opposite end below that, and
    ``clip01(|e|)`` is the certainty that replaces the cone factor in `confidence`.
    """
    votes = n_default + n_other
    if votes == 0:
        return _Prior(certainty=e_cone)
    m_turn = (n_default - n_other) / votes
    favoured = None if m_turn == 0 else (cone_dir if m_turn > 0 else cone_dir + 180.0)
    e = e_cone + cfg.turn_prior_weight * m_turn
    return _Prior(certainty=_clip01(abs(e)), flipped=e < 0.0, margin=abs(m_turn),
                  favoured_deg=None if favoured is None else float(favoured % 360.0),
                  votes=votes)


def foiling_courses(clean: CleanTrack, flights: FlightResult,
                    config: WindConfig | None = None
                    ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Per-step (cog_deg, distance_m, speed_mps) over foiling steps above the speed floor.

    One entry per gap-free 1-sample step whose start sample lies inside a flight and whose
    Doppler speed clears ``min_speed_mps``.
    """
    cfg = config or WindConfig()
    cogs, weights, speeds = [], [], []
    on = foiling_mask(clean, flights)
    for seg in clean.segments():
        if len(seg) < 2 or seg["x"].isna().all():
            continue
        idx = seg.index.to_numpy()
        x, y = seg["x"].to_numpy(float), seg["y"].to_numpy(float)
        v = seg["doppler_mps"].to_numpy(float)
        u = np.mod(unwrapped_cog_deg(x, y), 360.0)
        step = np.hypot(np.diff(x), np.diff(y))
        keep = on[idx][:-1] & (v[:-1] >= cfg.min_speed_mps)
        cogs.append(u[keep])
        weights.append(step[keep])
        speeds.append(v[:-1][keep])
    if not cogs:
        return np.array([]), np.array([]), np.array([])
    return np.concatenate(cogs), np.concatenate(weights), np.concatenate(speeds)


def foiling_mask(clean: CleanTrack, flights: FlightResult) -> np.ndarray:
    """Boolean per clean record: is this sample inside a detected flight?"""
    t = clean.records["t"].to_numpy(float)
    mask = np.zeros(len(t), dtype=bool)
    for f in flights.flights:
        mask |= (t >= f.start_t) & (t <= f.end_t)
    return mask


def circular_histogram(cog_deg: np.ndarray, weight: np.ndarray, bin_deg: float,
                       smooth_deg: float) -> tuple[np.ndarray, np.ndarray]:
    """Weighted circular histogram of COG -> (bin centers, smoothed weights)."""
    n = int(round(360.0 / bin_deg))
    idx = np.floor(np.mod(cog_deg, 360.0) / bin_deg).astype(int) % n
    hist = np.zeros(n)
    np.add.at(hist, idx, weight)
    half = max(int(round(smooth_deg / bin_deg)), 0)
    if half:
        kernel = np.ones(2 * half + 1) / (2 * half + 1)
        hist = np.convolve(np.concatenate([hist[-half:], hist, hist[:half]]),
                           kernel, mode="valid")
    return (np.arange(n) + 0.5) * bin_deg, hist


def _dominant_lobes(centers: np.ndarray, hist: np.ndarray,
                    min_sep_deg: float) -> tuple[float, float] | None:
    """Highest histogram bin, plus the highest bin at least `min_sep_deg` away."""
    if hist.sum() <= 0:
        return None
    first = int(np.argmax(hist))
    far = np.abs(_wrap180(centers - centers[first])) >= min_sep_deg
    if not far.any() or hist[far].max() <= 0:
        return None
    second = int(np.flatnonzero(far)[int(np.argmax(hist[far]))])
    return float(centers[first]), float(centers[second])


def _refine_lobe(cog_deg: np.ndarray, weight: np.ndarray, center: float,
                 half_width: float) -> float:
    """Weighted circular mean of the samples inside the lobe window (sub-bin resolution)."""
    sel = np.abs(_wrap180(cog_deg - center)) <= half_width
    if not sel.any():
        return float(center % 360.0)
    return float(_circular_mean(cog_deg[sel], weight[sel]) % 360.0)


def _lobe_mass(cog_deg: np.ndarray, weight: np.ndarray, center: float,
               half_width: float) -> float:
    return float(weight[np.abs(_wrap180(cog_deg - center)) <= half_width].sum())


def _axis_confidence(mass: tuple[float, float], sep_deg: float, cfg: WindConfig) -> float:
    """Product of three [0,1] factors: lobe mass, lobe balance, mode separation.

    mass    -- share of foiled distance inside the two lobe windows (0.2 -> 0, 0.6 -> 1)
    balance -- weaker lobe over stronger (0 -> 0, 0.5 -> 1); one-sided sessions score low
    sep     -- distinctness of the two modes (min separation -> 0, +20 deg -> 1)
    """
    total = mass[0] + mass[1]
    balance = min(mass) / max(mass) if max(mass) > 0 else 0.0
    f_mass = _clip01((total - 0.2) / 0.4)
    f_balance = _clip01(balance / 0.5)
    f_sep = _clip01((sep_deg - cfg.min_lobe_separation_deg) / 20.0)
    return f_mass * f_balance * f_sep


def _resolve_180(cog_deg: np.ndarray, weight: np.ndarray, bisector_deg: float,
                 cfg: WindConfig) -> tuple[float, float]:
    """Pick the axis end the wind blows *from* -> (dir_deg, margin).

    No-go zone: courses within ~45 deg of the wind are unsailable while dead downwind is
    not, so the emptier of the two end cones is upwind. The margin is the relative cone
    asymmetry in [0,1] (1 = upwind cone completely empty); it is 0 when both cones are
    empty, which leaves the axis line usable but the direction a coin flip.
    """
    th = cfg.no_go_half_angle_deg
    total = weight.sum()
    m_a = float(weight[np.abs(_wrap180(cog_deg - bisector_deg)) <= th].sum()) / total
    m_b = float(weight[np.abs(_wrap180(cog_deg - bisector_deg - 180.0)) <= th].sum()) / total
    if m_a + m_b < cfg.min_cone_mass:
        return float(bisector_deg % 360.0), 0.0
    dir_deg = bisector_deg if m_a < m_b else bisector_deg + 180.0
    return float(dir_deg % 360.0), abs(m_a - m_b) / (m_a + m_b)


def _weighted_corr(a: np.ndarray, b: np.ndarray, w: np.ndarray) -> float:
    tot = w.sum()
    if tot <= 0 or a.size < 2:
        return 0.0
    da = a - (w * a).sum() / tot
    db = b - (w * b).sum() / tot
    den = math.sqrt(float((w * da * da).sum()) * float((w * db * db).sum()))
    return float((w * da * db).sum() / den) if den > 0 else 0.0


def _circular_mean(deg: np.ndarray, weight: np.ndarray) -> float:
    r = np.radians(deg)
    return float(np.degrees(math.atan2(float((weight * np.sin(r)).sum()),
                                       float((weight * np.cos(r)).sum()))) % 360.0)


def _wrap180(deg):
    """Signed angle difference folded into (-180, 180]."""
    return (np.asarray(deg, float) + 180.0) % 360.0 - 180.0


def _clip01(v: float) -> float:
    return float(min(max(v, 0.0), 1.0))
