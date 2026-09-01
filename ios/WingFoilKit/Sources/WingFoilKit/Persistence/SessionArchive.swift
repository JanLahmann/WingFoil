import Foundation

/// Standard on-device locations (plan §3.1): `Application Support/wingfoil.sqlite` plus
/// `Application Support/Sessions/<uuid>/{original.fit|original.gpx,analysis.json}`.
public enum AppPaths {

    public static func applicationSupport() throws -> URL {
        let url = try FileManager.default.url(for: .applicationSupportDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func databaseURL() throws -> URL {
        try applicationSupport().appendingPathComponent("wingfoil.sqlite")
    }

    public static func sessionsRoot() throws -> URL {
        try applicationSupport().appendingPathComponent("Sessions", isDirectory: true)
    }
}

/// The immutable per-session file archive. The original recording is never rewritten; the
/// analysis JSON is a cache that can be dropped and recomputed at any time
/// (engine-version bump ⇒ lazy re-analysis).
public struct SessionArchive: Sendable {

    public enum Error: Swift.Error, CustomStringConvertible {
        case missingOriginal(String)

        public var description: String {
            switch self {
            case .missingOriginal(let id): "no original recording archived for session \(id)"
            }
        }
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func standard() throws -> SessionArchive {
        SessionArchive(root: try AppPaths.sessionsRoot())
    }

    public func directory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    /// Where this session's untouched recording lives.
    ///
    /// `original.fit` for a FIT and `original.gpx` for a GPX (engine 0.9.0) — the extension
    /// is part of the promise the archive makes, because these bytes are handed back out:
    /// to the re-analysis path, and to the share sheet, where the filename is what a
    /// stranger sees. A `.gpx` written under a `.fit` name would be a small lie that
    /// eventually reaches somebody else's mailbox.
    ///
    /// A directory holds exactly one original, so the lookup returns whichever is on
    /// disk and falls back to `.fit` — which is what every session archived before 0.9.0
    /// is, and what a caller asking for the path of a session it is about to write means.
    public func originalURL(for id: String) -> URL {
        let dir = directory(for: id)
        for format in TrackFormat.allCases where format != .fit {
            let candidate = dir.appendingPathComponent("original.\(format.fileExtension)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return dir.appendingPathComponent("original.fit")
    }

    /// The format the archived original is in, or nil when there is nothing archived.
    /// Read from the bytes, not from the name — the name is derived from them.
    public func originalFormat(for id: String) -> TrackFormat? {
        guard let data = try? originalData(for: id) else { return nil }
        return TrackParser.format(data)
    }

    public func analysisURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("analysis.json")
    }

    public func storeOriginal(_ data: Data, id: String) throws {
        let dir = directory(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = TrackParser.format(data)
        // One original per session: a re-import that changed format would otherwise leave
        // the old file beside the new one and `originalURL` would keep finding the wrong one.
        for other in TrackFormat.allCases where other != format {
            try? FileManager.default.removeItem(
                at: dir.appendingPathComponent("original.\(other.fileExtension)"))
        }
        try data.write(to: dir.appendingPathComponent("original.\(format.fileExtension)"),
                       options: .atomic)
    }

    public func originalData(for id: String) throws -> Data {
        let url = originalURL(for: id)
        guard let data = try? Data(contentsOf: url) else { throw Error.missingOriginal(id) }
        return data
    }

    /// Re-parses the archived recording — FIT or GPX, decided by its bytes. Samples
    /// (lat/lon/speed) are deliberately not stored in the DB: the map and the chart
    /// re-parse on demand (plan §3.3).
    public func rawTrack(for id: String) throws -> RawTrack {
        try TrackParser.parse(data: try originalData(for: id))
    }

    public func writeAnalysis(_ analysis: SessionAnalysis, id: String) throws {
        try FileManager.default.createDirectory(at: directory(for: id),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(analysis).write(to: analysisURL(for: id), options: .atomic)
    }

    /// Cached analysis, or nil when absent/unreadable/stale (engine version mismatch).
    public func analysis(for id: String, engineVersion: String = AnalysisEngine.version)
    -> SessionAnalysis? {
        guard let data = try? Data(contentsOf: analysisURL(for: id)),
              let decoded = try? JSONDecoder().decode(SessionAnalysis.self, from: data),
              decoded.engineVersion == engineVersion else { return nil }
        return decoded
    }

    public func dropAnalysis(for id: String) {
        try? FileManager.default.removeItem(at: analysisURL(for: id))
    }

    public func dropAllAnalyses() {
        for dir in sessionDirectories() {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("analysis.json"))
        }
    }

    public func delete(id: String) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }

    public func sessionDirectories() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: root,
                                                      includingPropertiesForKeys: nil)) ?? []
    }

    /// Total bytes under the archive root (Settings → storage stats).
    public func diskUsageBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
