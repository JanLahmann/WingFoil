// A QR code as a static SVG, drawn once at build time (rider review S13, 23 Oct 2026).
//
//     swift web/tools/make_qr.swift <url> <out.svg>
//
// The site shows a QR where a laptop reader needs to get a link onto the phone: the
// TestFlight link on /start/ (web/img/qr-testflight.svg). The URL is a constant, so a QR
// library in the page would be a dependency to draw a constant, and an external QR host
// would hand every visitor to a third party. This uses Apple's own CIQRCodeGenerator, the
// generator BrandQRImage uses for the share card, at correction level M, so it needs a Mac
// and nothing else. The SVG is one path of unit squares in a viewBox of whole modules,
// a four-module quiet zone included, with `shape-rendering="crispEdges"`, so it scales without blur.
// The URL is written into the file's first comment, and web/tools/verify_links.py holds
// that comment to the link the page prints beside it.

import CoreImage
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let message = args[1].data(using: .utf8) else {
    FileHandle.standardError.write("usage: swift make_qr.swift <url> <out.svg>\n".data(using: .utf8)!)
    exit(2)
}
let url = args[1], out = args[2]

let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(message, forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
let image = filter.outputImage!
let side = Int(image.extent.width)

let context = CIContext(options: [.useSoftwareRenderer: true])
var pixels = [UInt8](repeating: 0, count: side * side)
context.render(image, toBitmap: &pixels, rowBytes: side, bounds: image.extent,
               format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())

// The generator leaves one light module around the symbol; a decoder wants four, so the
// SVG adds three on every side. `dark[y][x]` is the symbol as the SVG draws it, top row first.
let pad = 3, full = side + 2 * pad
var dark = [[Bool]](repeating: [Bool](repeating: false, count: full), count: full)
for y in 0..<side { for x in 0..<side { dark[y + pad][x + pad] = pixels[y * side + x] < 128 } }

var path = ""
for y in 0..<full {
    var x = 0
    while x < full {
        if dark[y][x] {
            var run = 1
            while x + run < full && dark[y][x + run] { run += 1 }
            path += "M\(x) \(y)h\(run)v1h-\(run)z"
            x += run
        } else {
            x += 1
        }
    }
}

// Read it back before writing it: the matrix the SVG draws, at 8 px a module, through
// CoreImage's own QR detector. A transcription slip fails here, not on a rider's phone.
let scale = 8, w = full * scale
var raster = [UInt8](repeating: 255, count: w * w)
for y in 0..<w { for x in 0..<w where dark[y / scale][x / scale] { raster[y * w + x] = 0 } }
let provider = CGDataProvider(data: Data(raster) as CFData)!
let cg = CGImage(width: w, height: w, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: nil)!
let read = (detector.features(in: CIImage(cgImage: cg)).first as? CIQRCodeFeature)?.messageString
guard read == url else {
    FileHandle.standardError.write("read back \(read ?? "nothing"), not \(url)\n".data(using: .utf8)!)
    exit(1)
}

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(full) \(full)" shape-rendering="crispEdges">\
<!-- \(url) — written by web/tools/make_qr.swift; do not edit -->\
<rect width="\(full)" height="\(full)" fill="#fff"/><path fill="#000" d="\(path)"/></svg>

"""
try! svg.write(toFile: out, atomically: true, encoding: .utf8)
print("wrote \(out): \(full) x \(full) modules, read back as \(url)")
