import SwiftUI

#if BETA || DEBUG

/// **"Start over done — close the app and open it again."**
///
/// The honest half of `SessionStore.startOver`. The wipe always happens; what can fail is
/// the step after it, opening a new library on the path the wipe just cleared. If that
/// throws, the app is running on an in-memory library — every screen would look right, and
/// the next session imported would be gone at the next launch.
///
/// So the app stops rather than pretends. One screen, no buttons: iOS has no supported way
/// for an app to quit itself, and a button that called `exit(0)` would look to the rider
/// and to the crash reporter exactly like a crash in the feature he just used.
///
/// A whole screen for the same reason `LibraryNewerThanAppView` is one: behind it the four
/// tabs would be drawing a library that is not on the disk.
struct StartOverRelaunchView: View {

    @ScaledMetric(relativeTo: .largeTitle) private var heroGlyph: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: heroGlyph))
                    .foregroundStyle(.teal)
                    .padding(.top, 40)

                Text("Start over done — close the app and open it again.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Everything is gone: the library, the backups, your intervals.icu key, "
                     + "the Strava connection and every setting. The fresh library could "
                     + "not be opened without a restart, so CleanJibe is waiting rather "
                     + "than working from one it cannot keep.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Swipe up to close CleanJibe, then open it again. The next launch is a "
                     + "first launch.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .padding(24)
            .readableColumn()
        }
        .background(Color(.systemGroupedBackground))
    }
}

#endif
