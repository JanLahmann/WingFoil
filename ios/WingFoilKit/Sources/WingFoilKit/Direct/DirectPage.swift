import Foundation

/// One page of a direct transfer, decoded off the link (docs/transfer-format.md §3).
///
/// The peer of `CompanionSummary` and validated as hard, for the same reason: this crosses a
/// process boundary from Garmin Connect Mobile, arrives typed `Any`, and may come from a
/// watch build older or newer than this app. Nothing is force-unwrapped, every number is
/// range-checked, and a page that fails any check is refused whole rather than written to
/// disk. It is `Sendable` on purpose — the SDK's delegate callback is `nonisolated`, so the
/// page is decoded on whatever thread the SDK chose and only then crosses to the main actor
/// (the callback-isolation trap the companion link's header spells out).
public struct DirectPage: Sendable, Equatable {

    /// The only page-message schema this build reads. The watch's `cjr` value is the other
    /// half of this constant.
    public static let schemaVersion = 1

    /// Session start, epoch seconds — the card's `KEY_START`, and half of the ±60 s dedupe
    /// key (ADR-013). It is also the inbox directory's name.
    public let sessionStartEpochS: Int
    /// 0 for the record stream. Stream 1 is dev3's wrist magnitudes.
    public let stream: Int
    /// Page index, from 0.
    public let index: Int
    /// How many pages the stream has, or 0 while it is still being recorded.
    public let pageCount: Int
    /// True on the last page of the stream (`e = 1`).
    public let isLast: Bool
    /// The payload. `ByteArray` on API ≥ 6.0.0, `Array<Number>` below it.
    public let bytes: Data

    /// The key that tells a page message from the card. A receiver routes on it before it
    /// decodes anything, so the two paths can never take each other's messages.
    public static let messageKey = "cjr"

    enum Key {
        static let version = DirectPage.messageKey
        static let session = "sid"
        static let stream = "st"
        static let index = "p"
        static let count = "n"
        static let end = "e"
        static let bytes = "b"
    }

    /// 2010-01-01 … 2100-01-01, the same window a card's start has to land in.
    static let plausibleEpoch = CompanionSummary.plausibleEpoch
    /// A two-hour session is thirteen pages; a day of them could not reach this.
    static let maxPages = 4096

    public init(sessionStartEpochS: Int, stream: Int, index: Int, pageCount: Int,
                isLast: Bool, bytes: Data) {
        self.sessionStartEpochS = sessionStartEpochS
        self.stream = stream
        self.index = index
        self.pageCount = pageCount
        self.isLast = isLast
        self.bytes = bytes
    }

    /// Decodes a page message, or throws. Never traps.
    public init(payload: Any?) throws {
        guard let dictionary = Self.entries(payload) else {
            throw CompanionDecodeError.notADictionary
        }
        guard let rawVersion = dictionary[Key.version] else {
            throw CompanionDecodeError.missingSchemaVersion
        }
        guard let version = CompanionSummary.integer(rawVersion) else {
            throw CompanionDecodeError.notAnInteger(key: Key.version)
        }
        guard version == Self.schemaVersion else {
            throw CompanionDecodeError.unsupportedSchemaVersion(version)
        }

        sessionStartEpochS = try Self.value(dictionary, Key.session, in: Self.plausibleEpoch)
        stream = try Self.value(dictionary, Key.stream, in: 0...255)
        index = try Self.value(dictionary, Key.index, in: 0...Self.maxPages)
        // 0 means "still recording", so the page count is not yet known.
        pageCount = try Self.value(dictionary, Key.count, in: 0...Self.maxPages)
        // Absent on every page but the last, so a missing key is a 0 rather than a refusal.
        isLast = CompanionSummary.integer(dictionary[Key.end]) == 1

        guard let raw = dictionary[Key.bytes] else {
            throw CompanionDecodeError.missingKey(Key.bytes)
        }
        guard let bytes = Self.payloadBytes(raw), !bytes.isEmpty,
              bytes.count <= DirectStream.pageBytes else {
            throw CompanionDecodeError.notAnInteger(key: Key.bytes)
        }
        self.bytes = bytes
    }

    /// **The two shapes a page of bytes arrives in.**
    ///
    /// `ByteArray` exists only from Connect IQ 6.0.0 — the fenix 8, the fr970 and the enduro
    /// 3 have it, the fenix 7 (5.2.0) and the fenix 5 Plus (3.3.3) do not — so a page from an
    /// older watch is an `Array<Number>`, one byte per 32-bit Number. Both are read here, in
    /// one place, exactly as the link probe already reads its own `b` key. A Number outside
    /// 0…255 means the sender packed something this build cannot unpack (dev3's four-per-
    /// Number encoding), and the page is refused rather than truncated into nonsense.
    static func payloadBytes(_ raw: Any?) -> Data? {
        if let data = raw as? Data { return data }
        if let bytes = raw as? [UInt8] { return Data(bytes) }
        guard let values = raw as? [Any] else { return nil }
        var out = Data(capacity: values.count)
        for value in values {
            guard let byte = CompanionSummary.integer(value), byte >= 0, byte <= 255 else {
                return nil
            }
            out.append(UInt8(byte))
        }
        return out
    }

    /// The ACK this page is answered with, at once: `["cjrAck": [sid, st, p]]`.
    public var ack: [String: Any] {
        Self.ack(sessionStartEpochS: sessionStartEpochS, stream: stream, index: index)
    }

    /// The same message from three integers, for a caller that has the numbers rather than
    /// the page — the link answers a repeat it did not store.
    public static func ack(sessionStartEpochS: Int, stream: Int, index: Int) -> [String: Any] {
        [ackKey: [sessionStartEpochS, stream, index]]
    }

    public static let ackKey = "cjrAck"
    public static let needKey = "cjrNeed"

    /// **The need list, phone → watch.** Sent once the page with `e = 1` has arrived, always
    /// — with the pages that are missing, or with an empty list, which is the watch's signal
    /// that the stream is complete and its buffers can be freed. At most 32 pages, because
    /// the message has to fit the same radio the pages do.
    public static func need(sessionStartEpochS: Int, stream: Int,
                            pages: [Int]) -> [String: Any] {
        [needKey: [sessionStartEpochS, stream, Array(pages.prefix(maxNeed))]]
    }

    public static let maxNeed = 32

    // MARK: - Untyped access

    private static func entries(_ payload: Any?) -> [String: Any]? {
        guard let payload else { return nil }
        if let typed = payload as? [String: Any] { return typed }
        guard let loose = payload as? [AnyHashable: Any] else { return nil }
        var out: [String: Any] = [:]
        for (key, value) in loose {
            if let key = key.base as? String { out[key] = value }
        }
        return out
    }

    private static func value(_ dictionary: [String: Any], _ key: String,
                              in range: ClosedRange<Int>) throws -> Int {
        guard let raw = dictionary[key] else { throw CompanionDecodeError.missingKey(key) }
        guard let number = CompanionSummary.integer(raw) else {
            throw CompanionDecodeError.notAnInteger(key: key)
        }
        guard range.contains(number) else {
            throw CompanionDecodeError.outOfRange(key: key, value: number)
        }
        return number
    }
}
