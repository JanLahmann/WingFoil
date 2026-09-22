"""Discipline presets -- one engine, three rigs (docs/algorithms/disciplines.md "Disciplines").

A discipline is **not a fork of the engine**. Every stage, every clock and every verdict is
the one docs/algorithms.md describes; a preset only picks the numbers a few of them are asked
against, and switches off the one channel a windsurfer does not have.

``wingfoil``
    The published contract, unchanged. The preset is a no-op by construction: it is not even
    applied, so a wingfoil run is byte-identical to one produced before this module existed.

``windsurfFoil``
    A foiling windsurfer flies on the same foil at the same speeds, so every threshold is the
    wingfoil one. What he does not do is **pump**: there is no wing to load, the accelerometer
    hears the rig and the chop and nothing else, and every number built on it would be noise
    presented as effort. So the pump channel is not run at all.

``windsurfFin``
    A fin board does not fly, it **planes**, and it planes far faster than a foil flies. The
    hysteresis that says "on the foil" says "planing" instead, at speeds a fin board reaches:
    20 km/h in, 15 km/h out. The holds, the minimum duration and every turn parameter are
    unchanged -- a jibe is a jibe.

    **The two speeds are PROVISIONAL.** They are a first guess from planing thresholds
    elsewhere in the sport, not a reading off Jan's corpus, which contains no fin session at
    all. GitHub issue #6 gates them on 5-10 windsurf sessions with ground truth.
"""

from __future__ import annotations

from dataclasses import replace
from enum import Enum

from .flight import FlightConfig
from .flightend import FlightEndConfig
from .takeoff import TakeoffConfig
from .turns import TurnConfig


class Discipline(str, Enum):
    """Which rig the session was ridden on -- the preset key, not the dev field's spelling."""

    WINGFOIL = "wingfoil"
    WINDSURF_FOIL = "windsurfFoil"
    WINDSURF_FIN = "windsurfFin"

    @property
    def pumping(self) -> bool:
        """Is the pump channel run at all? Wingfoil only."""
        return self is Discipline.WINGFOIL

    @property
    def is_windsurf(self) -> bool:
        return self is not Discipline.WINGFOIL

    @property
    def foil_entry_speed_kmh(self) -> float:
        return 20.0 if self is Discipline.WINDSURF_FIN else 12.0

    @property
    def foil_exit_speed_kmh(self) -> float:
        return 15.0 if self is Discipline.WINDSURF_FIN else 8.0


def resolve(tag: str | None, override: str | None = None) -> Discipline:
    """The preset a session is analysed under.

    The rider's **override** wins over everything. Failing that, the `discipline` developer
    field decides -- and *only* it: a Garmin **windsurf profile** recording is the common way
    a wingfoil session reaches this library (ADR-004 records FIT sport 43 for wingfoiling),
    so the sport code alone must never switch the preset. Anything this function cannot read
    is wingfoil, the default.
    """
    for value in (override, tag):
        if not value:
            continue
        key = value.strip().lower().replace("_", "").replace("-", "").replace(" ", "")
        if key in ("windsurffin", "windsurfingfin", "fin"):
            return Discipline.WINDSURF_FIN
        if key in ("windsurf", "windsurfing", "windsurffoil", "windsurfingfoil", "windfoil"):
            return Discipline.WINDSURF_FOIL
        if key in ("wingfoil", "wing", "wingfoiling"):
            return Discipline.WINGFOIL
    return Discipline.WINGFOIL


def apply(discipline: Discipline, flight: FlightConfig, turn: TurnConfig,
          flight_end: FlightEndConfig, takeoff: TakeoffConfig
          ) -> tuple[FlightConfig, TurnConfig, FlightEndConfig, TakeoffConfig]:
    """The preset, over a set of configs. Identity for ``wingfoil``.

    The two speeds live in **four** configs and have to move together: the flight hysteresis
    segments the runs, the turn ladder and the flight-end ladder read "off the foil" from the
    exit speed, and the takeoff analyser shares the one off-foil evidence object built from
    it. Moving one alone would leave the scorer judging against a speed no run was segmented
    on -- and would silently split the shared evidence in `analyze`.
    """
    if discipline is Discipline.WINGFOIL:
        return flight, turn, flight_end, takeoff
    entry, exit_ = discipline.foil_entry_speed_kmh, discipline.foil_exit_speed_kmh
    return (
        replace(flight, foil_entry_speed_kmh=entry, foil_exit_speed_kmh=exit_),
        # The pump rung is not merely unreachable here, it is refused: with no pump channel
        # there is no burst to corroborate, and a switch left on would claim otherwise.
        replace(turn, foil_entry_speed_kmh=entry, foil_exit_speed_kmh=exit_,
                pumped_out_is_touchdown=False),
        replace(flight_end, foil_entry_speed_kmh=entry, foil_exit_speed_kmh=exit_),
        replace(takeoff, foil_exit_speed_kmh=exit_),
    )
