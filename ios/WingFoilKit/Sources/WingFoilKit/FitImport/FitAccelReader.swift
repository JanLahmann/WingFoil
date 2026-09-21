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
///
/// ## Not every device gives that stream a clock
/// Engine 0.23.0, ADR-030. A tester's fenix 5 Plus writes one message after each 1 Hz
/// record and stamps every one of them with a handful of constant `timestamp`s *days* away
/// from the session, with `sample_time_offset` flat at zero. Read literally that is a
/// stream fifty days long starting before the ride. `clockIsUsable` detects the shape and
/// the batches are then timed from **file order** instead — each begins at the last
/// `record` seen before it, its samples spread evenly over that second.
enum FitAccelReader {

    private static let accelerometerDataMesgNum: UInt16 = 165
    private static let recordMesgNum: UInt16 = 20
    /// FIT epoch: 1989-12-31 00:00:00 UTC, in Unix seconds.
    private static let fitEpochOffset: Double = 631_065_600
    /// How long one batch is taken to last when the stream carries no clock of its own.
    /// The device writes one batch per 1 Hz record, so a second is what a batch *is*.
    static let batchSpanS: Double = 1.0

    private enum Field {
        static let timestamp: UInt8 = 253
        static let timestampMs: UInt8 = 0
        static let sampleTimeOffset: UInt8 = 1
        static let calibratedAccelX: UInt8 = 5
        static let calibratedAccelY: UInt8 = 6
        static let calibratedAccelZ: UInt8 = 7
    }

    /// One `accelerometer_data` message, with its clock kept *unapplied* so the reader can
    /// decide whether to believe it.
    struct Batch {
        /// The batch's own epoch second (`timestamp` + `timestamp_ms`).
        var base: Double
        /// Per-sample offsets in ms, as written.
        var offsetsMs: [Double]
        var magnitudes: [Double]
        /// How many records had been read when this batch arrived — the file-order anchor.
        var afterRecords: Int
    }

    /// Every accelerometer sample as (t on the record time base, |a| in g), time-sorted,
    /// plus whether its clock had to be reconstructed. Returns an empty array when the
    /// source carries no stream — never throws, per the fail-soft contract.
    ///
    /// - Parameter recordEpoch: the first record's timestamp; the accel clock is rebased
    ///   onto it so pump analysis and the speed channels share one `t`.
    static func read(_ data: Data,
                     recordEpoch: Date?) -> (samples: [AccelSample], reconstructed: Bool) {
        guard let recordEpoch else { return ([], false) }
        let bytes = [UInt8](data)
        let epoch0 = recordEpoch.timeIntervalSince1970

        var batches: [Batch] = []
        var recordEpochs: [Double] = []

        let walked = FitStreamWalker.walk(bytes) { event in
            guard case let .data(_, def, _, payload) = event else { return }

            func field(_ num: UInt8) -> FitMessageDefinition.Field? {
                def.fields.first { $0.num == num }
            }

            if def.globalNum == recordMesgNum {
                guard let tsField = field(Field.timestamp),
                      let seconds = uint(bytes, payload, tsField, width: 4,
                                         bigEndian: def.bigEndian),
                      seconds != 0xFFFF_FFFF
                else { return }
                recordEpochs.append(fitEpochOffset + Double(seconds))
                return
            }

            guard def.globalNum == accelerometerDataMesgNum,
                  let tsField = field(Field.timestamp),
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

            var mags = [Double](); mags.reserveCapacity(n)
            for i in 0..<n {
                mags.append((xs[i] * xs[i] + ys[i] * ys[i] + zs[i] * zs[i]).squareRoot())
            }
            batches.append(Batch(base: base,
                                 offsetsMs: (0..<n).map { Double(offsets[$0]) },
                                 magnitudes: mags,
                                 afterRecords: recordEpochs.count))
        }
        guard walked != nil, !batches.isEmpty else { return ([], false) }

        let reconstructed = !clockIsUsable(batches, recordEpochs: recordEpochs)
        let times = sampleTimes(batches, recordEpochs: recordEpochs,
                                epoch0: epoch0, reconstructed: reconstructed)
        var magnitudes: [Double] = []
        magnitudes.reserveCapacity(times.count)
        for b in batches { magnitudes.append(contentsOf: b.magnitudes) }

        // A sample whose time or magnitude did not survive the file is dropped rather than
        // carried: a non-finite value reaches the pump resampler as a grid length.
        var keptT: [Double] = [], keptM: [Double] = []
        keptT.reserveCapacity(times.count); keptM.reserveCapacity(times.count)
        for i in times.indices where times[i].isFinite && magnitudes[i].isFinite {
            keptT.append(times[i]); keptM.append(magnitudes[i])
        }
        guard !keptT.isEmpty else { return ([], reconstructed) }

        // Scale sniff: a resting wrist magnitude near 1000 rather than 1 means milli-g.
        let scale = Evidence.median(keptM) > 20.0 ? 1e-3 : 1.0

        // Stable sort by time — batches are written in order, but the FIT spec does not
        // promise it and the lab sorts too (np.argsort kind="stable").
        let order = keptT.indices.sorted { keptT[$0] != keptT[$1] ? keptT[$0] < keptT[$1] : $0 < $1 }
        return (order.map { AccelSample(t: keptT[$0], magnitudeG: keptM[$0] * scale) },
                reconstructed)
    }

