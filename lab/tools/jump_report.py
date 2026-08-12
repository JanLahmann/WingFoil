"""Reproduce every number in docs/algorithms.md "Jumps (theoretical, uncalibrated)".

    uv run python tools/jump_report.py            # noise model + grids + corpus sweep
    uv run python tools/jump_report.py --reps 200 # tighter error bars, slower
    uv run python tools/jump_report.py --corpus   # corpus sweep only

Everything printed is simulation-validated. There is no real jump in the corpus, so there is
no calibration and nothing here is a measurement of anything Jan has done.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wingfoil_lab import jump as J                                   # noqa: E402
from wingfoil_lab.filters import clean                               # noqa: E402
from wingfoil_lab.flight import segment_flights                      # noqa: E402
from wingfoil_lab.parse import parse_fit                             # noqa: E402

FIXTURES = ROOT.parent / "fixtures"
CIQ = FIXTURES / "sessions" / "ciq" / "2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"


# --------------------------------------------------------------------------------------

def noise_model_from_corpus(path: Path = CIQ) -> J.NoiseModel:
    """Measure the sensor noise the synthetic generator will use, from the real fixture."""
    track = parse_fit(path)
    spans = [(f.start_t, f.end_t) for f in segment_flights(clean(track)).flights]
    nm = J.measure_noise_model(track, flight_spans=spans)
    if nm is None:
        raise SystemExit(f"no accel stream in {path}")
    nm.source = path.name
    return nm


def print_noise_model(nm: J.NoiseModel) -> None:
    print("\n## Noise model (measured from the real corpus)\n")
    print(f"| source | `{nm.source}` |")
    print("|---|---|")
    print(f"| accel rate | {nm.accel_rate_hz:g} Hz |")
    print(f"| accel sigma (quiet on-foil, per sample) | **{nm.accel_sigma_g:.3f} g** "
          f"({nm.n_accel_samples} 1 s blocks) |")
    print(f"| accel mean in those blocks | {nm.accel_rest_mean_g:.3f} g |")
    print(f"| altitude rate | {nm.alt_rate_hz:g} Hz |")
    print(f"| altitude quantum | {nm.alt_quantum_m:.2f} m |")
    print(f"| altitude sigma (detrended, at rest) | **{nm.alt_sigma_m:.3f} m** "
          f"({nm.n_alt_samples} samples) |")


# --------------------------------------------------------------------------------------

def grid_table(rows: list[dict], profile: str, title: str) -> None:
    sel = [r for r in rows if r["profile"] == profile]
    print(f"\n{title}\n")
    print("| h_true (m) | s | airtime (s) | det | integrated (m) | closed-form (m) "
          "| naive (m) | naive / true |")
    print("|---|---|---|---|---|---|---|---|")
    for r in sel:
        if not r["detected"]:
            print(f"| {r['h_true']:g} | {r['s']:g} | {r['airtime_true_s']:.2f} | "
                  f"**0 %** | — | — | — | — |")
            continue
        print(f"| {r['h_true']:g} | {r['s']:g} | {r['airtime_true_s']:.2f} | "
              f"{100 * r['detect_rate']:.0f} % | "
              f"{r['integrated_mean']:.2f} ± {r['integrated_sd']:.2f} "
              f"({100 * r['integrated_bias'] / r['h_true']:+.1f} %) | "
              f"{r['closed_form_mean']:.2f} ± {r['closed_form_sd']:.2f} "
              f"({100 * r['closed_form_bias'] / r['h_true']:+.1f} %) | "
              f"{r['naive_mean']:.2f} ± {r['naive_sd']:.2f} | "
              f"**{r['naive_ratio']:.2f}x** |")


def overestimation_table(rows: list[dict]) -> None:
    print("\n## Headline — how far the naive formula overshoots, by support fraction\n")
    print("| s (support fraction) | 1/(1-s) predicted | naive / true measured "
          "| integrated / true | closed-form / true |")
    print("|---|---|---|---|---|")
    for s in J.DEFAULT_SUPPORTS:
        sel = [r for r in rows if r["s"] == s and r["profile"] == "const" and r["detected"]]
        if not sel:
            print(f"| {s:g} | {1 / (1 - s):.2f}x | (not detected) | — | — |")
            continue
        nr = np.mean([r["naive_ratio"] for r in sel])
        ir = np.mean([r["integrated_ratio"] for r in sel])
        cr = np.mean([r["closed_form_ratio"] for r in sel])
        print(f"| {s:g} | {1 / (1 - s):.2f}x | **{nr:.2f}x** | {ir:.3f} | {cr:.3f} |")


def varying_table(rows: list[dict]) -> None:
    print("\n## Time-varying support (symmetric ramps, ±0.15 about s_mean)\n")
    print("| profile | s_mean | integrated err | closed-form err | naive / true | det |")
    print("|---|---|---|---|---|---|")
    for prof in ("ramp_up", "ramp_down"):
        for s in J.DEFAULT_SUPPORTS:
            sel = [r for r in rows if r["profile"] == prof and r["s"] == s and r["detected"]]
            if not sel:
                continue
            ib = np.mean([100 * r["integrated_bias"] / r["h_true"] for r in sel])
            cb = np.mean([100 * r["closed_form_bias"] / r["h_true"] for r in sel])
            nr = np.mean([r["naive_ratio"] for r in sel])
            dr = np.mean([r["detect_rate"] for r in sel])
            print(f"| `{prof}` | {s:g} | {ib:+.1f} % | {cb:+.1f} % | {nr:.2f}x "
                  f"| {100 * dr:.0f} % |")


def descent_table(nm: J.NoiseModel, reps: int, rate_hz: float) -> None:
    """The asymmetric case that separates the integrated estimator from the closed form."""
    rows = J.validation_grid(heights=(1.0, 2.0, 3.0), supports=(0.1, 0.2, 0.3, 0.35),
                             profiles=("descent",), reps=reps, noise=nm, rate_hz=rate_hz)
    print("\n## Descent-only support — where the closed form breaks and the integral does not\n")
    print("| s_mean | s during descent | integrated err | closed-form err | naive / true |")
    print("|---|---|---|---|---|")
    for s in (0.1, 0.2, 0.3, 0.35):
        sel = [r for r in rows if r["s"] == s and r["detected"]]
        if not sel:
            continue
        ib = np.mean([100 * r["integrated_bias"] / r["h_true"] for r in sel])
        cb = np.mean([100 * r["closed_form_bias"] / r["h_true"] for r in sel])
        nr = np.mean([r["naive_ratio"] for r in sel])
        print(f"| {s:g} | {min(2 * s, 1.0):g} | **{ib:+.1f} %** | {cb:+.1f} % | {nr:.2f}x |")


def ceiling_table(nm: J.NoiseModel, reps: int) -> None:
    print("\n## Detection ceiling — `jumpAirborneMaxG` is a hard cap on visible support\n")
    print("| jumpAirborneMaxG | s=0.0 | s=0.2 | s=0.4 | s=0.6 | s=0.7 |")
    print("|---|---|---|---|---|---|")
    for thr in (0.6, 0.75, 0.9):
        cfg = J.JumpConfig(airborne_max_g=thr, bridge_max_g=max(0.95, thr + 0.15))
        cells = []
        for s in J.DEFAULT_SUPPORTS:
            rows = J.validation_grid(heights=(1.0, 2.0), supports=(s,), profiles=("const",),
                                     reps=max(reps // 4, 8), noise=nm, config=cfg)
            cells.append(f"{100 * np.mean([r['detect_rate'] for r in rows]):.0f} %")
        print(f"| {thr:g} g | " + " | ".join(cells) + " |")


def baro_table(rows: list[dict]) -> None:
    print("\n## Baro secondary (1 Hz altitude) — usually cannot answer\n")
    print("| h_true (m) | airtime (s) | fits attempted | fit rate | fitted height (m) |")
    print("|---|---|---|---|---|")
    for h in J.DEFAULT_HEIGHTS:
        sel = [r for r in rows if r["h_true"] == h and r["profile"] == "const"
               and r["detected"]]
        if not sel:
            continue
        rate = np.mean([r["baro_fit_rate"] for r in sel])
        fits = [r for r in sel if r["baro_fit_rate"] > 0 and np.isfinite(r["baro_mean_m"])]
        val = (f"{np.mean([r['baro_mean_m'] for r in fits]):.2f} "
               f"± {np.mean([r['baro_sd_m'] for r in fits]):.2f}" if fits else "—")
        at = np.mean([r["airtime_true_s"] for r in sel])
        print(f"| {h:g} | {at:.2f} | {sum(r['detected'] for r in sel)} | "
              f"{100 * rate:.0f} % | {val} |")


def uncertainty_note(nm: J.NoiseModel) -> None:
    print("\n## Per-jump uncertainty budget (h_true = 1 m, s = 0.3, 100 Hz)\n")
    sj = J.simulate_jump(1.0, 0.3, "const", noise=nm, rate_hz=100.0,
                         rng=np.random.default_rng(1))
    res = J.detect_jumps_from_arrays(sj.t, sj.mag, alt_t=sj.alt_t, alt_m=sj.alt_m)
    if not res.jumps:
        print("(not detected)")
        return
    e = res.jumps[0].height
    print("| term | sigma (m) | share |")
    print("|---|---|---|")
    tot = e.sigma_m ** 2
    for name, v in (("accel noise", e.sigma_noise_m), ("support profile ±0.1", e.sigma_profile_m),
                    ("timing ±1 sample", e.sigma_timing_m)):
        print(f"| {name} | {v:.3f} | {100 * v * v / tot:.0f} % |")
    print(f"| **combined** | **{e.sigma_m:.3f}** | on h = {e.integrated_m:.2f} m |")


# --------------------------------------------------------------------------------------

def corpus_sweep(cfg: J.JumpConfig | None = None) -> list[dict]:
    """Run detection over every fixture. Nothing found is called a jump."""
    out: list[dict] = []
    fits = sorted(FIXTURES.rglob("*.fit"))
    for p in fits:
        track = parse_fit(p)
        res = J.detect_jumps(track, cfg)
        if res is None:
            out.append({"file": p.name, "accel": False, "note": "no accel stream — skipped"})
            continue
        out.append({"file": p.name, "accel": True, "rate": res.sample_rate_hz,
                    "samples": res.n_samples, "jumps": res.jumps,
                    "candidates": res.candidates})
    return out


def print_corpus(sweep: list[dict]) -> None:
    print("\n## Corpus sweep — every fixture, detector at the defaults above\n")
    print("**Nothing found here is a jump.** Jan does not jump, so there is nothing to find;")
    print("every hit is reported as a *candidate* with its timestamp, for eyeballing only.\n")
    print("| fixture | accel samples | rate | gate-passing candidates | gated-out candidates |")
    print("|---|---|---|---|---|")
    for r in sweep:
        if not r["accel"]:
            print(f"| `{r['file']}` | — | — | — | *{r['note']}* |")
            continue
        print(f"| `{r['file']}` | {r['samples']:,} | {r['rate']:g} Hz | "
              f"**{len(r['jumps'])}** | {len(r['candidates'])} |")
    for r in sweep:
        if not r["accel"] or not (r["jumps"] or r["candidates"]):
            continue
        print(f"\n`{r['file']}` — candidate detail:\n")
        for j in r["jumps"]:
            print(f"- candidate (**passed every gate**) t = {j.t_start:.1f}–{j.t_end:.1f} s: "
                  f"airtime {j.height.airtime_s:.2f} s, s_mean {j.height.s_mean:.2f}, "
                  f"pop {j.takeoff_g:.1f} g, impact {j.impact_g:.1f} g -> "
                  f"integrated **{j.height.integrated_m:.2f} ± {j.height.sigma_m:.2f} m** "
                  f"(naive would say {j.height.naive_m:.2f} m)")
        by_reason: dict[str, list] = {}
        for c in r["candidates"]:
            by_reason.setdefault(c.reason, []).append(c)
        for reason, cs in sorted(by_reason.items()):
            heads = ", ".join(f"{c.t_start:.1f} s ({c.airtime_s:.2f} s, min {c.min_g:.2f} g)"
                              for c in cs[:8])
            more = f" … +{len(cs) - 8} more" if len(cs) > 8 else ""
            print(f"- candidate x{len(cs)} — gated out by `{reason}`: {heads}{more}")


def threshold_sweep_corpus() -> None:
    """What `jumpAirborneMaxG` costs on real water, where every hit is a false positive."""
    track = parse_fit(CIQ)
    print("\n## `jumpAirborneMaxG` against the real session (every hit is a false positive)\n")
    print("| jumpAirborneMaxG | gate-passing | gated-out | dominant gate-out reason |")
    print("|---|---|---|---|")
    for thr in (0.6, 0.75, 0.9):
        cfg = J.JumpConfig(airborne_max_g=thr, bridge_max_g=max(0.95, thr + 0.15))
        res = J.detect_jumps(track, cfg)
        reasons: dict[str, int] = {}
        for c in res.candidates:
            reasons[c.reason] = reasons.get(c.reason, 0) + 1
        top = max(reasons.items(), key=lambda kv: kv[1], default=("—", 0))
        print(f"| {thr:g} g | {len(res.jumps)} | {len(res.candidates)} | "
              f"`{top[0]}` x{top[1]} |")


# --------------------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--reps", type=int, default=60, help="Monte-Carlo reps per grid cell")
    ap.add_argument("--corpus", action="store_true", help="corpus sweep only")
    ap.add_argument("--rate", type=float, default=100.0, help="synthetic accel rate (Hz)")
    args = ap.parse_args()

    print("# Jump estimator report — THEORETICAL, UNCALIBRATED")
    print("\nNo real jump exists in the corpus. Every accuracy figure below is measured")
    print("against the synthetic generator in `lab/src/wingfoil_lab/jump.py`, i.e. against")
    print("the physics we assume, never against a measured height.")

    if args.corpus:
        print_corpus(corpus_sweep())
        return

    nm = noise_model_from_corpus()
    print_noise_model(nm)

    clean_rows = J.validation_grid(reps=1, noise=nm, rate_hz=args.rate, noise_free=True)
    grid_table(clean_rows, "const",
               "## Noise-free grid — algorithm error alone (constant support)")

    rows = J.validation_grid(reps=args.reps, noise=nm, rate_hz=args.rate)
    grid_table(rows, "const",
               f"## Full grid with measured sensor noise ({args.reps} reps/cell, "
               f"{args.rate:g} Hz, constant support)")
    overestimation_table(rows)
    varying_table(rows)
    descent_table(nm, args.reps, args.rate)
    uncertainty_note(nm)
    ceiling_table(nm, args.reps)
    baro_table(rows)

    rows25 = J.validation_grid(reps=args.reps, noise=nm, rate_hz=25.0, profiles=("const",))
    grid_table(rows25, "const", "## Same grid at 25 Hz — what a slower stream costs")

    threshold_sweep_corpus()
    print_corpus(corpus_sweep())


if __name__ == "__main__":
    main()
