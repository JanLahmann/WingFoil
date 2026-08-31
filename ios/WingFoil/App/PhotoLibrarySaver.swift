import Foundation
import Photos

/// Putting a finished clip in the rider's camera roll.
///
/// **Why this exists at all.** The end-of-recording sheet used to offer a share sheet and a
/// bin, and a share sheet is not a save: iOS's own "Save Video" action inside it is one
/// destination among a dozen, below the app icons, and half the time it is not there. A clip
/// somebody just spent forty seconds making should be one tap from the place videos live.
///
/// **Add-only, and that is the whole permission.** `.addOnly` asks for the one thing this
/// needs — put a file in — and cannot read a single asset back. It is a different, quieter
/// system prompt than the read/write one, and it is the honest description of what happens:
/// nothing in CleanJibe ever looks at the camera roll. (The photos a rider splices into a clip
/// come from `PhotosPicker`, which runs out of process and needs no permission at all — see
/// `ReplaySetupSheet`. So this is the *only* photo-library permission the app ever asks for.)
///
/// **Why the authorization is re-asked every time rather than cached.** The status can change
/// while the app is running — the rider can walk into iOS Settings and revoke it — and
/// `requestAuthorization` is a no-op that returns the current status once it has been
/// answered. Asking is cheaper than being wrong.
enum PhotoLibrarySaver {

    /// Everything that can go wrong, in the rider's words, plus whether the fix is in iOS
    /// Settings — which is what decides whether the alert gets a second button.
    enum Failure: LocalizedError, Equatable {
        /// The rider said no, now or at some point in the past. The only failure with a fix
        /// the app can point at.
        case denied
        /// The library refused the write. Kept verbatim: these are rare and the exact text is
        /// the only thing that makes a report actionable.
        case library(String)

        var errorDescription: String? {
            switch self {
            case .denied:
                "CleanJibe is not allowed to add to your photo library, so the clip was not "
                    + "saved. You can still share it, or allow it in Settings."
            case .library(let message):
                "The clip could not be saved to Photos: \(message)"
            }
        }

        /// Whether "Open Settings" is a sensible second button.
        var isFixableInSettings: Bool { self == .denied }
    }

    /// Adds the video at `url` to the camera roll. Throws rather than returning a flag,
    /// because the two failures have different answers and a silent one would leave a button
    /// that says "Saved" over a library with nothing in it.
    static func save(video url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        // `.limited` cannot happen for `.addOnly` — a limited selection is a *read* concept —
        // but it is in the enum, and treating an unknown status as permission would be the
        // wrong way to be wrong.
        guard status == .authorized else { throw Failure.denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            throw Failure.library((error as NSError).localizedDescription)
        }
    }
}
