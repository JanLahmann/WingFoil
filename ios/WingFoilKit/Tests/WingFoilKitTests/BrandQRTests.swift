import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WingFoilKit

/// The QR in the corner of every card and every clip's last frame — decoded back.
///
/// A QR that does not scan is worse than no QR: the reader has already pointed a camera at
/// it, and nothing happens. That risk went up the day the brand mark was punched into the
/// middle of it, so this suite does the only check worth doing — render the code the way the
/// app exports it and read it back with the same Core Image detector a phone's camera app
/// uses, at every size the app draws it and after the JPEG recompression a chat app applies
/// on the way.
///
/// Every marked case is paired with the **unmarked** control at the same size. A failure on
/// both is the size being too small; a failure on the marked one alone is the mark being too
/// big, which is the thing this suite exists to catch.
@Suite("Brand QR")
struct BrandQRTests {

    /// The sizes the app actually exports the plate at, in pixels: 96 is the share card's
    /// 32 pt at `ShareCardView.renderScale` 3, and the rest bracket the replay outro's
    /// 38 pt × the 0.55…1.1 fit scale the clip renderer picks from the frame it is given.
    static let exportSizes = [70, 84, 96, 114, 126]

    /// A stand-in for the app icon that is far harsher than the icon: solid black, edge to
    /// edge of the plate's inner box. The real artwork is navy with light strokes in it, so
    /// anything that survives this survives that — and the test does not have to carry a
    /// copy of the app target's asset catalogue to say something true about it.
    static func blackMark(side: Int = 256) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }

    /// The bitmap as `BrandQRCode` puts it on a card: nearest-neighbour down to the export
    /// size, on the white plate whose ~11 % padding is the four modules of quiet zone the
    /// spec wants and the generator does not supply.
    static func exported(_ code: CGImage, size: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.interpolationQuality = .none
        let pad = Double(size) * 0.11
        ctx.draw(code, in: CGRect(x: pad, y: pad,
                                  width: Double(size) - pad * 2, height: Double(size) - pad * 2))
        return ctx.makeImage()!
    }

    /// Through a chat app: JPEG at quality 50, which is roughly what a picture arrives at
    /// after WhatsApp has had it. PNG is what the app exports; JPEG is what the reader's
    /// camera is usually pointed at.
    static func jpegRoundTrip(_ image: CGImage, quality: Double = 0.5) -> CGImage? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality:
                                                    quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// What the code says, read back. nil when nothing decoded.
    ///
    /// The 4× nearest upscale before detection is not a thumb on the scale: `CIDetector`
    /// wants several pixels per module, and a phone camera pointed at a screen gives it
    /// them. Sampling nearest keeps the module edges hard, so the upscale adds pixels and
    /// no information.
    static func decode(_ image: CGImage) -> String? {
        let big = CIImage(cgImage: image)
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: big) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }

    @Test("the bare code still decodes at every export size")
    func unmarkedDecodes() throws {
        let code = try #require(BrandQRImage.make(Branding.siteURL, mark: nil))
        for size in Self.exportSizes {
            #expect(Self.decode(Self.exported(code, size: size)) == Branding.siteURL,
                    "unmarked \(size) px")
        }
    }

    @Test("the marked code decodes at every export size")
    func markedDecodes() throws {
        let code = try #require(BrandQRImage.make(Branding.siteURL, mark: Self.blackMark()))
        for size in Self.exportSizes {
            #expect(Self.decode(Self.exported(code, size: size)) == Branding.siteURL,
                    "marked \(size) px")
        }
    }

    @Test("the marked code survives a chat app's JPEG")
    func markedSurvivesJpeg() throws {
        let code = try #require(BrandQRImage.make(Branding.siteURL, mark: Self.blackMark()))
        for size in Self.exportSizes {
            let jpeg = try #require(Self.jpegRoundTrip(Self.exported(code, size: size)))
            #expect(Self.decode(jpeg) == Branding.siteURL, "marked \(size) px through JPEG q50")
        }
    }

    /// The size budget, asserted as arithmetic rather than trusted to a comment.
    ///
    /// The plate is measured against the **symbol** (25 modules), not against the padded
    /// plate the view draws, because the symbol is what carries the parity that has to
    /// absorb it. Level M restores ~15 %; the contract is to stay under 10 %.
    @Test("the mark covers less than a tenth of the symbol")
    func markStaysInsideTheErrorBudget() {
        let symbolModules = 25.0
        let share = BrandQRImage.markModules / symbolModules
        let areaShare = share * share
        #expect(areaShare < 0.10)
        #expect(areaShare > 0.03, "a mark too small to read is not worth the parity")
        // The measured cliff (see `BrandQRImage`): every export size decodes up to 5.75
        // modules and a fifth of them stop at 6. Pinned as a number so that growing the mark
        // fails here, with the reason, rather than in a rider's camera app.
        #expect(BrandQRImage.markModules <= 5.75)
        // Odd, so the plate lands on module boundaries: the symbol's centre is the middle of
        // a module, and an even-width plate would leave a rim of half-covered cells for a
        // decoder to threshold.
        #expect(BrandQRImage.markModules.truncatingRemainder(dividingBy: 2) == 1)
        // The version-2 alignment pattern occupies modules 16…20. A plate centred on 12.5
        // must stop before 16, or a decoder loses the landmark it needs *before* parity can
        // help it.
        #expect(12.5 + BrandQRImage.markModules / 2 <= 16.0)
    }

    /// The control the other tests need to mean anything: a mark big enough to eat the
    /// alignment pattern really does stop the code decoding, so a passing suite is evidence
    /// about the chosen size rather than about `CIDetector` being agreeable.
    @Test("an oversized mark breaks the code")
    func anOversizedMarkFails() throws {
        let code = try #require(BrandQRImage.make(Branding.siteURL, mark: nil))
        let side = code.width
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(code, in: CGRect(x: 0, y: 0, width: side, height: side))
        // 15 modules of the 25 — 36 % of the symbol's area, twice level M's whole budget.
        let plate = Double(BrandQRImage.modulePx) * 15
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: (Double(side) - plate) / 2, y: (Double(side) - plate) / 2,
                        width: plate, height: plate))
        let broken = ctx.makeImage()!
        #expect(Self.decode(Self.exported(broken, size: 96)) != Branding.siteURL)
    }
}
