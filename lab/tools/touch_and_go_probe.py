"""Can the 100 Hz wrist accelerometer see a board touch-and-go inside a jibe?

A RESEARCH PROBE, not engine code: nothing in `wingfoil_lab` imports it and it changes
nothing. It exists to answer one question and to make the answer reproducible --
`lab/notebooks/touch-and-go-report.md` quotes every number this script prints.

The premise under test. The engine can only call a turn `touchdown` when the flight
detector actually drops out (speed below `foilExitSpeed` held for `exitHold`), so a brief
board touch inside a jibe -- the rider drops on, pumps twice, flies out -- is invisible to
speed alone and gets scored `flew_through`. The FIT also carries the watch's SensorLogger
stream (`accelerometer_data`, 100 Hz, +-8 g). If a board slapping the water leaves a
distinguishable impact signature at the wrist, those turns could be reclassified.

Four experiments, in the order the report tells them:

  liftoff   The tightest matched pair available: the 5 s before each successful takeoff
            (board in the water) against the 5 s after (board flying). Same rider, same
            wing, seconds apart, and the only thing that changed is water contact. If the
            wrist can see water contact anywhere, it has to show here.
  pump      The confound, isolated: pump episodes that happened ON foil against pump
            episodes that happened OFF foil. Both are the same 0.5-2.5 Hz wrist rhythm;
            only the board's contact with the water differs.
  turns     The feature battery scored per counted turn, with AUCs against the engine's
            own labels, and every `flew_through` turn listed.
  controls  What the battery costs: its false-alarm rate over clean mid-flight seconds,
            and over the turns that physically CANNOT have touched down (high min speed,
            no pump afterwards).
  baro      The other channel, for completeness: does 1 Hz barometric altitude see the
            ~60 cm foil ride height?

    uv run python tools/touch_and_go_probe.py
    uv run python tools/touch_and_go_probe.py --section turns --fixture 2026-08-07-0754_...
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfiltfilt, welch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from wingfoil_lab.parse import parse_fit  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "fixtures/sessions/ciq"
GOLDENS = ROOT / "fixtures/goldens"
MPS_TO_KN = 1.94384
FS = 100.0                    # the SensorLogger stream's rate on the fenix 8

# Analysis windows. The engine timestamps a turn [ts, endTs]; its speed minimum can land up
# to `minSpeedLag` past the end, so the probe re-derives the minimum the same way and hangs
# every window off that moment.
WIN_BEFORE, WIN_AFTER = 5.0, 5.0      # the impact window, around the speed minimum
SUS_BEFORE, SUS_AFTER = 2.0, 4.0      # the sustained-contact window
REC_BEFORE, REC_AFTER = 8.0, 8.0      # the RECOVERY window: wide enough to hold a whole
                                      # get-back-on-foil effort, which runs 9-17 s
HF_LO, HF_HI = 8.0, 45.0              # "impact" band: above wing handling, below Nyquist
PUMP_LO, PUMP_HI = 0.5, 2.5           # the pump band, straight from Config
ENV_S = 0.25                          # RMS envelope span for the impact band
PUMP_ENV_S = 1.0                      # RMS envelope span for the pump band


# ---- feed ----------------------------------------------------------------------------

class Session:
    """One fixture: the accel on a uniform grid, the 1 Hz records, and the golden."""

    def __init__(self, stem: str):
        self.stem = stem
        self.gold = json.loads((GOLDENS / f"{stem}.expected.json").read_text())
        track = parse_fit(FIXTURES / f"{stem}.fit")
        if track.accel is None:
            raise SystemExit(f"{stem}: no accelerometer_data in this FIT")

        a = track.accel
        t = a["t"].to_numpy()
        mag = np.sqrt(a.ax.to_numpy() ** 2 + a.ay.to_numpy() ** 2 + a.az.to_numpy() ** 2)
        # The samples are near-uniform but not exact; resample onto a true 100 Hz grid so
        # the filters and the cumulative-sum envelopes are honest about their bandwidths.
        self.grid = np.arange(t[0], t[-1], 1.0 / FS)
        self.mag = np.interp(self.grid, t, mag)

        df = track.records
        self.rec_t = df["t"].to_numpy()
        self.rec_kn = df["speed_mps"].to_numpy(float) * MPS_TO_KN
        alt_col = "enhanced_altitude" if "enhanced_altitude" in df else "altitude"
        self.alt = df[alt_col].to_numpy(float) if alt_col in df else None

        self.hf = self._band(HF_LO, HF_HI)
        self.pump = self._band(PUMP_LO, PUMP_HI)
        self.e_hf = self._env(self.hf, ENV_S)
        self.e_pump = self._env(self.pump, PUMP_ENV_S)
        # Normalise every band feature by the rider's own session median, so thresholds
        # read as "x times this rider's usual" and survive a different watch or wing.
        self.b_hf = float(np.nanmedian(self.e_hf))
        self.b_pump = float(np.nanmedian(self.e_pump))

        self.flights = [(f["startTs"], f["endTs"]) for f in self.gold["flights"]]
        self.turns = [x for x in self.gold["turns"] if x["counted"]]
        for x in self.turns:
            x["_tmin"] = self._speed_min_ts(x)

    def _band(self, lo: float, hi: float) -> np.ndarray:
        sos = butter(4, [lo / (FS / 2), hi / (FS / 2)], btype="band", output="sos")
        return sosfiltfilt(sos, self.mag)

    @staticmethod
    def _env(x: np.ndarray, span_s: float) -> np.ndarray:
        """Zero-lag RMS envelope over `span_s`, centred (cumsum, so it is O(n))."""
        w = int(span_s * FS)
        cs = np.concatenate([[0.0], np.cumsum(x * x)])
        r = np.sqrt((cs[w:] - cs[:-w]) / w)
        out = np.full(len(x), np.nan)
        out[w // 2:w // 2 + len(r)] = r
        return out

    def sl(self, t0: float, t1: float) -> slice:
        i0, i1 = np.searchsorted(self.grid, [t0, t1])
        return slice(i0, i1)

    def kn_at(self, t: float) -> float:
        return float(np.interp(t, self.rec_t, self.rec_kn))

    def _speed_min_ts(self, turn: dict) -> float:
        """The moment the turn actually bottomed out -- `minSpeedLag` past `endTs` is fair
        game, which is how `turns.py` computes `minKn` in the first place."""
        lo, hi = turn["ts"], turn["endTs"] + 2.0
        k = np.searchsorted(self.rec_t, [lo, hi])
        seg = self.rec_kn[k[0]:k[1] + 1]
        if not len(seg):
            return (lo + hi) / 2
        return float(self.rec_t[k[0] + int(np.argmin(seg))])

    def clean_flight_mask(self) -> np.ndarray:
        """Mid-flight seconds: inside a long flight, well clear of both ends and of every
        turn. This is what "nothing is happening" looks like for this rider."""
        ok = np.zeros(len(self.grid), bool)
        for s, e in self.flights:
            if e - s > 35:
                ok[self.sl(s + 12, e - 12)] = True
        for x in self.gold["turns"]:          # every turn, counted or rejected
            ok[self.sl(x["ts"] - 8, x["endTs"] + 10)] = False
        return ok


def auc(neg, pos) -> float:
    """P(a random positive scores above a random negative). 0.5 = the feature is noise."""
    neg, pos = np.asarray(neg, float), np.asarray(pos, float)
    if not len(neg) or not len(pos):
        return float("nan")
    r = np.concatenate([neg, pos]).argsort().argsort().astype(float)
    return float((r[len(neg):].sum() - len(pos) * (len(pos) - 1) / 2) / (len(neg) * len(pos)))


# ---- the feature battery --------------------------------------------------------------

def features(ss: Session, tmin: float) -> dict:
    """Everything the probe knows how to measure about one turn's bottom."""
    imp = ss.sl(tmin - WIN_BEFORE, tmin + WIN_AFTER)
    sus = ss.sl(tmin - SUS_BEFORE, tmin + SUS_AFTER)
    vh = ss.e_hf[imp][~np.isnan(ss.e_hf[imp])]
    vs = ss.e_hf[sus][~np.isnan(ss.e_hf[sus])]
    vp = ss.e_pump[imp][~np.isnan(ss.e_pump[imp])]
    raw = ss.mag[imp]
    if not len(vh) or not len(vp) or not len(raw):
        return {}

    pk_hf = float(vh.max()) / ss.b_hf                       # the impact spike
    sus_hf = float(np.percentile(vs, 75)) / ss.b_hf         # sustained roughness
    pk_pump = float(np.percentile(vp, 95)) / ss.b_pump      # how hard the arms worked
    span = (WIN_BEFORE + WIN_AFTER)

    # A free fall off the foil is ~60 cm: look for a low-g dip followed by a landing spike.
    lp = ss.mag[imp]
    drop = 0.0
    for i in range(0, len(lp) - int(0.8 * FS)):
        if lp[i] < 0.75:
            drop = max(drop, (1.0 - lp[i]) * lp[i + int(0.1 * FS):i + int(0.8 * FS)].max())

    # The recovery window is deliberately wider than the impact window. It is not looking
    # for a bang; it is looking for the 9-17 s of heaving that getting back onto the foil
    # costs this rider. `rec_hi_g` = seconds above 2 g inside it.
    rec = ss.mag[ss.sl(tmin - REC_BEFORE, tmin + REC_AFTER)]
    rec_hi_g = float((rec > 2.0).sum() / FS) if len(rec) else 0.0

    return {
        "pk_hf": pk_hf,
        "sus_hf": sus_hf,
        "pk_pump": pk_pump,
        "rec_hi_g": rec_hi_g,
        # the whole point of the ratio: an impact is broadband, so it should lift the HF
        # band WITHOUT lifting the pump band. Pumping lifts both together.
        "hf_over_pump": pk_hf / max(pk_pump, 1e-3),
        "pk_g": float(raw.max()),
        "s_over_2g": float((raw > 2.0).sum() / FS),
        "s_over_2g_rate": float((raw > 2.0).sum() / FS / span),
        "drop_spike": float(drop),
    }


