"""WingFoil lab — parse real session FITs, tune detectors, freeze goldens.

Module map (mirrors the analysis pipeline in docs/plan.md §3.3):
    parse    FIT/GPX -> RawTrack + SourceCapabilities
    filters  sample hygiene (GP3S gates, projection, hybrid speed)   [phase 1]
    flight   foil/flight segmentation (hysteresis)                    [phase 1]
    turns    turn detection + scoring + classification                [phase 2]
    wind     wind-axis estimation                                     [phase 2]
    gp3s     speed records incl. alpha 500                            [phase 1/3]
    pump     pump-stroke detection from wrist accel                   [phase 3]
    takeoff  takeoff runs, attempts, in-flight pumping                 [phase 3]
    goldens  golden-file writer/loader (schema: docs/testing.md)
Canonical parameters live in docs/algorithms.md — keep code defaults in sync.
"""

ENGINE_VERSION = "0.2.0"
