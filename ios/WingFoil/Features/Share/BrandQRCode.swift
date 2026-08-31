import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import WingFoilKit

/// The QR code in the corner of everything the app exports: a card, and the closing frame of
/// a clip.
///
/// **Why a QR at all.** The card is the promotion channel — it leaves the phone as a PNG and
/// is read on somebody else's screen, usually in a chat, usually by a rider who has never
/// heard of the app. `cleanjibe.org` printed in 10 pt is a thing he has to retype; a QR is a
/// thing his own phone's camera already offers to open. The footer therefore carries both:
/// the address for a reader who is looking at the picture, the code for one who is looking at
/// it *through a camera*.
///
/// **Why Core Image and not a package.** `CIQRCodeGenerator` is in the OS, it is stable, and
/// the payload is one short constant URL. A dependency for twenty-one characters would be a
/// dependency to audit at every Xcode bump.
///
/// **Why the rendering fusses.** A QR that does not scan is worse than no QR, and two things
/// break one at this size:
///
/// - **Resampling.** The generator emits one *pixel* per module — a 25 × 25 image. Scaled up
///   with the default (bilinear) sampling, every module edge becomes a grey ramp, and after a
///   chat app has re-compressed the card those ramps are what a decoder has to threshold.
///   `samplingNearest()` before the transform keeps the modules square, and the transform is
///   a whole-number factor so no module lands on a half pixel.
/// - **The quiet zone.** The spec wants four modules of blank around the symbol, and the
///   generator gives one. The white plate this view draws underneath supplies the rest, which
///   is also what makes a dark-on-light code possible on a card whose background is navy or
///   somebody's photo of a sunset — a decoder needs the light half to actually be light.
struct BrandQRCode: View {

    /// The payload. Defaults to the site, which is the only thing this is ever used for; a
    /// parameter because a session-specific deep link is the obvious next want.
    var url: String = Branding.siteURL

    /// The drawn size of the whole plate, in points. At the card's 3× export 32 pt is a
    /// 96 px code, which is the size a phone camera picks up from a photographed screen.
    var size: CGFloat

    /// Corner rounding and the white margin, as fractions of `size`, so one number scales the
    /// whole thing. The padding is ~11 %, which is four modules of a version-2 symbol.
    private var padding: CGFloat { size * 0.11 }
    private var corner: CGFloat { size * 0.13 }

    var body: some View {
        Group {
            if let image = Self.render(url) {
                Image(uiImage: image)
                    // Nearest again on the way to the screen: `Image` would otherwise smooth
                    // the already-crisp bitmap back into ramps when it fits it to the frame.
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(padding)
            } else {
                // The generator cannot fail for a constant ASCII URL, but a footer with a
                // white hole in it would be a worse card than a footer without a code.
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .background(Color.white, in: .rect(cornerRadius: corner))
        .accessibilityLabel("QR code to \(Branding.site)")
    }

    // MARK: - The bitmap

    /// Cached because both card renderers redraw on every layout pass and the payload never
    /// changes: `ImageRenderer` alone would otherwise regenerate this once per exported shape.
    /// Main-actor state, which is where every `body` that asks for it already is.
    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor static func render(_ string: String) -> UIImage? {
        if let hit = cache[string] { return hit }
        guard let made = make(string) else { return nil }
        cache[string] = made
        return made
    }

    private static func make(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // "M" — 15 % recovery. "H" would survive more damage but costs two versions of extra
        // modules, and on a 96 px code smaller modules is exactly the failure mode we are
        // avoiding. The card is a clean digital image, not a sticker on a wet boom.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        // 24 px per module: enough that the symbol is already larger than any size it is
        // drawn at, so the only resampling left is a downscale, which cannot break a module.
        let upscale: CGFloat = 24
        let crisp = output
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: upscale, y: upscale))
        guard let cgImage = CIContext().createCGImage(crisp, from: crisp.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    ZStack {
        Brand.cardGradient
        HStack(spacing: 24) {
            BrandQRCode(size: 32)
            BrandQRCode(size: 64)
            BrandQRCode(size: 120)
        }
    }
    .ignoresSafeArea()
}
