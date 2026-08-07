#!/usr/bin/env python
"""Phase-2 review deliverable: turn detection + wind axis on one session.

Renders a two-panel figure -- GPS track (off-foil gray, foiling colored, numbered turn
markers, wind-axis arrow) over a speed-vs-time strip carrying the same numbers -- and
prints the turn table the numbers refer to.

Usage: cd lab && uv run python tools/plot_turns.py [FIT ...] [--out PNG]
"""

from __future__ import annotations

import argparse
import datetime as dt
import sys
from pathlib import Path

import fitdecode
import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.patheffects as pe                                    # noqa: E402
import matplotlib.pyplot as plt                                        # noqa: E402
from matplotlib.lines import Line2D                                    # noqa: E402

from wingfoil_lab.filters import clean, hybrid_speed                   # noqa: E402
from wingfoil_lab.flight import segment_flights                        # noqa: E402
from wingfoil_lab.flightend import (GLIDE_OUT, UNKNOWN, classify_flight_ends,  # noqa: E402
                                    split_outcomes, summarize_flight_ends)
from wingfoil_lab.parse import MPS_TO_KN, parse_fit                    # noqa: E402
from wingfoil_lab.pump import pump_track                               # noqa: E402
from wingfoil_lab.turns import (FELL_IN, FLEW_THROUGH, JIBE, TACK, TOUCHDOWN,  # noqa: E402
                                detect_turns, summarize_turns)
from wingfoil_lab.wind import estimate_wind                            # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DEFAULT_FIT = REPO / "fixtures/sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit"

# Reference data-viz palette: categorical slots for series, status steps for state.
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
TRACK = "#d6d5d1"        # off-foil track: recessive
FOIL = "#2a78d6"         # categorical slot 1
MANEUVER = "#9fc2ea"     # slot 1, tinted: the positional channel behind the Doppler line
WIND = "#eb6834"         # categorical slot 2
GOOD = "#0ca30c"         # status: flew through
WARN = "#e8a020"         # status: touched down
BAD = "#d03b3b"          # status: fell in
REJECT = "#8c8b87"       # not a maneuver

# Outcome -> (marker, facecolor, edgecolor). A green/amber/red status ramp cannot pass an
# all-pairs CVD check (protan/deutan collapse exactly this hue range -- validator reports
# dE ~4 green<->red), so **shape carries the state** and color only reinforces it: every
# outcome has its own marker and its own legend label, never color alone.
TURN_STYLE = {
    FLEW_THROUGH: ("o", GOOD, GOOD),        # filled disc: carried the foil through
    TOUCHDOWN: ("v", WARN, WARN),           # dipped down and came back up
    FELL_IN: ("X", BAD, BAD),               # heavy cross: went swimming
}
REJECT_STYLE = ("x", REJECT, REJECT)        # hairline cross: not a maneuver at all

# Straight-line flight ends -- losses that happened outside any maneuver. They share the
# outcome *colour* with the turns so the state reads the same, but take **hollow square**
# markers: the fill/shape axis now carries "was this a maneuver or not", which is the one
# question a reader asks first when a marker sits in the middle of a reach.
END_STYLE = {
    GLIDE_OUT: ("s", "none", INK_2),        # came off the foil but kept moving
    TOUCHDOWN: ("s", "none", WARN),
    FELL_IN: ("s", "none", BAD),
}

HEADER = (f"{'#':>3}  {'time':>8}  {'type':<9} {'dir':<9} {'side':<9} "
          f"{'entry':>6} {'min':>6} {'score':>6} {'ok':<4} "
          f"{'outcome':<12} {'bl':<3} {'stop s':>6} {'offfoil':>7} {'win':>4} "
          f"{'pump':<5} {'wet':<4} {'arc':>5} {'R':>5}")

END_HEADER = (f"{'#':>3}  {'time':>8}  {'outcome':<10} {'bl':<3} {'stop s':>6} "
              f"{'offfoil':>7} {'vmin':>5} {'win':>4} {'pump':<5} {'wet':<4} {'owner':<7}")


