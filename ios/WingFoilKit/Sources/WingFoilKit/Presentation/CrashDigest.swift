import Foundation

/// **One crash, hang or disk-write exception, reduced to the four facts a reply needs.**
///
/// iOS already collects these. `MXMetricManager` hands the app an `MXDiagnosticPayload` a
/// day or so after the fact, and App Store Connect's beta feedback does not carry it: a
/// tester who writes "it quit on me yesterday" is describing a crash log that exists on his
/// own phone and reaches nobody. So the app keeps the last few, and the feedback mail
/// carries them under the rule with the rest of the diagnostics.
///
/// **Why the parsing lives in the kit.** The payload arrives as JSON — MetricKit's own
/// `jsonRepresentation()` — and turning that into four fields is a rule that can be wrong
/// without anybody noticing until a mail arrives with a blank frame in it. The kit is where
/// the test suite can read it, and it needs no MetricKit to do so. The app's half is the
/// subscription and the file.
///
/// **Nothing here is sent by anything.** A digest is written to a file in the app's own
/// container and printed into a mail the rider reads before he taps Send.
public struct CrashDigest: Codable, Sendable, Equatable, Identifiable {

    /// The three kinds iOS reports that are worth a rider's mail. CPU exceptions are left
    /// out: they describe a battery cost, not a failure the rider saw.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case crash, hang, diskWrite

        /// The word the mail prints, and the plural the count line uses.
        public var label: String {
            switch self {
            case .crash: "Crash"
            case .hang: "Hang"
            case .diskWrite: "Disk write"
            }
        }

        public var plural: String {
            switch self {
            case .crash: "Crashes"
            case .hang: "Hangs"
            case .diskWrite: "Disk writes"
            }
        }
    }

    public let kind: Kind
    /// When iOS says it happened — the payload's own end stamp, or the moment the payload
    /// arrived when that stamp cannot be read.
    public let date: Date
    /// What iOS called it: a termination reason, a signal, a hang duration. Nil when the
    /// payload's metadata says nothing this reader would understand.
    public let reason: String?
    /// The deepest frame of the attributed thread — where the app actually was.
    ///
    /// **Symbolicated as far as the payload allows, which is not far.** MetricKit sends
    /// binary names and text-segment offsets, never symbols, so this is `WingFoil +0x1b2c3`
    /// and an `atos` run away from a function name. It is still the one line that tells two
    /// reports apart.
    public let topFrame: String?
    /// The build the crash happened on. A tester who has since updated is reporting
    /// something already fixed, and this is the only thing that says so.
    public let build: String?

    /// Stable across a re-read of the same file: the same crash is the same row.
    public var id: String { kind.rawValue + "|" + date.description + "|" + (topFrame ?? "") }

    public init(kind: Kind, date: Date, reason: String?, topFrame: String?, build: String?) {
        self.kind = kind
        self.date = date
        self.reason = reason
        self.topFrame = topFrame
        self.build = build
    }
}

/// **The kept crashes, as a file and as a rule.**
///
/// The app owns the subscription and the directory; this owns what a payload means, how many
/// are kept and in what order. Both halves are here rather than in the app for the ordinary
/// reason: the payload shape is a contract with somebody else's framework, and the test suite
/// has to be able to read a fixture of it.
public enum CrashLog {

    /// How many are kept. Ten is about a year of a beta's worth of real failures and about
    /// four kilobytes of JSON, and the mail prints fewer than that.
    public static let keepCount = 10

    /// How many the mail lists before it stops naming them. The rest are counted.
    public static let listCount = 8

    // MARK: - The file

