import Foundation

/// A decoded developer-field value. Our schema uses numbers everywhere except
/// `session.discipline`, which is `string(16)` (docs/fit-schema.md).
enum FitDevValue: Equatable {
    case number(Double)
    case text(String)

    var double: Double? { if case let .number(v) = self { return v }; return nil }
    var string: String? { if case let .text(v) = self { return v }; return nil }
    var int: Int? { double.map { Int($0.rounded()) } }
}

/// Developer fields decoded straight from the FIT byte stream, in file order per message type.
struct FitDeveloperFields {
    /// Global message number → one dictionary per data message of that type, file order.
    /// Messages without developer data get an empty dictionary, so indices stay aligned
    /// with `FitFile.messages(forMessageType:)`.
    var byMessageType: [UInt16: [[String: FitDevValue]]] = [:]

    var isEmpty: Bool { byMessageType.allSatisfy { $0.value.allSatisfy(\.isEmpty) } }

    func fields(forMessageType type: UInt16) -> [[String: FitDevValue]] {
        byMessageType[type] ?? []
    }
}

/// Decodes FIT developer fields ourselves, because FitFileParser cannot.
///
/// ## Why this exists
/// `FitDevDataParser.recordDeveloperField:` (FitDevDataParser.m) `memcpy`s the raw message
/// buffer onto the profile struct `FIT_FIELD_DESCRIPTION_MESG`. In `.generic`
/// (`raw_mesg = 1`) mode that buffer is in **file** layout, not profile layout, and the
/// struct reserves 64 bytes for `field_name`. Our watch writes `field_name` as a short
/// variable-length string, so every struct member past it is read from the wrong offset:
/// `desc->native_mesg_num` comes back as garbage, never equals `record`/`session`, and
/// `parseData` therefore yields nothing. Field *names* survive (they sit before the
/// variable-length field), which is why `devDataParser.nativeFields()` looks healthy while
/// no message ever carries a developer value.
///
/// Rather than patch the vendored C, we decode the developer layer from the bytes. The FIT
/// record layer is fully self-describing — definition messages carry every field's size —
/// so this needs no profile knowledge beyond `field_description` (global 206), whose own
/// field numbers are fixed by the FIT spec.
enum FitDeveloperFieldReader {

    /// `field_description` global message number.
    private static let fieldDescriptionMesgNum: UInt16 = 206
    /// `field_description` native field numbers (FIT profile, fixed by the spec).
    private enum FD {
        static let developerDataIndex: UInt8 = 0
        static let fieldDefinitionNumber: UInt8 = 1
        static let fitBaseTypeId: UInt8 = 2
        static let fieldName: UInt8 = 3
        static let scale: UInt8 = 6
        static let offset: UInt8 = 7
    }

    private struct Description {
        var name: String
        var baseType: UInt8
        var scale: Double?
        var offset: Double?
    }

    /// Decodes every developer field in `data`. Returns an empty result when the stream is
    /// not walkable or carries no developer data — never throws, per the fail-soft contract.
    ///
    /// Run this on the *sanitized* bytes: message indices must line up with what
    /// FitFileParser actually yields.
    static func read(_ data: Data) -> FitDeveloperFields {
        let bytes = [UInt8](data)
        var descriptions: [UInt16: Description] = [:]   // devIndex << 8 | fieldNum
        var result = FitDeveloperFields()

        let walked = FitStreamWalker.walk(bytes) { event in
            guard case let .data(_, def, _, payload) = event else { return }

            if def.globalNum == fieldDescriptionMesgNum {
                if let (key, description) = describe(bytes, def: def, payload: payload) {
                    descriptions[key] = description
                }
                return
            }

            var values: [String: FitDevValue] = [:]
            for field in def.devFields {
                let key = UInt16(field.developerDataIndex) << 8 | UInt16(field.num)
                guard let description = descriptions[key] else { continue }
                let slice = (payload.lowerBound + field.offset)
                    ..< min(payload.lowerBound + field.offset + field.size, payload.upperBound)
                guard slice.lowerBound < slice.upperBound,
                      let value = decode(bytes, slice, baseType: description.baseType,
                                         bigEndian: def.bigEndian,
                                         scale: description.scale, offset: description.offset)
                else { continue }
                values[description.name] = value
            }
            result.byMessageType[def.globalNum, default: []].append(values)
        }

        return walked == nil ? FitDeveloperFields() : result
    }

