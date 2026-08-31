import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import WingFoilKit

/// One of the rider's own photos, loaded and ready to be composited into a clip.
///
/// The pair `ReplayStoryboard` schedules on: an id to look the picture up by and the instant
/// the shutter fired. The kit does the placing; this does the reading.
struct ReplayPhoto: Identifiable, Sendable {
    /// `PhotosPickerItem.itemIdentifier` when the library gave one, and a synthesised id
    /// otherwise — the storyboard only needs it to be unique and stable for one run.
    let id: String
    let image: UIImage
    /// When it was taken, when the file could say. See `ReplayPhotoLoader.takenAt`.
    let takenAt: Date?

    /// What the storyboard schedules with — the picture itself is never handed to the kit.
    var entry: ReplayStoryboard.Photo {
        ReplayStoryboard.Photo(id: id, takenAt: takenAt)
    }
}

/// Turns the picker's opaque items into `ReplayPhoto`s: a downscaled image and a timestamp.
///
/// **Why `PhotosPicker` and not `PHAsset`.** The share composer already made this choice and
/// the reason is the same — `PhotosPicker` runs out of process, so there is no photo-library
/// permission prompt and the app never gains access to anything the rider did not hand it.
/// The cost is that the convenient answer (`PHAsset.creationDate`) is not available and the
/// date has to come out of the file's own metadata, which is what `takenAt` is for.
///
/// **Why the images are downscaled.** Six 48-megapixel photos decoded at full size is around
/// 1 GB of backing store, held for the length of a recording, on a phone that is also
/// encoding video. 2048 px on the long edge is more than a screen can show and a twentieth of
/// the memory, and `CGImageSourceCreateThumbnailAtIndex` decodes straight to that size rather
/// than decoding full-size and throwing most of it away.
enum ReplayPhotoLoader {

    /// Long edge of the decoded image, in pixels. Above a 3× phone screen's own long edge, so
    /// a photo composited full-screen is never upscaled.
    static let maxPixels = 2048

    /// The most the picker will let a rider choose — `ReplayStoryboard.Timing.maxPhotos`, so
    /// the limit the sheet enforces and the limit the schedule enforces are one number.
    static let maxCount = ReplayStoryboard.Timing.standard.maxPhotos

    /// Loads what the picker handed back, in the rider's own order.
    ///
    /// An item that cannot be read is dropped rather than failing the batch: one photo saved
    /// out of a chat app in a format `ImageIO` will not open must not cost the rider the other
    /// five. The sheet reports the difference between what was picked and what came back.
    static func load(_ items: [PhotosPickerItem]) async -> [ReplayPhoto] {
        var out: [ReplayPhoto] = []
        for (index, item) in items.prefix(maxCount).enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let id = item.itemIdentifier ?? "picked-\(index)"
            // `Task.detached` and not a bare call: `decode` is `nonisolated`, which means it
            // runs on whatever executor *calls* it — and the caller here is a view's `.task`,
            // i.e. the main actor. Six JPEGs decoded on the main actor is a visible stutter
            // in the sheet they are being picked in.
            let decoded = await Task.detached(priority: .userInitiated) {
                decode(data, id: id)
            }.value
            if let decoded { out.append(decoded) }
        }
        return out
    }

    /// Decode + metadata in one pass over one `CGImageSource`.
    ///
    /// `Data` in, `ReplayPhoto` out, no actor: the expensive half, hoisted off the main actor
    /// by its caller.
    nonisolated static func decode(_ data: Data, id: String) -> ReplayPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0,
                                                                options as CFDictionary) else {
            return nil
        }
        return ReplayPhoto(id: id, image: UIImage(cgImage: cgImage),
                           takenAt: takenAt(in: source))
    }

    // MARK: - When the shutter fired

    /// The instant the photo was taken, from the most trustworthy source the file carries.
    ///
    /// Three sources, in descending order of how much they actually know:
    ///
    /// 1. **`DateTimeOriginal` + `OffsetTimeOriginal`.** EXIF's own timestamp with EXIF's own
    ///    UTC offset. Written by every iPhone since iOS 13 and unambiguous.
    /// 2. **The GPS timestamp.** A date and a time in UTC, straight off the satellites. Also
    ///    unambiguous, and present on almost anything shot outdoors — which a wingfoiling
    ///    photo is.
    /// 3. **`DateTimeOriginal` alone**, read in the device's current zone. EXIF's original
    ///    field has no zone in it at all, so this is a guess — and it is the *right* guess for
    ///    the case that matters (a rider back from the water, phone still on the same clock
    ///    the photos were shot on). An hour of error puts a photo an hour into a session that
    ///    lasted eleven minutes, which the span check then sends to the slideshow rather than
    ///    to a wrong moment.
    ///
    /// Nil is a perfectly ordinary answer: a screenshot, or anything a messenger re-encoded,
    /// arrives with the metadata gone.
    nonisolated static func takenAt(in source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any] else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let original = exif?[kCGImagePropertyExifDateTimeOriginal] as? String

        if let original, let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String,
           let date = parse(original, offset: offset) {
            return date
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let stamp = gps[kCGImagePropertyGPSDateStamp] as? String,
           let time = gps[kCGImagePropertyGPSTimeStamp] as? String,
           let date = parseGPS(stamp: stamp, time: time) {
            return date
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let zoneless = original ?? tiff?[kCGImagePropertyTIFFDateTime] as? String else {
            return nil
        }
        return parse(zoneless, offset: nil)
    }

    /// `"2026:08:30 14:32:11"` — EXIF's own colon-separated date, with or without a zone.
    private nonisolated static func parse(_ text: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = offset.flatMap(zone(from:)) ?? .current
        return formatter.date(from: text)
    }

    /// `"+02:00"` / `"-05:00"` / `"Z"`.
    private nonisolated static func zone(from offset: String) -> TimeZone? {
        let trimmed = offset.trimmingCharacters(in: .whitespaces)
        if trimmed == "Z" { return TimeZone(secondsFromGMT: 0) }
        let parts = trimmed.dropFirst().split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]),
              let sign = trimmed.first, sign == "+" || sign == "-" else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }

    /// `"2026:08:30"` + `"12:32:11.00"`, both UTC — GPS never speaks local time.
    private nonisolated static func parseGPS(stamp: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let seconds = time.split(separator: ".").first.map(String.init) ?? time
        return formatter.date(from: "\(stamp) \(seconds)")
    }
}
