import Foundation

/// **The presentation document** — every rider-facing fact of one session, emitted once.
///
/// The Swift twin of `lab/src/wingfoil_lab/presentation.py`, and the schema is
/// `docs/presentation/document.md` (ADR-033). The two produce **the same bytes** for every
/// corpus fixture, which `PresentationTests.presentationDocumentMatchesTheGoldenByte`
/// asserts against `fixtures/presentation/*.expected.json`'s `document` key.
///
/// Why it exists: the iPhone, the web, the share card, the widgets and the watch's summary
/// card each computed the same block, the same tally, the same record set and the same
/// callout sentence for themselves, in four languages, and the only thing keeping them
/// honest was a verifier re-deriving each one a third time. The facts are built once here;
/// a renderer formats them and decides layout, and nothing else.
///
/// Three rules, and they are what make it small:
///
/// * **No rider sentence.** Every word is an id into `docs/copy` (or into
///   `design/tokens.json`, which is copy for the record and layer names) plus the
///   arguments the sentence interpolates.
/// * **No formatted number.** A value is raw and carries a `unitKind`; the renderer
///   formats it through `Speed` / `KeyMetrics`, which is what lets one document serve a
///   rider reading knots and a rider reading km/h. **The speed unit is not an input.**
/// * **No colour value.** A cell carries a `colourRole` — a path into `design/tokens.json`
///   (`outcome.fellIn`, `phase.flying`) or the literal `neutral`.
///
/// The record *policy* **is** an input, as an argument: it is the rider's Settings choice
/// and it decides which records may stand (`SpeedRecordRule`). It is applied here, never
/// stored, exactly as every other surface applies it.
public enum PresentationDocument {

    /// Bumped when the shape changes in a way a renderer has to know about. Independent of
    /// `engineVersion`: the document is additive and no analysis number moved to add it.
    public static let version = 1

    /// The nine kinds, canonical order (`docs/presentation/records.md`).
    public static let recordKinds = RecordWindowSelection.catalogue

    /// `RowMetric.defaultTriple`, as keys.
    public static let defaultRowMetrics = RowMetric.defaultTriple.map(\.rawValue)

    /// Every metric a library row may be asked to draw, sorted — the document names them
    /// so the copy lint can see which labels a rider can reach.
    public static let offeredRowMetrics = RowMetric.allCases.map(\.rawValue).sorted()

    /// `ShareCardStats.Preset.leanKeys`, sorted so the document has one spelling of a set.
    public static let leanCardKeys = ShareCardStats.Preset.leanKeys.sorted()

    /// Keys that may never reach a card — real numbers the app shows in the tiles below
    /// the block, which on a card would be a second, quieter answer to "was that a good
    /// session". Sorted, for the same reason.
    public static let forbiddenCardKeys = ["best500m", "flightCount", "flights", "foilPct",
                                           "longestFlight", "wind"]

    /// `design/tokens.json` `layers`, in its order, with the token each chip is drawn in
    /// and the count it is live on. A line layer has no count.
    static let mapLayers: [(id: String, count: String?, colour: String)] = [
        ("flying", nil, "phase.flying"),
        ("offFoil", nil, "phase.offFoil"),
        ("effort", nil, "effort.window"),
        ("pumping", "pumping", "effort.pumping"),
        ("cleanJibe", "cleanJibe", "clean.jibe"),
        ("flewThrough", "flewThrough", "outcome.flew"),
        ("touchdown", "touchdown", "outcome.touchdown"),
        ("fellIn", "fellIn", "outcome.fellIn"),
        ("courseChange", "courseChange", "outcome.courseChange"),
        ("takeoff", "takeoff", "effort.takeoff"),
        ("splash", "splash", "effort.splash"),
        ("direction", nil, "direction.ink"),
    ]

    /// The rider's word for each kind of sweep, as an id into
    /// `docs/copy/presentation.json`'s `turnKind`.
    static func turnTypeID(_ raw: String) -> String {
        switch raw {
        case "jibe": "jibe"
        case "tack": "tack"
        case "bear_away": "bearAway"
        case "round_up": "roundUp"
        default: "turn"
        }
    }

    static func outcomeColour(_ layer: String) -> String {
        switch layer {
        case "touchdown": "outcome.touchdown"
        case "fellIn": "outcome.fellIn"
        case "courseChange": "outcome.courseChange"
        default: "outcome.flew"
        }
    }

