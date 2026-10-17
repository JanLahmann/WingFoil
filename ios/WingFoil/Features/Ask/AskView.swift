#if DEV
import SwiftUI
import WingFoilKit

/// **Ask CleanJibe** — dev only (docs/channels.md). A question box over the help texts, or
/// over one session's numbers when it is opened from a session.
///
/// The first time, the consent page comes first (the iPhone's consent is a one-time page,
/// Jan 15 Oct 2026; the website's is a line that is always on screen): what is sent, to whom,
/// for how long. Nothing leaves the phone before the rider taps Continue and then sends.
struct AskView: View {
    let context: AskClient.Context
    /// The app's facts, and with the session context that session's numbers
    /// (`AssistantState`, docs/copy/assistant/session-state.schema.json).
    let state: Data

    @Environment(\.dismiss) private var dismiss
    @AppStorage("ask.consented") private var consented = false

    var body: some View {
        NavigationStack {
            Group {
                if consented {
                    AskChat(context: context, state: state)
                } else {
                    AskConsent(context: context) { consented = true }
                }
            }
            .navigationTitle("Ask CleanJibe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Consent

private struct AskConsent: View {
    let context: AskClient.Context
    let agree: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text("Ask about the app, or about a session.")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 10) {
                    point("paperplane", "Your question goes with the app's version and your units, through Cloudflare, to Anthropic. Their Claude answers from our help texts.")
                    point("list.bullet.rectangle", "Asked from a session, that session's numbers go too: date, times, speeds, flights and every turn's verdict. No map, no positions, no name.")
                    point("clock", "We keep the question and the answer for 30 days to improve the answers, then they are deleted.")
                    point("iphone", "Apple confirms the question comes from this app. That is how we count 20 questions a day. No account, no cookie.")
                    point("hand.raised", "Please don't type personal details into the box.")
                }
                Button(action: agree) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
                Link("CleanJibe's privacy page",
                     destination: URL(string: Branding.siteURL + "/privacy/")!)
                    .font(.footnote)
                Link("Anthropic's privacy policy",
                     destination: URL(string: "https://www.anthropic.com/legal/privacy")!)
                    .font(.footnote)
            }
            .padding()
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.readableSecondary)
        }
        .font(.subheadline)
    }
}

// MARK: - Chat

private struct AskChat: View {
    let context: AskClient.Context
    let state: Data

    struct Message: Identifiable {
        let id = UUID()
        var mine: Bool
        var text: String
        var answerId: String?
        var vote = 0
        var failed = false
    }

    @AppStorage("ask.consented") private var consented = true
    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var asking: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var busy: Bool { asking != nil }

    private var starters: [String] {
        switch context {
        case .help: ["What is CPH?", "How do I get a session from my Garmin?",
                     "What is the difference between the watch app and the phone?"]
        case .session: ["Why was a jibe a touchdown?", "Which turns did I fly through?",
                        "How did this session go?"]
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty { intro }
                    ForEach($messages) { $m in bubble($m).id(m.id) }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.text) {
                if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .onDisappear { asking?.cancel() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(context == .session
                 ? "Ask about this session. The answer reads its numbers and never guesses one."
                 : "Ask how CleanJibe works or what a number means.")
                .font(.subheadline)
                .foregroundStyle(.readableSecondary)
            if !AskClient.isSupported {
                Label(AskClient.Failure.unsupported.message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
            }
            // The consent page again, on request (rider review, 16 Oct 2026): it shows once.
            Button("What is sent") { consented = false }
                .font(.footnote)
            ForEach(starters, id: \.self) { q in
                Button(q) { send(q) }
                    .buttonStyle(.bordered)
                    .disabled(busy || !AskClient.isSupported)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ m: Binding<Message>) -> some View {
        let msg = m.wrappedValue
        if msg.mine {
            Text(msg.text)
                .padding(10)
                .background(.tint.opacity(0.15), in: .rect(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if msg.text.isEmpty && !msg.failed {
                    ProgressView()
                } else {
                    Text(Self.markdown(msg.text))
                        .foregroundStyle(msg.failed ? Color.readableSecondary : Color.primary)
                        .textSelection(.enabled)
                }
                if let id = msg.answerId, !id.isEmpty {
                    HStack(spacing: 14) {
                        thumb(m, id: id, value: 1, symbol: "hand.thumbsup")
                        thumb(m, id: id, value: -1, symbol: "hand.thumbsdown")
                    }
                    .font(.footnote)
                    .foregroundStyle(.readableSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func thumb(_ m: Binding<Message>, id: String, value: Int, symbol: String) -> some View {
        let on = m.wrappedValue.vote == value
        return Button {
            m.wrappedValue.vote = on ? 0 : value
            if !on { Task { await AskClient.shared.vote(id, value) } }
        } label: {
            Image(systemName: on ? symbol + ".fill" : symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value > 0 ? "Helpful" : "Not helpful")
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Your question", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send(draft) }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || !AskClient.isSupported)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ raw: String) {
        let question = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !question.isEmpty, !busy else { return }
        // Earlier answered pairs only: the Worker wants user/assistant alternating, ending on an answer.
        var history: [AskClient.Turn] = []
        var i = 0
        while i + 1 < messages.count {
            let q = messages[i], a = messages[i + 1]
            if q.mine, !a.mine, !a.failed, !a.text.isEmpty {
                history += [.init(role: "user", content: q.text), .init(role: "assistant", content: a.text)]
            }
            i += 2
        }
        draft = ""
        messages.append(Message(mine: true, text: question))
        messages.append(Message(mine: false, text: ""))
        let index = messages.count - 1
        asking = Task {
            do {
                for try await event in await AskClient.shared.ask(
                    question, context: context, state: state, history: history) {
                    switch event {
                    case .delta(let t): messages[index].text += t
                    case .done(let id): messages[index].answerId = id
                    }
                }
            } catch {
                let failure = error as? AskClient.Failure ?? .server
                if messages[index].text.isEmpty { messages[index].text = failure.message }
                messages[index].failed = true
            }
            asking = nil
        }
    }

    private static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
#endif
