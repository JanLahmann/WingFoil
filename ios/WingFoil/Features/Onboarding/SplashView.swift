import SwiftUI
import WingFoilKit

/// The first two seconds of a cold start: the mark, the wordmark, and what the app is for.
///
/// **This is the launch screen, continued.** iOS draws `UILaunchScreen` (project.yml —
/// `SplashMark` on `LaunchBackground`) before a line of our code runs, and it draws that
/// image at its *natural point size*, centred in the safe area. That was measured on the
/// simulator rather than assumed, and it is the whole design: the asset is 140 / 280 / 420 px
/// at 1×/2×/3×, so the system's frame puts a 140 pt mark at the centre of the safe area on
/// every device, and this view puts the same artwork at the same size in the same place. The
/// handover moves nothing — which is why the mark here carries no shadow and no corner clip
/// (`WelcomeView`'s identity block has both): a launch screen can draw neither, so neither
/// may we. `Splash.markSide` and the pixel sizes of that asset are one decision; change one
/// and change the other.
///
/// The words are the only thing the system's frame cannot show, so they are the only thing
/// that moves: they fade up under a mark that is already where it was. They are the share
/// card's footer — the same call to action a receiver reads on a shared PNG, which is the
/// line that says what the app is for in the fewest words anyone has written for it, with
/// the address under it on a line of its own (`Branding.site`) because the start screen
/// should say where to find us and not only who we are (Jan, 14 Sep 2026).
///
/// They hang off the mark as an **overlay** and grow downwards, which is what keeps the
/// extra line from costing anything: the mark cannot be pushed off the centre the launch
/// screen already put it on, whatever is written under it.
///
/// It is one accessibility element labelled "CleanJibe" and it dismisses itself on a clock,
/// so VoiceOver has one thing to say and nothing to escape from.
struct SplashView: View {
    @Environment(SessionStore.self) private var store
    /// `.compact` is a phone in landscape: ~380 pt of height, where the mark stays exactly
    /// where the launch screen put it (that is the contract) and the *words* give way.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called once the hold is over. The caller owns the crossfade, because the caller owns
    /// the thing being crossfaded *to*.
    var onFinished: () -> Void

    @State private var wordsShown = false

