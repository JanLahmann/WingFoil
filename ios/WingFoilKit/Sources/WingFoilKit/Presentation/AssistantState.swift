import Foundation

/// **What the app tells "Ask CleanJibe" about itself** — the facts the help context needs:
/// which build is asking, and in which unit the rider reads a speed.
public struct AssistantApp: Sendable, Equatable {
    /// `"release"` · `"beta"` · `"dev"` (docs/channels.md).
    public var channel: String
    /// The marketing version, e.g. `"1.0.1"`.
    public var appVersion: String
    /// The build number, where the caller knows it.
    public var build: Int?
    /// Settings → Units. The kit has no distance setting, so distance is always `km`.
    public var speed: SpeedUnit

    public init(channel: String, appVersion: String, build: Int? = nil,
                speed: SpeedUnit = .knots) {
        self.channel = channel
        self.appVersion = appVersion
        self.build = build
        self.speed = speed
    }
}

/// **The state sent with a question to Ask CleanJibe** — the contract is
/// `docs/copy/assistant/session-state.schema.json`, the two worked examples beside it are
/// its meaning.
///
/// Pure: numbers in, compact JSON (sorted keys) out. Every number is one the app already
/// shows, read off the analysis or the presentation helpers that print it — the rates come
/// out of `PresentationDocument.rateCells`, so the assistant is never handed a CPH the page
/// does not carry, and a session under the rate floor sends nulls with `tooShort: true`.
/// No coordinates, no spot, no rider name: the schema has no key for them.
///
/// A key the kit cannot answer is **left out** rather than invented (`source.device`, and
/// `source.kind` on a measured-speed file whose maker the row does not record); `null`
/// appears only where the schema and the examples use it.
public enum AssistantState {

    /// The server trims `session.turnList` from the end past 12 000 bytes; this stays
    /// under the bar on its own, with headroom.
    public static let maxBytes = 11_000
    /// The schema's `turnList.maxItems`.
    public static let maxTurns = 80
    /// The schema's `watchVsPhone.maxItems`.
    public static let maxDivergences = 12

    /// The help context: which app, which engine, which units.
    public static func help(_ app: AssistantApp) -> Data {
        Data(compact(.object(base(app))).utf8)
    }

    /// The session context: the help facts plus `session`, built from one analysed session.
    ///
    /// - Parameters:
    ///   - timeZone: the zone the date and the clocks are printed in. Nil (the default) is
    ///     `row.displayZone`, the session's own clock — the rule every presentation type
    ///     follows (`SessionRow.displayZone`).
    ///   - tips: the turn coach's tip per turn, keyed by the turn's index in
    ///     `analysis.turns`. The coach needs the turn's track slice (`TurnCoach.tip`), which
    ///     an analysis alone does not carry, so a caller with the samples fills this; a
    ///     turn without one sends `tip: null`.
    ///   - divergences: the watch-vs-phone lines (`DivergenceCheck.compare`) when a watch
    ///     summary was paired; nil leaves `watchVsPhone` out.
    public static func session(_ app: AssistantApp, row: SessionRow, analysis: SessionAnalysis,
                               timeZone: TimeZone? = nil,
                               tips: [Int: String] = [:],
                               divergences: [Divergence]? = nil) -> Data {
        var top = base(app)
        var session = sessionFacts(row: row, analysis: analysis,
                                   timeZone: timeZone ?? row.displayZone)
        if let divergences {
            session["watchVsPhone"] = .array(divergences.prefix(maxDivergences).map(divergenceLine))
        }

        // The turn list, capped by count and then by bytes: measured on the very string
        // that is sent, so the cap is exact rather than an estimate per row.
        let rows = turnList(row: row, analysis: analysis,
                            timeZone: timeZone ?? row.displayZone, tips: tips)
        session["turnList"] = .array([])
        top["session"] = .object(session)
        var size = compact(.object(top)).utf8.count
        var kept: [PresentationValue] = []
        for item in rows.prefix(maxTurns) {
            let add = compact(item).utf8.count + (kept.isEmpty ? 0 : 1)
            guard size + add <= maxBytes else { break }
            size += add
            kept.append(item)
        }
        session["turnList"] = .array(kept)
        top["session"] = .object(session)
        return Data(compact(.object(top)).utf8)
    }

