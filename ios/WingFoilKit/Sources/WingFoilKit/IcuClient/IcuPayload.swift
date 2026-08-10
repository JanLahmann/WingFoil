import Compression
import Foundation
import ZIPFoundation

/// Container sniffing + unwrapping for downloaded activity files.
///
/// `GET /api/v1/activity/{id}/file` hands back whatever the device uploaded, in whatever
/// wrapper intervals.icu kept: a plain FIT, a gzip stream, or a ZIP holding the FIT
/// (Garmin's GDPR export nests ZIPs inside ZIPs). Mirrors `lab/tools/download_icu.py:unwrap`.
public enum IcuPayload {

    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case empty
        case notAFitFile(prefix: String)
        case zipContainsNoFit
        case unreadableZip
        case gzipFailed

        public var description: String {
            switch self {
            case .empty: "empty payload"
            case .notAFitFile(let p): "not a FIT file (header \(p))"
            case .zipContainsNoFit: "ZIP contains no .fit"
            case .unreadableZip: "unreadable ZIP"
            case .gzipFailed: "gzip decompression failed"
            }
        }
    }

    /// A FIT file carries the ASCII tag `.FIT` at bytes 8..<12 of its header.
    public static func isFit(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let start = data.startIndex
        return data[(start + 8)..<(start + 12)].elementsEqual(Array(".FIT".utf8))
    }

    public static func isGzip(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let start = data.startIndex
        return data[start] == 0x1f && data[start + 1] == 0x8b
    }

    public static func isZip(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let start = data.startIndex
        return data[start] == 0x50 && data[start + 1] == 0x4b   // "PK"
    }

    /// Unwrap a single-activity payload down to FIT bytes. Gzip is decompressed, a ZIP
    /// yields its first `.fit` entry, plain FIT passes through; anything else throws.
    public static func unwrap(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw Error.empty }
        var payload = data
        if isGzip(payload) { payload = try Gzip.decompress(payload) }
        if isZip(payload) {
            guard let fit = try firstFit(inZip: payload) else { throw Error.zipContainsNoFit }
            payload = fit
        }
        guard isFit(payload) else {
            throw Error.notAFitFile(prefix: hexPrefix(payload))
        }
        return payload
    }

    /// First `.fit` entry of a ZIP (recursing into nested ZIPs), or nil when there is none.
    static func firstFit(inZip data: Data, depth: Int = 0) throws -> Data? {
        for entry in try zipEntries(data) where entry.name.lowercased().hasSuffix(".fit") {
            return entry.data
        }
        guard depth < ZipWalker.maxDepth else { return nil }
        for entry in try zipEntries(data) where isZip(entry.data) {
            if let nested = try firstFit(inZip: entry.data, depth: depth + 1) { return nested }
        }
        return nil
    }

    static func zipEntries(_ data: Data) throws -> [(name: String, data: Data)] {
        var out: [(String, Data)] = []
        try forEachZipEntry(data) { name, payload in out.append((name, payload)) }
        return out
    }

    /// Streaming entry walk: inflates one member at a time and hands it to `body`, which
    /// is expected to consume it before returning. A Garmin GDPR export is hundreds of
    /// megabytes of nested ZIPs, and materializing all of it at once is what makes bulk
    /// import die on device.
    static func forEachZipEntry(_ data: Data,
                                _ body: (String, Data) throws -> Void) throws {
        guard let archive = try? Archive(data: data, accessMode: .read, pathEncoding: nil) else {
            throw Error.unreadableZip
        }
        for entry in archive where entry.type == .file {
            var buffer = Data()
            buffer.reserveCapacity(Int(entry.uncompressedSize))
            _ = try? archive.extract(entry, skipCRC32: true) { buffer.append($0) }
            if !buffer.isEmpty { try body(entry.path, buffer) }
        }
    }

    /// Central-directory walk: entry paths only, no inflation. Lets a caller decide what
    /// to extract (and when) instead of paying for the whole archive up front.
    static func forEachZipEntryPath(_ data: Data, _ body: (String) -> Void) throws {
        guard let archive = try? Archive(data: data, accessMode: .read, pathEncoding: nil) else {
            throw Error.unreadableZip
        }
        for entry in archive where entry.type == .file { body(entry.path) }
    }

    /// Inflates exactly one member.
    static func extractZipEntry(_ data: Data, path: String) throws -> Data? {
        guard let archive = try? Archive(data: data, accessMode: .read, pathEncoding: nil) else {
            throw Error.unreadableZip
        }
        guard let entry = archive[path] else { return nil }
        var buffer = Data()
        buffer.reserveCapacity(Int(entry.uncompressedSize))
        _ = try? archive.extract(entry, skipCRC32: true) { buffer.append($0) }
        return buffer
    }

    static func hexPrefix(_ data: Data, count: Int = 8) -> String {
        data.prefix(count).map { String(format: "%02x", $0) }.joined()
    }
}

