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
        GeometryReader { geometry in
            // A 16:9 clip on an upright phone is a 242 pt-tall box, and 40 pt of rounded bold
            // over a 54 pt mark does not fit in it. The card is the same card, drawn smaller —
            // same proportions, same spacing, so the opening frame of a wide clip and of a
            // tall one are recognisably one design.
            let scale = min(1.1, max(0.55, min(geometry.size.width / 390,
                                               geometry.size.height / 500)))
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

                VStack(spacing: 14 * scale) {
                    Image("LaunchMark")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 54 * scale, height: 54 * scale)
                        .clipShape(.rect(cornerRadius: 12 * scale))
                        .padding(.bottom, 6 * scale)

                    Text(card.place ?? fallbackTitle)
                        .font(.system(size: 40 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.paper)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    if !card.dateLine.isEmpty {
                        Text(card.dateLine)
                            .font(.system(size: 19 * scale, weight: .medium))
                            .foregroundStyle(Brand.paper.opacity(0.78))
                    }
                }
                .padding(.horizontal, 32 * scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement()
        .accessibilityLabel("\(card.place ?? fallbackTitle), \(card.dateLine)")
    }
}

// MARK: - Closing

/// The session in numbers — nine cells, three by three, and nothing else.
///
/// **The stats are the share card's, unchanged.** `ShareCardStats.outro` builds on the same
/// `complete` pipeline `ShareComposerView` renders a PNG from, which means the closing frame
/// cannot round a knot differently from the exported card, and a change to `KeyMetrics`
/// reaches both. The *layout* is new because a phone screen is not 1080 × 1350 — but nothing
/// on it is computed here.
///
/// **Why the highlight lines are gone.** The card used to print the grid and then two or
/// three sentences under it, lifted out of the commentary: "Top speed — 13.47 kn over 2 s"
/// under a max-2 s cell reading 13.47, "New streak — 8 dry jibes" under a streaks cell reading
/// 8. Two thirds of the closing card was the closing card again, in words. The one superlative
/// the grid did *not* carry was the longest flight — so it became the ninth cell, the lines
/// went, and the grid came out square.
///
/// **It lays out for the frame it is in, not for the phone.** A clip can now be 9:16, 1:1,
/// 16:9 or the whole glass (`ReplayFraming`), and a 16:9 box on an upright phone is 242 pt
/// tall. So the track sits *beside* the numbers when the frame is wide and above them when it
/// is tall — the same question `ShareCardStats.Shape.isWide` asks the exported card — and the
/// type scales with the box rather than assuming a screen's worth of room.
struct ReplayOutroCardView: View {
    let stats: ShareCardStats
    /// The session's own outline — `SessionDetail.shareOutline`, the same geometry the
    /// exported card draws. Nil for a recording with no positions, and the card then leans on
    /// the stats, which is the honest thing to show.
    var thumbnail: TrackThumbnail?
    /// Whether the frame is wider than it is tall. Asked of `ReplayFraming.isWide` upstream so
    /// this view never has to know which framing produced it.
    var isWide = false

    /// Three across, whatever the shape: nine cells is three rows of three in a tall frame and
    /// three rows of three beside the track in a wide one. Two columns would be five rows of
    /// large type; four would put "flew · touchdown · fell" in a column 60 pt wide.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    /// The box the card was designed against — an upright phone's glass. Everything below is
    /// scaled by how much of it this frame actually has, so a 16:9 letterbox gets the same
    /// card at a legible size instead of the same card with its title cut off.
    private static let reference = CGSize(width: 390, height: 700)

