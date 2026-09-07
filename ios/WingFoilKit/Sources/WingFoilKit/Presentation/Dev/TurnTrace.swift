import Foundation

/// **"Why this verdict" — the outcome ladder's working, step by step, on the turn's own clock.**
///
/// The turn page has always printed the *answer*: flew through, 74 %, stopped 0 s. When a
/// verdict looks wrong the next question is always the same one — *which sample decided that?*
/// — and until now the only way to ask it was to add a print statement and rebuild. This is
/// that question, answered from the stored analysis and the archived track, with every step
/// timed in seconds from the sweep's start so the reader can put a finger on the strip above.
///
/// **It re-derives; it never re-decides.** Each step is computed from the same channels the
/// engine read (`TurnWorkbench.Context`) with the same primitives (`Evidence.offFoilRun`,
/// `Evidence.longestStop`, `TurnDetector.windowEnd`), and then *compared* with what the record
/// says. Where the two disagree the step prints both and is marked — that disagreement is the
/// most informative thing this page can produce, and hiding it would defeat the whole exercise.
/// The commonest honest cause is an analysis stored before a config field was echoed, which is
/// why `TurnWorkbench.Context.assumedDefaults` is carried onto the trace as its own note.
///
/// Contract: docs/algorithms.md "Turn outcome" steps 0–5, and the clean rule in
/// `TurnDetector.cleanVerdict`. Presentation: docs/presentation.md, "Dev workbench".
public struct TurnTrace: Sendable, Equatable {

    /// What a step's re-derivation had to say about the record beside it.
    public enum Note: Sendable, Equatable {
        /// Nothing to compare, or the two agree.
        case none
        /// The re-derived value and the stored one differ. Both are printed.
        case disagrees(derived: String, record: String)
        /// The step rests on a config value the stored echo did not carry, so
        /// `TurnConfig`'s published default was assumed. The parameter's own name.
        case assumed(String)
    }

    /// One rung of the ladder.
    public struct Step: Sendable, Equatable, Identifiable {
        public var id: Int
        /// "Outcome window", "Longest stop" — the thing being decided.
        public var title: String
        /// The sentence: what was found, and where.
        public var detail: String
        /// Seconds from the sweep's start, where the step has an instant. nil where it is a
        /// span or a verdict rather than a moment.
        public var atRt: Double?
        /// The parameter that fixed this step, named as docs/algorithms.md names it.
        public var rule: String?
        public var note: Note

        public init(id: Int, title: String, detail: String, atRt: Double? = nil,
                    rule: String? = nil, note: Note = .none) {
            self.id = id
            self.title = title
            self.detail = detail
            self.atRt = atRt
            self.rule = rule
            self.note = note
        }

        public var disagrees: Bool {
            if case .disagrees = note { return true }
            return false
        }
    }

    public var steps: [Step]
    /// Parameters the stored echo could not say, assumed at the published default.
    public var assumedDefaults: [String]

    public var disagreements: Int { steps.filter(\.disagrees).count }
    public var isEmpty: Bool { steps.isEmpty }
}

// MARK: - Building

public enum TurnTraceBuilder {

    /// Why the outcome window stopped where it did — the four ways `Evidence.recoveryEnd`
    /// can end, named.
    public enum WindowEndReason: Sendable, Equatable {
        /// Doppler held `turnRecoverPct` of the entry speed (floored at `foilEntrySpeed`)
        /// for `turnRecoverHold`.
        case recovered(thrKn: Double)
        /// Ran out at `turnOutcomeLookahead` past the sweep.
        case lookahead
        /// A recording gap; the samples the far side are not evidence about this one.
        case gap
        /// The recording itself ended.
        case trackEnd

        public var phrase: String {
            switch self {
            case .recovered(let thrKn):
                return String(format: "flying again — Doppler back to %.1f kn and held", thrKn)
            case .lookahead: return "the lookahead cap ran out"
            case .gap: return "a recording gap ended it"
            case .trackEnd: return "the recording ended"
            }
        }