    // MARK: - The help facts

    static func base(_ app: AssistantApp) -> [String: PresentationValue] {
        var out: [String: PresentationValue] = [
            "surface": .string("ios"),
            "channel": .string(app.channel),
            "appVersion": .string(String(app.appVersion.prefix(16))),
            "engineVersion": .string(String(AnalysisEngine.version.prefix(16))),
            "units": .object(["speed": .string(speedUnit(app.speed)),
                              "distance": .string("km")]),
        ]
        if let build = app.build, build >= 0 { out["build"] = .int(build) }
        return out
    }

    /// Settings → Units in the schema's spelling.
    static func speedUnit(_ unit: SpeedUnit) -> String {
        switch unit {
        case .knots: "kn"
        case .kmh: "kmh"
        }
    }

    // MARK: - The session

    static func sessionFacts(row: SessionRow, analysis: SessionAnalysis,
                             timeZone: TimeZone) -> [String: PresentationValue] {
        let s = analysis.summary
        var out: [String: PresentationValue] = [
            "date": .string(clock(row.startDate, "yyyy-MM-dd", timeZone)),
            "startClock": .string(clock(row.startDate, "HH:mm", timeZone)),
            // The duration every surface displays (T1), in whole minutes like the examples.
            "durationMin": .int(whole(s.durationS / 60)),
            "distanceKm": .number(round(s.distanceKm, 1)),
            "foilPct": .int(min(100, max(0, whole(s.foilPct)))),
            "flights": .int(s.flightCount),
            "longestFlightS": .int(whole(s.longestFlightS)),
            "source": .object(source(row: row, analysis: analysis)),
            "wind": wind(analysis.wind),
            "turns": turns(s.turns),
            "records": records(analysis),
            "takeoff": takeoff(analysis),
            "jumps": jumps(s.jumps),
        ]
        if let rates = rates(s, rateFloorExempt: row.isExample) { out["rates"] = rates }
        return out
    }

    /// Where the recording came from. The ladder is `SessionDisplay.sourceClassNote`'s:
    /// the import door first where it knows more than the class letter (an Apple Watch
    /// recording is class b with a wrist), then the letter. A measured-speed file
    /// (class b) is a Garmin's own recording only where the door says so — a Garmin GDPR
    /// export — and another app's where the format does (a TCX, Apple Health); anything
    /// else is not recorded on the row, so `kind` is left out rather than guessed.
    static func source(row: SessionRow, analysis: SessionAnalysis) -> [String: PresentationValue] {
        var out: [String: PresentationValue] = [
            "hasAccel": .bool(analysis.capabilities.hasAccel),
            "hasDoppler": .bool(analysis.capabilities.hasDoppler),
        ]
        if let kind = sourceKind(row) { out["kind"] = .string(kind) }
        return out
    }

    static func sourceKind(_ row: SessionRow) -> String? {
        let door = row.importSource
        if ImportSource.appleWatch.isNamed(in: door) { return "appleWatch" }
        if ImportSource.watchDirect.isNamed(in: door) { return "cleanjibeWatch" }
        switch row.sourceClass {
        case "a": return "cleanjibeWatch"
        case "c": return "positionsOnly"
        case "b":
            if ImportSource.appleHealth.isNamed(in: door) { return "otherApp" }
            if row.originalFilename?.lowercased().hasSuffix(".tcx") == true { return "otherApp" }
            if ImportSource.gdpr.isNamed(in: door) { return "garminNative" }
            return nil
        default: return nil
        }
    }