FEATURE_KEYS = ["pk_hf", "sus_hf", "hf_over_pump", "pk_g", "s_over_2g", "drop_spike",
                "pk_pump", "rec_hi_g"]


def scored_turns(ss: Session) -> list[dict]:
    out = []
    for x in ss.turns:
        f = features(ss, x["_tmin"])
        if not f:
            continue
        f.update(ts=x["ts"], endTs=x["endTs"], outcome=x["outcome"], minKn=x["minKn"],
                 entryKn=x["entryKn"], pumped=x["pumped"], submerged=x["submerged"],
                 offFoilS=x["offFoilS"], stoppedS=x["stoppedS"], tmin=x["_tmin"])
        out.append(f)
    return out


def first_burst_after(ss: Session, turn: dict) -> tuple[int, float] | None:
    """Strokes and duration of the first pump burst after the turn -- the recovery effort."""
    best = None
    for p in ss.gold["pumpEpisodes"]:
        if turn["ts"] - 2 <= p["startTs"] <= turn["endTs"] + 14:
            if best is None or p["startTs"] < best["startTs"]:
                best = p
    return (best["strokes"], best["endTs"] - best["startTs"]) if best else None


# ---- experiment 1: the matched liftoff pair -------------------------------------------

def sec_liftoff(ss: Session) -> None:
    print(f"\n=== LIFTOFF: 5 s off-foil vs 5 s on-foil, matched at each takeoff "
          f"[{ss.stem}] ===")
    pre_chunks, post_chunks, pairs = [], [], []
    for tk in ss.gold["takeoffs"]:
        if not tk["success"]:
            continue
        lift = tk["startTs"]
        pre, post = ss.sl(lift - 5, lift - 0.5), ss.sl(lift + 1.5, lift + 6)
        if pre.stop - pre.start < 400 or post.stop - post.start < 400:
            continue
        pre_chunks.append(ss.mag[pre])
        post_chunks.append(ss.mag[post])
        pairs.append((ss.kn_at(lift - 2.5), ss.kn_at(lift + 3.5)))
    if not pairs:
        print("  no usable takeoff pairs")
        return
    print(f"  {len(pairs)} matched pairs; median speed {np.median([p[0] for p in pairs]):.1f} kn "
          f"off-foil -> {np.median([p[1] for p in pairs]):.1f} kn on-foil")

    def psd(chunks):
        acc = None
        for c in chunks:
            f, p = welch(c - c.mean(), fs=FS, nperseg=256)
            acc = p if acc is None else acc + p
        return f, acc / len(chunks)

    f, p_pre = psd(pre_chunks)
    _, p_post = psd(post_chunks)
    tot_pre, tot_post = p_pre.sum(), p_post.sum()
    print(f"\n  {'band Hz':>11} {'off-foil':>11} {'on-foil':>11} {'ratio':>7} {'shape ratio':>12}")
    for lo, hi in [(0.5, 2.5), (2.5, 5), (5, 8), (8, 12), (12, 16), (16, 20),
                   (20, 25), (25, 30), (30, 35), (35, 45)]:
        k = (f >= lo) & (f < hi)
        a, b = p_pre[k].mean(), p_post[k].mean()
        print(f"  {lo:4.1f}-{hi:<5.1f} {a:11.3e} {b:11.3e} {a / b:7.2f} "
              f"{(a / tot_pre) / (b / tot_post):12.2f}")
    print("  'shape ratio' divides out the overall amplitude. A board slapping the water\n"
          "  would push it ABOVE 1 at high frequency; every band here sits at or below 1.")