def local_offset(path: Path) -> dt.timedelta:
    """Watch-recorded UTC offset (activity.local_timestamp - activity.timestamp)."""
    with fitdecode.FitReader(path, check_crc=fitdecode.CrcCheck.WARN) as reader:
        for frame in reader:
            if isinstance(frame, fitdecode.FitDataMessage) and frame.name == "activity":
                got = {f.name: f.value for f in frame.fields}
                if got.get("local_timestamp") and got.get("timestamp"):
                    return got["local_timestamp"] - got["timestamp"]
    return dt.timedelta(0)


def analyze_session(path: Path) -> dict:
    """parse -> clean -> flights -> wind -> turns for one FIT."""
    track = parse_fit(path)
    ct = clean(track)
    flights = segment_flights(ct)
    wind = estimate_wind(ct, flights)
    pump = pump_track(track)
    turns = detect_turns(ct, flights, wind, pump=pump)
    ends = classify_flight_ends(ct, flights, turns, pump=pump)
    summary = summarize_turns(turns)
    end_summary = summarize_flight_ends(ends)
    start = track.records["timestamp"].iloc[0] + local_offset(path)
    return {"path": path, "clean": ct, "flights": flights, "wind": wind, "pump": pump,
            "turns": turns, "summary": summary, "start": start,
            "ends": ends, "end_summary": end_summary,
            "split": split_outcomes(summary, end_summary)}


def print_table(session: dict) -> None:
    wind, summary = session["wind"], session["summary"]
    print(f"\n{session['path'].name}")
    axis = "unresolved" if wind.dir_deg is None else (
        f"{wind.dir_deg:.0f} deg (from), confidence {wind.confidence:.2f}, "
        f"axis conf {wind.axis_confidence:.2f}, margin {wind.ambiguity_margin:.2f}, "
        f"lobes {wind.lobes_deg[0]:.0f}/{wind.lobes_deg[1]:.0f} deg")
    print(f"  wind: {axis}")
    print(f"  flights {session['flights'].flight_count}, "
          f"foil {session['flights'].foil_time_s / 60:.0f} min "
          f"({session['flights'].foil_pct:.0f} %)")
    print("\n" + HEADER)
    print("  " + "-" * (len(HEADER) - 2))
    for n, turn in enumerate(session["turns"], 1):
        clock = (session["start"] + dt.timedelta(seconds=turn.start_t)).strftime("%H:%M:%S")
        print(f"{n:3d}  {clock:>8}  {turn.kind:<9} {turn.direction:<9} {turn.side:<9} "
              f"{turn.entry_kn:6.2f} {turn.min_kn:6.2f} {100 * turn.score:5.1f}% "
              f"{'yes' if turn.success else 'no':<4} {turn.outcome:<12} "
              f"{'yes' if turn.borderline else '-':<3} "
              f"{turn.stopped_s:6.1f} {turn.off_foil_s:7.1f} "
              f"{turn.outcome_window_s:4.0f} "
              f"{'yes' if turn.pumped else '-':<5} {'yes' if turn.submerged else '-':<4} "
              f"{turn.arc_m:5.1f} {turn.radius_m:5.1f}")
    print(f"\n  tacks {summary.tacks} ({summary.tacks_successful} made) · "
          f"jibes {summary.jibes} ({summary.jibes_successful} made) · "
          f"counted {summary.turns_counted} ({summary.turns_successful} made, "
          f"{summary.success_pct:.0f} %) · rejected {summary.rejected} · "
          f"port/starboard {summary.port}/{summary.starboard}")
    for name, oc in (("jibes", summary.jibe_outcomes), ("tacks", summary.tack_outcomes)):
        print(f"  {name} outcome: flew through {oc.flew_through} · "
              f"touchdown {oc.touchdown} · fell in {oc.fell_in} "
              f"(of {oc.total}; {oc.borderline} borderline)")
    print_flight_ends(session)


