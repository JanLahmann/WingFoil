import CoreGraphics
import CoreLocation
import MapKit
import SwiftUI
import UIKit
import WingFoilKit

/// Everything an offscreen render of one session needs, resolved once, on the main actor,
/// into things a background thread may hold.
///
/// **Why a scene at all.** The renderer draws six hundred frames off the main actor, and
/// almost everything it wants — a `MKMapSnapshotter`, a `UIColor` that has to be resolved
/// against a trait collection, a SwiftUI view put through `ImageRenderer` — is main-actor
/// work or is not `Sendable`. Doing that work per frame would be six hundred hops; doing it
/// once and handing over immutable bitmaps and `CGColor`s is one hop, and it is what makes
/// the frame function a pure function of a number.
///
/// **The ground is one snapshot.** A session video is a breadcrumb drawing itself over a
/// still photograph of the water, not a moving map: nothing pans and nothing zooms, so the
/// map is taken once, at the region the whole track fits in, and every frame draws over the
/// same pixels. That is also the only version of this that can run in the Simulator, where
/// ReplayKit — the cinema clip's recorder — writes a zero-byte file (docs/testing.md).
struct ReelScene: @unchecked Sendable {

    /// One projected sample: where it is on the ground bitmap, when it happened, and what
    /// the rider was doing. `@unchecked Sendable` on the scene rather than here because the
    /// whole point is that nothing in it is ever mutated after `make` returns.
    struct Vertex {
        var t: Double
        var point: CGPoint
        var flying: Bool
        var kn: Double
    }

    struct Mark {
        var t: Double
        var point: CGPoint
        var kind: TrackThumbnail.Mark.Kind
        /// A clean jibe is a star and answers to its own chip on every map in the app
        /// (`TurnOutcomeKind.layer(clean:)`); it is a star here too.
        var clean: Bool
    }

    /// The frame, in pixels. 9:16 at 1080 wide is what every feed wants and what H.264
    /// hardware on every supported phone encodes without a second thought.
    static let size = CGSize(width: 1080, height: 1920)

    /// The snapshot is taken in points at 2× rather than in pixels at 1×, so MapKit draws
    /// its labels and coastlines at the weight a phone screen would show them at. A 1080-pt
    /// map is a map for a billboard: hairline roads and unreadable place names.
    static let snapshotScale: CGFloat = 2

    /// Where the track is allowed to live, in snapshot points. The generous top and bottom
    /// margins are the callout's and the live strip's — a breadcrumb that runs under the
    /// speed readout is a breadcrumb nobody can follow.
    static let trackBox = CGRect(x: 44, y: 132, width: 452, height: 636)

    let ground: CGImage
    let vertices: [Vertex]
    let marks: [Mark]
    let plan: ReelPlan
    /// The closing card, rendered once — `ReplayOutroCardView`, which is the clip's end card
    /// and carries the share card's own footer: the mark, the wordmark, the call to action
    /// and the QR, in that order (docs/presentation.md, "The share card carries the same
    /// block").
    let endCard: CGImage
    let ink: ReelInk
    /// The session's name and date, drawn small at the top — the same two lines the share
    /// card's header carries, from the same `ShareCardStats`, so a card and a video of one
    /// afternoon are titled identically.
    let title: String
    let dateLine: String
    /// Whether the ground is photography, and the track therefore needs its dark outer edge
    /// (`MapStyleRecipe.needsTrackHalo`).
    let needsHalo: Bool
    /// Whether this session's speeds may be quoted at all — the live strip wears the same
    /// mark the share card does when they may not.
    let disclaimer: String?

    // MARK: - Building

    /// The scene for one session, or nil when there is no track to draw.
    ///
    /// Runs on the main actor and takes about as long as the map snapshot does; the caller
    /// shows a progress bar over it.
    @MainActor
    static func make(detail: SessionDetail, title: String, style: MapStyleChoice,
                     visibility: MapLayerVisibility, length: ReelPlan.Length) async -> ReelScene? {
        guard let span = detail.timeRange, let geography = detail.shareGeography else {
            return nil
        }

        let points = CGSize(width: size.width / snapshotScale, height: size.height / snapshotScale)
        guard let rect = ShareCardMapper.frame(source: geography, size: points,
                                               trackBox: trackBox) else { return nil }

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        // The band MapKit burns Apple's attribution into, asked for and then cropped away —
        // the same trick the share card's background plays, and the reason the framing
        // arithmetic above is shared with it rather than rewritten.
        options.size = CGSize(width: points.width,
                              height: points.height + ShareCardMapper.attributionBand)
        options.scale = snapshotScale
        // A fixed artefact, like the card: the same session exported from two phones has to
        // be the same video, whatever appearance the two riders run.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        options.preferredConfiguration = style.recipe.snapshotConfiguration
        options.showsBuildings = false

        guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
              let full = snapshot.image.cgImage else { return nil }
        // Crop the attribution band off the bottom, in pixels.
        let keep = CGRect(x: 0, y: 0, width: CGFloat(full.width), height: size.height)
        guard let ground = full.cropping(to: keep) else { return nil }

        let scale = snapshotScale
        func place(_ lat: Double, _ lon: Double) -> CGPoint {
            let p = snapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            return CGPoint(x: p.x * scale, y: p.y * scale)
        }

        // The scrubbable timeline, not the chart series: it is evenly thinned, it carries
        // positions, and its `t` is what makes a progressive draw possible at all
        // (`SessionDetail.TimelinePoint`).
        let vertices: [Vertex] = detail.timeline.compactMap { moment in
            guard let lat = moment.lat, let lon = moment.lon else { return nil }
            return Vertex(t: moment.t, point: place(lat, lon), flying: moment.flying,
                          kn: moment.kn)
        }
        guard vertices.count >= 2 else { return nil }

        var marks: [Mark] = []
        for pin in detail.turnPins {
            marks.append(Mark(t: pin.t, point: place(pin.lat, pin.lon),
                              kind: kind(of: pin.outcome), clean: pin.clean))
        }
        for splash in detail.splashMarks {
            marks.append(Mark(t: splash.t, point: place(splash.lat, splash.lon),
                              kind: .splash, clean: false))
        }
        marks.sort { $0.t < $1.t }

        let metrics = KeyMetrics.make(summary: detail.analysis.summary,
                                      records: detail.analysis.records)
        let stats = ShareCardStats.outro(row: detail.row, title: title, metrics: metrics,
                                         longestFlightS: detail.analysis.summary.longestFlightS,
                                         timeZone: detail.row.displayZone)
        guard let endCard = renderEndCard(stats: stats, outline: detail.shareOutline) else {
            return nil
        }

        return ReelScene(
            ground: ground,
            vertices: vertices,
            marks: marks,
            plan: ReelPlan.make(detail.analysis, span: span, length: length),
            endCard: endCard,
            ink: ReelInk(style: style, visibility: visibility),
            title: stats.title,
            dateLine: stats.dateLine,
            needsHalo: style.recipe.needsTrackHalo,
            disclaimer: stats.disclaimer)
    }

