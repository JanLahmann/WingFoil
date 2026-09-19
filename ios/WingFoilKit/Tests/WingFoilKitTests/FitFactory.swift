import Foundation
@testable import WingFoilKit

/// A minimal FIT **writer**, for tests only.
///
/// The corpus is twelve well-behaved recordings from two devices. The shapes that break an
/// importer are the ones no device Jan owns has ever produced — a session with one record,
/// two records on the same second, a sport code nobody has heard of, a developer field
/// belonging to another app carrying a NaN. `SyncCrashHuntTests` needs to *make* those, so
/// this writes the record layer straight (header, definition messages, data messages, CRC),
/// the same self-describing layer `FitStreamWalker` reads.
///
/// Deliberately not in the shipping target: nothing in CleanJibe writes a FIT.
struct FitFactory {

    /// FIT epoch: 1989-12-31 00:00:00 UTC.
    static let epoch = Date(timeIntervalSince1970: 631_065_600)

    enum BaseType: UInt8 {
        case enumerated = 0x00
        case uint8 = 0x02
        case sint32 = 0x85
        case uint16 = 0x84
        case uint32 = 0x86
        case string = 0x07
        case float32 = 0x88
        case float64 = 0x89
        case uint8z = 0x0A

        var size: Int {
            switch self {
            case .enumerated, .uint8, .uint8z, .string: 1
            case .uint16: 2
            case .sint32, .uint32, .float32: 4
            case .float64: 8
            }
        }
    }

    struct Field {
        var num: UInt8
        var type: BaseType
        /// Raw little-endian bytes, already the right width (`type.size`, or any width for
        /// a string).
        var bytes: [UInt8]

        static func u8(_ num: UInt8, _ v: UInt8) -> Field {
            Field(num: num, type: .uint8, bytes: [v])
        }
        static func enumField(_ num: UInt8, _ v: UInt8) -> Field {
            Field(num: num, type: .enumerated, bytes: [v])
        }
        static func u16(_ num: UInt8, _ v: UInt16) -> Field {
            Field(num: num, type: .uint16, bytes: [UInt8(v & 0xFF), UInt8(v >> 8)])
        }
        static func u32(_ num: UInt8, _ v: UInt32) -> Field {
            Field(num: num, type: .uint32, bytes: le32(v))
        }
        static func s32(_ num: UInt8, _ v: Int32) -> Field {
            Field(num: num, type: .sint32, bytes: le32(UInt32(bitPattern: v)))
        }
        static func f32(_ num: UInt8, bitPattern: UInt32) -> Field {
            Field(num: num, type: .float32, bytes: le32(bitPattern))
        }
        static func f64(_ num: UInt8, bitPattern: UInt64) -> Field {
            var out: [UInt8] = []
            for i in 0..<8 { out.append(UInt8((bitPattern >> (8 * UInt64(i))) & 0xFF)) }
            return Field(num: num, type: .float64, bytes: out)
        }
        static func text(_ num: UInt8, _ s: String, width: Int) -> Field {
            var bytes = Array(s.utf8.prefix(width - 1))
            bytes.append(contentsOf: [UInt8](repeating: 0, count: width - bytes.count))
            return Field(num: num, type: .string, bytes: bytes)
        }

