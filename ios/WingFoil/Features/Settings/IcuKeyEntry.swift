import SwiftUI
import WingFoilKit

/// The one place an intervals.icu API key is ever typed — Settings and the first-run
/// setup card both embedded this view; since dev 70 Settings is its one home.
///
/// Saving and *proving* are one action here: a key that was accepted by the keychain but
/// rejected by intervals.icu would otherwise look identical to a working one until the
/// next pull-to-refresh. The check is a single list call, and the key itself never appears
/// in a message, a status line or a log — only the outcome does.
struct IcuKeyEntry: View {
    @Environment(SessionStore.self) private var store

    /// The card version repeats less chrome than the Settings version.
    var showsPrivacyNote = true

    /// A new key being typed. Never the stored one: the stored key is not put back into a
    /// field, it is shown as saved.
    @State private var draft = ""
    /// True while a saved key is being replaced, which brings the field back.
    @State private var replacing = false

    private var hasSavedKey: Bool { !store.apiKey.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasSavedKey && !replacing {
                savedKey
            } else {
                keyField
            }

            result

            if showsPrivacyNote && !store.apiKeyIsInjected {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    Text("Stored in this iPhone's Keychain, sent only to intervals.icu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HelpButton(topic: .privacy, size: .caption)
                }
            }
            if store.apiKeyIsInjected {
                Text("Using the ICU_API_KEY scheme environment variable. DEBUG build only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // A process that could not read the keychain at launch gets a second look when the
        // rider opens this screen (`SessionStore.reloadApiKeyIfMissing`).
        .task { store.reloadApiKeyIfMissing() }
    }

    /// **A saved key says so** (Jan, dev 106). The field used to be filled with the stored
    /// key, so an empty field was the only sign of a missing one, and a field that looks
    /// empty reads as "no key" either way. The key itself is never shown, only that it is
    /// there, with the three things a rider does with it.
    private var savedKey: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent {
                Text("••••••••")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } label: {
                Label("API key saved", systemImage: "key.fill")
            }
            HStack(spacing: 12) {
                Button {
                    Task { await store.checkApiKey() }
                } label: {
                    HStack(spacing: 6) {
                        if store.isCheckingKey { ProgressView().controlSize(.small) }
                        Text("Check connection")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isCheckingKey)

                if !store.apiKeyIsInjected {
                    Button("Replace") {
                        draft = ""
                        replacing = true
                    }
                    .buttonStyle(.borderless)
                    Button("Remove", role: .destructive) {
                        store.setApiKey("")
                    }
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The field, for a first key or a replacement. Saving and checking stay one action.
    private var keyField: some View {
        VStack(alignment: .leading, spacing: 10) {
            // `appTextFieldChrome` rather than `.roundedBorder`: that style fills itself
            // with `systemBackground`, which is pure black in dark mode, and this field is
            // drawn on the setup card's near-black `secondarySystemBackground` — the two
            // together were a solid black bar with nothing in it to tap (Jan, build 58).
            SecureField(replacing ? "New API key" : "Personal API key", text: $draft)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .appTextFieldChrome()
                .disabled(store.apiKeyIsInjected)

            HStack(spacing: 12) {
                Button {
                    let key = draft
                    Task {
                        await store.saveAndCheckApiKey(key)
                        draft = ""
                        replacing = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if store.isCheckingKey { ProgressView().controlSize(.small) }
                        Text(IcuSetupGuide.saveButton)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.apiKeyIsInjected || store.isCheckingKey
                          || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if replacing {
                    // Back to the saved key, untouched.
                    Button("Cancel") {
                        draft = ""
                        replacing = false
                    }
                    .buttonStyle(.borderless)
                } else if !draft.isEmpty && !store.apiKeyIsInjected {
                    Button("Clear") { draft = "" }
                        .buttonStyle(.borderless)
                }
                Spacer(minLength: 0)
            }
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
