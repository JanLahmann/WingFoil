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
            if let initialTopic, selected == nil { selected = initialTopic }
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
    @State private var next: HelpTopicID?

    private var topic: HelpTopic { HelpCatalog.topic(id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(topic.summary)
                        .font(.headline)
                        .foregroundStyle(.secondary)

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