    // MARK: - Rounding

    /// How many decimals a value of each unit kind carries — the lab's `DECIMALS`.
    static func decimals(_ unitKind: String) -> Int? {
        switch unitKind {
        case "speedKn", "distanceKm": 3
        case "distanceM", "durationS", "rate": 1
        case "seconds", "percent": 2
        case "score": 4
        // The wrist-under callout names whole seconds ("Wrist under · 4 s"), so the
        // argument is rounded here rather than by whichever renderer prints it.
        case "roundedSeconds": 0
        default: nil
        }
    }

    /// Round for the document, the way both implementations round: scale, round half to
    /// even on the scaled double, divide. Python's `round(x * 10**n) / 10**n` is the same
    /// operation on the same bits.
    ///
    /// `-0.0` becomes `0.0` — "−0 must never appear" (`docs/presentation/labels.md`).
    static func round(_ value: Double?, _ decimals: Int?) -> Double? {
        guard let value else { return nil }
        guard let decimals else { return value }
        let scale = pow(10.0, Double(decimals))
        let out = (value * scale).rounded(.toNearestOrEven) / scale
        return out == 0 ? 0 : out
    }

    static func number(_ value: Double?, _ unitKind: String) -> PresentationValue {
        guard let out = round(value, decimals(unitKind)) else { return .null }
        return .number(out)
    }

    // MARK: - The door

    /// Every presentation fact of one session, once.
    ///
    /// - Parameters:
    ///   - analysis: the engine's answer about this recording.
    ///   - policy: Settings → Speed records. Deliberately an argument rather than a stored
    ///     fact: one analysis, three answers, nothing to re-import.
    ///   - divergence: the watch-vs-phone banner's lines, when a watch summary was paired.
    ///     The analysis cannot know them, so a document built from an analysis alone
    ///     carries the empty, honest answer.
    public static func build(_ analysis: SessionAnalysis,
                             policy: SpeedRecordPolicy = .preferVerified,
                             divergence: [Divergence] = []) -> PresentationValue {
        let summary = analysis.summary
        let markers = markerCounts(analysis)
        let block = blockSection(summary, analysis.records)
        let records = recordsSection(analysis, policy: policy)

        return .object([
            "presentationVersion": .int(version),
            "engineVersion": .string(analysis.engineVersion),
            "block": block,
            "card": cardSection(block),
            "row": rowSection(analysis),
            "records": records,
            "turns": turnsSection(analysis, markers: markers),
            "markers": markers,
            "flightEnds": flightEndsSection(analysis),
            "splash": splashSection(analysis),
            "filters": filtersSection(analysis),
            "defaults": .object([
                "recordWindow": records["default"] ?? .null,
                "section": .string(SessionSection.ride.rawValue),
                "cardPreset": .string(ShareCardStats.Preset.complete.rawValue),
                "rowMetrics": .array(defaultRowMetrics.map(PresentationValue.string)),
                "speedRecordPolicy": .string(policy.rawValue),
            ]),
            "divergence": divergenceSection(divergence),
            "notASession": notASessionSection(summary),
        ])
    }

    /// The document as the goldens spell it: sorted keys, ASCII-safe, one trailing
    /// newline. The twin of `presentation.document_json`.
    public static func json(_ analysis: SessionAnalysis,
                            policy: SpeedRecordPolicy = .preferVerified,
                            divergence: [Divergence] = []) -> String {
        build(analysis, policy: policy, divergence: divergence).json() + "\n"
    }

    // MARK: - Cells

    static func cell(_ key: String, _ labelID: String, value: PresentationValue = .null,
                     unitKind: String = "none",
                     captions: [PresentationValue] = [],
                     colourRole: String = "neutral",
                     tally: PresentationValue? = nil,
                     counts: PresentationValue? = nil) -> PresentationValue {
        var out: [String: PresentationValue] = [
            "key": .string(key),
            "labelId": .string(labelID),
            "value": value,
            "unitKind": .string(unitKind),
            "captions": .array(captions),
            "colourRole": .string(colourRole),
        ]
        if let tally { out["tally"] = tally }
        if let counts { out["counts"] = counts }
        return .object(out)
    }

    static func caption(_ id: String, _ args: [String: PresentationValue] = [:])
    -> PresentationValue {
        .object(["id": .string(id), "args": .object(args)])
    }

