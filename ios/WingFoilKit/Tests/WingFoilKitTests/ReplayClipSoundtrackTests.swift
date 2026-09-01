import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import WingFoilKit

/// How a track the rider chose is cut to fit a clip whose length he did not choose, and
/// whether the mux that lays it down actually produces a video with sound on it.
///
/// Same two-layer shape as `ReplayStageTests`: the arithmetic is pinned on its own, because it
/// is the half that can be quietly wrong on a clip length nobody happened to try, and then the
/// AVFoundation half is checked against a synthetic movie and a synthetic tone — both made on
/// the spot, because a claim about an exported file is only worth having if something actually
/// exported one.
@Suite struct ReplayClipSoundtrackTests {

    // MARK: - The schedule

    /// A track longer than the clip is simply cut off at the clip's end: one piece, from the
    /// top of the file, no loop.
    @Test func aLongTrackIsTrimmedToTheClip() throws {
        let plan = try #require(ReplayClipSoundtrack.schedule(trackS: 210, clipS: 34.5))
        #expect(plan.pieces == 1)
        #expect(!plan.isLooped)
        #expect(plan.inserts[0] == ReplayClipSoundtrack.Insert(sourceStartS: 0, durationS: 34.5,
                                                               atS: 0))
        #expect(abs(plan.totalS - 34.5) < 0.001)
    }

    /// A track shorter than the clip goes round until the clip is full, and the last time round
    /// is cut wherever it lands — which is what makes the total exactly the clip's length
    /// rather than the next multiple of the track's.
    @Test func aShortTrackLoopsAndTheLastCopyIsCut() throws {
        let plan = try #require(ReplayClipSoundtrack.schedule(trackS: 8, clipS: 25))
        #expect(plan.isLooped)
        #expect(plan.pieces == 4)
        #expect(plan.inserts.map(\.durationS) == [8, 8, 8, 1])
        #expect(plan.inserts.map(\.atS) == [0, 8, 16, 24])
        // Every copy starts at the top of the file: a loop that started mid-phrase would be a
        // different edit each time round.
        #expect(plan.inserts.allSatisfy { $0.sourceStartS == 0 })
        #expect(abs(plan.totalS - 25) < 0.001)
    }

    /// Back to back with no gaps and no overlaps — the property that makes the loop seamless,
    /// checked as a property rather than on one example.
    @Test func thePiecesTileTheClipExactly() throws {
        for (trackS, clipS) in [(3.0, 10.0), (7.5, 34.7), (60.0, 25.0), (1.0, 12.0),
                                (13.3, 13.3), (120.0, 600.0)] {
            let plan = try #require(ReplayClipSoundtrack.schedule(trackS: trackS, clipS: clipS))
            var cursor = 0.0
            for insert in plan.inserts {
                #expect(abs(insert.atS - cursor) < 0.0001)
                #expect(insert.durationS > 0)
                #expect(insert.durationS <= trackS + 0.0001)
                cursor += insert.durationS
            }
            #expect(abs(cursor - clipS) <= ReplayClipSoundtrack.shortestPieceS)
        }
    }

    /// A track exactly as long as the clip is neither looped nor trimmed — the boundary case
    /// between the two rules above, and the one where an off-by-a-hundredth would show up as a
    /// second insert of a few milliseconds.
    @Test func anExactFitIsOnePiece() throws {
        let plan = try #require(ReplayClipSoundtrack.schedule(trackS: 25, clipS: 25))
        #expect(plan.pieces == 1)
        #expect(plan.inserts[0].durationS == 25)
    }

    /// The guard: something under a second is a system sound somebody picked by accident, not
    /// music, and looping it forty times would be a stutter rather than a soundtrack. No
    /// schedule means the clip comes out silent and the sheet says so.
    @Test func anAbsurdlyShortFileIsRefused() {
        #expect(ReplayClipSoundtrack.schedule(trackS: 0.4, clipS: 25) == nil)
        #expect(ReplayClipSoundtrack.schedule(trackS: 0, clipS: 25) == nil)
        // And the other end of the same guard: a clip with no length has nothing to carry.
        #expect(ReplayClipSoundtrack.schedule(trackS: 180, clipS: 0) == nil)
        // A second exactly is the shortest thing that is allowed through.
        #expect(ReplayClipSoundtrack.schedule(trackS: 1, clipS: 25) != nil)
    }

    /// The ramps: the nominal 0.8 s / 1.5 s on any clip long enough to hold them, and never
    /// overlapping on one that is not.
    @Test func theFadesStayInsideTheClip() throws {
        let ordinary = try #require(ReplayClipSoundtrack.schedule(trackS: 200, clipS: 25))
        #expect(ordinary.fadeInS == ReplayClipSoundtrack.fadeInS)
        #expect(ordinary.fadeOutS == ReplayClipSoundtrack.fadeOutS)
        // The fade out ends on the last frame, not after it.
        #expect(ordinary.clipS - ordinary.fadeOutS > ordinary.fadeInS)

        // A clip shorter than the two ramps put together: both shrink, in proportion, and a
        // fifth of the clip is still at full volume between them.
        for clipS in [0.5, 1.0, 2.0, 2.3, 3.0] {
            let short = try #require(ReplayClipSoundtrack.schedule(trackS: 60, clipS: clipS))
            #expect(short.fadeInS > 0)
            #expect(short.fadeOutS > 0)
            #expect(short.fadeInS + short.fadeOutS <= clipS * 0.8 + 0.0001)
            #expect(short.clipS - short.fadeOutS >= short.fadeInS)
            // The head ramp is never longer than the tail ramp: the music has to be audible
            // under the title card.
            #expect(short.fadeInS <= short.fadeOutS)
        }
    }

    // MARK: - A real mux, on a real movie

    /// The claim the arithmetic above is making, checked against a file something actually
    /// wrote.
    ///
    /// ReplayKit records nothing in the Simulator (`ReplayRecorder`), so a *screen* recording
    /// with music on it is device-only. The export is not: `AVAssetWriter` makes a movie and
    /// `AVAudioFile` makes a tone, and "the finished clip has exactly one audio track and it is
    /// as long as the video" is then a checkable claim rather than something only a phone can
    /// settle. **What still needs a device** is whether it sounds right — the fades, the loop
    /// seam, and whether the music sits under a clip at all.
    @Test func muxingATrackUnderASyntheticMovieProducesOneAudioTrack() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.mp4")
        let size = CGSize(width: 320, height: 640)
        try await makeMovie(at: source, size: size, frames: 60)
        let clipS = try await AVURLAsset(url: source).load(.duration).seconds

        // Deliberately shorter than the clip, so the export exercises the loop rather than a
        // single trimmed insert.
        let music = directory.appendingPathComponent("tone.m4a")
        try makeTone(at: music, seconds: 1.2)

        let output = directory.appendingPathComponent("with-music.mp4")
        _ = try await ReplayClipCropper.export(source, crop: nil, music: music, output: output)

        let clip = AVURLAsset(url: output)
        let audio = try await clip.loadTracks(withMediaType: .audio)
        #expect(audio.count == 1)
        let video = try await clip.loadTracks(withMediaType: .video)
        #expect(video.count == 1)
        // As long as the clip, give or take the AAC encoder's own padding — the point is that
        // the loop filled the whole thing rather than stopping after one copy.
        let audioS = try await #require(audio.first).load(.timeRange).duration.seconds
        #expect(abs(audioS - clipS) < 0.25)
        #expect(audioS > 1.2 * 1.5)
        // Nothing was resized: "Full screen with music" is a mux, not a crop.
        let natural = try await #require(video.first).load(.naturalSize)
        #expect(natural == size)
    }

    /// Music and a crop in the same pass — the case a rider who picks 9:16 *and* a track gets,
    /// and the one where the two halves of the export could disagree about which asset they are
    /// composing.
    @Test func aCroppedClipCanCarryMusicToo() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.mp4")
        let size = CGSize(width: 320, height: 640)
        try await makeMovie(at: source, size: size, frames: 60)

        let music = directory.appendingPathComponent("tone.m4a")
        try makeTone(at: music, seconds: 4)

        let crop = ReplayStage.crop(stage: ReplayStage.rect(in: size, framing: .square),
                                    screenPoints: size, videoPixels: size)
        let output = directory.appendingPathComponent("square-with-music.mp4")
        _ = try await ReplayClipCropper.export(source, crop: crop, music: music, output: output)

        let clip = AVURLAsset(url: output)
        #expect(try await clip.loadTracks(withMediaType: .audio).count == 1)
        let video = try await #require(try await clip.loadTracks(withMediaType: .video).first)
        #expect(try await video.load(.naturalSize) == crop.size)
    }

    /// A file with no sound in it costs the rider the music, not the clip. The recording has
    /// just taken as long to make as it lasts; throwing it away over a bad pick would be the
    /// wrong trade every time.
    @Test func aMusicFileWithNoAudioLeavesTheClipSilent() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.mp4")
        try await makeMovie(at: source, size: CGSize(width: 320, height: 640), frames: 30)
        let notMusic = directory.appendingPathComponent("notes.txt")
        try Data("this is not a song".utf8).write(to: notMusic)

        let output = directory.appendingPathComponent("silent.mp4")
        _ = try await ReplayClipCropper.export(source, crop: nil, music: notMusic,
                                               output: output)
        let clip = AVURLAsset(url: output)
        #expect(try await clip.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await clip.loadTracks(withMediaType: .video).count == 1)
    }

    // MARK: - Helpers

    private func scratch() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wingfoil-music-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A few frames of flat colour at a known size — the same synthetic movie `ReplayStageTests`
    /// crops, and for the same reason.
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
                memset(base, Int32(40 + frame % 200),
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

    /// A 440 Hz tone in an `.m4a`, which is the shape of the thing a rider hands over: AAC in
    /// an MPEG-4 container, one of the types the document picker offers. `AVAudioFile` does the
    /// encoding, so this is a handful of lines rather than a second asset writer.
    private func makeTone(at url: URL, seconds: Double) throws {
        let rate = 44_100.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
        ])
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.floatChannelData)[0]
        for frame in 0..<Int(frames) {
            samples[frame] = 0.4 * Float(sin(2 * Double.pi * 440 * Double(frame) / rate))
        }
        try file.write(from: buffer)
    }
}