        public var rule: String {
            switch self {
            case .recovered: return "turnRecoverPct · turnRecoverHold"
            case .lookahead: return "turnOutcomeLookahead"
            case .gap: return "gapMinS"
            case .trackEnd: return "—"
            }
        }
    }

    /// The whole trace for one counted turn, or an empty one where the session has no evidence.
    public static func trace(turnIndex: Int, analysis: SessionAnalysis,
                             context: TurnWorkbench.Context) -> TurnTrace {
        guard analysis.turns.indices.contains(turnIndex) else {
            return TurnTrace(steps: [], assumedDefaults: context.assumedDefaults)
        }
        let record = analysis.turns[turnIndex]
        guard let ev = context.evidence, ev.count > 0 else {
            return TurnTrace(steps: [Step(id: 0, title: "No evidence",
                                          detail: "This recording has no usable samples, so "
                                            + "the ladder had nothing to read and every turn "
                                            + "kept the flew-through default.")],
                             assumedDefaults: context.assumedDefaults)
        }
        let config = context.turn
        let assumed = Set(context.assumedDefaults)
        var steps: [Step] = []
        func add(_ title: String, _ detail: String, atRt: Double? = nil, rule: String? = nil,
                 note: TurnTrace.Note = .none) {
            steps.append(Step(id: steps.count, title: title, detail: detail, atRt: atRt,
                              rule: rule, note: note))
        }
        /// `.assumed` wins over `.none` where the rule this step rests on was not echoed.
        func noteFor(_ parameter: String, else other: TurnTrace.Note = .none) -> TurnTrace.Note {
            if case .none = other, assumed.contains(parameter) { return .assumed(parameter) }
            return other
        }
        func rt(_ t: Double) -> Double { t - record.ts }

        let headings = TurnWorkbench.headingSeries(context.clean, from: record.ts,
                                                   to: record.endTs, config: config)

        // 0. Entry window — where `entryKn` was read.
        let entryFrom = record.ts - config.entrySpeedWindowS
        let entryAt = ev.t.indices
            .filter { ev.t[$0] >= entryFrom && ev.t[$0] <= record.ts }
            .max { manoeuvreKn(context, $0) < manoeuvreKn(context, $1) }
        let derivedEntry = entryAt.map { manoeuvreKn(context, $0) }
        add("Entry window",
            String(format: "%.0f s before the sweep: fastest was %.1f kn",
                   config.entrySpeedWindowS, record.entryKn)
                + (entryAt.map { String(format: " at %+.0f s", rt(ev.t[$0])) } ?? ""),
            atRt: entryAt.map { rt(ev.t[$0]) },
            rule: "entrySpeedWindow",
            note: noteFor("entrySpeedWindow",
                          else: disagreement(derived: derivedEntry, record: record.entryKn,
                                             tolerance: 0.05, unit: "kn")))

        // 1. The sweep's end — the heading stopped turning.
        let endRate = headings?.rate(at: record.endTs)
        let sweepDetail = String(format: "the sweep ran %.0f s and turned %.0f°",
                                 max(record.endTs - record.ts, 0), abs(record.netDeg))
            + (endRate.map {
                String(format: "; the rate leaving it is %.1f °/s, under the %.0f °/s the sweep "
                       + "is trimmed at", abs($0), config.continueRateDegS)
            } ?? "; no heading series here — the run had no COG above turnCogSpeedFloor")
        add("Sweep end", sweepDetail, atRt: rt(record.endTs), rule: "turnContinueRate",
            note: noteFor("turnContinueRate"))

        // 2. The low point.
        add("Low point",
            String(format: "%.1f kn, searched to %.0f s past the sweep so it may sit after "
                   + "“out” (%.1f kn) — score %.0f %% of entry",
                   record.minKn, config.minSpeedLagS, record.exitKn, record.score * 100),
            atRt: rt(record.minTs), rule: "minSpeedLag · turnSuccessPct",
            note: noteFor("minSpeedLag"))

        // 3. Why the outcome window closed.
        let engineTurn = TurnWorkbench.turn(from: record)
        let (windowHi, reason) = windowEnd(engineTurn, ev: ev, config: config)
        let derivedWindowS = max(ev.t[windowHi] - record.endTs, 0)
        add("Outcome window",
            String(format: "closed %.0f s after the sweep — %@", derivedWindowS, reason.phrase),
            atRt: rt(ev.t[windowHi]), rule: reason.rule,
            note: noteFor("turnRecoverHold",
                          else: disagreement(derived: derivedWindowS,
                                             record: record.outcomeWindowS,
                                             tolerance: 0.5, unit: "s")))

        // 4. Off the foil, and for how long.
        let lo = min(searchSortedLeft(ev.t, record.ts), ev.count - 1)
        let win = lo..<max(lo, searchSortedRight(ev.t, ev.t[windowHi]))
        if let a = win.first(where: { !ev.flying[$0] }) {
            let (b, end) = Evidence.offFoilRun(t: ev.t, flying: ev.flying, a: a,
                                               capT: record.endTs + config.outcomeWindowS)
            let offFoilS = Evidence.elapsed(t: ev.t, gap: ev.gap, a: a, b: end)
            let stoppedS = Evidence.longestStop(t: ev.t, gap: ev.gap, v: ev.speed, a: a, b: b,
                                                floor: config.stopSpeedFloorMps)
            add("First off-foil sample",
                String(format: "%.1f kn on min(Doppler, positional) — off the foil for %.0f s",
                       ev.speed[a] * Units.mpsToKn, offFoilS),
                atRt: rt(ev.t[a]), rule: "foilExitSpeed",
                note: disagreement(derived: offFoilS, record: record.offFoilS,
                                   tolerance: 0.5, unit: "s"))
            add("Longest stop",
                String(format: "%.0f s below the %.1f m/s floor (touchdown up to %.1f s, "
                       + "a fall past %.1f s)", stoppedS, config.stopSpeedFloorMps,
                       config.touchdownMaxStopS, config.fallStopS),
                rule: "turnStopSpeedFloor · turnTouchdownMaxStop · turnFallStop",
                note: disagreement(derived: stoppedS, record: record.stoppedS,
                                   tolerance: 0.5, unit: "s"))
        } else {
            let marginal = win.contains { ev.speed[$0] < config.foilEntrySpeedKmh / Units.mpsToKmh }
            add("First off-foil sample",
                "none — every sample in the window was flying"
                    + (marginal
                       ? String(format: ", though the speed did go marginal (under %.1f km/h), "
                                + "which is what lets a pump burst demote it",
                                config.foilEntrySpeedKmh)
                       : ""),
                rule: "foilExitSpeed")
        }

        // 5. The pump burst.
        if let pump = context.pump {
            let burst = pump.longestBurst(from: record.ts, to: ev.t[windowHi])
            let derivedPumped = burst >= pump.config.minStrokes
            add("Pump burst",
                derivedPumped
                    ? "\(burst) strokes in a row inside the window — enough to corroborate a "
                        + "touchdown where the speed also went marginal"
                    : (burst > 0
                       ? "\(burst) strokes, short of the \(pump.config.minStrokes) a burst needs"
                       : "no strokes inside the window"),
                rule: "pumpMinStrokes",
                note: derivedPumped == record.pumped
                    ? .none
                    : .disagrees(derived: derivedPumped ? "pumped" : "not pumped",
                                 record: record.pumped ? "pumped" : "not pumped"))
        } else {
            add("Pump burst", "no accelerometer in this recording — the channel is absent, "
                + "which is not evidence that he did not pump", rule: "pumpMinStrokes")
        }

        // 6. The wrist under.
        if let under = win.first(where: { ev.submerged[$0] }) {
            add("Wrist under",
                String(format: "the barometer reads more than %.0f m below the session median "
                       + "— proof of water, and a fall outright", config.baroDropM),
                atRt: rt(ev.t[under]), rule: "turnBaroDrop",
                note: record.submerged ? .none : .disagrees(derived: "submerged",
                                                            record: "not submerged"))
        } else {
            add("Wrist under", "no submerged sample in the window", rule: "turnBaroDrop",
                note: record.submerged ? .disagrees(derived: "not submerged",
                                                    record: "submerged") : .none)
        }

        // 7. The axis crossing.
        if let axisTs = record.axisTs, let before = record.axisBeforeDeg,
           let after = record.axisAfterDeg {
            add("Wind axis",
                String(format: "through the axis · %.0f° before, %.0f° after",
                       before, after)
                    + (config.axisAfterDeg > 0
                       ? String(format: " (clean needs %.0f°)", config.axisAfterDeg) : ""),
                atRt: rt(axisTs), rule: "turnAxisBeforeDeg · turnAxisAfterDeg",
                note: noteFor("turnAxisAfterDeg", else: noteFor("turnAxisBeforeDeg")))
        } else {
            add("Wind axis", record.counted
                ? "no crossing recorded — this session has no wind axis the engine trusts"
                : "a course change crosses neither line, so there is no axis to measure",
                rule: "turnAxisBeforeDeg")
        }

        // 8. The quiet tail.
        if config.cleanQuietS > 0 {
            let quiet = quietTail(record, ev: ev, config: config, ends: context.ends)
            add("Quiet tail",
                String(format: "%.0f s after the sweep, %@: %@", config.cleanQuietS,
                       quiet.truncatedByGap ? "cut short by a gap" : "read to the end",
                       quiet.finding),
                atRt: quiet.atRt.map { $0 - record.ts }, rule: "turnCleanQuietS",
                note: noteFor("turnCleanQuietS",
                              else: quietDisagreement(quiet.block, record: record)))
        } else {
            add("Quiet tail", "off — turnCleanQuietS is 0, so nothing after the sweep is asked",
                rule: "turnCleanQuietS", note: noteFor("turnCleanQuietS"))
        }

        // 9. The two verdicts, and the rule that fixed each.
        let outcome = TurnOutcomeKind(record.outcome)
        add("Outcome", "\(outcome.label)\(record.borderline ? " (borderline)" : "") — "
            + outcomeReasonPhrase(record, config: config),
            rule: "turnFallStop · turnTouchdownMaxStop")
        add("Clean", cleanPhrase(record, config: config),
            rule: "turnSuccessPct · turnCleanQuietS")

        return TurnTrace(steps: steps, assumedDefaults: context.assumedDefaults)
    }

