import SwiftUI
import UniformTypeIdentifiers
import WingFoilKit

/// **"This library was last used by a newer CleanJibe."**
///
/// The one screen the app shows instead of itself. It exists because the three channels are
/// cut from one commit but not on one day (docs/channels.md): release and beta share a
/// bundle id, so TestFlight will put an older App Store build back on a phone whose library
/// a newer beta has already migrated, and `AppDatabase` refuses to open it
/// (`LibraryNewerThanApp`) rather than read a schema it does not know.
///
/// **A whole screen rather than a banner.** Behind a banner the four tabs would be showing
/// an empty library that is not empty, an empty Records page that is not empty, and an
/// Import button that invites the rider to bring a season back in on top of a library that
/// is still sitting on the disk. There is exactly one useful thing to do here and two ways
/// to do it, so the screen is those two ways and nothing else.
///
/// Nothing on this screen touches the library. The file is left as the newer build left it
/// until the rider has picked a backup *and* confirmed it — see
/// `SessionStore.adoptFreshLibraryForRestore`.
struct LibraryNewerThanAppView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.openURL) private var openURL

    let refusal: LibraryNewerThanApp

    @State private var showRestorePicker = false
    @State private var helpTopic: HelpTopicID?

    /// The hero glyph, in points rather than a text style because no text style is 44 pt —
    /// `@ScaledMetric` pins it to `.largeTitle` so it still grows with the rider's setting.
    @ScaledMetric(relativeTo: .largeTitle) private var heroGlyph: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: heroGlyph))
                    .foregroundStyle(.teal)
                    .padding(.top, 40)

                Text("This library was last used by a newer CleanJibe.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(Self.wayBack)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = store.restoreProgress {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(progress.done),
                                     total: Double(max(progress.total, 1)))
                        Text("Restoring session \(min(progress.done + 1, progress.total)) "
                             + "of \(progress.total)…")
                            .font(.footnote)
                            .foregroundStyle(.readableSecondary)
                    }
                } else {
                    buttons
                }

                // The two numbers, small, at the foot: a rider does not need them and the
                // one mail that follows this screen does.
                Text("Library version \(refusal.storedVersion) · this build reads up to "
                     + "\(refusal.knownVersion)")
                    .font(.caption2)
                    .foregroundStyle(.readableSecondary)
                    .padding(.top, 8)

                Text("Nothing has been changed. Your sessions are still on this phone, and "
                     + "the newer build will find them exactly where it left them.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .readableColumn()
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: Binding(get: { store.restoreOffer },
                             set: { store.restoreOffer = $0 })) { offer in
            RestoreConfirmation(offer: offer)
        }
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.zip],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result {
                Task { await store.offerRestore(urls: urls) }
            }
        }
    }

    /// The release meets this screen after the beta (same bundle id); a beta or dev build
    /// meets it after a newer build of its own (rider review I6).
    private static var wayBack: String {
        #if BETA
        "Install the newer build again, or restore a backup made with this version."
        #else
        "Open the beta again, or restore a backup made with this version."
        #endif
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                openTestFlight()
            } label: {
                Label("Open TestFlight", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                showRestorePicker = true
            } label: {
                Label("Restore from backup", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(store.isBusy)

            Text("Restoring puts the newer library aside — it is not deleted — and builds "
                 + "this one from the backup file you pick.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // **Back up first** (rider review I6, Jan 9 Oct 2026). A rider who wants the
            // App Store version for good goes back to the beta once, backs up there, and
            // the first App Store update that has caught up opens that file. The `?` opens
            // the backup topic, which carries the same way back as its last item.
            // Release only: in the beta and dev builds the newer library is their own.
            #if !BETA
            Text(BetaGuide.leavingTheBeta)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            #endif
            HelpTopicLink(.libraryBackup, label: BetaGuide.backupHelpLabel) {
                helpTopic = .libraryBackup
            }
            .sheet(item: $helpTopic) { HelpTopicSheet(id: $0) }
        }
    }

    /// `itms-beta:` goes straight to TestFlight when it is installed, which on a phone in
    /// this state it always is; the https link is the fallback that installs it and is the
    /// same public join link the release channel offers (`AppChannel.testFlight`).
    private func openTestFlight() {
        guard let scheme = URL(string: "itms-beta://testflight.apple.com/join/nygqGGcn") else {
            openURL(AppChannel.testFlight)
            return
        }
        openURL(scheme) { opened in
            if !opened { openURL(AppChannel.testFlight) }
        }
    }
}
