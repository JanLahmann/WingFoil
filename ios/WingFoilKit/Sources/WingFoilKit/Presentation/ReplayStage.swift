import CoreGraphics
import Foundation

/// The shape of the finished clip.
///
/// **Why a clip needs this and the share card's `Shape` was not enough.** They are the same
/// decision about two different artefacts, and the platforms want different numbers: a card is
/// a still in a feed, where 1080 × 1350 (4:5) is the tallest thing that is not cropped, and a
/// clip is a *video*, where the tall format is 9:16 because that is the shape of a phone held
/// upright. Reusing the card's 4:5 for a clip would produce a video with grey bars down the
/// sides in every app a rider posts one to. So the vocabulary is the card's — portrait, square,
/// landscape, in that order, with the same words on the picker — and the ratios are video's.
///
/// **Full screen is not an aspect and is the safety net.** ReplayKit records the glass, so
/// "full screen" is the one choice that needs no crop at all: whatever comes out of the
/// recorder is the clip. It is also what a failed crop falls back to.
public enum ReplayFraming: String, CaseIterable, Sendable, Identifiable, Codable {
    /// 9:16 — a phone held upright, which is what a story or a reel is.
    case portrait
    /// 1:1 — the shape that is never cropped anywhere.
    case square
    /// 16:9 — a chat preview, a forum post, a desktop screen.
    case landscape
    /// Whatever the glass is. No crop, no letterbox, no post-processing.
    case fullScreen

    public var id: String { rawValue }

    /// Width ÷ height, or nil for "the screen's own".
    public var aspect: Double? {
        switch self {
        case .portrait: 9.0 / 16
        case .square: 1
        case .landscape: 16.0 / 9
        case .fullScreen: nil
        }
    }

    public var label: String {
        switch self {
        case .portrait: "9:16"
        case .square: "1:1"
        case .landscape: "16:9"
        case .fullScreen: "Full"
        }
    }

    /// The word, for the sentence under the picker.
    public var name: String {
        switch self {
        case .portrait: "Portrait"
        case .square: "Square"
        case .landscape: "Landscape"
        case .fullScreen: "Full screen"
        }
    }

    /// True when the frame is wider than it is tall — which is what the cards ask before
    /// deciding whether the track goes beside the numbers or above them. Asked of the framing
    /// rather than tested for a case, exactly as `ShareCardStats.Shape.isWide` is, so a fifth
    /// ratio lands in the right layout for free.
    ///
    /// `fullScreen` answers for the screen it is on, which is why it takes one.
    public func isWide(on screen: CGSize) -> Bool {
        guard let aspect else { return screen.width > screen.height }
        return aspect > 1
    }
}

/// Where on the glass the clip actually is.
///
/// **Why the framing is staged live rather than only cropped afterwards.** ReplayKit captures
/// the whole screen — there is no API to record part of it — so a framed clip has to be cut out
/// in post either way. But a rider who could not *see* the frame while it recorded would be
/// composing blind: the pinch that put the jibe corner in the middle of the glass would put it
/// half outside a 9:16 clip, and he would only find out afterwards. So the cinema view draws
/// the replay inside the chosen box and paints the rest of the screen out, and the crop that
/// follows is exactly the box he was looking at.
///
/// Pure geometry, because it is the sort of arithmetic that is wrong by a scale factor on one
/// device family and right everywhere else — see `crop`.
public enum ReplayStage {

    /// The biggest box of the wanted ratio that fits the glass, centred.
    ///
    /// Centred rather than top-aligned because the map fills the box and its interesting part
    /// is wherever the rider pinched it to; and because a letterbox that is symmetrical reads
    /// as a frame while one that is all at the bottom reads as a layout mistake.
    public static func rect(in screen: CGSize, framing: ReplayFraming) -> CGRect {
        let whole = CGRect(origin: .zero, size: screen)
        guard screen.width > 0, screen.height > 0, let aspect = framing.aspect, aspect > 0
        else { return whole }
        // Fit by whichever dimension binds. A 9:16 box on a 19.5:9 phone is limited by the
        // width; the same box on an iPad is limited by the height.
        let byWidth = CGSize(width: screen.width, height: screen.width / aspect)
        let size = byWidth.height <= screen.height
            ? byWidth
            : CGSize(width: screen.height * aspect, height: screen.height)
        return CGRect(x: (screen.width - size.width) / 2,
                      y: (screen.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// The same box in the recorded file's own pixels.
    ///
    /// **Proportional, not `× scale`.** The obvious version multiplies points by
    /// `UIScreen.scale`, and it is wrong on every device where the rendered framebuffer is not
    /// the native panel — the "display zoom" accessibility setting and the 3× phones that
    /// downsample both break it, and ReplayKit hands back the *file's* dimensions rather than
    /// the panel's. Mapping fractions of the screen onto fractions of the video is right
    /// whatever the two happen to be, and degrades to the same answer when they agree.
    ///
    /// **The stage rect must be measured in the same space the recorder captures**, which is
    /// the whole glass including the safe areas. The cinema view measures it on a container
    /// that ignores the safe area for exactly that reason; a rect measured inside the insets
    /// would be offset by the status bar's height and the clip would be cropped a few pixels
    /// low on every phone with a notch.
    ///
    /// **Even numbers.** H.264 encodes in 2 × 2 chroma blocks and an odd render size is
    /// rejected or silently rounded by `AVAssetExportSession`, so the result is snapped
    /// outward to even pixels and then clamped back inside the frame.
    public static func crop(stage: CGRect, screenPoints: CGSize,
                            videoPixels: CGSize) -> CGRect {
        let whole = CGRect(origin: .zero, size: videoPixels)
        guard screenPoints.width > 0, screenPoints.height > 0,
              videoPixels.width > 0, videoPixels.height > 0, !stage.isEmpty
        else { return whole }
        let sx = videoPixels.width / screenPoints.width
        let sy = videoPixels.height / screenPoints.height
        // The frame itself may be odd (a downsampled capture is 1179 px wide), and the crop
        // may not exceed it — so the ceiling is the *even* frame, one pixel of which is then
        // never in any clip. Losing a single column beats handing the encoder a size it
        // silently rounds behind our back.
        let maxWidth = even(videoPixels.width, up: false)
        let maxHeight = even(videoPixels.height, up: false)
        let width = min(even(stage.width * sx, up: true), maxWidth)
        let height = min(even(stage.height * sy, up: true), maxHeight)
        // Rounding outward can push the box past the last pixel; slide it back rather than
        // shrinking it, so a full-width stage stays full width.
        let x = max(0, min(even(stage.minX * sx, up: false), maxWidth - width))
        let y = max(0, min(even(stage.minY * sy, up: false), maxHeight - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Whether the crop is worth doing at all: a box that is the whole frame already is the
    /// clip, and running an export over it would cost a re-encode and buy nothing.
    ///
    /// A pixel of tolerance, because `crop` rounds to even and a frame with an odd dimension
    /// therefore comes back one short of itself — which is not a crop anybody asked for.
    public static func needsCrop(_ crop: CGRect, videoPixels: CGSize) -> Bool {
        crop.minX > 1 || crop.minY > 1
            || videoPixels.width - crop.width > 1 || videoPixels.height - crop.height > 1
    }

    private static func even(_ value: CGFloat, up: Bool) -> CGFloat {
        let halves = up ? (value / 2).rounded(.up) : (value / 2).rounded(.down)
        return max(0, halves * 2)
    }
}
