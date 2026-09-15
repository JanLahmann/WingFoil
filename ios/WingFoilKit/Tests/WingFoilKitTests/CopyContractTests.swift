import Foundation
import Testing
@testable import WingFoilKit

/// **The copy contract: one wording, many surfaces** (`docs/copy/`).
///
/// The website, the App Store description and the app said the same things in different
/// words on 15 September 2026 — the beta list had a feature that had shipped, the phone's
/// clean-jibe definition was a version behind its own engine, and the dry streak counted
/// jibes "carried in a row" on one surface and jibes you "stayed out of the water" on the
/// other. Nothing was wrong with either sentence. What was missing was a mechanism.
///
/// `docs/copy/*.json` is that mechanism, and it is **pinned from both sides**:
///
/// * **This suite** asserts every kit constant equals its JSON. A kit edit that moves a fact
///   fails here until `docs/copy` moves with it.
/// * **`web/tools/verify_copy.py`** asserts the web pages carry the same strings, so the
///   website has to catch up before the check goes green again.
///
/// The JSON is the *artefact*, not the author: the kit is the author for everything the app
/// says, `docs/channels.md` for the channel lists, and the JSON is where both are written
/// down in a form a Python verifier can read. To regenerate it after a deliberate wording
/// change:
///
/// ```sh
/// COPY_WRITE=1 swift test --filter CopyContractTests
/// ```
///
/// which rewrites the kit-owned keys of every file in place and leaves the hand-authored
/// ones (the forbidden lists, the lexicon, the store names) exactly as they were.
@Suite struct CopyContractTests {

    // MARK: - Where the folder is

    /// The repository root, from this file: `…/ios/WingFoilKit/Tests/WingFoilKitTests/`
    /// is five levels down, and `#filePath` is the only thing a SwiftPM test can ask.
    /// There is no bundle to look in — the JSON is documentation, not a resource.
    static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    static var copyDir: URL { repoRoot.appendingPathComponent("docs/copy") }

    /// True when the suite is being asked to write rather than to check.
    static var isWriting: Bool { ProcessInfo.processInfo.environment["COPY_WRITE"] == "1" }