    private typealias Step = TurnTrace.Step

    // MARK: - The instrumented mirrors

    /// `Evidence.recoveryEnd`, with the break that fired named.
    ///
    /// Written out rather than called because the reason is the whole point of the step and the
    /// engine's version returns only an index — and it is checked against the engine's index in
    /// `TurnTraceTests`, so the mirror cannot drift silently.
    public static func windowEnd(_ turn: Turn, ev: OffFoilEvidence,
                                 config: TurnConfig) -> (index: Int, reason: WindowEndReason) {
        let lo = min(searchSortedLeft(ev.t, turn.startT), ev.count - 1)
        let thr = max(config.recoverPct / 100 * turn.entryKn / Units.mpsToKn,
                      config.foilEntrySpeedKmh / Units.mpsToKmh)
        let capT = turn.endT + config.outcomeLookaheadS
        var hi = lo, last = -1, held = 0.0, i = lo
        var reason = WindowEndReason.trackEnd
        while i < ev.count {
            if ev.t[i] > capT { reason = .lookahead; break }
            if i > lo, ev.gap[i] { reason = .gap; break }
            hi = i
            defer { i += 1 }
            if ev.t[i] <= turn.minT { continue }
            if ev.doppler[i] < thr { held = 0; last = -1; continue }
            held = last == i - 1 ? held + (ev.t[i] - ev.t[last]) : 0
            last = i
            if held >= config.recoverHoldS {
                reason = .recovered(thrKn: thr * Units.mpsToKn)
                break
            }
        }
        return (hi, reason)
    }

