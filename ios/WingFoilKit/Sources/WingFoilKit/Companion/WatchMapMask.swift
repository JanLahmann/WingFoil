import Foundation

/// The ground the watch draws under its breadcrumb, as arithmetic.
///
/// WHAT THIS IS. The firmware's own map view kills the app on the fenix 8 (docs/decisions,
/// GitHub #4), so the watch will never get a Garmin map. What it can get is a picture the
/// phone made: a coarse **land / water / road mask** of the rider's spot, a kilobyte or
/// two, pushed once over the companion link and blitted under the track. This type is the
/// whole phone-side rule — classify a bitmap, shrink it to the grid, encode it, hash it —
/// written down where it can be tested. `docs/watch-map-snapshot.md` is the contract and
/// `garmin/source/ui/MapSnapshot.mc` is the other half of every number in this file.
///
/// WHY IT IS IN THE KIT AND NOT IN THE APP. Everything here is bytes in, bytes out. The
/// one thing that needs a framework — asking MapKit for the picture — is `WatchMapSender`
/// in the app target, and it hands the pixels straight back to `classify`. That seam means
/// the part that can actually be wrong (a run that crosses a row, a row that sums to 119,
/// a shoreline that comes out inverted) is checked by `swift test` on any machine, with no
/// map server, no watch and no Garmin Connect in the room.
///
/// WHY THE CLASSES ARE THREE AND NOT MORE. The watch draws them in three inks and nothing
/// brighter than mid grey, because the teal breadcrumb and the white position marker have
/// to stay the brightest things on the glass. A fourth class would buy a distinction the
/// rider cannot see at 1.4 inches and would cost a bit in the run byte.
public enum WatchMapMask {

    /// The schema the watch checks first and refuses to read past. Bump here and in
    /// `MapSnapshot.SCHEMA` together, never one alone.
    public static let schema = 1

    /// The grid the watch expects by default — 120 × 120 cells over a 3 km box, so one
    /// cell is 25 m on the ground. Finer than the fenix's own pixel pitch at that zoom,
    /// which is the point at which more cells stop buying more shoreline.
    public static let gridSide = 120

    /// The coarser grid used when 120 will not fit the payload budget: 60 × 60, one cell
    /// 50 m. The watch reads `mw`/`mh` and never assumes either number.
    public static let fallbackGridSide = 60

    /// The most the encoded mask may be. `ConnectIQ.sendMessage` to a device app is not a
    /// file transfer — a payload past a few kilobytes is refused by the SDK, silently on
    /// some firmware — so the sender drops to `fallbackGridSide` rather than find out on
    /// the water. Well clear of the 14 400-byte theoretical worst case a 120 grid can hit.
    public static let maxBytes = 8_000

    /// The snapshot the phone asks MapKit for: 360 × 360 points at scale 1, which is
    /// exactly 3 × `gridSide` and 6 × `fallbackGridSide`. Both downsamples are therefore
    /// whole-pixel blocks with no resampling anywhere — a fractional block would smear the
    /// shoreline by a cell and there would be no way to tell which side it moved to.
    public static let snapshotSide = 360

    /// Half the box, in metres: the spot's centre ± 1 500 m, a 3 km square of ground.
    public static let halfSpanM: Double = 1_500

    /// Metres per degree of latitude, from `SpotClusterer`'s own earth radius. Spelled
    /// from that constant rather than as a literal so the box and the clustering that
    /// chose its centre are drawn on the same sphere.
    public static let metresPerDegreeLat = SpotClusterer.earthRadiusM * .pi / 180

    // MARK: - Classes

    /// What one cell is. The raw values are the wire values: they are shifted into the top
    /// two bits of a run byte, so nothing above 3 can ever exist.
    public enum Class: UInt8, Sendable, CaseIterable {
        case water = 0
        case land = 1
        /// Road, or built up. Apple's muted map paints both near-white and the rider reads
        /// them the same way — "that is the town, the water is over there".
        case road = 2
        /// Reserved. Nothing produces it; the watch draws it as land.
        case reserved = 3
    }

    // MARK: - Classification thresholds

