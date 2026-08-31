import SwiftUI
import WingFoilKit

/// The first screen of a first launch: what this app is, and the two ways in.
///
/// It sits *in front of* `IcuSetupCard`, which is still the setup path and still decides
/// its own three faces. The card answers "how do I connect my watch"; nobody had answered
/// "what is this for" — and a first run that opens on four intervals.icu steps asks for
/// five minutes of work before it has earned any. So: one paragraph of what the app does,
/// then the demo, then the setup, then a way past both.
///
/// Painted in the brand colours rather than the system ones — the only screen in the app
/// that is. It is a deliberate committed look, and the reason is continuity: the launch
/// screen is `LaunchMark` on `LaunchBackground` (see project.yml, `UILaunchScreen`), so on
/// a first run the cold-start frame *becomes* this screen instead of flashing away into a
/// list. That is also why `Brand` is the right palette here by its own rule — a surface the
/// app paints itself, with no system background to adapt to.
struct WelcomeView: View {
    @Environment(SessionStore.self) private var store
    /// `.compact` is landscape on a phone: 402 pt of height, which the mark and the
    /// paragraph would otherwise fill entirely, leaving the buttons below a fold nobody is
    /// told about. Everything above them shrinks rather than the layout changing shape.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isShort: Bool { verticalSizeClass == .compact }

    /// What the buttons do. The screen is presented in two situations — the first run and
    /// "show me that again" from Settings — and only the first one has anywhere to go
    /// afterwards, so the actions are handed in rather than assumed.
    var onTryExample: () -> Void
    var onConnect: () -> Void
    var onLater: () -> Void

