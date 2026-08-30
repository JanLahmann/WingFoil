import Foundation
import Testing
@testable import WingFoilKit

/// Unit cover for the phase-2/3 engine: wind-axis classification, the turn spatial gate,
/// the accelerometer path, source-capability degradation and the divergence banner.
/// Cross-implementation agreement with the lab is asserted separately in `GoldenTests`.
@Suite struct Phase23Tests {

    // MARK: - Turn classification against a wind axis

    /// TWA is wrap180(cog − windFrom): a tack crosses head-to-wind, a jibe crosses dead
    /// downwind, and a sweep that crosses neither is a course change (docs/algorithms.md).
    @Test func classifiesTackJibeAndCourseChanges() {
        let north = WindEstimate(userDirDeg: 0)

        // 315° → 405° (= 45°): passes through 0, head to wind.
        #expect(TurnDetector.classify(cogIn: 315, cogOut: 405, wind: north).kind == .tack)
        // 135° → 225°: passes through 180, dead downwind.
        #expect(TurnDetector.classify(cogIn: 135, cogOut: 225, wind: north).kind == .jibe)
        // 45° → 135°: crosses neither, and turns away from the wind.
        #expect(TurnDetector.classify(cogIn: 45, cogOut: 135, wind: north).kind == .bearAway)
        // 135° → 45°: crosses neither, and turns toward the wind.
        #expect(TurnDetector.classify(cogIn: 135, cogOut: 45, wind: north).kind == .roundUp)
    }

    @Test func sideIsTheTackSailedBeforeTheTurn() {
        let north = WindEstimate(userDirDeg: 0)
        // Positive TWA = wind over the port bow.
        #expect(TurnDetector.classify(cogIn: 45, cogOut: 135, wind: north).side == "port")
        #expect(TurnDetector.classify(cogIn: 315, cogOut: 225, wind: north).side == "starboard")
    }

    /// Without a usable axis nothing is named — the low-confidence case is a plain "turn",
    /// never a guessed jibe.
    @Test func unusableWindLeavesTurnsUnclassified() {
        var weak = WindEstimate(userDirDeg: 0)
        weak.confidence = 0.2
        weak.usable = false
        let c = TurnDetector.classify(cogIn: 135, cogOut: 225, wind: weak)
        #expect(c.kind == .unclassified)
        #expect(c.side == "unknown")
        #expect(TurnDetector.classify(cogIn: 135, cogOut: 225, wind: nil).kind == .unclassified)
    }

    // MARK: - Spatial gate

    /// `turnMinArc` / `turnMinRadius`: a heading flip on the spot covers no water however
    /// wide its angle, so it is dropped — not counted as a rejected course change.
    @Test func spatialGateDropsPivotsAndKeepsCarvedTurns() {
        var config = TurnConfig()
        config.minArcM = 12
        config.minRadiusM = 6

        // The radius is *derived* from arc ÷ swept angle, so each case is one honest
        // geometry rather than an arc and a radius that could disagree.
        #expect(abs(TurnDetector.radius(arcM: 8, netDeg: 180) - 2.55) < 0.01)

        // Pivot on the spot: 8 m of water swept through a half turn.
        #expect(!TurnDetector.carved(arcM: 8, netDeg: 180, config))

        // Enough water, still pivoting: 30 m spent spinning through 430° is a 4 m radius.
        #expect(!TurnDetector.carved(arcM: 30, netDeg: 430, config))

        // A carved jibe: 44 m through 150° is a 16.8 m radius.
        #expect(TurnDetector.carved(arcM: 44, netDeg: 150, config))

        // Corpus-calibration anchor (docs/algorithms.md): the tightest genuine turn in the
        // three reference sessions measures arc 14.4 m / radius 8.7 m and must survive.
        #expect(TurnDetector.carved(arcM: 14.4, netDeg: 95, config))
        #expect(abs(TurnDetector.radius(arcM: 14.4, netDeg: 95) - 8.69) < 0.01)
    }

    // MARK: - Default turn type (the 180° prior)

    // docs/algorithms.md "Default turn type". Mirrors the block of the same name in
    // `lab/tests/test_wind.py`: the blend is exercised twice over, as pure arithmetic and
    // end to end on a constructed track.