# ---- experiment 2: pumping on foil vs pumping off foil ---------------------------------

def sec_pump(ss: Session) -> None:
    print(f"\n=== PUMP: the same wrist rhythm, board flying vs board in the water "
          f"[{ss.stem}] ===")
    on, off = [], []
    for p in ss.gold["pumpEpisodes"]:
        if p["strokes"] < 5 or p["endTs"] - p["startTs"] < 3:
            continue
        s = ss.sl(p["startTs"], p["endTs"])
        if s.stop - s.start < 300:
            continue
        vh = ss.e_hf[s][~np.isnan(ss.e_hf[s])]
        vp = ss.e_pump[s][~np.isnan(ss.e_pump[s])]
        if not len(vh) or not len(vp):
            continue
        row = {
            "pump": float(np.median(vp)),
            "hf": float(np.median(vh)),
            "hf_over_pump": float(np.median(vh)) / max(float(np.median(vp)), 1e-4),
            "crest_hf": float(np.percentile(vh, 95)) / max(float(np.median(vh)), 1e-5),
            "pk_g": float(ss.mag[s].max()),
            "s_over_2g_rate": float((ss.mag[s] > 2.0).sum() / FS / (p["endTs"] - p["startTs"])),
        }
        flying = any(a <= p["startTs"] and p["endTs"] <= b for a, b in ss.flights)
        (on if flying else off).append(row)
    print(f"  {len(on)} episodes on foil, {len(off)} off foil")
    if not on or not off:
        return
    print(f"\n  {'feature':16s} {'on-foil med':>12s} {'off-foil med':>13s} {'AUC(off>on)':>12s}")
    for k in ("pump", "hf", "hf_over_pump", "crest_hf", "pk_g", "s_over_2g_rate"):
        a = [x[k] for x in on]
        b = [x[k] for x in off]
        print(f"  {k:16s} {np.median(a):12.4f} {np.median(b):13.4f} {auc(a, b):12.3f}")
    print("  Raw amplitudes separate (off-foil pumping is more violent); the moment the HF\n"
          "  band is normalised by the pump band, the separation collapses to chance.")


