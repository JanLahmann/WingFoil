import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import WingFoilKit

/// The phone half of docs/watch-map-snapshot.md: the bytes the watch is asked to blit.
///
/// Two of these tests are about arithmetic that has one right answer (a run may not cross a
/// row; a row that does not sum to `mw` is refused) and two are about a judgement call that
/// only real pixels can settle — whether the thresholds actually find the lake. The second
/// kind runs against two committed snapshots, `Tests/Fixtures/watchmap-*.png`, rendered once
/// with `MKMapSnapshotter` at the exact box and style `WatchMapSender` asks for. They are
/// checked in rather than fetched: a test that needs Apple's map servers is a test that fails
/// on a train, and the thresholds are tuned to *these* pixels, so the pixels are the fixture.
@Suite struct WatchMapMaskTests {

    // MARK: - Fixtures

    /// The two spots, with the centre each PNG was rendered around.
    static let torbole = (file: "watchmap-nago-torbole", lat: 45.8690, lon: 10.8740)
    static let fehmarn = (file: "watchmap-fehmarn", lat: 54.4050, lon: 11.1830)

    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // -> WingFoilKitTests/
            .deletingLastPathComponent()      // -> Tests/
            .appendingPathComponent("Fixtures")
    }

    /// A fixture as straight RGBA bytes, which is what `WatchMapSender` hands the kit after
    /// MapKit has drawn into a bitmap context.
    static func rgba(_ name: String) throws -> (bytes: [UInt8], side: Int) {
        let url = fixturesDir.appendingPathComponent("\(name).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MaskFixtureError.unreadable(url.lastPathComponent)
        }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = bytes.withUnsafeMutableBytes({ raw in
            CGContext(data: raw.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
        }) else { throw MaskFixtureError.unreadable(name) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (bytes, width)
    }

    enum MaskFixtureError: Error { case unreadable(String) }

    /// Which cell of a 120-grid a coordinate falls in, the same arithmetic the watch's
    /// `MapSnapshot` does in reverse.
    static func cell(_ grid: WatchMapMask.Grid, box: WatchMapMask.Box,
                     lat: Double, lon: Double) -> WatchMapMask.Class {
        let gx = Int((lon - box.west) / (box.east - box.west) * Double(grid.width))
        let gy = Int((box.north - lat) / (box.north - box.south) * Double(grid.height))
        let clampedX = min(max(gx, 0), grid.width - 1)
        let clampedY = min(max(gy, 0), grid.height - 1)
        return WatchMapMask.Class(rawValue: grid.cells[clampedY * grid.width + clampedX]) ?? .land
    }

    // MARK: - The classifier, on real map pixels

    /// Nago-Torbole: the lake has to be water, the Via Linfano has to be road, and the
    /// hillside east of the village has to be neither.
    ///
    /// The lake probes are two kilometres apart so the test is about the whole surface
    /// rather than one tint; the Via Linfano probe is the one the contract names, and it is
    /// the harder half — a road is one or two cells wide at 25 m a cell, so a classifier
    /// that let the near-white of a road wash into the land class would lose it entirely.
    @Test func theLakeIsWaterAndTheViaLinfanoIsRoadAtTorbole() throws {
        let picture = try Self.rgba(Self.torbole.file)
        let grid = try #require(WatchMapMask.grid(rgba: picture.bytes, side: picture.side))
        let box = WatchMapMask.Box(centreLat: Self.torbole.lat, centreLon: Self.torbole.lon)

        #expect(Self.cell(grid, box: box, lat: 45.8620, lon: 10.8620) == .water)   // Garda, SW
        #expect(Self.cell(grid, box: box, lat: 45.8650, lon: 10.8700) == .water)   // Garda, mid
        #expect(Self.cell(grid, box: box, lat: 45.8760, lon: 10.8700) == .road)    // Via Linfano
        #expect(Self.cell(grid, box: box, lat: 45.8700, lon: 10.8760) == .road)    // the village
        #expect(Self.cell(grid, box: box, lat: 45.8650, lon: 10.8880) == .land)    // the hillside

        // A shore box is mostly shore: if the water share collapsed the thresholds moved.
        let water = grid.cells.count { $0 == WatchMapMask.Class.water.rawValue }
        #expect(water > grid.cells.count / 6)
        #expect(water < grid.cells.count / 2)
    }

    /// Fehmarn: the Baltic south of the Wulfener Hals and the Burger Binnensee north of it
    /// are two different waters that must both read as water, and Burgtiefe across the
    /// channel must read as built-up.
    @Test func bothSeaAndLagoonAreWaterAtFehmarn() throws {
        let picture = try Self.rgba(Self.fehmarn.file)
        let grid = try #require(WatchMapMask.grid(rgba: picture.bytes, side: picture.side))
        let box = WatchMapMask.Box(centreLat: Self.fehmarn.lat, centreLon: Self.fehmarn.lon)

        #expect(Self.cell(grid, box: box, lat: 54.3960, lon: 11.1830) == .water)   // the Baltic
        #expect(Self.cell(grid, box: box, lat: 54.3930, lon: 11.2000) == .water)   // the Baltic, SE
        #expect(Self.cell(grid, box: box, lat: 54.4150, lon: 11.1750) == .water)   // Binnensee
        #expect(Self.cell(grid, box: box, lat: 54.4120, lon: 11.1990) == .road)    // Burgtiefe
        #expect(Self.cell(grid, box: box, lat: 54.4020, lon: 11.1680) == .land)    // the fields

        // An island's tip in a sea: water is most of the picture, and land is a real share
        // of it rather than a rounding error.
        let water = grid.cells.count { $0 == WatchMapMask.Class.water.rawValue }
        #expect(water > grid.cells.count * 2 / 3)
        #expect(water < grid.cells.count * 9 / 10)
    }

    /// Both fixtures come out as the fine grid, well inside the payload budget. The
    /// numbers are the reason the contract can promise "1–3 KB".
    @Test func aShoreMaskIsACoupleOfKilobytes() throws {
        for fixture in [Self.torbole, Self.fehmarn] {
            let picture = try Self.rgba(fixture.file)
            let grid = try #require(WatchMapMask.grid(rgba: picture.bytes, side: picture.side))
            #expect(grid.width == WatchMapMask.gridSide)
            #expect(grid.encoded.count <= 3_000)
            #expect(grid.encoded.count <= WatchMapMask.maxBytes)
        }
    }

    // MARK: - The wire format

    @Test func aGridSurvivesTheRoundTrip() throws {
        var cells = [UInt8](repeating: 0, count: 120 * 120)
        // A shape with runs of every length class in it: a diagonal, a block, and single
        // cells — the three things a run-length coder gets wrong in different ways.
        for y in 0..<120 {
            for x in 0..<120 {
                if x == y { cells[y * 120 + x] = 2 }
                else if x > 80 && y > 80 { cells[y * 120 + x] = 1 }
                else if (x + y) % 37 == 0 { cells[y * 120 + x] = 2 }
            }
        }
        let encoded = WatchMapMask.encode(grid: cells, width: 120, height: 120)
        #expect(WatchMapMask.decode(encoded, width: 120, height: 120) == cells)
    }

    /// The rule the watch drops a mask on. A row that sums to 119 is a mask whose every
    /// later row is one cell out, which would draw a shoreline that is wrong everywhere and
    /// looks plausible nowhere — so it is refused whole.
    @Test func aRowThatDoesNotSumToTheWidthIsRefused() {
        // Four rows of 4, then a fifth row one cell short.
        var data = Data()
        for _ in 0..<4 { data.append(UInt8(0 << 6) | 3) }        // 4 runs of 4 = 4 rows
        data.append(UInt8(0 << 6) | 2)                            // a run of 3 in a width of 4
        #expect(WatchMapMask.decode(data, width: 4, height: 5) == nil)
    }

    @Test func aRunThatWouldSpillIntoTheNextRowIsRefused() {
        var data = Data()
        data.append(UInt8(1 << 6) | 5)                            // a run of 6 in a width of 4
        #expect(WatchMapMask.decode(data, width: 4, height: 2) == nil)
    }

    @Test func aTruncatedMaskIsRefused() {
        let cells = [UInt8](repeating: 0, count: 16)
        let encoded = WatchMapMask.encode(grid: cells, width: 4, height: 4)
        #expect(WatchMapMask.decode(encoded.dropLast(), width: 4, height: 4) == nil)
        #expect(WatchMapMask.decode(encoded + Data([0]), width: 4, height: 4) == nil)
    }

    /// A run is at most 64 cells, so a plain row of 120 is two bytes and not one — the
    /// length field is six bits and nothing about the encoder may quietly overflow it.
    @Test func longRunsSplitAtSixtyFour() {
        let row = [UInt8](repeating: 1, count: 120)
        let encoded = WatchMapMask.encode(grid: row, width: 120, height: 1)
        #expect(encoded.count == 2)
        #expect(encoded[encoded.startIndex] == (1 << 6) | 63)     // 64 cells
        #expect(encoded[encoded.index(after: encoded.startIndex)] == (1 << 6) | 55)  // 56
        #expect(WatchMapMask.decode(encoded, width: 120, height: 1) == row)

        // Exactly 64 is one byte, 65 is two: the boundary itself.
        #expect(WatchMapMask.encode(grid: [UInt8](repeating: 0, count: 64),
                                    width: 64, height: 1).count == 1)
        #expect(WatchMapMask.encode(grid: [UInt8](repeating: 0, count: 65),
                                    width: 65, height: 1).count == 2)
    }

    /// The worst case the contract talks about: a checkerboard is one byte a cell, 14 400 of
    /// them at 120, so the sender drops to the 60 grid — which is still 3 600 bytes and
    /// still fits. This is the only path that produces a 60 × 60 message, and the watch
    /// reads `mw`/`mh` precisely because it exists.
    @Test func anUnencodableGridFallsBackToSixty() {
        // A per-pixel checkerboard survives the 3 × 3 majority as a per-cell one only if the
        // period is right; build the pathological picture directly in pixel space.
        var rgba = [UInt8](repeating: 255, count: 360 * 360 * 4)
        for y in 0..<360 {
            for x in 0..<360 {
                let water = ((x / 3) + (y / 3)) % 2 == 0
                let base = (y * 360 + x) * 4
                // Apple's water tint, and a near-white road, the two the classifier knows.
                rgba[base] = water ? 189 : 248
                rgba[base + 1] = water ? 232 : 248
                rgba[base + 2] = water ? 249 : 242
            }
        }
        let fine = WatchMapMask.downsample(
            classes: WatchMapMask.classify(rgba: rgba, width: 360, height: 360),
            from: 360, to: 120)
        #expect(WatchMapMask.encode(grid: fine, width: 120, height: 120).count == 14_400)

        let grid = WatchMapMask.grid(rgba: rgba)
        #expect(grid?.width == WatchMapMask.fallbackGridSide)
        #expect(grid?.height == WatchMapMask.fallbackGridSide)
        #expect((grid?.encoded.count ?? 0) <= WatchMapMask.maxBytes)
        // And the coarse grid is still a legal mask.
        #expect(WatchMapMask.decode(grid?.encoded ?? Data(), width: 60, height: 60) != nil)
    }

    // MARK: - Downsampling

    @Test func theMajorityWinsAndATieGoesToTheLowerClass() {
        // One 3 × 3 block: five water, four land -> water.
        var classes = [UInt8](repeating: 1, count: 9)
        for index in 0..<5 { classes[index] = 0 }
        #expect(WatchMapMask.downsample(classes: classes, from: 3, to: 1) == [0])

        // Five land, four water -> land.
        classes = [UInt8](repeating: 0, count: 9)
        for index in 0..<5 { classes[index] = 1 }
        #expect(WatchMapMask.downsample(classes: classes, from: 3, to: 1) == [1])

        // A genuine tie between land and road in a 2 × 2 block goes to land.
        #expect(WatchMapMask.downsample(classes: [1, 2, 2, 1], from: 2, to: 1) == [1])
    }

    @Test func aSideThatDoesNotDivideIsRefusedRatherThanResampled() {
        let classes = [UInt8](repeating: 0, count: 100 * 100)
        #expect(WatchMapMask.downsample(classes: classes, from: 100, to: 120).isEmpty)
        #expect(WatchMapMask.downsample(classes: classes, from: 100, to: 7).isEmpty)
    }

    // MARK: - Identity

    @Test func theHashMovesWhenAnyCellDoes() {
        var cells = [UInt8](repeating: 0, count: 120 * 120)
        let before = WatchMapMask.hash(WatchMapMask.encode(grid: cells, width: 120, height: 120))
        cells[60 * 120 + 60] = 1
        let after = WatchMapMask.hash(WatchMapMask.encode(grid: cells, width: 120, height: 120))
        #expect(before != after)
        #expect(before == WatchMapMask.hash(
            WatchMapMask.encode(grid: [UInt8](repeating: 0, count: 120 * 120),
                                width: 120, height: 120)))
    }

    /// 31 bits, because Monkey C has no unsigned integer and a negative id would not match
    /// itself across the watch's storage.
    @Test func aSpotIdIsStableAndFitsInThirtyOneBits() {
        let key = "6D6E0B8A-7C3E-4F1B-9A2D-5E7C1F3A9B04"
        #expect(WatchMapMask.spotID(clusterKey: key) == WatchMapMask.spotID(clusterKey: key))
        #expect(WatchMapMask.spotID(clusterKey: key) >= 0)
        #expect(WatchMapMask.spotID(clusterKey: key) != WatchMapMask.spotID(clusterKey: key + "x"))
        for candidate in ["a", "bb", "Nago-Torbole", "", UUID().uuidString] {
            #expect(WatchMapMask.spotID(clusterKey: candidate) >= 0)
        }
    }

    // MARK: - The message

    @Test func theMessageCarriesExactlyTheContractsKeys() {
        let box = WatchMapMask.Box(centreLat: 45.8690, centreLon: 10.8740)
        let grid = WatchMapMask.Grid(width: 120, height: 120,
                                     cells: [UInt8](repeating: 0, count: 120 * 120))
        let message = WatchMapMask.message(
            spot: .init(clusterKey: "spot-1", name: "Nago-Torbole"), box: box, grid: grid)

        #expect(Set(message.keys) == ["mv", "mi", "mn", "la", "lo", "lh", "lx", "mw", "mh", "mp"])
        #expect(message["mv"] as? Int == 1)
        #expect(message["mw"] as? Int == 120)
        #expect(message["mh"] as? Int == 120)
        #expect(message["mn"] as? String == "Nago-Torbole")
        #expect(message["mp"] as? Data != nil)
        for key in ["mi", "la", "lo", "lh", "lx"] { #expect(message[key] is Int) }

        // The box is a square on the ground, so at 45.87° it is half again as wide in
        // degrees as it is tall.
        let south = try! #require(message["la"] as? Int)
        let north = try! #require(message["lh"] as? Int)
        let west = try! #require(message["lo"] as? Int)
        let east = try! #require(message["lx"] as? Int)
        #expect(north - south == 2_698)                             // 3 000 m of latitude
        #expect(Double(east - west) / Double(north - south) > 1.4)
        #expect(Double(east - west) / Double(north - south) < 1.5)
    }

    // MARK: - The link

    /// The link takes a well-formed message and refuses a malformed one on the phone's own
    /// side, so a mask that could never be drawn does not cost a BLE round trip.
    @Test func theLinkTakesAWholeMaskAndRefusesAShortenedOne() async throws {
        let link = FakeCompanionLink()
        let box = WatchMapMask.Box(centreLat: 45.8690, centreLon: 10.8740)
        let grid = WatchMapMask.Grid(width: 120, height: 120,
                                     cells: [UInt8](repeating: 0, count: 120 * 120))
        let spot = WatchMapMask.Spot(clusterKey: "spot-1", name: "Nago-Torbole")
        try await link.sendMapSnapshot(WatchMapMask.message(spot: spot, box: box, grid: grid))

        let sent = await link.sentMaps
        #expect(sent.count == 1)
        #expect(sent.first?.spotID == Int(WatchMapMask.spotID(clusterKey: "spot-1")))
        #expect(sent.first?.bytes == grid.encoded.count)

        // The same message with one run byte missing: every row after it is a cell out.
        var thrown: CompanionLinkError?
        do {
            var broken = WatchMapMask.message(spot: spot, box: box, grid: grid)
            broken["mp"] = Data(grid.encoded.dropLast())
            try await link.sendMapSnapshot(broken)
        } catch let error as CompanionLinkError {
            thrown = error
        }
        #expect(thrown == .mapUnavailable)
        #expect(await link.sentMaps.count == 1)
    }

    /// The caption is one line under a 1.4-inch map, so a long spot name is cut here rather
    /// than by whatever the watch's font does when it runs out of glass.
    @Test func aLongSpotNameIsTrimmedForTheCaption() {
        let message = WatchMapMask.message(
            spot: .init(clusterKey: "k", name: String(repeating: "Torbole ", count: 6)),
            box: WatchMapMask.Box(centreLat: 45, centreLon: 10),
            grid: WatchMapMask.Grid(width: 4, height: 4, cells: [UInt8](repeating: 0, count: 16)))
        #expect((message["mn"] as? String)?.count == WatchMapMask.nameLimit)
    }
}