    static func ladder(_ counts: OutcomeCounts) -> PresentationValue {
        .object(["flewThrough": .int(counts.flewThrough),
                 "touchdown": .int(counts.touchdown),
                 "fellIn": .int(counts.fellIn)])
    }

    // MARK: - The key-metrics block

    /// `docs/presentation/key-metrics.md`, four rows. Every gate here is that file's, and
    /// a row with no cells is absent rather than empty.
    static func blockSection(_ summary: SessionSummary, _ records: GP3SRecords)
    -> PresentationValue {
        var rows: [PresentationValue] = []

        rows.append(.object(["id": .string("basics"), "cells": .array([
            cell("duration", "presentation.label.duration",
                 value: number(summary.durationS, "durationS"), unitKind: "durationS"),
            cell("distance", "presentation.label.distance",
                 value: number(summary.distanceKm, "distanceKm"), unitKind: "distanceKm"),
            // The engine reports km/h for this one number and every other speed in both
            // apps is a knot, so it is converted rather than printed beside a column of
            // knots. The *unit on screen* is still the renderer's.
            //
            // `avgSpeedKmh` itself carries only 2 decimal places — right for a km/h column,
            // but a digit short before the knot conversion even starts. `distanceKm` and
            // `timerTimeS` are the same division's two halves, each already at the
            // document's own convention precision, so re-deriving from them is the raw
            // value at full precision rather than a knot rounded twice. Twin of the lab's
            // `_block`.
            cell("avgSpeed", "presentation.label.avgSpeed",
                 value: number(summary.avgSpeedKmh != nil && summary.timerTimeS > 0
                     ? (summary.distanceKm / (summary.timerTimeS / 3600.0)) / 1.852
                     : nil, "speedKn"),
                 unitKind: "speedKn"),
        ])]))

        // Row 2 names the WINDOW, not the peak. The two composites beside it are
        // block-only: the card is the block minus them, because a card carries one speed.
        rows.append(.object(["id": .string("speed"), "cells": .array([
            cell("max2s", "presentation.label.max2s",
                 value: number(records.best2sKn, "speedKn"), unitKind: "speedKn"),
            cell("best5x10s", "presentation.label.best5x10s",
                 value: number(records.best5x10sKn, "speedKn"), unitKind: "speedKn"),
            cell("alpha500", "presentation.label.alpha500",
                 value: number(records.alpha500Kn, "speedKn"), unitKind: "speedKn"),
        ])]))

        var turnCells: [PresentationValue] = []
        // The clean jibes lead the row, in their own cell (Jan, 25 Sep 2026, F8e): they
        // were a clause in the tally's caption, the smallest type in the block for the one
        // number the product is named for. Twin of the lab's `_block`.
        if summary.turns.jibes > 0 {
            turnCells.append(cell("cleanJibes", "presentation.label.cleanJibes",
                                  value: .int(summary.turns.jibesSuccessful),
                                  unitKind: "count", colourRole: "clean.jibe"))
        }
        if let tally = tallyCell(summary.turns) { turnCells.append(tally) }
        if let tacks = tackCell(summary.turns) { turnCells.append(tacks) }
        if let falls = fallsCell(summary) { turnCells.append(falls) }
        if summary.turns.turnsCounted > 0 {
            // Flying leads the pair: the harder run first, and always the smaller number.
            turnCells.append(cell("streaks", "presentation.label.streaks",
                                  unitKind: "count",
                                  counts: .array([
                                    // Each half in the ink of what it counts (F8f): a
                                    // flew streak is the ladder's green; a dry streak is
                                    // flew *or* touchdown, no single rung, so body ink.
                                    .object(["labelId": .string("glossary.flewThrough"),
                                             "value": .int(summary.turns.longestFlewStreak),
                                             "colourRole": .string("outcome.flew")]),
                                    .object(["labelId": .string("glossary.dry"),
                                             "value": .int(summary.turns.longestDryStreak),
                                             "colourRole": .string("neutral")]),
                                  ])))
        }
        if !turnCells.isEmpty {
            rows.append(.object(["id": .string("turns"), "cells": .array(turnCells)]))
        }

        let rates = rateCells(summary)
        if !rates.isEmpty {
            rows.append(.object(["id": .string("rates"), "cells": .array(rates)]))
        }
        return .object(["rows": .array(rows)])
    }

