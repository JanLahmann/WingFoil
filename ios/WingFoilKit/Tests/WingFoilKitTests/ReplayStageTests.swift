import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import WingFoilKit

/// Where the clip is on the glass, and where that lands in the recorded file's pixels.
///
/// This is the arithmetic that is wrong by a scale factor on exactly one device family and
/// right everywhere else, which is the worst way for geometry to be wrong — so the two halves
/// are pinned separately: the **stage** against screen sizes that really exist, and the
/// **crop** against a real movie made on the spot, because a claim about pixel dimensions is
/// only worth having if something actually produced those pixels.
@Suite struct ReplayStageTests {

    /// A 15 Pro Max in points, which is the tall end of what the app runs on, and a 4:3 iPad,
    /// which is the other end.
    private let phone = CGSize(width: 430, height: 932)
    private let pad = CGSize(width: 834, height: 1194)

    // MARK: - The stage

    /// On a phone every ratio narrower than the glass is limited by the width, and the
    /// letterbox is symmetrical top and bottom.
    @Test func aBoxIsAsBigAsItsRatioAllowsAndSitsInTheMiddle() {
        let portrait = ReplayStage.rect(in: phone, framing: .portrait)
        #expect(portrait.width == 430)
        #expect(abs(portrait.height - 430 * 16 / 9) < 0.001)
        #expect(abs(portrait.midX - phone.width / 2) < 0.001)
        #expect(abs(portrait.midY - phone.height / 2) < 0.001)
        // Comfortably inside a 932 pt screen: 9:16 is *narrower* than a modern phone.
        #expect(portrait.height < phone.height)
        #expect(portrait.minY > 0)

        let square = ReplayStage.rect(in: phone, framing: .square)
        #expect(square.width == 430 && square.height == 430)

        let wide = ReplayStage.rect(in: phone, framing: .landscape)
        #expect(wide.width == 430)
        #expect(abs(wide.height - 430 * 9 / 16) < 0.001)
    }

    /// Where the height binds instead — a 9:16 box on a 4:3 screen is limited by how tall the
    /// screen is, and the bars go down the sides.
    @Test func aTallBoxOnASquarishScreenIsLimitedByTheHeight() {
        let portrait = ReplayStage.rect(in: pad, framing: .portrait)
        #expect(abs(portrait.height - pad.height) < 0.001)
        #expect(abs(portrait.width - pad.height * 9 / 16) < 0.001)
        #expect(portrait.minX > 0)
        #expect(abs(portrait.midX - pad.width / 2) < 0.001)
    }