    /// Reads one `field_description` message into a keyed description.
    private static func describe(_ bytes: [UInt8], def: FitMessageDefinition,
                                 payload: Range<Int>) -> (UInt16, Description)? {
        func raw(_ num: UInt8) -> Range<Int>? {
            guard let f = def.fields.first(where: { $0.num == num }) else { return nil }
            let start = payload.lowerBound + f.offset
            let slice = start..<min(start + f.size, payload.upperBound)
            return slice.lowerBound < slice.upperBound ? slice : nil
        }
        func number(_ num: UInt8, _ baseType: UInt8) -> Double? {
            guard let slice = raw(num) else { return nil }
            return decode(bytes, slice, baseType: baseType, bigEndian: def.bigEndian,
                          scale: nil, offset: nil)?.double
        }

        guard let nameSlice = raw(FD.fieldName),
              let name = string(bytes, nameSlice), !name.isEmpty,
              let devIndex = number(FD.developerDataIndex, 2),      // uint8
              let fieldNum = number(FD.fieldDefinitionNumber, 2),   // uint8
              let baseType = number(FD.fitBaseTypeId, 2)            // uint8
        else { return nil }

        let key = UInt16(UInt8(devIndex)) << 8 | UInt16(UInt8(fieldNum))
        return (key, Description(name: name, baseType: UInt8(baseType),
                                 scale: number(FD.scale, 2),
                                 offset: number(FD.offset, 1)))     // sint8
    }

    // MARK: - Base-type decoding

    /// Decodes one scalar. Arrays are not part of our schema; the first element is taken.
    /// Returns nil for the FIT "invalid" sentinel of the type, matching the lab's
    /// fitdecode behaviour of dropping invalid values entirely.
    private static func decode(_ bytes: [UInt8], _ slice: Range<Int>, baseType: UInt8,
                               bigEndian: Bool, scale: Double?, offset: Double?) -> FitDevValue? {
        let type = baseType & 0x1F
        if type == 7 {   // string
            guard let s = string(bytes, slice), !s.isEmpty else { return nil }
            return .text(s)
        }

        func uint(_ width: Int) -> UInt64? {
            guard slice.count >= width else { return nil }
            var v: UInt64 = 0
            for i in 0..<width {
                let byte = UInt64(bytes[slice.lowerBound + i])
                v |= byte << (8 * UInt64(bigEndian ? width - 1 - i : i))
            }
            return v
        }
        /// Two's-complement reinterpretation of `width` bytes.
        func sint(_ width: Int) -> Int64? {
            guard let u = uint(width) else { return nil }
            let signBit = UInt64(1) << (8 * UInt64(width) - 1)
            return u & signBit != 0 ? Int64(bitPattern: u | ~(signBit &* 2 &- 1)) : Int64(u)
        }
        func scaled(_ v: Double) -> FitDevValue {
            var out = v
            if let scale, scale > 0 { out /= scale }
            if let offset { out -= offset }
            return .number(out)
        }

        switch type {
        case 0, 2, 13:                                              // enum, uint8, byte
            guard let v = uint(1), v != 0xFF else { return nil }
            return scaled(Double(v))
        case 1:                                                     // sint8
            guard let v = sint(1), v != 0x7F else { return nil }
            return scaled(Double(v))
        case 10:                                                    // uint8z
            guard let v = uint(1), v != 0 else { return nil }
            return scaled(Double(v))
        case 3:                                                     // sint16
            guard let v = sint(2), v != 0x7FFF else { return nil }
            return scaled(Double(v))
        case 4:                                                     // uint16
            guard let v = uint(2), v != 0xFFFF else { return nil }
            return scaled(Double(v))
        case 11:                                                    // uint16z
            guard let v = uint(2), v != 0 else { return nil }
            return scaled(Double(v))
        case 5:                                                     // sint32
            guard let v = sint(4), v != 0x7FFF_FFFF else { return nil }
            return scaled(Double(v))
        case 6:                                                     // uint32
            guard let v = uint(4), v != 0xFFFF_FFFF else { return nil }
            return scaled(Double(v))
        case 12:                                                    // uint32z
            guard let v = uint(4), v != 0 else { return nil }
            return scaled(Double(v))
        case 8:                                                     // float32
            guard let v = uint(4), v != 0xFFFF_FFFF else { return nil }
            return scaled(Double(Float(bitPattern: UInt32(v))))
        case 9:                                                     // float64
            guard let v = uint(8), v != UInt64.max else { return nil }
            return scaled(Double(bitPattern: v))
        case 14:                                                    // sint64
            guard let v = sint(8), v != Int64.max else { return nil }
            return scaled(Double(v))
        case 15:                                                    // uint64
            guard let v = uint(8), v != UInt64.max else { return nil }
            return scaled(Double(v))
        case 16:                                                    // uint64z
            guard let v = uint(8), v != 0 else { return nil }
            return scaled(Double(v))
        default:
            return nil
        }
    }

    /// NUL-terminated UTF-8, trimmed of any trailing padding.
    private static func string(_ bytes: [UInt8], _ slice: Range<Int>) -> String? {
        var end = slice.lowerBound
        while end < slice.upperBound, bytes[end] != 0 { end += 1 }
        guard end > slice.lowerBound else { return nil }
        return String(decoding: bytes[slice.lowerBound..<end], as: UTF8.self)
    }
}
