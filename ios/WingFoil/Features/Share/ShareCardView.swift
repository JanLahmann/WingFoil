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

    /// The QR plate's side, in layout points — **144 exported px** at `renderScale`. The
    /// twin of `QR_SIZE` in web/js/sharecard.js; the two cards must print the same code at
    /// the same size or one of them ships a QR that is harder to scan than the other's. See
    /// `footer` for why 48 and not 32.
    static let qrSide: CGFloat = 48

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
            let column = stats.story == nil ? Self.wideColumn : Self.storyColumn
        let edge = (size.width * (1 - column) - 16) / size.width
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
            if let story = stats.story {
                if shape.isWide { storyWide(story) } else { storyTall(story) }
            } else if shape.isWide { wideContent } else { tallContent }
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
            // The session card's line carries the start time too ("29 August 2026 · 14:40").
            Text(stats.story?.dateLine ?? stats.dateLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.paper.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                        // Two lines, not one (22 September 2026): the falls tile's caption
                        // ("15 in a turn · 10 in a straight line") is the longest in the
                        // block, and at the dense four-column layout it no longer fits
                        // `.lineLimit(1)` even at the scale floor — it truncated. The card
                        // adds nothing and rewords nothing (see the type's own doc above),
                        // so the fix is room to wrap rather than a shorter word; every
                        // other caption is short enough that this is a no-op for it. A
                        // `LazyVGrid` sizes a row to its tallest cell, so a two-line falls
                        // caption grows the row it is in and every cell beside it grows
                        // with it — the row stays level, it is simply taller.
                        Text(caption)
                            .font(.system(size: isDense ? 7 : 9))
                            .foregroundStyle(Brand.paper.opacity(0.6))
                            .lineLimit(2)
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

    // MARK: - Layout B v2

    // The session card (Jan, 26 Sep 2026): header · track · hero · the outcome bars · the
    // streak line · one ribbon · the footer — the twin of `storyBoxes` / `drawStory` in
    // web/js/sharecard.js, point for point. There is no tile grid, so nothing can grow past
    // the footer the way the old eleven-tile landscape did. **The track gets every point the
    // words do not need** (Jan, 26 Sep 2026): the stack is packed from the footer up, and on
    // the square the ride takes whichever of two boxes — beside the title, or the full width
    // under it — draws it larger.

    static let heroHeight: CGFloat = 50
    static let barHeight: CGFloat = 33
    static let barGap: CGFloat = 5
    static let streakHeight: CGFloat = 16
    static let ribbonHeight: CGFloat = 30
    static let noteHeight: CGFloat = 10
    /// The landscape's word column in layout B v2 — `STORY_COLUMN` on the web.
    static let storyColumn: CGFloat = 0.43

    private func heroHeight(_ story: ShareCardStats.Story) -> CGFloat {
        guard let hero = story.hero else { return 0 }
        return Self.heroHeight + (hero.kind == .max2s && story.speedNote != nil ? Self.noteHeight : 0)
    }

    private func barsHeight(_ story: ShareCardStats.Story) -> CGFloat {
        CGFloat(story.bars.count) * (Self.barHeight + Self.barGap)
    }

    private func ribbonNote(_ story: ShareCardStats.Story) -> CGFloat {
        story.speedNote != nil && story.ribbon.contains { $0.key == ShareCardStats.Key.maxSpeed }
            ? Self.noteHeight : 0
    }

    private func hasStreak(_ story: ShareCardStats.Story) -> Bool {
        !story.streak.isEmpty || !story.falls.isEmpty
    }

    /// Whether the square puts the ride beside the title rather than under it — the one that
    /// draws it larger for this ride's own proportions (`largerBox` on the web).
    private func squareTrackBeside(_ story: ShareCardStats.Story) -> Bool {
        guard shape == .square, let box = thumbnail?.contentBox else { return false }
        let dx = max(box.maxX - box.minX, 1e-6), dy = max(box.maxY - box.minY, 1e-6)
        let inner = size.height - 14 - 12
        let headH: CGFloat = 42 + (stats.note == nil ? 0 : 14)
        let ribY = 14 + inner - ShareCardView.qrSide - 8 - Self.ribbonHeight - ribbonNote(story)
        let barsY = ribY - 6 - barsHeight(story)
        let heroY = barsY - heroHeight(story) - (story.hero == nil ? 0 : 2)
        let inset = ShareCardStats.trackInset * 2
        func scale(_ w: CGFloat, _ h: CGFloat) -> Double {
            min(Double(w - inset) / dx, Double(h - inset) / dy)
        }
        let beside = scale(size.width / 2 - 16, heroY - 2 - 12)
        let below = scale(size.width - 32, heroY - 4 - (14 + headH) - 4)
        return beside > below
    }

    private func storyTall(_ story: ShareCardStats.Story) -> some View {
        let square = shape == .square
        let beside = squareTrackBeside(story)
        return VStack(alignment: .leading, spacing: 0) {
            if beside {
                HStack(alignment: .top, spacing: 8) {
                    header.frame(width: size.width / 2 - 16 - 8, alignment: .topLeading)
                    track.padding(.top, -2)
                }
                .frame(maxHeight: .infinity)
                .padding(.bottom, 2)
            } else {
                header
                track.padding(.vertical, 4)
            }
            if story.hero != nil {
                storyHero(story).padding(.bottom, 2)
            }
            storyBars(story)
            if hasStreak(story) && !square {
                storyStreak(story)
                    .frame(height: 15, alignment: .bottomLeading)
                    .padding(.top, 2)
            }
            storyRibbon(story, valueSize: 15, width: size.width - 32)
                .padding(.top, hasStreak(story) && !square ? 8 : 6)
            footer
        }
    }

    private func storyWide(_ story: ShareCardStats.Story) -> some View {
        HStack(alignment: .top, spacing: 16) {
            track
            VStack(alignment: .leading, spacing: 0) {
                header
                if story.hero != nil { storyHero(story).padding(.top, 2) }
                storyBars(story).padding(.top, 4)
                if hasStreak(story) {
                    storyStreak(story).frame(height: 15, alignment: .bottomLeading).padding(.top, 2)
                }
                storyRibbon(story, valueSize: 14, width: size.width * Self.storyColumn)
                    .padding(.top, 10)
                Spacer(minLength: 0)
                footer
            }
            .frame(width: size.width * Self.storyColumn)
        }
    }

    /// ★ 25 clean jibes / of 56 jibes — or 13.21 kn / top speed · best 2 s, or 3 tacks.
    private func storyHero(_ story: ShareCardStats.Story) -> some View {
        let hero = story.hero!
        return HStack(alignment: .center, spacing: 8) {
            if hero.kind == .clean {
                Image(systemName: DesignTokens.Glyph.cleanJibe)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DesignTokens.Clean.jibe)
            }
            Text(hero.value)
                .font(.system(size: 58, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(hero.unit)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(hero.kind == .clean ? DesignTokens.Clean.jibe : Brand.paper)
                Text(hero.sub)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Brand.paper.opacity(0.75))
                if hero.kind == .max2s, let note = story.speedNote {
                    Text(note)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.95))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .frame(height: heroHeight(story))
    }

    private func storyBars(_ story: ShareCardStats.Story) -> some View {
        VStack(alignment: .leading, spacing: Self.barGap) {
            ForEach(Array(story.bars.enumerated()), id: \.offset) { _, bar in
                storyBar(bar, legend: story.legend)
            }
        }
    }

    /// One outcome bar: its name and caption, the bar, and the three counts in the ladder's
    /// colours. A zero is dimmed, not dropped, so two bars' legends line up.
    private func storyBar(_ bar: ShareCardStats.Story.Bar, legend: [String]) -> some View {
        let parts: [(Int, Color, String)] = [
            (bar.flewThrough, DesignTokens.Outcome.flew, (legend.count > 0 ? legend[0] : "")),
            (bar.touchdown, DesignTokens.Outcome.touchdown, (legend.count > 1 ? legend[1] : "")),
            (bar.fellIn, DesignTokens.Outcome.fellIn, (legend.count > 2 ? legend[2] : "")),
        ]
        let total = max(bar.total, 1)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(bar.label.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Brand.green.opacity(0.95))
                Spacer(minLength: 4)
                if let right = bar.right {
                    Text(right)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Brand.paper.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if bar.star {
                        Image(systemName: DesignTokens.Glyph.cleanJibe)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DesignTokens.Clean.jibe)
                    }
                }
            }
            .frame(height: 10)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        parts[i].1.frame(width: geo.size.width * CGFloat(parts[i].0) / CGFloat(total))
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .background(Brand.paper.opacity(0.12))
                .clipShape(.capsule)
            }
            .frame(height: 7)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(parts[i].0)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(parts[i].1)
                        Text(parts[i].2)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Brand.paper.opacity(0.78))
                    }
                    .opacity(parts[i].0 == 0 ? 0.45 : 1)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(height: Self.barHeight, alignment: .top)
    }

    private func storyInk(_ role: String) -> Color {
        switch role {
        case "paper": Brand.paper
        case "flew": DesignTokens.Outcome.flew
        case "fell": DesignTokens.Outcome.fellIn
        default: Brand.paper.opacity(0.75)
        }
    }

    /// "best streak 7 flew · 11 dry     fell in 25 times", each number in its ink.
    private func storyStreak(_ story: ShareCardStats.Story) -> some View {
        var runs = story.streak
        if !story.streak.isEmpty && !story.falls.isEmpty {
            runs.append(.init(text: "     ", role: "muted"))
        }
        runs += story.falls
        let line = runs.reduce(Text("")) { text, run in
            text + Text(run.text)
                .font(.system(size: run.role == "muted" ? 9.5 : 11,
                              weight: run.role == "muted" ? .medium : .bold))
                .foregroundColor(storyInk(run.role))
        }
        return line.lineLimit(1).minimumScaleFactor(0.6)
    }

    /// The ribbon: the rates in words first, then max 2 s, duration and distance.
    private func storyRibbon(_ story: ShareCardStats.Story, valueSize: CGFloat,
                             width: CGFloat) -> some View {
        // Fixed cell widths, the web's `cw`: an intrinsic layout lets one long label take the
        // width — and the type size — of the number under it.
        let cellW = width / CGFloat(max(story.ribbon.count, 1))
        return VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(Brand.paper.opacity(0.18)).frame(height: 0.5)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(story.ribbon.enumerated()), id: \.offset) { i, cell in
                    HStack(spacing: 0) {
                        if i > 0 {
                            Rectangle().fill(Brand.paper.opacity(0.18))
                                .frame(width: 0.5, height: valueSize + 11)
                                .padding(.trailing, 6.5)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cell.label)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Brand.green.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(cell.value)
                                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                                .foregroundStyle(cell.clean ? DesignTokens.Clean.jibe : Brand.paper)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(width: cellW, alignment: .leading)
                }
            }
            .padding(.top, 4)
            if ribbonNote(story) > 0, let note = story.speedNote {
                // Next to the speed it qualifies: under the ribbon, from the max 2 s cell on.
                let index = story.ribbon.firstIndex { $0.key == ShareCardStats.Key.maxSpeed } ?? 0
                GeometryReader { geo in
                    Text(note)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.leading, geo.size.width * CGFloat(index)
                                 / CGFloat(max(story.ribbon.count, 1)) + (index > 0 ? 7 : 0))
                }
                .frame(height: Self.noteHeight)
            }
        }
        // Its own height, never squeezed: a proposed height shorter than the two lines would
        // shrink the numbers through their scale factor.
        .fixedSize(horizontal: false, vertical: true)
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
    /// subtitle stack into that height beside it.
    ///
    /// **48 pt, not 32** (Jan, 14 Sep 2026; the web changed first, `QR_SIZE` in
    /// web/js/sharecard.js). 32 pt exported at 96 px, and 96 px is the floor at which a phone
    /// camera can frame a code *photographed off somebody else's screen in a chat thread* —
    /// which is the only way this code is ever read. A floor is not a target: a card shared
    /// into a group, screenshotted, forwarded and re-compressed spends that margin twice
    /// over. 48 pt exports at 144 px and buys back a whole re-share. It costs 16 pt of the
    /// footer's height, which comes out of the track box on the tall shapes and out of the
    /// wordmark's width on the wide one; both are checked at all three shapes, and the
    /// wordmark's `minimumScaleFactor` absorbs what is left.
    private var footer: some View {
        // Layout B v2 (Jan, 26 Sep 2026): the mark at 30 pt, and "CleanJibe · cleanjibe.org"
        // at 16 pt ABOVE the tagline — the name and the address are what a stranger has to
        // remember. The twin of `drawFooter` in web/js/sharecard.js.
        HStack(alignment: .center, spacing: 9) {
            Image("LaunchMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .clipShape(.rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                (Text(Branding.appName).foregroundColor(Brand.paper)
                    + Text(" · " + Branding.site).foregroundColor(Brand.green))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Branding.tagline)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Brand.paper.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 4)
            // The session card draws its speed note next to the speed instead.
            if stats.story == nil, let disclaimer = stats.disclaimer {
                Text(disclaimer)
                    .font(.system(size: 7.5))
                    .foregroundStyle(.orange.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            BrandQRCode(size: ShareCardView.qrSide)
        }
        .padding(.top, 4)
    }
}