    /// `wind`: the direction it blows from, how sure the estimate is, and whether the
    /// rider set it. Null where the analysis has no wind at all.
    static func wind(_ wind: WindEstimate?) -> PresentationValue {
        guard let wind else { return .null }
        return .object([
            "fromDeg": .int(whole(wind.dirDeg)),
            "confidence": .number(min(1, max(0, round(wind.confidence, 2)))),
            "setByRider": .bool(wind.source == "user"),
        ])
    }

    /// The counted turns, the outcome ladder over **every counted turn** (the set the
    /// turn list is drawn from), the clean jibes and the longest dry run.
    static func turns(_ t: TurnSummary) -> PresentationValue {
        .object([
            "jibes": .int(t.jibes),
            "tacks": .int(t.tacks),
            "unclassified": .int(t.unclassified),
            "flewThrough": .int(t.outcomes.flewThrough),
            "touchdown": .int(t.outcomes.touchdown),
            "fellIn": .int(t.outcomes.fellIn),
            "clean": .int(t.jibesSuccessful),
            "longestDryStreak": .int(t.longestDryStreak),
        ])
    }

    /// Row 4 of the key-metrics block, exactly: `PresentationDocument.rateCells` picks the
    /// cells (CPH first, then JPH on a jibes-only session or TPH once tacks exist, then
    /// WPH) and gates them on the rate floor; a rate the row does not carry is null. Nil
    /// where the block has no rates row at all (no hour to divide by).
    static func rates(_ s: SessionSummary, rateFloorExempt: Bool) -> PresentationValue? {
        let cells = PresentationDocument.rateCells(s, rateFloorExempt: rateFloorExempt)
        guard !cells.isEmpty else { return nil }
        var values: [String: PresentationValue] = [:]
        for cell in cells {
            guard let key = cell["key"]?.stringValue else { continue }
            switch cell["value"] {
            case .number(let v)?: values[key] = .number(round(v, 1))
            case .int(let v)?: values[key] = .number(Double(v))
            default: values[key] = .null
            }
        }
        var out: [String: PresentationValue] = [:]
        for key in ["cph", "jph", "tph", "wph"] { out[key] = values[key] ?? .null }
        out["tooShort"] = .bool(!(rateFloorExempt || RateFloor.holds(timerS: s.timerTimeS)))
        return .object(out)
    }

    /// The four records the schema names, in knots; a record the session did not set is
    /// left out. Without Doppler every one of them is estimated from positions.
    static func records(_ analysis: SessionAnalysis) -> PresentationValue {
        let r = analysis.records
        var out: [String: PresentationValue] = [
            "estimated": .bool(!analysis.capabilities.hasDoppler),
        ]
        let pairs: [(String, Double?)] = [
            ("best2sKn", r.best2sKn), ("best10sKn", r.best10sKn),
            ("best500mKn", r.best500mKn), ("alpha500Kn", r.alpha500Kn),
        ]
        for (key, value) in pairs {
            if let value, value.isFinite, value > 0 { out[key] = .number(round(value, 1)) }
        }
        return .object(out)
    }

    /// Takeoffs: every flight is a success; attempts and pump strokes need the wrist's
    /// accelerometer, and are null without one (the rule `DivergenceCheck` keys on).
    static func takeoff(_ analysis: SessionAnalysis) -> PresentationValue {
        let k = analysis.summary.takeoff
        let accel = analysis.capabilities.hasAccel
        return .object([
            "successes": .int(k.takeoffSuccesses),
            "attempts": accel ? .int(k.takeoffAttempts) : .null,
            "pumpStrokes": k.totalPumpStrokes.map(PresentationValue.int) ?? .null,
        ])
    }

    /// Jumps (engine 0.29.0): null where nothing counted them — no accelerometer, or a
    /// windsurf preset. The height is integrated and always an estimate.
    static func jumps(_ j: JumpSummary?) -> PresentationValue {
        guard let j else { return .null }
        return .object([
            "count": .int(j.count),
            "highestM": j.highestM.map { .number(round($0, 1)) } ?? .null,
            "estimated": .bool(true),
        ])
    }

