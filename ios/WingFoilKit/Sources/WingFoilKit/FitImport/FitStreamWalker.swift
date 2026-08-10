import Foundation

/// One local message type's declared layout, exactly as the file states it.
struct FitMessageDefinition {
    struct Field {
        var num: UInt8
        var offset: Int          // within the message payload
        var size: Int
        var baseType: UInt8
    }
    struct DevField {
        var num: UInt8
        var offset: Int          // within the message payload (after the native fields)
        var size: Int
        var developerDataIndex: UInt8
    }

    var globalNum: UInt16
    var bigEndian: Bool
    var fields: [Field] = []
    var devFields: [DevField] = []
    var nativeBytes: Int = 0
    var devBytes: Int = 0

    var totalBytes: Int { nativeBytes + devBytes }
}

/// Walks the FIT record layer (definition + data messages) without interpreting any
/// profile semantics — the shared front end for `FitStreamSanitizer` (which decides what
/// the vendored C decoder may safely see) and `FitDeveloperFieldReader` (which decodes the
/// developer fields that decoder gets wrong).
///
/// Deliberately independent of FitFileParser: it only needs the self-describing record
/// layer (definition messages carry every field's size), never the FIT profile.
enum FitStreamWalker {

    enum Event {
        /// A definition message. `range` covers the header byte through the last field def.
        case definition(local: Int, def: FitMessageDefinition, range: Range<Int>)
        /// A data message. `range` includes the header byte; `payload` is the data only.
        case data(local: Int, def: FitMessageDefinition, range: Range<Int>, payload: Range<Int>)
    }

    struct Layout {
        var headerSize: Int
        /// End of the data section (exclusive); the 2-byte file CRC follows.
        var dataEnd: Int
    }

    // FIT record header bits (fit.h).
    private static let timeRecBit: UInt8 = 0x80
    private static let timeTypeMask: UInt8 = 0x60
    private static let timeTypeShift: UInt8 = 5
    private static let defBit: UInt8 = 0x40
    private static let devDataBit: UInt8 = 0x20
    private static let localTypeMask: UInt8 = 0x0F

    /// Visits every message in the first FIT chunk. Returns nil — without having emitted a
    /// partial result the caller could act on — if `bytes` is not a walkable plain FIT file,
    /// so every caller can fall back to leaving the stream alone.
    static func walk(_ bytes: [UInt8], _ visit: (Event) -> Void) -> Layout? {
        guard let layout = layout(of: bytes) else { return nil }
        var defs = [FitMessageDefinition?](repeating: nil, count: 16)
        var events: [Event] = []
        var p = layout.headerSize
        let end = layout.dataEnd

        while p < end {
            let start = p
            let hdr = bytes[p]
            p += 1

            // Data message — compressed-timestamp header (2-bit local type) or normal.
            if hdr & timeRecBit != 0 || hdr & defBit == 0 {
                let local = hdr & timeRecBit != 0
                    ? Int((hdr & timeTypeMask) >> timeTypeShift)
                    : Int(hdr & localTypeMask)
                guard let def = defs[local] else { return nil }
                let payload = p..<(p + def.totalBytes)
                p = payload.upperBound
                guard p <= end else { return nil }
                events.append(.data(local: local, def: def, range: start..<p, payload: payload))
                continue
            }

            // Definition message.
            let local = Int(hdr & localTypeMask)
            guard p + 5 <= end else { return nil }
            let bigEndian = bytes[p + 1] == 1
            let globalNum = bigEndian
                ? UInt16(bytes[p + 2]) << 8 | UInt16(bytes[p + 3])
                : UInt16(bytes[p + 3]) << 8 | UInt16(bytes[p + 2])
            let fieldCount = Int(bytes[p + 4])
            p += 5

            var def = FitMessageDefinition(globalNum: globalNum, bigEndian: bigEndian)
            guard p + 3 * fieldCount <= end else { return nil }
            for i in 0..<fieldCount {
                let size = Int(bytes[p + 3 * i + 1])
                def.fields.append(.init(num: bytes[p + 3 * i], offset: def.nativeBytes,
                                        size: size, baseType: bytes[p + 3 * i + 2]))
                def.nativeBytes += size
            }
            p += 3 * fieldCount

            if hdr & devDataBit != 0 {
                guard p < end else { return nil }
                let devCount = Int(bytes[p])
                p += 1
                guard p + 3 * devCount <= end else { return nil }
                for i in 0..<devCount {
                    let size = Int(bytes[p + 3 * i + 1])
                    def.devFields.append(.init(num: bytes[p + 3 * i],
                                               offset: def.nativeBytes + def.devBytes,
                                               size: size,
                                               developerDataIndex: bytes[p + 3 * i + 2]))
                    def.devBytes += size
                }
                p += 3 * devCount
            }

            defs[local] = def
            events.append(.definition(local: local, def: def, range: start..<p))
        }
        guard p == end else { return nil }   // ragged tail

        events.forEach(visit)
        return layout
    }

    /// Header/data-section geometry of the first FIT chunk, or nil if this is not one.
    static func layout(of bytes: [UInt8]) -> Layout? {
        guard bytes.count >= 14 else { return nil }
        let headerSize = Int(bytes[0])
        guard headerSize == 12 || headerSize == 14, bytes.count > headerSize,
              bytes[8] == 0x2E, bytes[9] == 0x46, bytes[10] == 0x49, bytes[11] == 0x54
        else { return nil }
        let dataSize = Int(bytes[4]) | Int(bytes[5]) << 8
            | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
        let dataEnd = headerSize + dataSize
        guard dataSize > 0, dataEnd + 2 <= bytes.count else { return nil }
        return Layout(headerSize: headerSize, dataEnd: dataEnd)
    }

    /// Garmin FIT CRC-16 (fit_crc.m), nibble-table form.
    static func crc16(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        let table: [UInt16] = [
            0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
            0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
        ]
        var crc: UInt16 = 0
        for byte in bytes {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte & 0xF)]

            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte >> 4)]
        }
        return crc
    }
}
