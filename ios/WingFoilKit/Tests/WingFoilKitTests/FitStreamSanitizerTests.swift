import Foundation
import Testing
@testable import WingFoilKit

/// Regression cover for the FitFileParser buffer-overflow guard (see FitStreamSanitizer).
/// Our Connect IQ files log `accelerometer_data` (356-byte definition) and Garmin logs
/// `device_settings` (114 field defs); both blow past fixed limits in the vendored C
/// decoder, silently corrupting the record stream and intermittently segfaulting.
@Suite struct FitStreamSanitizerTests {

    /// Independent re-walk of the FIT record layer: every definition the C decoder will
    /// see must fit `u.mesg` (254 B) and `convert_table[].fields` (91 entries).
    /// Returns nil if the stream is not walkable (which itself is a failure here).
    private func oversizeDefinitions(in data: Data) -> [UInt16]? {
        let b = [UInt8](data)
        guard b.count >= 14 else { return nil }
        let headerSize = Int(b[0])
        let dataSize = Int(b[4]) | Int(b[5]) << 8 | Int(b[6]) << 16 | Int(b[7]) << 24
        let end = headerSize + dataSize
        guard headerSize == 12 || headerSize == 14, end + 2 <= b.count else { return nil }

        var sizes = [Int?](repeating: nil, count: 16)   // total data bytes per local type
        var oversize: [UInt16] = []
        var p = headerSize
        while p < end {
            let hdr = b[p]
            p += 1
            if hdr & 0x80 != 0 {                                    // compressed timestamp
                guard let s = sizes[Int((hdr & 0x60) >> 5)] else { return nil }
                p += s
                continue
            }
            let local = Int(hdr & 0x0F)
            guard hdr & 0x40 != 0 else {                            // data message
                guard let s = sizes[local] else { return nil }
                p += s
                continue
            }
            guard p + 5 <= end else { return nil }                  // definition message
            let big = b[p + 1] == 1
            let globalNum = big ? UInt16(b[p + 2]) << 8 | UInt16(b[p + 3])
                                : UInt16(b[p + 3]) << 8 | UInt16(b[p + 2])
            let fieldCount = Int(b[p + 4])
            p += 5
            guard p + 3 * fieldCount <= end else { return nil }
            var native = 0
            for i in 0..<fieldCount { native += Int(b[p + 3 * i + 1]) }
            p += 3 * fieldCount
            var dev = 0
            if hdr & 0x20 != 0 {
                guard p < end else { return nil }
                let devCount = Int(b[p])
                p += 1
                guard p + 3 * devCount <= end else { return nil }
                for i in 0..<devCount { dev += Int(b[p + 3 * i + 1]) }
                p += 3 * devCount
            }
            sizes[local] = native + dev
            if native > FitStreamSanitizer.maxNativeMessageBytes
                || fieldCount > FitStreamSanitizer.maxNativeFieldDefs {
                oversize.append(globalNum)
            }
        }
        return p == end ? oversize : nil
    }

    @Test func sanitizedFixturesCarryNoOversizeDefinitions() throws {
        let fits = allFixtureFITs()
        guard !fits.isEmpty else { return }
        var sawOversizeSource = false
        for url in fits {
            let original = try Data(contentsOf: url)
            let result = FitStreamSanitizer.sanitize(original)
            let before = try #require(oversizeDefinitions(in: original),
                                      "\(url.lastPathComponent): unwalkable FIT stream")

            let name = url.lastPathComponent
            let after = try #require(oversizeDefinitions(in: result.data),
                                     "\(name): sanitizer produced an unwalkable FIT stream")
            #expect(after.isEmpty, "\(name): still oversize after sanitizing: \(after)")
            #expect(Set(result.droppedMessageTypes.keys) == Set(before),
                    "\(name): dropped \(result.droppedMessageTypes), expected \(Set(before))")
            if before.isEmpty {
                // Nothing to fix ⇒ byte-identical passthrough, so an already-correct parse
                // can never be perturbed by this guard.
                #expect(result.data == original, "\(name): not a byte-identical passthrough")
            } else {
                sawOversizeSource = true
                #expect(result.data.count < original.count)
            }
        }
        #expect(sawOversizeSource,
                "no fixture exercises the oversize path — the guard is untested")
    }

    /// End-to-end: the CIQ file that triggered the overflow parses to its full 1 Hz stream.
    /// Pre-fix this yielded 269 of 4154 records (and often a SIGSEGV).
    @Test func ciqFixtureParsesEveryRecord() throws {
        let url = testFixturesDir.appendingPathComponent(
            "sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let track = try FitSessionParser.parse(url: url)
        #expect(track.samples.count == 4154)
        #expect(track.capabilities.sampleRateHz == 1.0)
        #expect(track.capabilities.hasAccel)          // stripped, but the channel existed
        let distance = try #require(track.samples.last?.distanceM)
        #expect(abs(distance - 12785.1) < 1.0)
    }
}
