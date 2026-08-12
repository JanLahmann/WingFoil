import SwiftUI
import WingFoilKit

/// The shareable session card, as a plain SwiftUI view.
///
/// Kept a *view* (rather than Core Graphics drawing code) so `ImageRenderer` can export it
/// at any scale and so it can be previewed and screenshotted like anything else. Its
/// content comes pre-resolved from `ShareCardStats`, which is where the "—" decisions and
/// the uncertified disclaimer are made — an image cannot fall back at draw time.
///
/// Layout is expressed against `ShareCardStats.Shape.size` divided by `renderScale`, so
/// one set of paddings works for both aspect ratios and the exported pixels land exactly
/// on 1080 × 1350 / 1080 × 1080.
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // The track absorbs whatever height is left over, so the stat block and the
            // footer are never pushed off the bottom of a fixed-size export.
            track
            statGrid
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stats.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(stats.dateLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brand.paper.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var track: some View {
        if let thumbnail, !thumbnail.points.isEmpty {
            TrackOutlineView(thumbnail: thumbnail,
                             flyingColor: Brand.green,
                             offFoilColor: Brand.paper.opacity(0.45),
                             lineWidth: 2.4,
                             offFoilScale: 0.5,
                             padding: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: Brand.green.opacity(0.35), radius: 8)
        } else {
            Spacer(minLength: 0)
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                  spacing: 10) {
            ForEach(stats.stats) { stat in
                VStack(alignment: .leading, spacing: 1) {
                    Text(stat.label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Brand.green.opacity(0.85))
                        .tracking(0.6)
                    Text(stat.value)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.paper)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(stat.caption ?? " ")
                        .font(.system(size: 9))
                        .foregroundStyle(Brand.paper.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(.white.opacity(0.10), in: .rect(cornerRadius: 12))
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let turnLine = stats.turnLine {
                HStack(spacing: 6) {
                    Text("TURNS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Brand.green.opacity(0.85))
                        .tracking(0.6)
                    Text(turnLine)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.paper.opacity(0.9))
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "water.waves")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.green)
                Text("WingFoil")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.paper.opacity(0.9))
                Spacer()
                if let disclaimer = stats.disclaimer {
                    Text(disclaimer)
                        .font(.system(size: 8))
                        .foregroundStyle(.orange.opacity(0.9))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.top, 12)
    }
}
