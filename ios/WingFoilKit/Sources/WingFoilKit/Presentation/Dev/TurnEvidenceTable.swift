import Foundation

/// **One row per sample around a turn — the numbers the verdict was read from, unrounded.**
///
/// The strip draws one channel and the trace names the deciding samples; this is the rest of
/// the recording between them, so a reader who does not believe a step can check it against the
/// row it happened on. Ten seconds before the sweep to thirty after, which is the entry window,
/// the sweep, the low-point lag, the outcome window and the whole quiet tail with room either
/// side — every span the ladder reads, on one clock.
///
/// **Gaps are shown, not skipped.** A row whose `gapBefore` is true is the far side of a
/// recording hole, and every window in the engine stops at one; a table that closed the hole up
/// would make the ladder's short windows look arbitrary.
///
/// Pure, and shared with the CSV export so the file and the screen cannot say different things.
public struct TurnEvidenceRow: Sendable, Equatable {

    /// Which of the engine's spans this sample falls in. One band per row: the most specific
    /// wins, because a sample two seconds past the sweep is in the low-point lag *and* the
    /// outcome window *and* the quiet tail, and colouring it three times says nothing.
    public enum Band: String, Sendable, Equatable, CaseIterable {
        /// `entrySpeedWindow` before the sweep — where `entryKn` is the maximum.
        case entry
        /// `ts … endTs`: the heading actually turning.
        case sweep
        /// `minSpeedLag` past the sweep, where the low point may still sit.
        case minLag
        /// The tail the outcome was judged over (`outcomeWindowS` on the record).
        case outcome
        /// `turnCleanQuietS` past the sweep — the clean jibe's extra question.
        case quietTail
        /// Context either side.
        case none

        public var label: String {
            switch self {
            case .entry: return "entry"
            case .sweep: return "sweep"
            case .minLag: return "min-lag"
            case .outcome: return "outcome"
            case .quietTail: return "quiet"
            case .none: return ""
            }
        }
    }

    /// Session clock, seconds from the recording's start.
    public var t: Double
    /// Seconds from the sweep's start — the turn's own clock, and the strip's.
    public var rt: Double
    /// Device Doppler: the recovery test and the flight state.
    public var dopplerKn: Double
    /// min(Doppler, positional) is what the ladder reads; this is the *maneuver* channel
    /// (positional where there is one), which is what the scores were read on.
    public var manoeuvreKn: Double
    /// Course over ground, 0–360, or nil where the sample is outside the sweep's sailing run.
    public var headingDeg: Double?
    /// Signed heading rate leaving this sample, or nil under the same rule.
    public var turnRateDegS: Double?
    /// True wind angle, −180…180, or nil where the session has no wind.
    public var twaDeg: Double?
    /// Inside a flight, above `foilExitSpeed`, not submerged.
    public var flying: Bool
    /// Below `turnStopSpeedFloor` on min(Doppler, positional).
    public var stopped: Bool
    /// The barometer says the wrist is under.
    public var submerged: Bool
    /// Pump strokes in the second ending at this sample.
    public var pumpStrokes: Int
    /// A recording gap precedes this sample — every window in the engine stops here.
    public var gapBefore: Bool
    public var band: Band

    public init(t: Double, rt: Double, dopplerKn: Double, manoeuvreKn: Double,
                headingDeg: Double?, turnRateDegS: Double?, twaDeg: Double?,
                flying: Bool, stopped: Bool, submerged: Bool, pumpStrokes: Int,
                gapBefore: Bool, band: Band) {
        self.t = t
        self.rt = rt
        self.dopplerKn = dopplerKn
        self.manoeuvreKn = manoeuvreKn
        self.headingDeg = headingDeg
        self.turnRateDegS = turnRateDegS
        self.twaDeg = twaDeg
        self.flying = flying
        self.stopped = stopped
        self.submerged = submerged
        self.pumpStrokes = pumpStrokes
        self.gapBefore = gapBefore
        self.band = band
    }
}

public enum TurnEvidenceTable {

    /// How far either side of the sweep the table runs.
    public static let leadS = 10.0
    public static let trailS = 30.0

