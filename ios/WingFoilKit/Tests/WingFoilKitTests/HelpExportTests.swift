import Foundation
import Testing
@testable import WingFoilKit

/// **The help catalogue, exported for the website** (`docs/copy/help.json`).
///
/// Jan, 19 September 2026: *"/help is built from the app's help catalog"*. The website used
/// to carry its own explanations — `/learn/`'s eleven glossary lines and four questions —
/// written in a different pass from the app's, which is the mechanism `docs/copy` exists to
/// end. So the site stops writing them: `web/tools/make_help.py` reads this file and renders
/// `web/help/index.html`, and `HelpCatalog` stays the one author.
///
/// It is the same shape of contract as `CopyContractTests`, one level up: that suite pins
/// the short sentences two surfaces *say*, this one hands the whole reference work over.
/// So it writes the same way, with the same switch:
///
/// ```sh
/// COPY_WRITE=1 swift test --filter HelpExportTests
/// ```
///
/// **Channel-aware, because the catalogue is** (docs/channels.md). The export is the dev
/// view — everything — with each topic and each item carrying the channels that may read
/// it. The web then prints the release set plainly, puts a `beta` pill on what only the
/// beta has, and prints no dev row at all, exactly as `make_whats_new.py` does with the
/// release notes. A page that listed a dev door would promise a stranger a door nobody can
/// have.
@Suite struct HelpExportTests {

    static let file = "help.json"

    static var isWriting: Bool { CopyContractTests.isWriting }

    /// The channel's name in the JSON. `HelpChannel` is `Int`-raw, because the order is the
    /// nesting order and the comparison is the point; the file wants the word.
    static let name: [HelpChannel: String] = [.release: "release", .beta: "beta", .dev: "dev"]

    /// Every channel that may read something whose lowest channel is `lowest`.
    static func channels(from lowest: HelpChannel) -> [String] {
        HelpChannel.allCases.filter { $0.has(lowest) }.compactMap { name[$0] }
    }

    /// The sections, their topics, and each topic's items — the dev view, marked.
    ///
    /// An item's channel is **derived**, not declared: the one topic whose items branch is
    /// Getting started, whose routes are the two Apple doors of docs/channels.md, and
    /// `HelpCatalog.topic(_:channel:)` is what decides. Asking each channel what it sees
    /// and taking the lowest that sees an item keeps that decision in the one place that
    /// makes it, so a second branching topic needs no edit here.
    static func document() -> [String: Any] {
        let ladder: [HelpChannel] = [.release, .beta, .dev]
        var sections: [[String: Any]] = []
        for section in HelpCatalog.sections {
            var topics: [[String: Any]] = []
            // A topic on no index (What's new, since 26 September 2026) is not exported:
            // the site has its own /whats-new/ page, and a fold onto a button would be a
            // page about a page.
            for listed in HelpCatalog.topics(in: section)
            where !HelpCatalog.offIndex.contains(listed.id) {
                let topic = HelpCatalog.topic(listed.id, channel: .dev)
                let items: [[String: Any]] = topic.items.map { item in
                    let lowest = ladder.first { channel in
                        HelpCatalog.topic(listed.id, channel: channel).items.contains(item)
                    } ?? .dev
                    var row: [String: Any] = ["term": item.term, "detail": item.detail,
                                              "channels": channels(from: lowest)]
                    // The signpost's topic, which the web draws as a link on the term.
                    if let link = item.link { row["link"] = link.rawValue }
                    return row
                }
                var row: [String: Any] = [
                    "id": topic.id.rawValue,
                    "title": topic.title,
                    "summary": topic.summary,
                    "body": topic.body,
                    "items": items,
                    "related": topic.related.map(\.rawValue),
                    "channels": channels(from: listed.channel),
                    // The ids the merge retired that now open this topic, so an old
                    // `/help/#help-foilPct` or `#/help/sourceClass` still arrives.
                    "aliases": HelpCatalog.aliases(of: topic.id),
                ]
                // The sub-heading inside "Read the numbers".
                if let sub = topic.subsection {
                    row["group"] = ["id": sub.rawValue, "title": sub.title]
                }
                topics.append(row)
            }
            sections.append(["id": section.rawValue, "title": section.title,
                             "topics": topics])
        }
        return ["sections": sections]
    }

