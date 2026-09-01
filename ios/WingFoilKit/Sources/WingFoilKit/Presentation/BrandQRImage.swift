import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The bitmap behind every QR the app exports — the code itself, and the brand mark in the
/// middle of it.
///
/// Lives in the kit rather than beside `BrandQRCode` (the SwiftUI view) for one reason: a
/// QR with a hole punched in it is a QR that can stop scanning, and "it looked fine in the
/// preview" is not evidence. Here it is a pure function over `CGImage`, which
/// `BrandQRTests` can render at every size the app exports at and *decode back* with
/// `CIDetector`. The view is then layout and caching and nothing else.
///
/// **Why a mark at all.** The code travels as a 96 px square in the corner of a PNG in
/// somebody else's chat thread. Unbranded it is anonymous — a grey square a reader has no
/// reason to trust or to point a camera at; with the app's own icon in it, it is visibly
/// *this* app's link, which is the whole job of a footer that exists to be followed.
///
/// **Why it is safe, and why five modules.** A QR carries Reed–Solomon parity, and level M
/// restores about 15 % of the symbol's codewords. The white plate is `markModules` (5)
/// across the centre of a 25-module version-2 symbol: 25 of its 625 cells, **4 % of the
/// symbol's area** — a quarter of the budget, leaving the rest for the real enemy, which is
/// a chat app's recompression of a photograph of a phone screen.
///
/// The number is not a guess. Decoding the rendered code back at every export size, as PNG
/// and through JPEG q50 and q35, the cliff is sharp: up to 5.75 modules every size decodes,
/// at 6 modules a fifth of them stop. Two things go at once there — the version-2
/// **alignment pattern** starts at module 16, and a plate wide enough to reach it takes away
/// the landmark a decoder needs *before* parity can help it, which is why the failure is
/// abrupt rather than gradual. Five sits a clear module inside that edge, and it is **odd**,
/// which matters: the symbol's centre is the middle of a module, so only an odd-width plate
/// lands on module boundaries and costs whole cells rather than half-lit ones. The same
/// number, for the same reasons, is drawn by the web card (`web/js/sharecard.js`).
public enum BrandQRImage {

    /// Pixels per module in the generated bitmap. Enough that the symbol is larger than any
    /// size it is ever drawn at, so the only resampling left is a downscale — which cannot
    /// turn one module into two — and large enough that the mark is composited into real
    /// artwork rather than into a 30 px thumbnail.
    static let modulePx = 24

    /// The side of the mark's white plate, **in modules**. See the type's note for why 5.
    static let markModules = 5.0

    /// The mark's own side inside the plate, in modules — three quarters of it, so the plate
    /// keeps a white rim about two thirds of a module wide. That rim is what makes the mark
    /// read as a plate rather than as a blot, and it is also the local quiet zone that keeps
    /// the artwork's dark edge from merging with the dark modules it abuts.
    static let markInnerModules = markModules * 0.75

    /// The QR for `string`, with `mark` (the app icon) on a rounded white plate at its
    /// centre. `mark` nil draws the bare code — the same bitmap the app shipped before, and
    /// the control the decode tests measure the marked one against.
    ///
    /// nil only if Core Image refuses to generate, which for a constant ASCII URL it does
    /// not; every caller draws nothing rather than a hole in that case.
    public static func make(_ string: String, mark: CGImage?) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // "M" — 15 % recovery. "H" would survive more damage but costs two versions of extra
        // modules, and on a 96 px code smaller modules is exactly the failure mode we are
        // avoiding. The card is a clean digital image, not a sticker on a wet boom.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        // The generator emits one *pixel* per module — 27 × 27 for this payload: a
        // version-2 symbol (25) plus the single module of quiet zone it adds. Scaled up with
        // the default (bilinear) sampling every module edge becomes a grey ramp, and after a
        // chat app has re-compressed the card those ramps are what a decoder has to
        // threshold. `samplingNearest()` before the transform keeps the modules square, and
        // the factor is a whole number so no module lands on a half pixel.
        let scale = CGFloat(modulePx)
        let crisp = output
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let code = CIContext().createCGImage(crisp, from: crisp.extent) else { return nil }
        guard let mark else { return code }
        return branded(code, mark: mark)
    }

    /// The plate and the mark, drawn into a copy of `code`.
    ///
    /// The centre of the bitmap *is* the centre of the symbol: the generator's quiet zone is
    /// one module on all four sides, so the padding cancels and no offset arithmetic is
    /// needed. Everything is measured in modules from `modulePx`, so the plate lands on
    /// module boundaries and a decoder sees whole cells lost rather than half-lit ones.
    private static func branded(_ code: CGImage, mark: CGImage) -> CGImage? {
        let side = code.width
        guard let ctx = CGContext(data: nil, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let full = CGRect(x: 0, y: 0, width: side, height: side)
        // Nearest for the code — the modules are already the size they will be drawn at, and
        // anything smoother would put a ramp back on every edge this method exists to keep.
        ctx.interpolationQuality = .none
        ctx.draw(code, in: full)

        let module = CGFloat(modulePx)
        let plate = CGRect(x: 0, y: 0, width: markModules * module, height: markModules * module)
            .offsetBy(dx: (CGFloat(side) - markModules * module) / 2,
                      dy: (CGFloat(side) - markModules * module) / 2)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(roundedPath(plate, radius: plate.width * 0.22))
        ctx.fillPath()

        let inner = plate.insetBy(dx: (markModules - markInnerModules) * module / 2,
                                  dy: (markModules - markInnerModules) * module / 2)
        ctx.saveGState()
        // The artwork's own corners are rounded, but it is a square PNG and an export scale
        // can leave a hairline of its navy backing outside them; the clip makes that
        // impossible rather than unlikely.
        ctx.addPath(roundedPath(inner, radius: inner.width * 0.24))
        ctx.clip()
        // High quality *here* only: the mark is real artwork being reduced, and it is inside
        // the plate, so smoothing it cannot soften a module edge.
        ctx.interpolationQuality = .high
        ctx.draw(mark, in: inner)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}
