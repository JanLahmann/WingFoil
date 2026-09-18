import SwiftUI
import WingFoilKit

/// **Renaming a session, from the session** (GitHub issue 13).
///
/// The only way to rename an afternoon used to be the share composer's title field, which is
/// a sheet about sending a picture to somebody. A rider whose watch filed Tuesday under the
/// wrong spot was fixing a name the library list shows him, not preparing an export, and had
/// to go through a screen about exporting to do it.
///
/// It writes the same column that field writes — `SessionRow.customTitle`, through
/// `SessionStore.renameSession` — so the two doors are one name on eleven surfaces and not
/// two competing ones. Clearing the field gives the derived name back, which is the only
/// honest meaning of an empty title field.
struct RenameSessionSheet: View {
    let row: SessionRow
    @Binding var draft: String

    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(SessionDisplay.derivedTitle(row), text: $draft)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    Text("Leave it empty to go back to the name CleanJibe read off the "
                         + "recording.")
                }
            }
            .navigationTitle("Rename session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .task { focused = true }
        }
        .presentationDetents([.height(220)])
        .presentationSizing(.form)
    }

    private func save() {
        let typed = draft
        dismiss()
        Task { await store.renameSession(row, to: typed) }
    }
}
