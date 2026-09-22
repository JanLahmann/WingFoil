import Foundation

// STREAM 1 OF THE DIRECT TRANSFER — `wrist.v1`, the 25 Hz wrist magnitudes
// (docs/transfer-format.md §2b, ADR-031). `lab/tools/cjr_ref.py` is the reference and this
// mirrors it statement for statement; the watch's `DirectSend` is the third implementation
// and the worked example of §2b is pinned in all three.
//
// **Only the windows the watch flagged are on the wire.** Two hours of 25 Hz magnitudes is
// about 180 KB and fits the memory of no watch in the manifest, so the watch keeps a bounded
// ring of the stretches its own detector has anything to find in — off the foil, inside a
// turn window, within ten seconds of a stroke — and sends those. Everything between two
// windows is a **sensor gap**, which is a state the pump grid has always modelled: empty bins
// held at the mean, `valid` false, no stroke picked there. So a windowed stream needs no new
// concept downstream, no new capability and no new source letter (pattern L).
//
// Everything is little-endian, stated rather than inherited, as the rest of the format is.

/// The constants of docs/transfer-format.md §2b, in one place.
public enum DirectWrist {

    /// Stream 1. The page header already carried the stream number, so this added no message.
    public static let wristStream: UInt8 = 1

    /// The grid the magnitudes sit on. Exactly `PumpConfig.resampleHz`, and not by
    /// coincidence: the watch feeds this stream from the same `_pushGrid` its own band-pass
    /// reads, so what arrives is what the lab's chain expects with no resampling in between.
    /// A watch whose sensor cannot reach the grid leaves its detector unavailable and sends
    /// no wrist stream at all.
    public static let hz = 25
    /// 1000 / hz, exact. Samples inside a window carry no time of their own.
    public static let stepMs = 40

    public static let windowTag: UInt8 = 0xFF
    public static let escapeTag: UInt8 = 0xFE
    public static let windowHeaderBytes = 9
    /// A delta byte `v` (0x00…0xFD) means `v - deltaBias` centi-g.
    public static let deltaBias = 126
    public static let deltaMin = -126
    public static let deltaMax = 127
    /// Magnitudes are centi-g, gravity included: a resting wrist reads about 100.
    public static let magMax = 65535
    /// 10 s. A longer flagged stretch becomes consecutive windows, each with its own header
    /// and its own absolute first sample.
    public static let windowMaxSamples = 250

    /// Centi-g to g, the unit `AccelSample.magnitudeG` and `PumpAnalyzer` both speak.
    public static func gravities(_ centiG: Int) -> Double { Double(centiG) / 100 }
}

/// One flagged stretch of wrist motion, as the wire states it.
public struct DirectWristWindow: Sendable, Equatable {
    /// Epoch milliseconds of `magnitudes[0]`. Sample `i` is `DirectWrist.stepMs` later than
    /// sample `i − 1`, by construction — that is what a window *is*.
    public var startEpochMs: Int
    /// Centi-g, one per 25 Hz sample.
    public var magnitudes: [Int]

    public init(startEpochMs: Int, magnitudes: [Int]) {
        self.startEpochMs = startEpochMs
        self.magnitudes = magnitudes
    }

    /// Epoch seconds of the sample after the last one — the open end of the covered span.
    public var endEpochS: Double {
        (Double(startEpochMs) + Double(magnitudes.count * DirectWrist.stepMs)) / 1000
    }

    public var startEpochS: Double { Double(startEpochMs) / 1000 }
}

// MARK: - Decoder

public enum DirectWristDecoder {

    /// The concatenation of stream 1's pages, in order.
    ///
    /// **Fail-soft in exactly one direction**, like every other parser here: a structurally
    /// broken stream throws, a *trailing* window short of its own width is dropped, because a
    /// transfer cut off mid-page still holds real seconds of real wrist motion.
    public static func decode(_ data: Data) throws -> (DirectStreamHeader, [DirectWristWindow]) {
        let head = try DirectStreamDecoder.header(data)
        guard head.stream == DirectWrist.wristStream else {
            throw DirectStreamError.truncated("stream \(head.stream) is not the wrist stream")
        }
        let b = [UInt8](data)
        var i = try DirectStreamDecoder.headerLength(data)
        var out: [DirectWristWindow] = []

        while i < b.count {
            guard b[i] == DirectWrist.windowTag else {
                throw DirectStreamError.truncated("a window header at byte \(i)")
            }
            guard i + DirectWrist.windowHeaderBytes <= b.count else { break }
            let seconds = Int(readUInt32(b, i + 1))
            let millis = Int(readUInt16(b, i + 5))
            let count = Int(readUInt16(b, i + 7))
            guard millis < 1000, count > 0, count <= DirectWrist.windowMaxSamples else {
                throw DirectStreamError.truncated("a window of \(count) samples at byte \(i)")
            }
            var j = i + DirectWrist.windowHeaderBytes
            var magnitudes: [Int] = []
            magnitudes.reserveCapacity(count)
            var previous: Int?
            var short = false
            for _ in 0..<count {
                guard j < b.count else { short = true; break }
                let code = b[j]
                let magnitude: Int
                if code == DirectWrist.escapeTag {
                    guard j + 3 <= b.count else { short = true; break }
                    magnitude = Int(readUInt16(b, j + 1))
                    j += 3
                } else if code == DirectWrist.windowTag {
                    // A window that names more samples than it carries is structural: the
                    // count came off the wire and the bytes did not agree with it.
                    throw DirectStreamError.truncated("a window that ended at byte \(j)")
                } else {
                    guard let last = previous else {
                        throw DirectStreamError.deltaBeforeKeyframe
                    }
                    magnitude = last + Int(code) - DirectWrist.deltaBias
                    j += 1
                }
                magnitudes.append(magnitude)
                previous = magnitude
            }
            if short {
                // The last window of a transfer that stopped. What it holds is real; keep it
                // if there is enough of it to mean anything, and stop.
                if magnitudes.count >= DirectWrist.hz {
                    out.append(DirectWristWindow(startEpochMs: seconds * 1000 + millis,
                                                 magnitudes: magnitudes))
                }
                break
            }
            out.append(DirectWristWindow(startEpochMs: seconds * 1000 + millis,
                                         magnitudes: magnitudes))
            i = j
        }
        return (head, out)
    }

