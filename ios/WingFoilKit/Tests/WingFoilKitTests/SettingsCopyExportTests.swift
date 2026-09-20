import Foundation
import Testing
@testable import WingFoilKit

/// **The Settings screen's words, exported for the browser app** (`docs/copy/settings.json`).
///
/// The same contract `HelpExportTests` keeps one file over, for a smaller list: the phone
/// authors every Settings section's header, its one-line lead and its footer, and the
/// browser renders them rather than writing its own. Write the file after a deliberate
/// wording change:
///
/// ```sh
/// COPY_WRITE=1 swift test --filter SettingsCopyExportTests
/// ```
///
/// then regenerate `web/js/appcopy.js`:
///
/// ```sh
/// python3 web/tools/make_app_copy.py
/// ```
///
/// `verify_links.py` runs `make_app_copy.py --check`, so a stale browser fails a web check
/// and a stale JSON fails `swift test`.
@Suite struct SettingsCopyExportTests {

    static let file = "settings.json"

    static var isWriting: Bool { CopyContractTests.isWriting }

    static let name: [HelpChannel: String] = [.release: "release", .beta: "beta", .dev: "dev"]

    static func document() -> [String: Any] {
        var sections: [[String: Any]] = []
        for section in SettingsCopy.sections {
            var row: [String: Any] = [
                "id": section.id,
                "title": section.title,
                "lead": section.lead,
                "footer": section.footer,
                "channel": Self.name[section.channel] ?? "release",
                "web": section.web,
                "phone": section.phone,
            ]
            if let help = section.help { row["help"] = help.rawValue }
            sections.append(row)
        }
        return ["sections": sections]
    }

    static func write(_ document: [String: Any]) throws {
        let url = CopyContractTests.copyDir.appendingPathComponent(file)
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (String(data: data, encoding: .utf8)! + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    static func canonical(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: ["sections": value],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test func theSettingsCopyMatchesItsJSON() throws {
        let document = Self.document()
        if Self.isWriting {
            try Self.write([
                "_readme": "GENERATED from SettingsCopy by "
                    + "`COPY_WRITE=1 swift test --filter SettingsCopyExportTests`. The kit "
                    + "is the author; web/tools/make_app_copy.py renders the browser app's "
                    + "Settings page from this file. Do not edit by hand.",
                "schema": "cleanjibe.settings/1",
                "sections": document["sections"]!,
            ])
            return
        }

        let json = try CopyContractTests.load(Self.file)
        let want = try Self.canonical(document["sections"]!)
        let got = try Self.canonical(json["sections"] ?? [])
        #expect(got == want,
                """
                docs/copy/settings.json is out of step with SettingsCopy. Regenerate it:
                  COPY_WRITE=1 swift test --filter SettingsCopyExportTests
                then regenerate the browser's copy module:
                  python3 web/tools/make_app_copy.py
                """)
    }

    /// **A lead is one line** (pattern K, and the budget of docs/voice.md). Twenty words is
    /// the help summary's budget, and a Settings lead does the same job one screen down.
    @Test func everyLeadIsOneLine() {
        for section in SettingsCopy.sections {
            let count = section.lead.split(whereSeparator: \.isWhitespace).count
            #expect(count <= 20, "\(section.id): the lead is \(count) words")
            #expect(!section.lead.contains("\n"), "\(section.id): the lead has a line break")
            #expect(!section.lead.isEmpty, "\(section.id) has no lead")
        }
    }

    /// Every `?` resolves, every id is unique, and every section is on some shell.
    @Test func everySectionIsRenderable() {
        var seen: Set<String> = []
        for section in SettingsCopy.sections {
            #expect(seen.insert(section.id).inserted, "\(section.id) is declared twice")
            #expect(!section.title.isEmpty, "\(section.id) has no title")
            #expect(section.web || section.phone, "\(section.id) is on no shell at all")
            if let help = section.help {
                #expect(HelpCatalog.topic(help).id == help,
                        "\(section.id) points at a topic that is not in the catalogue")
            }
        }
    }

    /// The two sections the browser draws and the phone does not, and the reason each is
    /// here rather than in `web/app/index.html`: docs/screens.md calls them deviations, and
    /// a deviation is a decision that is written down.
    @Test func theWebOnlySectionsAreTheOnesTheScreensFileNames() {
        let webOnly = SettingsCopy.sections.filter { $0.web && !$0.phone }.map(\.id)
        #expect(webOnly == ["units", "data", "whatsNew"])
    }
}