        static func le32(_ v: UInt32) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
             UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }
    }

    /// One message: a global number plus its fields. Every message of the same global
    /// number in one file must carry the same field list — the builder emits one definition
    /// per distinct layout and reuses it.
    struct Message {
        var globalNum: UInt16
        var fields: [Field]
        /// Developer fields, as (developerDataIndex, fieldNum, bytes). The field's
        /// `field_description` must already have been added to the file.
        var devFields: [(dev: UInt8, num: UInt8, bytes: [UInt8])] = []
    }

    private var messages: [Message] = []

    mutating func add(_ message: Message) { messages.append(message) }

    /// FIT seconds for a wall-clock instant.
    static func stamp(_ date: Date) -> UInt32 {
        UInt32(max(0, min(Double(UInt32.max) - 1, date.timeIntervalSince(epoch).rounded())))
    }

    // MARK: - Common messages

    static func fileId(created: Date) -> Message {
        Message(globalNum: 0, fields: [
            .enumField(0, 4),                      // type = activity
            .u16(1, 1),                            // manufacturer = garmin
            .u16(2, 3121),                          // product
            .u32(3, 123_456),                      // serial_number
            .u32(4, stamp(created)),               // time_created
        ])
    }

    /// `record` (global 20). Everything but the timestamp is optional — that is the point.
    static func record(at date: Date, lat: Double? = nil, lon: Double? = nil,
                       speedMps: Double? = nil, distanceM: Double? = nil,
                       altitudeM: Double? = nil, heartRate: UInt8? = nil) -> Message {
        var fields: [Field] = [.u32(253, stamp(date))]
        if let lat, let lon {
            fields.append(.s32(0, semicircles(lat)))
            fields.append(.s32(1, semicircles(lon)))
        }
        if let speedMps {
            // enhanced_speed, uint32, scale 1000 (mm/s)
            fields.append(.u32(73, UInt32(max(0, min(4_000_000_000, (speedMps * 1000).rounded())))))
        }
        if let distanceM {
            fields.append(.u32(5, UInt32(max(0, min(4_000_000_000, (distanceM * 100).rounded())))))
        }
        if let altitudeM {
            // altitude, uint16, scale 5 offset 500
            fields.append(.u16(2, UInt16(max(0, min(65534, ((altitudeM + 500) * 5).rounded())))))
        }
        if let heartRate { fields.append(.u8(3, heartRate)) }
        return Message(globalNum: 20, fields: fields)
    }

    static func semicircles(_ degrees: Double) -> Int32 {
        let raw = (degrees / 180.0 * 2147483648.0).rounded()
        return Int32(max(Double(Int32.min), min(Double(Int32.max), raw)))
    }

    /// `session` (global 18). `sport` is the byte that decides whether the importer has ever
    /// heard of this activity.
    static func session(start: Date, end: Date, sport: UInt8, distanceM: Double = 1000) -> Message {
        Message(globalNum: 18, fields: [
            .u32(253, stamp(end)),
            .u32(2, stamp(start)),                                     // start_time
            .u32(7, UInt32(max(0, (end.timeIntervalSince(start) * 1000).rounded()))),  // elapsed
            .u32(8, UInt32(max(0, (end.timeIntervalSince(start) * 1000).rounded()))),  // timer
            .u32(9, UInt32(max(0, (distanceM * 100).rounded()))),      // total_distance
            .enumField(5, sport),
        ])
    }

    /// `lap` (global 19).
    static func lap(start: Date, end: Date, distanceM: Double = 0) -> Message {
        Message(globalNum: 19, fields: [
            .u32(253, stamp(end)),
            .u32(2, stamp(start)),
            .u32(8, UInt32(max(0, (end.timeIntervalSince(start) * 1000).rounded()))),
            .u32(9, UInt32(max(0, (distanceM * 100).rounded()))),
        ])
    }

    /// `activity` (global 34) — the message `FitSessionParser.utcOffsetS` reads.
    static func activity(timestamp: Date, localOffsetS: Int) -> Message {
        Message(globalNum: 34, fields: [
            .u32(253, stamp(timestamp)),
            .u32(5, stamp(timestamp.addingTimeInterval(Double(localOffsetS)))),
        ])
    }

    /// `developer_data_id` (global 207) + `field_description` (global 206) — what another
    /// app's developer field looks like on the wire.
    static func developerDataId(index: UInt8) -> Message {
        Message(globalNum: 207, fields: [
            .u8(3, index),                                   // developer_data_index
            .u32(4, 42),                                     // application_version
        ])
    }

    static func fieldDescription(dev: UInt8, num: UInt8, name: String,
                                 baseType: BaseType) -> Message {
        Message(globalNum: 206, fields: [
            .u8(0, dev),                                     // developer_data_index
            .u8(1, num),                                     // field_definition_number
            .u8(2, baseType.rawValue),                       // fit_base_type_id
            .text(3, name, width: 16),                       // field_name
        ])
    }

    // MARK: - Encoding

    func build() -> Data {
        var body: [UInt8] = []
        // local message type → the layout currently assigned to it.
        var assigned: [String: Int] = [:]
        var nextLocal = 0

        for message in messages {
            let key = layoutKey(message)
            var local = assigned[key]
            if local == nil {
                local = nextLocal % 16
                nextLocal += 1
                assigned[key] = local
                body.append(contentsOf: definitionBytes(message, local: local!))
            }
            // The developer-data bit lives on the *definition* message only; a data
            // message header is just its local type.
            body.append(UInt8(local! & 0x0F))
            for field in message.fields { body.append(contentsOf: field.bytes) }
            for dev in message.devFields { body.append(contentsOf: dev.bytes) }
        }

        var out: [UInt8] = [14, 0x20, 0x34, 0x08]
        out.append(contentsOf: Field.le32(UInt32(body.count)))
        out.append(contentsOf: Array(".FIT".utf8))
        let headerCRC = FitStreamWalker.crc16(out[0..<12])
        out.append(UInt8(headerCRC & 0xFF))
        out.append(UInt8(headerCRC >> 8))
        out.append(contentsOf: body)
        let fileCRC = FitStreamWalker.crc16(out[0..<out.count])
        out.append(UInt8(fileCRC & 0xFF))
        out.append(UInt8(fileCRC >> 8))
        return Data(out)
    }

    private func layoutKey(_ message: Message) -> String {
        let native = message.fields.map { "\($0.num):\($0.type.rawValue):\($0.bytes.count)" }
        let dev = message.devFields.map { "d\($0.dev):\($0.num):\($0.bytes.count)" }
        return "\(message.globalNum)|" + native.joined(separator: ",")
            + "|" + dev.joined(separator: ",")
    }

    private func definitionBytes(_ message: Message, local: Int) -> [UInt8] {
        var out: [UInt8] = [UInt8(0x40 | (local & 0x0F) | (message.devFields.isEmpty ? 0 : 0x20))]
        out.append(0)                                        // reserved
        out.append(0)                                        // architecture: little-endian
        out.append(UInt8(message.globalNum & 0xFF))
        out.append(UInt8(message.globalNum >> 8))
        out.append(UInt8(message.fields.count))
        for field in message.fields {
            out.append(field.num)
            out.append(UInt8(field.bytes.count))
            out.append(field.type.rawValue)
        }
        if !message.devFields.isEmpty {
            out.append(UInt8(message.devFields.count))
            for dev in message.devFields {
                out.append(dev.num)
                out.append(UInt8(dev.bytes.count))
                out.append(dev.dev)
            }
        }
        return out
    }

    /// Build a file out of a message list in one call.
    static func file(_ messages: [Message]) -> Data {
        var factory = FitFactory()
        for message in messages { factory.add(message) }
        return factory.build()
    }
}