    /// The geometric fact the whole prior rests on, asserted directly.
    @Test func flippingTheWind180SwapsEveryTackAndJibe() {
        let track = misreadConeTrack()
        let sweeps = TurnDetector.sweeps(track, flights: FlightSegmenter.segment(track),
                                         config: TurnConfig())
        #expect(sweeps.count == 12)
        for (cogIn, cogOut) in sweeps {
            let here = TurnDetector.classifySweep(cogIn: cogIn, cogOut: cogOut, dirDeg: 0).kind
            let there = TurnDetector.classifySweep(cogIn: cogIn, cogOut: cogOut, dirDeg: 180).kind
            #expect(Set([here, there]) == Set([TurnKind.tack, .jibe]))
        }
    }

    /// Only a sweep that is a tack-or-jibe under *both* ends of the axis may vote.
    @Test func turnTypeVotesIgnoreSweepsThatAreNotManeuversUnderBothEnds() {
        let jibe = (135.0, 225.0)       // crosses 180: jibe at wind-from 0, tack at 180
        let tack = (315.0, 405.0)       // crosses 0:   tack at wind-from 0, jibe at 180
        let bearAway = (45.0, 135.0)    // crosses neither end, whichever way the wind blows
        let sweeps = [jibe, jibe, jibe, tack, bearAway, bearAway]

        #expect(WindEstimator.turnTypeVotes(sweeps, coneDir: 0, defaultTurnType: .jibes) == (3, 1))
        #expect(WindEstimator.turnTypeVotes(sweeps, coneDir: 0, defaultTurnType: .tacks) == (1, 3))
        // The other end of the axis names every voting sweep the opposite way.
        #expect(WindEstimator.turnTypeVotes(sweeps, coneDir: 180, defaultTurnType: .jibes) == (1, 3))
    }

