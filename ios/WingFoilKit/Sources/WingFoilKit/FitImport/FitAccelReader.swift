import Foundation

/// Decodes the CIQ SensorLogging accelerometer stream straight from the FIT byte stream.
///
/// ## Why this exists
/// `FitStreamSanitizer` **strips** every `accelerometer_data` message before the vendored C
/// decoder sees it: a 356-byte definition overflows that decoder's fixed 254-byte scratch
/// buffer and corrupts the record stream (see FitStreamSanitizer for the full autopsy). The
/// stream still has to reach the pump/takeoff analysis, so it is read here — from the
/// *original*, unsanitized bytes, with `FitStreamWalker`, the same technique
/// `FitDeveloperFieldReader` uses. The vendored C is never touched.
///
/// ## Layout (FIT profile, global message 165)
/// One message per ~25 samples: `timestamp` (253, uint32 FIT date_time) + `timestamp_ms`
/// (0, uint16) give the batch base; `sample_time_offset` (1, uint16 array, ms) times each
/// sample within it; `calibrated_accel_x/y/z` (5/6/7, float32 arrays) carry the axes.
///
/// Garmin writes `calibrated_accel_*` in **milli-g** although the FIT profile names the unit
/// "g", so the scale is sniffed from the resting magnitude rather than assumed — a device
/// that really emits g still parses correctly. Mirrors `lab/src/wingfoil_lab/parse.py`.
enum FitAccelReader {

    private static let accelerometerDataMesgNum: UInt16 = 165
    /// FIT epoch: 1989-12-31 00:00:00 UTC, in Unix seconds.
    private static let fitEpochOffset: Double = 631_065_600

    private enum Field {
        static let timestamp: UInt8 = 253
        static let timestampMs: UInt8 = 0
        static let sampleTimeOffset: UInt8 = 1
        static let calibratedAccelX: UInt8 = 5
        static let calibratedAccelY: UInt8 = 6
        static let calibratedAccelZ: UInt8 = 7
    }

    /// Every accelerometer sample as (t on the record time base, |a| in g), time-sorted.
    /// Returns an empty array when the source carries no stream — never throws, per the
    /// fail-soft contract.
    ///
    /// - Parameter recordEpoch: the first record's timestamp; the accel clock is rebased
    ///   onto it so pump analysis and the speed channels share one `t`.
    static func read(_ data: Data, recordEpoch: Date?) -> [AccelSample] {
        guard let recordEpoch else { return [] }
        let bytes = [UInt8](data)
        let epoch0 = recordEpoch.timeIntervalSince1970

        var times: [Double] = []
        var magnitudes: [Double] = []

        let walked = FitStreamWalker.walk(bytes) { event in
            guard case let .data(_, def, _, payload) = event,
                  def.globalNum == accelerometerDataMesgNum else { return }

            func field(_ num: UInt8) -> FitMessageDefinition.Field? {
                def.fields.first { $0.num == num }
            }
            guard let tsField = field(Field.timestamp),
                  let offField = field(Field.sampleTimeOffset),
                  let xField = field(Field.calibratedAccelX),
                  let yField = field(Field.calibratedAccelY),
                  let zField = field(Field.calibratedAccelZ),
                  let seconds = uint(bytes, payload, tsField, width: 4, bigEndian: def.bigEndian),
                  seconds != 0xFFFF_FFFF
            else { return }

            let ms = field(Field.timestampMs)
                .flatMap { uint(bytes, payload, $0, width: 2, bigEndian: def.bigEndian) }
                .flatMap { $0 == 0xFFFF ? nil : $0 } ?? 0
            // Absolute epoch first, rebased only once per *sample* — the same order the
            // lab evaluates it in. Folding `- epoch0` in early would keep more precision
            // but move samples across 40 ms resample-bin boundaries relative to the
            // reference, and the pump grid is the one place that is observable.
            let base = fitEpochOffset + Double(seconds) + Double(ms) / 1000

            let offsets = uintArray(bytes, payload, offField, width: 2, bigEndian: def.bigEndian)
            let xs = floatArray(bytes, payload, xField, bigEndian: def.bigEndian)
            let ys = floatArray(bytes, payload, yField, bigEndian: def.bigEndian)
            let zs = floatArray(bytes, payload, zField, bigEndian: def.bigEndian)
            let n = min(offsets.count, min(xs.count, min(ys.count, zs.count)))
            guard n > 0 else { return }

            for i in 0..<n {
                times.append(base + Double(offsets[i]) / 1000 - epoch0)
                magnitudes.append((xs[i] * xs[i] + ys[i] * ys[i] + zs[i] * zs[i]).squareRoot())
            }
        }
        guard walked != nil, !times.isEmpty else { return [] }

        // Scale sniff: a resting wrist magnitude near 1000 rather than 1 means milli-g.
        let scale = Evidence.median(magnitudes) > 20.0 ? 1e-3 : 1.0

        // Stable sort by time — batches are written in order, but the FIT spec does not
        // promise it and the lab sorts too (np.argsort kind="stable").
        let order = times.indices.sorted { times[$0] != times[$1] ? times[$0] < times[$1] : $0 < $1 }
        return order.map { AccelSample(t: times[$0], magnitudeG: magnitudes[$0] * scale) }
    }

    // MARK: - Field decoding

    private static func slice(_ payload: Range<Int>,
                              _ field: FitMessageDefinition.Field) -> Range<Int>? {
        let start = payload.lowerBound + field.offset
        let end = min(start + field.size, payload.upperBound)
        return start < end ? start..<end : nil
    }

    private static func uint(_ bytes: [UInt8], _ payload: Range<Int>,
                             _ field: FitMessageDefinition.Field, width: Int,
                             bigEndian: Bool) -> UInt32? {
        guard let s = slice(payload, field), s.count >= width else { return nil }
        return readUInt(bytes, at: s.lowerBound, width: width, bigEndian: bigEndian)
    }

    private static func uintArray(_ bytes: [UInt8], _ payload: Range<Int>,
                                  _ field: FitMessageDefinition.Field, width: Int,
                                  bigEndian: Bool) -> [UInt32] {
        guard let s = slice(payload, field) else { return [] }
        let count = s.count / width
        return (0..<count).map {
            readUInt(bytes, at: s.lowerBound + $0 * width, width: width, bigEndian: bigEndian)
        }
    }

    private static func floatArray(_ bytes: [UInt8], _ payload: Range<Int>,
                                   _ field: FitMessageDefinition.Field,
                                   bigEndian: Bool) -> [Double] {
        guard let s = slice(payload, field) else { return [] }
        let count = s.count / 4
        var out: [Double] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let raw = readUInt(bytes, at: s.lowerBound + i * 4, width: 4, bigEndian: bigEndian)
            // The float32 "invalid" sentinel is all-ones; a NaN would poison the magnitude.
            guard raw != 0xFFFF_FFFF else { return out }
            let value = Float(bitPattern: raw)
            guard value.isFinite else { return out }
            out.append(Double(value))
        }
        return out
    }

    private static func readUInt(_ bytes: [UInt8], at start: Int, width: Int,
                                 bigEndian: Bool) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<width {
            let byte = UInt32(bytes[start + i])
            v |= byte << (8 * UInt32(bigEndian ? width - 1 - i : i))
        }
        return v
    }
}