    /// Every sample in `[ts − leadS, endTs + trailS]`, in time order.
    public static func rows(turnIndex: Int, analysis: SessionAnalysis,
                            context: TurnWorkbench.Context) -> [TurnEvidenceRow] {
        guard analysis.turns.indices.contains(turnIndex), let ev = context.evidence else {
            return []
        }
        let record = analysis.turns[turnIndex]
        let config = context.turn
        let from = record.ts - leadS
        let to = record.endTs + trailS
        let headings = TurnWorkbench.headingSeries(context.clean, from: record.ts,
                                                   to: record.endTs, config: config)
        let lo = searchSortedLeft(ev.t, from)
        let hi = searchSortedRight(ev.t, to)
        guard lo < hi else { return [] }

        var out: [TurnEvidenceRow] = []
        out.reserveCapacity(hi - lo)
        for i in lo..<hi {
            let t = ev.t[i]
            let heading = headings?.heading(at: t)
            out.append(TurnEvidenceRow(
                t: t,
                rt: t - record.ts,
                dopplerKn: ev.doppler[i] * Units.mpsToKn,
                manoeuvreKn: context.clean.samples.indices.contains(i)
                    ? context.clean.samples[i].hybridMps * Units.mpsToKn
                    : ev.doppler[i] * Units.mpsToKn,
                headingDeg: heading,
                turnRateDegS: headings?.rate(at: t),
                twaDeg: TurnWorkbench.twa(heading: heading, windDirDeg: context.windDirDeg),
                flying: ev.flying[i],
                stopped: ev.speed[i] < config.stopSpeedFloorMps,
                submerged: ev.submerged[i],
                // The second *ending* here, so a stroke is counted once and lands on the row
                // the reader is looking at rather than the one before it.
                pumpStrokes: context.pump?.strokes(from: t - 1, to: t).count ?? 0,
                gapBefore: ev.gap[i],
                band: band(t: t, record: record, config: config)))
        }
        return out
    }

    /// Most specific span wins — see `TurnEvidenceRow.Band`.
    static func band(t: Double, record: TurnRecord,
                     config: TurnConfig) -> TurnEvidenceRow.Band {
        if t >= record.ts, t <= record.endTs { return .sweep }
        if t >= record.ts - config.entrySpeedWindowS, t < record.ts { return .entry }
        guard t > record.endTs else { return .none }
        if t <= record.endTs + config.minSpeedLagS { return .minLag }
        if t <= record.endTs + record.outcomeWindowS { return .outcome }
        if config.cleanQuietS > 0, t <= record.endTs + config.cleanQuietS { return .quietTail }
        return .none
    }

    // MARK: - CSV

    /// The same table as a file. Header names are the column headings, lower-cased and
    /// unit-suffixed, so a spreadsheet needs no legend; booleans are `1`/`0` rather than
    /// `true`/`false` because every tool that opens this will want to sum them.
    public static func csv(_ rows: [TurnEvidenceRow]) -> String {
        var out = "t_s,rt_s,doppler_kn,manoeuvre_kn,heading_deg,turn_rate_deg_s,twa_deg,"
            + "flying,stopped,wrist_under,pump_strokes,gap_before,band\n"
        for row in rows {
            out += [
                String(format: "%.3f", row.t),
                String(format: "%.3f", row.rt),
                String(format: "%.2f", row.dopplerKn),
                String(format: "%.2f", row.manoeuvreKn),
                row.headingDeg.map { String(format: "%.1f", $0) } ?? "",
                row.turnRateDegS.map { String(format: "%.2f", $0) } ?? "",
                row.twaDeg.map { String(format: "%.1f", $0) } ?? "",
                row.flying ? "1" : "0",
                row.stopped ? "1" : "0",
                row.submerged ? "1" : "0",
                "\(row.pumpStrokes)",
                row.gapBefore ? "1" : "0",
                row.band == .none ? "" : row.band.label,
            ].joined(separator: ",") + "\n"
        }
        return out
    }

    /// `2026-08-07-0754-nago-torbole-turn12.csv` — the session's own name and the turn's
    /// index, reduced to something a filesystem and a mail attachment can both carry.
    public static func filename(session: String, turnIndex: Int) -> String {
        let slug = session.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let stem = slug.isEmpty ? "session" : String(slug.prefix(60))
        return "\(stem)-turn\(turnIndex).csv"
    }
}