    /// What the quiet tail found, as a sentence — `TurnDetector.quietBlocked` with its working
    /// shown.
    public struct QuietTail: Sendable, Equatable {
        public var block: CleanBlock?
        public var finding: String
        /// The instant the tail was refused at, where there is one.
        public var atRt: Double?
        /// The tail ran into a recording gap before `turnCleanQuietS` was up.
        public var truncatedByGap: Bool
    }

    public static func quietTail(_ record: TurnRecord, ev: OffFoilEvidence, config: TurnConfig,
                                 ends: [FlightEnd]) -> QuietTail {
        let t = ev.t
        let lo = searchSortedLeft(t, record.endTs)
        guard lo < t.count else {
            return QuietTail(block: nil, finding: "no samples after the sweep", atRt: nil,
                             truncatedByGap: false)
        }
        let until = record.endTs + config.cleanQuietS
        var hi = lo, i = lo, truncated = false
        while i < t.count {
            if t[i] > until { break }
            if i > lo, ev.gap[i] { truncated = true; break }
            hi = i
            i += 1
        }
        let stopT = t[hi]

        if let end = ends.first(where: {
            !$0.truncated && ($0.outcome == .touchdown || $0.outcome == .fellIn)
                && $0.t >= record.endTs && $0.t <= stopT
        }) {
            return QuietTail(block: .quietFlightEnd,
                             finding: "flight \(end.flightIndex + 1) ended in a "
                                + "\(end.outcome == .fellIn ? "fall" : "touchdown")",
                             atRt: end.t, truncatedByGap: truncated)
        }
        i = lo
        while i <= hi {
            if ev.flying[i] { i += 1; continue }
            let (b, resume) = Evidence.offFoilRun(t: t, flying: ev.flying, a: i, capT: stopT)
            let spell = Evidence.elapsed(t: t, gap: ev.gap, a: i, b: b)
            if spell >= TurnDetector.cleanQuietOffFoilS {
                return QuietTail(block: .quietOffFoil,
                                 finding: String(format: "off the foil for %.0f s", spell),
                                 atRt: t[i], truncatedByGap: truncated)
            }
            i = max(resume, b + 1)
        }
        if let under = (lo...hi).first(where: { ev.submerged[$0] }) {
            return QuietTail(block: .quietSubmerged, finding: "the wrist went under",
                             atRt: t[under], truncatedByGap: truncated)
        }
        return QuietTail(block: nil,
                         finding: "no touchdown, no fall, no wrist under",
                         atRt: nil, truncatedByGap: truncated)
    }

