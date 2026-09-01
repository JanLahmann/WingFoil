import AVFoundation
import Foundation
import UniformTypeIdentifiers
import WingFoilKit

/// A piece of music the rider chose to put under a clip.
///
/// Stored by *our* copy of the file rather than by where it came from. The document picker
/// hands back a security-scoped URL that is alive for about as long as the sheet is, and a
/// clip's music is needed twenty seconds to four minutes later, at the end of a recording,
/// possibly after the app has been backgrounded by the system's own recording banner. A
/// bookmark would survive that but not much else — a file in iCloud Drive that has since been
/// evicted, a share sheet's temporary item, a folder the rider has since revoked — and every
/// one of those failures would surface as a silent clip with no explanation. A copy in our own
/// container is a file that either exists or does not, which is a state the sheet can show.
///
/// The cost is a duplicate of one audio file (single slot: adopting a new track deletes the
/// old one), which is a few megabytes against a library that stores whole FITs.
struct ReplayMusicTrack: Codable, Equatable, Sendable, Identifiable {
    /// What the rider will recognise: the file's own display name, extension included.
    let name: String
    /// How long the file is, so the sheet can say whether it will loop or be cut.
    let durationS: Double
    /// The name of our copy inside `ReplayMusicStore.directory`. The id as well, since one
    /// slot means one track.
    let file: String

    var id: String { file }

    /// The copy, if it is still there. Nil is the "gracefully forget it" case — see
    /// `ReplayMusicStore.remembered`.
    var url: URL? {
        guard let directory = ReplayMusicStore.directory else { return nil }
        let url = directory.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// Where a chosen track is kept, and the one place that copies one in.
///
/// **The seam for bundled tracks.** Everything downstream of here — the setup sheet's row, the
/// cinema view's `music` parameter, `ReplayClipSoundtrack` — takes a file URL and asks nothing
/// about where it came from. "Pick one of ours" would be a second row on the sheet producing a
/// URL out of the app bundle, and no other file would change. What is missing is the audio: a
/// track shipped in an app and then posted to social networks by its riders needs a licence
/// that covers exactly that, and nothing from a commercial streaming service can ever be it —
/// those files are DRM'd, their APIs hand out stream handles rather than samples, and their
/// terms forbid redistribution outright. Hence the rider's own file, and the one-line caption
/// under the row.
enum ReplayMusicStore {

    /// `Application Support/ReplayMusic/` — beside the session archive, and backed up with it.
    static var directory: URL? {
        guard let root = try? AppPaths.applicationSupport() else { return nil }
        let url = root.appendingPathComponent("ReplayMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    enum Failure: LocalizedError {
        case unreadable
        case silent

        var errorDescription: String? {
            switch self {
            case .unreadable: "That file could not be read."
            case .silent:
                "That file has no music in it, or is too short to use "
                    + "(under \(Int(ReplayClipSoundtrack.shortestTrackS)) second)."
            }
        }
    }

    /// Copies what the document picker handed back into our own container and measures it.
    ///
    /// The duration is probed here rather than at export time for one reason: it is the only
    /// thing that tells the rider, *before* he spends the length of a clip recording it,
    /// whether his track will be trimmed or looped. It also catches the picked-by-accident
    /// cases — a voice memo of two seconds, a text file renamed — while there is still a sheet
    /// to say so on.
    static func adopt(_ picked: URL) async throws -> ReplayMusicTrack {
        guard let directory else { throw Failure.unreadable }
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

        // A fresh name every time: the same song picked twice must not race an export that is
        // still reading the first copy.
        let file = UUID().uuidString + "." + (picked.pathExtension.isEmpty ? "m4a"
                                                                           : picked.pathExtension)
        let copy = directory.appendingPathComponent(file)
        do {
            try FileManager.default.copyItem(at: picked, to: copy)
        } catch {
            throw Failure.unreadable
        }

        let asset = AVURLAsset(url: copy)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        let hasAudio = (try? await asset.loadTracks(withMediaType: .audio))?.isEmpty == false
        guard hasAudio, seconds >= ReplayClipSoundtrack.shortestTrackS else {
            try? FileManager.default.removeItem(at: copy)
            throw Failure.silent
        }
        return ReplayMusicTrack(name: picked.lastPathComponent, durationS: seconds, file: file)
    }

    /// Throws away every copy but this one — called when the choice changes, so the container
    /// holds at most one track. Nil sweeps the lot.
    static func keepOnly(_ track: ReplayMusicTrack?) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for file in files where file != track?.file {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// What the sheet offers as "Use last", or nil when the copy has gone — deleted by hand in
    /// Files, lost to a restore, or swept by `keepOnly`. Forgotten quietly: a rider who is
    /// handed "Use last: sunset.m4a" and then gets silence has been lied to, and there is
    /// nothing he could have done about it.
    static func remembered(_ stored: ReplayMusicTrack?) -> ReplayMusicTrack? {
        guard let stored, stored.url != nil else { return nil }
        return stored
    }
}