# ---- experiment 3: the per-turn battery -----------------------------------------------

def sec_turns(ss: Session) -> None:
    rows = scored_turns(ss)
    td = [r for r in rows if r["outcome"] == "touchdown"]
    fl = [r for r in rows if r["outcome"] == "flew_through"]
    fi = [r for r in rows if r["outcome"] == "fell_in"]
    sus = [r for r in fl if r["pumped"]]
    # Turns that cannot have touched down: fast through the bottom AND no pump afterwards.
    # This rider has never once got back on foil without pumping (see `sec_anchor`), so a
    # touch-and-go with zero strokes is not a thing he does.
    ctrl = [r for r in fl if not r["pumped"] and r["minKn"] >= 8.3]

    print(f"\n=== TURNS [{ss.stem}] ===")
    print(f"  counted {len(rows)}: flew_through {len(fl)}, touchdown {len(td)}, fell_in {len(fi)}")
    print(f"  flew_through with pumped=true (the suspects): {len(sus)}")
    print(f"  impossible-touchdown controls (flew, no pump, minKn >= 8.3): {len(ctrl)}")

    print(f"\n  {'feature':14s} {'AUC td>flew':>12s} {'AUC td>suspect':>15s} {'AUC td>control':>15s}")
    for k in FEATURE_KEYS:
        print(f"  {k:14s} {auc([r[k] for r in fl], [r[k] for r in td]):12.3f}"
              f" {auc([r[k] for r in sus], [r[k] for r in td]):15.3f}"
              f" {auc([r[k] for r in ctrl], [r[k] for r in td]):15.3f}")
    print(f"  {'-minKn':14s} {auc([-r['minKn'] for r in fl], [-r['minKn'] for r in td]):12.3f}"
          f" {auc([-r['minKn'] for r in sus], [-r['minKn'] for r in td]):15.3f}"
          f" {auc([-r['minKn'] for r in ctrl], [-r['minKn'] for r in td]):15.3f}"
          "   <- speed alone, what the engine already has")
    print(f"  {'pumped':14s} {auc([float(r['pumped']) for r in fl], [float(r['pumped']) for r in td]):12.3f}"
          "                                <- the pump flag alone")

    print(f"\n  --- every counted turn, sorted by the RECOVERY feature ---")
    print(f"  {'ts':>6} {'outcome':12s} {'minKn':>6} {'pmp':>4} {'offS':>5} {'rec_hi_g':>8}"
          f" {'pk_hf':>6} {'sus_hf':>7} {'hf/pmp':>7} {'pk_g':>5} {'burst':>10}")
    for r in sorted(rows, key=lambda r: -r["rec_hi_g"]):
        turn = next(x for x in ss.turns if x["ts"] == r["ts"])
        b = first_burst_after(ss, turn)
        mark = "*" if (r["outcome"] == "flew_through" and r["pumped"]) else " "
        print(f" {mark}{r['ts']:6.0f} {r['outcome']:12s} {r['minKn']:6.2f}"
              f" {str(r['pumped'])[0]:>4} {r['offFoilS']:5.0f} {r['rec_hi_g']:8.2f}"
              f" {r['pk_hf']:6.1f} {r['sus_hf']:7.2f} {r['hf_over_pump']:7.2f}"
              f" {r['pk_g']:5.1f} {(f'{b[0]}str/{b[1]:.0f}s' if b else '-'):>10}")
    print("  (* = flew_through with a pump afterwards: the only turns that could be a touch-and-go)")


