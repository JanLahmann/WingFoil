import Foundation
@testable import WingFoilKit

/// One recording shape that no device in the corpus produces and a stranger's intervals.icu
/// account can hold anyway. `bytes()` builds it from scratch (`FitFactory`), so the family
/// can grow without a single committed binary and without teaching `allFixtureFITs()` about
/// files that are *meant* to be broken.
struct DegenerateFit: Sendable, CustomStringConvertible {
    let name: String
    let build: @Sendable () -> Data

    var description: String { name }
    func bytes() -> Data { build() }

    static let all: [DegenerateFit] = DegenerateShapes.all
}

/// The shapes themselves, one function each — deliberately not one big array literal, which
/// the type checker cannot see through in reasonable time.
enum DegenerateShapes {

    static let t0 = Date(timeIntervalSince1970: 1_754_460_000)     // 2025-08-06 07:00 UTC
    static let lat = 45.87
    static let lon = 10.87

    /// A plain, well-behaved run of `count` samples — the base every shape deforms.
    static func straightLine(count: Int, speedMps: Double = 7,
                             step: Double = 1) -> [FitFactory.Message] {
        var out: [FitFactory.Message] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let at: Date = t0.addingTimeInterval(Double(i) * step)
            out.append(FitFactory.record(at: at,
                                         lat: lat + Double(i) * 1e-5,
                                         lon: lon + Double(i) * 1e-5,
                                         speedMps: speedMps,
                                         distanceM: Double(i) * speedMps,
                                         altitudeM: 65, heartRate: 140))
        }
        return out
    }

    static func wrap(_ body: [FitFactory.Message], durationS: Double,
                     sport: UInt8 = 43) -> Data {
        var messages: [FitFactory.Message] = [FitFactory.fileId(created: t0)]
        messages.append(contentsOf: body)
        messages.append(FitFactory.session(start: t0,
                                           end: t0.addingTimeInterval(durationS),
                                           sport: sport))
        return FitFactory.file(messages)
    }

    // MARK: - The shapes

    static func noRecords() -> Data { wrap([], durationS: 600) }

    static func oneRecord() -> Data { wrap(straightLine(count: 1), durationS: 0) }

    static func twoRecordsSameTimestamp() -> Data {
        let a = FitFactory.record(at: t0, lat: lat, lon: lon, speedMps: 5)
        let b = FitFactory.record(at: t0, lat: lat, lon: lon, speedMps: 5)
        return wrap([a, b], durationS: 0)
    }

    static func noPosition() -> Data {
        var body: [FitFactory.Message] = []
        for i in 0..<300 {
            body.append(FitFactory.record(at: t0.addingTimeInterval(Double(i)),
                                          speedMps: 6, heartRate: 150))
        }
        return wrap(body, durationS: 300)
    }

    static func noSpeed() -> Data {
        var body: [FitFactory.Message] = []
        for i in 0..<300 {
            body.append(FitFactory.record(at: t0.addingTimeInterval(Double(i)),
                                          lat: lat + Double(i) * 1e-5,
                                          lon: lon + Double(i) * 1e-5))
        }
        return wrap(body, durationS: 300)
    }

    static func speedZeroThroughout() -> Data {
        var body: [FitFactory.Message] = []
        for i in 0..<600 {
            body.append(FitFactory.record(at: t0.addingTimeInterval(Double(i)),
                                          lat: lat, lon: lon, speedMps: 0,
                                          distanceM: 0, altitudeM: 65))
        }
        return wrap(body, durationS: 600)
    }

    static func enormousSpeedSpike() -> Data {
        var body = straightLine(count: 400)
        body[201] = FitFactory.record(at: t0.addingTimeInterval(201),
                                      lat: lat + 4, lon: lon + 4,
                                      speedMps: 3_999_999, distanceM: 1e7,
                                      altitudeM: 65, heartRate: 190)
        return wrap(body, durationS: 400)
    }

    static func timestampsGoingBackwards() -> Data {
        var body: [FitFactory.Message] = []
        for i in 0..<300 {
            body.append(FitFactory.record(at: t0.addingTimeInterval(Double(300 - i)),
                                          lat: lat + Double(i) * 1e-5,
                                          lon: lon + Double(i) * 1e-5, speedMps: 6))
        }
        return wrap(body, durationS: 300)
    }

    static func twentyFourHourGap() -> Data {
        var body = straightLine(count: 120)
        for i in 0..<120 {
            body.append(FitFactory.record(at: t0.addingTimeInterval(86_400 + Double(i)),
                                          lat: lat, lon: lon, speedMps: 6))
        }
        return wrap(body, durationS: 86_640)
    }

    /// 30 h at one sample every 20 s — Smart Recording over a multi-day crossing.
    static func thirtyHourSession() -> Data {
        wrap(straightLine(count: 5_400, step: 20), durationS: 108_000)
    }

    static func entirelyOnLand() -> Data {
        var body: [FitFactory.Message] = []
        for i in 0..<900 {
            body.append(FitFactory.record(at: t0.addingTimeInterval(Double(i)),
                                          lat: 48.13 + Double(i) * 2e-6,
                                          lon: 11.58 + Double(i) * 2e-6,
                                          speedMps: 1.4, distanceM: Double(i) * 1.4,
                                          altitudeM: 519, heartRate: 120))
        }
        return wrap(body, durationS: 900, sport: 1)
    }

    static func running() -> Data {
        wrap(straightLine(count: 1_800, speedMps: 3), durationS: 1_800, sport: 1)
    }

    static func cycling() -> Data {
        wrap(straightLine(count: 1_800, speedMps: 9), durationS: 1_800, sport: 2)
    }

    static func unknownSportCode() -> Data {
        wrap(straightLine(count: 600), durationS: 600, sport: 251)
    }

    static func noActivityMessage() -> Data {
        wrap(straightLine(count: 600), durationS: 600)
    }

    static func withActivityMessage() -> Data {
        var messages: [FitFactory.Message] = [FitFactory.fileId(created: t0)]
        messages.append(contentsOf: straightLine(count: 600))
        messages.append(FitFactory.session(start: t0, end: t0.addingTimeInterval(600),
                                           sport: 43))
        messages.append(FitFactory.activity(timestamp: t0.addingTimeInterval(600),
                                            localOffsetS: 7_200))
        return FitFactory.file(messages)
    }

    static func zeroDurationLaps() -> Data {
        var body = straightLine(count: 600)
        for i in 0..<10 {
            let at: Date = t0.addingTimeInterval(Double(i) * 60)
            body.append(FitFactory.lap(start: at, end: at, distanceM: 0))
        }
        return wrap(body, durationS: 600)
    }

    static func heartRateOnly() -> Data {
        var body: [FitFactory.Message] = []
        for i in 0..<1_200 {
            body.append(FitFactory.record(at: t0.addingTimeInterval(Double(i)),
                                          heartRate: UInt8(120 + (i % 60))))
        }
        return wrap(body, durationS: 1_200)
    }

    /// Another app's developer fields, under *our* names, carrying the float bit patterns a
    /// foreign encoder can legally write: a quiet NaN and +inf. `FitDevValue.int` hands those
    /// straight to `Int(_:)` unless something stops it.
    static func foreignDevFieldsNaN() -> Data {
        var messages: [FitFactory.Message] = [
            FitFactory.fileId(created: t0),
            FitFactory.developerDataId(index: 0),
            FitFactory.fieldDescription(dev: 0, num: 0, name: "foil_state", baseType: .float32),
            FitFactory.fieldDescription(dev: 0, num: 1, name: "flight_count", baseType: .float64),
            FitFactory.fieldDescription(dev: 0, num: 2, name: "tick", baseType: .float32),
        ]
        for i in 0..<300 {
            var record = FitFactory.record(at: t0.addingTimeInterval(Double(i)),
                                           lat: lat + Double(i) * 1e-5,
                                           lon: lon + Double(i) * 1e-5, speedMps: 6)
            record.devFields = [
                (dev: 0, num: 0, bytes: FitFactory.Field.le32(0x7FC0_0000)),   // quiet NaN
                (dev: 0, num: 2, bytes: FitFactory.Field.le32(0x7F80_0000)),   // +inf
            ]
            messages.append(record)
        }
        var session = FitFactory.session(start: t0, end: t0.addingTimeInterval(300), sport: 43)
        session.devFields = [(dev: 0, num: 1, bytes: [0, 0, 0, 0, 0, 0, 0xF0, 0x7F])]
        messages.append(session)
        return FitFactory.file(messages)
    }

    /// The same trick on the session summary's packed and counted fields.
    static func foreignDevFieldsHuge() -> Data {
        var messages: [FitFactory.Message] = [
            FitFactory.fileId(created: t0),
            FitFactory.developerDataId(index: 0),
            FitFactory.fieldDescription(dev: 0, num: 10, name: "takeoff_pack",
                                        baseType: .float64),
            FitFactory.fieldDescription(dev: 0, num: 11, name: "total_pump_strokes",
                                        baseType: .float64),
            FitFactory.fieldDescription(dev: 0, num: 12, name: "foil_pct", baseType: .float64),
        ]
        messages.append(contentsOf: straightLine(count: 300))
        var session = FitFactory.session(start: t0, end: t0.addingTimeInterval(300), sport: 43)
        session.devFields = [
            (dev: 0, num: 10, bytes: [0, 0, 0, 0, 0, 0, 0xF0, 0x7F]),          // +inf
            (dev: 0, num: 11, bytes: [0, 0, 0, 0, 0, 0, 0xF0, 0xFF]),          // -inf
            (dev: 0, num: 12, bytes: [0, 0, 0, 0, 0, 0, 0xF8, 0x7F]),          // NaN
        ]
        messages.append(session)
        return FitFactory.file(messages)
    }

    /// A **complete, well-formed** file whose clock is nonsense: ten minutes of riding and
    /// then one record stamped forty years later. Every CRC checks out, so nothing structural
    /// catches it — only the arithmetic notices that this "session" lasted four decades.
    static func brokenClock() -> Data {
        var body = straightLine(count: 600)
        body.append(FitFactory.record(at: t0.addingTimeInterval(40 * 365 * 86_400),
                                      lat: lat, lon: lon, speedMps: 6))
        return wrap(body, durationS: 600)
    }

    /// A file cut off a third of the way through — a download that died mid-stream.
    static func truncatedFile() -> Data {
        let data = wrap(straightLine(count: 600), durationS: 600)
        return data.prefix(data.count / 3)
    }

    static let all: [DegenerateFit] = [
        DegenerateFit(name: "no-records", build: noRecords),
        DegenerateFit(name: "one-record", build: oneRecord),
        DegenerateFit(name: "two-records-same-timestamp", build: twoRecordsSameTimestamp),
        DegenerateFit(name: "no-position", build: noPosition),
        DegenerateFit(name: "no-speed", build: noSpeed),
        DegenerateFit(name: "speed-zero-throughout", build: speedZeroThroughout),
        DegenerateFit(name: "one-enormous-speed-spike", build: enormousSpeedSpike),
        DegenerateFit(name: "timestamps-going-backwards", build: timestampsGoingBackwards),
        DegenerateFit(name: "twenty-four-hour-gap", build: twentyFourHourGap),
        DegenerateFit(name: "thirty-hour-session", build: thirtyHourSession),
        DegenerateFit(name: "entirely-on-land", build: entirelyOnLand),
        DegenerateFit(name: "running-that-slipped-the-filter", build: running),
        DegenerateFit(name: "cycling-that-slipped-the-filter", build: cycling),
        DegenerateFit(name: "unknown-sport-code", build: unknownSportCode),
        DegenerateFit(name: "no-activity-message", build: noActivityMessage),
        DegenerateFit(name: "activity-message-present", build: withActivityMessage),
        DegenerateFit(name: "zero-duration-laps", build: zeroDurationLaps),
        DegenerateFit(name: "heart-rate-only", build: heartRateOnly),
        DegenerateFit(name: "foreign-developer-fields-nan", build: foreignDevFieldsNaN),
        DegenerateFit(name: "foreign-developer-fields-huge", build: foreignDevFieldsHuge),
        DegenerateFit(name: "broken-clock", build: brokenClock),
        DegenerateFit(name: "truncated-file", build: truncatedFile),
    ]
}