    /// The jibe ladder, or the whole counted-turn ladder where the wind axis named no
    /// jibes. The caption says which. The clean count is the `cleanJibes` cell beside it
    /// since 25 Sep 2026, so the caption no longer carries it: one fact, one cell.
    static func tallyCell(_ t: TurnSummary) -> PresentationValue? {
        if t.jibes > 0 {
            return cell("tally", "presentation.label.outcomeLadder", unitKind: "count",
                        captions: [caption("presentation.caption.ofJibes",
                                           ["jibes": .int(t.jibes)])],
                        colourRole: "outcome.ladder", tally: ladder(t.jibeOutcomes))
        }
        guard t.turnsCounted > 0 else { return nil }
        // No clean clause on the fallback: `turnsSuccessful` is the score verdict over
        // every counted turn, and a session whose wind axis named no jibes has no clean
        // jibes to report.
        return cell("tally", "presentation.label.outcomeLadder", unitKind: "count",
                    captions: [caption("presentation.caption.ofTurns",
                                       ["turns": .int(t.turnsCounted)])],
                    colourRole: "outcome.ladder", tally: ladder(t.outcomes))
    }

    /// The tack ladder beside the jibe one. Two gates: a tack to report, and a jibe tally
    /// that is the *jibe* ladder — otherwise the fallback above already counted these
    /// turns and the block would print one set of numbers twice.
    static func tackCell(_ t: TurnSummary) -> PresentationValue? {
        guard t.tacks > 0, t.jibes > 0 else { return nil }
        return cell("tacks", "presentation.label.outcomeLadder", unitKind: "count",
                    captions: [caption("presentation.caption.ofTacks",
                                       ["tacks": .int(t.tacks)])],
                    colourRole: "outcome.ladder", tally: ladder(t.tackOutcomes))
    }

    /// Every fall of the session, off the flight-end channel, with the split in its
    /// caption. Absent where no flight ended with usable evidence — an unknown number of
    /// falls, not zero of them.
    static func fallsCell(_ s: SessionSummary) -> PresentationValue? {
        let ends = s.flightEnds
        guard ends.all.total > 0 else { return nil }
        return cell("falls", "glossary.fellIn", value: .int(ends.all.fellIn),
                    unitKind: "count",
                    captions: [caption("presentation.caption.fallsSplit",
                                       ["inTurn": .int(ends.inTurn.fellIn),
                                        "straight": .int(ends.straight.fellIn)])])
    }

    /// Row 4. Empty where there is no hour to divide by. **CPH first, then one dry-turn
    /// rate, then WPH** (Jan, 25 Sep 2026): JPH while every counted turn is a jibe, TPH once
    /// a tack is among them, and CPH absent where the wind axis named no jibes. Gated on the
    /// **counts**, never on a rate. Twin of the lab's `_rate_cells`.
    static func rateCells(_ s: SessionSummary) -> [PresentationValue] {
        guard let wet = s.wetPerHour else { return [] }
        var out: [PresentationValue] = []
        let jibes = s.turns.jibes
        let tph = s.turnsPerHour ?? 0
        if jibes > 0 || tph <= 0 {
            out.append(cell("cph", "glossary.cph",
                            value: number(s.cleanJibesPerHour ?? 0, "rate"),
                            unitKind: "rate"))
        }
        if s.turns.tacks > 0 || (jibes <= 0 && tph > 0) {
            out.append(cell("tph", "glossary.tph", value: number(tph, "rate"),
                            unitKind: "rate"))
        } else {
            out.append(cell("jph", "glossary.jph",
                            value: number(s.jibesPerHour ?? 0, "rate"), unitKind: "rate"))
        }
        out.append(cell("wph", "glossary.wph", value: number(wet, "rate"),
                        unitKind: "rate"))
        return out
    }

    // MARK: - The card

