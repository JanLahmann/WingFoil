import Foundation
import ReplayKit
import SwiftUI
import WingFoilKit

/// ReplayKit, wrapped down to the four things the cinema replay actually needs: can we
/// record, start, stop with a file, throw the file away.
///
/// **Why ReplayKit and not an offline render.** The replay already exists — a map, a moving
/// dot, captions that appear as the playhead crosses them — and it is already the thing a
/// rider watches. Rebuilding all of it a second time against `AVAssetWriter`, on a background
/// thread, with its own copy of the pacing and the caption timing, would be a second renderer
/// that can disagree with the first. `RPScreenRecorder` records what is on the glass, so the
/// replay UI *is* the renderer and there is only ever one of it. The cost is that the clip is
/// captured in real time and can only be verified on a device — see `isAvailable`.
///
/// **The simulator lies.** On iOS 26 `isAvailable` comes back **true** in the Simulator and
/// the whole flow runs — permission, start, stop, a file at the right path — and the file is
/// zero bytes, because there is no capture pipeline behind it. So everything except the
/// pixels can be exercised on a Mac, and only a phone can say whether the clip is any good.
/// The `.empty` failure below is what makes that difference visible rather than shippable.
///
/// **The microphone is off and stays off.** `isMicrophoneEnabled = false` before every start:
/// the default is sticky across launches, and a clip that quietly picked up a living room is
/// the worst possible surprise to find after sharing one.
@MainActor
@Observable
final class ReplayRecorder {

