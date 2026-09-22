> Part of `docs/algorithms.md`. Engine 0.23.0.

## Recordings the importer refuses (phone)

**No engine version.** Nothing here reads a recording differently — it decides whether there
is a recording to read at all, and every fixture and every golden is untouched. Bumping
`AnalysisEngine.version` for it would re-derive every session in every library to arrive at
the same numbers.

Every rule above assumes a recording that *arrived*. Four kinds do not, and each is refused
by name, before the file reaches a parser or an analyzer, so that a bulk sync reports one
failed activity and carries on with the rest (`IcuSyncSummary.failed`).

| refusal | test | why it is fatal without the gate |
|---|---|---|
| `truncated` | the FIT header's declared data size runs past the end of the file | the bytes past the end are decoded as records: timestamps decades apart, a session spanning half a century |
| `damaged` | the file's own CRC-16 does not match its bytes | a corrupted definition message rebuilds the vendored C decoder's field table from garbage and walks the next message off a stack-allocated struct — a **segfault** |
| `malformed` | `FitStreamWalker` cannot frame the record layer | our walker and the C decoder would frame the same bytes differently, which is the same failure by another route |
| `implausibleDuration` | first to last sample spans more than **7 days** | `durationS` sizes arrays — the rolling-rate series is one point a minute — so a broken clock asks for tens of millions of entries and iOS answers by killing the app, which leaves **no crash report at all** |

The first three are `FitSessionParser.ParseError`; the last is `IngestError`, checked in
`SessionIngestor.ingest` where the duration is first known and applies to every format.

**Every recording in the corpus passes all four**, and so does the bundled example session:
the gates are written against damage, not against strangeness. A file from a device nobody
here owns is still read — that is what the input classes are for.

**Three ceilings say the same thing inside the engine**, as a second lock on the same door,
and none of them can be reached by a session: the rolling-rate series stops at 20 000 points
(fourteen days), the pump resample grid at four hours of 25 Hz samples, and the HR fatigue
bins at a year of them. They move no number on any fixture; they exist so that an engine
handed a number it did not measure cannot allocate on it. `MAX_SERIES_POINTS` in
`lab/src/wingfoil_lab/goldens.py` is the lab's twin of the first.

**And nothing converts a file's Double to an `Int` directly.** `Int(_:)` traps on NaN,
infinity and anything past the range, and a trap is uncatchable: the app dies with nothing to
report. Values that came out of a file go through `Int(clamped:)`, and a developer field
whose float payload is NaN or infinite is dropped at the decoder the way an invalid sentinel
already is (`FitDevValue.double`).

## GPX import — input class (c) (phone/web, engine ≥ 0.9.0)

`lab/src/wingfoil_lab/gpx.py` · `ios/…/GpxImport/GpxSessionParser.swift`

A GPX carries positions and a clock, and none of the three channels the analysis would like
to have. Each absence is recorded as a fact about the *source* rather than papered over, and
the whole of the degradation follows from `SourceCapabilities` exactly as it already does
for a native FIT.

| what is read | from | notes |
|---|---|---|
| position | `trkpt/@lat`, `@lon` | a point without both is skipped |
| time | `trkpt/time` | ISO 8601; **a point without one is not a sample at all** — every phase of the analysis is a function of time |
| altitude | `trkpt/ele` | feeds `turnBaroDrop` where the exporter wrote a barometric value |
| heart rate | `extensions/…/hr` | Garmin `TrackPointExtension`, matched on the local tag name so any prefix works |

**Speed is differentiated from positions**, over the same local-meter projection
`speedChannelManeuvers` already uses — deliberately the arithmetic that produces `pos_mps`,
so a GPX session's two speed channels agree instead of disagreeing about the same metres.
Haversine would be marginally more correct over a session's *extent* and no more correct at
all over the one-second steps this actually measures.

