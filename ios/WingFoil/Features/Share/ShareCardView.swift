import SwiftUI
import WingFoilKit

/// The shareable session card, as a plain SwiftUI view.
///
/// Kept a *view* (rather than Core Graphics drawing code) so `ImageRenderer` can export it
/// at any scale and so it can be previewed and screenshotted like anything else. Its
/// content comes pre-resolved from `ShareCardStats`, which is where the "—" decisions, the
/// preset filtering and the uncertified disclaimer are made — an image cannot fall back at
/// draw time.
///
/// Layout is expressed against `ShareCardStats.Shape.size` divided by `renderScale`, so
/// one set of paddings works for every aspect ratio and the exported pixels land exactly
/// on 1080 × 1350 / 1080 × 1080 / 1920 × 1080.
///
/// The wide shape gets a *column* layout rather than the tall shapes' stack: at 1920 × 1080
/// a track stretched across the full width leaves the stat block a 200 px strip, and the
/// title reads as a caption under a banner. Beside the stats the same track is square-ish
/// and the block is a readable column — same tokens, same type sizes, only the axis
/// changes (`ShareCardStats.Shape.isWide`).
///
/// **The track is the card.** It used to get whatever height the fixed 2 × 2 stat block
/// left over, and then inscribe its own square normalization into that — so a session
/// sailed up and down one reach drew as a thin line in the middle of a small square in the
/// middle of a wide gap. Three things fixed it: the block is denser and its column count
/// follows the stat count, the paddings came in, and `TrackOutlineView.fillsBox` scales the
/// *ride* to the box instead of the box it was normalized into.
struct ShareCardView: View {
    let stats: ShareCardStats
    let shape: ShareCardStats.Shape
    /// Track outline; nil for a recording with no positions (the card then leans on the
    /// stats, which is the honest thing to show).
    var thumbnail: TrackThumbnail?
    /// The **period** card's artwork: every session's outline, stacked in one box.
    ///
    /// A period has no single ride to draw, and picking one would be picking a favourite.
    /// What it has is a shape — a week at one spot is a dozen tracks over the same water —
    /// so all of them go down, faint, and the picture is the accumulation. Empty on a
    /// session card, which is every card this view drew before periods existed.
    var thumbnails: [TrackThumbnail] = []
    /// Rider-picked background. Without one the card uses the brand gradient.
    var photo: Image?
    /// The optional map background and the track already projected onto it
    /// (`ShareCardMap`). Nil is the card this app has always exported.
    var map: ShareCardMap?
    /// Where the layout put the track, reported back so the *next* snapshot can be framed to
    /// land in exactly that rectangle. See `ShareCardMap` for why the card measures instead
    /// of recomputing: SwiftUI's own arithmetic is the only copy of it that is certainly
    /// right, and a map framed against a second copy of the layout would drift a few points
    /// every time the stat block changed.
    var onTrackFrame: ((CGRect) -> Void)?

    /// Points per exported pixel. The card is laid out at 360 pt wide and rendered at 3×.
    static let renderScale: CGFloat = 3

    /// The card's own coordinate space, so the track's frame can be reported in the same
    /// points the snapshot is drawn in.
    static let cardSpace = "shareCard"

    var size: CGSize {
        CGSize(width: shape.size.width / Self.renderScale,
               height: shape.size.height / Self.renderScale)
    }

    var body: some View {
        ZStack {
            background
            // Above the ground and below the words: the breadcrumb runs past its own box
            // into the map's margins, where the header and the footer have to stay on top
            // of it.
            if let map { mapTrack(map) }
            content
            if map != nil { credit }
        }
        .coordinateSpace(.named(Self.cardSpace))
        .frame(width: size.width, height: size.height)
        // The card is a fixed-size artwork: it must not pick up the reader's Dynamic Type
        // setting and reflow off the edge of an exported PNG.
        .environment(\.sizeCategory, .medium)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if let map {
            // Sized to the snapshot and then cropped to the card, top-pinned: the extra band
            // at the bottom carries Apple's burnt-in attribution, which the card prints for
            // itself where nothing covers it. See `ShareCardMapper.attributionBand`.
            Image(uiImage: map.image)
                .resizable()
                .frame(width: size.width,
                       height: size.height + ShareCardMapper.attributionBand)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
            mapScrim
        } else if let photo {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
            // A photo is whatever the rider shot — bright sky, white water, a dark
            // evening. The scrim is what guarantees the text is legible on all of them,
            // and it is stronger at the ends where the text actually sits.
            LinearGradient(
                stops: [.init(color: .black.opacity(0.72), location: 0),
                        .init(color: .black.opacity(0.30), location: 0.42),
                        .init(color: .black.opacity(0.78), location: 1)],
                startPoint: .top, endPoint: .bottom)
        } else {
            Brand.cardGradient
            // A faint horizon glow, so the plain card is not a flat rectangle.
            RadialGradient(colors: [Brand.cyan.opacity(0.22), .clear],
                           center: .init(x: 0.5, y: 0.34),
                           startRadius: 0, endRadius: size.width * 0.75)
        }
    }