    /// The share card is the block, re-laid-out — minus the two block-only speed cells.
    /// Nothing is computed here that the block does not already carry: a preset can only
    /// drop a tile, never reword, reorder or invent one.
    static func cardSection(_ block: PresentationValue) -> PresentationValue {
        var tiles: [PresentationValue] = []
        for row in block["rows"]?.arrayValue ?? [] {
            for cell in row["cells"]?.arrayValue ?? [] {
                guard let key = cell["key"]?.stringValue,
                      key != "best5x10s", key != "alpha500" else { continue }
                var tile = cell.objectValue ?? [:]
                tile["presets"] = .array(ShareCardStats.Preset.leanKeys.contains(key)
                                         ? [.string("complete"), .string("lean")]
                                         : [.string("complete")])
                tiles.append(.object(tile))
            }
        }
        return .object([
            "tiles": .array(tiles),
            "leanKeys": .array(leanCardKeys.map(PresentationValue.string)),
            "forbiddenKeys": .array(forbiddenCardKeys.map(PresentationValue.string)),
        ])
    }

    // MARK: - The library row

    /// Three slots the rider chose, and the tally the row wears.
    ///
    /// The row's tally is over **every counted turn**, not over the jibes: a row scanned
    /// against its neighbours has to be one set of turns the whole way down the list.
    static func rowSection(_ analysis: SessionAnalysis) -> PresentationValue {
        let s = analysis.summary
        let t = s.turns
        func slot(_ metric: String) -> PresentationValue {
            let label = "presentation.rowMetric." + metric
            switch metric {
            case "foilShare":
                return cell(metric, label, value: number(s.foilPct, "percent"),
                            unitKind: "percent")
            case "flights": return cell(metric, label, value: .int(s.flightCount),
                                        unitKind: "count")
            case "jibes": return cell(metric, label, value: .int(t.jibes), unitKind: "count")
            case "cleanJibes": return cell(metric, label, value: .int(t.jibesSuccessful),
                                           unitKind: "count")
            case "turns": return cell(metric, label, value: .int(t.turnsCounted),
                                      unitKind: "count")
            case "best2s": return cell(metric, label,
                                       value: number(analysis.records.best2sKn, "speedKn"),
                                       unitKind: "speedKn")
            case "best10s": return cell(metric, label,
                                        value: number(analysis.records.best10sKn, "speedKn"),
                                        unitKind: "speedKn")
            case "distance": return cell(metric, label,
                                         value: number(s.distanceKm, "distanceKm"),
                                         unitKind: "distanceKm")
            case "duration": return cell(metric, label,
                                         value: number(s.durationS, "durationS"),
                                         unitKind: "durationS")
            case "dryStreak": return cell(metric, label, value: .int(t.longestDryStreak),
                                          unitKind: "count")
            default: return cell(metric, label, value: .int(s.flightEnds.all.fellIn),
                                 unitKind: "count")
            }
        }
        return .object([
            "slots": .array(defaultRowMetrics.map(slot)),
            "offered": .array(offeredRowMetrics.map(PresentationValue.string)),
            "tally": t.turnsCounted > 0 ? ladder(t.outcomes) : .null,
            "tagIds": .array(s.isSession ? [] : [.string("verdicts.notASession.tag")]),
        ])
    }

    // MARK: - Records

    /// Every window the engine found for one kind. `best5x10s` is the array — the record
    /// *is* the five, and one segment misnames it.
    static func windows(_ records: GP3SRecords, _ kind: RecordKind) -> [RecordWindow] {
        if kind == .best5x10s { return records.windows.best5x10s ?? [] }
        return records.windows[kind.rawValue].map { [$0] } ?? []
    }

    /// The nine kinds: value, window provenance, whether the recording measured its own
    /// speed, and whether the rider's policy lets the record stand.
    ///
    /// A session is one candidate per kind, so `preferVerified` has nothing to prefer and
    /// answers like `includeUnverified` — `SpeedRecordRule.stands`, the one function that
    /// answers this question anywhere in the product.
    static func recordsSection(_ analysis: SessionAnalysis, policy: SpeedRecordPolicy)
    -> PresentationValue {
        let verified = analysis.capabilities.hasDoppler
        let stands = SpeedRecordRule.stands(verified: verified, policy: policy)
        var kinds: [PresentationValue] = []
        var achieved: [PresentationValue] = []
        for kind in recordKinds {
            let value = kind.value(in: analysis.records)
            let spans = windows(analysis.records, kind)
            let isAchieved = (value ?? 0) > 0 && !spans.isEmpty
            if isAchieved { achieved.append(.string(kind.rawValue)) }
            kinds.append(.object([
                "key": .string(kind.rawValue),
                "labelId": .string("tokens.recordWindow." + kind.rawValue),
                "value": number(value, "speedKn"),
                "unitKind": .string("speedKn"),
                "windows": .array(spans.map {
                    .object(["startTs": number($0.startTs, "seconds"),
                             "durS": number($0.durS, "seconds")])
                }),
                "achieved": .bool(isAchieved),
                "verified": .bool(verified),
                "offered": .bool(isAchieved && stands),
                "colourRole": .string("effort.window"),
            ]))
        }
        let available = Set(achieved.compactMap(\.stringValue))
        return .object([
            "kinds": .array(kinds),
            "achieved": .array(achieved),
            "policy": .string(policy.rawValue),
            "verified": .bool(verified),
            "default": RecordWindowSelection.initial(available: available)
                .map(PresentationValue.string) ?? .null,
        ])
    }