The derived channel then *becomes* `doppler_mps`, and `capabilities.hasDoppler` is
nevertheless **false**. That pair is the point: the column says the analysis has a number
to work with, the flag says the file could not prove it was measured. `hasDoppler` is what
makes `source_class` `c`, and class (c) is what every surface reads to mark these speed
records **uncertified** (docs/presentation.md). Positional differentiation is noisier than
Doppler and biased *upward* on a bad fix — on the converted fixture it reads 13.65 kn
against the FIT's 13.47 over 2 s — which is why the mark is on the record and not merely in
a footnote. Since engine 0.20.0 the shortest of those records is also *gated* on the same
track's best 10 s ("The plausibility gate"); the mark stays either way.

No accelerometer means `pump.py` and `takeoff.py` take their speed-only paths (every stroke
count null, `pumpEpisodes` empty), exactly as they do on a native FIT. No developer fields
means no watch summary and so no divergence check.

**Segments.** A `<trkseg>` boundary is the recorder saying it stopped, so the two sides are
not one motion and a speed differentiated across the join would be a fiction. Each segment
is differentiated on its own and the join is marked `gap_before`, which `filters.clean` ORs
into the dt-aware gap rule *and* resets the spike filter on — the break survives even when
the clock happens to be continuous across it, which is the one case the dt rule alone cannot
see. Several `<trk>`s are several activities, not several segments: the first is analysed
and the count is reported (`session["gpxTracks"]`).

**Time zone.** A `Z` timestamp states an *instant* and nothing about the rider's clock, so it
yields no offset and the longitude rung of the ladder below takes over. A timestamp written
with a numeric offset (`+02:00`) is the exporter naming the local clock, and wins.

## TCX import — class (b) *or* class (c), decided by one element

`lab/src/wingfoil_lab/tcx.py` · `ios/…/TcxImport/TcxSessionParser.swift`

A TCX (Garmin's Training Center Database v2) is the other XML door, and it is the only
format in this engine that is **not one input class**. It carries positions and a clock
exactly as a GPX does, and it *may* also carry the receiver's own speed in the per-point
`TPX` extension. Polar, Suunto and Coros sessions reach CleanJibe this way through
intervals.icu, so this is a common file and not an exotic one.

**The rule, and it is the whole of the difference:**

| the file says | class | speed channel | records |
|---|---|---|---|
| `Extensions/TPX/Speed` present (m/s) | **(b)** | the receiver's own, carried through untouched | **certified** |
| no `TPX/Speed` anywhere | **(c)** | differentiated from positions, `gpx.py`'s arithmetic | **uncertified** |

`capabilities.hasDoppler` is the flag, as always, and it is a question about *the file*, not
about coverage: one stated speed anywhere makes the session class (b), and the samples that
carry none get a null that `clean` drops — the same treatment a FIT with dropped samples
already gets. A negative or unparseable `Speed` is not a measurement of anything, so it
leaves the file having said nothing.

| what is read | from | notes |
|---|---|---|
| time | `Trackpoint/Time` | ISO 8601; **a point without one is not a sample at all**, the GPX rule verbatim |
| position | `Position/LatitudeDegrees`, `LongitudeDegrees` | a point without both is skipped (an indoor trackpoint is exactly this) |
| altitude | `Trackpoint/AltitudeMeters` | feeds `turnBaroDrop` where the exporter wrote a barometric value |
| heart rate | `HeartRateBpm/Value` | `Value` counts as heart rate *only* inside `HeartRateBpm`; TCX reuses the tag for a lap's average and maximum |
| speed | `Extensions/…/Speed` | m/s. The element above, matched on local tag name so either activity-extension namespace and any prefix are read |
| laps | `Lap/@StartTime`, `TotalTimeSeconds`, `DistanceMeters` | carried verbatim; `hasWatchLaps` is `laps > 1`, the FIT rule |

**Segments.** TCX nests `Activity > Lap > Track > Trackpoint`, and the two container levels
mean different things. A `<Lap>` is a *marker* — the rider pressed lap, or the watch closed
one on a distance — and the board kept moving through it, so a lap boundary is **not** a
gap. A second `<Track>` is the recorder having stopped and started again, which is exactly
what a GPX `<trkseg>` boundary says, so **that** is the join marked `gap_before`.

**Several activities.** The first `<Activity>` is analysed and the count is reported
(`session["tcxActivities"]`) — several activities are several sessions, the same rule GPX
applies to several `<trk>`s.

**Sport is not read.** `Activity/@Sport` admits only `Running`, `Biking` and `Other`, so
every watersport session is `Other`; filing that as `capabilities.sport` would turn "this
file cannot say" into a claim that a watersport gate downstream would act on.

**Time zone, accelerometer, developer fields.** All three as for GPX: the same ladder (a
`Z` states an instant and hands over to longitude, a numeric offset wins), no accelerometer
so no strokes and no `pumpEpisodes`, nothing of ours so no watch summary and no divergence
check.

Everything a TCX shares with a GPX is *shared code* rather than a second spelling — the
ISO-8601 scanner and the positional-speed differentiation both — because two XML parsers
disagreeing about the same metres would be a bug no golden could see. The fixture pair
`fixtures/sessions/tcx/2026-08-30-1407_nago-torbole-{speed,nospeed}.tcx` is that claim's
experiment: the 2026-08-30 CIQ afternoon converted twice by `lab/tools/fit_to_tcx.py`,
differing by the one element. The speedless one reproduces the GPX golden's numbers
(13.65 kn best-2 s, 67.3 % foil); the speed-bearing one reproduces the FIT's (13.47 kn,
67.9 %).
## Strava import — input class (c) by construction (phone, engine ≥ 0.9.0)