    /// The clip's own closing card, at the reel's size.
    ///
    /// `ReplayOutroCardView` is drawn against a 390 × 700 reference, which is 9:16 to within
    /// a percent, so it lands here without a single layout change — and using it rather than
    /// hand-drawing a card is what guarantees the call to action and the QR are *the share
    /// card's*, character for character and plate for plate, rather than a second rendering
    /// of them that can drift.
    @MainActor
    private static func renderEndCard(stats: ShareCardStats,
                                      outline: TrackThumbnail) -> CGImage? {
        let points = CGSize(width: size.width / 3, height: size.height / 3)
        let card = ReplayOutroCardView(stats: stats,
                                       thumbnail: outline.isEmpty ? nil : outline)
            .frame(width: points.width, height: points.height)
            .environment(\.colorScheme, .dark)
            .environment(\.sizeCategory, .medium)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage?.cgImage
    }

    private static func kind(of outcome: TurnOutcomeKind) -> TrackThumbnail.Mark.Kind {
        switch outcome {
        case .flewThrough: .flewThrough
        case .touchdown: .touchdown
        case .fellIn: .fellIn
        }
    }
}

/// The reel's palette, resolved once against a fixed appearance.
///
/// **Nothing here chooses a colour.** Every entry is a token or a map colour looked up
/// through the code path that already owns it — `TrackContent.color(_:on:)` for the phases
/// (which is why that function stopped being private), `TrackOutlineView.markColor` for the
/// marks, `TrackHalo.ink` for the dark edge over photography, `DesignTokens` for the
/// outcome ladder and the star. What this type adds is only the resolution: a semantic
/// `Color` means nothing to a `CGContext`, and resolving it per frame would be a main-actor
/// hop six hundred times over.
///
/// **Two appearances, deliberately.** The track and the marks are resolved **light**,
/// because that is the trait the map snapshot itself is taken with and a semantic ink means
/// "readable against the app's background" — off-foil resolved dark is a pale grey line that
/// disappears entirely on a sunlit standard map, which is what the first render of this
/// feature did. The chrome is resolved **dark**, because it is drawn on a black scrim.
/// `Brand` colours are authored RGB and do not care either way.
struct ReelInk: @unchecked Sendable {

    let flying: CGColor
    let offFoil: CGColor
    let neutral: CGColor
    let flew: CGColor
    let touchdown: CGColor
    let fellIn: CGColor
    let clean: CGColor
    let splash: CGColor
    /// The orange a record window glows in on every map (`DesignTokens.Effort.window`).
    let record: CGColor
    let paper: CGColor
    let navy: CGColor
    let halo: CGColor
    let uncertified: CGColor

    @MainActor
    init(style: MapStyleChoice, visibility: MapLayerVisibility) {
        let onMap = UITraitCollection(userInterfaceStyle: .light)
        let onScrim = UITraitCollection(userInterfaceStyle: .dark)
        func cg(_ color: Color, _ traits: UITraitCollection = onMap) -> CGColor {
            UIColor(color).resolvedColor(with: traits).cgColor
        }
        // Through `lineStyle`, so a rider who has hidden a phase on his map gets the same
        // neutral line here that his map draws (docs/presentation.md, "Layers").
        flying = cg(TrackContent.color(visibility.lineStyle(flying: true), on: style))
        offFoil = cg(TrackContent.color(visibility.lineStyle(flying: false), on: style))
        neutral = cg(TrackContent.color(.neutral, on: style))
        flew = cg(TrackOutlineView.markColor(.flewThrough))
        touchdown = cg(TrackOutlineView.markColor(.touchdown))
        fellIn = cg(TrackOutlineView.markColor(.fellIn))
        clean = cg(DesignTokens.Clean.jibe)
        splash = cg(TrackOutlineView.markColor(.splash))
        record = cg(DesignTokens.Effort.window)
        paper = cg(Brand.paper, onScrim)
        navy = cg(Brand.navy, onScrim)
        halo = cg(TrackHalo.ink, onScrim)
        uncertified = cg(.orange, onScrim)
    }

    func mark(_ kind: TrackThumbnail.Mark.Kind) -> CGColor {
        switch kind {
        case .flewThrough: flew
        case .touchdown: touchdown
        case .fellIn: fellIn
        case .splash: splash
        }
    }
}
