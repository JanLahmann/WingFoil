import Foundation

/// What a blob of recording bytes turned out to be.
///
/// Decided by **content**, never by filename: the callers that matter — a file dropped on
/// the share sheet, a member of a GDPR ZIP, an original re-read out of the archive — all
/// have bytes and only sometimes have a trustworthy name.
public enum TrackFormat: String, Sendable, CaseIterable {
    case fit
    case gpx
    /// Garmin's Training Center Database v2 — how a Polar, Suunto or Coros session usually
    /// reaches CleanJibe through intervals.icu. The one format that is not one input class:
    /// with `Extensions/TPX/Speed` it is class (b) and its records certify, without it class
    /// (c) like a GPX (`TcxSessionParser`).
    case tcx
    /// The CleanJibe watch container (`docs/watch-session-schema.md`) — what the watchOS app
    /// hands the phone over `WCSession.transferFile`. Named for the extension it is stored
    /// under rather than for the watch, because like the other two this is a *format* and the
    /// pipeline past this point does not know what wrote it.
    case watch = "cjw"
    /// The Garmin watch's **direct** stream (`docs/transfer-format.md`) — the pages the
    /// watch sends over the Connect IQ link, concatenated. Named for its extension like the
    /// other four: past this enum nothing knows the bytes crossed a radio rather than an
    /// account. A DEV door (docs/channels.md); the kit reads it in every channel, and only
    /// the app's inbox is gated.
    case direct = "cjr"

    /// The extension the archive stores this format under.
    public var fileExtension: String { rawValue }
}

/// The single door every recording comes through (engine 0.9.0).
///
/// Before GPX there was one parser and every caller named it. Now there are several, and
/// the choice between them is a property of the *file* rather than of the caller — so it is
/// made here, once, and nothing downstream of `RawTrack` + `SourceCapabilities` knows or
/// needs to know which door a track came in by. That is the whole point of the input-class
/// split (docs/plan.md §3.3): the pipeline degrades on capabilities, not on formats.
///
/// Mirrors `parse_track` in lab/src/wingfoil_lab/parse.py.
public enum TrackParser {

    /// FIT until the bytes say otherwise. The FIT signature (`.FIT` at byte 8) is the
    /// stronger test, but the others announce themselves at the very front of the file —
    /// `CJWS` for a watch container, `CJR1` for a direct stream, a leading `<` plus a root
    /// element for the two XML formats — so they all go first and FIT stays the fallback it
    /// has always been. TCX is
    /// tested before GPX only because both start with `<`; their root elements are
    /// unambiguous, so the order is a convention rather than a tie-break.
    public static func format(_ data: Data) -> TrackFormat {
        if WatchSessionContainer.isContainer(data) { return .watch }
        if DirectStreamDecoder.isStream(data) { return .direct }
        if TcxSessionParser.isTcx(data) { return .tcx }
        return GpxSessionParser.isGpx(data) ? .gpx : .fit
    }

    public static func parse(data: Data) throws -> RawTrack {
        switch format(data) {
        case .gpx: try GpxSessionParser.parse(data: data)
        case .tcx: try TcxSessionParser.parse(data: data)
        case .watch: try WatchSessionParser.parse(data: data)
        case .direct: try DirectStreamParser.parse(data: data)
        case .fit: try FitSessionParser.parse(data: data)
        }
    }

    public static func parse(url: URL) throws -> RawTrack {
        guard let data = try? Data(contentsOf: url) else {
            throw FitSessionParser.ParseError.unreadable(url)
        }
        var track = try parse(data: data)
        track.sourceURL = url
        return track
    }
}
