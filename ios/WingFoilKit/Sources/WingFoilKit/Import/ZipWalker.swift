import Foundation

/// One FIT found while walking an import container. `name` is the display path
/// (`export.zip/2026-08-01.zip/12345.fit` for nested archives).
public struct DiscoveredFit: Sendable, Equatable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public struct ZipWalkResult: Sendable, Equatable {
    public var fits: [DiscoveredFit] = []
    /// Entries that were neither FIT, gzip nor ZIP (Garmin's GDPR export is full of JSON).
    public var ignoredEntries = 0
    /// ZIP containers opened, including nested ones.
    public var archives = 0
    /// Containers we could not read at all.
    public var unreadable = 0

    public init() {}
}

/// Walks an imported blob and yields every FIT inside it: plain FIT, gzipped FIT, ZIP of
/// FITs, or Garmin's GDPR export (ZIPs nested inside ZIPs). Depth-limited, fail-soft:
/// a broken member never aborts the walk.
public enum ZipWalker {

    public static let maxDepth = 4

    public static func walk(data: Data, name: String) -> ZipWalkResult {
        var result = ZipWalkResult()
        visit(data: data, name: name, depth: 0, into: &result)
        return result
    }

    private static func visit(data: Data, name: String, depth: Int, into result: inout ZipWalkResult) {
        var payload = data
        if IcuPayload.isGzip(payload) {
            guard let inflated = try? Gzip.decompress(payload) else {
                result.unreadable += 1
                return
            }
            payload = inflated
        }
        if IcuPayload.isFit(payload) {
            result.fits.append(DiscoveredFit(name: name, data: payload))
            return
        }
        guard IcuPayload.isZip(payload) else {
            result.ignoredEntries += 1
            return
        }
        guard depth < maxDepth else {
            result.unreadable += 1
            return
        }
        guard let entries = try? IcuPayload.zipEntries(payload) else {
            result.unreadable += 1
            return
        }
        result.archives += 1
        for entry in entries {
            // Skip resource forks / macOS metadata that would just count as noise.
            if entry.name.hasPrefix("__MACOSX/") || entry.name.hasPrefix(".") { continue }
            visit(data: entry.data, name: "\(name)/\(entry.name)", depth: depth + 1, into: &result)
        }
    }
}
