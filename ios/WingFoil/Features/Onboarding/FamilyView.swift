import SwiftUI
import WingFoilKit

/// **The CleanJibe family** — the three apps, and how a session travels between them.
///
/// A small view rather than a help topic, because that is what the row above it in the
/// menu is: *What CleanJibe does* raises the welcome screen, and this answers the second
/// half of the same question. Every word is the kit's (`CleanJibeFamily`), so the browser
/// app's page says exactly this.
///
/// The phone marks its own row, because the one thing this screen knows that the copy
/// cannot is which of the three the rider is holding.
struct FamilyView: View {
    @Environment(\.dismiss) private var dismiss

    /// The app this build is. The browser app answers `browser` to the same question.
    private let thisApp = "iphone"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(CleanJibeFamily.intro)
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(CleanJibeFamily.apps) { app in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(app.title).font(.subheadline.weight(.semibold))
                                    if app.id == thisApp {
                                        Text(CleanJibeFamily.here)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(app.line)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemBackground),
                                        in: .rect(cornerRadius: 12))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(CleanJibeFamily.travel, id: \.self) { line in
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 28)
                .readableColumn()
            }
            .navigationTitle(CleanJibeFamily.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
