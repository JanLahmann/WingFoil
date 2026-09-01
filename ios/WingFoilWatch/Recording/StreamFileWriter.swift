import Foundation
import OSLog

/// An append-only binary stream on disk, buffered so a 50 Hz sensor does not become 50
/// filesystem calls a second.
///
/// **This is the memory bound for the whole recorder.** The accelerometer alone produces
/// 180 000 samples an hour; holding a session in an array and serialising it at stop would
/// grow without limit and would lose everything if the app were jetsammed at minute 89. So
/// each stream is written as it arrives, and the only thing in memory is a buffer that never
/// exceeds `capacity`.
///
/// "Ring buffer" in the sense that matters — bounded memory, reused storage — but
/// deliberately **not** one that overwrites: a full buffer is flushed to disk, never
/// discarded. A recorder that silently dropped the oldest samples when the filesystem got
/// slow would be one that quietly lost the rider's best run, and would look exactly like a
/// working recorder while doing it.
///
/// Thread-safe by lock rather than by actor: the accelerometer handler runs on its own
/// `OperationQueue` 50 times a second, and hopping to an actor per sample would put 50 tasks
/// a second on the scheduler to move eight bytes.
final class StreamFileWriter: @unchecked Sendable {

    private static let log = Logger(subsystem: "de.lahmann.wingfoil.watch", category: "stream")

    let url: URL
    /// Bytes held before a flush. 16 KB is two seconds of accelerometer and about four
    /// minutes of track.
    private let capacity: Int

    /// Guards every stored property below it. Held only for buffer appends and the write
    /// itself, both of which are microseconds.
    private let lock = NSLock()
    private var buffer: Data
    private var handle: FileHandle?
    private var written = 0
    private var records = 0
    private var failure: String?

    init(url: URL, capacity: Int = 16 * 1024) throws {
        self.url = url
        self.capacity = capacity
        self.buffer = Data(capacity: capacity)
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.handle = try FileHandle(forWritingTo: url)
    }

    /// Appends one record. Never throws: a recorder that stopped riding because a write
    /// failed would be worse than one that carried on and reported it at the end.
    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        records += 1
        if buffer.count >= capacity { flushLocked() }
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        flushLocked()
    }

    private func flushLocked() {
        guard !buffer.isEmpty, let handle else { return }
        do {
            try handle.write(contentsOf: buffer)
            written += buffer.count
            buffer.removeAll(keepingCapacity: true)
        } catch {
            // Keep the bytes in the buffer for one more try, but do not let it grow without
            // limit — past twice capacity the disk is not coming back and holding the data
            // would take the app down with it.
            failure = "\(error)"
            Self.log.error("stream write failed for \(self.url.lastPathComponent): \(error)")
            if buffer.count > capacity * 2 { buffer.removeAll(keepingCapacity: true) }
        }
    }

    /// Flushes, closes the handle and reports what got written. Safe to call twice.
    @discardableResult
    func close() -> (records: Int, bytes: Int, failure: String?) {
        lock.lock()
        defer { lock.unlock() }
        flushLocked()
        try? handle?.close()
        handle = nil
        return (records, written, failure)
    }

    var recordCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}