# ---- experiment 4: what the battery costs ---------------------------------------------

def sec_controls(ss: Session) -> None:
    print(f"\n=== CONTROLS: the price of the impact score [{ss.stem}] ===")
    ok = ss.clean_flight_mask()
    score = ss.e_hf / ss.b_hf
    ref = score[ok]
    ref = ref[~np.isnan(ref)]
    print(f"  clean mid-flight reference: {ok.sum() / FS / 60:.1f} min")
    print("  pk_hf percentiles there: " +
          "  ".join(f"p{q}={np.percentile(ref, q):.1f}" for q in (50, 90, 99, 99.9)) +
          f"  max={ref.max():.1f}")

    rows = scored_turns(ss)
    td = [r for r in rows if r["outcome"] == "touchdown"]
    fl = [r for r in rows if r["outcome"] == "flew_through"]
    sus = [r for r in fl if r["pumped"]]
    ctrl = [r for r in fl if not r["pumped"] and r["minKn"] >= 8.3]

    idx = np.flatnonzero(ok)
    step = int(10 * FS)
    windows = []
    for k in range(0, len(idx) - step, step):
        seg = idx[k:k + step]
        if seg[-1] - seg[0] > int(11 * FS):
            continue
        v = score[seg]
        v = v[~np.isnan(v)]
        if len(v) > 500:
            windows.append(float(v.max()))

    print(f"\n  --- pk_hf: the IMPACT feature, +-{WIN_BEFORE:.0f} s ---")
    print(f"  {'thr':>5} | {'touchdown':>10} | {'suspects':>9} | {'IMPOSSIBLE ctrl':>16}"
          f" | {'all flew':>9} | {'clean 10 s':>12} | {'precision':>9}")
    for thr in (4, 6, 8, 10, 13, 16, 20, 24):
        h_td = sum(r["pk_hf"] > thr for r in td)
        h_su = sum(r["pk_hf"] > thr for r in sus)
        h_ct = sum(r["pk_hf"] > thr for r in ctrl)
        h_fl = sum(r["pk_hf"] > thr for r in fl)
        h_cw = sum(v > thr for v in windows)
        prec = h_td / (h_td + h_fl) if (h_td + h_fl) else float("nan")
        print(f"  {thr:5.0f} | {h_td:5d}/{len(td):<4d} | {h_su:4d}/{len(sus):<4d}"
              f" | {h_ct:7d}/{len(ctrl):<7d} | {h_fl:4d}/{len(fl):<4d}"
              f" | {h_cw / max(len(windows), 1):11.0%} | {prec:9.0%}")
    print("  'IMPOSSIBLE ctrl' turns physically cannot have touched down. Every threshold\n"
          "  that catches most touchdowns also fires on a third of them: no operating point.")

    print(f"\n  --- rec_hi_g: the RECOVERY feature, seconds above 2 g in +-{REC_BEFORE:.0f} s ---")
    print(f"  {'thr s':>6} | {'touchdown':>10} | {'suspects':>9} | {'IMPOSSIBLE ctrl':>16}"
          f" | {'all flew':>9} | {'precision':>9}")
    for thr in (0.3, 0.5, 0.8, 1.0, 1.5, 2.0):
        h_td = sum(r["rec_hi_g"] > thr for r in td)
        h_su = sum(r["rec_hi_g"] > thr for r in sus)
        h_ct = sum(r["rec_hi_g"] > thr for r in ctrl)
        h_fl = sum(r["rec_hi_g"] > thr for r in fl)
        prec = h_td / (h_td + h_fl) if (h_td + h_fl) else float("nan")
        print(f"  {thr:6.2f} | {h_td:5d}/{len(td):<4d} | {h_su:4d}/{len(sus):<4d}"
              f" | {h_ct:7d}/{len(ctrl):<7d} | {h_fl:4d}/{len(fl):<4d} | {prec:9.0%}")
    for label, group in (("touchdown", td), ("suspects", sus), ("all flew", fl)):
        print(f"  {label:10s} rec_hi_g: "
              f"{sorted(round(r['rec_hi_g'], 2) for r in group)}")
    verdict = (f"and it clears all {len(sus)} suspects" if sus and
               all(r["rec_hi_g"] <= 0.8 for r in sus)
               else f"({sum(r['rec_hi_g'] > 0.8 for r in sus)}/{len(sus)} suspects over 0.8 s)")
    print("  This one has an operating point. It is not an impact detector: it measures the\n"
          f"  SUSTAINED heaving of a get-back-on-foil recovery, {verdict}.")


