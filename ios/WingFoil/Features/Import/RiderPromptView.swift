import SwiftUI
import WingFoilKit

/// "Whose session is this?", asked once, on the way in.
///
/// The app answers for `.fit` files and appears in the share sheet, so a recording a friend
/// sent — scrubbed by `FitShareFilter` on his phone, identity-free by design — is one tap
/// on a chat attachment away from the library. Nothing in the file says who rode it, and
/// nothing could: attribution is the receiver's to state.
///
/// Getting it wrong is not cosmetic. An unattributed friend's session joins Records,
/// Trends, the gear rollups, the widget and Apple Health, and a fast afternoon of his
/// becomes a personal best of the reader's that no later correction can un-celebrate. So
/// the question is asked *before* the import runs rather than offered as an edit
/// afterwards, and "Mine" — the true answer nearly every time — is one tap.
///
/// Names already in the library are offered as chips: the second file from the same friend
/// should land on the same spelling as the first, which is also what makes "distinct values
/// of the column" a sufficient address book (`LibraryStore.riders`).
struct RiderPromptView: View {
    let pending: SessionStore.PendingImport

    @Environment(SessionStore.self) private var store

    @State private var isFriend = false
    @State private var name = ""
    @State private var known: [String] = []
    @FocusState private var nameFocused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Whose session is this?", selection: $isFriend) {
                        Text("Mine").tag(false)
                        Text("A friend's").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Whose session is this?")
                } footer: {
                    Text(pending.filenames.joined(separator: ", "))
                        .lineLimit(3)
                        .truncationMode(.middle)
                }

                if isFriend {
                    Section {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { confirm() }
                        if !known.isEmpty { knownRiders }
                    } footer: {
                        Text("A friend's session is shown in full — map, chart, replay, "
                             + "everything — but stays out of your records, trends, gear "
                             + "totals and Apple Health.")
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Cancelling imports nothing. There is no safe default for "whose is
                    // it" once the app can be handed a stranger's file.
                    Button("Cancel") { store.cancelPendingImport() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { confirm() }
                        // A friend with no name would be a badge with nothing in it, and a
                        // session excluded from everything for a reason nobody can read.
                        .disabled(isFriend && trimmed.isEmpty)
                }
            }
            .task { known = await store.knownRiders() }
            // The text field is the only thing to do on this screen once "a friend's" is
            // picked; making the rider tap it as well is a step for nothing.
            .onChange(of: isFriend) { _, friend in nameFocused = friend }
        }
        .presentationDetents([.medium])
    }

    private var knownRiders: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(known, id: \.self) { rider in
                    Button(rider) { name = rider }
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(trimmed == rider ? 0.28 : 0.14),
                                    in: .capsule)
                        .foregroundStyle(Color.purple)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    /// Clearing `store.pendingImport` is what dismisses the sheet — the store owns the
    /// question, so it must also own the answer. Dismissing first would run the sheet's
    /// own nil-write back through the binding and cancel the import we are confirming.
    private func confirm() {
        guard !(isFriend && trimmed.isEmpty) else { return }
        let rider = isFriend ? trimmed : nil
        Task { await store.confirmPendingImport(rider: rider) }
    }
}