    private var isShort: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()
            mark
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Branding.appName)
        // The navy is dark whatever the phone is set to, so the clock and the battery on top
        // of it have to be told — `WelcomeView` does the same, for the same reason. The other
        // half of that sentence is `UIStatusBarStyle: UIStatusBarStyleLightContent` in
        // project.yml, which is what the *launch* screen reads: without it the handover would
        // flip the clock from black to white, and the words fading up are the only thing on
        // this screen allowed to change.
        .preferredColorScheme(.dark)
        .task { await hold() }
    }

    /// The mark, centred the way the launch screen centres it — a plain centred view in a
    /// stack whose *background* ignores the safe area and whose content does not.
    private var mark: some View {
        Image(ChannelArt.splashMark)
            .resizable()
            .scaledToFit()
            .frame(width: Splash.markSide, height: Splash.markSide)
            // An overlay rather than a stack: the words must not be able to push the mark
            // off the centre the system's frame already put it on.
            .overlay(alignment: .top) { words.offset(y: Splash.markSide + (isShort ? 16 : 28)) }
    }

    private var words: some View {
        VStack(spacing: isShort ? 6 : 10) {
            Text(Branding.appName)
                .font(.system(size: isShort ? Splash.wordmarkPointShort : Splash.wordmarkPoint,
                              weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Brand.paper)
                .multilineTextAlignment(.center)

            // In landscape there is no room under a 140 pt mark for two lines, and the
            // wordmark is the half that carries the brand.
            if !isShort {
                Text(Splash.tagline)
                    .font(.system(size: Splash.taglinePoint))
                    .foregroundStyle(Brand.paper.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The address, quieter than everything above it — *"the start screen should say
            // where to find us, not just who we are"* (Jan, 14 Sep 2026). It survives
            // landscape where the tagline does not, because it is one short line rather than
            // a wrapping sentence, and because the whole point of it is the address.
            Text(Branding.site)
                .font(.system(size: isShort ? Splash.sitePointShort : Splash.sitePoint))
                .foregroundStyle(Brand.paper.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        // A width of its own, and this is load-bearing: an overlay is *proposed* the size of
        // the thing it hangs off, which here is a 140 pt square, and "CleanJibe" set in the
        // largest type the app owns came out of that proposal hyphenated across two lines.
        // 320 pt is the width of the narrowest phone still supported, so the block never
        // overhangs a screen it has to be centred on.
        //
        // That width is why this is the one screen in the app whose type has a ceiling. The
        // words scale with the rider's setting like everything else, but they cannot be
        // allowed past 320 pt, and "CleanJibe" set in `.largeTitle` fills 320 pt at about
        // `.accessibility2`; beyond that it would hyphenate across two lines again — which
        // is the one thing the wordmark may not do. It costs nothing: the screen holds three
        // short lines for two seconds, it is one accessibility element, and every word on it
        // is repeated on the Welcome screen, which scales the whole way.
        .frame(width: 320)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .opacity(wordsShown ? 1 : 0)
    }

    // MARK: - The hold

    /// **max(2 s, the library).** Jan, on the timing: *"Don't make it too short; can be 2
    /// seconds or so."* Two seconds is therefore a floor and not a timer — a cold start that
    /// is still reading the library at the end of it goes on showing the brand rather than
    /// handing over to a spinner, and on a simulator full of fixtures that is a minute or
    /// more. The wait ends on *either* answer the load can give, so a library that cannot be
    /// read (`errorMessage`) is a dismissal and never a screen the rider is stuck on.
    private func hold() async {
        if !reduceMotion { withAnimation(.easeIn(duration: 0.35)) { wordsShown = true } }
        else { wordsShown = true }
        do {
            try await Task.sleep(for: Splash.minimumHold)
            // Polled rather than observed: `SessionStore` is `@Observable`, which has no
            // stream to await, and a tenth of a second of latency on a two-second screen is
            // not worth a continuation. `try` and not `try?` on purpose — a cancelled sleep
            // must leave the loop, not spin in it.
            while !(store.hasLoadedLibrary || store.errorMessage != nil) {
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            return  // cancelled: the view is already going away
        }
        onFinished()
    }
}

/// The numbers the splash and the launch screen have to agree on, in one place.
enum Splash {
    /// The mark's side, in points. **The asset `SplashMark` is this size at 1× (140 px), 2×
    /// (280 px) and 3× (420 px)** — `UILaunchScreen` draws it at its natural point size, so
    /// those pixel counts are what make the system's frame and ours the same picture.
    static let markSide: CGFloat = 140

    /// The floor on the hold (see `SplashView.hold`).
    static let minimumHold: Duration = .seconds(2)

    // MARK: - The type, in points rather than in text styles
    //
    // **Fixed sizes, on purpose, and this is the one screen that earns them.** Jan, 14 Sep
    // 2026: the three lines were *too small on a phone* — the tagline was `.footnote` (13 pt)
    // and the address `.caption2` (11 pt at 55 % of the paper), which is the size of small
    // print on a screen whose entire job for two seconds is to be read from arm's length,
    // often over somebody's shoulder on a beach. They are one **lockup** under a mark that is
    // pinned to the pixel by the launch screen (see `markSide`), so they may not reflow with
    // Dynamic Type: a rider on the largest accessibility size would otherwise push the
    // address off the bottom of a phone in landscape, and the mark cannot move to make room.
    // Every other screen in the app follows Dynamic Type; this one holds still for two
    // seconds and then hands over to screens that do.
    //
    // The landscape numbers are the same lockup with the tagline dropped (`SplashView.words`)
    // and the two survivors stepped down, so the block still clears the ~195 pt a compact
    // height leaves below the centred mark: 140/2 + 16 + 28 + 6 + 14 ≈ 134 pt.

    /// The wordmark. 34 pt is `.largeTitle`'s own size, said as a number because the weight
    /// moved with it: **semibold**, not bold — at this size bold reads as a shout, and the
    /// mark above it is already the loud half of the lockup.
    static let wordmarkPoint: CGFloat = 34
    /// Landscape, where the whole block has about 195 pt to live in.
    static let wordmarkPointShort: CGFloat = 28

    /// "analyze your wingfoil sessions free" — body size, because it is the sentence that
    /// says what the app is and a reader who cannot make it out has been told nothing.
    static let taglinePoint: CGFloat = 17

    /// `cleanjibe.org`. Still the quietest line of the three, but quiet now means 80 % of the
    /// paper rather than 55 % of it at 11 pt — an address nobody can read is not an address.
    static let sitePoint: CGFloat = 15
    static let sitePointShort: CGFloat = 14

    /// The crossfade into the library. Not applied under Reduce Motion, where the splash
    /// cuts after the same hold instead.
    static let crossfade: Double = 0.4

    /// "analyze your wingfoil sessions free" — the share card's call to action without the
    /// address it ends in. Derived rather than retyped: the card's line is a contract
    /// (`docs/presentation.md`, the footer), and a second literal here would be a second
    /// place for it to drift. The address is split off rather than dropped: it is set on its
    /// own line under this one, smaller and quieter, so the screen reads mark · CleanJibe ·
    /// what the app is for · cleanjibe.org.
    static let tagline = Branding.callToAction
        .replacingOccurrences(of: " — " + Branding.site, with: "")

    /// Whether a cold start shows the splash at all.
    ///
    /// It does, except under the simulator screenshot hooks: `UI_IMPORT_FIXTURES`,
    /// `UI_OPEN_SESSION` and the rest of that family (docs/testing.md) drive the app
    /// headlessly and photograph whatever is on screen, and a brand screen in front of it
    /// would change every existing shot. Any `UI_` variable means an automated launch, so
    /// the hold is zero and the splash is never built.
    static var isWanted: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("UI_") }) {
            return false
        }
        #endif
        return true
    }
}