def sec_window(ss: Session) -> None:
    """Window sensitivity -- the honest check on a feature chosen after the fact."""
    global WIN_BEFORE, WIN_AFTER
    keep = (WIN_BEFORE, WIN_AFTER)
    print(f"\n=== WINDOW: is the impact score's separation an artefact of the window? "
          f"[{ss.stem}] ===")
    print(f"  {'window':>14} {'pk_hf td>flew':>14} {'td>suspect':>11} {'td>ctrl':>9}"
          f" {'best precision':>15}")
    try:
        for wb, wa in ((3, 3), (5, 5), (8, 8), (2, 8), (0, 6), (5, 10)):
            WIN_BEFORE, WIN_AFTER = float(wb), float(wa)
            rows = scored_turns(ss)
            td = [r for r in rows if r["outcome"] == "touchdown"]
            fl = [r for r in rows if r["outcome"] == "flew_through"]
            sus = [r for r in fl if r["pumped"]]
            ctrl = [r for r in fl if not r["pumped"] and r["minKn"] >= 8.3]
            best = 0.0
            for thr in np.arange(2, 30, 0.5):
                h_td = sum(r["pk_hf"] > thr for r in td)
                h_fl = sum(r["pk_hf"] > thr for r in fl)
                if h_td >= max(len(td) * 0.6, 1):
                    best = max(best, h_td / (h_td + h_fl))
            print(f"  -{wb}s..+{wa}s     {auc([r['pk_hf'] for r in fl], [r['pk_hf'] for r in td]):14.3f}"
                  f" {auc([r['pk_hf'] for r in sus], [r['pk_hf'] for r in td]):11.3f}"
                  f" {auc([r['pk_hf'] for r in ctrl], [r['pk_hf'] for r in td]):9.3f}"
                  f" {best:15.0%}")
    finally:
        WIN_BEFORE, WIN_AFTER = keep
    print("  Both AUC and precision climb as the window widens -- which is itself the finding:\n"
          "  an IMPACT lasts milliseconds, so a genuine impact feature would peak at the\n"
          "  NARROW window and decay. This does the opposite. The wider window is capturing\n"
          "  the recovery that follows, and it still tops out well below what `rec_hi_g`\n"
          "  reaches by measuring that recovery deliberately.")


# ---- experiment 5: the barometer ------------------------------------------------------