    /// The rules that turn an Apple muted-standard pixel into a class, tuned on the two
    /// committed fixtures (Nago-Torbole and Fehmarn, `Tests/Fixtures`).
    ///
    /// HSL and not RGB because the map's palette is a set of *tints* — the same blue at
    /// four lightnesses for lake, sea, river and the antialiased edge between them — and a
    /// hue band survives a tint where three RGB ranges do not.
    ///
    /// The water hue band stops at **210°** for one concrete reason: Apple's road shields
    /// (the blue `SS 240` lozenge over Torbole) sit at 213–216° with a saturation and a
    /// lightness indistinguishable from the lake's. Water itself is 196° to within a
    /// degree across both fixtures, so the band has 14° of headroom on that side and still
    /// excludes the shield — which would otherwise punch a three-cell lake into a hillside.
    public enum Thresholds {
        /// Water's hue band, degrees. Apple's water is 196°; the margins carry the
        /// antialiased shoreline without reaching the 213°+ of a road shield.
        public static let waterHue: ClosedRange<Double> = 185...210
        /// Below this the pixel is a grey and no hue means anything.
        public static let waterSaturationMin: Double = 0.30
        /// Water is a light tint but never white. The ceiling keeps the near-white of a
        /// road casing from reading as a very pale lake.
        public static let waterLightness: ClosedRange<Double> = 0.35...0.95
        /// Near-white: roads, buildings, the built-up wash over a town. Land's lightest
        /// green is 0.910, so 0.925 is the gap between them rather than a guess.
        public static let roadLightnessMin: Double = 0.925
        /// …and near-white means barely tinted. A saturated near-white is a label or a
        /// shield, not a road.
        public static let roadSaturationMax: Double = 0.45
        /// The map's road yellow — the cream Apple fills a trunk road with at this zoom.
        public static let roadYellowHue: ClosedRange<Double> = 30...65
        public static let roadYellowSaturationMin: Double = 0.45
        public static let roadYellowLightnessMin: Double = 0.85
    }

    /// One pixel's class, from 8-bit sRGB.
    public static func classify(red: UInt8, green: UInt8, blue: UInt8) -> Class {
        let (hue, saturation, lightness) = hsl(red: red, green: green, blue: blue)
        if Thresholds.waterHue.contains(hue),
           saturation >= Thresholds.waterSaturationMin,
           Thresholds.waterLightness.contains(lightness) {
            return .water
        }
        if lightness >= Thresholds.roadLightnessMin,
           saturation <= Thresholds.roadSaturationMax {
            return .road
        }
        if Thresholds.roadYellowHue.contains(hue),
           saturation >= Thresholds.roadYellowSaturationMin,
           lightness >= Thresholds.roadYellowLightnessMin {
            return .road
        }
        return .land
    }

