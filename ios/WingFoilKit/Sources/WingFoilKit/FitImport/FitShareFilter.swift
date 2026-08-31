import Foundation

/// Strips device- and rider-identifying metadata from a FIT activity before it leaves the
/// phone, byte-for-byte — the Swift port of `lab/tools/scrub_fit.py`.
///
/// ## Why a rewrite rather than a re-encode
/// A class-(a) CIQ recording carries 14 developer field descriptions, a `developer_data_id`,
/// thousands of batched `accelerometer_data` messages and a dozen Garmin-private global
/// message numbers that no encoder round-trips. Re-encoding would silently change the very
/// file we are trying to hand over unchanged. So this walks the FIT record layer itself and
/// rewrites it:
///
///   * data records of a *dropped* global message number are omitted entirely,
///   * selected fields of a *patched* message are overwritten in place with the FIT
///     "invalid" value for their base type,
///   * everything else, definitions included, is copied through unmodified.
///
/// `data_size`, the 14-byte header CRC and the trailing file CRC are recomputed. Every
/// surviving byte of the result came from the original.
///
/// ## What is removed, and why
///
///     file_id.serial_number (0/3)      unique watch id             -> 0 (uint32z invalid)
///     device_info.serial_number (23/3) the same id, repeated       -> 0
///     user_profile (global 3)          name, weight, height,       -> dropped
///                                      gender, language
///     global 147                       paired-accessory record:    -> dropped
///                                      BLE address + its name
///     global 79, global 140            Garmin-private blobs of     -> dropped
///                                      lifetime totals and
///                                      physiological metrics
///
/// Everything the receiving app is meant to show survives: the GPS track, heart rate, all
/// developer fields, every lap, the session summary — and, unless `dropAccel` is set, the
/// 100 Hz accelerometer stream. Dropping that stream is the difference between a 1 MB file
/// and a 43 KB one, which is why it is the default for a share.
///
/// **Definition messages are never dropped**, not even for a dropped global number: an
/// unused definition is legal FIT and keeps every local-type slot exactly where it was, so
/// nothing downstream has to be renumbered.
///
/// The rules are pinned against the Python tool byte-for-byte
/// (`FitShareFilterTests`), because "scrubbed" is a claim about a file we hand to someone
/// else and a divergence between the two implementations would be invisible on screen.
public enum FitShareFilter {

    /// Global message numbers whose *data* records are removed wholesale, with the reason
    /// each one is personal. Mirrors `scrub_fit.DROP_MESSAGES`.
    public static let dropMessages: [UInt16: String] = [
        3: "user_profile — name, weight, height, gender, language, wake/sleep times",
        79: "Garmin-private user-metrics blob (physiological metrics, lifetime aggregates)",
        140: "Garmin-private lifetime-totals blob",
        147: "paired-accessory record — BLE address and the accessory's user-given name",
    ]

    /// The high-rate stream, dropped only when `dropAccel` is set.
    public static let accelerometerData: UInt16 = 165

    /// `global << 8 | fieldNum` for every field zeroed in place, with the name the report
    /// uses. The replacement is the FIT "invalid" pattern for the field's base type, so a
    /// parser reports the field as absent rather than as a plausible-looking fake id.
    /// Mirrors `scrub_fit.PATCH_FIELDS`.
    static let patchFields: [UInt32: String] = [
        0 << 8 | 3: "file_id.serial_number",
        23 << 8 | 3: "device_info.serial_number",
    ]

    /// Base type number -> its invalid byte pattern. Only the types we actually patch; a
    /// patch field of any other base type aborts the rewrite rather than guessing, exactly
    /// as the Python tool raises.
    static let invalidBytes: [UInt8: [UInt8]] = [
        0x00: [0xFF],                            // enum
        0x01: [0x7F],                            // sint8
        0x02: [0xFF],                            // uint8
        0x0A: [0x00],                            // uint8z
        0x83: [0xFF, 0x7F],                      // sint16
        0x84: [0xFF, 0xFF],                      // uint16
        0x8B: [0x00, 0x00],                      // uint16z
        0x85: [0xFF, 0xFF, 0xFF, 0x7F],          // sint32
        0x86: [0xFF, 0xFF, 0xFF, 0xFF],          // uint32
        0x8C: [0x00, 0x00, 0x00, 0x00],          // uint32z
    ]

    /// What the rewrite touched — the share sheet's "n messages removed" line, and what the
    /// tests assert on.
    public struct Report: Sendable, Equatable {
        /// Data records dropped, per global message number.
        public var dropped: [UInt16: Int] = [:]
        /// Fields zeroed in place, per `PATCH_FIELDS` label.
        public var patched: [String: Int] = [:]
        /// Data records copied through (patched or not).
        public var kept: Int = 0

        public var droppedTotal: Int { dropped.values.reduce(0, +) }
    }

    // MARK: - The rewriter

    /// The scrubbed bytes, or nil — without a partial result the caller could hand on — if
    /// this is not a plain, self-consistent, single-chunk FIT file. Fail-closed on purpose:
    /// a file we cannot walk is a file we cannot promise anything about, and refusing to
    /// share it is the only safe answer.
    public static func filter(_ bytes: [UInt8], dropAccel: Bool) -> [UInt8]? {
        scrub(bytes, dropAccel: dropAccel)?.bytes
    }