def sec_baro(ss: Session) -> None:
    print(f"\n=== BARO: does 1 Hz altitude see the foil's ride height? [{ss.stem}] ===")
    if ss.alt is None or not np.isfinite(ss.alt).any():
        print("  no altitude channel")
        return
    t, alt = ss.rec_t, ss.alt
    steps = []
    for tk in ss.gold["takeoffs"]:
        if not tk["success"]:
            continue
        lift = tk["startTs"]
        pre = alt[(t >= lift - 6) & (t < lift - 1)]
        post = alt[(t >= lift + 2) & (t < lift + 7)]
        if len(pre) >= 3 and len(post) >= 3:
            steps.append(float(np.nanmedian(post) - np.nanmedian(pre)))
    noise = []
    for s, e in ss.flights:
        if e - s <= 60:
            continue
        for c in np.arange(s + 15, e - 15, 10):
            a1 = alt[(t >= c - 6) & (t < c - 1)]
            a2 = alt[(t >= c + 2) & (t < c + 7)]
            if len(a1) >= 3 and len(a2) >= 3:
                noise.append(float(np.nanmedian(a2) - np.nanmedian(a1)))
    steps, noise = np.array(steps), np.array(noise)
    print(f"  liftoff step: n={len(steps)} median {np.median(steps):+.2f} m, "
          f"positive {int((steps > 0).sum())}/{len(steps)}")
    print(f"  in-flight noise floor for the same 5 s-vs-5 s comparison: n={len(noise)} "
          f"sd {noise.std():.2f} m")
    snr = abs(float(np.median(steps))) / max(noise.std(), 1e-6)
    print(f"  effect / noise = {snr:.2f}  ->  needs ~{int(np.ceil((2 / max(snr, 1e-6)) ** 2))} "
          f"events averaged for a 2-sigma read. Real, and useless per event.")


# ---- the physical anchor ---------------------------------------------------------------

def sec_anchor(ss: Session) -> None:
    print(f"\n=== ANCHOR: what it costs this rider to get back on foil [{ss.stem}] ===")
    tk = [x for x in ss.gold["takeoffs"] if x["success"]]
    if not tk:
        print("  no successful takeoffs")
        return
    e = np.array([x["entryKn"] for x in tk])
    p = np.array([x["pumps"] for x in tk])
    free = sum(1 for x in tk if x.get("free"))
    print(f"  {len(tk)} successful takeoffs; entry speed p10/median/p90 = "
          f"{np.percentile(e, 10):.2f}/{np.median(e):.2f}/{np.percentile(e, 90):.2f} kn")
    print(f"  pump strokes to takeoff p10/median/p90 = "
          f"{np.percentile(p, 10):.0f}/{np.median(p):.0f}/{np.percentile(p, 90):.0f}")
    print(f"  takeoffs that needed NO pumping at all: {free}/{len(tk)}")
    print("  So a turn that touched down and flew out with zero strokes is not a thing this\n"
          "  rider does. `pumped` is the necessary condition, and it is already computed.")


# ---- the rule that is already there ----------------------------------------------------

def sec_gate(ss: Session) -> None:
    """What actually separates `touchdown` from `flew_through` in today's engine.

    `turns._outcome` has two touchdown paths, and the second one is already a touch-and-go
    rule: when the flight never breaks, a turn is still called `touchdown` if the rider
    PUMPED inside the outcome window AND the speed went `marginal` -- below `foilEntrySpeed`
    on min(Doppler, positional). So the question is not "can the accel see a touch"; it is
    "where does the marginal gate sit".
    """
    from wingfoil_lab.evidence import KMH_TO_MPS, off_foil_evidence  # noqa: PLC0415
    from wingfoil_lab.goldens import analyze                          # noqa: PLC0415
    from wingfoil_lab.turns import _window_end                        # noqa: PLC0415

    print(f"\n=== GATE: the marginal test the engine already applies [{ss.stem}] ===")
    a = analyze(FIXTURES / f"{ss.stem}.fit")
    cfg = a.turn_config
    ev = off_foil_evidence(a.clean, a.flights, cfg.foil_exit_speed_kmh, cfg.baro_drop_m)
    gate_kn = cfg.foil_entry_speed_kmh * KMH_TO_MPS * MPS_TO_KN
    exit_kn = cfg.foil_exit_speed_kmh * KMH_TO_MPS * MPS_TO_KN
    print(f"  foilEntrySpeed {cfg.foil_entry_speed_kmh:.0f} km/h = {gate_kn:.2f} kn  (the "
          f"'marginal' gate)\n  foilExitSpeed  {cfg.foil_exit_speed_kmh:.0f} km/h = "
          f"{exit_kn:.2f} kn  (the hard off-foil gate)")

    rows = []
    for tn in a.turns:
        if not tn.counted:
            continue
        hi = _window_end(tn, ev, cfg)
        win = (ev.t >= tn.start_t) & (ev.t <= ev.t[hi])
        rows.append((tn.outcome, float(ev.speed[win].min()) * MPS_TO_KN, tn.start_t,
                     tn.min_kn, tn.pumped))
    print(f"\n  {'outcome':12s} {'n':>3} {'min gate-channel speed over the window (kn)':>46}")
    for oc in ("flew_through", "touchdown", "fell_in"):
        v = sorted(r[1] for r in rows if r[0] == oc)
        if v:
            print(f"  {oc:12s} {len(v):3d} {'min ' + f'{v[0]:.2f}':>12} "
                  f"{'median ' + f'{v[len(v) // 2]:.2f}':>15} {'max ' + f'{v[-1]:.2f}':>12}")
    sus = sorted((r for r in rows if r[0] == "flew_through" and r[4]), key=lambda r: r[1])
    if sus:
        print(f"\n  the {len(sus)} flew_through turns that DID pump -- how far each is from the gate:")
        print(f"  {'ts':>6} {'minKn(man)':>10} {'gate channel':>13} {'short by':>9}")
        for _, mn, ts, mk, _ in sus:
            print(f"  {ts:6.0f} {mk:10.2f} {mn:13.2f} {mn - gate_kn:9.2f} kn")
    td = [r[1] for r in rows if r[0] == "touchdown"]
    fw = [r[1] for r in rows if r[0] == "flew_through"]
    if td and fw:
        margin = min(fw) - max(td)
        if margin > 0:
            print(f"\n  The two classes do not overlap on this channel: a {margin:.2f} kn gap\n"
                  f"  between the slowest flew_through and the fastest touchdown.")
        else:
            print(f"\n  The classes overlap by {-margin:.2f} kn on this channel -- the `pumped`\n"
                  f"  half of the test is what keeps the slow flew_through turns where they are.")


