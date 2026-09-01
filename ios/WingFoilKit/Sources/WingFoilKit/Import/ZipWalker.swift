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
    /// Only populated by the collecting `walk`; the streaming walk hands FITs to its
    /// sink and keeps nothing.
    public var fits: [DiscoveredFit] = []
    /// FITs seen, whether or not they were collected.
    public var fitCount = 0
    /// Entries that were neither FIT, gzip nor ZIP (Garmin's GDPR export is full of JSON).
    public var ignoredEntries = 0
    /// ZIP containers opened, including nested ones.
    public var archives = 0
    /// Containers we could not read at all.
    public var unreadable = 0

    public init() {}

    mutating func absorb(_ other: ZipWalkResult) {
        fits.append(contentsOf: other.fits)
        fitCount += other.fitCount
        ignoredEntries += other.ignoredEntries
        archives += other.archives
        unreadable += other.unreadable
    }
}

/// Walks an imported blob and yields every FIT inside it: plain FIT, gzipped FIT, ZIP of
/// FITs, or Garmin's GDPR export (ZIPs nested inside ZIPs). Depth-limited, fail-soft:
/// a broken member never aborts the walk.
public enum ZipWalker {

    public static let maxDepth = 4

    /// What one blob turned out to be, after gzip is peeled off.
    ///
    /// `.track` covers both recording formats (engine 0.9.0): the walker's job is to find
    /// sessions, and which parser reads one is `TrackParser`'s business, decided from the
    /// same bytes further down. Keeping the two apart here would only mean every caller
    /// had to remember to handle both.
    enum Layer {
        case track(Data)
        case archive(Data)
        case ignored
        case unreadable
    }

    static func classify(_ data: Data) -> Layer {
        var payload = data
        if IcuPayload.isGzip(payload) {
            guard let inflated = try? Gzip.decompress(payload) else { return .unreadable }
            payload = inflated
        }
        if IcuPayload.isFit(payload) { return .track(payload) }
        if GpxSessionParser.isGpx(payload) { return .track(payload) }
        // A CleanJibe watch container. Every file import in the app comes through here —
        // `SessionStore.runImport` calls `ingestContainer` for a hand-picked file exactly as
        // it does for a GDPR ZIP — so a format missing from this ladder is not merely
        // unclassified, it is silently dropped as `.ignored` and the rider is told "no FIT
        // found" about a file the parser two modules away can read perfectly well.
        if WatchSessionContainer.isContainer(payload) { return .track(payload) }
        if IcuPayload.isZip(payload) { return .archive(payload) }
        return .ignored
    }

    /// macOS resource forks and dotfiles are pure noise in a GDPR export.
    static func isNoise(_ name: String) -> Bool {
        name.hasPrefix("__MACOSX/") || name.hasPrefix(".")
    }

    // MARK: - Collecting walk (small payloads, tests)

    public static func walk(data: Data, name: String) -> ZipWalkResult {
        var result = ZipWalkResult()
        visit(data: data, name: name, depth: 0, into: &result)
        return result
    }

    private static func visit(data: Data, name: String, depth: Int, into result: inout ZipWalkResult) {
        switch classify(data) {
        case .track(let payload):
            result.fits.append(DiscoveredFit(name: name, data: payload))
            result.fitCount += 1
        case .ignored:
            result.ignoredEntries += 1
        case .unreadable:
            result.unreadable += 1
        case .archive(let payload):
            guard depth < maxDepth, let entries = try? IcuPayload.zipEntries(payload) else {
                result.unreadable += 1
                return
            }
            result.archives += 1
            for entry in entries where !isNoise(entry.name) {
                visit(data: entry.data, name: "\(name)/\(entry.name)", depth: depth + 1,
                      into: &result)
            }
        }
    }

    // MARK: - Streaming walk (bulk GDPR import)

    /// Hands every FIT to `onFit` as it is inflated and releases it before opening the
    /// next member — a Garmin GDPR export is hundreds of MB of nested ZIPs, and holding
    /// all of it is what kills a bulk import on device. Returns the tally only.
    public static func walk(data: Data, name: String,
                            onFit: (DiscoveredFit) async -> Void) async -> ZipWalkResult {
        await visit(data: data, name: name, depth: 0, onFit: onFit)
    }

    private static func visit(data: Data, name: String, depth: Int,
                              onFit: (DiscoveredFit) async -> Void) async -> ZipWalkResult {
        var result = ZipWalkResult()
        switch classify(data) {
        case .track(let payload):
            result.fitCount += 1
            await onFit(DiscoveredFit(name: name, data: payload))
        case .ignored:
            result.ignoredEntries += 1
        case .unreadable:
            result.unreadable += 1
        case .archive(let payload):
            guard depth < maxDepth else {
                result.unreadable += 1
                return result
            }
            // Members are extracted one at a time (`forEachZipEntry`) but the recursion
            // has to await, so each level buffers only the *paths* of its own entries.
            var paths: [String] = []
            do {
                try IcuPayload.forEachZipEntryPath(payload) { paths.append($0) }
            } catch {
                result.unreadable += 1
                return result
            }
            result.archives += 1
            for path in paths where !isNoise(path) {
                guard let entry = try? IcuPayload.extractZipEntry(payload, path: path),
                      !entry.isEmpty else { continue }
                let sub = await visit(data: entry, name: "\(name)/\(path)", depth: depth + 1,
                                      onFit: onFit)
                result.absorb(sub)
            }
        }
        return result
    }
}
