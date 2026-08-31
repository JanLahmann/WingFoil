import SwiftUI
import WingFoilKit

/// "You pulled twice and nothing came — did you mean to get any of these back?"
///
/// **Why a picker and not an alert.** The obvious version of this feature is a yes/no:
/// "Re-add 6 previously deleted sessions?". But those six are six different afternoons, and
/// the rider who pulled twice was almost certainly after *one* of them — the one this
/// morning's swipe took by mistake. Yes brings back five he threw away on purpose; no leaves
/// him exactly where he started, with the question answered and nothing solved.
///
/// **Why it is up at all**, given that deleting is an instruction the app obeys silently
/// everywhere else: because a second pull-to-refresh ten seconds after the first one finished
/// is not a routine sync. It is a rider saying "that did not work". This is the app's answer.
///
/// The rows speak the library's own vocabulary — the title over date and duration, the same
/// `Fmt` helpers `SessionRowView` uses — because these *were* rows in that list, and a rider
/// recognising the one he wants is the only thing this screen has to make possible.
struct ReAddDeletedSheet: View {
    let offer: SessionStore.ReAddOffer

    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Nothing pre-ticked. The safe default is the one the rider already gave by deleting,
    /// and a sheet that opened with all six selected would turn a mis-tap on the confirm
    /// button into exactly the outcome the picker exists to prevent.
    @State private var selected: Set<String> = []

    private var candidates: SessionTombstones.ReAddCandidates { offer.candidates }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates.stones) { stone in
                        row(stone)
                    }
                } header: {
                    Text(SessionTombstones.reAddQuestion(count: offer.count))
                } footer: {
                    Text("You deleted these, so CleanJibe has been leaving them on "
                         + "intervals.icu rather than downloading them again. Anything you "
                         + "do not pick stays deleted.")
                }

                if candidates.offersSelectAll { shortcuts }
            }
            .navigationTitle("Deleted sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Dismissing is "keep deleted", and it is the same call the sheet's own
                    // swipe-down makes — there is one answer to a question the rider walked
                    // away from, and it is the one he already gave.
                    Button("Keep deleted") { store.declineReAdd() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore \(selected.count)") {
                        let ids = Array(selected)
                        Task { await store.acceptReAdd(ids: ids) }
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// One deleted session: what it was called, when it was, how long it ran. Everything else
    /// a library row carries — foil share, flights, best 2 s — is gone with the analysis, and
    /// inventing a placeholder for it would make the row look like a session that is still
    /// here.
    private func row(_ stone: SessionTombstoneRow) -> some View {
        Button {
            if selected.contains(stone.id) {
                selected.remove(stone.id)
            } else {
                selected.insert(stone.id)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: selected.contains(stone.id)
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(stone.id)
                                     ? AnyShapeStyle(Color.accentColor)
                                     : AnyShapeStyle(.tertiary))
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stone.title ?? "Session")
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(Fmt.date(stone.startDate)) · \(Fmt.duration(stone.durationS))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected.contains(stone.id) ? [.isSelected] : [])
    }

    /// The two ways to tick several at once.
    ///
    /// "Only <day>" appears when the list is long enough to be worth narrowing *and* spans
    /// more than one day — a run of six that all happened on the same Tuesday is already what
    /// the shortcut would select, and "Select all" says that more plainly.
    @ViewBuilder
    private var shortcuts: some View {
        Section {
            Button(selected.count == candidates.count ? "Select none" : "Select all") {
                selected = selected.count == candidates.count
                    ? [] : Set(candidates.stones.map(\.id))
            }
            if let day = candidates.recentDay {
                Button("Only \(Fmt.shortDate(day))") {
                    selected = Set(candidates.recentDayIds)
                }
            }
        }
    }
}
