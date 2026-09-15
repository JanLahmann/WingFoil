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
                .navigationTitle("Help")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            // Forty-odd topics in ten sections, searchable — a screen, not a question. Same
            // trade as Settings: `.page` at regular width, the phone unchanged.
            .presentationSizing(.page)
        }
    }
}

/// The same index, pushed onto an existing stack (Settings).
struct HelpIndexPage: View {
    var body: some View {
        HelpIndexList()
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The searchable list of topics, without any navigation chrome of its own.
private struct HelpIndexList: View {
    var initialTopic: HelpTopicID?

    @Environment(SessionStore.self) private var store

    @State private var query = ""
    @State private var selected: HelpTopicID?

    /// What this index may list: the catalogue, minus the topics this **channel** does not
    /// have a door for and minus the ones a feature switch is hiding
    /// (`HelpCatalog.indexTopics`). The list a rider browses is a menu, and a topic on it is
    /// an offer — "Recording with the Apple Workout app" is not one in the App Store build,
    /// which has no Health door, and "Windsurf (experimental)" is not one until the rider has
    /// turned it on in Settings.
    ///
    /// The page itself stays reachable: a `?` on a session that *is* read as windsurf still
    /// opens it, which is why the filter is here and not in the catalogue.
    private var visible: [HelpTopic] {
        HelpCatalog.indexTopics(channel: AppChannel.channel,
                                windsurfEnabled: store.windsurfEnabled)
    }

    private var sections: [(section: HelpSection, topics: [HelpTopic])] {
        let listed = Set(visible.map(\.id))
        // Search reads the whole catalogue, so it is filtered by the same set — typing
        // "windsurf" must not advertise the feature the list is hiding, and typing "Health"
        // in the App Store build must not advertise a door that build does not have.
        let matched = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? visible
            : HelpCatalog.search(query, channel: AppChannel.channel)
                .filter { listed.contains($0.id) }
        return HelpCatalog.sections.compactMap { section in
            let topics = matched.filter { $0.section == section }
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
            Text(markdown: topic.summary)
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
    @Environment(\.sendFeedback) private var sendFeedback
    /// Optional on purpose: a `?` is drawn on cards all over the app, and this sheet must
    /// not be the one view that insists on a store being in the environment. Without one the
    /// "see also" list is filtered by the channel alone, which is the filter that matters.
    @Environment(SessionStore.self) private var store: SessionStore?
    @State private var next: HelpTopicID?

    /// **The page this build reads.** The catalogue is the same data in every channel, but
    /// one topic's *items* are the ways in (Getting started) and two of those are beta
    /// doors — so the channel is handed in here rather than left to the kit's default,
    /// which is the release's list (docs/channels.md). Every entry point to a topic goes
    /// through this sheet: the menu's Getting started, the index, a card's `?`, a "see
    /// also" chevron and the Settings deep links, so there is one channel-aware path and
    /// not five.
    private var topic: HelpTopic { HelpCatalog.topic(id, channel: AppChannel.channel) }

    /// The topics this build may actually offer as a next step. A "see also" is a button,
    /// and a button onto a topic the index hides would be a dead end wearing a chevron —
    /// so it is filtered by the same rule the index uses (`HelpCatalog.relatedTopics`).
    private var related: [HelpTopic] {
        HelpCatalog.relatedTopics(of: topic, channel: AppChannel.channel,
                                  windsurfEnabled: store?.windsurfEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Every string that comes out of the catalogue is drawn through
                    // `Text(markdown:)`: the topics are written with `**bold**` and
                    // `*italic*` in them, and a `Text(String)` would print the asterisks.
                    // `HelpCatalogTests.everyParagraphParsesAsMarkdown` holds the other end
                    // of this bargain.
                    Text(markdown: topic.summary)
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
                        Text(markdown: paragraph)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !topic.items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(topic.items.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(markdown: item.term)
                                        .font(.subheadline.weight(.semibold))
                                    Text(markdown: item.detail)
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
                            // Same rule again, and the reason the page has a button at all
                            // (Jan, dev 65): a topic that explains how to send feedback and
                            // then asks the reader to go and find one of the three doors is
                            // a page he has to leave to use. `FeedbackDoors.menuRow` names
                            // the door this opens, so the button and the paragraph above it
                            // cannot drift apart.
                            if topic.action == .sendFeedback, let send = sendFeedback {
                                Button {
                                    send()
                                    dismiss()
                                } label: {
                                    Label("Send feedback…", systemImage: "envelope")
                                        .font(.callout.weight(.semibold))
                                }
                                .accessibilityHint("Opens the same mail as Menu → "
                                                   + "\(FeedbackDoors.menuRow)")
                            }
                        }
                        .padding(.top, 2)
                    }

                    if !related.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("See also")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(related) { link in
                                Button { next = link.id } label: {
                                    HStack(spacing: 6) {
                                        Text(link.title)
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
                // A help topic is prose with a picture in it, and the sheet it lives in is
                // page-sized on an iPad: without this the paragraphs would run the width of
                // the sheet, which is the one thing prose may not do.
                .readableColumn()
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
            .presentationSizing(.page)
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

/// "Write to me about this", handed down by the screen that owns the feedback composer —
/// the Sessions list, whose `feedbackMail(on:)` is the same ladder Menu → Support & ideas
/// climbs. Nil anywhere else, so the *Sending feedback* topic reads as prose rather than
/// offering a button that does nothing.
private struct SendFeedbackKey: EnvironmentKey {
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

    var sendFeedback: (@MainActor () -> Void)? {
        get { self[SendFeedbackKey.self] }
        set { self[SendFeedbackKey.self] = newValue }
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
        .accessibilityLabel("What does " + HelpCatalog.topic(topic).title + " mean?")
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