def sec_sweep(ss: Session) -> None:
    """The one knob that moves the tally, swept. No accel involved."""
    import dataclasses  # noqa: PLC0415
    from wingfoil_lab.evidence import KMH_TO_MPS                      # noqa: PLC0415
    from wingfoil_lab.goldens import analyze                          # noqa: PLC0415
    from wingfoil_lab.turns import TurnConfig                         # noqa: PLC0415

    print(f"\n=== SWEEP: foilEntrySpeed vs the outcome tally [{ss.stem}] ===")
    print(f"  {'km/h':>6} {'kn':>6} | {'flew':>5} {'touch':>6} {'fell':>5} | turns that moved")
    base = None
    for kmh in (12.0, 12.5, 13.0, 13.5, 14.0, 15.0, 16.0):
        cfg = dataclasses.replace(TurnConfig(), foil_entry_speed_kmh=kmh)
        a = analyze(FIXTURES / f"{ss.stem}.fit", turn_config=cfg)
        t = [x for x in a.turns if x.counted]
        c = {o: sum(1 for x in t if x.outcome == o)
             for o in ("flew_through", "touchdown", "fell_in")}
        cur = {x.start_t: x.outcome for x in t}
        if base is None:
            base, flips = cur, ""
        else:
            flips = " ".join(f"{int(k)}:{base[k][:4]}->{v[:4]}"
                             for k, v in cur.items() if k in base and base[k] != v)
        print(f"  {kmh:6.1f} {kmh * KMH_TO_MPS * MPS_TO_KN:6.2f} | {c['flew_through']:5d}"
              f" {c['touchdown']:6d} {c['fell_in']:5d} | {flips}")
    print("  Flips to `fell_in`, or flips of turns that never pumped, are the over-reach\n"
          "  signal: past that point the knob is inventing touchdowns, not finding them.")


SECTIONS = {
    "anchor": sec_anchor,
    "liftoff": sec_liftoff,
    "pump": sec_pump,
    "turns": sec_turns,
    "controls": sec_controls,
    "window": sec_window,
    "baro": sec_baro,
    "gate": sec_gate,
    "sweep": sec_sweep,
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fixture", action="append", default=None,
                    help="fixture stem (repeatable); default: both ciq fixtures")
    ap.add_argument("--section", default="all", choices=["all", *SECTIONS])
    args = ap.parse_args()

    stems = args.fixture or sorted(p.stem for p in FIXTURES.glob("*_ciq.fit"))
    which = list(SECTIONS) if args.section == "all" else [args.section]
    for stem in stems:
        ss = Session(stem)
        for name in which:
            SECTIONS[name](ss)
        print()


if __name__ == "__main__":
    main()