    /// The kept crashes, newest first, out of the bytes the app stored.
    ///
    /// A file that cannot be read is an empty list and never an error: a mail that refused
    /// to compose because a diagnostics file was corrupt would cost a bug report to save a
    /// footnote.
    public static func decode(_ data: Data) -> [CrashDigest] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CrashDigest].self, from: data)) ?? []
    }

    public static func encode(_ digests: [CrashDigest]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(digests)
    }

    /// The new payload's digests in front of the kept ones, de-duplicated and capped.
    ///
    /// MetricKit re-delivers: the same crash can arrive in two daily payloads, and a mail
    /// that listed it twice would read as two failures. `CrashDigest.id` is what makes them
    /// the same row.
    public static func merge(_ kept: [CrashDigest], with arrived: [CrashDigest])
        -> [CrashDigest] {
        var seen = Set<String>()
        return (arrived + kept)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
            .prefix(keepCount)
            .map { $0 }
    }

    // MARK: - The payload

    /// **MetricKit's `jsonRepresentation()`, read as digests.**
    ///
    /// The shape is Apple's and is not versioned, so every step of the walk is optional and
    /// a key that has moved costs one field rather than the whole report. What is taken:
    /// the three diagnostic arrays, each entry's `diagnosticMetaData` for the reason and the
    /// build, and the deepest frame of the first attributed call stack.
    ///
    /// - Parameter receivedAt: what the date falls back to when the payload's own stamp
    ///   cannot be parsed. The app passes `Date()`; a test passes a fixed date.
    public static func digests(fromPayloadJSON data: Data,
                               receivedAt: Date = Date()) -> [CrashDigest] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        let stamp = payloadDate(root) ?? receivedAt
        let arrays: [(String, CrashDigest.Kind)] = [
            ("crashDiagnostics", .crash),
            ("hangDiagnostics", .hang),
            ("diskWriteExceptionDiagnostics", .diskWrite),
        ]
        return arrays.flatMap { key, kind in
            (root[key] as? [[String: Any]] ?? []).map { digest($0, kind: kind, date: stamp) }
        }
    }

    private static func digest(_ entry: [String: Any], kind: CrashDigest.Kind,
                               date: Date) -> CrashDigest {
        let meta = entry["diagnosticMetaData"] as? [String: Any] ?? [:]
        return CrashDigest(kind: kind, date: date, reason: reason(meta, kind: kind),
                           topFrame: topFrame(entry),
                           build: meta["appBuildVersion"] as? String)
    }

    /// What iOS called it, in the words the payload happens to carry.
    ///
    /// A crash states a termination reason ("Namespace SIGNAL, Code 11"), sometimes only a
    /// signal number; a hang states how long it lasted; a disk-write exception states how
    /// much it wrote. Each is the one number a reader of that kind of report asks for first.
    private static func reason(_ meta: [String: Any], kind: CrashDigest.Kind) -> String? {
        switch kind {
        case .crash:
            if let stated = meta["terminationReason"] as? String, !stated.isEmpty {
                return stated
            }
            if let signal = meta["signal"] as? Int { return "Signal " + String(signal) }
            if let type = meta["exceptionType"] as? Int {
                return "Exception type " + String(type)
            }
            return nil
        case .hang:
            return measurement(meta["hangDuration"]).map { "Hung for " + $0 }
        case .diskWrite:
            return measurement(meta["writesCaused"]).map { "Wrote " + $0 }
        }
    }

    /// An `MXUnit` measurement, whichever of its three spellings arrived: a dictionary of
    /// value and unit, a formatted string, or a bare number.
    private static func measurement(_ raw: Any?) -> String? {
        if let pair = raw as? [String: Any], let value = pair["value"] as? Double {
            let unit = pair["unit"] as? String ?? ""
            return trimmed(value) + (unit.isEmpty ? "" : " " + unit)
        }
        if let text = raw as? String, !text.isEmpty { return text }
        if let value = raw as? Double { return trimmed(value) }
        return nil
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// **The deepest frame of the thread iOS blamed.**
    ///
    /// MetricKit's tree runs the other way round from a crash log: `callStackRootFrames`
    /// holds the outermost frame, and `subFrames` descends towards where the app actually
    /// was. So the walk goes down the first sub-frame of each level until there is none
    /// left, which is the line worth printing. The attributed stack is preferred when the
    /// payload marks one; otherwise the first stack is taken.
    private static func topFrame(_ entry: [String: Any]) -> String? {
        let tree = entry["callStackTree"] as? [String: Any]
        let stacks = tree?["callStacks"] as? [[String: Any]] ?? []
        let stack = stacks.first { $0["threadAttributed"] as? Bool == true } ?? stacks.first
        guard var frame = (stack?["callStackRootFrames"] as? [[String: Any]])?.first
        else { return nil }
        while let deeper = (frame["subFrames"] as? [[String: Any]])?.first {
            frame = deeper
        }
        let binary = frame["binaryName"] as? String ?? "unknown"
        guard let offset = frame["offsetIntoBinaryTextSegment"] as? Int else { return binary }
        return binary + " +0x" + String(offset, radix: 16)
    }

    /// The payload's own window. `timeStampEnd` rather than the beginning: a payload covers
    /// a day, and the end of it is the closest thing to when the failure happened.
    private static func payloadDate(_ root: [String: Any]) -> Date? {
        for key in ["timeStampEnd", "timeStampBegin"] {
            if let text = root[key] as? String, let date = parse(text) { return date }
        }
        return nil
    }

    /// Apple prints the payload window as `2026-09-14 15:05:00 +0000`, and has printed it
    /// as ISO-8601 too. Both are tried, in a fixed locale, because a diagnostic stamp is a
    /// machine fact and must not be read through whatever calendar the phone is set to.
    private static func parse(_ text: String) -> Date? {
        for format in ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return ISO8601DateFormatter().date(from: text)
    }
}
