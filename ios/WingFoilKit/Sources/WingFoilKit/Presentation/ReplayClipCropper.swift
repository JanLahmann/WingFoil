import AVFoundation
import CoreGraphics
import Foundation

/// Cutting the chosen frame out of a full-screen screen recording.
///
/// **Why in post and not at capture.** `RPScreenRecorder` records the glass. There is no API
/// that records part of it, and there is no second renderer to draw a 9:16 version into — the
/// whole reason the replay is captured off the screen is that the screen *is* the renderer
/// (see `ReplayRecorder`). So the clip is made full-screen with the wanted frame staged on it
/// (`ReplayStage`), and this cuts that frame out afterwards.
///
/// **Why a video composition and not a resize.** The crop has to keep the pixels it kept: a
/// scale-to-fit would squash a 9:16 box out of a 19.5:9 recording into something nobody framed.
/// An `AVMutableVideoComposition` with a `renderSize` of the crop and a translate transform on
/// the layer is the cheapest exact answer — the encoder writes the wanted rectangle and
/// discards the rest, with no resampling of what it keeps.
///
/// **Why it lives in the kit.** It is the one piece of the recording path that can be tested
/// without a phone. ReplayKit writes nothing in the Simulator (`ReplayRecorder` says so at
/// length), but `AVAssetWriter` will happily make a synthetic movie on a Mac, and the crop is
/// then a checkable claim about pixel dimensions rather than something only a device can
/// settle — see `ReplayClipCropperTests`.
public enum ReplayClipCropper {

    public enum Failure: LocalizedError, Equatable {
        /// The file has no video track — a zero-byte simulator capture, or something that is
        /// not a movie at all.
        case noVideoTrack
        /// `AVAssetExportSession` refused the job or died in the middle of it.
        case export(String)

        public var errorDescription: String? {
            switch self {
            case .noVideoTrack: "the recording has no video in it"
            case .export(let message): message
            }
        }
    }

    /// Crops `url` to `crop`, in the source's own pixel space, and writes it to `output`.
    ///
    /// Returns the output URL. Throws rather than falling back: the *caller* decides what an
    /// un-croppable recording means, and on the recording path it means "offer the full-screen
    /// clip and say so", which is a better answer than silently handing back a file that is not
    /// the shape the rider asked for.
    @discardableResult
    public static func crop(_ url: URL, to crop: CGRect, output: URL,
                            preset: String = AVAssetExportPresetHighestQuality) async throws
        -> URL {
        let asset = AVURLAsset(url: url)
        // A file AVFoundation refuses to open and a movie with no video in it are the same
        // thing here — a recording there is nothing to crop — and the simulator's own
        // zero-byte capture is the first of the two. Neither is worth two error cases.
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }
        let (naturalSize, preferred) = try await track.load(.naturalSize, .preferredTransform)
        let duration = try await asset.load(.duration)

        // The recording's own orientation is baked into `preferredTransform`, and the crop was
        // computed against what the rider *saw* — i.e. the displayed frame, not the stored
        // one. Composing the display transform first and the crop translation after it means
        // the arithmetic is in one space throughout, and a portrait capture stored landscape
        // (which is what a rotated phone produces) crops where it looks like it should.
        let displayed = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let transform = preferred
            .concatenating(.init(translationX: -displayed.minX - crop.minX,
                                 y: -displayed.minY - crop.minY))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = crop.size
        // The source's own frame rate, when it will say — a screen recording is 60 fps on a
        // ProMotion phone and 30 on everything else, and re-timing it here would either drop
        // frames or duplicate them.
        let fps = try await track.load(.nominalFrameRate)
        composition.frameDuration = CMTime(value: 1, timescale: fps > 0 ? CMTimeScale(fps.rounded()) : 30)
        composition.instructions = [instruction]

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.export("the export session could not be created")
        }
        session.videoComposition = composition
        try? FileManager.default.removeItem(at: output)
        do {
            try await session.export(to: output, as: .mp4)
        } catch {
            throw Failure.export((error as NSError).localizedDescription)
        }
        return output
    }
}
