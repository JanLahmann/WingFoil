import MessageUI
import SwiftUI
import UIKit
import WatchConnectivity
import WingFoilKit

/// Beta feedback, prefilled by the app (Jan, 13 Sep 2026: "can we provide a more structured
/// template, or even pre-fill some infos from the app").
///
/// **The problem this solves is not writing, it is answering.** A beta report that says "the
/// jibe count looks wrong" costs three mails to make actionable: which build, which engine,
/// were the thresholds tuned, which session, what did it come in as. Every one of those is a
/// fact the phone already knows and the rider would have to go hunting for — half of them are
/// only on the Settings screen he is not on — so the app writes them and he writes the
/// sentence.
///
/// **Nothing leaves the phone until he taps Send.** This type builds text and hands it to
/// `MFMailComposeViewController`, which is Apple's, shows the mail in full, and is the only
/// thing that can send it. There is no CleanJibe server, no upload and no silent telemetry;
/// the facts below are exactly what a rider can read on the screen before he sends it.
///
/// The *wording* lives in the kit (`FeedbackReport`), where the test suite reads it. What
/// lives here is the gathering, which needs `Bundle`, `UIDevice`, `WCSession` and the store
/// — four things a package test cannot have in the room.
enum FeedbackMail {

    /// A file to send with the report. Only one thing ever uses it: the share card of the
    /// session being complained about, which is a picture of the numbers in question.
    struct Attachment {
        let data: Data
        let filename: String
        let mimeType: String

        static func card(png: Data, sessionID: String) -> Attachment {
            Attachment(data: png, filename: "cleanjibe-\(sessionID.prefix(8)).png",
                       mimeType: "image/png")
        }
    }

    /// Everything the phone knows about itself, plus the session when there is one.
    @MainActor
    static func facts(store: SessionStore, session row: SessionRow? = nil) -> FeedbackFacts {
        FeedbackFacts(app: appFacts(store: store), phone: phoneFacts(),
                      watch: watchFacts(store: store), library: libraryFacts(store: store),
                      session: row.map { sessionFacts($0, store: store) })
    }

    // MARK: - The four sections

    @MainActor
    private static func appFacts(store: SessionStore) -> FeedbackFacts.App {
        let info = Bundle.main.infoDictionary
        #if TUNING
        let isDev = true
        // Only the dev build ever *applies* stored overrides (`SessionStore.init`), so only
        // the dev build may claim any: a public build with a leftover tuning blob in its
        // defaults is running the published thresholds, and saying otherwise would send a
        // reader looking for a difference that is not there.
        let tuned = store.tuning.changedCount
        #else
        let isDev = false
        let tuned = 0
        #endif
        return FeedbackFacts.App(
            version: info?["CFBundleShortVersionString"] as? String ?? "0",
            build: info?["CFBundleVersion"] as? String ?? "0",
            isDev: isDev, engineVersion: AnalysisEngine.version, tunedThresholds: tuned)
    }

    @MainActor
    private static func phoneFacts() -> FeedbackFacts.Phone {
        FeedbackFacts.Phone(model: modelIdentifier(),
                            system: UIDevice.current.systemName + " "
                                + UIDevice.current.systemVersion,
                            locale: Locale.current.identifier)
    }

    /// `hw.machine` — "iPhone18,2". On a simulator that is the *host Mac's* architecture
    /// ("arm64"), so the simulated device's own identifier is read out of the environment
    /// instead; a screenshot run that reported "arm64" would be describing nothing.
    private static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo
            .environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        // `Mirror` over the fixed-size C array rather than a pointer into it: taking the
        // address of `info.machine` while `info` is still being read is an exclusivity
        // violation the compiler refuses outright.
        let identifier = Mirror(reflecting: info.machine).children
            .compactMap { $0.value as? CChar }
            .prefix { $0 != 0 }
            .map { String(UnicodeScalar(UInt8($0))) }
            .joined()
        return identifier.isEmpty ? "unknown" : identifier
    }

    @MainActor
    private static func watchFacts(store: SessionStore) -> FeedbackFacts.Watch {
        FeedbackFacts.Watch(garminModel: store.companionState.deviceName,
                            garminAppVersion: store.lastCardWatchAppVersion
                                .flatMap(watchAppVersion),
                            appleWatchPaired: appleWatchPaired(),
                            healthImport: store.healthAutoImport)
    }

    /// The watch's build tag, spelled out: the card carries `APP_MINOR * 256 + SCHEMA`
    /// (`garmin/source/fit/FitFields.mc`), and the two halves are what a divergence report
    /// needs — the minor says which watch release, the schema which FIT field set.
    private static func watchAppVersion(_ tag: Int) -> String? {
        guard tag > 0 else { return nil }
        return "0.\(tag >> 8) (FIT schema \(tag & 0xFF))"
    }

    /// nil rather than false when the question cannot be asked yet: `isPaired` means nothing
    /// until the session has activated, and "no Apple Watch" is a claim, not a default.
    private static func appleWatchPaired() -> Bool? {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return nil }
        return WCSession.default.isPaired
    }

    @MainActor
    private static func libraryFacts(store: SessionStore) -> FeedbackFacts.Library {
        FeedbackFacts.Library(
            sessionCount: store.sessions.count,
            sources: FeedbackFacts.Library.sources(
                importSources: store.sessions.map(\.importSource)))
    }

    @MainActor
    private static func sessionFacts(_ row: SessionRow,
                                     store: SessionStore) -> FeedbackFacts.Session {
        FeedbackFacts.Session(
            id: row.id,
            // The session's own zone, like every other date in the app: a report that
            // renamed the afternoon into the reader's timezone would name a different one.
            date: Fmt.date(row.startDate, zone: row.displayZone),
            spot: store.spot(id: row.spotId)?.name,
            discipline: SessionDisplay.badge(row),
            duration: Fmt.duration(row.durationS),
            sourceClass: row.sourceClass,
            engineStamp: row.engineVersion)
    }
}