    /// The counted turns in time order — `TurnAnalytics.items`, the Turns tab's own list.
    static func turnList(row: SessionRow, analysis: SessionAnalysis, timeZone: TimeZone,
                         tips: [Int: String]) -> [PresentationValue] {
        TurnAnalytics.items(analysis.turns).map { item in
            let turn = analysis.turns[item.id]
            var out: [String: PresentationValue] = [
                "clock": .string(clock(row.startDate.addingTimeInterval(turn.ts),
                                       "HH:mm:ss", timeZone)),
                "kind": .string(["jibe", "tack"].contains(turn.type) ? turn.type : "turn"),
                "side": .string(["port", "starboard"].contains(turn.side) ? turn.side
                                                                          : "unknown"),
                "outcome": .string(item.outcome.rawValue),
                "clean": .bool(turn.clean),
                "entryKn": .number(round(turn.entryKn, 1)),
                "minKn": .number(round(turn.minKn, 1)),
                // "You held 67 % of your entry speed" — the coach's and the list's number.
                "heldPct": .int(Int(TurnAnalytics.scoreText(turn.score)) ?? whole(turn.score * 100)),
                "tip": tips[item.id].map { .string(String($0.prefix(160))) } ?? .null,
            ]
            switch turn.outcomeReason.flatMap(OutcomeReason.init(rawValue:)) {
            case nil: out["reason"] = .null
            case .stop?: out["reason"] = .string("stop")
            case .offFoil?: out["reason"] = .string("offFoil")
            case .submerged?: out["reason"] = .string("submerged")
            // Not in the schema's vocabulary (unreachable at the published defaults since
            // engine 0.18.0): left out rather than renamed.
            case .pumpedMarginal?: break
            }
            return .object(out)
        }
    }

    /// One watch-vs-phone line, in the metric's own unit — knots for a record, whole
    /// seconds for foil time, a count for a count — with the threshold it crossed.
    static func divergenceLine(_ line: Divergence) -> PresentationValue {
        func value(_ raw: Double) -> PresentationValue {
            switch line.unitKind {
            case "speedKn": .number(round(raw, 1))
            default: .int(whole(raw))
            }
        }
        let reason: String
        switch line.unitKind {
        case "durationS":
            reason = "differs by more than \(Int(DivergenceCheck.foilTimePctThreshold)) %"
        case "speedKn":
            reason = "differs by more than \(DivergenceCheck.recordKnThreshold) kn"
        default:
            reason = "differs by more than \(DivergenceCheck.countThreshold)"
        }
        return .object([
            "metric": .string(String(line.metricId.prefix(40))),
            "watch": value(line.watchValue),
            "phone": value(line.phoneValue),
            "reason": .string(reason),
        ])
    }

    // MARK: - Formatting

    static func clock(_ date: Date, _ format: String, _ zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// Rounded the way the app prints the number: `%.Nf`, the correctly rounded decimal of
    /// the stored double (`Speed.format`, `KeyMetrics.rate`) — so 10.65 kn, stored a hair
    /// above, is the 10.7 the turn page shows, and 6.35, a hair below, is 6.3.
    static func round(_ value: Double, _ decimals: Int) -> Double {
        guard value.isFinite else { return 0 }
        let out = Double(String(format: "%.\(decimals)f", value)) ?? 0
        return out == 0 ? 0 : out
    }

    static func whole(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(clamped: value.rounded())
    }

    /// Compact JSON, keys sorted — the document's number and string spelling without its
    /// indentation.
    static func compact(_ value: PresentationValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return String(v)
        case .number(let v): return PresentationValue.number(v)
        case .string(let v): return PresentationValue.quoted(v)
        case .array(let items): return "[" + items.map(compact).joined(separator: ",") + "]"
        case .object(let fields):
            return "{" + fields.keys.sorted().map { key in
                PresentationValue.quoted(key) + ":" + compact(fields[key]!)
            }.joined(separator: ",") + "}"
        }
    }
}