    /// Did the device *time* this accelerometer stream, or only stamp it?
    ///
    /// Two independent tests, either of which condemns the clock (engine 0.23.0, ADR-030):
    ///
    /// * **The bases are not on this session's clock.** Fewer than half the batch
    ///   timestamps fall inside the records' own span. A watch that timed the stream puts
    ///   every batch inside the session, and our own recordings do.
    /// * **There is no clock inside a batch either.** No batch of two or more samples has
    ///   any spread in its `sample_time_offset`. Twenty-five samples all at offset 0 are
    ///   twenty-five samples with one time, which is not a time.
    ///
    /// With no records to compare against the file is believed: there is nothing better.
    /// Mirrors `lab/src/wingfoil_lab/parse.py` `_accel_clock_is_usable`.
    static func clockIsUsable(_ batches: [Batch], recordEpochs: [Double]) -> Bool {
        guard !batches.isEmpty else { return true }
        if let lo = recordEpochs.first, let hi = recordEpochs.last {
            let inside = batches.count { $0.base >= lo - 1 && $0.base <= hi + 1 }
            if inside * 2 < batches.count { return false }
        }
        for b in batches where b.offsetsMs.count >= 2 {
            if let lo = b.offsetsMs.min(), let hi = b.offsetsMs.max(), hi > lo { return true }
        }
        return false
    }

    /// Per-sample times on the record base, believing the file or replacing its clock.
    private static func sampleTimes(_ batches: [Batch], recordEpochs: [Double],
                                    epoch0: Double, reconstructed: Bool) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(batches.reduce(0) { $0 + $1.magnitudes.count })
        guard reconstructed else {
            for b in batches {
                for off in b.offsetsMs { out.append(b.base + off / 1000 - epoch0) }
            }
            return out
        }
        // File order. Each batch starts at the record that precedes it and lasts one
        // second, monotonically — so several batches written after the same record queue
        // up behind it rather than landing on one instant.
        var prevEnd = -Double.infinity
        for b in batches {
            let anchor = (b.afterRecords > 0 && b.afterRecords <= recordEpochs.count)
                ? recordEpochs[b.afterRecords - 1] : epoch0
            let start = max(anchor, prevEnd)
            let n = b.magnitudes.count
            for i in 0..<n {
                out.append(start + Double(i) / Double(n) * batchSpanS - epoch0)
            }
            prevEnd = start + batchSpanS
        }
        return out
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
