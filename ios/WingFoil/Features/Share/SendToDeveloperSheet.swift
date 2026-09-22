#if BETA
import MessageUI
import SwiftUI
import WingFoilKit

/// **"Send this session to the developer"** — the Share page's third thing (Jan,
/// 21 September 2026).
///
/// The two doors beside it answer "send this to someone": a picture to look at, a recording
/// to open. This one answers a different request — *this number is wrong* — and the only
/// way to chase that is on the recording that produced it. Everything the answer needs goes
/// in one mail: the rider's note, the archived original, and the same fact sheet the
/// feedback mail prints, with this session's headline numbers under it.
///
/// **Nothing is sent by the app.** The sheet composes text, hands it to
/// `MFMailComposeViewController` and stops; the rider reads the whole mail, edits or
/// deletes any line of it, and iOS sends it from his own account or not at all. There is no
/// CleanJibe server for it to reach. That is the same contract `FeedbackMail` documents,
/// and it is why the consent sentence above the button can be short: it says what is in the
/// file, not what the app promises to do with it.
///
/// BETA (docs/channels.md). The whole file is behind the flag, so the App Store build has
/// no button, no sheet and no attachment path.
struct SendToDeveloperSheet: View {
    let row: SessionRow
    /// The analysis, when the page has it. Its absence costs the headline numbers and the
    /// divergence lines and nothing else: the mail is still worth sending.
    var detail: SessionDetail?

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var comment = ""
    @State private var draft: Draft?
    @State private var fallback: Draft?
    @FocusState private var typing: Bool

    /// The composed mail, held only while the composer is up.
    private struct Draft: Identifiable {
        let id = UUID()
        let subject: String
        let body: String
        let attachment: FeedbackMail.Attachment?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        // `axis: .vertical` rather than a `TextEditor`: the field has to
                        // grow with what is typed and still carry a placeholder, and a
                        // `TextEditor` has no placeholder of its own.
                        TextField(SessionAnalysisMail.prompt, text: $comment,
                                  axis: .vertical)
                            .lineLimit(4...10)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.sentences)
                            .focused($typing)
                        Text("Say what you saw and where. A turn number or a time is "
                             + "enough.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // The consent sentence, above the button and not in a footnote: the
                    // rider is about to attach a recording of where he rides, and the three
                    // facts about it belong where the decision is taken.
                    VStack(alignment: .leading, spacing: 8) {
                        Label(attachmentTitle, systemImage: "paperclip")
                            .font(.subheadline.weight(.semibold))
                        Text(SessionAnalysisMail.consent)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))

                    Button { compose() } label: {
                        Label("Write the mail", systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("You see the whole mail before it goes. Nothing is sent until you "
                         + "tap Send.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .readableColumn()
            }
            .navigationTitle("Send to the developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HelpButton(topic: .sendSessionToDeveloper, size: .body)
                }
            }
            .sheet(item: $draft) { draft in
                MailComposeView(subject: draft.subject, messageBody: draft.body,
                                attachment: draft.attachment) {
                    self.draft = nil
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .sheet(item: $fallback) { draft in
                SendToDeveloperFallbackSheet(subject: draft.subject, report: draft.body)
            }
            .presentationSizing(.page)
        }
    }

    /// What is going with the mail, named in the rider's words rather than by extension.
    private var attachmentTitle: String {
        switch store.analysisAttachment(for: row) {
        case .some(let file) where file.isRecording: "Your recording goes with it"
        case .some: "Your track goes with it"
        case nil: "No recording could be read"
        }
    }

    /// Gathers, composes, and picks the route iOS actually has.
    ///
    /// The ladder is `FeedbackMailPresenter`'s, for the same reason: a phone with no mail
    /// account and no `mailto:` handler is a real configuration, and a rider holding a
    /// report he cannot send from a screen that promised he could is the failure worth
    /// spending a fallback sheet on.
    private func compose() {
        Usage.record(.feedbackMail)
        let file = store.analysisAttachment(for: row)
        let facts = FeedbackMail.facts(store: store, session: row, detail: detail)
        let composed = Draft(
            subject: SessionAnalysisMail.subject(date: facts.session?.date ?? ""),
            body: SessionAnalysisMail.body(facts, comment: comment,
                                           attachment: file?.described ?? .none),
            attachment: file.map {
                FeedbackMail.Attachment(data: $0.data, filename: $0.filename,
                                        mimeType: $0.mimeType)
            })
        guard MFMailComposeViewController.canSendMail() else {
            // The `mailto:` route cannot carry an attachment — no mail URL scheme can — so
            // the body says which file to add and the rider adds it from Files. Saying so
            // is the whole of it: a mail that silently arrived without the recording would
            // cost the round trip this feature exists to remove.
            guard let url = SessionAnalysisMail.mailtoURL(subject: composed.subject,
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

/// The last resort: the mail, in full, with one button that copies it.
///
/// `FeedbackFallbackSheet`'s twin, and deliberately a second view rather than a shared one:
/// this sheet has a second thing to say, which is that the recording has to be attached by
/// hand from here.
private struct SendToDeveloperFallbackSheet: View {
    let subject: String
    let report: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Copy.noMailAccount + " " + Copy.copyTheReportInstead)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Share the recording separately. The Share page's FIT file tab "
                         + "sends it.")
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
            .navigationTitle("Send to the developer")
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
#endif