`ios/…/Strava/StravaImport.swift` · docs/decisions.md ADR-023

`GET /activities/{id}/streams?keys=time,latlng,altitude,heartrate,velocity_smooth&key_by_type=true`
returns parallel arrays on one elapsed clock. Channel for channel that is what a GPX holds,
so the mapper **writes a GPX** and `GpxSessionParser` does the rest: no line of the import
decides a source class, marks a record uncertified or derives a speed, and a Strava session
and a converted GPX of the same afternoon analyse to the same numbers because after the
mapper they are the same file.

| what is read | from | notes |
|---|---|---|
| position | `latlng[i]` | `[lat, lon]`; a `[0, 0]` pair is the "no fix" sentinel and is dropped |
| time | `time[i]` | seconds from the activity start; the instant is `start_date + t` |
| altitude | `altitude[i]` | `<ele>`, feeds `turnBaroDrop` where the watch wrote a barometric value |
| heart rate | `heartrate[i]` | written as `gpxtpx:hr`, read back by the GPX parser's HR rule |
| clock | `utc_offset` / `timezone` | written into every `<time>` as `+02:00`, so the offset ladder's rung 1 applies |

**`velocity_smooth` is fetched and discarded.** Strava computes it from the positions and
then smooths it, so it is not a measurement and the file cannot prove one; carrying it beside
the engine's own positional derivation would put two differently-filtered answers in the same
column, which is the disagreement the GPX rule above exists to prevent. `hasSpeed` is
therefore false, `source_class` is `c`, and every surface marks these speed records
**uncertified** (docs/presentation.md).

**Pauses.** Strava's `time` is *elapsed*, so a paused recording is a jump in it. A jump over
**10 s** starts a new `<trkseg>`, which `filters.clean` ORs into its dt-aware gap rule — the
same threshold and the same argument as `HealthImport.gapThresholdS`, and for the case the dt
rule alone cannot see once Strava has thinned an old stream to 3–5 s per point.

No accelerometer and no developer fields, exactly as for a GPX: `pumpEpisodes` empty, every
stroke count null, no watch summary and so no divergence check.

