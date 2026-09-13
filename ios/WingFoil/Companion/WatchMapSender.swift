import CoreLocation
import MapKit
import UIKit
import WingFoilKit

/// The phone half of docs/watch-map-snapshot.md, above the arithmetic: pick the spots, ask
/// MapKit for the picture, hand the pixels to `WatchMapMask`, push the result.
///
/// WHY IT IS IN THE APP TARGET. Two frameworks the kit must never see — MapKit, which needs
/// a map server and an Apple platform, and ConnectIQ, which needs a binary xcframework. The
/// bit that can be wrong (a hue band that loses the shoreline, a run that crosses a row, a
/// box that is not square on the ground) is all next door in `WatchMapMask`, with tests.
/// What is left here is glue, and glue is what it should look like.
///
/// WHY TWO SPOTS AND NOT EVERY SPOT. The watch keeps two slots (`MapSnapshot.mc`), because
/// a fenix's storage is small and a rider is at one of two places on any given afternoon.
/// Sending a third would evict one of the two he actually uses, so the phone sends exactly
/// what the watch can hold. *Which* two is `WatchMapChoice` in the kit: by default the two
/// he has ridden most, and otherwise whatever he ticked in Settings — up to two of the
/// library's spots and "Where I am now", the phone's own position, for the afternoon at a
/// lake the library has never seen. By the time a target reaches this file the choosing is
/// over; what arrives is a name and a centre.
///
/// WHY IT IS SO SHY ABOUT SENDING. Every push is a couple of kilobytes over BLE through
/// Garmin Connect Mobile, and the ground under a spot does not change. So a mask goes out
/// only when its hash differs from the one this phone last got a `.success` for *on this
/// watch* — a new spot, a re-cluster that moved a centre, or a rider who picked a different
/// watch. Everything else is a no-op with no radio in it.
@MainActor
enum WatchMapSender {

    /// How many spots the watch can hold — `MapSnapshot.SLOTS` is the other half, and
    /// `WatchMapChoice.slots` in the kit is the number this one is spelled from.
    static let slots = WatchMapChoice.slots

    /// What one send produced, for the settings row and for the log.
    struct Report: Equatable {
        /// Spot names actually pushed, in order.
        var sent: [String] = []
        /// Spot names whose mask this watch already has.
        var unchanged: [String] = []
        /// Total mask bytes on the wire.
        var bytes = 0
        /// The first thing that went wrong, in the rider's words.
        var failure: String?

        var didSomething: Bool { !sent.isEmpty }
    }

    // MARK: - Choosing

    /// The two most-ridden spots that have a coordinate, most-ridden first — what the
    /// watch gets when the rider has not said otherwise.
    ///
    /// The rule itself lives in `WatchMapChoice.mostRidden`, in the kit, where it is tested
    /// and where the picker reads it too: the order the rider chooses from and the order
    /// the automatic answer picks in have to be one order, or the "Two most-ridden spots"
    /// row would name a different pair than the list under it.
    static func targets(from spots: [SpotAggregate], limit: Int = slots) -> [SpotAggregate] {
        WatchMapChoice.mostRidden(spots, limit: limit)
    }

    // MARK: - Rendering

    /// The snapshot, classified and shrunk. `nil` when MapKit could not draw the box —
    /// offline with nothing cached is the ordinary reason, and it is not an error worth a
    /// banner: the rider will be online again before he is on the water.
    static func grid(centreLat: Double, centreLon: Double) async -> WatchMapMask.Grid? {
        await gridOrReason(centreLat: centreLat, centreLon: centreLon).grid
    }

    /// The same, with the reason MapKit gave when it could not draw — for the status line,
    /// which used to say "no map to send yet" for a failed render *and* for an empty
    /// library, and the rider could not tell which (Jan, 13 Sep 2026).
    static func gridOrReason(centreLat: Double, centreLon: Double) async
    -> (grid: WatchMapMask.Grid?, reason: String?) {
        let shot = await snapshotRGBA(centreLat: centreLat, centreLon: centreLon)
        guard let rgba = shot.bytes else { return (nil, shot.reason ?? "no image") }
        return (WatchMapMask.grid(rgba: rgba), nil)
    }

