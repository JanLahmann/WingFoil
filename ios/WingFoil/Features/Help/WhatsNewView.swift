import SwiftUI
import WingFoilKit

/// **What's new** — the release notes, in the app.
///
/// They had three homes and no source until 18 September 2026: two hand-typed strings in
/// `ios/tools/testflight_publish.py`, a stack of hand-written cards on
/// cleanjibe.org/whats-new, and nothing at all here. A rider whose app changed under him on
/// a Tuesday had to go and find a website to learn what it now did.
///
/// Everything below comes out of `WingFoilKit.WhatsNew`, which
/// `web/tools/make_whats_new.py` writes from `docs/copy/whats-new.json` — the same file the
/// website's cards and the TestFlight "What to Test" text are written from. Nothing in this
/// file is a sentence: it is presentation, like the rest of `Features/Help`.
///
/// **This is the app's one dated surface.** A release note that does not say when it
/// shipped is not a release note; the dates are written by the generator rather than typed,
/// which is the condition `docs/copy/check_voice.py` puts on a dated target.
private struct WhatsNewList: View {

    /// **What this build may read** (docs/channels.md): the release build reads the release
    /// notes, a beta build reads beta and release, the dev build reads everything. A note
    /// about a build the reader could never have is the app describing a door he cannot
    /// open — the same rule the Help index follows for topics.
    private var entries: [WhatsNewEntry] { WhatsNew.entries(for: AppChannel.channel) }

    var body: some View {
        List {
            ForEach(entries) { entry in
                Section {
                    // One line, one thought — the shape the source enforces. Markdown,
                    // because the notes are written with `**bold**` and `*italic*` in
                    // them exactly as the help topics are.
                    ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                        Text(markdown: line)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    header(entry)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if entries.isEmpty { ContentUnavailableView("Nothing yet", systemImage: "sparkles") }
        }
        .readableColumn()
    }

    /// The product and its number, then the day and the version, then what the build was
    /// about. The version is not repeated under a watch release: its heading is the version.
    private func header(_ entry: WhatsNewEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.heading)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(markdown: entry.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .textCase(nil)
                .padding(.top, 2)
        }
        .textCase(nil)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(_ entry: WhatsNewEntry) -> String {
        guard entry.build != nil else { return entry.dateText }
        return entry.dateText + " · " + entry.version
    }
}

/// The notes pushed onto an existing stack — Settings → About → What's new.
struct WhatsNewPage: View {
    var body: some View {
        WhatsNewList()
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The same notes as a sheet, which is how the Help topic opens them: a help topic is
/// itself a sheet, and a page pushed inside one loses its way back.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WhatsNewList()
                .navigationTitle("What's new")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationSizing(.page)
    }
}
