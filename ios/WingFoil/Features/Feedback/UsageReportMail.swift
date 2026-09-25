#if BETA
import MessageUI
import SwiftUI
import UIKit
import WingFoilKit

/// **The beta's usage report** — a short sheet, then the mail (docs/channels.md, "What the
/// usage report counts"; docs/presentation/status-feedback-start-widgets-ipad.md, "The
/// beta's usage report").
///
/// Two things reach it: the card the library puts at the top of the list every fifth
/// session or fortnight (`UsageAskCard`), and the permanent row in Settings → Beta. Both
/// open the same sheet: *Your feedback* first, because the tester's own sentence is worth
/// more than any counter, then the Normal / Extended switch. *Write mail* composes the body
/// in the kit (`UsageReportText`) and hands it to Mail, where every line is still his to
/// read and delete before he sends it.
///
/// **Why the separator sentence is in the mail rather than on a screen before it.** The
/// rider reads the block in the mail, and the sentence he needs while reading it is "this
/// is what it is, and you may delete any line of it". A consent screen in front of the
/// composer would be asking him to agree to something he has not seen yet.
enum UsageReportMail {

    /// The prefilled body: his words, the rule, the facts, the counters.
    @MainActor
    static func body(store: SessionStore, feedback: String,
                     layout: UsageCounters.ReportLayout) -> String {
        UsageReportText.body(facts: FeedbackMail.facts(store: store), feedback: feedback,
                             counters: Usage.counters, layout: layout)
    }
}

// MARK: - Presenting it

extension View {

    /// Opens the usage report's sheet every time `request` changes. A counter rather than
    /// a `Bool`, for the same reason `feedbackMail(on:)` uses one: the thing that asks — a
    /// card that then goes away, a row in a sheet — is not reliably in the view tree when
    /// the sheet would have to present.
    func usageReportMail(on request: Binding<Int>) -> some View {
        modifier(UsageReportPresenter(request: request))
    }
}

private struct UsageReportPresenter: ViewModifier {
    @Binding var request: Int

    @Environment(SessionStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var asking = false
    /// The sheet's answer, held until the sheet has gone: one view cannot present two
    /// sheets at once.
    @State private var answer: Answer?
    @State private var draft: Draft?
    @State private var fallback: Draft?

    private struct Answer {
        let feedback: String
        let layout: UsageCounters.ReportLayout
    }

    private struct Draft: Identifiable {
        let id = UUID()
        let body: String
        var subject: String { UsageReportText.subject }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, _ in asking = true }
            .sheet(isPresented: $asking, onDismiss: {
                guard let answered = answer else { return }
                answer = nil
                compose(answered)
            }) {
                UsageReportSheet { feedback, layout in
                    answer = Answer(feedback: feedback, layout: layout)
                }
            }
            .sheet(item: $draft) { draft in
                MailComposeView(subject: draft.subject, messageBody: draft.body,
                                attachment: nil, feature: .usageReport) { self.draft = nil }
                    .ignoresSafeArea()
            }
            .sheet(item: $fallback) { draft in
                UsageReportFallbackSheet(subject: draft.subject, report: draft.body)
            }
    }

    /// The same ladder the feedback mail climbs: Mail, then whatever answers `mailto:`,
    /// then the text itself with a button that copies it.
    private func compose(_ answer: Answer) {
        // Counted here rather than at the tap, because this is the path both doors share,
        // and the ask is spent the same way whichever of them was used. The try is counted
        // now; Mail's "sent" is its answer (`MailComposeView`).
        Usage.started(.usageReport)
        Usage.askAnswered(snooze: false)
        let composed = Draft(body: UsageReportMail.body(store: store,
                                                        feedback: answer.feedback,
                                                        layout: answer.layout))
        guard MFMailComposeViewController.canSendMail() else {
            guard let url = UsageReportText.mailtoURL(subject: composed.subject,
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

/// **Your feedback, and how much of the counters to send.**
///
/// The free text first and focused, because the tester opened this to say something more
/// often than to send numbers. The switch under it opens on Normal: one line per feature
/// is what a reader tallies across twenty mails, and Extended is there for the phone
/// where something keeps failing.
private struct UsageReportSheet: View {
    let onWrite: (String, UsageCounters.ReportLayout) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedback = ""
    @State private var layout = UsageCounters.ReportLayout.normal
    @FocusState private var writing: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(UsageReportText.feedbackPrompt, text: $feedback, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($writing)
                } header: {
                    Text(UsageReportText.feedbackHeading)
                }

                Section {
                    Picker("Usage report", selection: $layout) {
                        ForEach(UsageCounters.ReportLayout.allCases) {
                            Text($0.label).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(UsageReportText.layoutFooter)
                }
            }
            .navigationTitle("Usage report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Write mail") {
                        onWrite(feedback, layout)
                        dismiss()
                    }
                }
            }
            .onAppear { writing = true }
        }
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

            Text("Tell us what works and what you miss. The mail adds which features you "
                 + "used and whether they worked. You read it before you send it. "
                 + "A feature reaches the App Store once testers show it works.")
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