    // MARK: - Phrasing

    /// The step that actually fixed the outcome, in the ladder's own order.
    static func outcomeReasonPhrase(_ record: TurnRecord, config: TurnConfig) -> String {
        switch TurnOutcomeKind(record.outcome) {
        case .fellIn:
            return record.submerged
                ? "the wrist went under, which is a fall whatever the stop measured"
                : String(format: "the stop ran %.0f s, past the %.1f s a fall starts at",
                         record.stoppedS, config.fallStopS)
        case .touchdown:
            if record.offFoilS == 0, record.pumped {
                return "he never left the foil, but the speed went marginal and he pumped a "
                    + "burst out of it"
            }
            return String(format: "off the foil, and the stop ran %.0f s — inside the %.1f s "
                          + "a fall starts at", record.stoppedS, config.fallStopS)
        case .flewThrough:
            return "no sample in the window was off the foil"
        }
    }

    static func cleanPhrase(_ record: TurnRecord, config: TurnConfig) -> String {
        guard record.counted, record.type == "jibe" else {
            return "not a counted jibe, so “clean” is not a verdict this turn can have"
        }
        if record.clean { return "clean" }
        if TurnOutcomeKind(record.outcome) != .flewThrough {
            return "not clean — it did not fly through"
        }
        if !record.success {
            if record.cleanBlockedBy == CleanBlock.axisAfter.rawValue {
                return String(format: "not clean — it carried less than %.0f° past the axis",
                              config.axisAfterDeg)
            }
            return String(format: "not clean — it held %.0f %% of entry, under the %.0f %% "
                          + "the score asks", record.score * 100, config.successPct)
        }
        switch record.cleanBlockedBy.flatMap(CleanBlock.init(rawValue:)) {
        case .quietFlightEnd: return "not clean — a flight end inside the quiet tail"
        case .quietOffFoil: return "not clean — off the foil inside the quiet tail"
        case .quietSubmerged: return "not clean — the wrist went under inside the quiet tail"
        case .axisAfter: return "not clean — too little carry past the axis"
        case nil: return "not clean, and the record gives no reason — which should not happen"
        }
    }

