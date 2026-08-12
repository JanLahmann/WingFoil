import SwiftUI
import WingFoilKit

/// The one place an intervals.icu API key is ever typed — Settings and the first-run
/// setup card both embed this view.
///
/// Saving and *proving* are one action here: a key that was accepted by the keychain but
/// rejected by intervals.icu would otherwise look identical to a working one until the
/// next pull-to-refresh. The check is a single list call, and the key itself never appears
/// in a message, a status line or a log — only the outcome does.
struct IcuKeyEntry: View {
    @Environment(SessionStore.self) private var store

    /// The card version repeats less chrome than the Settings version.
    var showsPrivacyNote = true

    @State private var draft = ""
    @State private var loaded = false

    private var isUnchanged: Bool { draft.trimmingCharacters(in: .whitespaces) == store.apiKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("Personal API key", text: $draft)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .disabled(store.apiKeyIsInjected)

            HStack(spacing: 12) {
                Button {
                    Task { await store.saveAndCheckApiKey(draft) }
                } label: {
                    HStack(spacing: 6) {
                        if store.isCheckingKey { ProgressView().controlSize(.small) }
                        Text(isUnchanged && !draft.isEmpty ? "Check connection" : "Save & check")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.apiKeyIsInjected || store.isCheckingKey
                          || (draft.isEmpty && store.apiKey.isEmpty))

                if !draft.isEmpty && !store.apiKeyIsInjected {
                    Button("Clear") {
                        draft = ""
                        store.setApiKey("")
                    }
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 0)
            }

            result

            if showsPrivacyNote && !store.apiKeyIsInjected {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    Text("Stored in this iPhone's Keychain, sent only to intervals.icu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HelpButton(topic: .icuPrivacy, size: .caption)
                }
            }
            if store.apiKeyIsInjected {
                Text("Using the ICU_API_KEY scheme environment variable (DEBUG build).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard !loaded else { return }
            draft = store.apiKey
            loaded = true
        }
    }

    /// The inline verdict: green when the key demonstrably works, amber when it works but
    /// there is nothing behind it yet, red when it does not.
    @ViewBuilder
    private var result: some View {
        switch store.keyCheck {
        case .success(let report):
            VStack(alignment: .leading, spacing: 6) {
                line("checkmark.circle.fill", .green, report.message)
                if let caveat = report.caveat {
                    line("exclamationmark.triangle.fill", .orange, caveat.fix)
                }
            }
        case .failure(let problem):
            VStack(alignment: .leading, spacing: 6) {
                line("xmark.octagon.fill", .red, "\(problem.title). \(problem.message)")
                line("wrench.and.screwdriver.fill", .secondary, problem.fix)
            }
        case nil:
            EmptyView()
        }
    }

    private func line(_ symbol: String, _ tone: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.caption).foregroundStyle(tone)
            Text(text)
                .font(.caption)
                .foregroundStyle(tone == .secondary ? Color.secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