// MARK: - The composer

/// `MFMailComposeViewController`, wrapped.
///
/// The whole mail is Apple's from here on: the rider sees the recipient, the subject, the
/// body and the attachment, can edit every one of them, and iOS sends it from his own
/// account or not at all.
struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    /// Not `body`: a `UIViewControllerRepresentable` **is** a `View`, and a stored property
    /// of that name is read as the `View.body` witness rather than as the mail's text.
    let messageBody: String
    var attachment: FeedbackMail.Attachment?
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackReport.recipient])
        controller.setSubject(subject)
        controller.setMessageBody(messageBody, isHTML: false)
        if let attachment {
            controller.addAttachmentData(attachment.data, mimeType: attachment.mimeType,
                                         fileName: attachment.filename)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    /// The delegate requirement is `nonisolated` — a main-actor method cannot witness it —
    /// so the callback is too, and states the isolation it actually has.
    ///
    /// `assumeIsolated` rather than a `Task { @MainActor in … }` hop for two reasons: UIKit
    /// has always called this on the main thread, and a hop would let the mail sheet outlive
    /// its own dismissal by a turn of the run loop. The closure is lifted into a local first
    /// so that `self` — a non-`Sendable` `NSObject` — is not what crosses into the closure;
    /// the same trap `WatchSessionReceiver` documents from the other side.
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func mailComposeController(_ controller: MFMailComposeViewController,
                                               didFinishWith result: MFMailComposeResult,
                                               error: (any Error)?) {
            // `nonisolated(unsafe)` states what the callback's own contract already
            // guarantees and the type system cannot see: this method runs on the main
            // thread, so the closure is not crossing an isolation boundary at all.
            nonisolated(unsafe) let finish = onFinish
            MainActor.assumeIsolated { finish() }
        }
    }
}

// MARK: - The row

/// The "Send feedback" row, wherever it is offered.
///
/// One view for both homes — Settings, and the session's share sheet — because the only
/// difference between them is the title, the session in the facts and whether the card comes
/// along. Two copies of the "is Mail configured, and what if it is not" ladder would be two
/// places to get the fallback wrong.
struct FeedbackMailRow: View {
    let title: String
    var systemImage = "envelope"
    /// The session the report is about; nil from Settings.
    var session: SessionRow?
    /// The session's share card, when the caller has one rendered. Called at the moment of
    /// the tap rather than held, so a sheet that has not finished drawing does not pay for a
    /// PNG nobody asked for.
    var card: () -> Data? = { nil }

    @Environment(SessionStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var draft: Draft?
    @State private var fallback: Draft?

    /// A composed report, held only while one of the two sheets is up.
    private struct Draft: Identifiable {
        let id = UUID()
        let facts: FeedbackFacts
        let attachment: FeedbackMail.Attachment?

        var subject: String { FeedbackReport.subject(facts) }
        var body: String { FeedbackReport.body(facts) }
    }

    var body: some View {
        Button { compose() } label: {
            Label(title, systemImage: systemImage)
        }
        .sheet(item: $draft) { draft in
            MailComposeView(subject: draft.subject, messageBody: draft.body,
                            attachment: draft.attachment) { self.draft = nil }
                .ignoresSafeArea()
        }
        .sheet(item: $fallback) { draft in
            FeedbackFallbackSheet(subject: draft.subject, report: draft.body)
        }
        #if DEBUG && targetEnvironment(simulator)
        // `UI_FEEDBACK=fallback` opens the fallback sheet on launch: a simulator can never
        // send mail, and `simctl` cannot tap the row that would prove it.
        .task {
            guard session == nil,
                  ProcessInfo.processInfo.environment["UI_FEEDBACK"] == "fallback"
            else { return }
            fallback = Draft(facts: FeedbackMail.facts(store: store), attachment: nil)
        }
        #endif
    }

    /// Mail if the phone has it, the system's `mailto:` handler if not, and the sheet with
    /// the copy button when even that goes nowhere — a phone with no mail app at all, which
    /// is a real configuration and is exactly the one a rider cannot fix from here.
    private func compose() {
        let png = card()
        let attachment = png.flatMap { data in
            session.map { FeedbackMail.Attachment.card(png: data, sessionID: $0.id) }
        }
        let composed = Draft(facts: FeedbackMail.facts(store: store, session: session),
                             attachment: attachment)
        guard MFMailComposeViewController.canSendMail() else {
            guard let url = FeedbackReport.mailtoURL(composed.facts) else {
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

/// The last resort: the report, in full, with one button that copies it.
///
/// It exists because the two routes above can both be closed — no mail account, and no app
/// registered for `mailto:` — and the rider is then holding a bug report he cannot send from
/// a screen that promised he could. Showing him the text means he can paste it into whatever
/// he does use, which on a phone is usually a messenger.
private struct FeedbackFallbackSheet: View {
    let subject: String
    let report: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("No mail account is set up on this phone, so CleanJibe cannot open "
                         + "a mail for you. Copy the report and send it from wherever you "
                         + "write to us — \(FeedbackReport.recipient).")
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
            .navigationTitle("Send feedback")
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
