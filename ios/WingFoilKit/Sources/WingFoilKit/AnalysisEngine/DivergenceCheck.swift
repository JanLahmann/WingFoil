import Foundation

/// One watch-vs-phone disagreement — **as facts, not as sentences**.
///
/// It held four pre-formatted strings until round 2 of ADR-033, which is what kept the
/// divergence lines out of the presentation document: a formatted number in the document
/// breaks rule 2, and the banner's own sentence broke rule 1. Both halves are ids and raw
/// values now, and `DivergenceText` is the renderer — which is also what makes the
/// dismissal fingerprint independent of the unit the rider happens to be reading in.
///
/// `unitKind` is the document's, and there are only three here: `durationS` (foil time),
/// `speedKn` (the six records) and `count` (the five tallies).
public struct Divergence: Sendable, Equatable, Identifiable {
    public var id: String { metricId }
    /// The metric's stable id — `foilTime`, `best2s`, `takeoffAttempts`.
    public var metricId: String
    /// Where its name is written: `presentation.divergence.<id>` for the six with no other
    /// home, `tokens.recordWindow.<id>` for the six that are speed records, so there is one
    /// spelling of `Best 2 s` in the product.
    public var labelId: String
    /// What the watch wrote into the session dev fields, in the metric's own unit.
    public var watchValue: Double
    /// What the phone recomputed from the same FIT.
    public var phoneValue: Double
    /// `durationS` · `speedKn` · `count`.
    public var unitKind: String

    public init(metricId: String, labelId: String, watchValue: Double, phoneValue: Double,
                unitKind: String) {
        self.metricId = metricId
        self.labelId = labelId
        self.watchValue = watchValue
        self.phoneValue = phoneValue
        self.unitKind = unitKind
    }

    /// The line as the presentation document spells it (`docs/presentation/document.md`,
    /// "`divergence`"). The banner's numbers live here since round 2; round 1 left them
    /// out because they were strings.
    public var documentLine: PresentationValue {
        func value(_ raw: Double) -> PresentationValue {
            // A count is a whole number in the document, the way every other count is:
            // `4`, never `4.0` (`docs/presentation/document.md`, "Determinism").
            unitKind == "count" ? .int(Int(raw.rounded()))
                                : PresentationDocument.number(raw, unitKind)
        }
        return .object(["metricId": .string(metricId),
                        "labelId": .string(labelId),
                        "watch": value(watchValue),
                        "phone": value(phoneValue),
                        "unitKind": .string(unitKind)])
    }
}

/// Watch-vs-phone divergence check (docs/algorithms/divergence.md "Divergence check", source class (a)
/// only). The phone recompute is authoritative by design (docs/plan.md §3: "the watch
/// captures maximum-fidelity data plus robust live approximations; the phone re-derives
/// everything and is authoritative"), so a divergence is a standing *tuning* signal, not a
/// bug report — file it against the session fixture.
///
/// Thresholds: foil time > 5 % · any speed record > 0.3 kn · flight/turn/attempt counts off
/// by more than 1.
public enum DivergenceCheck {

    public static let foilTimePctThreshold = 5.0
    public static let recordKnThreshold = 0.3
    public static let countThreshold = 1

    /// Empty for every source without our session dev fields — there is nothing to compare.
    public static func compare(watch: WatchSummary, phone: SessionAnalysis) -> [Divergence] {
        guard !watch.isEmpty else { return [] }
        var out: [Divergence] = []

        if let w = watch.foilTimeS, w > 0 {
            let p = phone.summary.foilTimeS
            let pct = abs(p - w) / w * 100
            if pct > foilTimePctThreshold {
                out.append(Divergence(metricId: "foilTime",
                                      labelId: "presentation.divergence.foilTime",
                                      watchValue: w, phoneValue: p, unitKind: "durationS"))
            }
        }

        // The six records name themselves out of `RecordKind`, which is the product's one
        // spelling of a record (`tokens.recordWindow.<id>`).
        let records: [(RecordKind, Double?, Double?)] = [
            (.best2s, watch.best2sMps, phone.records.best2sKn),
            (.best10s, watch.best10sMps, phone.records.best10sKn),
            (.best5x10s, watch.best5x10sMps, phone.records.best5x10sKn),
            (.best500m, watch.best500mMps, phone.records.best500mKn),
            (.bestNm, watch.bestNmMps, phone.records.bestNmKn),
            (.alpha500, watch.alpha500LiteMps, phone.records.alpha500Kn),
        ]
        for (kind, watchMps, phoneKn) in records {
            guard let watchMps, let phoneKn, watchMps > 0, phoneKn > 0 else { continue }
            let watchKn = watchMps * Units.mpsToKn
            guard abs(phoneKn - watchKn) > recordKnThreshold else { continue }
            out.append(Divergence(metricId: kind.rawValue,
                                  labelId: "tokens.recordWindow." + kind.rawValue,
                                  watchValue: watchKn, phoneValue: phoneKn,
                                  unitKind: "speedKn"))
        }

        let counts: [(String, Int?, Int)] = [
            ("flights", watch.flightCount, phone.summary.flightCount),
            ("tacks", watch.tackCount, phone.summary.turns.tacks),
            ("jibes", watch.jibeCount, phone.summary.turns.jibes),
            ("takeoffAttempts", watch.takeoffAttempts, phone.summary.takeoff.takeoffAttempts),
            ("takeoffs", watch.takeoffSuccesses, phone.summary.takeoff.takeoffSuccesses),
        ]
        for (id, watchCount, phoneCount) in counts {
            guard let watchCount, abs(phoneCount - watchCount) > countThreshold else { continue }
            out.append(Divergence(metricId: id, labelId: "presentation.divergence." + id,
                                  watchValue: Double(watchCount),
                                  phoneValue: Double(phoneCount), unitKind: "count"))
        }
        return out
    }
}
