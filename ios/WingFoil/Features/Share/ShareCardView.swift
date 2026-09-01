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
    /// Rider-picked background. Without one the card uses the brand gradient.
    var photo: Image?

    /// Points per exported pixel. The card is laid out at 360 pt wide and rendered at 3×.
    static let renderScale: CGFloat = 3

    var size: CGSize {
        CGSize(width: shape.size.width / Self.renderScale,
               height: shape.size.height / Self.renderScale)
    }

    var body: some View {
        ZStack {
            background
            content
        }
        .frame(width: size.width, height: size.height)
        // The card is a fixed-size artwork: it must not pick up the reader's Dynamic Type
        // setting and reflow off the edge of an exported PNG.
        .environment(\.sizeCategory, .medium)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if let photo {
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
            .frame(width: size.width * 0.40)
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
        if let thumbnail, !thumbnail.points.isEmpty {
            TrackOutlineView(thumbnail: thumbnail,
                             flyingColor: flyingColor,
                             offFoilColor: offFoilColor,
                             lineWidth: 2.6,
                             offFoilScale: 0.5,
                             padding: 4,
                             fillsBox: true,
                             // 3.2 pt at the card's 3× export is a 19 px dot — the size a
                             // marker has to be to still read as a coloured verdict after a
                             // feed has resampled the picture.
                             markRadius: 3.2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: flyingColor.opacity(0.35), radius: 8)
        } else {
            Spacer(minLength: 0)
        }
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
                .background(.white.opacity(0.10), in: .rect(cornerRadius: isDense ? 9 : 12))
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
