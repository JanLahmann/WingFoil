import Foundation

/// One watch-vs-phone disagreement, ready to render in the banner.
public struct Divergence: Sendable, Equatable, Identifiable {
    public var id: String { metric }
    /// Rider-facing metric name, e.g. "Foil time" or "Best 2 s".
    public var metric: String
    /// What the watch wrote into the session dev fields.
    public var watch: String
    /// What the phone recomputed from the same FIT.
    public var phone: String
    /// Signed difference, formatted with its unit.
    public var delta: String
}

/// Watch-vs-phone divergence check (docs/algorithms.md "Divergence check", source class (a)
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
                out.append(Divergence(metric: "Foil time",
                                      watch: seconds(w), phone: seconds(p),
                                      delta: String(format: "%+.0f %%", (p - w) / w * 100)))
            }
        }

        let records: [(String, Double?, Double?)] = [
            ("Best 2 s", watch.best2sMps, phone.records.best2sKn),
            ("Best 10 s", watch.best10sMps, phone.records.best10sKn),
            ("5 × 10 s", watch.best5x10sMps, phone.records.best5x10sKn),
            ("Best 500 m", watch.best500mMps, phone.records.best500mKn),
            ("Best 1 NM", watch.bestNmMps, phone.records.bestNmKn),
            ("Alpha 500", watch.alpha500LiteMps, phone.records.alpha500Kn),
        ]
        for (name, watchMps, phoneKn) in records {
            guard let watchMps, let phoneKn, watchMps > 0, phoneKn > 0 else { continue }
            let watchKn = watchMps * Units.mpsToKn
            guard abs(phoneKn - watchKn) > recordKnThreshold else { continue }
            out.append(Divergence(metric: name,
                                  watch: knots(watchKn), phone: knots(phoneKn),
                                  delta: String(format: "%+.2f kn", phoneKn - watchKn)))
        }

        let counts: [(String, Int?, Int)] = [
            ("Flights", watch.flightCount, phone.summary.flightCount),
            ("Tacks", watch.tackCount, phone.summary.turns.tacks),
            ("Jibes", watch.jibeCount, phone.summary.turns.jibes),
            ("Takeoff attempts", watch.takeoffAttempts, phone.summary.takeoff.takeoffAttempts),
            ("Takeoff successes", watch.takeoffSuccesses, phone.summary.takeoff.takeoffSuccesses),
        ]
        for (name, watchCount, phoneCount) in counts {
            guard let watchCount, abs(phoneCount - watchCount) > countThreshold else { continue }
            out.append(Divergence(metric: name, watch: "\(watchCount)", phone: "\(phoneCount)",
                                  delta: String(format: "%+d", phoneCount - watchCount)))
        }
        return out
    }

    private static func knots(_ v: Double) -> String { String(format: "%.2f kn", v) }

    private static func seconds(_ v: Double) -> String {
        let total = Int(v.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