/// Minimal gzip (RFC 1952) reader on top of Apple's Compression framework: strip the
/// member header, raw-inflate the DEFLATE stream, ignore the CRC/ISIZE trailer.
public enum Gzip {

    public static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else {
            throw IcuPayload.Error.gzipFailed
        }
        let flags = bytes[3]
        var offset = 10
        func need(_ n: Int) throws {
            guard offset + n <= bytes.count else { throw IcuPayload.Error.gzipFailed }
        }
        if flags & 0x04 != 0 {                                  // FEXTRA
            try need(2)
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
            try need(xlen)
            offset += xlen
        }
        for mask in [UInt8(0x08), UInt8(0x10)] where flags & mask != 0 {   // FNAME, FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            try need(1)
            offset += 1
        }
        if flags & 0x02 != 0 {                                  // FHCRC
            try need(2)
            offset += 2
        }
        guard offset < bytes.count - 8 else { throw IcuPayload.Error.gzipFailed }
        return try rawInflate(Data(bytes[offset..<(bytes.count - 8)]))
    }

    /// Raw DEFLATE (RFC 1951) — what `COMPRESSION_ZLIB` means in Apple's Compression API.
    static func rawInflate(_ input: Data) throws -> Data {
        let streamStorage = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamStorage.deallocate() }
        var stream = streamStorage.pointee
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { throw IcuPayload.Error.gzipFailed }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        var output = Data()
        var failed = false
        input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                failed = true
                return
            }
            stream.src_ptr = base
            stream.src_size = raw.count
            var status = COMPRESSION_STATUS_OK
            repeat {
                stream.dst_ptr = destination
                stream.dst_size = bufferSize
                status = compression_stream_process(&stream,
                                                   Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    output.append(destination, count: bufferSize - stream.dst_size)
                default:
                    failed = true
                }
            } while status == COMPRESSION_STATUS_OK && !failed
        }
        guard !failed else { throw IcuPayload.Error.gzipFailed }
        return output
    }

    /// Gzip-wrap (used by tests and any future export path). CRC32 is written for
    /// well-formedness; our reader ignores it.
    public static func compress(_ data: Data) throws -> Data {
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
        out.append(try rawDeflate(data))
        var crc = crc32(data).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        var size = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
        return out
    }

    static func rawDeflate(_ input: Data) throws -> Data {
        let streamStorage = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamStorage.deallocate() }
        var stream = streamStorage.pointee
        guard compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { throw IcuPayload.Error.gzipFailed }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        var output = Data()
        var failed = false
        input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.bindMemory(to: UInt8.self).baseAddress
            stream.src_ptr = base ?? UnsafePointer(destination)
            stream.src_size = base == nil ? 0 : raw.count
            var status = COMPRESSION_STATUS_OK
            repeat {
                stream.dst_ptr = destination
                stream.dst_size = bufferSize
                status = compression_stream_process(&stream,
                                                   Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    output.append(destination, count: bufferSize - stream.dst_size)
                default:
                    failed = true
                }
            } while status == COMPRESSION_STATUS_OK && !failed
        }
        guard !failed else { throw IcuPayload.Error.gzipFailed }
        return output
    }

    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) == 1 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
