import AVFoundation
import Foundation

/// Fitting a piece of music the rider chose onto a clip whose length he did not choose.
///
/// **Why the clip is the master and the track is not.** The length of a clip comes out of
/// `ReplayPacing` — a target, a session, a title card and however many photo pauses — and it is
/// never a round number. A track is whatever the rider handed over: three and a half minutes of
/// a song, or an eight-second loop he made himself. So the schedule below is always *exactly*
/// the clip long: a longer track is cut off, a shorter one is laid down again from its start
/// until the clip is full, and the last copy is cut mid-phrase. Nobody is going to notice the
/// splice under a fade-out.
///
/// **Why the fades are not symmetrical.** The clip opens on a title card and the music has to be
/// there when it does, so the fade in is short (0.8 s — enough not to click, short enough that
/// the first bar is audible under the title). The clip ends on a closing card that stays up for
/// four seconds, and a soundtrack that stopped dead on the last frame would sound like the file
/// ran out; 1.5 s is the shortest ramp that reads as an ending rather than a cut.
///
/// **Why the schedule is pure and separate from the muxing.** The arithmetic — how many copies,
/// where each one is cut, where the two ramps go — is the part that can be wrong in a way no
/// listening test would catch on the one clip it was tried on, and it is the part a Mac can
/// check exhaustively. `ReplayClipSoundtrackTests` pins it. The AVFoundation half below is then
/// small enough to read.
///
/// **The seam for bundled tracks.** Everything here takes a file URL and knows nothing about
/// where it came from. A future "pick one of ours" row on the setup sheet is a second way of
/// producing that URL — a track shipped in the app bundle — and nothing in this file changes
/// when it arrives. What is missing is not code but licensed audio: a track shipped inside an
/// app that riders then post to social networks needs a licence that covers exactly that, and
/// music from a commercial streaming service can never be it (the files are DRM'd, the APIs
/// return stream handles rather than samples, and the terms forbid redistribution outright).
public enum ReplayClipSoundtrack {

    /// Seconds of ramp at the head of the clip.
    public static let fadeInS: Double = 0.8
    /// Seconds of ramp at its tail. Longer than the head — see the type comment.
    public static let fadeOutS: Double = 1.5
    /// The shortest file worth looping. Below a second the loop is a stutter rather than a
    /// soundtrack, and something that short is nearly always a picked-by-accident system sound.
    public static let shortestTrackS: Double = 1
    /// A piece shorter than this is not laid down at all: the clip ends a few hundredths early,
    /// which is inaudible, and the alternative is a zero-length insert AVFoundation would
    /// rather not have.
    static let shortestPieceS: Double = 0.05

    /// One copy, or part of one, of the track on the clip's clock.
    public struct Insert: Equatable, Sendable {
        /// Where in the music file this piece begins. Zero for every copy but a trim.
        public let sourceStartS: Double
        public let durationS: Double
        /// Where the piece lands on the finished clip.
        public let atS: Double
    }

    /// What the muxer lays down, and what the tests assert against.
    public struct Schedule: Equatable, Sendable {
        public let inserts: [Insert]
        /// The ramp `0 → 1` over `[0, fadeInS]`.
        public let fadeInS: Double
        /// The ramp `1 → 0` over `[clipS - fadeOutS, clipS]`.
        public let fadeOutS: Double
        public let clipS: Double

        /// How many pieces the track was cut into — 1 when it was long enough to cover the
        /// clip on its own, and the number of times it goes round otherwise.
        public var pieces: Int { inserts.count }
        /// Seconds of music, which is the clip's own length to within `shortestPieceS`.
        public var totalS: Double { inserts.reduce(0) { $0 + $1.durationS } }
        /// True when the track had to go round more than once.
        public var isLooped: Bool { inserts.count > 1 }
    }

    /// Works out how a `trackS`-long file covers a `clipS`-long clip.
    ///
    /// Returns nil for the two cases where there is no soundtrack to make rather than a bad
    /// one: a clip with no length, and a file too short to be music (`shortestTrackS`). The
    /// caller treats nil as "no music", which is what the rider gets and what he can hear.
    public static func schedule(trackS: Double, clipS: Double) -> Schedule? {
        guard clipS > shortestPieceS, trackS >= shortestTrackS else { return nil }

        // Copies from the top until the clip is full, the last one cut wherever it lands. The
        // count is bounded by the clip's length in seconds (nothing shorter than a second is
        // looped at all), so a pathological one-second file on a long clip costs a few hundred
        // inserts and nothing else — AVFoundation composes them without resampling.
        var inserts: [Insert] = []
        var placed = 0.0
        while clipS - placed > shortestPieceS {
            let piece = min(trackS, clipS - placed)
            inserts.append(Insert(sourceStartS: 0, durationS: piece, atS: placed))
            placed += piece
        }

        // Both ramps, shrunk together on a clip too short to hold them. The 0.8 leaves a fifth
        // of even the shortest clip at full volume, so a fade in never runs straight into a
        // fade out with no music in between.
        var fadeIn = min(fadeInS, clipS)
        var fadeOut = min(fadeOutS, clipS)
        let budget = clipS * 0.8
        if fadeIn + fadeOut > budget {
            let squeeze = budget / (fadeIn + fadeOut)
            fadeIn *= squeeze
            fadeOut *= squeeze
        }

        return Schedule(inserts: inserts, fadeInS: fadeIn, fadeOutS: fadeOut, clipS: clipS)
    }

    // MARK: - Laying it down

    /// Copies the schedule's pieces of `music` into `composition` and returns the mix that
    /// fades them.
    ///
    /// Returns nil when there is nothing to lay down — a file with no sound in it, or one too
    /// short to loop — because a clip with no music is a perfectly good clip and losing the
    /// recording over a bad pick would be the wrong trade. The caller says so; see
    /// `ReplayClipCropper.export`.
    static func lay(_ music: URL, over composition: AVMutableComposition,
                    clip: CMTime) async throws -> AVAudioMix? {
        let asset = AVURLAsset(url: music)
        guard let source = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        let trackS = try await asset.load(.duration).seconds
        guard let plan = schedule(trackS: trackS, clipS: clip.seconds),
              let track = composition.addMutableTrack(withMediaType: .audio,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        for insert in plan.inserts {
            let range = CMTimeRange(start: Self.time(insert.sourceStartS),
                                    duration: Self.time(insert.durationS))
            try track.insertTimeRange(range, of: source, at: Self.time(insert.atS))
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1,
                                 timeRange: CMTimeRange(start: .zero,
                                                        duration: Self.time(plan.fadeInS)))
        parameters.setVolumeRamp(
            fromStartVolume: 1, toEndVolume: 0,
            timeRange: CMTimeRange(start: Self.time(plan.clipS - plan.fadeOutS),
                                   duration: Self.time(plan.fadeOutS)))
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    /// Seconds as a `CMTime` on a 600-tick scale — the standard video timescale, which divides
    /// evenly by every frame rate a phone records at, so an insert boundary never lands
    /// half-way through a frame.
    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