    /// Reads one file of the contract, with a failure message that says what to do rather
    /// than printing a path and stopping.
    static func load(_ name: String) throws -> [String: Any] {
        let dir = copyDir
        try #require(FileManager.default.fileExists(atPath: dir.path),
                     """
                     docs/copy is missing at \(dir.path) — the copy contract's single \
                     source. Expected the repository root five levels above this test file; \
                     if the tree moved, fix CopyContractTests.repoRoot.
                     """)
        let url = dir.appendingPathComponent(name)
        try #require(FileManager.default.fileExists(atPath: url.path),
                     """
                     docs/copy/\(name) is missing. Write it by hand, or regenerate the \
                     kit-owned keys with: COPY_WRITE=1 swift test --filter CopyContractTests
                     """)
        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data)
        return try #require(parsed as? [String: Any], "docs/copy/\(name) is not a JSON object")
    }

    /// Writes the kit-owned keys back, keeping every other key of the file untouched.
    ///
    /// Deterministic on purpose — sorted keys, two-space indent, unescaped slashes — so a
    /// regeneration that changes nothing produces no diff. The files stay hand-editable:
    /// the assertions compare *values*, never bytes, so formatting is nobody's contract.
    static func write(_ name: String, _ owned: [String: Any]) throws {
        let url = copyDir.appendingPathComponent(name)
        var merged = (try? load(name)) ?? [:]
        for (key, value) in owned { merged[key] = value }
        let data = try JSONSerialization.data(
            withJSONObject: merged,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (String(data: data, encoding: .utf8)! + "\n").write(to: url, atomically: true,
                                                                encoding: .utf8)
    }

    /// One assertion with a message that names the file, the key and the fix.
    static func same(_ actual: String, _ expected: Any?, _ file: String, _ key: String,
                     sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(actual == (expected as? String),
                """
                docs/copy/\(file) · \(key) is out of step with the kit.
                  kit:  \(actual)
                  json: \(expected.map { "\($0)" } ?? "«missing»")
                Move one to the other, then COPY_WRITE=1 swift test --filter CopyContractTests
                """,
                sourceLocation: sourceLocation)
    }

    static func same(_ actual: [String], _ expected: Any?, _ file: String, _ key: String,
                     sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(actual == (expected as? [String]),
                """
                docs/copy/\(file) · \(key) is out of step with the kit.
                  kit:  \(actual)
                  json: \(expected.map { "\($0)" } ?? "«missing»")
                Move one to the other, then COPY_WRITE=1 swift test --filter CopyContractTests
                """,
                sourceLocation: sourceLocation)
    }

    // MARK: - channels.json

    /// The beta and dev rows, and the name of the section that shows them. `ChannelFeatures`
    /// is written from docs/channels.md; this is the same list a Python verifier can read,
    /// so the website's "what is coming" block cannot be a fortnight behind it again.
    @Test func theChannelListsMatchTheirJSON() throws {
        if Self.isWriting {
            // The rows are objects with a stable id; the ids are hand-kept and survive a
            // rewording, so a rewrite replaces the texts by position and leaves them alone.
            let json = try Self.load("channels.json")
            func rows(_ key: String, _ texts: [String]) -> [[String: String]] {
                let existing = (json[key] as? [[String: Any]]) ?? []
                return texts.enumerated().map { index, text in
                    ["id": (existing.indices.contains(index)
                            ? existing[index]["id"] as? String : nil) ?? "row\(index + 1)",
                     "text": text]
                }
            }
            try Self.write("channels.json", [
                "sectionTitle": ChannelFeatures.sectionTitle,
                "beta": rows("beta", ChannelFeatures.beta),
                "dev": rows("dev", ChannelFeatures.dev),
            ])
            return
        }

        let json = try Self.load("channels.json")
        Self.same(ChannelFeatures.sectionTitle, json["sectionTitle"],
                  "channels.json", "sectionTitle")

        for (key, kit) in [("beta", ChannelFeatures.beta), ("dev", ChannelFeatures.dev)] {
            let rows = try #require(json[key] as? [[String: Any]],
                                    "channels.json · \(key) is not a list of objects")
            Self.same(kit, rows.map { $0["text"] as? String ?? "" }, "channels.json", key)
            let ids = rows.compactMap { $0["id"] as? String }
            #expect(ids.count == rows.count, "channels.json · \(key): every row needs an id")
            #expect(Set(ids).count == ids.count, "channels.json · \(key): duplicate ids")
        }
        // The forbidden list is hand-authored — it is the *release copy's* guard, not a kit
        // constant — but it has to exist and it has to name every door above the release.
        let forbidden = try #require(json["forbiddenInRelease"] as? [String],
                                     "channels.json · forbiddenInRelease is missing")
        #expect(!forbidden.isEmpty)
    }

    // MARK: - recording-classes.json

    @Test func theRecordingClassesMatchTheirJSON() throws {
        let rows: [[String: String]] = RecordingClass.allCases.map {
            ["id": $0.rawValue, "name": $0.name, "line": $0.line, "footerLine": $0.footerLine]
        }
        if Self.isWriting {
            try Self.write("recording-classes.json", ["classes": rows])
            return
        }
        let json = try Self.load("recording-classes.json")
        let listed = try #require(json["classes"] as? [[String: Any]],
                                  "recording-classes.json · classes is not a list of objects")
        #expect(listed.count == rows.count,
                "recording-classes.json has \(listed.count) classes, the kit has \(rows.count)")
        for (kit, file) in zip(rows, listed) {
            for key in ["id", "name", "line", "footerLine"] {
                Self.same(kit[key]!, file[key], "recording-classes.json",
                          "\(kit["id"]!).\(key)")
            }
        }
    }

    // MARK: - glossary.json

    @Test func theGlossaryMatchesItsJSON() throws {
        let rows: [[String: String]] = MetricGlossary.entries.map {
            ["id": $0.id, "term": $0.term, "line": $0.line]
        }
        if Self.isWriting {
            try Self.write("glossary.json", ["entries": rows])
            return
        }
        let json = try Self.load("glossary.json")
        let listed = try #require(json["entries"] as? [[String: Any]],
                                  "glossary.json · entries is not a list of objects")
        #expect(listed.count == 8, "the glossary is eight entries, found \(listed.count)")
        #expect(listed.count == rows.count)
        for (kit, file) in zip(rows, listed) {
            for key in ["id", "term", "line"] {
                Self.same(kit[key]!, file[key], "glossary.json", "\(kit["id"]!).\(key)")
            }
        }
    }

    /// The welcome screen picks four of the eight rather than writing its own, which is the
    /// whole point of the type: a glossary line edited once reaches both surfaces.
    @Test func theWelcomeHighlightsComeFromTheGlossary() {
        for highlight in WelcomeGuide.highlights {
            let entry = MetricGlossary.entries.first { $0.term == highlight.term }
            #expect(entry?.line == highlight.detail,
                    "\"\(highlight.term)\" on the welcome screen is not a glossary line")
        }
    }

    // MARK: - feedback.json

    @Test func theFeedbackPromptsMatchTheirJSON() throws {
        let prompts = [FeedbackReport.Prompt.what, FeedbackReport.Prompt.expected,
                       FeedbackReport.Prompt.session]
        let subjectPrefix = Branding.appName + " feedback"
        if Self.isWriting {
            try Self.write("feedback.json", [
                "prompts": prompts,
                "invitation": FeedbackInvitation.sentence,
                "subjectPrefix": subjectPrefix,
            ])
            return
        }
        let json = try Self.load("feedback.json")
        Self.same(prompts, json["prompts"], "feedback.json", "prompts")
        Self.same(FeedbackInvitation.sentence, json["invitation"],
                  "feedback.json", "invitation")
        Self.same(subjectPrefix, json["subjectPrefix"], "feedback.json", "subjectPrefix")
    }

    // MARK: - icu-setup.json

    @Test func theIcuSetupStepsMatchTheirJSON() throws {
        let steps: [[String: String]] = IcuSetupGuide.steps.map {
            ["title": $0.title, "detail": $0.detail]
        }
        if Self.isWriting {
            try Self.write("icu-setup.json", [
                "steps": steps,
                "saveButton": IcuSetupGuide.saveButton,
                "privacyNote": IcuSetupGuide.privacyNote,
            ])
            return
        }
        let json = try Self.load("icu-setup.json")
        let listed = try #require(json["steps"] as? [[String: Any]],
                                  "icu-setup.json · steps is not a list of objects")
        #expect(listed.count == steps.count,
                "icu-setup.json has \(listed.count) steps, the kit has \(steps.count)")
        for (index, (kit, file)) in zip(steps, listed).enumerated() {
            Self.same(kit["title"]!, file["title"], "icu-setup.json", "steps[\(index)].title")
            Self.same(kit["detail"]!, file["detail"], "icu-setup.json", "steps[\(index)].detail")
        }
        Self.same(IcuSetupGuide.saveButton, json["saveButton"], "icu-setup.json", "saveButton")
        Self.same(IcuSetupGuide.privacyNote, json["privacyNote"],
                  "icu-setup.json", "privacyNote")
    }

    // MARK: - phrases.json

    @Test func theSharedPhrasesMatchTheirJSON() throws {
        if Self.isWriting {
            try Self.write("phrases.json", [
                "promise": WelcomeGuide.promise,
                "headline": WelcomeGuide.headline,
                "callToAction": Branding.callToAction,
                "captionOffer": ShareCaption.offer,
            ])
            return
        }
        let json = try Self.load("phrases.json")
        Self.same(WelcomeGuide.promise, json["promise"], "phrases.json", "promise")
        Self.same(WelcomeGuide.headline, json["headline"], "phrases.json", "headline")
        Self.same(Branding.callToAction, json["callToAction"], "phrases.json", "callToAction")
        Self.same(ShareCaption.offer, json["captionOffer"], "phrases.json", "captionOffer")

        // The hand-authored half. Not kit constants — they are facts about Strava, the
        // stores and the vocabulary — but the file is worthless without them, so their
        // absence is a failure rather than a silence.
        for key in ["strava", "ciqListingTitle", "appStoreName", "appStoreSubtitle"] {
            #expect(json[key] is String, "phrases.json · \(key) is missing")
        }
        #expect(json["stravaForbidden"] is [String],
                "phrases.json · stravaForbidden is missing")
        let lexicon = try #require(json["lexicon"] as? [String: Any],
                                   "phrases.json · lexicon is missing")
        #expect(lexicon["banned"] is [String])
        #expect(lexicon["preferred"] is [String: Any])

        // The rule docs/channels.md sets: the rider is never told what Strava has or has
        // not reviewed. The pinned sentence must not itself break it.
        let sentence = (json["strava"] as? String ?? "").lowercased()
        for forbidden in (json["stravaForbidden"] as? [String] ?? []) {
            #expect(!sentence.contains(forbidden.lowercased()),
                    "phrases.json · the Strava sentence says \"\(forbidden)\"")
        }
    }

    // MARK: - verdicts.json

    /// The not-a-session wording. The two page lines carry `{duration}` and `{distance}`
    /// where the row's own numbers go — the placeholders are the JSON's, not the kit's, so
    /// the check substitutes a known pair and compares the whole sentence.
    @Test func theNotASessionWordingMatchesItsJSON() throws {
        let durationS = 95.0, distanceKm = 0.4
        let lines = [
            NotASessionNote.line(reason: .noRecording, durationS: nil, distanceKm: nil),
            NotASessionNote.line(reason: .tooShort, durationS: durationS,
                                 distanceKm: distanceKm),
        ]
        if Self.isWriting {
            let templated = [
                lines[0],
                lines[1]
                    .replacingOccurrences(of: NotASessionNote.clock(durationS),
                                          with: "{duration}")
                    .replacingOccurrences(of: NotASessionNote.distance(distanceKm),
                                          with: "{distance}"),
            ]
            try Self.write("verdicts.json", [
                "notASession": ["tag": NotASessionNote.tag, "lines": templated],
            ])
            return
        }
        let json = try Self.load("verdicts.json")
        let note = try #require(json["notASession"] as? [String: Any],
                                "verdicts.json · notASession is missing")
        Self.same(NotASessionNote.tag, note["tag"], "verdicts.json", "notASession.tag")
        let templated = try #require(note["lines"] as? [String],
                                     "verdicts.json · notASession.lines is missing")
        let filled = templated.map {
            $0.replacingOccurrences(of: "{duration}", with: NotASessionNote.clock(durationS))
                .replacingOccurrences(of: "{distance}",
                                      with: NotASessionNote.distance(distanceKm))
        }
        Self.same(lines, filled, "verdicts.json", "notASession.lines")
    }

    // MARK: - The lexicon

    /// **The words this product does not use**, greped out of the kit's own rider-facing
    /// sources rather than trusted to a review.
    ///
    /// CLAUDE.md fixes the vocabulary — *flew through*, *clean*, *dry* — and says that
    /// "success" and "carried" are engine-internal and appear in no rider-facing text. The
    /// welcome screen said "how many you carried in a row" for a fortnight anyway, which is
    /// what a rule with no check is worth.
    ///
    /// Only **string literals** are read: the doc comments above them are written for the
    /// next author and describe the engine on purpose. The exemptions in the JSON are the
    /// places where a banned word is ordinary English or a pinned cross-platform string;
    /// each names its file and says why.
    @Test func noBannedWordReachesTheRiderFacingKit() throws {
        let json = try Self.load("phrases.json")
        let lexicon = try #require(json["lexicon"] as? [String: Any])
        let banned = try #require(lexicon["banned"] as? [String])
        let exemptions = (lexicon["exemptions"] as? [[String: Any]]) ?? []

        let sources = Self.repoRoot
            .appendingPathComponent("ios/WingFoilKit/Sources/WingFoilKit")
        var hits: [String] = []
        for folder in ["Presentation", "Help"] {
            let root = sources.appendingPathComponent(folder)
            let walker = FileManager.default.enumerator(at: root,
                                                        includingPropertiesForKeys: nil)
            while let url = walker?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let relative = url.path.replacingOccurrences(of: Self.repoRoot.path + "/",
                                                             with: "")
                let allowed = Set(exemptions.compactMap { exemption -> String? in
                    guard let path = exemption["path"] as? String,
                          relative.hasPrefix(path) else { return nil }
                    return (exemption["word"] as? String)?.lowercased()
                })
                let text = try String(contentsOf: url, encoding: .utf8)
                for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") { continue }
                    for literal in Self.stringLiterals(in: String(line)) {
                        for word in banned where !allowed.contains(word.lowercased()) {
                            if Self.containsWholeWord(word, in: literal) {
                                hits.append("\(relative):\(number + 1) says \"\(word)\"")
                            }
                        }
                    }
                }
            }
        }
        #expect(hits.isEmpty, """
                banned vocabulary in rider-facing copy (CLAUDE.md, docs/copy/README.md):
                \(hits.joined(separator: "\n"))
                """)
    }

    /// Every `"…"` on a line, with escapes left alone — close enough to find a word in, and
    /// exact enough not to read the code around it.
    static func stringLiterals(in line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inside = false, escaped = false
        for character in line {
            if escaped { if inside { current.append(character) }; escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "\"" {
                if inside { out.append(current); current = "" }
                inside.toggle()
                continue
            }
            if inside { current.append(character) }
        }
        return out
    }

    /// Whole words, case-insensitively: "carried" must fire and "carriedness" must not,
    /// and a hyphenated term like "no-fall streak" has to match as it is written.
    static func containsWholeWord(_ word: String, in text: String) -> Bool {
        let haystack = text.lowercased(), needle = word.lowercased()
        var search = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: search) {
            let before = found.lowerBound == haystack.startIndex
                ? nil : haystack[haystack.index(before: found.lowerBound)]
            let after = found.upperBound == haystack.endIndex
                ? nil : haystack[found.upperBound]
            func isWordish(_ character: Character?) -> Bool {
                guard let character else { return false }
                return character.isLetter || character.isNumber || character == "-"
            }
            if !isWordish(before) && !isWordish(after) { return true }
            guard found.upperBound < haystack.endIndex else { return false }
            search = found.upperBound..<haystack.endIndex
        }
        return false
    }
}