    /// What keeps the card readable over a photograph of a coastline.
    ///
    /// Two layers, and both earn their place. A flat navy wash first, so the map's own greens
    /// and ochres are pulled towards the card's palette and the phase tints — brand green for
    /// flying, paper for off foil — are again the only saturated thing on the picture. Then a
    /// vertical gradient, heavier at the two ends where every word actually sits and lightest
    /// across the middle, where the track is and where a rider wants to see the shore he
    /// sailed off.
    ///
    /// The wide shape gets a third pass, because its words are a column on the right rather
    /// than two bands. It is a *panel*, not a ramp: a gradient still brightening at the
    /// right-hand edge leaves the last stat cell and the QR sitting on whatever the map put
    /// there. It fades in over 70 points so the panel's edge is not a seam down the middle of
    /// the picture.
    ///
    /// The opacities are the twins of `drawScrim` in web/js/sharecard.js, set by eye against
    /// the worst ground either platform produces — a town's white building fill under the
    /// footer — and not against open water, which needs about half of this.
    @ViewBuilder
    private var mapScrim: some View {
        Brand.navy.opacity(0.34)
        LinearGradient(
            stops: [.init(color: .black.opacity(0.70), location: 0),
                    .init(color: .black.opacity(0.34), location: 0.30),
                    .init(color: .black.opacity(0.38), location: 0.62),
                    .init(color: .black.opacity(0.80), location: 1)],
            startPoint: .top, endPoint: .bottom)
        if shape.isWide {
            let edge = (size.width * (1 - Self.wideColumn) - 16) / size.width
            LinearGradient(
                stops: [.init(color: .black.opacity(0), location: max(edge - 70 / size.width, 0)),
                        .init(color: .black.opacity(0.55), location: edge),
                        .init(color: .black.opacity(0.55), location: 1)],
                startPoint: .leading, endPoint: .trailing)
        }
    }

    /// The wide shape's word column, as a fraction of the card — the number `wideContent`
    /// lays out against, named so the scrim can darken exactly that strip.
    static let wideColumn: CGFloat = 0.40