    // MARK: - Disagreement

    static func disagreement(derived: Double?, record: Double, tolerance: Double,
                             unit: String) -> TurnTrace.Note {
        guard let derived, derived.isFinite, record.isFinite else { return .none }
        guard abs(derived - record) > tolerance else { return .none }
        return .disagrees(derived: String(format: "%.1f %@", derived, unit),
                          record: String(format: "%.1f %@", record, unit))
    }

    static func quietDisagreement(_ block: CleanBlock?, record: TurnRecord) -> TurnTrace.Note {
        // Only meaningful where the record could carry a reason at all: the engine sets
        // `cleanBlockedBy` on a counted jibe whose score *and* outcome were good enough, and
        // leaves it nil everywhere else — so a nil there is silence, not a claim of "quiet".
        guard record.counted, record.type == "jibe", record.success,
              TurnOutcomeKind(record.outcome) == .flewThrough else { return .none }
        let stored = record.cleanBlockedBy
        guard block?.rawValue != stored else { return .none }
        return .disagrees(derived: block?.rawValue ?? "quiet", record: stored ?? "quiet")
    }
}

// MARK: - The engine type, back out of the record

extension TurnWorkbench {

    /// The engine's `Turn` rebuilt from a stored `TurnRecord`, for the primitives that take one.
    ///
    /// The two Doppler speeds are `.nan`: `TurnRecord` never carried them (they are scoring
    /// intermediates, not results), and a 0 there would be a number the record does not have.
    /// Nothing the workbench calls reads them — `TurnDetector.windowEnd` reads `startT`,
    /// `endT`, `minT` and `entryKn`; `cleanVerdict` reads the verdict fields — and a future
    /// caller that does will get a NaN rather than a plausible lie.
    static func turn(from record: TurnRecord) -> Turn {
        var turn = Turn(startT: record.ts, endT: record.endTs, minT: record.minTs,
                        kind: TurnKind(rawValue: record.type) ?? .unclassified,
                        netDeg: record.netDeg, peakRateDegS: record.peakRateDegS,
                        direction: record.direction, side: record.side,
                        entryKn: record.entryKn, minKn: record.minKn,
                        entryKnDoppler: .nan, minKnDoppler: .nan,
                        score: record.score, success: record.success,
                        twaInDeg: record.twaInDeg ?? .nan,
                        twaOutDeg: record.twaOutDeg ?? .nan)
        turn.exitKn = record.exitKn
        turn.axisT = record.axisTs ?? .nan
        turn.axisBeforeDeg = record.axisBeforeDeg ?? .nan
        turn.axisAfterDeg = record.axisAfterDeg ?? .nan
        turn.arcM = record.arcM
        turn.radiusM = record.radiusM
        turn.outcome = TurnOutcome(rawValue: record.outcome) ?? .flewThrough
        turn.borderline = record.borderline
        turn.offFoilS = record.offFoilS
        turn.stoppedS = record.stoppedS
        turn.pumped = record.pumped
        turn.submerged = record.submerged
        turn.outcomeWindowS = record.outcomeWindowS
        turn.clean = record.clean
        turn.cleanBlockedBy = record.cleanBlockedBy.flatMap(CleanBlock.init(rawValue:))
        return turn
    }
}

/// The maneuver channel at one evidence index — the channel the turn was scored on.
private func manoeuvreKn(_ context: TurnWorkbench.Context, _ index: Int) -> Double {
    context.clean.samples.indices.contains(index)
        ? context.clean.samples[index].hybridMps * Units.mpsToKn
        : 0
}