    /// The windows as `AccelSample`s on a record time base — the shape `RawTrack.accel`
    /// holds and `PumpAnalyzer` reads, and the same shape `FitAccelReader` produces from a
    /// FIT's `accelerometer_data`. `base` is the session's own epoch zero
    /// (`DirectStreamParser.build`'s `base`), so the two streams share one clock.
    public static func samples(_ windows: [DirectWristWindow], base: Int) -> [AccelSample] {
        var out: [AccelSample] = []
        out.reserveCapacity(windows.reduce(0) { $0 + $1.magnitudes.count })
        let step = Double(DirectWrist.stepMs) / 1000
        for window in windows {
            var t = window.startEpochS - Double(base)
            for magnitude in window.magnitudes {
                out.append(AccelSample(t: t, magnitudeG: DirectWrist.gravities(magnitude)))
                t += step
            }
        }
        // The watch writes its windows in time order; a stream assembled out of order would
        // be a stream with a missing page, and the sort costs nothing against the gain of
        // never handing the grid an unsorted array.
        return out.sorted { $0.t < $1.t }
    }

    private static func readUInt16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }

    private static func readUInt32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}

// MARK: - Encoder

/// Windows in, closed pages out.
///
/// **Why the phone has an encoder at all** is `DirectStreamEncoder`'s reason: the format can
/// then be round-tripped in a test, a fixture can be built from windows rather than from a
/// hex string, and the arithmetic the decoder undoes is written down twice in one language.
///
/// **Page 0 is the twenty-byte stream header alone.** Stream 1's pages are dropped under
/// budget pressure on the watch and their indices are only assigned at save, so the header
/// cannot ride on a page that might not survive. Every page after it opens with a window
/// header and decodes on its own — the rule §1 states for stream 0.
public struct DirectWristEncoder {

    private var pages: [Data]
    private var buffer = Data()

    public init(header: DirectStreamHeader) {
        var head = header
        head.stream = DirectWrist.wristStream
        pages = [DirectStreamEncoder.pack(head)]
    }

    public mutating func push(_ window: DirectWristWindow) {
        let encoded = Self.encode(window)
        guard !encoded.isEmpty, encoded.count <= DirectStream.pageBytes else { return }
        if buffer.count + encoded.count > DirectStream.pageBytes {
            pages.append(buffer)
            buffer = Data()
        }
        buffer.append(encoded)
    }

    public mutating func close() -> [Data] {
        if !buffer.isEmpty {
            pages.append(buffer)
            buffer = Data()
        }
        return pages
    }

    public mutating func archive() -> Data {
        var out = Data()
        for page in close() { out.append(page) }
        return out
    }

    /// One window: its header, then one code per sample — an 8-bit delta where it holds, a
    /// two-byte escape where it does not. The first sample always escapes.
    public static func encode(_ window: DirectWristWindow) -> Data {
        let count = window.magnitudes.count
        guard count > 0, count <= DirectWrist.windowMaxSamples else { return Data() }
        var out = Data(capacity: DirectWrist.windowHeaderBytes + count + 3)
        out.append(DirectWrist.windowTag)
        let seconds = window.startEpochMs / 1000
        let millis = window.startEpochMs - seconds * 1000
        out.appendLE32(UInt32(truncatingIfNeeded: seconds))
        out.appendLE16(UInt16(truncatingIfNeeded: millis))
        out.appendLE16(UInt16(truncatingIfNeeded: count))
        var previous: Int?
        for raw in window.magnitudes {
            let magnitude = min(max(raw, 0), DirectWrist.magMax)
            if let last = previous, case let delta = magnitude - last,
               delta >= DirectWrist.deltaMin, delta <= DirectWrist.deltaMax {
                out.append(UInt8(delta + DirectWrist.deltaBias))
            } else {
                out.append(DirectWrist.escapeTag)
                out.appendLE16(UInt16(magnitude))
            }
            previous = magnitude
        }
        return out
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLE32(_ value: UInt32) {
        for i in 0..<4 { append(UInt8(truncatingIfNeeded: value >> (8 * i))) }
    }
}