def print_flight_ends(session: dict) -> None:
    """The flight-end table plus the in-turn / straight-line split."""
    es, split = session["end_summary"], session["split"]
    print(f"\n  flight ends ({len(session['ends'])} flights)\n")
    print(END_HEADER)
    print("  " + "-" * (len(END_HEADER) - 2))
    for n, end in enumerate(session["ends"], 1):
        clock = (session["start"] + dt.timedelta(seconds=end.t)).strftime("%H:%M:%S")
        vmin = "-" if end.min_speed_mps == float("inf") else f"{end.min_speed_mps:5.2f}"
        print(f"{n:3d}  {clock:>8}  {end.outcome:<10} "
              f"{'yes' if end.borderline else '-':<3} {end.stopped_s:6.1f} "
              f"{end.off_foil_s:7.1f} {vmin:>5} {end.window_s:4.0f} "
              f"{'yes' if end.pumped else '-':<5} {'yes' if end.submerged else '-':<4} "
              f"{('turn ' + str(end.owned_by_turn + 1)) if end.in_turn else '-':<7}")
    for label, oc in (("all      ", es.all_ends), ("in turn  ", es.in_turn),
                      ("straight ", es.straight)):
        print(f"  {label}: glide out {oc.glide_out} · touchdown {oc.touchdown} · "
              f"fell in {oc.fell_in} (of {oc.total}; {oc.borderline} borderline)"
              + (f" · {oc.unknown} truncated by a gap" if oc.unknown else ""))
    print(f"\n  SESSION SPLIT: falls {split.falls} "
          f"({split.turn_falls} in turns / {split.straight_falls} straight-line) · "
          f"touchdowns {split.touchdowns} "
          f"({split.turn_touchdowns} in turns / {split.straight_touchdowns} straight-line) · "
          f"glide-outs {split.glide_outs}"
          + (f" · {split.unknown_ends} evidence-free flight ends"
             if split.unknown_ends else ""))


def _straight_ends(session: dict) -> list:
    """Flight ends no turn owns and that carry evidence -- the straight-line losses."""
    return [e for e in session["ends"] if not e.in_turn and e.outcome != UNKNOWN]


def _turn_style(turn) -> tuple[str, str, str]:
    """(marker, facecolor, edgecolor) -- shape carries the outcome, color reinforces it.

    Bear-aways/round-ups are not maneuvers, so they stay a recessive gray hairline
    whatever their outcome was.
    """
    if turn.kind not in (TACK, JIBE):
        return REJECT_STYLE
    return TURN_STYLE[turn.outcome]


def _label(ax, x, y, n: int, color: str) -> None:
    """Numbered marker label; alternating side keeps dense clusters readable."""
    up = n % 2 == 1
    ax.annotate(str(n), (x, y), textcoords="offset points", xytext=(0, 9 if up else -10),
                ha="center", va="bottom" if up else "top", fontsize=8, fontweight="bold",
                color=color, zorder=6,
                path_effects=[pe.withStroke(linewidth=2.8, foreground=SURFACE)])


def draw_map(ax, session: dict) -> None:
    df = session["clean"].records
    ax.plot(df["x"], df["y"], color=TRACK, lw=0.9, solid_capstyle="round", zorder=1)
    for flight in session["flights"].flights:
        seg = df[(df["t"] >= flight.start_t) & (df["t"] <= flight.end_t)]
        ax.plot(seg["x"], seg["y"], color=FOIL, lw=1.4, alpha=0.85,
                solid_capstyle="round", zorder=2)

    t = df["t"].to_numpy(float)
    for end in _straight_ends(session):
        k = int(np.argmin(np.abs(t - end.t)))
        marker, face, edge = END_STYLE[end.outcome]
        ax.plot(df["x"].iloc[k], df["y"].iloc[k], marker=marker, ms=8.5, mew=1.6,
                mfc=face, mec=edge, zorder=4)

    for n, turn in enumerate(session["turns"], 1):
        k = int(np.argmin(np.abs(t - turn.min_t)))
        marker, face, edge = _turn_style(turn)
        ax.plot(df["x"].iloc[k], df["y"].iloc[k], marker=marker, ms=7.5, mew=1.6,
                mfc=face, mec=edge, zorder=5)
        _label(ax, df["x"].iloc[k], df["y"].iloc[k], n, edge)

    wind = session["wind"]
    if wind.dir_deg is not None:
        _wind_arrow(ax, wind)

    ax.set_aspect("equal")
    ax.set_xlabel("east (m)", color=INK_2, fontsize=8)
    ax.set_ylabel("north (m)", color=INK_2, fontsize=8)
    _chrome(ax)