    var body: some View {
        ZStack {
            Brand.cardGradient.ignoresSafeArea()
            ScrollView {
                // The homepage's rhythm, and for its reason (web/index.html): the promise,
                // then the way in, then the picture, then the vocabulary. Putting the
                // glossary above the buttons would make the reader earn them.
                VStack(spacing: isShort ? 18 : 26) {
                    identity
                    actions
                    WelcomeTrackMotif()
                        .frame(height: isShort ? 64 : 84)
                        .padding(.horizontal, 4)
                    vocabulary
                    footer
                }
                // 560 pt is about a long line of body text; without the cap the paragraph
                // runs the full width of a landscape phone and reads like a licence.
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, isShort ? 12 : 28)
                .padding(.bottom, 36)
            }
            // The whole screen scrolls, because it has to: in landscape on the smallest
            // supported phone the identity block alone is taller than the safe area.
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(Brand.paper)
        // The brand navy is dark whatever the phone is set to, so the status bar and every
        // system control on top of it have to be told.
        .preferredColorScheme(.dark)
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(spacing: isShort ? 8 : 14) {
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: isShort ? 56 : 88, height: isShort ? 56 : 88)
                .clipShape(.rect(cornerRadius: isShort ? 13 : 20))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .accessibilityHidden(true)

            Text(Branding.appName)
                .font(isShort ? .title.weight(.bold) : .largeTitle.weight(.bold))
                .kerning(0.5)

            Text(WelcomeGuide.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.green)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // The one block on the screen that is set ragged-right rather than centred: it
            // is eight lines of prose, and eight centred lines are a poster, not a
            // paragraph.
            Text(WelcomeGuide.lede)
                .font(.callout)
                .foregroundStyle(Brand.paper.opacity(0.82))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    // MARK: - The vocabulary

    private var vocabulary: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(WelcomeGuide.highlights) { highlight in
                VStack(alignment: .leading, spacing: 3) {
                    Text(highlight.term)
                        .font(.subheadline.weight(.semibold))
                    Text(highlight.detail)
                        .font(.footnote)
                        .foregroundStyle(Brand.paper.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.paper.opacity(0.07), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Brand.paper.opacity(0.10), lineWidth: 1)
        }
    }

    // MARK: - The three ways on

    private var actions: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Button(action: onTryExample) {
                    Label(WelcomeGuide.tryExampleTitle, systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .background(Brand.green, in: .capsule)
                .foregroundStyle(Brand.navy)
                .disabled(store.isBusy)
                .opacity(store.isBusy ? 0.6 : 1)

                Text(WelcomeGuide.tryExampleDetail)
                    .font(.caption)
                    .foregroundStyle(Brand.paper.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                Button(action: onConnect) {
                    Label(WelcomeGuide.connectTitle, systemImage: "link")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .foregroundStyle(Brand.paper)
                .overlay {
                    Capsule().strokeBorder(Brand.paper.opacity(0.35), lineWidth: 1.5)
                }

                Text(WelcomeGuide.connectDetail)
                    .font(.caption)
                    .foregroundStyle(Brand.paper.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Quiet, but present. A rider who came here to import a file by hand has
            // nothing to gain from either button above, and hiding his way out would make
            // the screen a gate rather than a greeting.
            Button(WelcomeGuide.laterTitle, action: onLater)
                .font(.subheadline)
                .foregroundStyle(Brand.paper.opacity(0.6))
                .padding(.top, 2)
        }
    }

    private var footer: some View {
        Text(Branding.credit)
            .font(.caption2)
            .foregroundStyle(Brand.paper.opacity(0.45))
    }
}

/// The screen's one graphic: a track with two flights on it and the three turn verdicts
/// marked, in the presentation tokens themselves.
///
/// It is the vocabulary rather than decoration — the same drawing the homepage carries as
/// inline SVG (web/index.html, the hero motif), in the same 640 × 128 frame and with the
/// same colours, so the two front doors show the same picture. Drawn rather than shipped as
/// an image: at ~40 lines it costs less than an asset, and it follows the tokens if they
/// move instead of quietly disagreeing with them.
private struct WelcomeTrackMotif: View {

    /// The web motif's viewBox. Keeping the coordinates identical is what makes the two
    /// renditions comparable at all — every number below is readable against the SVG.
    private static let box = CGSize(width: 640, height: 128)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.box.width, size.height / Self.box.height)
            let inset = CGPoint(x: (size.width - Self.box.width * scale) / 2,
                                y: (size.height - Self.box.height * scale) / 2)
            let transform = CGAffineTransform(translationX: inset.x, y: inset.y)
                .scaledBy(x: scale, y: scale)

            func draw(_ path: Path, _ color: Color, width: CGFloat, dashed: Bool = false) {
                let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round,
                                        dash: dashed ? [3, 5] : [])
                context.stroke(path.applying(transform), with: .color(color), style: style)
            }

            // The whole ride, off the foil…
            var track = Path()
            track.move(to: CGPoint(x: 20, y: 100))
            track.addLine(to: CGPoint(x: 120, y: 46))
            track.addQuadCurve(to: CGPoint(x: 172, y: 44), control: CGPoint(x: 150, y: 32))
            track.addLine(to: CGPoint(x: 268, y: 96))
            track.addQuadCurve(to: CGPoint(x: 318, y: 96), control: CGPoint(x: 296, y: 110))
            track.addLine(to: CGPoint(x: 414, y: 44))
            track.addQuadCurve(to: CGPoint(x: 464, y: 42), control: CGPoint(x: 442, y: 30))
            track.addLine(to: CGPoint(x: 560, y: 94))
            track.addLine(to: CGPoint(x: 620, y: 74))
            draw(track, DesignTokens.Phase.offFoil, width: 5)

            // …and the parts of it that were flown, laid over the top.
            var first = Path()
            first.move(to: CGPoint(x: 20, y: 100))
            first.addLine(to: CGPoint(x: 120, y: 46))
            first.addQuadCurve(to: CGPoint(x: 172, y: 44), control: CGPoint(x: 150, y: 32))
            first.addLine(to: CGPoint(x: 268, y: 96))
            first.addQuadCurve(to: CGPoint(x: 305, y: 103), control: CGPoint(x: 296, y: 110))
            var second = Path()
            second.move(to: CGPoint(x: 340, y: 86))
            second.addLine(to: CGPoint(x: 414, y: 44))
            second.addQuadCurve(to: CGPoint(x: 452, y: 35), control: CGPoint(x: 442, y: 30))
            var third = Path()
            third.move(to: CGPoint(x: 566, y: 91))
            third.addLine(to: CGPoint(x: 620, y: 74))
            for flight in [first, second, third] {
                draw(flight, DesignTokens.Phase.flying, width: 5)
            }

            // Flew through — a green disc on the apex of the first jibe.
            let flew = Path(ellipseIn: CGRect(x: 156, y: 29, width: 14, height: 14))
            context.fill(flew.applying(transform),
                         with: .color(DesignTokens.Outcome.flew))

            // Touched down — the amber triangle where the first flight ends.
            var touchdown = Path()
            touchdown.move(to: CGPoint(x: 305, y: 94))
            touchdown.addLine(to: CGPoint(x: 313, y: 108))
            touchdown.addLine(to: CGPoint(x: 297, y: 108))
            touchdown.closeSubpath()
            context.fill(touchdown.applying(transform),
                         with: .color(DesignTokens.Outcome.touchdown))

            // Fell in — the red cross where the second one does.
            var fell = Path()
            fell.move(to: CGPoint(x: 446, y: 29))
            fell.addLine(to: CGPoint(x: 458, y: 41))
            fell.move(to: CGPoint(x: 458, y: 29))
            fell.addLine(to: CGPoint(x: 446, y: 41))
            draw(fell, DesignTokens.Outcome.fellIn, width: 3.5)
        }
        .accessibilityElement()
        .accessibilityLabel("A wingfoil track: two flights on the foil, a jibe flown "
                            + "through, a touchdown, and a fall.")
    }
}
