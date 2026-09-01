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
            // the screen a gate rather than a greeting. It carries a detail line like the
            // other two, because "Later" alone does not tell the rider holding a .fit file
            // that opening it by hand is a supported way in rather than a postponement.
            VStack(spacing: 6) {
                Button(WelcomeGuide.laterTitle, action: onLater)
                    .font(.subheadline)
                    .foregroundStyle(Brand.paper.opacity(0.6))

                Text(WelcomeGuide.laterDetail)
                    .font(.caption2)
                    .foregroundStyle(Brand.paper.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var footer: some View {
        Text(Branding.credit)
            .font(.caption2)
            .foregroundStyle(Brand.paper.opacity(0.45))
    }
}

/// The screen's one graphic: a session's track with its flights on it and the turn
/// verdicts marked, in the presentation tokens themselves.
///
/// It is the vocabulary rather than decoration — the same drawing the homepage carries as
/// inline SVG (web/index.html, the hero motif), in the same 640 × 128 frame and with the
/// same colours, so the two front doors show the same picture. Drawn rather than shipped as
/// an image: it costs less than an asset, and it follows the tokens if they move instead of
/// quietly disagreeing with them.
///
/// The shape is the bundled example session's — the reaches, their lengths, which end each
/// jibe sits at, and where the fall and the swim after it come in the order all read out of
/// `fixtures/sessions/ciq/2026-08-30-1407_nago-torbole-windsurfen_ciq.fit`; only the even
/// spacing between the reaches is drawn by hand, because at true scale 240 m of reach inside
/// 67 m of drift crosses into a knot. The loops are teardrops rather than U-turns: a jibe
/// exits heading back up, so the exit cuts across the entry short of the tip, and that
/// crossover is what makes the pattern read as wingfoil at all.
private struct WelcomeTrackMotif: View {

    /// The web motif's viewBox. Keeping the coordinates identical is what makes the two
    /// renditions comparable at all — every number below is readable against the SVG.
    private static let box = CGSize(width: 640, height: 128)

    // The generated geometry, verbatim from web/index.html's `<path d="…">` attributes —
    // one table in three files (here, the homepage, web/tools/social_card.html), so a
    // `grep` for any of these strings is the drift check. Regenerate all three together or
    // not at all; hand-editing one of them is how the front doors start disagreeing.

    /// The whole ride, off the foil.
    private static let trackD = "M133 102L354 101Q364 101 374 101L562 104Q572 104 581 100L590 96Q598 92 605 98L607 100Q614 106 606 109L601 111Q592 116 583 112L541 96Q532 93 522 93L387 90Q377 90 367 90L192 87Q182 87 173 83L164 78Q156 75 149 80L147 82Q140 88 148 91L153 94Q162 98 171 94L213 78Q222 75 232 75L344 72Q354 71 364 72L517 75Q527 75 536 71L545 67Q553 63 559 68L562 70Q569 76 561 79L556 82Q547 86 537 82L496 67Q487 63 477 63L362 61Q352 61 342 60L188 57Q178 57 169 53L160 49Q152 45 145 51L143 53Q136 58 144 62L149 64Q158 68 167 65L209 49Q218 45 228 45L282 42Q292 42 302 42L397 45Q407 45 417 45L421 45Q431 45 421 43L361 32Q351 30 341 31L203 31Q193 31 183 31L68 28Q58 28 48 28L34 28"

    /// …and the parts of it that were flown: the long flight that ends in the water, then
    /// the reach home after the swim.
    private static let foilDs = [
        "M133 102L354 101Q364 101 374 101L562 104Q572 104 581 100L590 96Q598 92 605 98L607 100Q614 106 606 109L601 111Q592 116 583 112L541 96Q532 93 522 93L387 90Q377 90 367 90L192 87Q182 87 173 83L164 78Q156 75 149 80L147 82Q140 88 148 91L153 94Q162 98 171 94L213 78Q222 75 232 75L344 72Q354 71 364 72L517 75Q527 75 536 71L545 67Q553 63 559 68L562 70Q569 76 561 79L556 82Q547 86 537 82L496 67Q487 63 477 63L362 61Q352 61 342 60L188 57Q178 57 169 53L160 49Q152 45 145 51L143 53Q136 58 144 62L149 64Q158 68 167 65L209 49Q218 45 228 45L282 42Q292 42 302 42L397 45Q407 45 417 45L431 45",
        "M351 30L203 31Q193 31 183 31L68 28Q58 28 48 28L34 28",
    ]

    /// The jibes carried, on the apex of the loop each one made.
    private static let flew = [CGPoint(x: 598, y: 92), CGPoint(x: 152, y: 45)]
    /// The touchdown. This session flew through every jibe it did not fall in, so this one
    /// mark is the key's third verdict rather than a reading of the track.
    private static let touchdown = CGPoint(x: 553, y: 63)
    /// Where the long flight ended.
    private static let fellIn = CGPoint(x: 431, y: 45)
    /// Which way he went, set off the lines: (x, y, pointing left?).
    private static let arrows: [(CGFloat, CGFloat, Bool)] = [(330, 113, false), (190, 20, true)]

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

            draw(Self.path(Self.trackD), DesignTokens.Phase.offFoil, width: 3)
            for d in Self.foilDs {
                draw(Self.path(d), DesignTokens.Phase.flying, width: 5)
            }

            // Which way he went — off the line rather than on it, where a chevron inside a
            // 5 pt stroke just reads as a nick in the paint.
            for (x, y, left) in Self.arrows {
                var chevron = Path()
                let s: CGFloat = left ? -1 : 1
                chevron.move(to: CGPoint(x: x - 4 * s, y: y - 5))
                chevron.addLine(to: CGPoint(x: x + 2 * s, y: y))
                chevron.addLine(to: CGPoint(x: x - 4 * s, y: y + 5))
                draw(chevron, DesignTokens.Direction.ink.opacity(0.45), width: 2)
            }

            // Flew through — a green disc on each jibe's apex.
            for centre in Self.flew {
                let disc = Path(ellipseIn: CGRect(x: centre.x - 7, y: centre.y - 7,
                                                  width: 14, height: 14))
                context.fill(disc.applying(transform),
                             with: .color(DesignTokens.Outcome.flew))
            }

            // Touched down — the amber triangle.
            var triangle = Path()
            triangle.move(to: CGPoint(x: Self.touchdown.x, y: Self.touchdown.y - 7))
            triangle.addLine(to: CGPoint(x: Self.touchdown.x + 7, y: Self.touchdown.y + 6))
            triangle.addLine(to: CGPoint(x: Self.touchdown.x - 7, y: Self.touchdown.y + 6))
            triangle.closeSubpath()
            context.fill(triangle.applying(transform),
                         with: .color(DesignTokens.Outcome.touchdown))

            // Fell in — the red cross where the long flight stops.
            var cross = Path()
            cross.move(to: CGPoint(x: Self.fellIn.x - 6, y: Self.fellIn.y - 6))
            cross.addLine(to: CGPoint(x: Self.fellIn.x + 6, y: Self.fellIn.y + 6))
            cross.move(to: CGPoint(x: Self.fellIn.x + 6, y: Self.fellIn.y - 6))
            cross.addLine(to: CGPoint(x: Self.fellIn.x - 6, y: Self.fellIn.y + 6))
            draw(cross, DesignTokens.Outcome.fellIn, width: 3.5)
        }
        .accessibilityElement()
        .accessibilityLabel("A wingfoil session's track: five cross-wind reaches with "
                            + "teardrop jibe loops at their ends, two jibes flown through, "
                            + "one touched down, and a fall with a swim before the last "
                            + "reach.")
    }

    /// The slice of SVG path data the motif uses — absolute `M x y`, `L x y`, `Q cx cy x y`
    /// and nothing else. Reading the strings rather than transcribing them into Swift
    /// literals is the point: the homepage, the share card and this screen then hold the
    /// *same* characters, and no hand-copied number can go quietly out of step.
    private static func path(_ d: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var digits = ""
        var command: Character = " "

        func flush() {
            if let value = Double(digits) { numbers.append(CGFloat(value)) }
            digits = ""
        }
        func apply() {
            switch (command, numbers.count) {
            case ("M", 2):
                path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
            case ("L", 2):
                path.addLine(to: CGPoint(x: numbers[0], y: numbers[1]))
            case ("Q", 4):
                path.addQuadCurve(to: CGPoint(x: numbers[2], y: numbers[3]),
                                  control: CGPoint(x: numbers[0], y: numbers[1]))
            default:
                break
            }
            numbers = []
        }

        for character in d {
            if character.isNumber || character == "." {
                digits.append(character)
            } else if character == " " {
                flush()
            } else {
                flush()
                apply()
                command = character
            }
        }
        flush()
        apply()
        return path
    }
}
