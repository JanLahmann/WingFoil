import Foundation

/// The one line a tapped mark gains: which flight it belongs to, and what became of it
/// (docs/presentation.md, "Pairing").
///
/// A takeoff, the flight it started and the end that stopped it are three marks on one
/// event, and the map draws all three. Linking them *always* — a leader line, a shared
/// number, a badge on every arrow — buys a fact nobody asked for at the cost of the busiest
/// layer on the map. So the pairing is tap-only, it is one line, and every fact in it is
/// read straight out of the analysis: the flight's own `startTs` / `endTs` / `distM`, its
/// end's `outcome`, its takeoff's `pumps`. The only arithmetic is `endTs - startTs`.
///
/// The strings live here rather than in a view because the web app draws the same four and
/// "the two apps word it differently" is exactly the class of drift `docs/presentation.md`
/// exists to stop.
public enum FlightPairing {

    /// What stopped a flight, in the words the callout uses. The ladder's own three, plus
    /// the honest fourth: a recording that stopped is not a verdict.
    public enum Outcome: String, Sendable, CaseIterable {
        case glidedOut = "glided out"
        case touchdown = "touchdown"
        case fellIn = "fell in"
        case recordingEnded = "recording ended"

        /// From the engine's `flightEnds[].outcome`, with `truncated` overriding it: the
        /// engine still labels a truncated end, and reporting that label would state as
        /// fact the one thing the data cannot say.
        public init(endOutcome: String, truncated: Bool) {
            if truncated { self = .recordingEnded; return }
            switch endOutcome {
            case "fell_in": self = .fellIn
            case "touchdown": self = .touchdown
            case "unknown": self = .recordingEnded
            default: self = .glidedOut          // glide_out | flew_through
            }
        }
    }

    /// One flight as the pairing states it: everything the four lines need, resolved once.
    public struct Flight: Sendable, Equatable {
        /// Index in `analysis.flights`.
        public let index: Int
        /// How many flights the session has — the "of 55" half of the segment line.
        public let count: Int
        public let startTs: Double
        public let endTs: Double
        /// nil when the flight covered no measured distance.
        public let distM: Double?
        /// Strokes of the run that produced it; nil without an accelerometer stream.
        public let pumps: Int?
        public let outcome: Outcome

        public init(index: Int, count: Int, startTs: Double, endTs: Double, distM: Double?,
                    pumps: Int?, outcome: Outcome) {
            self.index = index
            self.count = count
            self.startTs = startTs
            self.endTs = endTs
            self.distM = distM
            self.pumps = pumps
            self.outcome = outcome
        }

        /// 1-based: what the rider reads.
        public var number: Int { index + 1 }
        public var durationS: Double { endTs - startTs }
    }

    // MARK: - Resolving

    /// The session's flights, each with the end that stopped it and the strokes that
    /// started it. Index-aligned with `analysis.flights`.
    public static func flights(_ analysis: SessionAnalysis) -> [Flight] {
        let ends = Dictionary(analysis.flightEnds.map { ($0.flightIndex, $0) }) { a, _ in a }
        let count = analysis.flights.count
        return analysis.flights.enumerated().map { index, flight in
            let end = ends[index]
            return Flight(index: index, count: count, startTs: flight.startTs,
                          endTs: flight.endTs,
                          distM: flight.distM > 0 ? flight.distM : nil,
                          pumps: flight.takeoffPumps,
                          outcome: Outcome(endOutcome: end?.outcome ?? "unknown",
                                           truncated: end?.truncated ?? true))
        }
    }

    /// The flight a takeoff started: the one whose `startTs` is the takeoff's own.
    ///
    /// Matched on the instant rather than trusting the two arrays to be index-aligned. They
    /// are — `verify_presentation.py` asserts "takeoff i starts flight i, at the same
    /// instant" on every fixture — and this is what makes that assertion checkable here too:
    /// a takeoff whose flight cannot be resolved gets no pairing line rather than a wrong
    /// number.
    public static func flight(startingAt t: Double, in flights: [Flight]) -> Flight? {
        flights.first { $0.startTs == t } ?? flights.first { t >= $0.startTs && t <= $0.endTs }
    }

    public static func flight(at index: Int, in flights: [Flight]) -> Flight? {
        flights.indices.contains(index) ? flights[index] : nil
    }

    /// The flight covering an instant — what a tap on a flying stretch of track resolves to.
    public static func flight(covering t: Double, in flights: [Flight]) -> Flight? {
        flights.first { t >= $0.startTs && t <= $0.endTs }
    }

    // MARK: - The four lines

    /// `starts flight 12 · 1:23 · ended: touchdown`
    public static func takeoffLine(_ flight: Flight) -> String {
        "starts flight \(flight.number) · \(clock(flight.durationS)) "
            + "· ended: \(flight.outcome.rawValue)"
    }

    /// `no flight · 3 strokes` — the one mark in the takeoff layer that starts no flight,
    /// so it names no flight either.
    public static func failedLine(strokes: Int) -> String {
        "no flight · \(strokes) stroke\(strokes == 1 ? "" : "s")"
    }

    /// `ends flight 12 · started 41:07 · 7 pumps`
    ///
    /// The stroke count is *absent* without an accelerometer stream, never `0 pumps`: "the
    /// wind did it" and "nobody measured" are different facts and only one of them is true.
    public static func flightEndLine(_ flight: Flight) -> String {
        var line = "ends flight \(flight.number) · started \(clock(flight.startTs))"
        if let pumps = flight.pumps { line += " · \(pumps) pump\(pumps == 1 ? "" : "s")" }
        return line
    }

    /// `flight 12 of 55 · 1:23 · 272 m · ended: touchdown`
    public static func flightLine(_ flight: Flight) -> String {
        var line = "flight \(flight.number) of \(flight.count) · \(clock(flight.durationS))"
        if let distM = flight.distM { line += " · \(metres(distM))" }
        return line + " · ended: \(flight.outcome.rawValue)"
    }

    // MARK: - Formatting

    /// `m:ss`, or `h:mm:ss` past an hour — the web app's `hms`, so a line written on one
    /// platform reads identically on the other.
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// Whole metres below a kilometre, then two decimals of one — the same break the rest of
    /// the app makes between "how far was that run" and "how far did I ride today".
    public static func metres(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.2f km", m / 1000) : String(format: "%.0f m", m)
    }
}
