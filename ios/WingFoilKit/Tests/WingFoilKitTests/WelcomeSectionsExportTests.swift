import Foundation
import Testing
@testable import WingFoilKit

/// **The two front doors' one basis, exported for the homepage** (`docs/copy/welcome.json`).
///
/// The kit authors every section of *What CleanJibe does* and of the cleanjibe.org
/// homepage (`WelcomeSections`); the homepage is rendered from this export by
/// `web/tools/make_home.py`. Write the file after a deliberate wording change:
///
/// ```sh
/// COPY_WRITE=1 swift test --filter WelcomeSectionsExportTests
/// python3 web/tools/make_home.py
/// ```
///
/// `verify_links.py` runs `make_home.py --check`, so a stale homepage fails a web check and a
/// stale JSON fails `swift test`.
@Suite struct WelcomeSectionsExportTests {

    static let file = "welcome.json"

    static func row(_ action: WelcomeAction) -> [String: Any] {
        ["id": action.id, "title": action.title]
    }

    static func document() -> [[String: Any]] {
        WelcomeSections.all.map { section in
            [
                "id": section.id.rawValue,
                "surfaces": section.surfaces.rawValue,
                "kicker": section.kicker,
                "title": section.title,
                "lede": section.lede,
                "note": section.note,
                "actions": section.actions.map(Self.row),
                "items": section.items.map { item in
                    [
                        "id": item.id,
                        "term": item.term,
                        "detail": item.detail,
                        "beta": item.beta,
                        "apps": item.apps,
                        "actions": item.actions.map(Self.row),
                    ] as [String: Any]
                },
            ]
        }
    }

    static func canonical(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: ["sections": value],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test func theSectionsMatchTheirJSON() throws {
        let sections = Self.document()
        if CopyContractTests.isWriting {
            let url = CopyContractTests.copyDir.appendingPathComponent(Self.file)
            let document: [String: Any] = [
                "_readme": "GENERATED from WelcomeSections by "
                    + "`COPY_WRITE=1 swift test --filter WelcomeSectionsExportTests`. The kit is "
                    + "the author of both front doors: the app's What CleanJibe does reads the "
                    + "kit, and web/tools/make_home.py renders web/index.html and "
                    + "docs/web-parity/welcome-vs-homepage.md from this file. Do not edit by "
                    + "hand.",
                "schema": "cleanjibe.welcome/1",
                "sections": sections,
            ]
            let data = try JSONSerialization.data(
                withJSONObject: document,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try (String(data: data, encoding: .utf8)! + "\n")
                .write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let json = try CopyContractTests.load(Self.file)
        #expect(try Self.canonical(json["sections"] ?? []) == Self.canonical(sections),
                """
                docs/copy/welcome.json is out of step with WelcomeSections. Regenerate it:
                  COPY_WRITE=1 swift test --filter WelcomeSectionsExportTests
                then regenerate the homepage:
                  python3 web/tools/make_home.py
                """)
    }

    /// The welcome screen draws these, in this order. A new section on the app is a
    /// decision, and this is where it is written down.
    @Test func theAppDrawsItsSectionsInItsOrder() {
        #expect(WelcomeSections.app.map(\.id) == [
            .identity, .legend, .example, .measures, .getStarted, .family, .community,
            .footerLinks,
        ])
    }

    /// The homepage's own sections, and the shared ones it draws beside them.
    @Test func theHomepageDrawsItsSectionsInItsOrder() {
        #expect(WelcomeSections.web.map(\.id) == [
            .hero, .legend, .example, .measures, .verdicts, .family, .chooser, .oldSessions,
            .watchApp, .trust, .community,
        ])
    }

    /// The promise is split, not rewritten: the hero's two halves are the pinned sentence.
    @Test func theHeroIsThePromise() {
        let hero = WelcomeSections.section(.hero)
        #expect(hero.title + " " + hero.lede == WelcomeGuide.promise)
        #expect(hero.kicker == Branding.tagline)
    }

    /// Every id is unique, every card names apps the family has, every section says
    /// something.
    @Test func everySectionIsRenderable() {
        var seen: Set<String> = []
        let family = Set(CleanJibeFamily.apps.map(\.id))
        for section in WelcomeSections.all {
            #expect(seen.insert(section.id.rawValue).inserted)
            #expect(!section.words.isEmpty, "\(section.id) says nothing")
            for item in section.items {
                for app in item.apps {
                    #expect(family.contains(app), "\(section.id).\(item.id) names \(app)")
                }
            }
        }
        #expect(Set(WelcomeSections.all.map(\.id)) == Set(WelcomeSection.ID.allCases))
    }

    /// The voice's budget (docs/voice.md): no sentence over 20 words, no dash, no bracket.
    @Test func everySentenceIsInsideTheVoice() {
        for section in WelcomeSections.all {
            for text in section.words {
                #expect(!text.contains("—") && !text.contains("–") && !text.contains("("),
                        "\(section.id): \(text)")
                for sentence in text.split(whereSeparator: { ".?!".contains($0) }) {
                    let count = sentence.split(whereSeparator: \.isWhitespace).count
                    #expect(count <= 20, "\(section.id): \(count) words in \(sentence)")
                }
            }
        }
    }
}