def _wind_arrow(ax, wind) -> None:
    """Arrow drawn blowing *with* the wind (from `dir_deg` toward the lee), in the corner."""
    lo_x, hi_x = ax.dataLim.x0, ax.dataLim.x1
    lo_y, hi_y = ax.dataLim.y0, ax.dataLim.y1
    span = 0.16 * max(hi_x - lo_x, hi_y - lo_y)
    cx = hi_x - 0.10 * (hi_x - lo_x)
    cy = hi_y - 0.10 * (hi_y - lo_y)
    to = np.radians(wind.dir_deg + 180.0)          # direction the air travels
    dx, dy = np.sin(to) * span, np.cos(to) * span
    ax.annotate("", xy=(cx + dx / 2, cy + dy / 2), xytext=(cx - dx / 2, cy - dy / 2),
                arrowprops=dict(arrowstyle="-|>,head_width=0.28,head_length=0.6",
                                color=WIND, lw=2.0, shrinkA=0, shrinkB=0), zorder=4)
    ax.annotate(f"wind {wind.dir_deg:.0f}°  (conf {wind.confidence:.2f})",
                (cx, cy - span * 0.75), ha="center", va="top", fontsize=8,
                color=WIND, fontweight="bold",
                path_effects=[pe.withStroke(linewidth=2.6, foreground=SURFACE)], zorder=5)


def draw_strip(ax, session: dict) -> None:
    df = session["clean"].records
    t_min = df["t"].to_numpy(float) / 60.0
    for flight in session["flights"].flights:
        ax.axvspan(flight.start_t / 60.0, flight.end_t / 60.0, color=FOIL, alpha=0.08, lw=0)
    ax.plot(t_min, hybrid_speed(df) * MPS_TO_KN, color=MANEUVER, lw=0.6, alpha=0.8,
            label="positional (scores turns)", zorder=2)
    ax.plot(t_min, df["doppler_mps"] * MPS_TO_KN, color=FOIL, lw=1.0,
            label="Doppler (flight state)", zorder=3)
    ax.legend(loc="upper left", ncol=2, frameon=False, fontsize=7.5,
              labelcolor=INK_2, bbox_to_anchor=(0.0, 1.16), handlelength=1.6)

    speed_kn = hybrid_speed(df) * MPS_TO_KN
    t_all = df["t"].to_numpy(float)
    for end in _straight_ends(session):
        marker, face, edge = END_STYLE[end.outcome]
        k = int(np.argmin(np.abs(t_all - end.t)))
        ax.plot(end.t / 60.0, speed_kn[k], marker=marker, ms=7.0, mew=1.5,
                mfc=face, mec=edge, zorder=4)

    for n, turn in enumerate(session["turns"], 1):
        marker, face, edge = _turn_style(turn)
        ax.plot(turn.min_t / 60.0, turn.min_kn, marker=marker, ms=6.5, mew=1.5,
                mfc=face, mec=edge, zorder=5)
        _label(ax, turn.min_t / 60.0, turn.min_kn, n, edge)

    ax.set_xlim(t_min.min(), t_min.max())
    ax.set_ylim(0, None)
    ax.set_xlabel("session time (min)", color=INK_2, fontsize=8)
    ax.set_ylabel("speed (kn)", color=INK_2, fontsize=8)
    ax.grid(axis="y", color=INK, alpha=0.07, lw=0.7)
    ax.set_axisbelow(True)
    _chrome(ax)


def _chrome(ax) -> None:
    ax.set_facecolor(SURFACE)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color("#dedcd6")
    ax.tick_params(colors=INK_2, labelsize=8, length=3, width=0.8)