    /// Full screen is the whole glass and nothing else — no box, no bars, and (see `crop`)
    /// no export.
    @Test func fullScreenIsTheWholeGlass() {
        #expect(ReplayStage.rect(in: phone, framing: .fullScreen)
                == CGRect(origin: .zero, size: phone))
        #expect(ReplayFraming.fullScreen.aspect == nil)
        // A screen of no size cannot be divided into one.
        #expect(ReplayStage.rect(in: .zero, framing: .portrait) == .zero)
    }

    /// The cards ask the framing which way round they are, exactly as the share card asks its
    /// shape — so a fifth ratio would land in the right layout with no edit.
    @Test func theFramingKnowsWhetherItIsWide() {
        #expect(!ReplayFraming.portrait.isWide(on: phone))
        #expect(!ReplayFraming.square.isWide(on: phone))
        #expect(ReplayFraming.landscape.isWide(on: phone))
        // Full screen answers for the screen it is on, which is the only honest answer.
        #expect(!ReplayFraming.fullScreen.isWide(on: phone))
        #expect(ReplayFraming.fullScreen.isWide(on: CGSize(width: 932, height: 430)))
    }

    // MARK: - Points to pixels

    /// Proportional and not `× scale`: the recorder reports the *file's* dimensions, which are
    /// not the panel's on a phone with display zoom on or on a 3× device that downsamples.
    /// Mapping fractions onto fractions is right whatever the two are.
    @Test func theCropIsTheSameFractionOfTheVideoAsOfTheScreen() {
        let stage = ReplayStage.rect(in: phone, framing: .square)
        // A 3× capture, which is what a Pro Max writes.
        let pixels = CGSize(width: 1290, height: 2796)
        let crop = ReplayStage.crop(stage: stage, screenPoints: phone, videoPixels: pixels)
        #expect(crop.width == 1290)
        #expect(abs(crop.height - 1290) <= 2)
        #expect(abs(crop.midY - pixels.height / 2) <= 2)

        // …and the same stage against a file that is not 3× at all still lands centred and
        // full width, which is the assertion a `× scale` implementation fails.
        let odd = CGSize(width: 886, height: 1920)
        let scaled = ReplayStage.crop(stage: stage, screenPoints: phone, videoPixels: odd)
        #expect(scaled.width == 886)
        #expect(abs(scaled.midY - odd.height / 2) <= 2)
    }

    /// H.264 encodes 2 × 2 chroma blocks, so an odd render size is rejected or silently
    /// rounded. Every number that comes out of here is even, and none of it leaves the frame.
    @Test func everyCropIsEvenAndInsideTheFrame() {
        let pixels = CGSize(width: 1179, height: 2555)      // deliberately odd, both ways
        for framing in ReplayFraming.allCases {
            let stage = ReplayStage.rect(in: phone, framing: framing)
            let crop = ReplayStage.crop(stage: stage, screenPoints: phone, videoPixels: pixels)
            #expect(crop.minX.truncatingRemainder(dividingBy: 2) == 0)
            #expect(crop.minY.truncatingRemainder(dividingBy: 2) == 0)
            #expect(crop.width.truncatingRemainder(dividingBy: 2) == 0)
            #expect(crop.height.truncatingRemainder(dividingBy: 2) == 0)
            #expect(crop.minX >= 0 && crop.minY >= 0)
            #expect(crop.maxX <= pixels.width && crop.maxY <= pixels.height)
        }
    }

    /// A full-screen clip is not exported at all: a crop that is the whole frame would cost a
    /// re-encode and buy nothing, and it is also what a failed crop falls back to.
    @Test func aFullScreenClipNeedsNoExport() {
        let pixels = CGSize(width: 1290, height: 2796)
        let stage = ReplayStage.rect(in: phone, framing: .fullScreen)
        let crop = ReplayStage.crop(stage: stage, screenPoints: phone, videoPixels: pixels)
        #expect(!ReplayStage.needsCrop(crop, videoPixels: pixels))

        let square = ReplayStage.crop(stage: ReplayStage.rect(in: phone, framing: .square),
                                      screenPoints: phone, videoPixels: pixels)
        #expect(ReplayStage.needsCrop(square, videoPixels: pixels))
    }

    /// Degenerate inputs give back the whole frame rather than an empty export.
    @Test func nonsenseGivesBackTheWholeFrame() {
        let pixels = CGSize(width: 100, height: 200)
        let whole = CGRect(origin: .zero, size: pixels)
        #expect(ReplayStage.crop(stage: .zero, screenPoints: phone, videoPixels: pixels)
                == whole)
        #expect(ReplayStage.crop(stage: CGRect(x: 0, y: 0, width: 10, height: 10),
                                 screenPoints: .zero, videoPixels: pixels) == whole)
    }

    // MARK: - A real crop, on a real movie

    /// The claim the geometry above is making, checked against pixels something actually
    /// wrote.
    ///
    /// ReplayKit records nothing in the Simulator — a zero-byte file, by design, see
    /// `ReplayRecorder` — so the capture itself is device-only. `AVAssetWriter` is not: it
    /// makes a real movie on a Mac, and the export path (composition, render size, transform,
    /// the mp4 that comes out) is then a checkable claim rather than something only a phone
    /// can settle. **What still needs a device** is whether the crop lands on the frame the
    /// rider was looking at, because only a device produces a recording of the staged screen.
    @Test func croppingASyntheticMovieProducesTheWantedPixels() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-crop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.mp4")
        let size = CGSize(width: 640, height: 1280)
        try await makeMovie(at: source, size: size, frames: 12)

        // The 1:1 stage of a 640 × 1280 "screen": full width, centred vertically.
        let stage = ReplayStage.rect(in: size, framing: .square)
        let crop = ReplayStage.crop(stage: stage, screenPoints: size, videoPixels: size)
        #expect(crop == CGRect(x: 0, y: 320, width: 640, height: 640))

        let output = directory.appendingPathComponent("cropped.mp4")
        _ = try await ReplayClipCropper.crop(source, to: crop, output: output)

        #expect(FileManager.default.fileExists(atPath: output.path))
        let cropped = AVURLAsset(url: output)
        let track = try #require(try await cropped.loadTracks(withMediaType: .video).first)
        let natural = try await track.load(.naturalSize)
        #expect(natural == crop.size)
        // The clip is still the clip: the export must not have swallowed the duration.
        let duration = try await cropped.load(.duration)
        #expect(duration.seconds > 0.2)
    }

    /// A capture with nothing in it — the Simulator's own zero-byte output — is refused rather
    /// than silently producing an empty clip.
    @Test func aFileWithNoVideoIsRefused() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-crop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = directory.appendingPathComponent("empty.mp4")
        try Data().write(to: empty)

        await #expect(throws: ReplayClipCropper.Failure.noVideoTrack) {
            try await ReplayClipCropper.crop(
                empty, to: CGRect(x: 0, y: 0, width: 100, height: 100),
                output: directory.appendingPathComponent("out.mp4"))
        }
    }

    // MARK: - Helpers

    /// A few frames of flat colour at a known size — enough to be a movie, small enough to
    /// write in a test.
    private func makeMovie(at url: URL, size: CGSize, frames: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frames {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) {
                memset(base, Int32(40 + frame),
                       CVPixelBufferGetBytesPerRow(pixels) * Int(size.height))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame),
                                                                timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}