    /// Everything that can go wrong, in the rider's words rather than ReplayKit's.
    enum Failure: LocalizedError, Equatable {
        /// `isAvailable` is false: Low Power Mode, an active AirPlay/mirroring session, or
        /// the simulator, which has no screen to capture.
        case unavailable
        /// The rider said no to the system's one-time permission alert.
        case declined
        /// The capture stopped without error and left nothing behind. It is what the
        /// simulator does (it reports `isAvailable`, records nothing and writes a zero-byte
        /// file), and it is what a capture that was killed the instant it began does on a
        /// phone. Either way there is no clip, and offering an empty `.mp4` to a share sheet
        /// is worse than saying so.
        case empty
        /// Anything else ReplayKit reported, kept verbatim — these are rare and the exact
        /// text is the only thing that makes a bug report actionable.
        case recorder(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Screen recording is not available right now. Low Power Mode, AirPlay and "
                    + "screen mirroring all switch it off."
            case .declined:
                "Screen recording was not allowed, so there is no clip. You can still watch "
                    + "the replay."
            case .empty:
                "The recording came back empty, so there is no clip. Screen recording does "
                    + "not work in the iOS Simulator; on a phone, try again."
            case .recorder(let message):
                "The recording could not be made: \(message)"
            }
        }
    }

    /// Where the finished clip is, once there is one. Nil until `stop()` returns.
    private(set) var clip: URL?
    /// True between a successful `start()` and the `stop()` that ends it. The cinema view
    /// reads it to decide whether the stop control means "stop recording" or "leave".
    private(set) var isRecording = false

    /// Computed rather than stored, so the only stored state is two `Sendable` values and the
    /// initializer can be `nonisolated` — which is what lets a `View` hold one in `@State`
    /// without a main-actor hop in a property initializer. `shared()` is a singleton; there is
    /// no cost to asking for it again.
    private var screen: RPScreenRecorder { RPScreenRecorder.shared() }

    nonisolated init() {}

    /// Whether the button should offer a recording at all — false in Low Power Mode, under
    /// AirPlay or screen mirroring, and on some devices while another capture is running.
    ///
    /// Not a promise that a clip will come out the other end: see the type comment on what
    /// the Simulator claims here. `stop` is where an empty capture is caught.
    static var isAvailable: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if stubbedInSimulator { return true }
        #endif
        return RPScreenRecorder.shared().isAvailable
    }

    #if DEBUG && targetEnvironment(simulator)
    /// `UI_REPLAY_CLIP=stub` makes `start`/`stop` succeed without ReplayKit and hand back a
    /// placeholder file with bytes in it, so the clip sheet — the player, the size, the share
    /// link, discard — can be driven on a machine whose real capture writes nothing. Same
    /// family as `UI_SHEET=share`: it stages a state the machine cannot otherwise reach, and
    /// it stages nothing else.
    static var stubbedInSimulator: Bool {
        ProcessInfo.processInfo.environment["UI_REPLAY_CLIP"] == "stub"
    }
    #endif

    // MARK: - Transport

    /// Begins capture. Throws rather than returning a flag: every caller has to decide
    /// between "record" and "just watch", and a silent failure would produce a replay that
    /// looks like it is recording and is not.
    func start() async throws {
        guard !isRecording else { return }
        clip = nil

        #if DEBUG && targetEnvironment(simulator)
        if Self.stubbedInSimulator {
            isRecording = true
            return
        }
        #endif

        guard screen.isAvailable else { throw Failure.unavailable }
        screen.isMicrophoneEnabled = false
        do {
            try await started()
            isRecording = true
        } catch {
            throw Self.translate(error)
        }
    }

    /// `startRecording` bridged by hand, and it has to be.
    ///
    /// ReplayKit declares `startRecording(handler:)` with a **defaulted** handler, so the
    /// bare `startRecording()` is a perfectly good synchronous call — and it is the one
    /// overload resolution picks for `try await screen.startRecording()`. The compiler says
    /// so ("no 'async' operations occur within 'await'"), the recorder starts, and the
    /// permission refusal that never arrives is the whole reason this class exists. A
    /// continuation names the callback explicitly and cannot be resolved to anything else.
    private func started() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            screen.startRecording { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Ends capture and writes the clip to a temp file named after the session.
    ///
    /// Returns nil when there was nothing running — the cancel path can reach this after an
    /// interruption already stopped the recorder, and "no clip" is a state, not an error.
    @discardableResult
    func stop(named name: String) async throws -> URL? {
        guard isRecording else { return nil }
        isRecording = false

        let url = Self.temporaryClipURL(named: name)
        #if DEBUG && targetEnvironment(simulator)
        if Self.stubbedInSimulator {
            // Not a playable movie — a placeholder with the right name and extension, which
            // is everything the share sheet's plumbing touches.
            try? Data("stub replay clip".utf8).write(to: url, options: .atomic)
            clip = url
            return url
        }
        #endif

        do {
            try await screen.stopRecording(withOutput: url)
        } catch {
            throw Self.translate(error)
        }
        // A clip with no bytes in it is not a clip. Checked here rather than left to the
        // sheet, so "0 KB" can never reach a share sheet and land in somebody's chat.
        guard Self.size(of: url) > 0 else {
            try? FileManager.default.removeItem(at: url)
            throw Failure.empty
        }
        clip = url
        return url
    }

    /// Deletes a clip the rider decided against. Temp files would be reaped eventually; a
    /// discarded video should not sit on the disk waiting for that.
    func discard() {
        if let clip { try? FileManager.default.removeItem(at: clip) }
        clip = nil
    }

    // MARK: - Files

    /// `…/tmp/Replay/2026-08-30-torbole.mp4` — one directory, and the name is the session's,
    /// so a second recording of the same afternoon replaces the first instead of piling up.
    ///
    /// The name comes from `FitShareFilter.filename`, which is what the shared FIT is called:
    /// the clip and the recording of one afternoon should arrive in a chat looking like two
    /// halves of the same thing.
    static func clipName(for row: SessionRow) -> String {
        FitShareFilter.filename(date: row.startDate, title: SessionDisplay.title(row),
                                pathExtension: "mp4", timeZone: row.displayZone)
    }

    private static func temporaryClipURL(named name: String) -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Replay", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        return url
    }

    /// Size of the finished clip, for the share button's label — the same "you are about to
    /// send this many megabytes" courtesy the FIT tab already pays.
    static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    // MARK: - Errors

    /// ReplayKit's `userDeclined` is the one error with a different answer — the rider can
    /// still watch — so it is the one that gets its own case.
    private static func translate(_ error: any Error) -> Failure {
        let nsError = error as NSError
        if nsError.domain == RPRecordingErrorDomain,
           RPRecordingErrorCode(rawValue: nsError.code) == .userDeclined {
            return .declined
        }
        return .recorder(nsError.localizedDescription)
    }
}
