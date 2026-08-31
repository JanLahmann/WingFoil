import SwiftUI
import WingFoilKit

/// The clip's two bookends: the card it opens on and the card it closes on.
///
/// **Why a clip needs them at all.** A screen recording of a replay starts on whatever frame
/// the recorder happened to catch and ends on whatever frame the session ended on. Sent to
/// somebody, that is a video with no beginning: the viewer sees a moving dot for two seconds
/// before working out that it is a map, and it stops without ever saying what the afternoon
/// added up to. The title card answers "where and when" before anything moves, and the outro
/// answers "so what" after everything has — which between them are the two questions the
/// replay itself is very bad at.
///
/// **Both are painted on `Brand.cardGradient`, deliberately.** It is the same surface the
/// shared card uses, so the still somebody screenshots out of the clip and the picture the
/// same rider posts an hour later are recognisably the same artefact. The stats on the outro
/// are literally the card's — `ShareCardStats`, `complete` preset — for the stronger version
/// of the same reason: two exports of one session must never name different numbers.
///
/// Neither card is laid out at a fixed size. They are drawn on the phone's own glass at
/// whatever it is, upright or landscape, and the recorder takes them as they are.

// MARK: - Opening

/// "Torbole · 30 August 2026 · 14:07", held for two and a half seconds.
///
/// The content comes from `ReplayTitleCard` in the kit rather than from two `Text`s here,
/// because it is the commentary's own opening bookend laid out instead of spoken — same place
/// string, same POSIX 24-hour clock, same long date as the share card.
struct ReplayTitleCardView: View {
    let card: ReplayTitleCard
    /// The session's own name, shown when the caller could not name a place — never both, or
    /// the card says "Torbole" twice in two type sizes.
    let fallbackTitle: String

    var body: some View {
        ZStack {
            Group {
                Brand.cardGradient
                // The same horizon glow the plain share card has, so the two surfaces are
                // one surface rather than two navy rectangles.
                RadialGradient(colors: [Brand.cyan.opacity(0.22), .clear],
                               center: .init(x: 0.5, y: 0.38),
                               startRadius: 0, endRadius: 420)
            }
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image("LaunchMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 54, height: 54)
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.bottom, 6)

                Text(card.place ?? fallbackTitle)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.paper)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)

                if !card.dateLine.isEmpty {
                    Text(card.dateLine)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Brand.paper.opacity(0.78))
                }
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel("\(card.place ?? fallbackTitle), \(card.dateLine)")
    }
}

// MARK: - Closing

/// The session in numbers, plus the two or three lines the replay already said out loud.
///
/// **The stats are the share card's, unchanged.** `ShareCardStats.make` with the `complete`
/// preset is the same pipeline `ShareComposerView` renders a PNG from, which means the outro
/// cannot round a knot differently from the card, and a change to `KeyMetrics` reaches both.
/// The *layout* is new because a phone screen is not 1080 × 1350 — but nothing on it is
/// computed here.
///
/// **The highlights are the commentary's, unchanged.** `ReplayCommentary.highlights` picks
/// them out of the same script the clip captioned forty seconds earlier, so the closing line
/// and the caption a viewer already read are the same sentence.
struct ReplayOutroCardView: View {
    let stats: ShareCardStats
    let highlights: [ReplayMilestone]
    /// The session's own outline — `SessionDetail.shareOutline`, the same geometry the
    /// exported card draws. Nil for a recording with no positions, and the card then leans on
    /// the stats, which is the honest thing to show.
    var thumbnail: TrackThumbnail?

    /// Three across on a phone in portrait: the complete block is up to eight cells, and two
    /// columns would be four rows of large type with no room for the highlights under them.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ZStack {
            // Only the paint ignores the safe area. The words must not: a clip recorded on a
            // phone with a Dynamic Island had its session title cut in half by it, and the
            // one frame of this card that anybody screenshots is the one with the title on.
            Group {
                Brand.cardGradient
                RadialGradient(colors: [Brand.cyan.opacity(0.18), .clear],
                               center: .init(x: 0.5, y: 0.28),
                               startRadius: 0, endRadius: 460)
            }
            .ignoresSafeArea()