    /// The breadcrumb, in the map's own projection, over the whole card.
    ///
    /// Deliberately *not* `TrackOutlineView`: that view fits a normalized outline to a box,
    /// which is the one thing a mapped track may not do. The vocabulary is shared instead —
    /// `markPath` and `markColor` are the same static functions the library row and the plain
    /// card draw through, so a dot means the same thing on every surface.
    private func mapTrack(_ map: ShareCardMap) -> some View {
        Canvas(opaque: false) { context, _ in
            for run in map.runs {
                var path = Path()
                path.addLines(run.points)
                let width = run.flying ? map.lineWidth : map.lineWidth * 0.5
                if map.needsHalo {
                    // Over photography only, and by the map's own rule: a foil-green line on
                    // sunlit chop is not legible without a dark outer edge.
                    context.stroke(path, with: .color(TrackHalo.ink),
                                   style: StrokeStyle(lineWidth: TrackHalo.width(under: width),
                                                      lineCap: .round, lineJoin: .round))
                }
                // `map.opacity` is 1 for a session and the stack's own for a period, where a
                // dozen breadcrumbs on one ground have to read as one shape.
                let ink = run.flying ? flyingColor : offFoilColor.opacity(0.55)
                context.stroke(
                    path, with: .color(ink.opacity(map.opacity)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            // Splashes last, so the one mark that is *evidence* rather than a verdict sits on
            // top of the verdict it belongs to instead of hiding under it.
            let ordered = map.marks.sorted { ($0.kind == .splash ? 1 : 0)
                                           < ($1.kind == .splash ? 1 : 0) }
            for mark in ordered {
                let shape = TrackOutlineView.markPath(mark.kind, at: mark.point,
                                                      radius: Self.markRadius)
                context.stroke(shape, with: .color(.black.opacity(0.55)),
                               style: StrokeStyle(lineWidth: Self.markRadius * 0.75))
                context.fill(shape, with: .color(TrackOutlineView.markColor(mark.kind)))
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: flyingColor.opacity(0.35), radius: 8)
        .accessibilityHidden(true)
    }

    /// 3.2 pt at the card's 3× export is a 19 px dot — the size a marker has to be to still
    /// read as a coloured verdict after a feed has resampled the picture.
    static let markRadius: Double = 3.2

    /// The map's required credit, where it costs the card nothing.
    ///
    /// **Top-trailing on the tall shapes.** The bottom-trailing corner is the QR's, and a
    /// decoder that has to find three finder patterns in a photograph of a phone screen does
    /// not need six points of grey type against its quiet zone; the bottom-leading corner is
    /// the mark and the call to action, which is the line the whole card exists to carry. That
    /// leaves the corner opposite the title, and the title is told to stop short of it
    /// (`header`) so the two can never collide — a card is a PNG, and overlapping type on one
    /// is permanent.
    ///
    /// **Bottom-leading on the wide shape**, where every word is in the right-hand column and
    /// the corner under the track is empty. Its header has 40 % of the card to work in and
    /// cannot afford to give a credit any of it.
    private var credit: some View {
        Text(ShareCardMap.credit)
            .font(.system(size: 6.5, weight: .medium))
            .foregroundStyle(Brand.paper.opacity(0.62))
            .padding(.horizontal, 16)
            .padding(.vertical, shape.isWide ? 12 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: shape.isWide ? .bottomLeading : .topTrailing)
    }

    /// The room the credit needs beside the title, on the shapes where it sits in the top
    /// corner. Reserved as padding rather than measured, because the credit is one fixed
    /// string at one fixed size and a card is not a place to discover a collision.
    private var titleTrailingInset: CGFloat {
        map != nil && !shape.isWide ? 54 : 0
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        Group {
            if shape.isWide { wideContent } else { tallContent }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var tallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            // The track absorbs whatever height is left over, so the stat block and the
            // footer are never pushed off the bottom of a fixed-size export.
            track
            statGrid
            footer
        }
    }

    /// Track left, everything that is words right. The right column is a fixed fraction of
    /// the card rather than intrinsic width, so the stat cells are the same size on a wide
    /// card as on a tall one and the track always gets the remainder — including the whole
    /// card when a recording has no positions at all.
    private var wideContent: some View {
        HStack(alignment: .top, spacing: 16) {
            track
            VStack(alignment: .leading, spacing: 8) {
                header
                statGrid
                Spacer(minLength: 0)
                footer
            }
            .frame(width: size.width * Self.wideColumn)
        }
    }

    /// Name, date, and — when the rider wrote one — his own caption.
    ///
    /// **The caption is the only thing on this card addressed by the sender to the reader.**
    /// Everything else is either a measurement or the footer's offer. So it sits directly
    /// under the two lines that say which afternoon this is, in the same subordinate ink as
    /// the date, and it costs the track about fourteen points of height — which the tall
    /// layout takes out of the track's remainder and the wide layout out of the column's
    /// slack. Absent, the header is the two lines it has always been and nothing moves.
    ///
    /// It shrinks rather than truncating, by the rule the whole card follows: an ellipsis in
    /// a PNG is permanent, three points of type size are only small. At the 80-character cap
    /// (`SessionNaming.noteLimit`) the floor is never reached on any shape — the wide card's
    /// 40 % column is the tightest, and a full-length caption lands there around 6.5 pt,
    /// which is 19 px in an exported 1920-pixel image.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stats.title)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Room for the map credit in the corner above it. It shrinks the title rather
                // than moving it, by the rule the whole card follows.
                .padding(.trailing, titleTrailingInset)
            Text(stats.dateLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.paper.opacity(0.72))
            if let note = stats.note {
                Text(note)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Brand.paper.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The track

    /// Phase tints, with one deliberate departure from `DesignTokens.Phase`.
    ///
    /// Off foil is `.secondary` in the tokens — a *system* semantic colour, which has no
    /// defined value over a surface the app paints itself, so the card substitutes its own
    /// paper at the same subordinate weight.
    ///
    /// Flying is brand green rather than the map's teal, and this one is load-bearing: the
    /// splash mark's token (`Effort.splash`, #3fc4d8) and the flying phase's (#40c8e0) are
    /// the same colour to the eye, and the whole point of drawing splashes here is that a
    /// reader can find them. On the map the two never touch, because the splash sits on a
    /// glyph and the phase on a line under a dozen other layers; on a 1080 px card with
    /// three semantics and nothing else, they would be one colour.
    private var flyingColor: Color { Brand.green }
    private var offFoilColor: Color { Brand.paper.opacity(0.45) }

    @ViewBuilder
    private var track: some View {
        if !thumbnails.isEmpty {
            Group {
                // With a ground under it the whole stack is drawn by `mapTrack` instead, in
                // the map's own projection and over the whole card. The slot stays, at exactly
                // the size it had, because nothing else on the card may move when the switch
                // is flipped — and because the snapshot is framed against this rectangle.
                if map == nil { stack } else { Color.clear }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(Self.cardSpace))
            } action: { onTrackFrame?($0) }
        } else if let thumbnail, !thumbnail.points.isEmpty {
            Group {
                if map == nil {
                    TrackOutlineView(thumbnail: thumbnail,
                                     flyingColor: flyingColor,
                                     offFoilColor: offFoilColor,
                                     lineWidth: 2.6,
                                     offFoilScale: 0.5,
                                     padding: 4,
                                     fillsBox: true,
                                     markRadius: Self.markRadius)
                        .shadow(color: flyingColor.opacity(0.35), radius: 8)
                } else {
                    // Drawn by `mapTrack` instead, over the whole card and in the map's own
                    // projection. The slot stays, at exactly the size it had, because the
                    // header, the stat block and the footer must not move when the switch is
                    // flipped — and because the snapshot is framed against this rectangle.
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(Self.cardSpace))
            } action: { onTrackFrame?($0) }
        } else {
            Spacer(minLength: 0)
        }
    }

    /// The period's outlines, laid on one another **at one metres scale**.
    ///
    /// Every outline is un-normalized back to metres through the extent its thumbnail now
    /// carries (`TrackThumbnail.metres(x:y:)`), and all of them go through one placer fitted
    /// to the union of those extents (`TrackStack.placement`). So a half-hour paddle draws
    /// small inside a three-hour reach rather than being stretched to match it, and a week at
    /// one spot laid over itself is recognisably that beach.
    ///
    /// It used to stack `TrackOutlineView`s, each normalized against its own extent: they
    /// shared a box and a centre and not a scale, so twelve afternoons of twelve different
    /// lengths came out twelve identical sizes. That was the follow-up the contract named, and
    /// this is it — pinned against the browser's own arithmetic by
    /// `fixtures/periods/outlines.expected.json`.
    ///
    /// No marks: fifty outcome dots per session times a dozen sessions is confetti, and the
    /// card's own numbers already say how the maneuvers went.
    private var stack: some View {
        Canvas(opaque: false) { context, size in
            let extents = thumbnails.compactMap(\.stackExtent)
            guard let placement = TrackStack.placement(
                of: extents, in: TrackStack.Box(x: 0, y: 0, w: size.width, h: size.height),
                inset: ShareCardStats.trackInset) else { return }
            // Faint enough that a dozen read as one shape rather than a scribble; the overlap
            // is what draws the eye, so the water everything was ridden over comes out
            // brightest. Per stroke rather than per layer, which is what the web's
            // `globalAlpha` does and therefore the same picture.
            let alpha = TrackStack.opacity(count: thumbnails.count)
            for thumbnail in thumbnails {
                for run in thumbnail.runs {
                    let placed = run.points.compactMap { point -> CGPoint? in
                        guard let m = thumbnail.metres(x: point.x, y: point.y) else {
                            return nil
                        }
                        let p = placement.place(x: m.x, y: m.y)
                        return CGPoint(x: p.x, y: p.y)
                    }
                    guard placed.count >= 2 else { continue }
                    var path = Path()
                    path.addLines(placed)
                    let ink = run.flying ? flyingColor : offFoilColor.opacity(0.55)
                    context.stroke(
                        path, with: .color(ink.opacity(alpha)),
                        style: StrokeStyle(lineWidth: run.flying ? 1.8 : 1.8 * 0.5,
                                           lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - The stats

    /// Four across once the block is more than a headline. The complete key-metrics block
    /// is up to eight cells; at two columns that is four rows and a card with no room left
    /// for the ride it is about.
    private var columnCount: Int {
        shape.isWide || stats.stats.count <= 4 ? 2 : 4
    }

    /// Smaller type and tighter cells for the full block — the same trade the block itself
    /// makes on the phone, where eight numbers do not get eight headlines.
    private var isDense: Bool { stats.stats.count > 4 }

    private var statGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(),
                                                     spacing: isDense ? 5 : 10),
                                 count: columnCount),
                  spacing: isDense ? 5 : 10) {
            ForEach(stats.stats) { stat in
                VStack(alignment: .leading, spacing: 1) {
                    Text(stat.label)
                        .font(.system(size: isDense ? 7.5 : 9, weight: .semibold))
                        .foregroundStyle(Brand.green.opacity(0.85))
                        .tracking(0.3)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    value(of: stat)
                    if let caption = stat.caption {
                        Text(caption)
                            .font(.system(size: isDense ? 7 : 9))
                            .foregroundStyle(Brand.paper.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.vertical, isDense ? 4 : 8)
                .padding(.horizontal, isDense ? 6 : 10)
                                // White at a tenth over the brand gradient — which is how the card has
                // always drawn it — but the *opposite* direction over a map: a translucent
                // white plate over a town's white building fill is not a plate at all, and
                // the eight numbers are the half of the card a reader actually reads.
                .background(map == nil ? AnyShapeStyle(.white.opacity(0.10))
                                       : AnyShapeStyle(.black.opacity(0.34)),
                            in: .rect(cornerRadius: isDense ? 9 : 12))
            }
        }
    }

    /// The tally cell is the one that is not a string: its three counts are drawn on the
    /// verdict ladder's own inks, the same way `KeyMetricsView` draws them in the app. Every
    /// other cell is `stat.value` and nothing else.
    /// How far a value may shrink before it truncates. The block's longest string by far is
    /// the streaks pair ("5 flew · 11 dry"), and a card is an image: an ellipsis on it is
    /// permanent, where three points of type size are only small. At the dense floor it
    /// still exports at 21 px.
    private var valueFloor: Double { isDense ? 0.45 : 0.6 }

    @ViewBuilder
    private func value(of stat: ShareCardStats.Stat) -> some View {
        let font = Font.system(size: isDense ? 16 : 21, weight: .bold, design: .rounded)
        if let tally = stat.tally {
            HStack(spacing: 3) {
                Text("\(tally.flewThrough)").foregroundStyle(DesignTokens.Outcome.flew)
                Text("·").foregroundStyle(Brand.paper.opacity(0.45))
                Text("\(tally.touchdown)").foregroundStyle(DesignTokens.Outcome.touchdown)
                Text("·").foregroundStyle(Brand.paper.opacity(0.45))
                Text("\(tally.fellIn)").foregroundStyle(DesignTokens.Outcome.fellIn)
            }
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(valueFloor)
        } else {
            Text(stat.value)
                .font(font)
                .foregroundStyle(Brand.paper)
                .lineLimit(1)
                .minimumScaleFactor(valueFloor)
        }
    }

    // MARK: - Footer

    /// The mark, the name, the invitation and the code — the whole point of a card someone
    /// else sees, and the same four things in the same order as the web card's footer
    /// (`docs/presentation.md`, the card contract). A rider who is sent this picture is the
    /// audience the app has: the footer is the only part of it addressed to him rather than
    /// to the person who made it.
    ///
    /// `LaunchMark` is the app-icon artwork as an ordinary image asset (the launch screen
    /// already needs it as one, because `AppIcon` cannot be loaded outside the icon slot).
    /// Its corners are rounded in the artwork itself; the clip is belt and braces so the
    /// square backing can never show through at an export scale.
    ///
    /// The QR is trailing on every shape, which is where it fits without moving anything:
    /// the footer row was 18 pt of mark against 300-odd pt of slack, and the wordmark and its
    /// subtitle stack into that height beside it. 32 pt exports at 96 px — see `BrandQRCode`
    /// for why the number matters.
    private var footer: some View {
        HStack(alignment: .center, spacing: 7) {
            Image("LaunchMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(.rect(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 0) {
                Text(Branding.appName)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Branding.callToAction)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Brand.paper.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            Spacer(minLength: 4)
            if let disclaimer = stats.disclaimer {
                Text(disclaimer)
                    .font(.system(size: 7.5))
                    .foregroundStyle(.orange.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            BrandQRCode(size: 32)
        }
        .padding(.top, 4)
    }
}