def _legend(fig, session: dict) -> None:
    oc = session["summary"].outcomes
    labels = {FLEW_THROUGH: f"flew through ({oc.flew_through})",
              TOUCHDOWN: f"touched down ({oc.touchdown})",
              FELL_IN: f"fell in ({oc.fell_in})"}
    handles = [Line2D([], [], color=TRACK, lw=1.6, label="off foil"),
               Line2D([], [], color=FOIL, lw=1.8, label="foiling")]
    handles += [Line2D([], [], ls="none", marker=TURN_STYLE[k][0], ms=7.5, mew=1.6,
                       mfc=TURN_STYLE[k][1], mec=TURN_STYLE[k][2], label=labels[k])
                for k in (FLEW_THROUGH, TOUCHDOWN, FELL_IN)]
    handles += [
        Line2D([], [], ls="none", marker=REJECT_STYLE[0], ms=7, mec=REJECT, mew=1.6,
               label=f"bear-away / round-up, not counted ({session['summary'].rejected})"),
        Line2D([], [], color=WIND, lw=2.0, label="estimated wind axis"),
    ]
    straight = session["end_summary"].straight
    end_labels = {GLIDE_OUT: f"straight-line glide-out ({straight.glide_out})",
                  TOUCHDOWN: f"straight-line touchdown ({straight.touchdown})",
                  FELL_IN: f"straight-line fall ({straight.fell_in})"}
    handles += [Line2D([], [], ls="none", marker=END_STYLE[k][0], ms=8.5, mew=1.6,
                       mfc="none", mec=END_STYLE[k][2], label=end_labels[k])
                for k in (GLIDE_OUT, TOUCHDOWN, FELL_IN) if getattr(straight, k)]
    fig.legend(handles=handles, loc="lower center", ncol=3, frameon=False,
               fontsize=8, labelcolor=INK_2, bbox_to_anchor=(0.5, 0.005))


def render(session: dict, out: Path) -> Path:
    summary, wind = session["summary"], session["wind"]
    fig = plt.figure(figsize=(9.5, 11.0), facecolor=SURFACE)
    gs = fig.add_gridspec(2, 1, height_ratios=[2.5, 1.0], hspace=0.22,
                          left=0.09, right=0.97, top=0.90, bottom=0.10)
    draw_map(fig.add_subplot(gs[0]), session)
    draw_strip(fig.add_subplot(gs[1]), session)

    stamp = session["start"].strftime("%Y-%m-%d %H:%M")
    fig.text(0.09, 0.965, f"Turns & wind axis — {session['path'].stem}", fontsize=13,
             fontweight="bold", color=INK, ha="left")
    oc = summary.outcomes
    fig.text(0.09, 0.944,
             f"{stamp} local · {summary.jibes} jibes / {summary.tacks} tacks · "
             f"{oc.flew_through} flown through · {oc.touchdown} touchdowns · "
             f"{oc.fell_in} falls"
             + (f" · {oc.borderline} borderline" if oc.borderline else ""),
             fontsize=9, color=INK_2, ha="left")
    fig.text(0.09, 0.923,
             f"{summary.turns_successful} of {summary.turns_counted} also kept "
             f"≥ 70 % of entry speed ({summary.success_pct:.0f} %) · "
             f"{summary.rejected} bear-aways rejected · "
             f"wind from {wind.dir_deg:.0f}° (confidence {wind.confidence:.2f})",
             fontsize=9, color=INK_2, ha="left")
    split = session["split"]
    fig.text(0.09, 0.902,
             f"falls {split.falls} ({split.turn_falls} in turns / "
             f"{split.straight_falls} straight-line) · "
             f"touchdowns {split.touchdowns} ({split.turn_touchdowns} / "
             f"{split.straight_touchdowns}) · glide-outs {split.glide_outs}",
             fontsize=9, color=INK_2, ha="left")
    _legend(fig, session)
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=170, facecolor=SURFACE)
    plt.close(fig)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("fits", nargs="*", type=Path, default=[DEFAULT_FIT],
                    help="FIT files (default: today's CIQ session)")
    ap.add_argument("--out", type=Path, default=Path("/tmp/wingfoil-turns-review.png"),
                    help="PNG for the FIRST file (default: /tmp/wingfoil-turns-review.png)")
    args = ap.parse_args(argv)

    for i, fit in enumerate(args.fits or [DEFAULT_FIT]):
        if not fit.exists():
            print(f"missing: {fit}", file=sys.stderr)
            return 1
        session = analyze_session(fit)
        print_table(session)
        if i == 0:
            print(f"\n  figure: {render(session, args.out)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