            // Title at the top, credit at the bottom, all the slack in between: the ordinary
            // shape of a card, and the shape of the share card this one is the moving version
            // of. The top padding is on top of the safe area, not instead of it.
            VStack(alignment: .leading, spacing: 16) {
                header
                // The track absorbs the slack, exactly as it does on the exported card — and
                // for a stronger reason here. A phone screen is much taller than 1080 × 1350,
                // so a card that only carried words would close the clip on half a screen of
                // empty gradient; and the shape of the afternoon is what the viewer has spent
                // the last forty seconds watching get drawn.
                track
                statGrid
                if !highlights.isEmpty { highlightLines }
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stats.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(stats.dateLine)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Brand.paper.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Same inks and the same `fillsBox` scaling as the exported card, including the one
    /// deliberate departure from `DesignTokens.Phase`: flying is brand green rather than the
    /// map's teal, because the splash mark's token and the flying phase's are the same colour
    /// to the eye and the whole point of drawing splashes is that a reader can find them.
    @ViewBuilder
    private var track: some View {
        if let thumbnail, !thumbnail.points.isEmpty {
            TrackOutlineView(thumbnail: thumbnail,
                             flyingColor: Brand.green,
                             offFoilColor: Brand.paper.opacity(0.45),
                             lineWidth: 3,
                             offFoilScale: 0.5,
                             padding: 6,
                             fillsBox: true,
                             markRadius: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: Brand.green.opacity(0.35), radius: 10)
        } else {
            Spacer(minLength: 0)
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(stats.stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.green.opacity(0.85))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    value(of: stat)
                    if let caption = stat.caption {
                        Text(caption)
                            .font(.system(size: 9))
                            .foregroundStyle(Brand.paper.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.vertical, 7)
                .padding(.horizontal, 9)
                .background(.white.opacity(0.10), in: .rect(cornerRadius: 11))
            }
        }
    }

    /// The tally cell is the one that is not a string — the verdict ladder's own inks, the
    /// same three the share card and `KeyMetricsView` draw (`docs/presentation.md`).
    @ViewBuilder
    private func value(of stat: ShareCardStats.Stat) -> some View {
        let font = Font.system(size: 21, weight: .bold, design: .rounded)
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
            .minimumScaleFactor(0.45)
        } else {
            Text(stat.value)
                .font(font)
                .foregroundStyle(Brand.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
    }

    /// The three superlatives, as lines rather than as cells: they are sentences the viewer
    /// has already heard once, and a sentence in a stat cell reads as a truncated number.
    private var highlightLines: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(highlights) { milestone in
                HStack(spacing: 9) {
                    Image(systemName: ReplayCommentaryBubble.symbol(of: milestone.kind))
                        .font(.system(size: 15))
                        .foregroundStyle(Brand.green)
                        .frame(width: 20)
                    Text(milestone.text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 2)
    }

    /// The mark, the name, the address — the whole point of a frame somebody else sees, and
    /// the same footer the shared card carries.
    private var footer: some View {
        HStack(spacing: 8) {
            Image("LaunchMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(.rect(cornerRadius: 5))
            Text(Branding.credit)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.paper.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            if let disclaimer = stats.disclaimer {
                Text(disclaimer)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - A photo, full screen

/// One of the rider's own pictures, filling the frame while the replay waits for it.
///
/// `scaledToFill` and clipped rather than fitted: a clip is a full-bleed thing and a photo
/// letterboxed into black bars in the middle of one reads as a mistake. The scrim at the top
/// is what keeps the time chip legible over a bright sky.
struct ReplayPhotoFrame: View {
    let image: UIImage
    /// Session-clock caption, shown only for a photo that was placed *in* the session — a
    /// slideshow picture has no moment to name, which is why it is in the slideshow.
    let stamp: String?

    var body: some View {
        ZStack {
            Color.black
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
            if let stamp {
                VStack {
                    Spacer(minLength: 0)
                    Text(stamp)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Brand.paper)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: .capsule)
                        .padding(.bottom, 26)
                }
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