    /// Data-in / Data-out, for the app: the archived `original.fit` is a `Data`.
    public static func filter(_ data: Data, dropAccel: Bool) -> Data? {
        filter([UInt8](data), dropAccel: dropAccel).map { Data($0) }
    }

    /// The rewrite plus the tally of what it did.
    public static func scrub(_ bytes: [UInt8],
                             dropAccel: Bool) -> (bytes: [UInt8], report: Report)? {
        guard let layout = FitStreamWalker.layout(of: bytes) else { return nil }
        // Chained FIT files exist; the corpus has none, and silently sharing only the first
        // chunk would be worse than refusing. Same refusal as the Python tool.
        guard layout.dataEnd + 2 == bytes.count else { return nil }
        // A file that already fails its own CRC is not one we may rewrite and then re-sign:
        // the fresh CRC would certify bytes we know are damaged.
        let storedCRC = UInt16(bytes[layout.dataEnd]) | UInt16(bytes[layout.dataEnd + 1]) << 8
        guard FitStreamWalker.crc16(bytes[0..<layout.dataEnd]) == storedCRC else { return nil }

        var drop = Set(dropMessages.keys)
        if dropAccel { drop.insert(accelerometerData) }

        var tally = Report()
        var failed = false
        /// Half-open byte ranges of the data section copied through verbatim, coalesced,
        /// interleaved with the records that had to be rewritten.
        var pieces: [[UInt8]] = []
        var runStart = layout.headerSize

        func flush(upTo bound: Int) {
            if bound > runStart { pieces.append([UInt8](bytes[runStart..<bound])) }
        }

        guard FitStreamWalker.walk(bytes, { event in
            guard case let .data(_, def, range, payload) = event, !failed else { return }
            if drop.contains(def.globalNum) {
                tally.dropped[def.globalNum, default: 0] += 1
                flush(upTo: range.lowerBound)
                runStart = range.upperBound
                return
            }
            tally.kept += 1
            var patched: [UInt8]?
            for field in def.fields {
                guard let label = patchFields[UInt32(def.globalNum) << 8 | UInt32(field.num)]
                else { continue }
                guard let blank = invalidBytes[field.baseType] else { failed = true; return }
                if patched == nil { patched = [UInt8](bytes[range]) }
                // The pattern is repeated to fill the declared size, so an *array* field
                // blanks every element rather than only its first.
                let start = payload.lowerBound - range.lowerBound + field.offset
                for i in 0..<field.size { patched?[start + i] = blank[i % blank.count] }
                tally.patched[label, default: 0] += 1
            }
            if let patched {
                flush(upTo: range.lowerBound)
                pieces.append(patched)
                runStart = range.upperBound
            }
        }) != nil, !failed else { return nil }
        flush(upTo: layout.dataEnd)

        // Rebuild: the original header with a patched data_size and a fresh header CRC,
        // the kept records, then the file CRC over everything before it.
        var out = [UInt8](bytes[0..<layout.headerSize])
        let dataSize = pieces.reduce(0) { $0 + $1.count }
        out[4] = UInt8(dataSize & 0xFF)
        out[5] = UInt8((dataSize >> 8) & 0xFF)
        out[6] = UInt8((dataSize >> 16) & 0xFF)
        out[7] = UInt8((dataSize >> 24) & 0xFF)
        if layout.headerSize == 14 {
            let headerCRC = FitStreamWalker.crc16(out[0..<12])
            out[12] = UInt8(headerCRC & 0xFF)
            out[13] = UInt8(headerCRC >> 8)
        }
        out.reserveCapacity(layout.headerSize + dataSize + 2)
        for piece in pieces { out.append(contentsOf: piece) }
        let fileCRC = FitStreamWalker.crc16(out[0...])
        out.append(UInt8(fileCRC & 0xFF))
        out.append(UInt8(fileCRC >> 8))

        return (out, tally)
    }

    // MARK: - Naming

    /// A filename a stranger can read in a Files list: `2026-08-30-torbole.fit`.
    ///
    /// The date is the session's own, in the reader's calendar, and the tail is the title
    /// the app already shows for the session, lowercased and reduced to what is safe in a
    /// filename on every platform a share sheet can reach.
    ///
    /// `pathExtension` is here so the *other* thing a session can leave as — the replay clip
    /// (`ReplayRecorder`) — arrives in the same chat under the same name with a different
    /// tail. One naming rule, or a rider ends up with `2026-08-30-torbole.fit` beside
    /// `Replay 3.mp4` and no way to tell they are the same afternoon.
    public static func filename(date: Date, title: String,
                                pathExtension: String = "fit",
                                timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: date)

        var slug = ""
        var lastWasDash = false
        for scalar in title.folding(options: .diacriticInsensitive, locale: nil)
            .lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !slug.isEmpty && !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        slug = String(slug.prefix(40))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "\(stamp).\(pathExtension)" : "\(stamp)-\(slug).\(pathExtension)"
    }
}
