import Foundation
import Testing
@testable import WingFoilKit

/// **The app's screen sentences, exported for the browser app** (`docs/copy/app-words.json`).
///
/// The same contract `SettingsCopyExportTests` keeps for the Settings sections, for every
/// other sentence the browser shows and the phone authors: `AppShellCopy`'s groups, the
/// turn coach's table, and the kit constants the browser used to retype (`Copy`,
/// `SpeedRecordPolicy`, `ExampleOnlyNote`, `SessionAnalysisMail`, `IcuProblem`,
/// `DisciplineLexicon`). Write the file after a deliberate wording change:
///
/// ```sh
/// COPY_WRITE=1 swift test --filter AppShellCopyExportTests
/// python3 web/tools/make_app_copy.py
/// ```
///
/// `verify_links.py` runs `make_app_copy.py --check`, and `check_web_literals.py` fails a
/// `say("group.key")` in web/js that this file does not carry.
@Suite struct AppShellCopyExportTests {

    static let file = "app-words.json"

    /// A `%.0f` format as the browser's template: the placeholders in order.
    static func template(_ format: String, _ names: [String]) -> String {
        var out = format
        for name in names {
            guard let range = out.range(of: "%.0f") else { break }
            out.replaceSubrange(range, with: "{" + name + "}")
        }
        return out
    }

    static func document() -> [String: [String: String]] {
        var groups = AppShellCopy.groups
        groups["turnCoach"] = TurnCoach.lines
        groups["turnCoachTips"] = TurnCoach.tipLines
        groups["copy"] = [
            "noWindForOrientation": Copy.noWindForOrientation,
            "pathNumbers": Copy.pathNumbers,
            "northAndWind": Copy.northAndWind,
            "outcomeWindow": Copy.outcomeWindowTemplate,
            "axisSweep": template(Copy.axisSweepFormat, ["before", "after"]),
            "deleteAnyLine": Copy.deleteAnyLine,
        ]
        var speed: [String: String] = [:]
        for policy in SpeedRecordPolicy.allCases {
            speed[policy.rawValue] = policy.label
            speed[policy.rawValue + "Summary"] = policy.summary
        }
        groups["speedRecords"] = speed
        groups["exampleOnly"] = [
            "recordsTitle": ExampleOnlyNote.recordsTitle,
            "records": ExampleOnlyNote.records,
            "trendsTitle": ExampleOnlyNote.trendsTitle,
            "trends": ExampleOnlyNote.trends,
            "importButton": ExampleOnlyNote.importButton,
            "connectButton": ExampleOnlyNote.connectButton,
        ]
        groups["sessionMail"] = [
            "prompt": SessionAnalysisMail.prompt,
            "commentLabel": SessionAnalysisMail.commentLabel,
            "consentHolds": SessionAnalysisMail.consentHolds,
            "consentStripped": SessionAnalysisMail.consentStripped,
            "consentUse": SessionAnalysisMail.consentUse,
            "originalAttached": SessionAnalysisMail.originalAttached,
            "subject": SessionAnalysisMail.subject(date: "{date}"),
        ]
        var icu: [String: String] = [:]
        for kind in IcuProblem.Kind.allCases {
            let problem = IcuProblem(kind: kind)
            icu[kind.rawValue + "Title"] = problem.title
            icu[kind.rawValue + "Message"] = problem.message
            icu[kind.rawValue + "Fix"] = problem.fix
        }
        icu["serverMessageDetail"] = IcuProblem(kind: .server, detail: "{detail}").message
        groups["icu"] = icu
        groups["discipline"] = ["experimentalNote": DisciplineLexicon.experimentalNote]
        groups["settings"] = [
            "detailTitle": SettingsCopy.detailTitle,
            "detailConcise": SettingsCopy.detailConcise,
            "detailExtensive": SettingsCopy.detailExtensive,
            "detailCaption": SettingsCopy.detailCaption,
        ]
        return groups
    }

    static func canonical(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: ["groups": value],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? ""
    }

    @Test func theAppWordsMatchTheirJSON() throws {
        let groups = Self.document()
        if CopyContractTests.isWriting {
            let url = CopyContractTests.copyDir.appendingPathComponent(Self.file)
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "_readme": "GENERATED from AppShellCopy and the kit constants it names by "
                        + "`COPY_WRITE=1 swift test --filter AppShellCopyExportTests`. The "
                        + "kit is the author; web/tools/make_app_copy.py writes WORDS in "
                        + "web/js/appcopy.js from this file. `{name}` is a value the screen "
                        + "fills in. Do not edit by hand.",
                    "schema": "cleanjibe.app-words/1",
                    "groups": groups,
                ] as [String: Any],
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try (String(data: data, encoding: .utf8)! + "\n")
                .write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let json = try CopyContractTests.load(Self.file)
        let want = try Self.canonical(groups)
        let got = try Self.canonical(json["groups"] ?? [:])
        #expect(got == want,
                """
                docs/copy/app-words.json is out of step with AppShellCopy. Regenerate it:
                  COPY_WRITE=1 swift test --filter AppShellCopyExportTests
                then regenerate the browser's copy module:
                  python3 web/tools/make_app_copy.py
                """)
    }

    /// A template's placeholders are names, never positions, and `fill` leaves none behind
    /// when it is handed every name the template carries.
    @Test func everyTemplateFillsCompletely() {
        let placeholder = try! NSRegularExpression(pattern: "\\{([A-Za-z]+)\\}")
        for (group, lines) in Self.document() {
            for (key, template) in lines {
                let range = NSRange(template.startIndex..., in: template)
                var args: [String: String] = [:]
                for match in placeholder.matches(in: template, range: range) {
                    if let name = Range(match.range(at: 1), in: template) {
                        args[String(template[name])] = "1"
                    }
                }
                let filled = AppShellCopy.fill(template, args)
                #expect(!filled.contains("{") && !filled.contains("}"),
                        "\(group).\(key) keeps a placeholder after fill: \(filled)")
                #expect(!template.isEmpty, "\(group).\(key) is empty")
            }
        }
    }

    /// The coach's templates say what `TurnCoach.line` says, rung for rung — the sentence
    /// the phone prints is the template filled, not a second wording beside it.
    @Test func theCoachReadsItsOwnTable() {
        #expect(TurnCoach.tipText(.rideItOut, type: "jibe", quietS: 10)
                == "Next time, stay on the foil for 10 s after the turn, and it counts as clean.")
        #expect(TurnCoach.tipText(.rideItOut, type: "jibe", quietS: nil)
                == "Next time, stay on the foil for a few seconds after the turn, and it counts "
                    + "as clean.")
        #expect(Copy.outcomeWindow(seconds: 12) == "\"Outcome\" is the 12 s the verdict is read from.")
        #expect(SessionAnalysisMail.consent
                == "The file holds your track, your heart rate and your times. "
                    + "It is stripped of your watch's serial number and profile. "
                    + "It is used only to improve the detection. It is never published.")
    }
}