    /// A whole bitmap's classes, row-major, one byte per pixel.
    ///
    /// `rgba` is four bytes per pixel in that order; the alpha byte is ignored, because a
    /// map snapshot is opaque and a partly transparent pixel would be a bug upstream
    /// rather than a class. A buffer that is not `width * height * 4` long returns empty:
    /// the caller handed us something that is not the picture it said it was.
    public static func classify(rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return [] }
        var out = [UInt8](repeating: Class.land.rawValue, count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            out[index] = classify(red: rgba[base],
                                  green: rgba[base + 1],
                                  blue: rgba[base + 2]).rawValue
        }
        return out
    }

    /// sRGB → HSL, hue in degrees 0..<360, saturation and lightness 0…1.
    static func hsl(red: UInt8, green: UInt8, blue: UInt8) -> (Double, Double, Double) {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let high = max(r, g, b), low = min(r, g, b)
        let lightness = (high + low) / 2
        let span = high - low
        guard span > 0 else { return (0, 0, lightness) }
        let saturation = lightness > 0.5 ? span / (2 - high - low) : span / (high + low)
        var hue: Double
        if high == r {
            hue = (g - b) / span + (g < b ? 6 : 0)
        } else if high == g {
            hue = (b - r) / span + 2
        } else {
            hue = (r - g) / span + 4
        }
        hue *= 60
        return (hue, saturation, lightness)
    }

    // MARK: - Downsampling

    /// Majority vote over whole `from / to` blocks — 3 × 3 for the 120 grid, 6 × 6 for the
    /// 60 one.
    ///
    /// Majority rather than an average of anything: these are labels, not quantities, and
    /// the mean of water and land is not a coastline, it is a wrong colour. A **tie goes
    /// to the lower class** (water before land before road), which is deterministic and,
    /// on the one boundary where ties actually happen, errs towards the water — the side
    /// the rider is on, and the side whose edge he is reading the picture for.
    ///
    /// Returns empty when the sides do not divide, rather than resampling: see
    /// `snapshotSide`.
    public static func downsample(classes: [UInt8], from: Int, to: Int) -> [UInt8] {
        guard from > 0, to > 0, from % to == 0, classes.count >= from * from else { return [] }
        let factor = from / to
        var out = [UInt8](repeating: Class.land.rawValue, count: to * to)
        for gy in 0..<to {
            for gx in 0..<to {
                var counts = [Int](repeating: 0, count: 4)
                for y in (gy * factor)..<(gy * factor + factor) {
                    let row = y * from
                    for x in (gx * factor)..<(gx * factor + factor) {
                        let value = Int(classes[row + x])
                        if value < 4 { counts[value] += 1 }
                    }
                }
                var best = 0
                for value in 1..<4 where counts[value] > counts[best] { best = value }
                out[gy * to + gx] = UInt8(best)
            }
        }
        return out
    }

    // MARK: - Run-length coding

    /// The mask on the wire: one byte per run, `(class << 6) | (length − 1)`, so a run is
    /// 1…64 cells and **never crosses a row boundary**.
    ///
    /// The row rule is what lets the watch validate a mask it did not build: it walks the
    /// runs, adds their lengths, and every row has to land on exactly `mw`. A payload that
    /// was truncated, reordered or built by an older phone fails that sum and is dropped
    /// whole rather than drawn as a shoreline in the wrong place.
    public static func encode(grid: [UInt8], width: Int, height: Int) -> Data {
        guard width > 0, height > 0, grid.count >= width * height else { return Data() }
        var out = Data()
        out.reserveCapacity(width * height / 8)
        for y in 0..<height {
            var x = 0
            while x < width {
                let value = grid[y * width + x] & 0b11
                var run = 1
                while x + run < width, run < 64, grid[y * width + x + run] & 0b11 == value {
                    run += 1
                }
                out.append(UInt8(value << 6) | UInt8(run - 1))
                x += run
            }
        }
        return out
    }

    /// The watch's own reading of `encode`, so the round trip is a test rather than a
    /// promise. `nil` on any row that does not sum to `width` — the exact rule
    /// `MapSnapshot.store` drops a message on.
    public static func decode(_ data: Data, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(width * height)
        var index = data.startIndex
        for _ in 0..<height {
            var filled = 0
            while filled < width {
                guard index < data.endIndex else { return nil }
                let byte = data[index]
                index = data.index(after: index)
                let value = byte >> 6
                let run = Int(byte & 0b0011_1111) + 1
                // Past the row's end is the failure this check exists for: a run that
                // would spill into the next row means the whole mask is misaligned.
                guard filled + run <= width else { return nil }
                out.append(contentsOf: repeatElement(value, count: run))
                filled += run
            }
            guard filled == width else { return nil }
        }
        // Trailing bytes mean the sender and this reader disagree about the grid.
        guard index == data.endIndex else { return nil }
        return out
    }

    // MARK: - Identity

    /// FNV-1a over the encoded mask. Not a checksum the watch verifies — it is the phone's
    /// own answer to "is this the same picture I already sent that watch?", which is what
    /// keeps a launch from re-pushing two kilobytes over BLE every time.
    public static func hash(_ data: Data) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in data {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    /// A spot's id on the watch: FNV-1a of its cluster key, folded to 31 bits.
    ///
    /// 31 and not 32 because Monkey C has no unsigned integer — a `Number` is a signed
    /// 32-bit value, and a hash with the top bit set would arrive negative, compare
    /// unequal to itself across a storage round trip on some firmware, and quietly
    /// duplicate the slot it was supposed to replace.
    public static func spotID(clusterKey: String) -> Int32 {
        Int32(hash(Data(clusterKey.utf8)) & 0x7FFF_FFFF)
    }

    // MARK: - The message

    /// The spot a mask is of.
    public struct Spot: Sendable, Equatable {
        /// The library's own handle for the cluster — `SpotRow.id`. Stable across renames,
        /// which is why the id hangs off it and not off the name.
        public var clusterKey: String
        /// What the caption says. Trimmed to 24 characters by `message`, because the watch
        /// draws it in one line under a 1.4-inch map.
        public var name: String

        public init(clusterKey: String, name: String) {
            self.clusterKey = clusterKey
            self.name = name
        }
    }

    /// The square of ground a mask covers, in degrees.
    public struct Box: Sendable, Equatable {
        public var south: Double
        public var west: Double
        public var north: Double
        public var east: Double

        public init(south: Double, west: Double, north: Double, east: Double) {
            self.south = south
            self.west = west
            self.north = north
            self.east = east
        }

        /// The spot's centre ± `halfSpanM`. The longitude half-span is divided by
        /// `cos(latitude)` so the box is a square **on the ground** rather than in degrees
        /// — at Fehmarn a degree of longitude is 58 % of a degree of latitude, and a box
        /// that ignored that would hand the watch a picture stretched almost two to one.
        public init(centreLat: Double, centreLon: Double, halfSpanM: Double = WatchMapMask.halfSpanM) {
            let dLat = halfSpanM / WatchMapMask.metresPerDegreeLat
            // Clamped away from the poles, where the division stops meaning anything. No
            // wingfoiler is at 89.9°, but a corrupt fix is not impossible and an infinite
            // box would be sent rather than caught.
            let cosLat = max(cos(min(max(centreLat, -85), 85) * .pi / 180), 0.01)
            let dLon = dLat / cosLat
            self.init(south: centreLat - dLat, west: centreLon - dLon,
                      north: centreLat + dLat, east: centreLon + dLon)
        }
    }

    /// A finished mask: the cells and the shape they are in.
    public struct Grid: Sendable, Equatable {
        public var width: Int
        public var height: Int
        /// Row-major, **north row first**, west cell first — the order the watch blits in.
        public var cells: [UInt8]

        public init(width: Int, height: Int, cells: [UInt8]) {
            self.width = width
            self.height = height
            self.cells = cells
        }

        public var encoded: Data { WatchMapMask.encode(grid: cells, width: width, height: height) }
    }

    /// How many characters of a spot name the caption gets.
    public static let nameLimit = 24

    /// The dictionary handed to `ConnectIQ.sendMessage`, exactly as the watch reads it.
    ///
    /// Every number is an `Int` and every coordinate is an integer of hundred-thousandths
    /// of a degree (≈ 1.1 m, a tenth of a cell). Not a float anywhere: Monkey C's `Float`
    /// is 32-bit, the serialiser rounds it on the way over, and a box edge that arrives a
    /// metre out would shift the whole picture against the breadcrumb drawn on top of it.
    public static func message(spot: Spot, box: Box, grid: Grid) -> [String: Any] {
        [
            "mv": schema,
            "mi": Int(spotID(clusterKey: spot.clusterKey)),
            "mn": String(spot.name.prefix(nameLimit)),
            "la": micro(box.south),
            "lo": micro(box.west),
            "lh": micro(box.north),
            "lx": micro(box.east),
            "mw": grid.width,
            "mh": grid.height,
            "mp": grid.encoded,
        ]
    }

    /// Degrees × 100 000, rounded — the integer the watch divides back out.
    public static func micro(_ degrees: Double) -> Int {
        Int((degrees * 100_000).rounded())
    }

    // MARK: - The whole phone-side pipeline

    /// Classify a snapshot, shrink it, and drop to the coarse grid if the fine one will
    /// not fit the payload budget. `nil` when the bitmap is not the square this expects.
    ///
    /// The fallback is measured, never predicted: a 120 grid of open sea is 700 bytes and
    /// a 120 grid of a city would be ten thousand, and the only honest way to tell them
    /// apart is to encode and look.
    public static func grid(rgba: [UInt8], side: Int = snapshotSide) -> Grid? {
        let classes = classify(rgba: rgba, width: side, height: side)
        guard !classes.isEmpty else { return nil }
        let fine = downsample(classes: classes, from: side, to: gridSide)
        guard !fine.isEmpty else { return nil }
        let fineGrid = Grid(width: gridSide, height: gridSide, cells: fine)
        if fineGrid.encoded.count <= maxBytes { return fineGrid }
        let coarse = downsample(classes: classes, from: side, to: fallbackGridSide)
        guard !coarse.isEmpty else { return nil }
        return Grid(width: fallbackGridSide, height: fallbackGridSide, cells: coarse)
    }
}