    // MARK: - Turns

    /// The legend chips with their live counts, and one strip entry per detected sweep.
    ///
    /// `ordinal` is the turn's position among the counted turns of its own kind — the
    /// number the turn page's "3 of 14" and the wrist-under callout both name, computed
    /// once here so two surfaces cannot count differently.
    static func turnsSection(_ analysis: SessionAnalysis,
                             markers: PresentationValue) -> PresentationValue {
        let takeoff = markers["takeoff"]
        func count(_ key: String) -> PresentationValue {
            key == "takeoff" ? (takeoff?["total"] ?? .null) : (markers[key] ?? .null)
        }
        let legend = mapLayers.map { layer in
            PresentationValue.object([
                "layerId": .string(layer.id),
                "labelId": .string("tokens.layer." + layer.id),
                "count": layer.count.map(count) ?? .null,
                "colourRole": .string(layer.colour),
                "defaultVisible": .bool(true),
            ])
        }

        var ordinals: [String: Int] = [:]
        var strip: [PresentationValue] = []
        for (index, turn) in analysis.turns.enumerated() {
            let layer = PresentationRules.layer(for: turn).rawValue
            var ordinal = PresentationValue.null
            if turn.counted {
                ordinals[turn.type, default: 0] += 1
                ordinal = .int(ordinals[turn.type] ?? 0)
            }
            strip.append(.object([
                "index": .int(index),
                "counted": .bool(turn.counted),
                "ordinal": ordinal,
                "typeId": .string(turnTypeID(turn.type)),
                "sideId": .string(turn.side),
                "outcomeId": .string(PresentationRules.layer(forOutcome: turn.outcome)
                    .rawValue),
                "outcomeReasonId": turn.outcomeReason.map(PresentationValue.string) ?? .null,
                "clean": .bool(turn.clean),
                "cleanBlockedById": turn.cleanBlockedBy.map(PresentationValue.string)
                    ?? .null,
                "aborted": .bool(turn.aborted),
                "borderline": .bool(turn.borderline),
                "ts": number(turn.ts, "seconds"),
                "minTs": number(turn.minTs, "seconds"),
                "endTs": number(turn.endTs, "seconds"),
                "entryKn": number(turn.entryKn, "speedKn"),
                "minKn": number(turn.minKn, "speedKn"),
                "exitKn": number(turn.exitKn, "speedKn"),
                "score": number(turn.score, "score"),
                "layerId": .string(turn.clean ? MapLayer.cleanJibe.rawValue : layer),
                "colourRole": .string(outcomeColour(layer)),
            ]))
        }
        return .object(["legend": .array(legend), "strip": .array(strip)])
    }

    // MARK: - Markers, flight ends, wrist under

    /// Turn outcomes, the drawn straight-line ends, the star layer and the two effort
    /// layers — the counts `fixtures/presentation/*.expected.json` has always pinned.
    static func markerCounts(_ analysis: SessionAnalysis) -> PresentationValue {
        let facts = PresentationFacts(analysis)
        return .object([
            "flewThrough": .int(facts.markers.flewThrough),
            "touchdown": .int(facts.markers.touchdown),
            "fellIn": .int(facts.markers.fellIn),
            "courseChange": .int(facts.markers.courseChange),
            "cleanJibe": .int(facts.cleanJibes),
            "splash": .int(facts.splash),
            "pumping": .int(facts.pumpingSpans),
            "takeoff": .object(["pumped": .int(facts.takeoff.pumped),
                                "free": .int(facts.takeoff.free),
                                "failed": .int(facts.takeoff.failed),
                                "total": .int(facts.takeoff.total)]),
        ])
    }

