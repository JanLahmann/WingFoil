import Foundation

/// Standard on-device locations (plan §3.1): `Application Support/wingfoil.sqlite` plus
/// `Application Support/Sessions/<uuid>/{original.fit,analysis.json}`.
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

/// The immutable per-session file archive. The original FIT is never rewritten; the
/// analysis JSON is a cache that can be dropped and recomputed at any time
/// (engine-version bump ⇒ lazy re-analysis).
public struct SessionArchive: Sendable {

    public enum Error: Swift.Error, CustomStringConvertible {
        case missingOriginal(String)

        public var description: String {
            switch self {
            case .missingOriginal(let id): "no original.fit archived for session \(id)"
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

    public func originalURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("original.fit")
    }

    public func analysisURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("analysis.json")
    }

    public func storeOriginal(_ data: Data, id: String) throws {
        try FileManager.default.createDirectory(at: directory(for: id),
                                                withIntermediateDirectories: true)
        try data.write(to: originalURL(for: id), options: .atomic)
    }

    public func originalData(for id: String) throws -> Data {
        let url = originalURL(for: id)
        guard let data = try? Data(contentsOf: url) else { throw Error.missingOriginal(id) }
        return data
    }

    /// Re-parses the archived FIT. Samples (lat/lon/speed) are deliberately not stored in
    /// the DB — the map and the chart re-parse on demand (plan §3.3).
    public func rawTrack(for id: String) throws -> RawTrack {
        try FitSessionParser.parse(data: try originalData(for: id))
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