    var body: some View {
        GeometryReader { geometry in
            let scale = scale(for: geometry.size)
            ZStack {
                // Only the paint ignores the safe area. The words must not: a clip recorded on
                // a phone with a Dynamic Island had its session title cut in half by it, and
                // the one frame of this card that anybody screenshots is the one with the
                // title on. (Inside a letterboxed stage the paint is already clipped to the
                // box, and `ignoresSafeArea` then costs nothing.)
                Group {
                    Brand.cardGradient
                    RadialGradient(colors: [Brand.cyan.opacity(0.18), .clear],
                                   center: .init(x: 0.5, y: 0.28),
                                   startRadius: 0, endRadius: 460)
                }
                .ignoresSafeArea()

                // Title at the top, credit at the bottom, all the slack in between: the
                // ordinary shape of a card, and the shape of the share card this one is the
                // moving version of. The top padding is on top of the safe area, not instead
                // of it.
                VStack(alignment: .leading, spacing: 16 * scale) {
                    header(scale)
                    content(scale)
                    // In a wide frame the credit rides under the track instead — see
                    // `content`. Repeating it here would print it twice.
                    if !isWide { footer(scale) }
                }
                .padding(.horizontal, 22 * scale)
                .padding(.top, 18 * scale)
                .padding(.bottom, 14 * scale)
            }
        }
    }

    /// How much of the reference card this frame has room for, clamped so a very small box
    /// gets small type rather than unreadable type and a very large one does not blow the
    /// card up past the proportions it was drawn at.
    private func scale(for box: CGSize) -> CGFloat {
        guard box.width > 0, box.height > 0 else { return 1 }
        let byWidth = box.width / Self.reference.width
        let byHeight = box.height / Self.reference.height
        // The height is the binding dimension in a letterbox and the width in a pillarbox, so
        // the smaller of the two is the honest answer — but the height gets a floor of its
        // own, because a 16:9 frame is short by design rather than cramped.
        return min(1.15, max(0.55, min(byWidth, max(byHeight, byWidth * 0.72))))
    }

    /// The track and the numbers, arranged for the shape of the frame.
    ///
    /// Wide: side by side, exactly as the exported landscape card puts the outline beside the
    /// stats — a 16:9 box has no vertical room to stack them and the track would come out a
    /// 30 pt sliver. Tall: stacked, with the track absorbing the slack, because the shape of
    /// the afternoon is what the viewer has spent the last forty seconds watching get drawn.
    ///
    /// **The credit moves with the layout.** In a tall frame it is the bottom rule, under
    /// everything. In a wide one there is no room for a rule under a three-row grid — the
    /// first version of this clipped it clean off the bottom of a 16:9 box — so it goes where
    /// the wide layout actually has space, under the track.
    @ViewBuilder
    private func content(_ scale: CGFloat) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: 16 * scale) {
                VStack(alignment: .leading, spacing: 8 * scale) {
                    track
                    footer(scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                statGrid(scale)
                    .frame(maxWidth: .infinity)
            }
        } else {
            track
            statGrid(scale)
        }
    }

    private func header(_ scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(stats.title)
                .font(.system(size: 30 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(stats.dateLine)
                .font(.system(size: 14 * scale, weight: .medium))
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

    private func statGrid(_ scale: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: 8 * scale) {
            ForEach(stats.stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.label)
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundStyle(Brand.green.opacity(0.85))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    value(of: stat, scale: scale)
                    if let caption = stat.caption {
                        Text(caption)
                            .font(.system(size: 9 * scale))
                            .foregroundStyle(Brand.paper.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.vertical, 7 * scale)
                .padding(.horizontal, 9 * scale)
                .background(.white.opacity(0.10), in: .rect(cornerRadius: 11 * scale))
            }
        }
    }

    /// The tally cell is the one that is not a string — the verdict ladder's own inks, the
    /// same three the share card and `KeyMetricsView` draw (`docs/presentation.md`).
    @ViewBuilder
    private func value(of stat: ShareCardStats.Stat, scale: CGFloat) -> some View {
        let font = Font.system(size: 21 * scale, weight: .bold, design: .rounded)
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

    /// The mark, the name, the address — the whole point of a frame somebody else sees, and
    /// the same footer the shared card carries.
    private func footer(_ scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            Image("LaunchMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 22 * scale, height: 22 * scale)
                .clipShape(.rect(cornerRadius: 5 * scale))
            Text(Branding.credit)
                .font(.system(size: 13 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.paper.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            if let disclaimer = stats.disclaimer {
                Text(disclaimer)
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(.orange.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .padding(.top, 6 * scale)
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