    /// Every flight end in the three buckets the marker rules distinguish, and one entry
    /// per *drawn* end — the hollow marks no turn explains.
    static func flightEndsSection(_ analysis: SessionAnalysis) -> PresentationValue {
        let facts = PresentationFacts(analysis)
        var marks: [PresentationValue] = []
        for (index, end) in analysis.flightEnds.enumerated()
        where end.ownedByTurn == nil && !end.truncated {
            let layer = PresentationRules.layer(forOutcome: end.outcome).rawValue
            marks.append(.object([
                "index": .int(index),
                "flightIndex": .int(end.flightIndex),
                "ts": number(end.ts, "seconds"),
                "outcomeId": .string(layer),
                "colourRole": .string(outcomeColour(layer)),
                "stoppedS": number(end.stoppedS, "seconds"),
                "hollow": .bool(true),
            ]))
        }
        return .object([
            "flightCount": .int(facts.flightCount),
            "drawn": .int(facts.flightEnds.drawn),
            "ownedByTurn": .int(facts.flightEnds.ownedByTurn),
            "truncated": .int(facts.flightEnds.truncated),
            "total": .int(facts.flightEnds.total),
            "marks": .array(marks),
        ])
    }

    /// "Wrist under" — one mark per submersion episode, and the callout it prints, as copy
    /// ids with their arguments (`docs/presentation/layers-map-colour-type.md`).
    static func splashSection(_ analysis: SessionAnalysis) -> PresentationValue {
        var marks: [PresentationValue] = []
        for sub in analysis.submersions {
            let title = sub.durationS.rounded() < 1
                ? caption("presentation.wristUnder.title")
                : caption("presentation.wristUnder.titleFor",
                          ["durationS": number(sub.durationS, "roundedSeconds")])
            var during = caption("presentation.wristUnder.offFoil")
            if let index = sub.turnIndex, index >= 0, index < analysis.turns.count {
                let turn = analysis.turns[index]
                let typeID = turnTypeID(turn.type)
                let same = analysis.turns.enumerated()
                    .filter { $0.element.counted && $0.element.type == turn.type }
                    .map(\.offset)
                if let position = same.firstIndex(of: index) {
                    during = caption("presentation.wristUnder.duringTurn",
                                     ["turnId": .string(typeID),
                                      "ordinal": .int(position + 1)])
                } else {
                    during = caption("presentation.wristUnder.duringAnyTurn",
                                     ["turnId": .string(typeID)])
                }
            } else if let index = sub.flightEndIndex, index >= 0,
                      index < analysis.flightEnds.count {
                let end = analysis.flightEnds[index]
                if end.stoppedS >= 1 {
                    during = caption("presentation.wristUnder.afterFlightStopped",
                                     ["flight": .int(end.flightIndex + 1),
                                      "stoppedS": number(end.stoppedS, "roundedSeconds")])
                } else {
                    during = caption("presentation.wristUnder.afterFlight",
                                     ["flight": .int(end.flightIndex + 1)])
                }
            }
            marks.append(.object([
                "ts": number(sub.ts, "seconds"),
                "durationS": number(sub.durationS, "seconds"),
                "turnIndex": sub.turnIndex.map(PresentationValue.int) ?? .null,
                "flightEndIndex": sub.flightEndIndex.map(PresentationValue.int) ?? .null,
                "title": title,
                "during": during,
                "colourRole": .string("effort.splash"),
            ]))
        }
        return .object(["episodes": .int(marks.count), "marks": .array(marks)])
    }

    // MARK: - Filters, divergence, the verdict

    /// Every type × ENTRY-side combination over the counted turns, with the flew-through
    /// share's numerator. Side is the tack the turn was entered on, never the rotation.
    static func filtersSection(_ analysis: SessionAnalysis) -> PresentationValue {
        var out: [PresentationValue] = []
        for type in TurnTypeFilter.allCases {
            for side in TurnSideFilter.allCases {
                let tally = TurnAnalytics.tally(analysis.turns,
                                                filter: TurnFilter(type: type, side: side))
                out.append(.object(["typeId": .string(type.rawValue),
                                    "sideId": .string(side.rawValue),
                                    "count": .int(tally.total),
                                    "flewThrough": .int(tally.flewThrough)]))
            }
        }
        return .array(out)
    }

