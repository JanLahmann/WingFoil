import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import WingFoilKit

/// Writes a session video, one frame at a time, into an .mp4 — off the main actor, with no
/// screen capture anywhere in it.
///
/// **Why not ReplayKit.** The cinema clip records the live glass, for a good reason it states
/// itself: the replay already exists and rebuilding it offscreen would be a second renderer
/// that can disagree with the first. A reel is a different artefact and the trade goes the
/// other way. It is 9:16 at a fixed 1080 × 1920 whatever phone it came off, it has to be the
/// same video from two riders' phones, it must not depend on Dynamic Type or on a
/// notification arriving mid-recording, it renders faster than real time, and — the thing
/// that settles it — `RPScreenRecorder` writes a zero-byte file in the Simulator, so a
/// screen-captured reel could never be looked at except by hand on a phone.
///
/// The whole encoder is the standard four pieces: an `AVAssetWriter` in `.mp4`, one H.264
/// `AVAssetWriterInput`, an `AVAssetWriterInputPixelBufferAdaptor` over a `CVPixelBufferPool`,
/// and a loop that waits on `isReadyForMoreMediaData`.
enum ReelRenderer {

    enum Failure: LocalizedError, Equatable {
        case noTrack
        case writer(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noTrack:
                "This session has no track to draw — a video needs positions."
            case .writer(let reason):
                "The video could not be written (\(reason))."
            case .cancelled:
                "Export cancelled."
            }
        }
    }

    /// Bits per second. 1080 × 1920 at 30 fps of a mostly-still map with a line growing over
    /// it is not a demanding encode; 10 Mbps is generous for it and keeps a thirty-second
    /// reel comfortably inside what a messaging app will carry without re-encoding.
    static let bitRate = 10_000_000

    /// Renders `scene` to `output`, reporting 0…1 as it goes.
    ///
    /// `progress` is called on whatever thread the loop is on — the caller hops to the main
    /// actor itself, so a UI that only wants every tenth frame can say so.
    @discardableResult
    static func render(_ scene: ReelScene, to output: URL,
                       progress: @Sendable (Double) -> Void = { _ in }) throws -> URL {
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        let size = ReelScene.size
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        } catch {
            throw Failure.writer("\(error)")
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                // One keyframe a second: a reader scrubbing a twenty-second clip should
                // land on a real frame rather than on a smear.
                AVVideoMaxKeyFrameIntervalKey: ReelPlan.fps,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ])

        guard writer.canAdd(input) else { throw Failure.writer("the encoder refused the input") }
        writer.add(input)
        guard writer.startWriting() else {
            throw Failure.writer(writer.error.map { "\($0)" } ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        let space = CGColorSpaceCreateDeviceRGB()
        let frames = scene.plan.frameCount
        var frame = 0
        while frame < frames {
            if Task.isCancelled {
                input.markAsFinished()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: output)
                throw Failure.cancelled
            }
            guard input.isReadyForMoreMediaData else {
                // The encoder is behind. Yielding the thread is the documented way to wait
                // on a non-real-time input without a run loop, and at 30 fps of static-ish
                // frames it is hit rarely and briefly.
                Thread.sleep(forTimeInterval: 0.002)
                continue
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw Failure.writer("no pixel buffer pool")
            }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let pixels = buffer else {
                throw Failure.writer("no pixel buffer")
            }

            CVPixelBufferLockBaseAddress(pixels, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixels),
                width: CVPixelBufferGetWidth(pixels),
                height: CVPixelBufferGetHeight(pixels),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue) {
                ReelFrame.draw(context, scene: scene,
                               reelTime: Double(frame) / Double(ReelPlan.fps))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])

            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(ReelPlan.fps))
            guard adaptor.append(pixels, withPresentationTime: time) else {
                throw Failure.writer(writer.error.map { "\($0)" } ?? "a frame was refused")
            }
            frame += 1
            progress(Double(frame) / Double(frames))
        }

        input.markAsFinished()
        // `finishWriting(completionHandler:)` is the only way to know the moov atom landed,
        // and this function is synchronous by design (it is the body of a detached task), so
        // the wait is a semaphore rather than a continuation.
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()

        if writer.status != .completed {
            throw Failure.writer(writer.error.map { "\($0)" } ?? "the file did not finish")
        }
        return output
    }

    // MARK: - Where the file goes

    /// The caches directory, not `tmp`: a reel is worth keeping alive while the share sheet
    /// is open and worth losing when the system is short, which is exactly what caches means.
    /// Same name as the shared FIT and the cinema clip, so a rider's three exports of one
    /// afternoon sort together.
    static func destination(for row: SessionRow) -> URL {
        let name = FitShareFilter.filename(date: row.startDate, title: SessionDisplay.title(row),
                                           pathExtension: "mp4", timeZone: row.displayZone)
        let directory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Reel", isDirectory: true)
        return directory.appendingPathComponent(name)
    }

    /// Everything this feature has ever written, gone. Called when the sheet closes: the
    /// share sheet has already copied whatever it was given by then, and a video nobody
    /// asked to keep is 10 MB of somebody's phone.
    static func clearCache() {
        let directory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Reel", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    static func size(of url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) as? Int64
            ?? 0
    }
}