    /// Writes the file whole.
    ///
    /// Unlike `CopyContractTests.write`, which merges kit-owned keys into a file that also
    /// carries hand-authored ones, **every key of this file is generated** — there is no
    /// hand-authored half to carry forward, so there is nothing to read first. Deterministic
    /// on purpose, the way the rest of `docs/copy` is: sorted keys, two spaces, unescaped
    /// slashes, so a regeneration that changes nothing produces no diff.
    static func write(_ document: [String: Any]) throws {
        let url = CopyContractTests.copyDir.appendingPathComponent(file)
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (String(data: data, encoding: .utf8)! + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    /// One deterministic spelling of a JSON value, so two of them compare as strings and a
    /// failure prints something a person can read.
    static func canonical(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: ["sections": value],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test func theHelpCatalogueMatchesItsJSON() throws {
        let document = Self.document()
        if Self.isWriting {
            try Self.write([
                "_readme": "GENERATED from HelpCatalog by "
                    + "`COPY_WRITE=1 swift test --filter HelpExportTests`. The kit is the "
                    + "author; web/tools/make_help.py renders web/help/index.html from this "
                    + "file. Do not edit by hand.",
                "sections": document["sections"]!,
            ])
            return
        }

        let json = try CopyContractTests.load(Self.file)
        let want = try Self.canonical(document["sections"]!)
        let got = try Self.canonical(json["sections"] ?? [])
        #expect(got == want,
                """
                docs/copy/help.json is out of step with HelpCatalog. Regenerate it:
                  COPY_WRITE=1 swift test --filter HelpExportTests
                then re-render the page:
                  python3 web/tools/make_help.py
                """)
    }

    /// The shape the web renderer relies on, asserted here rather than discovered there.
    ///
    /// `make_help.py` is stdlib-only and has no schema of its own: a missing `related` or a
    /// topic on no channel at all would render a page with a dead link or an empty article,
    /// which is the kind of thing a static site ships and nobody notices.
    @Test func everyExportedTopicIsRenderable() throws {
        let sections = try #require(Self.document()["sections"] as? [[String: Any]])
        #expect(sections.count == HelpCatalog.sections.count)
        var ids: Set<String> = []
        for section in sections {
            let topics = try #require(section["topics"] as? [[String: Any]])
            #expect(!topics.isEmpty, "section \(section["id"] ?? "?") has no topics")
            for topic in topics {
                let id = try #require(topic["id"] as? String)
                ids.insert(id)
                #expect(!(topic["title"] as? String ?? "").isEmpty, "\(id) has no title")
                #expect(!(topic["summary"] as? String ?? "").isEmpty, "\(id) has no summary")
                let channels = try #require(topic["channels"] as? [String])
                #expect(!channels.isEmpty, "\(id) is on no channel")
                #expect(channels.last == "dev",
                        "\(id): every channel list ends at dev, the widest reader")
            }
        }
        #expect(ids.count == HelpTopicID.allCases.count - HelpCatalog.offIndex.count,
                "the export drops a topic the catalogue lists")
        // Every "see also" resolves to a topic that was exported, so the page's own links
        // cannot point at an article it never drew.
        for section in sections {
            for topic in (section["topics"] as? [[String: Any]] ?? []) {
                for related in (topic["related"] as? [String] ?? []) {
                    #expect(ids.contains(related),
                            "\(topic["id"] ?? "?") is related to \(related), which is not exported")
                }
            }
        }
    }

    /// **The four questions cleanjibe.org/learn used to answer are all in here.**
    ///
    /// /learn/ is a redirect to /help/#numbers since 19 September 2026, so if one of its
    /// four answers has no topic the fact has no home at all (rule 10 of docs/voice.md).
    /// Three were already written. The fourth asked whether there is an app for the other
    /// phone, and became `.browserApp` — which answers it by naming the browser and not the
    /// platform, because an iOS app's own text may not name another platform (App Store
    /// guideline 2.3.10). The platform's own name keeps its home on /start/#watches, where
    /// it is the website speaking.
    @Test func theFourQuestionsFromTheOldLearnPageHaveTopics() {
        for id in [HelpTopicID.browserApp, .stravaImport, .turnSuccess, .privacy] {
            #expect(HelpCatalog.topic(id).id == id)
        }
    }
}