    /// The watch-vs-phone banner. The watch summary is not part of the analysis, so a
    /// document built from one alone carries the empty, honest answer rather than nothing.
    ///
    /// **The numbers are in it since round 2** (ADR-033). `Divergence` held pre-formatted
    /// strings in round 1, which is a rule-2 violation the document could not carry at all;
    /// each line is `{metricId, labelId, watch, phone, unitKind}` now and `DivergenceText`
    /// is the renderer. A golden's document still spells `{"available": false, "lines": []}`
    /// — an analysis alone never pairs a watch summary — so no golden moved for this.
    static func divergenceSection(_ lines: [Divergence]) -> PresentationValue {
        .object([
            "available": .bool(!lines.isEmpty),
            "lines": .array(lines.map(\.documentLine)),
        ])
    }

    /// What the rider is told about a recording that was never an afternoon — the row's
    /// quiet tag and the page's one line, as ids with the two numbers that decided.
    static func notASessionSection(_ s: SessionSummary) -> PresentationValue {
        guard !s.isSession else {
            return .object(["isSession": .bool(true), "reasonId": .null, "tagId": .null,
                            "lineId": .null, "args": .object([:])])
        }
        let reason = s.notASessionReason
        let noRecording = reason == .noRecording
        let args: [String: PresentationValue] = noRecording ? [:] : [
            "durationS": number(s.durationS, "durationS"),
            "distanceKm": number(s.distanceKm, "distanceKm"),
        ]
        return .object([
            "isSession": .bool(false),
            "reasonId": reason.map { PresentationValue.string($0.rawValue) } ?? .null,
            "tagId": .string("verdicts.notASession.tag"),
            "lineId": .string(noRecording ? "verdicts.notASession.lines.0"
                                          : "verdicts.notASession.lines.1"),
            "args": .object(args),
        ])
    }
}

/// One node of the presentation document.
///
/// A tree rather than a nest of `Codable` structs, for one reason: the document has to come
/// out of Swift **byte for byte** the way Python writes it, and that needs an integer to
/// stay an integer (`2`, never `2.0`), keys to be sorted at every depth and floats to be
/// printed by the shortest representation that round-trips. `JSONEncoder` decides all three
/// for itself.
public indirect enum PresentationValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double)
    case string(String)
    case array([PresentationValue])
    case object([String: PresentationValue])

    /// Deliberately not `string` / `array` / `object`: those names are the cases', and a
    /// property sharing one makes `PresentationValue.string` ambiguous at every use site.
    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    public var arrayValue: [PresentationValue]? {
        if case .array(let a) = self { a } else { nil }
    }
    public var objectValue: [String: PresentationValue]? {
        if case .object(let o) = self { o } else { nil }
    }

    public subscript(key: String) -> PresentationValue? { objectValue?[key] }

    /// Canonical JSON: two-space indent, keys sorted at every depth, no escaped slashes,
    /// no non-ASCII (the document contains none — every string is an id or an enum value).
    /// The twin of `json.dumps(tree, indent=2, ensure_ascii=False)` over a sorted tree.
    public func json(indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent)
        let inner = String(repeating: " ", count: indent + 2)
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .number(let value): return Self.number(value)
        case .string(let value): return Self.quoted(value)
        case .array(let items):
            if items.isEmpty { return "[]" }
            let body = items.map { inner + $0.json(indent: indent + 2) }
            return "[\n" + body.joined(separator: ",\n") + "\n" + pad + "]"
        case .object(let fields):
            if fields.isEmpty { return "{}" }
            let body = fields.keys.sorted().map { key in
                inner + Self.quoted(key) + ": " + fields[key]!.json(indent: indent + 2)
            }
            return "{\n" + body.joined(separator: ",\n") + "\n" + pad + "}"
        }
    }

    /// Python's float repr for the values this document holds: the shortest string that
    /// round-trips, with a `.0` on a whole number. Swift's own `String(Double)` is the same
    /// algorithm; the exponent forms the two spell differently are unreachable here,
    /// because every value is rounded to at most four decimals and no magnitude in a
    /// session comes near 1e16.
    static func number(_ value: Double) -> String {
        let text = String(value)
        return text == "-0.0" ? "0.0" : text
    }

    static func quoted(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }
}
