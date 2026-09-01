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
/// The drawing is not a drawing. It is 6 min 40 s of a real session, traced: seconds
/// 1145–1545 of Nago-Torbole, 1 September 2026, 16:11 — the third and last ride of that
/// day, 75 minutes and 54 jibes of it. Nine of those jibes are in this window, and the
/// track is the track: 1715 m of sailing over 277 × 57 m of water.
///
/// What was done to it: rotated (the frame's left-to-right is 284.5° true, so the reaches
/// lie across the box), scaled by one number in both axes — 0.547 m per unit, no vertical
/// exaggeration, the loops are as round as they were — and simplified with Douglas–Peucker
/// at 1.2 m, which is about the width of the board. Nothing was moved. The earlier version
/// of this motif laid the reaches on even bands and spaced the loops by hand; this one
/// does not, because the uneven spacing *is* the realism — a rider recognises his own
/// water by it, and a drawn ladder is the one thing that reads as clip art.
///
/// The teardrop loops, the crossovers, the reach that runs three-quarters of the frame and
/// the one that gives up early are all in the file. So are the marks: seven jibes flown
/// through, the touchdown at second 1379, and the fall at 1268. Both greys are real too —
/// the long one at the left is the 26 seconds off the foil after that touchdown, and the
/// shorter one under the middle, mostly overdrawn by later reaches, is the 81-second swim
/// out of the fall. Every mark sits where it happened.
private struct WelcomeTrackMotif: View {

    /// The web motif's viewBox. Keeping the coordinates identical is what makes the two
    /// renditions comparable at all — every number below is readable against the SVG.
    private static let box = CGSize(width: 640, height: 128)

    // The generated geometry, verbatim from web/index.html's `<path d="…">` attributes —
    // one table in three files (here, the homepage, web/tools/social_card.html), so a
    // `grep` for any of these strings is the drift check. Regenerate all three together or
    // not at all; hand-editing one of them is how the front doors start disagreeing.

    /// The whole excerpt, off the foil.
    private static let trackD = "M215 69Q162 89 140 94Q118 100 111 101Q105 102 91 100Q77 98 71 95Q65 93 62 87Q60 82 60 75Q60 69 63 64Q67 59 89 47Q112 35 130 34Q149 34 180 37Q211 40 248 38Q286 37 355 52Q424 67 455 67Q487 67 499 63Q511 60 515 55Q520 51 522 45Q524 39 523 33Q523 28 519 24Q516 20 507 16Q498 12 479 13Q461 15 447 18Q433 22 360 55Q287 88 273 91Q260 95 253 96Q247 98 232 97Q218 96 205 89Q192 83 189 75Q187 68 187 61Q188 54 197 45Q207 37 218 35Q230 33 243 35Q256 37 290 49Q324 62 375 71Q427 81 466 94Q506 108 527 112Q548 116 560 114Q573 112 576 107Q580 102 580 96Q580 91 577 87Q575 83 557 71Q539 59 525 54Q512 50 489 54Q467 58 396 81Q326 104 306 107Q286 111 266 110Q246 109 224 111Q203 114 196 110Q189 107 183 101Q178 95 178 82Q179 70 182 66Q186 62 205 54Q224 47 236 46Q249 46 270 48Q292 51 309 57Q326 64 330 68Q334 72 328 67Q323 62 312 60Q302 58 299 45Q296 33 299 35Q303 38 304 36Q306 34 300 28Q294 23 296 25Q298 27 296 28Q295 30 298 30Q301 30 305 29Q309 28 313 22Q317 17 324 18Q332 19 339 16Q346 14 360 13L374 13"

    /// …and the parts of it he was flying: the run that ends in the fall, the short one
    /// that ends in the touchdown, and the long one that runs the window out.
    private static let foilDs = [
        "M215 69Q162 89 140 94Q118 100 111 101Q105 102 91 100Q77 98 71 95Q65 93 62 87Q60 82 60 75Q60 69 63 64Q67 59 89 47Q112 35 130 34Q149 34 180 37Q211 40 248 38Q286 37 355 52Q424 67 455 67Q487 67 499 63Q511 60 515 55Q520 51 522 45Q524 39 523 33Q523 28 519 24Q516 20 507 16Q498 12 479 13Q461 15 447 18Q433 22 360 55Q287 88 273 91Q260 95 253 96Q247 98 232 97Q218 96 205 89Q192 83 189 75Q187 68 187 61Q188 54 197 45Q207 37 218 35Q230 33 243 35Q256 37 290 49Q324 62 375 71Q427 81 466 94Q506 108 527 112Q548 116 560 114Q573 112 576 107Q580 102 580 96Q580 91 577 87Q575 83 557 71Q539 59 525 54Q512 50 489 54Q467 58 396 81Q326 104 306 107Q286 111 266 110Q246 109 224 111Q203 114 196 110Q189 107 183 101Q178 95 177 88Q177 82 178 76Q179 70 182 66Q186 62 197 56Q209 51 223 48Q238 45 257 47Q277 49 301 56Q326 64 330 68L334 72",
    ]

    /// The jibes carried, on the apex of the loop each one made.
    private static let flew = [
        CGPoint(x: 67, y: 59),
        CGPoint(x: 508, y: 15),
        CGPoint(x: 207, y: 37),
        CGPoint(x: 179, y: 70),
    ]
    /// The touchdown at second 1379, at the far end of the reach it happened on.
    private static let touchdown = CGPoint(x: 560, y: 73)
    /// The jibe he fell in, second 1268; the 81-second swim out of it is the grey the
    /// later reaches cross over.
    private static let fellIn = CGPoint(x: 334, y: 72)
    /// Which way he went, set off the lines: (x, y, heading in degrees). Position and
    /// heading are the track's; only the two moments are chosen, for the emptiest stretch.
    private static let arrows: [(CGFloat, CGFloat, CGFloat)] = [
        (98, 53, -33.2),
        (435, 32, 168.1),
    ]

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

            draw(Self.path(Self.trackD), DesignTokens.Phase.offFoil, width: 4.5)
            for d in Self.foilDs {
                draw(Self.path(d), DesignTokens.Phase.flying, width: 5)
            }

            // Which way he went — off the line rather than on it, where a chevron inside a
            // 5 pt stroke just reads as a nick in the paint.
            for (x, y, heading) in Self.arrows {
                var chevron = Path()
                chevron.move(to: CGPoint(x: -4, y: -5))
                chevron.addLine(to: CGPoint(x: 2, y: 0))
                chevron.addLine(to: CGPoint(x: -4, y: 5))
                let placed = chevron.applying(
                    CGAffineTransform(translationX: x, y: y)
                        .rotated(by: heading * .pi / 180))
                draw(placed, DesignTokens.Direction.ink.opacity(0.45), width: 2)
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

            // Fell in — the red cross on the jibe he swam out of.
            var cross = Path()
            cross.move(to: CGPoint(x: Self.fellIn.x - 6, y: Self.fellIn.y - 6))
            cross.addLine(to: CGPoint(x: Self.fellIn.x + 6, y: Self.fellIn.y + 6))
            cross.move(to: CGPoint(x: Self.fellIn.x + 6, y: Self.fellIn.y - 6))
            cross.addLine(to: CGPoint(x: Self.fellIn.x - 6, y: Self.fellIn.y + 6))
            draw(cross, DesignTokens.Outcome.fellIn, width: 3.5)
        }
        .accessibilityElement()
        .accessibilityLabel("A four-minute excerpt from a real session's track: "
                            + "five jibes flown through, one touched down, and one "
                            + "fallen in with the swim that followed.")
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