    /// `WatchMapMask.snapshotSide` square pixels of Apple's muted standard map, as RGBA.
    private static func snapshotRGBA(centreLat: Double, centreLon: Double) async
    -> (bytes: [UInt8]?, reason: String?) {
        let side = WatchMapMask.snapshotSide
        let box = WatchMapMask.Box(centreLat: centreLat, centreLon: centreLon)
        let northWest = MKMapPoint(CLLocationCoordinate2D(latitude: box.north, longitude: box.west))
        let southEast = MKMapPoint(CLLocationCoordinate2D(latitude: box.south, longitude: box.east))
        let rect = MKMapRect(x: northWest.x, y: northWest.y,
                             width: southEast.x - northWest.x,
                             height: southEast.y - northWest.y)
        guard rect.width > 0, rect.height > 0 else { return (nil, "the box has no area") }

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = CGSize(width: side, height: side)
        // Scale 1, so 360 points are 360 pixels and the 3 × 3 and 6 × 6 downsamples are
        // whole blocks. A retina snapshot would be 720 px and would have to be resampled,
        // which is the one thing the whole pipeline is built to avoid.
        options.scale = 1
        // Always the light map, whatever the phone is set to. The thresholds are tuned on
        // Apple's light palette and the dark one inverts every one of them — a rider in
        // dark mode would get a mask with the lake and the hillside swapped.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        // `.muted` is the flat, label-light emphasis; `.flat` elevation because realistic
        // terrain shades a hillside through several lightnesses and would speckle the land
        // class with roads. POIs off because a pin is not ground.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        options.showsBuildings = false

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await MKMapSnapshotter(options: options).start()
        } catch {
            return (nil, error.localizedDescription)
        }
        guard let image = snapshot.image.cgImage else { return (nil, "no image") }
        // `options.scale = 1` is not honoured on iOS 26: the snapshot comes back at the
        // screen's scale, 1080 px on a 3× phone (measured, 13 Sep 2026 — this is what
        // Jan's "no map to send yet" was). So the image is drawn into the 360-px context
        // below whatever size it arrived at; a 3× image drawn at 1× is a 3 × 3 box
        // average, which is the same whole-block downsample the pipeline wanted.

        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = bytes.withUnsafeMutableBytes({ raw in
            CGContext(data: raw.baseAddress, width: side, height: side,
                      bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
        }) else { return (nil, "no drawing context") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return (bytes, nil)
    }

    // MARK: - Sending

    /// Render and push the chosen maps. `force` sends even a mask the watch already has —
    /// the manual button, for the rider who wants to watch it happen.
    ///
    /// `progress` is called with a spot name before each render, because drawing two map
    /// snapshots takes a second or two on a cold tile cache and a row that says nothing for
    /// that long reads as a row that did nothing.
    static func send(targets: [WatchMapTarget], through link: ConnectIQCompanionLink,
                     force: Bool, defaults: UserDefaults = .standard,
                     progress: (String) -> Void = { _ in }) async -> Report {
        var report = Report()
        guard !targets.isEmpty else {
            report.failure = CompanionLinkError.mapUnavailable.riderMessage
            return report
        }
        guard let deviceKey = link.deviceKey else {
            report.failure = CompanionLinkState.noDevice.headline
            return report
        }

        for target in targets {
            let spot = WatchMapMask.Spot(clusterKey: target.clusterKey, name: target.name)
            let spotID = WatchMapMask.spotID(clusterKey: spot.clusterKey)
            progress(spot.name)
            let drawn = await gridOrReason(centreLat: target.lat, centreLon: target.lon)
            guard let grid = drawn.grid else {
                report.failure = report.failure
                    ?? "MapKit could not draw \(spot.name): \(drawn.reason ?? "no image"). "
                    + "Be online once while it draws, then send again."
                continue
            }
            let mask = grid.encoded
            let hash = WatchMapMask.hash(mask)
            if !force, acknowledged(device: deviceKey, spot: spotID, in: defaults) == hash {
                report.unchanged.append(spot.name)
                continue
            }
            let box = WatchMapMask.Box(centreLat: target.lat, centreLon: target.lon)
            do {
                try await link.sendMapSnapshot(
                    WatchMapMask.message(spot: spot, box: box, grid: grid))
                // Written only after the radio said yes: an optimistic note would mean a
                // failed push is never retried.
                acknowledge(hash, device: deviceKey, spot: spotID, in: defaults)
                report.sent.append(spot.name)
                report.bytes += mask.count
            } catch let error as CompanionLinkError {
                report.failure = report.failure ?? error.riderMessage
            } catch {
                report.failure = report.failure ?? "\(error)"
            }
        }
        return report
    }

    // MARK: - When it is worth even looking

    /// What the automatic pass compares: which watch, which two maps, and where their
    /// centres are to the metre.
    ///
    /// The acknowledged-hash check is the honest one, but it costs two map renders to
    /// reach — and the automatic pass runs at every launch and after every import. This is
    /// the cheap gate in front of it: if the same watch is still looking at the same two
    /// boxes at the same centres, the masks cannot have changed either, and the whole thing
    /// is skipped without touching MapKit. A re-cluster that nudges a centroid by a metre
    /// does move it, which is right — that is a different box. So does a rider who walked
    /// fifty metres with "Where I am now" ticked, which is also right and is the reason
    /// that pick is worth a manual send rather than a launch.
    static func fingerprint(targets: [WatchMapTarget], deviceKey: String) -> String {
        let parts = targets.map {
            "\($0.clusterKey):\(WatchMapMask.micro($0.lat)):\(WatchMapMask.micro($0.lon))"
        }
        return ([deviceKey] + parts).joined(separator: "|")
    }

    private static let fingerprintKey = "watchMap.lastAuto"

    static func automaticPassIsWorthIt(targets: [WatchMapTarget], deviceKey: String,
                                       in defaults: UserDefaults) -> Bool {
        defaults.string(forKey: fingerprintKey)
            != fingerprint(targets: targets, deviceKey: deviceKey)
    }

    static func rememberAutomaticPass(targets: [WatchMapTarget], deviceKey: String,
                                      in defaults: UserDefaults) {
        defaults.set(fingerprint(targets: targets, deviceKey: deviceKey),
                     forKey: fingerprintKey)
    }

    // MARK: - What this watch already has

    /// Keyed by device **and** spot: a rider with two watches has told us nothing about the
    /// second by having told us about the first.
    static func acknowledgedKey(device: String, spot: Int32) -> String {
        "watchMap.ack.\(device).\(spot)"
    }

    static func acknowledged(device: String, spot: Int32, in defaults: UserDefaults) -> UInt32? {
        guard let stored = defaults.object(forKey: acknowledgedKey(device: device, spot: spot))
                as? NSNumber else { return nil }
        return stored.uint32Value
    }

    static func acknowledge(_ hash: UInt32, device: String, spot: Int32,
                            in defaults: UserDefaults) {
        defaults.set(NSNumber(value: hash), forKey: acknowledgedKey(device: device, spot: spot))
    }
}

extension WatchMapSender.Report {

    /// The settings row's one line. "sent 2.1 KB · 14:02", or what went wrong, or the quiet
    /// answer that there was nothing to do — which is the usual one and has to read as
    /// success rather than as silence.
    func line(at moment: Date, zone: TimeZone = .current) -> String {
        if let failure { return failure }
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_GB")
        clock.timeZone = zone
        clock.dateFormat = "HH:mm"
        let time = clock.string(from: moment)
        if sent.isEmpty {
            return unchanged.isEmpty ? "Nothing to send" : "Already on the watch · \(time)"
        }
        let kilobytes = Double(bytes) / 1_024
        return String(format: "sent %.1f KB · %@", kilobytes, time)
    }
}
