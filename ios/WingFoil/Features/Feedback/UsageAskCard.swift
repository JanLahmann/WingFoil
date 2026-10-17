#if BETA
import SwiftUI
import WingFoilKit

// The usage report is not a mail of its own any more (Jan, 17 Oct 2026: one mail, one sheet,
// in every channel). Its counters ride in the feedback mail when *Usage statistics* is on
// (`FeedbackAskSheet`, `UsageReportText`), and what is left here is the beta's reminder.

/// **The ask** — at the top of the library, every fifth session imported or a fortnight
/// after the last one, whichever comes first (`UsageCounters.askIsDue`).
///
/// A card in the list rather than an alert. An alert interrupts whatever the rider opened
/// the app to look at, and the honest answer to "help the beta" is often "not while I am
/// standing on a beach" — so it waits in the place he is already looking, and the "Not now"
/// beside it buys a fortnight of quiet rather than ending the conversation.
struct UsageAskCard: View {
    /// Bumped to open the composer. It belongs to the **list**, not to this card: the card
    /// is gone the instant it is answered, and a sheet hung on a view that has just left
    /// the tree never presents — the trap `feedbackMail(on:)` documents from the other
    /// side. `LibraryView` mounts `feedbackMail(on:usageAsk:)` and owns this counter.
    @Binding var request: Int
    /// Set to false by either button, so the card goes the moment it is answered rather
    /// than on the next launch.
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Help the beta: send your feedback", systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.weight(.semibold))

            Text("Tell us what works and what you miss. The mail adds which features you "
                 + "used and whether they worked. You read it before you send it. "
                 + "A feature reaches the App Store once testers show it works.")
                .font(.footnote)
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    request += 1
                    isShowing = false
                } label: {
                    Text("Write the mail")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    Usage.askAnswered(snooze: true)
                    isShowing = false
                } label: {
                    Text("Not now")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
