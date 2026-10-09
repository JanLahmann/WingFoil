import SwiftUI
import UniformTypeIdentifiers
import WingFoilKit

/// **Strava is full, and here is what still works** (rider review I5, 9 October 2026).
///
/// Strava lets an unreviewed application connect ten riders. The eleventh one to tap
/// *Connect with Strava* used to get a modal that named the cap and a menu path, and then
/// nothing on the screen he was standing on. Pattern B (docs/review-checklist.md): where a
/// text names an action, the control is there.
///
/// So the refusal stays on the Strava section that raised it, for as long as it is true
/// (`SyncTroubles` keeps it until a connect succeeds), with the two things a refused rider
/// can do right now: bring the same session in as a file, which Strava hands out as
/// *Export Original* on its desktop page, and tell us, which is how CleanJibe asks Strava
/// for more seats. The file picker is this view's own, so the button works from Settings and
/// from Import alike without either screen handing anything down. The feedback mail is the
/// menu's, handed down as `sendFeedback` the way the Help sheet gets it; a screen with no
/// such door simply shows no such button.
///
/// Every channel: the refusal, the file door and the mail are all in the release.
struct StravaFullFix: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.sendFeedback) private var sendFeedback
    @State private var choosingFile = false

    /// The trouble line, the way out, and the two buttons. Drawn only while the last connect
    /// was refused for the cap, so a rider who never met it never reads about it here.
    var body: some View {
        if let trouble = store.syncTroubles[.strava], trouble.kind == .stravaFull {
            Text(trouble.settingsLine)
                .font(.footnote)
                .foregroundStyle(.orange)
            Text(Copy.stravaFullExport)
                .font(.footnote)
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                choosingFile = true
            } label: {
                Label("Import a file instead", systemImage: "doc.badge.plus")
            }
            .disabled(store.isBusy)
            .fileImporter(isPresented: $choosingFile,
                          allowedContentTypes: ImportView.importableTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await store.importPicked(urls: urls) }
                }
            }
            if let send = sendFeedback {
                Button {
                    send()
                } label: {
                    Label("Tell us Strava is full", systemImage: "envelope")
                }
            }
        }
    }
}