    /// `e = eCone + w · mTurn`; the sign of `e` is the call, `|e|` clipped is the certainty.
    @Test func blendIsTheDocumentedFormula() {
        let config = WindConfig()                       // turnPriorWeight 0.5

        // Weak cone (0.2), unanimous majority against it: 0.2 − 0.5 = −0.3 ⇒ flip.
        let flipped = WindEstimator.blend(eCone: 0.2, nDefault: 0, nOther: 10, coneDir: 90,
                                          config: config)
        #expect(flipped.flipped)
        #expect(abs(flipped.certainty - 0.3) < 1e-9)
        #expect(abs(flipped.margin - 1.0) < 1e-9)
        #expect(flipped.favouredDeg == 270)
        #expect(flipped.votes == 10)

        // The same cone with the majority behind it: 0.2 + 0.5 = 0.7, and it keeps its pick.
        let agreed = WindEstimator.blend(eCone: 0.2, nDefault: 10, nOther: 0, coneDir: 90,
                                         config: config)
        #expect(!agreed.flipped)
        #expect(abs(agreed.certainty - 0.7) < 1e-9)
        #expect(agreed.favouredDeg == 90)

        // 0.5 is exactly the weight, so a unanimous majority cannot quite overturn it.
        #expect(!WindEstimator.blend(eCone: 0.5, nDefault: 0, nOther: 10, coneDir: 90,
                                     config: config).flipped)

        // A 60/40 split moves 0.2 by 0.5 × 0.2 = 0.1, not enough to flip a 0.2 cone.
        let narrow = WindEstimator.blend(eCone: 0.2, nDefault: 4, nOther: 6, coneDir: 90,
                                         config: config)
        #expect(!narrow.flipped)
        #expect(abs(narrow.certainty - 0.1) < 1e-9)
        #expect(abs(narrow.margin - 0.2) < 1e-9)
        #expect(narrow.favouredDeg == 270)
    }

    @Test func evenSplitAndEmptyElectorateContributeNothing() {
        let config = WindConfig()
        for prior in [WindEstimator.blend(eCone: 0.3, nDefault: 5, nOther: 5, coneDir: 90,
                                          config: config),
                      WindEstimator.blend(eCone: 0.3, nDefault: 0, nOther: 0, coneDir: 90,
                                          config: config)] {
            #expect(abs(prior.certainty - 0.3) < 1e-9)   // the bare cone factor
            #expect(!prior.flipped)
            #expect(prior.margin == 0)
            #expect(prior.favouredDeg == nil)
        }
    }

    /// The motivating case: the cone cannot tell, and "I mostly jibe" decides.
    ///
    /// `fullMargin` is raised to 3.0 to say the cone's 0.6 asymmetry is *not* certain —
    /// which is exactly what that parameter means. The twelve sweeps are tacks under the
    /// cone's pick and jibes under the other end, so a rider who declares "jibes" turns the
    /// call over. `minConfidence` is dropped so the labels are readable on both sides of the
    /// flip: the point is *which* wind was chosen, not whether it clears the shipped bar.
    @Test func weakConeAndAJibeMajorityFlipsThe180Call() throws {
        let track = misreadConeTrack()
        let flights = FlightSegmenter.segment(track)
        var config = WindConfig()
        config.fullMargin = 3.0
        config.minConfidence = 0.1

        var balanced = config
        balanced.defaultTurnType = .balanced
        let coneOnly = try #require(WindEstimator.estimate(track, flights: flights,
                                                           config: balanced))
        #expect(abs(WindEstimator.wrap180(coneOnly.dirDeg)) < 5)
        #expect(TurnDetector.summarize(TurnDetector.detect(track, flights: flights,
                                                           wind: coneOnly)).tacks == 12)

        let est = try #require(WindEstimator.estimate(track, flights: flights,
                                                      config: config))   // .jibes
        #expect(est.priorFlipped)
        #expect(abs(WindEstimator.wrap180(est.dirDeg - 180)) < 5)
        #expect(est.turnTypeVotes == 12)
        #expect(abs(est.turnTypeMargin - 1.0) < 1e-9)
        #expect(abs(WindEstimator.wrap180((est.turnTypeDirDeg ?? .nan) - est.dirDeg)) < 1e-9)
        // e = 0.598/3 − 0.5 = −0.301, and the labels follow the wind that was chosen.
        #expect(abs(est.confidence - est.axisConfidence * 0.301) < 0.01)
        #expect(TurnDetector.summarize(TurnDetector.detect(track, flights: flights,
                                                           wind: est)).jibes == 12)

        // The declared habit pointing *with* the cone leaves the call alone, only raising it.
        var tacks = config
        tacks.defaultTurnType = .tacks
        let agreeing = try #require(WindEstimator.estimate(track, flights: flights,
                                                           config: tacks))
        #expect(!agreeing.priorFlipped)
        #expect(agreeing.dirDeg == coneOnly.dirDeg)
        #expect(agreeing.confidence > coneOnly.confidence)
    }

    /// At the shipped `fullMargin` the same session's cone is certain, so nothing moves.
    @Test func aDecisiveConeIsUntouchableByThePrior() throws {
        let track = misreadConeTrack()
        let flights = FlightSegmenter.segment(track)
        let est = try #require(WindEstimator.estimate(track, flights: flights))
        #expect(est.ambiguityMargin > WindConfig().fullMargin)
        #expect(!est.priorFlipped)
        #expect(est.turnTypeVotes == 0)
        #expect(est.turnTypeMargin == 0)
        #expect(est.turnTypeDirDeg == nil)
        #expect(TurnDetector.summarize(TurnDetector.detect(track, flights: flights,
                                                           wind: est)).tacks == 12)
        // … and it is the *same* estimate the prior-free engine produces, field for field.
        var balanced = WindConfig()
        balanced.defaultTurnType = .balanced
        #expect(est == WindEstimator.estimate(track, flights: flights, config: balanced))
    }

    /// `balanced` is the engine as it was: confidence = axis confidence × cone certainty.
    @Test func balancedReproducesThePreProriorConfidence() throws {
        let track = misreadConeTrack()
        let flights = FlightSegmenter.segment(track)
        for fullMargin in [0.4, 3.0] {
            var config = WindConfig()
            config.fullMargin = fullMargin
            config.defaultTurnType = .balanced
            let est = try #require(WindEstimator.estimate(track, flights: flights,
                                                          config: config))
            let expected = est.axisConfidence * min(est.ambiguityMargin / fullMargin, 1)
            #expect(abs(est.confidence - expected) < 1e-12)
            #expect(est.turnTypeVotes == 0)
            #expect(est.turnTypeDirDeg == nil)
        }
    }

    /// A session the no-go cone reads one way and the turn types read the other.
    ///
    /// Two reaches at COG 100 and 260 with every transit taken through 0 (so each sweep
    /// crosses one end of the axis, never the other), plus a long straight leg at 180
    /// entered and left at 4°/s — too slow for `turnPeakRate`, so it adds cone mass without
    /// adding a turn. That 180 leg is what makes the cone pick the *other* end than the
    /// sweeps do: the cone lands on ~0, under which all twelve sweeps are tacks, while a
    /// rider who declares "mostly jibes" is pointing at ~180.
    /// Mirrors `_misread_cone_track()` in `lab/tests/test_wind.py`.
    private func misreadConeTrack() -> CleanTrack {
        enum Step { case hold(Double, Int), turn(Double, Double) }
        var steps: [Step] = [.hold(100, 60)]
        for _ in 0..<6 {
            steps += [.turn(-100, 30), .hold(-100, 60), .turn(100, 30), .hold(100, 60)]
        }
        steps += [.turn(180, 4), .hold(180, 120), .turn(100, 4), .hold(100, 60)]

        var cog: [Double] = []
        var cur = 0.0
        for step in steps {
            switch step {
            case let .hold(deg, seconds):
                cur = deg
                cog += Array(repeating: deg, count: seconds)
            case let .turn(target, rate):
                let n = Int(abs(target - cur) / rate)
                for k in 0..<n { cog.append(cur + (target - cur) * Double(k) / Double(n)) }
                cur = target
            }
        }
        return courseTrack(cog, speedMps: 6)
    }

    /// A `CleanTrack` sailed at a constant speed along the given per-second unwrapped COG,
    /// with the local-metre frame integrated straight from the course (the Swift twin of the
    /// lab's `clean_from_arrays`).
    private func courseTrack(_ cogDeg: [Double], speedMps: Double) -> CleanTrack {
        var track = CleanTrack()
        var x = 0.0, y = 0.0, dist = 0.0
        for (i, deg) in cogDeg.enumerated() {
            track.samples.append(CleanSample(t: Double(i), dt: i == 0 ? 0 : 1, gapBefore: false,
                                             x: x, y: y, dopplerMps: speedMps,
                                             positionalMps: speedMps, cumDistM: dist))
            x += sin(deg * .pi / 180) * speedMps
            y += cos(deg * .pi / 180) * speedMps
            dist += speedMps
        }
        track.segments = [0..<track.samples.count]
        track.medianDtS = 1
        track.gapThresholdS = 3
        track.spanS = Double(cogDeg.count - 1)
        track.timerTimeS = Double(cogDeg.count - 1)
        return track
    }

    /// Below `turnCogSpeedFloor` the COG is position noise, so those samples never form a
    /// geometry run — and a run needs at least 3 samples.
    @Test func sailingRunsNeedThreeConsecutiveSamples() {
        let runs = TurnDetector.sailingRuns([false, true, true, false,
                                             true, true, true, true, false, true])
        #expect(runs.count == 1)
        #expect(runs[0] == (4, 7))
    }

    // MARK: - Pump detection

    /// A clean 1 Hz oscillation inside the 0.5–2.5 Hz band is picked as one stroke per
    /// cycle; a 5 Hz chop of the same amplitude is rejected by the band-pass.
    @Test func pumpBandPassSeparatesPumpingFromChop() throws {
        func track(hz: Double, amplitudeG: Double) -> PumpTrack? {
            var t: [Double] = []
            var mag: [Double] = []
            for i in 0..<10_000 {                       // 100 Hz for 100 s
                let time = Double(i) / 100
                t.append(time)
                mag.append(1.0 + amplitudeG * sin(2 * .pi * hz * time))
            }
            return PumpAnalyzer.track(times: t, magnitudes: mag)
        }

        let pumping = try #require(track(hz: 1.0, amplitudeG: 0.6))
        let strokes = pumping.strokes(from: 10, to: 90)
        #expect(strokes.count >= 70 && strokes.count <= 85)   // ~1 per second
        #expect(pumping.isPumping(from: 10, to: 30))

        let chop = try #require(track(hz: 5.0, amplitudeG: 0.6))
        #expect(chop.strokes(from: 10, to: 90).isEmpty)
        #expect(!chop.isPumping(from: 10, to: 90))
    }

    /// `pumpStrokeMaxInterval` splits efforts: two clusters a long silence apart are two
    /// bursts, and `pumpMinStrokes` decides which of them counts as pumping.
    @Test func burstsSplitOnSilence() {
        let strokes = [0.0, 0.9, 1.8, 2.7, 20.0, 20.9]
        let bursts = PumpAnalyzer.groupBursts(strokes, maxIntervalS: 1.5)
        #expect(bursts.count == 2)
        #expect(bursts[0].count == 4)
        #expect(bursts[1].count == 2)
    }

    // MARK: - Accelerometer decoding

    /// The sanitizer strips `accelerometer_data` before the C decoder, so the stream has to
    /// come off the original bytes — this asserts it actually arrives, on the record clock,
    /// with the milli-g scale sniffed away.
    @Test func decodesTheSensorLoggingAccelStream() throws {
        let stem = "2026-08-07-0754_nago-torbole-windsurfen_ciq"
        guard let url = findFixtureFIT(stem: stem) else { return }   // fixture-optional
        let raw = try FitSessionParser.parse(url: url)

        #expect(raw.capabilities.hasAccel)
        #expect(raw.accel.count > 100_000, "expected the ~100 Hz stream, got \(raw.accel.count)")
        // Resting magnitude is ~1 g once the milli-g scale is undone.
        let median = Evidence.median(raw.accel.map(\.magnitudeG))
        #expect(abs(median - 1.0) < 0.3, "magnitude median \(median) is not in g")
        // Time-sorted and on the record time base (the first record is t = 0).
        #expect(zip(raw.accel, raw.accel.dropFirst()).allSatisfy { $0.t <= $1.t })
        #expect(abs(raw.accel[0].t) < 60)
        #expect(PumpAnalyzer.track(raw) != nil)
    }

    /// A source with no accelerometer must degrade, not fail: speed-only takeoff runs, nil
    /// stroke counts, and a nil success rate rather than a flattering 100 %.
    @Test func sourcesWithoutAccelDegradeInsteadOfFailing() {
        let analysis = SessionSummarizer.analyze(syntheticFlightTrack())
        #expect(analysis.capabilities.hasAccel == false)
        #expect(analysis.flights.count == 1)
        #expect(analysis.takeoffs.count == 1)
        #expect(analysis.takeoffs[0].pumps == nil)
        #expect(analysis.takeoffs[0].inFlightStrokes == nil)
        #expect(analysis.flights[0].takeoffPumps == nil)
        #expect(analysis.summary.takeoff.successPct == nil)
        #expect(analysis.summary.takeoff.totalPumpStrokes == nil)
        #expect(analysis.summary.takeoff.takeoffSuccesses == 1)
        // The speed-only half of the run is still measured.
        #expect(analysis.takeoffs[0].speedRiseS > 0)
    }

    /// No barometer ⇒ no submersion evidence, and an all-nil altitude channel must not
    /// make every sample look submerged.
    @Test func missingBarometerYieldsNoSubmersionEvidence() {
        let none = Evidence.submergedMask([nil, nil, nil], dropM: 25)
        #expect(none == [false, false, false])
        // With a channel, only a sample far below the median counts.
        let some = Evidence.submergedMask([100, 101, 99, -200], dropM: 25)
        #expect(some == [false, false, false, true])
    }

    // MARK: - Shared off-foil evidence

    /// The whole-track `OffFoilEvidence` is built once per session and handed to both the
    /// turn ladder and the flight-end ladder. Sharing it is an efficiency change only:
    /// every turn and every flight end must come out bit-identical to the version where
    /// each stage built its own copy.
    @Test func sharedEvidenceMatchesPerStageBuilds() throws {
        let url = try #require(allFixtureFITs().first {
            $0.lastPathComponent.contains("2026-08-05-0827")
        }, "no 2026-08-05-0827 fixture")
        let raw = try FitSessionParser.parse(url: url)
        let clean = TrackCleaner.clean(raw)
        let flights = FlightSegmenter.segment(clean)
        let wind = WindEstimator.estimate(clean, flights: flights)
        let pump = PumpAnalyzer.track(raw)
        let shared = try #require(Evidence.build(clean, flights: flights,
                                                 exitSpeedKmh: TurnConfig().foilExitSpeedKmh,
                                                 baroDropM: TurnConfig().baroDropM))

        let ownTurns = TurnDetector.detect(clean, flights: flights, wind: wind, pump: pump)
        let sharedTurns = TurnDetector.detect(clean, flights: flights, wind: wind, pump: pump,
                                              evidence: shared)
        #expect(!sharedTurns.isEmpty, "the fixture must actually produce turns")
        #expect(sharedTurns == ownTurns)

        let ownEnds = FlightEndClassifier.classify(clean, flights: flights, turns: ownTurns,
                                                   pump: pump)
        let sharedEnds = FlightEndClassifier.classify(clean, flights: flights,
                                                      turns: sharedTurns, pump: pump,
                                                      evidence: shared)
        #expect(!sharedEnds.isEmpty)
        #expect(sharedEnds == ownEnds)
    }

    // MARK: - Turn streaks

    /// Counted turns carrying only what a streak reads: end time and outcome. End times are
    /// 10, 20, 30 … so a flight end can be dropped between any two of them.
    private func streakTurns(_ outcomes: [TurnOutcome],
                             counted: [Bool]? = nil) -> [Turn] {
        let flags = counted ?? Array(repeating: true, count: outcomes.count)
        return outcomes.enumerated().map { i, outcome in
            let end = 10.0 * Double(i + 1)
            return Turn(startT: end - 1, endT: end, minT: end,
                        kind: flags[i] ? .jibe : .bearAway, netDeg: 180, peakRateDegS: 30,
                        direction: "port", side: "port", entryKn: 12, minKn: 9,
                        entryKnDoppler: 12, minKnDoppler: 9, score: 0.75, success: true,
                        twaInDeg: 90, twaOutDeg: -90, outcome: outcome)
        }
    }

    /// A flight end at `t`; `owner` is an index into the turn list, as the classifier sets it.
    private func streakEnd(_ t: Double, _ outcome: FlightEndOutcome,
                           owner: Int? = nil, truncated: Bool = false) -> FlightEnd {
        var end = FlightEnd(flightIndex: 0, t: t, outcome: outcome)
        end.truncated = truncated
        end.ownedByTurn = owner
        return end
    }

    /// docs/algorithms.md "Turn streaks": dry counts staying out of the water, so a
    /// touchdown extends it; flew is the strict run and a touchdown resets it too.
    @Test func touchdownExtendsDryButBreaksFlew() {
        let s = TurnDetector.streaks(streakTurns([.flewThrough, .touchdown, .flewThrough]))
        #expect(s.dry == 3)
        #expect(s.flew == 1)
    }

    @Test func aFallResetsBothStreaksAndTheLongestRunWins() {
        let s = TurnDetector.streaks(
            streakTurns([.flewThrough, .flewThrough, .flewThrough, .fellIn, .flewThrough]))
        #expect(s.dry == 3)
        #expect(s.flew == 3)
    }

    /// A bear-away is not a maneuver, so *as a turn* it is invisible either way.
    @Test func rejectedSweepsAreInvisibleToStreaksAsTurns() {
        let bridged = TurnDetector.streaks(
            streakTurns([.flewThrough, .fellIn, .flewThrough], counted: [true, false, true]))
        #expect(bridged.dry == 2)
        #expect(bridged.flew == 2)

        let notLengthened = TurnDetector.streaks(
            streakTurns([.flewThrough, .flewThrough, .flewThrough],
                        counted: [true, false, true]))
        #expect(notLengthened.dry == 2)
        #expect(notLengthened.flew == 2)
    }

    /// The bug the first cut of this metric had: a swim between two clean jibes that the
    /// turn channel cannot see, because the rider simply fell in on a reach.
    @Test func aStraightLineFallInsideAFlownRunBreaksIt() {
        let turns = streakTurns([.flewThrough, .flewThrough, .flewThrough, .flewThrough])
        #expect(TurnDetector.streaks(turns) == (4, 4))          // blind to it

        let broken = TurnDetector.streaks(turns, ends: [streakEnd(25, .fellIn)])
        #expect(broken.dry == 2)
        #expect(broken.flew == 2)
    }

    /// The sweep is not a maneuver; the swim it ended is still a swim.
    @Test func aFallOwnedByARejectedSweepBreaksTheStreak() {
        let turns = streakTurns([.flewThrough, .fellIn, .flewThrough, .flewThrough],
                                counted: [true, false, true, true])
        let owned = TurnDetector.streaks(turns, ends: [streakEnd(21, .fellIn, owner: 1)])
        #expect(owned.dry == 2)
        #expect(owned.flew == 2)
        #expect(TurnDetector.streaks(turns) == (3, 3))          // without the end
    }

    /// An end a counted turn owns is already spoken for by that turn's own outcome.
    @Test func anEndOwnedByACountedTurnIsNotChargedTwice() {
        let turns = streakTurns([.flewThrough, .fellIn, .flewThrough, .flewThrough])
        #expect(TurnDetector.streaks(turns, ends: [streakEnd(21, .fellIn, owner: 1)])
                    == TurnDetector.streaks(turns))
        #expect(TurnDetector.streaks(turns) == (2, 2))
    }

    /// He got wet without swimming: the dry run survives, the clean run does not.
    @Test func aStraightLineTouchdownBreaksFlewButNotDry() {
        let s = TurnDetector.streaks(
            streakTurns([.flewThrough, .flewThrough, .flewThrough]),
            ends: [streakEnd(15, .touchdown)])
        #expect(s.dry == 3)
        #expect(s.flew == 2)
    }

    @Test func glideOutsUnknownsAndTruncatedEndsChangeNothing() {
        let turns = streakTurns([.flewThrough, .flewThrough, .flewThrough])
        let harmless = [streakEnd(15, .glideOut), streakEnd(15, .unknown),
                        streakEnd(15, .unknown, truncated: true),
                        // A stopped recording says nothing about the rider.
                        streakEnd(15, .fellIn, truncated: true)]
        for end in harmless {
            #expect(TurnDetector.streaks(turns, ends: [end]) == (3, 3), "\(end.outcome)")
        }
        // Only a maneuver the rider carried can add to a streak.
        #expect(TurnDetector.streaks(streakTurns([.flewThrough, .flewThrough]),
                                     ends: [5, 15, 25, 35].map { streakEnd($0, .glideOut) })
                    == (2, 2))
    }

    /// Events merge by time, not by list order.
    @Test func eventsMergeInTimeOrderAndAreZeroWhenEmpty() {
        var turns = streakTurns([.fellIn, .flewThrough, .flewThrough])
        turns.reverse()
        #expect(TurnDetector.streaks(turns) == (2, 2))
        #expect(TurnDetector.streaks(turns, ends: [streakEnd(25, .fellIn)]) == (1, 1))

        #expect(TurnDetector.streaks([]) == (0, 0))
        #expect(TurnDetector.streaks([], ends: [streakEnd(5, .glideOut)]) == (0, 0))
        #expect(TurnDetector.streaks(
            streakTurns([.flewThrough, .flewThrough], counted: [false, false])) == (0, 0))
    }

    @Test func summaryCarriesTheStreaks() {
        let s = TurnDetector.summarize(
            streakTurns([.flewThrough, .touchdown, .flewThrough, .fellIn, .flewThrough]),
            ends: [streakEnd(15, .glideOut)])
        #expect(s.turnsCounted == 5)
        #expect(s.longestDryStreak == 3)
        #expect(s.longestFlewStreak == 1)
    }


    // MARK: - Divergence check

    @Test func divergenceBannerFiresOnlyPastTheThresholds() {
        var analysis = SessionSummarizer.analyze(syntheticFlightTrack())
        analysis.summary.foilTimeS = 1000
        analysis.records.best2sKn = 20.0
        analysis.summary.flightCount = 10

        var agreeing = WatchSummary()
        agreeing.foilTimeS = 1030                      // +3 % — inside 5 %
        agreeing.best2sMps = 20.2 / Units.mpsToKn      // +0.2 kn — inside 0.3
        agreeing.flightCount = 11                      // ±1 — inside the count threshold
        #expect(DivergenceCheck.compare(watch: agreeing, phone: analysis).isEmpty)

        var diverging = WatchSummary()
        diverging.foilTimeS = 800                      // −20 %
        diverging.best2sMps = 19.0 / Units.mpsToKn     // −1.0 kn
        diverging.flightCount = 14                     // +4
        let found = DivergenceCheck.compare(watch: diverging, phone: analysis)
        #expect(Set(found.map(\.metric)) == ["Foil time", "Best 2 s", "Flights"])

        // Nothing to compare on a source without our session dev fields.
        #expect(DivergenceCheck.compare(watch: WatchSummary(), phone: analysis).isEmpty)
    }

    /// A `0`/`0` turn pair with no `wind_dir_user` means the watch could not classify, not
    /// that it saw no turns — docs/fit-schema.md. Reading it literally produced banners like
    /// "Jibes: watch 0 vs phone 50" on a session of fifty clean jibes.
    @Test func unclassifiedTurnCountsDoNotDiverge() {
        var analysis = SessionSummarizer.analyze(syntheticFlightTrack())
        analysis.summary.turns.tacks = 4
        analysis.summary.turns.jibes = 50

        /// Fixture-shaped session dev fields: the watch always writes these.
        func session(tacks: Int, jibes: Int, windDeg: Double?,
                     autoDeg: Double? = nil) -> [String: FitDevValue] {
            var d: [String: FitDevValue] = [
                "discipline": .text("wingfoil"), "foil_time": .number(2439),
                "foil_pct": .number(58), "flight_count": .number(23),
                "tack_count": .number(Double(tacks)), "jibe_count": .number(Double(jibes)),
            ]
            if let windDeg { d["wind_dir_user"] = .number(windDeg) }
            if let autoDeg { d["wind_dir_auto"] = .number(autoDeg) }
            return d
        }

        // No wind axis ⇒ the pair is absent, so neither metric is comparable at all.
        let noWind = FitSessionParser.watchSummary(session(tacks: 0, jibes: 0, windDeg: nil))
        #expect(noWind.tackCount == nil)
        #expect(noWind.jibeCount == nil)
        #expect(!noWind.isEmpty)                       // the rest of the summary still stands
        let quiet = DivergenceCheck.compare(watch: noWind, phone: analysis)
        #expect(!quiet.contains { $0.metric == "Tacks" || $0.metric == "Jibes" })

        // Same zeros *with* a wind axis: the watch really did count none, so it compares.
        let withWind = FitSessionParser.watchSummary(session(tacks: 0, jibes: 0, windDeg: 200))
        #expect(withWind.tackCount == 0)
        #expect(withWind.jibeCount == 0)
        let loud = DivergenceCheck.compare(watch: withWind, phone: analysis)
        #expect(Set(loud.map(\.metric)).isSuperset(of: ["Tacks", "Jibes"]))

        // And the demotion is narrow: one non-zero count means the axis was set after all.
        let oneSided = FitSessionParser.watchSummary(session(tacks: 3, jibes: 0, windDeg: nil))
        #expect(oneSided.tackCount == 3)
        #expect(oneSided.jibeCount == 0)
        #expect(DivergenceCheck.compare(watch: oneSided, phone: analysis)
                    .contains { $0.metric == "Jibes" })

        // Device app ≥ 0.9.0 (docs/fit-schema.md session 44): the watch can estimate the axis
        // itself. That is an axis too, so an *estimated* session's 0/0 is a real observation
        // and must still compare — the demotion asks "was anything classified", not "did the
        // rider type a bearing".
        let auto = FitSessionParser.watchSummary(
            session(tacks: 0, jibes: 0, windDeg: nil, autoDeg: 200))
        #expect(auto.windDirUserDeg == nil)
        #expect(auto.windDirAutoDeg == 200)
        #expect(auto.tackCount == 0)
        #expect(auto.jibeCount == 0)
        #expect(Set(DivergenceCheck.compare(watch: auto, phone: analysis).map(\.metric))
                    .isSuperset(of: ["Tacks", "Jibes"]))

        // Both fields present: the rider set an axis part-way through a session the watch had
        // already estimated. Neither displaces the other.
        let both = FitSessionParser.watchSummary(
            session(tacks: 2, jibes: 9, windDeg: 225, autoDeg: 200))
        #expect(both.windDirUserDeg == 225)
        #expect(both.windDirAutoDeg == 200)

        // 65535 is the schema's "this source had none" sentinel, not a bearing — and a
        // session that writes it for BOTH is the no-axis case the demotion exists for.
        let sentinel = FitSessionParser.watchSummary(
            session(tacks: 0, jibes: 0, windDeg: 65535, autoDeg: 65535))
        #expect(sentinel.windDirUserDeg == nil)
        #expect(sentinel.windDirAutoDeg == nil)
        #expect(sentinel.tackCount == nil)
        #expect(sentinel.jibeCount == nil)
    }

    // MARK: - Helpers

    /// 1 Hz, one clear flight, no position/accel/altitude channel.
    private func syntheticFlightTrack() -> RawTrack {
        var raw = RawTrack()
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        for t in stride(from: 0.0, through: 200, by: 1) {
            var s = RecordSample(t: t, timestamp: epoch.addingTimeInterval(t))
            switch t {
            case ..<40: s.speedMps = 0.5                     // sitting on the board
            case 40..<50: s.speedMps = 0.5 + (t - 40) * 0.6  // the rise
            case 50...140: s.speedMps = 6.5                  // flying
            default: s.speedMps = 0.4
            }
            raw.samples.append(s)
        }
        raw.capabilities.hasSpeed = true
        raw.capabilities.sampleRateHz = 1
        return raw
    }
}
