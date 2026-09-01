import SwiftUI
import WingFoilKit

/// The Help index as a sheet, with its own navigation stack and a Done button.
///
/// The content itself lives in `WingFoilKit.HelpCatalog` (pure data, covered by the test
/// suite) — everything in this file is presentation.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    /// Set when Help is opened from a card's `?`, so the matching topic opens straight away.
    var initialTopic: HelpTopicID?

    var body: some View {
        NavigationStack {
            HelpIndexList(initialTopic: initialTopic)
                .navigationTitle("What the numbers mean")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// The same index, pushed onto an existing stack (Settings).
struct HelpIndexPage: View {
    var body: some View {
        HelpIndexList()
            .navigationTitle("What the numbers mean")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The searchable list of topics, without any navigation chrome of its own.
private struct HelpIndexList: View {
    var initialTopic: HelpTopicID?

    @State private var query = ""
    @State private var selected: HelpTopicID?

    private var sections: [(section: HelpSection, topics: [HelpTopic])] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return HelpCatalog.sections.map { ($0, HelpCatalog.topics(in: $0)) }
        }
        let hits = HelpCatalog.search(query)
        return HelpCatalog.sections.compactMap { section in
            let topics = hits.filter { $0.section == section }
            return topics.isEmpty ? nil : (section, topics)
        }
    }

    var body: some View {
        List {
            if sections.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
            ForEach(sections, id: \.section.id) { group in
                Section {
                    ForEach(group.topics) { topic in
                        Button { selected = topic.id } label: { row(topic) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Label(group.section.title, systemImage: group.section.symbol)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Search the metrics")
        .sheet(item: $selected) { HelpTopicSheet(id: $0) }
        .task {
            // Deep link from a `?` or from the setup card: the topic sheet has to wait for
            // the index's own presentation to finish, or UIKit drops the second one.
            guard let initialTopic, selected == nil else { return }
            try? await Task.sleep(for: .milliseconds(450))
            if selected == nil { selected = initialTopic }
        }
    }

    private func row(_ topic: HelpTopic) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(topic.title).font(.subheadline.weight(.semibold))
            Text(topic.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .padding(.vertical, 2)
    }
}

/// One topic, as a sheet. Also the destination of every card's `?`.
struct HelpTopicSheet: View {
    let id: HelpTopicID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openIcuSettings) private var openSettings
    @Environment(\.loadExampleSession) private var loadExample
    @State private var next: HelpTopicID?

    private var topic: HelpTopic { HelpCatalog.topic(id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(topic.summary)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    // Between the summary and the prose, because the topics that carry one
                    // describe a *screen*: the reader recognises the picture and then reads
                    // the paragraphs knowing what they are about. One `Image`, fit to the
                    // width, rounded — deliberately not a lightbox, a zoom or a carousel.
                    // The name is a `HelpImage.asset` from the catalogue and resolves in
                    // the app's own asset catalogue; `PresentationTests` asserts every one
                    // of them is actually checked in, because a typo here would silently
                    // draw nothing.
                    if let image = topic.image {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(image.asset)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(.rect(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                                }
                                .accessibilityLabel(image.caption)
                            Text(image.caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ForEach(Array(topic.body.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !topic.items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(topic.items.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.term).font(.subheadline.weight(.semibold))
                                    Text(item.detail)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                    }

                    if !topic.links.isEmpty || topic.action != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(topic.links, id: \.url) { link in
                                Link(destination: link.url) {
                                    Label(link.title, systemImage: "arrow.up.right.square")
                                        .font(.callout.weight(.semibold))
                                }
                            }
                            // Only the screen that owns the Settings sheet can open it, so
                            // the button appears exactly where that action was handed down.
                            if topic.action == .openIcuSettings, let open = openSettings {
                                Button {
                                    open()
                                } label: {
                                    Label("Open CleanJibe Settings", systemImage: "gearshape")
                                        .font(.callout.weight(.semibold))
                                }
                            }
                            // Same rule as above: the button appears only where somebody
                            // can honour it, and reading about the example is the moment
                            // you want to actually see it.
                            if topic.action == .loadExampleSession, let load = loadExample {
                                Button {
                                    load()
                                    dismiss()
                                } label: {
                                    Label("Load the example session", systemImage: "sparkles")
                                        .font(.callout.weight(.semibold))
                                }
                            }
                        }
                        .padding(.top, 2)
                    }

                    if !topic.related.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("See also")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(topic.related) { link in
                                Button { next = link } label: {
                                    HStack(spacing: 6) {
                                        Text(HelpCatalog.topic(link).title)
                                        Image(systemName: "chevron.right").font(.caption2)
                                        Spacer(minLength: 0)
                                    }
                                    .font(.callout)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // A "see also" opens on top rather than replacing: the reader can always get
            // back to the metric they started from.
            .sheet(item: $next) { HelpTopicSheet(id: $0) }
        }
    }
}

/// "Take me to the setting this describes", handed down by whichever screen owns the
/// Settings sheet. Nil where nobody can honour it, so the button simply does not appear
/// rather than appearing and doing nothing.
private struct OpenIcuSettingsKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

/// "Show me that example", handed down by the screen that owns the session store. Nil in
/// any context that cannot import, so the topic reads as prose rather than offering a
/// button that does nothing.
private struct LoadExampleSessionKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    var openIcuSettings: (@MainActor () -> Void)? {
        get { self[OpenIcuSettingsKey.self] }
        set { self[OpenIcuSettingsKey.self] = newValue }
    }

    var loadExampleSession: (@MainActor () -> Void)? {
        get { self[LoadExampleSessionKey.self] }
        set { self[LoadExampleSessionKey.self] = newValue }
    }
}

/// The small `?` that sits on a card and opens the matching topic.
///
/// It takes a `HelpTopicID`, not a string, so a card cannot link to a topic that does not
/// exist — the catalogue's completeness is then a compile-time property plus one test.
struct HelpButton: View {
    let topic: HelpTopicID
    var size: Font = .caption

    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "questionmark.circle")
                .font(size)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What does \(HelpCatalog.topic(topic).title) mean?")
        .sheet(isPresented: $showing) { HelpTopicSheet(id: topic) }
    }
}

/// A section heading with its own `?` — used by the detail screen's card groups.
struct HelpSectionHeader: View {
    let title: String
    let topic: HelpTopicID

    init(_ title: String, topic: HelpTopicID) {
        self.title = title
        self.topic = topic
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.headline)
            HelpButton(topic: topic, size: .footnote)
            Spacer()
        }
    }
}
