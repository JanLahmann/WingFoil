"""Jump detection and height estimation from the wrist accelerometer — THEORETICAL.

**UNCALIBRATED.** Jan does not jump (yet), so no real jump exists anywhere in the corpus and
nothing here has ever been checked against a measured height. Every number this module
produces is validated *only* against the synthetic generator in this same file, which is to
say: it is validated against the physics we believe, not against the water. Treat it as a
design study for when jumps start happening, not as a metric. Nothing in here feeds goldens,
the watch, or the phone.

The physics (the reason this module exists)
-------------------------------------------
The textbook hang-time formula ``h = g*T^2/8`` assumes an unsupported ballistic body: up at
``v0``, apex at ``T/2``, back down, apex height ``g*T^2/8``. A wingfoiler is **not** that
body. The wing is loaded during the whole jump; it lifts on the way up and parachutes on the
way down, so the rider's vertical acceleration is smaller than ``g`` in *both* phases. Same
airtime, much less height. Applied naively the formula therefore **overestimates** — and it
does so by exactly ``1/(1-s)`` for a constant support fraction ``s`` (see below), which is a
factor of 3.3 at ``s = 0.7``. That is not a rounding error, it is the whole answer.

An accelerometer measures *specific force*, not acceleration: it reads ~0 g in free fall and
~1 g when fully supported. During the airborne phase it therefore reads the **support
fraction** ``s(t) = |a|(t) / g`` directly — the very quantity the naive formula assumes is
zero. So the sensor that gives us the airtime also tells us how wrong the airtime formula is.

With support, the vertical equation of motion is::

    z''(t) = -(1 - s(t)) * g          (down positive g, s in [0, 1])

Integrated over the airborne window ``[t0, t1]`` with ``z(t0) = z(t1) = 0`` (leaves the
water, returns to it), the initial vertical velocity is fixed by the boundary condition
rather than assumed, and the reported height is the peak of that trajectory. Three
estimators are reported side by side, deliberately:

``integrated``    primary — the full ``z''= -(1-s(t))g`` simulation using the measured
                  per-sample support profile. Handles a wing whose loading changes through
                  the jump (it usually does: light off the takeoff, heavy on the descent).
``closed_form``   ``(1 - s_mean) * g * T^2 / 8`` — the naive formula scaled by the mean
                  support. Identical to ``integrated`` for constant ``s`` (proved in the
                  validation grid: bias 0.000 m); it diverges only when ``s`` varies.
``naive``         ``g * T^2 / 8`` — reported **for comparison only**, never as a metric. Its
                  ratio to the truth is the headline number of docs/algorithms.md.

Wrist vs centre of mass (the honest caveat)
-------------------------------------------
``s(t)`` is measured at the *wrist*, and the wrist is the hand holding a loaded wing — the
one part of the body most directly coupled to the lifting surface. It is not the centre of
mass. Arm flex, wing sheeting and the boom's own swing all add wrist-specific specific force
that the trunk never feels, and the sign is not fixed: pulling the wing down loads the wrist
above body support, letting it float unloads it below. The estimator treats wrist support as
a proxy for body support, and the ±0.1 support-profile term in the per-jump uncertainty is
sized to cover that proxy error rather than sensor noise (which is ~10x smaller). A chest or
waist sensor would remove the caveat; a wrist watch cannot.

Detection
---------
Takeoff spike (the pop off the water) -> a sustained low-g phase (the airborne window) ->
a landing impact spike. Thresholds are the ``jump*`` parameters in docs/algorithms.md.
Sources without an accel stream (native / other-app FITs) get ``None``, as everywhere else.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

from .parse import RawTrack

G = 9.80665  # m/s^2


# --------------------------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------------------------

@dataclass
class JumpConfig:
    """docs/algorithms.md "Jumps (theoretical, uncalibrated)" defaults.

    Chosen from the synthetic grid + the shape of the real corpus, NOT from labeled jumps —
    there are none. They are starting points to be re-tuned the day a jump is recorded.
    """

    # --- detection ---
    smooth_s: float = 0.06              # jumpSmooth: MEDIAN filter span on |a| (spike-safe)
    airborne_max_g: float = 0.75        # jumpAirborneMaxG: |a| below this is "airborne"
    bridge_s: float = 0.10              # jumpBridge: noise excursion that does not end a window
    bridge_max_g: float = 0.95          # jumpBridgeMaxG: ... provided it stays below this
    min_airtime_s: float = 0.4          # jumpMinAirtime: shorter is chop, not a jump
    max_airtime_s: float = 4.0          # jumpMaxAirtime: longer is a dropout, not a jump
    takeoff_min_g: float = 1.8          # jumpTakeoffMinG: pop spike before the window
    impact_min_g: float = 2.5           # jumpImpactMinG: landing spike after the window
    spike_window_s: float = 0.5         # jumpSpikeWindow: search span for both spikes
    refractory_s: float = 2.0           # jumpRefractory: dead time after an accepted jump
    max_gap_s: float = 0.1              # jumpMaxGap: a sensor hole voids the window

    # --- height estimation ---
    support_max: float = 1.0            # s(t) clipped to [0, support_max] before integrating
    support_sigma: float = 0.1          # jumpSupportSigma: assumed error on the profile
    min_height_m: float = 0.0           # heights are clamped at 0 (a jump cannot go down)

    # --- baro secondary ---
    baro_context_s: float = 5.0         # jumpBaroContext: baseline span each side of window
    baro_min_in_window: int = 2         # jumpBaroMinSamples: fewer -> "insufficient samples"


@dataclass
class NoiseModel:
    """Sensor noise measured from the real corpus — the input to the synthetic validation."""

    accel_sigma_g: float                # per-sample sd of |a| in quiet on-foil spans
    accel_rate_hz: float
    accel_rest_mean_g: float            # mean |a| in those spans (should be ~1)
    alt_sigma_m: float                  # detrended residual sd of the altitude channel at rest
    alt_quantum_m: float                # altitude channel quantisation step
    alt_rate_hz: float
    source: str = ""                    # fixture the model was measured from
    n_accel_samples: int = 0
    n_alt_samples: int = 0


# --------------------------------------------------------------------------------------
# results
# --------------------------------------------------------------------------------------

@dataclass
class HeightEstimate:
    """Three estimates of the same jump, plus the uncertainty budget of the primary one."""

    integrated_m: float                 # primary: z'' = -(1 - s(t)) g simulated over [t0, t1]
    closed_form_m: float                # (1 - s_mean) * g * T^2 / 8
    naive_m: float                      # g * T^2 / 8  -- comparison only
    airtime_s: float
    s_mean: float                       # mean clipped support fraction over the window
    s_min: float
    s_max: float
    v0_mps: float                       # initial vertical velocity implied by the profile
    sigma_m: float                      # combined 1-sigma on `integrated_m`
    sigma_noise_m: float                # accel-noise term
    sigma_profile_m: float              # +-support_sigma term (normally dominant)
    sigma_timing_m: float               # +-1 sample on the window edges
    n_samples: int

    @property
    def naive_ratio(self) -> float:
        """How many times larger the naive formula is than the corrected estimate."""
        return self.naive_m / self.integrated_m if self.integrated_m > 1e-9 else math.inf


@dataclass
class BaroFit:
    """Least-squares fit of a rise-fall template over the *known* airborne window."""

    status: str                         # "fit" | "insufficient_samples" | "no_channel"
    height_m: float | None = None
    sigma_m: float | None = None
    n_in_window: int = 0
    n_context: int = 0


@dataclass
class Jump:
    t_start: float                      # airborne window start, seconds on the records' base
    t_end: float
    height: HeightEstimate
    takeoff_g: float                    # peak |a| in the spike window before t_start
    impact_g: float                     # peak |a| in the spike window after t_end
    baro: BaroFit
    uncalibrated: bool = True           # always True; there is no calibration to switch off


@dataclass
class JumpCandidate:
    """A low-g span of jump-like duration that failed a gate. **Never** called a jump."""

    t_start: float
    t_end: float
    airtime_s: float
    min_g: float
    takeoff_g: float
    impact_g: float
    reason: str                         # why it was not accepted


@dataclass
class JumpResult:
    jumps: list[Jump] = field(default_factory=list)
    candidates: list[JumpCandidate] = field(default_factory=list)
    config: JumpConfig = field(default_factory=JumpConfig)
    sample_rate_hz: float = 0.0
    n_samples: int = 0
    notes: list[str] = field(default_factory=list)


# --------------------------------------------------------------------------------------
# detection
# --------------------------------------------------------------------------------------

def detect_jumps(track: RawTrack, config: JumpConfig | None = None) -> JumpResult | None:
    """Detect jumps in a parsed source, or None when it carries no accelerometer stream."""
    accel = track.accel
    if accel is None or accel.empty:
        return None
    mag = np.sqrt(accel["ax"].to_numpy(float) ** 2
                  + accel["ay"].to_numpy(float) ** 2
                  + accel["az"].to_numpy(float) ** 2)
    alt_t, alt_m = _altitude_channel(track)
    return detect_jumps_from_arrays(accel["t"].to_numpy(float), mag, config,
                                    alt_t=alt_t, alt_m=alt_m)


def detect_jumps_from_arrays(t: np.ndarray, mag: np.ndarray,
                             config: JumpConfig | None = None,
                             alt_t: np.ndarray | None = None,
                             alt_m: np.ndarray | None = None) -> JumpResult:
    """Detect jumps in raw (time, |a| in g) samples — unit tests and synthetic traces.

    Spike -> sustained low-g -> impact, in that order, with a refractory dead time. Spans
    that have jump-like duration but fail a gate come back as `candidates`, so a sweep over
    real sessions can be eyeballed without anything being mislabelled a jump.
    """
    cfg = config or JumpConfig()
    t = np.asarray(t, float)
    mag = np.asarray(mag, float)
    res = JumpResult(config=cfg, n_samples=int(t.size))
    if t.size < 8:
        res.notes.append("too few accel samples")
        return res

    step = float(np.median(np.diff(t)))
    if not (step > 0):
        res.notes.append("non-monotonic accel time base")
        return res
    fs = 1.0 / step
    res.sample_rate_hz = round(fs, 3)

    width = max(1, int(round(cfg.smooth_s * fs)))
    # A *median* filter, not a box average: a box drags the tail of the takeoff spike into
    # the first samples of the airborne window and shortens the measured airtime (~4 % at
    # 100 Hz, and h goes as T^2). The median rejects the spike and preserves the step edge.
    sm = _median_smooth(mag, width)

    last_end = -np.inf
    for i0, i1 in _bridged_runs(t, sm, cfg):
        # sub-sample crossing refinement: the true threshold crossing lies between the last
        # supported sample and the first low one, and at 25 Hz that half-sample matters
        # (h ~ T^2, so a 20 ms timing error on a 0.6 s window is already 7 % of the height).
        t0 = _crossing(t, sm, i0 - 1, i0, cfg.airborne_max_g)
        t1 = _crossing(t, sm, i1, i1 + 1, cfg.airborne_max_g)
        airtime = t1 - t0
        if airtime < cfg.min_airtime_s:
            continue                                  # chop, arm swing, one bad sample
        seg_t, seg_m = t[i0:i1 + 1], sm[i0:i1 + 1]
        pre = _peak_in(t, mag, t0 - cfg.spike_window_s, t0)
        post = _peak_in(t, mag, t1, t1 + cfg.spike_window_s)
        cand = JumpCandidate(t_start=float(t0), t_end=float(t1), airtime_s=float(airtime),
                             min_g=float(seg_m.min()), takeoff_g=float(pre),
                             impact_g=float(post), reason="")

        if airtime > cfg.max_airtime_s:
            cand.reason = "airtime_over_max"
        elif seg_t.size > 1 and float(np.max(np.diff(seg_t))) > max(cfg.max_gap_s, 3 * step):
            cand.reason = "gap_in_window"
        elif pre < cfg.takeoff_min_g:
            cand.reason = "no_takeoff_spike"
        elif post < cfg.impact_min_g:
            cand.reason = "no_landing_impact"
        elif t0 - last_end < cfg.refractory_s:
            cand.reason = "refractory"

        if cand.reason:
            res.candidates.append(cand)
            continue

        height = estimate_height(seg_t, seg_m, airtime_s=airtime, config=cfg, rate_hz=fs)
        res.jumps.append(Jump(t_start=float(t0), t_end=float(t1), height=height,
                              takeoff_g=float(pre), impact_g=float(post),
                              baro=fit_baro(alt_t, alt_m, t0, t1, cfg)))
        last_end = t1
    return res


# --------------------------------------------------------------------------------------
# height estimation
# --------------------------------------------------------------------------------------

def estimate_height(t: np.ndarray, mag: np.ndarray, airtime_s: float | None = None,
                    config: JumpConfig | None = None,
                    rate_hz: float | None = None) -> HeightEstimate:
    """Height from the support profile over one airborne window.

    `t`/`mag` are the in-window samples (|a| in g). `airtime_s` is the *refined* window
    length from the threshold crossings, which is slightly longer than ``t[-1] - t[0]``;
    the timing that matters for ``T^2`` is the crossing one, so it is passed in rather than
    re-derived from the samples we happen to have inside.
    """
    cfg = config or JumpConfig()
    t = np.asarray(t, float)
    mag = np.asarray(mag, float)
    T = float(airtime_s) if airtime_s is not None else float(t[-1] - t[0])
    fs = float(rate_hz) if rate_hz else (1.0 / float(np.median(np.diff(t))) if t.size > 1
                                         else 100.0)

    s = np.clip(mag, 0.0, cfg.support_max)
    s_mean = float(s.mean()) if s.size else 0.0

    naive = G * T * T / 8.0
    closed = max(cfg.min_height_m, (1.0 - s_mean) * naive)
    integrated, v0 = _integrate_profile(t, s, T, cfg)

    # Uncertainty budget. dh/ds = -g T^2 / 8 for the whole window, so every support-side
    # term is that sensitivity times a support error; the timing term is dh/dT = 2h/T.
    sens = naive
    # sqrt(pi/2): the support profile is read off a *median*-filtered stream, and a median is
    # ~1.25x less efficient than a mean at estimating the level of a Gaussian.
    sigma_noise = sens * MEDIAN_EFFICIENCY * _ACCEL_SIGMA_DEFAULT / math.sqrt(max(s.size, 1))
    sigma_profile = sens * cfg.support_sigma
    sigma_timing = 2.0 * integrated / T * (1.0 / fs) if T > 0 else 0.0
    sigma = math.sqrt(sigma_noise ** 2 + sigma_profile ** 2 + sigma_timing ** 2)

    return HeightEstimate(
        integrated_m=integrated, closed_form_m=closed, naive_m=naive, airtime_s=T,
        s_mean=s_mean, s_min=float(s.min()) if s.size else 0.0,
        s_max=float(s.max()) if s.size else 0.0, v0_mps=v0, sigma_m=sigma,
        sigma_noise_m=sigma_noise, sigma_profile_m=sigma_profile,
        sigma_timing_m=sigma_timing, n_samples=int(s.size))


# Per-sample |a| noise measured from the 2026-08-07 ciq fixture's quiet on-foil spans; used
# only to size the (sub-dominant) noise term when a caller has not measured its own.
_ACCEL_SIGMA_DEFAULT = 0.11
MEDIAN_EFFICIENCY = math.sqrt(math.pi / 2.0)


def _integrate_profile(t: np.ndarray, s: np.ndarray, T: float,
                       cfg: JumpConfig) -> tuple[float, float]:
    """Peak of z'' = -(1 - s(t)) g over [0, T] with z(0) = z(T) = 0. Returns (h, v0).

    v0 is *not* a free parameter: the rider left the water and came back to it, so the
    zero-displacement boundary condition at t = T pins it, and the whole estimate follows
    from the measured profile plus the measured airtime. That is the entire trick.
    """
    if s.size == 0 or T <= 0:
        return 0.0, 0.0
    if s.size == 1:
        phi = 1.0 - float(s[0])
        return max(cfg.min_height_m, phi * G * T * T / 8.0), phi * G * T / 2.0

    # Put the samples on [0, T] and pad to the true window edges (the first/last samples sit
    # a fraction of a sample inside the crossings), holding the edge support values.
    u = t - t[0]
    span = float(u[-1])
    if span <= 0:
        return 0.0, 0.0
    u = u * (T / span)
    a = -(1.0 - s) * G

    # v(t) = v0 + A(t), A = cumulative integral of a; z(T) = v0 T + int_0^T A = 0.
    A = _cumtrapz(a, u)
    v0 = -float(_cumtrapz(A, u)[-1]) / T
    z = v0 * u + _cumtrapz(A, u)
    return max(cfg.min_height_m, float(z.max())), float(v0)


def _cumtrapz(y: np.ndarray, x: np.ndarray) -> np.ndarray:
    out = np.zeros_like(y, dtype=float)
    out[1:] = np.cumsum((y[1:] + y[:-1]) / 2.0 * np.diff(x))
    return out


# --------------------------------------------------------------------------------------
# baro secondary
# --------------------------------------------------------------------------------------

def fit_baro(alt_t: np.ndarray | None, alt_m: np.ndarray | None,
             t0: float, t1: float, config: JumpConfig | None = None) -> BaroFit:
    """Fit a rise-fall template of unknown amplitude over the *known* airborne window.

    The window is not searched for, it is handed over by the accelerometer, so the fit has
    exactly one interesting free parameter (the height) plus a local baseline and drift.
    That is the only reason a 1 Hz channel can say anything at all about a sub-second event
    — and even so it usually cannot: at a typical 0.9 s airtime the expected number of
    in-window samples is ~1, and `jumpBaroMinSamples` = 2 then reports
    "insufficient_samples" rather than inventing a height from a single point.
    """
    cfg = config or JumpConfig()
    if alt_t is None or alt_m is None or len(alt_t) == 0:
        return BaroFit(status="no_channel")
    at = np.asarray(alt_t, float)
    am = np.asarray(alt_m, float)
    ok = np.isfinite(at) & np.isfinite(am)
    at, am = at[ok], am[ok]

    T = t1 - t0
    inw = (at >= t0) & (at <= t1)
    n_in = int(inw.sum())
    ctx = (at >= t0 - cfg.baro_context_s) & (at <= t1 + cfg.baro_context_s)
    n_ctx = int(ctx.sum())
    if n_in < cfg.baro_min_in_window or T <= 0:
        return BaroFit(status="insufficient_samples", n_in_window=n_in, n_context=n_ctx)

    x, y = at[ctx], am[ctx]
    # Parabolic rise-fall normalised to unit peak: 4 u (1 - u) on [0, 1], zero outside.
    u = np.clip((x - t0) / T, 0.0, 1.0)
    tmpl = np.where((x >= t0) & (x <= t1), 4.0 * u * (1.0 - u), 0.0)
    mid = 0.5 * (t0 + t1)
    design = np.column_stack([np.ones_like(x), x - mid, tmpl])
    if design.shape[0] < design.shape[1] + 1:
        return BaroFit(status="insufficient_samples", n_in_window=n_in, n_context=n_ctx)

    coef, *_ = np.linalg.lstsq(design, y, rcond=None)
    resid = y - design @ coef
    dof = max(design.shape[0] - design.shape[1], 1)
    s2 = float(resid @ resid) / dof
    try:
        cov = s2 * np.linalg.inv(design.T @ design)
        sigma = float(math.sqrt(max(cov[2, 2], 0.0)))
    except np.linalg.LinAlgError:
        sigma = float("nan")
    return BaroFit(status="fit", height_m=float(coef[2]), sigma_m=sigma,
                   n_in_window=n_in, n_context=n_ctx)


def _altitude_channel(track: RawTrack) -> tuple[np.ndarray | None, np.ndarray | None]:
    df = track.records
    for col in ("enhanced_altitude", "altitude"):
        if col in df and df[col].notna().any():
            a = df[col].to_numpy(float)
            t = df["t"].to_numpy(float)
            ok = np.isfinite(a) & np.isfinite(t) & (a > -400.0) & (a < 9000.0)
            return t[ok], a[ok]
    return None, None


# --------------------------------------------------------------------------------------
# noise model measured from the real corpus
# --------------------------------------------------------------------------------------

def measure_noise_model(track: RawTrack, flight_spans: list[tuple[float, float]] | None = None,
                        quiet_quantile: float = 0.25) -> NoiseModel | None:
    """Measure accel and altitude noise from a real session — the synthetic generator's input.

    Accel: |a| is binned into 1 s blocks; the quietest `quiet_quantile` of the blocks that
    fall inside `flight_spans` (steady foiling, no pumping, no chop hit) define the noise
    floor, and their pooled within-block sd is the per-sample sigma. Altitude: the residual
    of a linear fit over each rest span (speed < 0.5 m/s), which removes real climb without
    removing noise.
    """
    accel = track.accel
    if accel is None or accel.empty:
        return None
    t = accel["t"].to_numpy(float)
    mag = np.sqrt(accel["ax"].to_numpy(float) ** 2 + accel["ay"].to_numpy(float) ** 2
                  + accel["az"].to_numpy(float) ** 2)
    step = float(np.median(np.diff(t)))
    rate = 1.0 / step if step > 0 else 0.0

    b = ((t - t[0]) / 1.0).astype(int)
    n = int(b.max()) + 1
    cnt = np.bincount(b, minlength=n).astype(float)
    s1 = np.bincount(b, weights=mag, minlength=n)
    s2 = np.bincount(b, weights=mag * mag, minlength=n)
    full = cnt >= max(4.0, 0.5 * rate)
    with np.errstate(invalid="ignore", divide="ignore"):
        bmean = np.where(full, s1 / np.maximum(cnt, 1), np.nan)
        bsd = np.sqrt(np.clip(np.where(full, s2 / np.maximum(cnt, 1), np.nan) - bmean ** 2,
                              0.0, None))
    tb = t[0] + np.arange(n)
    keep = full & np.isfinite(bsd)
    if flight_spans:
        inside = np.zeros(n, bool)
        for a0, a1 in flight_spans:
            inside |= (tb >= a0) & (tb <= a1)
        keep &= inside
    if keep.sum() < 5:
        return None
    thr = float(np.nanquantile(bsd[keep], quiet_quantile))
    quiet = keep & (bsd <= thr)
    sigma_a = float(np.nanmedian(bsd[quiet]))
    mean_a = float(np.nanmedian(bmean[quiet]))

    alt_t, alt_m = _altitude_channel(track)
    alt_sigma, alt_q, alt_rate, n_alt = float("nan"), float("nan"), 0.0, 0
    if alt_t is not None and alt_t.size > 3:
        alt_rate = 1.0 / float(np.median(np.diff(alt_t)))
        steps = np.diff(np.unique(np.round(alt_m, 4)))
        alt_q = float(np.min(steps)) if steps.size else 0.0
        alt_sigma, n_alt = _rest_altitude_sigma(track, alt_t, alt_m)

    return NoiseModel(accel_sigma_g=sigma_a, accel_rate_hz=round(rate, 3),
                      accel_rest_mean_g=mean_a, alt_sigma_m=alt_sigma, alt_quantum_m=alt_q,
                      alt_rate_hz=round(alt_rate, 3), source=track.path,
                      n_accel_samples=int(quiet.sum()), n_alt_samples=n_alt)


def _rest_altitude_sigma(track: RawTrack, alt_t: np.ndarray, alt_m: np.ndarray,
                         rest_speed_mps: float = 0.5,
                         min_run: int = 20) -> tuple[float, int]:
    """Detrended residual sd of the altitude channel over spans where the rider is at rest."""
    df = track.records
    if "speed_mps" not in df:
        return float("nan"), 0
    tt = df["t"].to_numpy(float)
    sp = df["speed_mps"].to_numpy(float)
    rest_t = tt[np.isfinite(sp) & (sp < rest_speed_mps)]
    if rest_t.size == 0:
        return float("nan"), 0
    sel = np.isin(alt_t, rest_t)
    idx = np.flatnonzero(sel)
    if idx.size < min_run:
        return float("nan"), 0
    res: list[np.ndarray] = []
    for run in np.split(idx, np.flatnonzero(np.diff(idx) > 1) + 1):
        if run.size < min_run:
            continue
        x, y = alt_t[run], alt_m[run]
        res.append(y - np.polyval(np.polyfit(x, y, 1), x))
    if not res:
        return float("nan"), 0
    pooled = np.concatenate(res)
    return float(np.std(pooled)), int(pooled.size)


# --------------------------------------------------------------------------------------
# synthetic jump generator — the only validation that exists
# --------------------------------------------------------------------------------------

@dataclass
class SynthJump:
    """A generated jump trace plus the ground truth that produced it."""

    t: np.ndarray                       # accel time base, s
    mag: np.ndarray                     # |a| in g
    alt_t: np.ndarray                   # 1 Hz altitude time base
    alt_m: np.ndarray                   # altitude in m (baseline + trajectory + noise)
    h_true: float
    airtime_true_s: float
    t0: float                           # true airborne window start
    t1: float
    s_profile: str
    s_mean_true: float


def support_profile(kind: str, s: float, swing: float = 0.15):
    """Return ``phi(u) = s(u)`` on the normalised flight phase ``u`` in [0, 1].

    ``const`` is the textbook case. ``ramp_up`` is a wing that loads through the jump (light
    off the pop, heavy on the descent — the physically expected shape); ``ramp_down`` is the
    opposite and is included precisely because the closed form cannot tell them apart.
    """
    if kind == "const":
        return lambda u: np.full_like(np.asarray(u, float), s)
    if kind == "ramp_up":
        return lambda u: np.clip(s - swing + 2.0 * swing * np.asarray(u, float), 0.0, 1.0)
    if kind == "ramp_down":
        return lambda u: np.clip(s + swing - 2.0 * swing * np.asarray(u, float), 0.0, 1.0)
    if kind == "descent":
        # The physically interesting shape and the only one that separates the two corrected
        # estimators: nothing on the way up (wing sheeted out for the pop), 2s on the way
        # down (parachuting the landing), so the *mean* support is still s but it is all in
        # the wrong half. The closed form, which knows only the mean, reads such a jump low.
        return lambda u: np.where(np.asarray(u, float) < 0.5, 0.0, min(2.0 * s, 1.0))
    raise ValueError(f"unknown support profile {kind!r}")


def airtime_for(h_true: float, profile, n: int = 2001) -> tuple[float, float]:
    """Airtime that a given peak height implies under a given support profile.

    Physics, not a fit. With ``u = t/T``, ``z(u) = g T^2 (I2 u - J(u))``, so the peak height
    is ``g T^2 M`` with ``M = max_u (I2 u - J(u))`` depending only on the *shape* of the
    profile. Hence ``T = sqrt(h / (g M))``. Returns ``(T, M)``.
    """
    u = np.linspace(0.0, 1.0, n)
    phi = 1.0 - np.asarray(profile(u), float)
    J = _cumtrapz(phi, u)                       # inner integral
    JJ = _cumtrapz(J, u)                        # double integral
    I2 = float(JJ[-1])
    M = float(np.max(I2 * u - JJ))
    if M <= 0:
        raise ValueError("support profile leaves no ballistic phase (s >= 1 throughout)")
    return math.sqrt(h_true / (G * M)), M


def simulate_jump(h_true: float, s: float = 0.0, profile: str = "const",
                  noise: NoiseModel | None = None, rate_hz: float = 100.0,
                  context_s: float = 4.0, takeoff_peak_g: float = 3.2,
                  takeoff_span_s: float = 0.15, impact_peak_g: float = 5.0,
                  impact_span_s: float = 0.10, base_alt_m: float = 65.0,
                  alt_rate_hz: float | None = None, alt_phase: float | None = None,
                  swing: float = 0.15, rng: np.random.Generator | None = None) -> SynthJump:
    """Generate a wrist-accel + altitude trace for a jump of known height.

    The trace is built *from* the physics rather than fitted to it: pick the height and the
    support profile, derive the airtime the two imply, then write the specific force the
    wrist would read (``|a| = s(t) g`` airborne, ~1 g supported, half-sine spikes at the pop
    and the landing) and the altitude the barometer would see. Noise comes from
    `NoiseModel`, i.e. from the real corpus, so "does this survive the sensor" is answered
    with the sensor we actually have rather than an optimistic one.
    """
    rng = rng or np.random.default_rng(0)
    nm = noise or NoiseModel(accel_sigma_g=_ACCEL_SIGMA_DEFAULT, accel_rate_hz=rate_hz,
                             accel_rest_mean_g=1.0, alt_sigma_m=0.19, alt_quantum_m=0.2,
                             alt_rate_hz=1.0)
    prof = support_profile(profile, s, swing)
    T, _ = airtime_for(h_true, prof)

    t0 = context_s
    t1 = t0 + T
    total = t1 + context_s
    t = np.arange(0.0, total, 1.0 / rate_hz)

    u = np.clip((t - t0) / T, 0.0, 1.0)
    s_t = np.asarray(prof(u), float)
    airborne = (t >= t0) & (t <= t1)

    mag = np.full_like(t, nm.accel_rest_mean_g)
    mag[airborne] = s_t[airborne]

    pop = (t >= t0 - takeoff_span_s) & (t < t0)
    mag[pop] = nm.accel_rest_mean_g + (takeoff_peak_g - nm.accel_rest_mean_g) * np.sin(
        np.pi * (t[pop] - (t0 - takeoff_span_s)) / takeoff_span_s)
    land = (t > t1) & (t <= t1 + impact_span_s)
    mag[land] = nm.accel_rest_mean_g + (impact_peak_g - nm.accel_rest_mean_g) * np.sin(
        np.pi * (t[land] - t1) / impact_span_s)

    sigma = nm.accel_sigma_g if np.isfinite(nm.accel_sigma_g) else _ACCEL_SIGMA_DEFAULT
    mag = np.clip(mag + rng.normal(0.0, sigma, t.size), 0.0, None)

    # --- altitude: the true trajectory, sampled by a 1 Hz quantised barometer ---
    a_rate = alt_rate_hz if alt_rate_hz else (nm.alt_rate_hz or 1.0)
    phase = rng.uniform(0.0, 1.0 / a_rate) if alt_phase is None else alt_phase
    alt_t = np.arange(phase, total, 1.0 / a_rate)
    z = _trajectory(alt_t, t0, T, prof)
    a_sigma = nm.alt_sigma_m if np.isfinite(nm.alt_sigma_m) else 0.19
    alt_m = base_alt_m + z + rng.normal(0.0, a_sigma, alt_t.size)
    q = nm.alt_quantum_m if np.isfinite(nm.alt_quantum_m) and nm.alt_quantum_m > 0 else 0.2
    alt_m = np.round(alt_m / q) * q

    return SynthJump(t=t, mag=mag, alt_t=alt_t, alt_m=alt_m, h_true=h_true,
                     airtime_true_s=T, t0=t0, t1=t1, s_profile=profile,
                     s_mean_true=float(np.mean(prof(np.linspace(0, 1, 1001)))))


def _trajectory(t: np.ndarray, t0: float, T: float, profile) -> np.ndarray:
    """True vertical displacement of the simulated rider at arbitrary times (0 outside)."""
    grid = np.linspace(0.0, 1.0, 2001)
    phi = 1.0 - np.asarray(profile(grid), float)
    J = _cumtrapz(phi, grid)
    JJ = _cumtrapz(J, grid)
    I2 = float(JJ[-1])
    z_grid = G * T * T * (I2 * grid - JJ)
    u = (np.asarray(t, float) - t0) / T
    out = np.interp(u, grid, z_grid, left=0.0, right=0.0)
    out[(u < 0.0) | (u > 1.0)] = 0.0
    return out


# --------------------------------------------------------------------------------------
# validation grid
# --------------------------------------------------------------------------------------

DEFAULT_HEIGHTS = (0.5, 1.0, 2.0, 3.0, 5.0)
DEFAULT_SUPPORTS = (0.0, 0.2, 0.4, 0.6, 0.7)


def validation_grid(heights=DEFAULT_HEIGHTS, supports=DEFAULT_SUPPORTS,
                    profiles=("const", "ramp_up", "ramp_down"), reps: int = 40,
                    noise: NoiseModel | None = None, rate_hz: float = 100.0,
                    config: JumpConfig | None = None, seed: int = 20260807,
                    noise_free: bool = False) -> list[dict]:
    """Run detect + estimate over the whole (height x support x profile) grid.

    One row per cell, carrying the bias and spread of all three estimators. `noise_free`
    zeroes the sensor noise so the pure discretisation/algorithm error can be separated from
    the sensor's contribution.
    """
    cfg = config or JumpConfig()
    nm = noise or NoiseModel(accel_sigma_g=_ACCEL_SIGMA_DEFAULT, accel_rate_hz=rate_hz,
                             accel_rest_mean_g=1.0, alt_sigma_m=0.19, alt_quantum_m=0.2,
                             alt_rate_hz=1.0)
    if noise_free:
        nm = NoiseModel(accel_sigma_g=0.0, accel_rate_hz=nm.accel_rate_hz,
                        accel_rest_mean_g=1.0, alt_sigma_m=0.0,
                        alt_quantum_m=nm.alt_quantum_m, alt_rate_hz=nm.alt_rate_hz)
    rng = np.random.default_rng(seed)
    rows: list[dict] = []
    for prof in profiles:
        for h in heights:
            for s in supports:
                est = {"integrated": [], "closed_form": [], "naive": []}
                airtimes, s_means, sigmas, baro_ok, baro_h, detected = [], [], [], 0, [], 0
                truth = None
                for _ in range(reps):
                    sj = simulate_jump(h, s, prof, noise=nm, rate_hz=rate_hz, rng=rng)
                    truth = sj
                    res = detect_jumps_from_arrays(sj.t, sj.mag, cfg,
                                                   alt_t=sj.alt_t, alt_m=sj.alt_m)
                    if len(res.jumps) != 1:
                        continue
                    detected += 1
                    j = res.jumps[0]
                    est["integrated"].append(j.height.integrated_m)
                    est["closed_form"].append(j.height.closed_form_m)
                    est["naive"].append(j.height.naive_m)
                    airtimes.append(j.height.airtime_s)
                    s_means.append(j.height.s_mean)
                    sigmas.append(j.height.sigma_m)
                    if j.baro.status == "fit":
                        baro_ok += 1
                        baro_h.append(j.baro.height_m)
                row = {"profile": prof, "h_true": h, "s": s, "reps": reps,
                       "detected": detected,
                       "detect_rate": detected / reps if reps else 0.0,
                       "airtime_true_s": truth.airtime_true_s if truth else float("nan"),
                       "s_mean_true": truth.s_mean_true if truth else float("nan"),
                       "airtime_s": _mean(airtimes), "s_mean": _mean(s_means),
                       "sigma_m": _mean(sigmas),
                       "baro_fit_rate": baro_ok / detected if detected else 0.0,
                       "baro_mean_m": _mean(baro_h), "baro_sd_m": _sd(baro_h)}
                for name, vals in est.items():
                    arr = np.asarray(vals, float)
                    row[f"{name}_mean"] = _mean(arr)
                    row[f"{name}_bias"] = _mean(arr - h) if arr.size else float("nan")
                    row[f"{name}_sd"] = _sd(arr)
                    row[f"{name}_ratio"] = _mean(arr / h) if arr.size and h else float("nan")
                rows.append(row)
    return rows


def _mean(v) -> float:
    a = np.asarray(v, float)
    return float(a.mean()) if a.size else float("nan")


def _sd(v) -> float:
    a = np.asarray(v, float)
    return float(a.std(ddof=1)) if a.size > 1 else 0.0


# --------------------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------------------

def _median_smooth(x: np.ndarray, width: int) -> np.ndarray:
    """Centred running median, edge-padded (keeps length, preserves steps, kills spikes)."""
    x = np.asarray(x, float)
    if width <= 1:
        return x
    width |= 1                                   # odd, so the window is symmetric
    pad = width // 2
    padded = np.pad(x, (pad, pad), mode="edge")
    view = np.lib.stride_tricks.sliding_window_view(padded, width)
    return np.median(view, axis=-1)


def _bridged_runs(t: np.ndarray, sm: np.ndarray, cfg: JumpConfig) -> list[tuple[int, int]]:
    """Low-g runs, with short noise excursions bridged rather than treated as landings.

    Hysteresis expressed as a merge rule: two sub-threshold runs less than `jumpBridge`
    apart, with nothing between them above `jumpBridgeMaxG`, are one airborne window. Both
    edges therefore stay defined by the single `jumpAirborneMaxG` crossing, which keeps the
    airtime measurement consistent — a two-level hysteresis would time the two edges against
    two different thresholds. This matters most exactly where the physics is hardest: at
    ``s = 0.7`` the signal sits 0.05 g below the threshold against ~0.06 g of filtered noise,
    so without bridging a single real window shatters into a dozen sub-minimum fragments.
    """
    runs = _runs(sm < cfg.airborne_max_g)
    if not runs:
        return []
    merged = [runs[0]]
    for a, b in runs[1:]:
        pa, pb = merged[-1]
        between = sm[pb + 1:a]
        if (t[a] - t[pb] <= cfg.bridge_s
                and (between.size == 0 or float(between.max()) <= cfg.bridge_max_g)):
            merged[-1] = (pa, b)
        else:
            merged.append((a, b))
    return merged


def _runs(mask: np.ndarray) -> list[tuple[int, int]]:
    """Inclusive index pairs of the contiguous True runs of `mask`."""
    m = np.asarray(mask, bool)
    if not m.any():
        return []
    d = np.diff(m.astype(np.int8))
    starts = list(np.flatnonzero(d == 1) + 1)
    ends = list(np.flatnonzero(d == -1))
    if m[0]:
        starts.insert(0, 0)
    if m[-1]:
        ends.append(m.size - 1)
    return list(zip(starts, ends))


def _crossing(t: np.ndarray, y: np.ndarray, i_out: int, i_in: int, level: float) -> float:
    """Linearly interpolated time at which `y` crosses `level` between two samples."""
    if i_out < 0 or i_in < 0 or i_out >= t.size or i_in >= t.size:
        return float(t[max(0, min(i_in, t.size - 1))])
    y0, y1 = float(y[i_out]), float(y[i_in])
    if y0 == y1:
        return float(t[i_in])
    frac = (y0 - level) / (y0 - y1)
    frac = min(max(frac, 0.0), 1.0)
    return float(t[i_out] + frac * (t[i_in] - t[i_out]))


def _peak_in(t: np.ndarray, y: np.ndarray, a: float, b: float) -> float:
    lo = int(np.searchsorted(t, a, "left"))
    hi = int(np.searchsorted(t, b, "right"))
    return float(y[lo:hi].max()) if hi > lo else 0.0
