#if BETA
import MessageUI
import SwiftUI
import UIKit
import WingFoilKit

/// **The beta's usage report** — the ordinary feedback mail with one more block at the foot
/// of it (docs/channels.md, "Beta section"; docs/presentation/status-feedback-start-widgets-ipad.md, "The beta's usage report").
///
/// Two things reach it: the card the library puts at the top of the list every fifth
/// session or fortnight (`UsageAskCard`), and the permanent row in Settings → Beta. Both
/// open the same composer with the same subject, so a mailbox sorted by subject has one
/// thread of them rather than two.
///
/// **Why the separator sentence is in the mail rather than on a screen before it.** The
/// rider is going to read the block — that is the whole design — and the sentence he needs
/// while reading it is "this is what it is, and you may delete any line of it". A consent
/// screen in front of the composer would be asking him to agree to something he has not
/// seen yet, which is the shape of a dialog nobody reads.
///
/// **A note for whoever unifies this with `FeedbackMail`.** This file presents its own
/// `MFMailComposeViewController` — through `MailComposeView`, which is shared — because
/// `feedbackMail(on:)` composes its body from `FeedbackFacts` and takes a subject override
/// but no body override. When that modifier grows a `body:` parameter, everything below
/// `UsageReportMail.body` can go and the two rows can call it instead.
enum UsageReportMail {

    /// One subject for both doors. Not the report's — "CleanJibe beta feedback · build 23 ·
    /// fenix 8" — because this mail is not a report of anything going wrong, and a mailbox
    /// that files it as one answers it as one.
    static let subject = Branding.appName + " beta usage report"

    /// The sentence between the facts and the counters. It says the two things a rider
    /// needs before he taps Send: what the block is, and that it is his to edit.
    static let separator =
        "The block below is what the beta counts on this phone. It helps development and "
        + "is a key part of being in the beta. " + Copy.deleteAnyLine

    /// The prefilled body: the ordinary report, the sentence, the counters.
    @MainActor
    static func body(store: SessionStore) -> String {
        [FeedbackReport.body(FeedbackMail.facts(store: store)),
         separator,
         Usage.report(appVersion: SessionStore.appVersion)]
            .joined(separator: "\n\n")
    }

    /// The `mailto:` fallback, escaped the way `FeedbackReport.mailtoURL` escapes: through
    /// a character set with `&`, `=`, `+` and `?` removed, because a body carrying any of
    /// them would otherwise be cut short at that character.
    static func mailtoURL(subject: String, body: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed
            .subtracting(CharacterSet(charactersIn: "&=+?"))
        guard let subject = subject.addingPercentEncoding(withAllowedCharacters: allowed),
              let body = body.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = FeedbackReport.recipient
        components.percentEncodedQuery = "subject=\(subject)&body=\(body)"
        return components.url
    }
}

// MARK: - Presenting it

extension View {

    /// Composes and presents the usage report every time `request` changes. A counter
    /// rather than a `Bool`, for the same reason `feedbackMail(on:)` uses one: the thing
    /// that asks — a card that then goes away, a row in a sheet — is not reliably in the
    /// view tree when the sheet would have to present.
    func usageReportMail(on request: Binding<Int>) -> some View {
        modifier(UsageReportPresenter(request: request))
    }
}

private struct UsageReportPresenter: ViewModifier {
    @Binding var request: Int

    @Environment(SessionStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var draft: Draft?
    @State private var fallback: Draft?

    private struct Draft: Identifiable {
        let id = UUID()
        let body: String
        var subject: String { UsageReportMail.subject }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, _ in compose() }
            .sheet(item: $draft) { draft in
                MailComposeView(subject: draft.subject, messageBody: draft.body,
                                attachment: nil) { self.draft = nil }
                    .ignoresSafeArea()
            }
            .sheet(item: $fallback) { draft in
                UsageReportFallbackSheet(subject: draft.subject, report: draft.body)
            }
    }

    /// The same ladder the feedback mail climbs: Mail, then whatever answers `mailto:`,
    /// then the text itself with a button that copies it.
    private func compose() {
        // Counted here rather than at the tap, because this is the path both doors share —
        // and the ask is spent the same way whichever of them was used.
        Usage.record(.feedbackMail)
        Usage.askAnswered(snooze: false)
        let composed = Draft(body: UsageReportMail.body(store: store))
        guard MFMailComposeViewController.canSendMail() else {
            guard let url = UsageReportMail.mailtoURL(subject: composed.subject,
                                                      body: composed.body) else {
                fallback = composed
                return
            }
            openURL(url) { opened in
                if !opened { fallback = composed }
            }
            return
        }
        draft = composed
    }
}

/// The last resort: the report in full, with one button that copies it. Same shape as the
/// feedback mail's own fallback, and the same reason — a phone with no mail account and no
/// `mailto:` handler is a real configuration, and it is the one the rider cannot fix from
/// this screen.
private struct UsageReportFallbackSheet: View {
    let subject: String
    let report: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("No mail account is set up on this phone. "
                         + Copy.copyTheReportInstead)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subject)
                        .font(.subheadline.weight(.semibold))
                        .textSelection(.enabled)

                    Text(report)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground),
                                    in: .rect(cornerRadius: 14))

                    Button {
                        UIPasteboard.general.string = subject + "\n\n" + report
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy the report",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
                .readableColumn()
            }
            .navigationTitle("Usage report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationSizing(.page)
        }
    }
}

// MARK: - The row, and the card

/// Settings → Beta, permanently. The rider who wants to send one without waiting to be
/// asked, and the one who just said "Not now" and changed his mind.
struct UsageReportRow: View {
    @State private var request = 0

    var body: some View {
        Button { request += 1 } label: {
            Label("Send usage report", systemImage: "chart.bar.doc.horizontal")
        }
        .usageReportMail(on: $request)
    }
}

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
    /// side. `LibraryView` mounts `usageReportMail(on:)` and owns this counter.
    @Binding var request: Int
    /// Set to false by either button, so the card goes the moment it is answered rather
    /// than on the next launch.
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Help the beta: send your usage report", systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.weight(.semibold))

            Text("A mail you read and edit before you send it. It carries which parts of "
                 + "CleanJibe you have used, how often, and anything that has gone wrong "
                 + "on this phone. It decides which doors open for everyone else.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
