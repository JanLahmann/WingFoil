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
        // The feedback mail's "Most wanted" ticks are these same rows, by id, in order: a
        // tick is tallied by the id, so an id the JSON does not have is a vote for nothing.
        let jsonIds = ["beta", "dev"].flatMap { key in
            ((json[key] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        }
        #expect(MostWanted.all.map(\.id) == jsonIds,
                "MostWanted.all is out of step with channels.json's beta and dev ids")
        let betaIds = ((json["beta"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        #expect(MostWanted.all.filter { $0.channel == .beta }.map(\.id) == betaIds)

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

    /// **The kit owns `id`, `term`, `expansion`, `line` and `surfaces`.**
    ///
    /// `short` and `sentence` are hand-authored beside them, exactly the way `lexicon` and
    /// `ciqListingTitle` live in `phrases.json`: the watch's seven-character budget and the
    /// store voice's clause are copy-editing decisions, and a `COPY_WRITE=1` rewrite
    /// carries the file's own values forward rather than flattening them. The kit's values
    /// are the seed a **new** entry is born with and nothing more.
    @Test func theGlossaryMatchesItsJSON() throws {
        if Self.isWriting {
            let existing = ((try? Self.load("glossary.json"))?["entries"]
                            as? [[String: Any]]) ?? []
            func kept(_ id: String, _ key: String, _ seed: String) -> String {
                (existing.first { $0["id"] as? String == id }?[key] as? String) ?? seed
            }
            let rows: [[String: Any]] = MetricGlossary.entries.map {
                ["id": $0.id,
                 "term": $0.term,
                 "short": kept($0.id, "short", $0.short),
                 "expansion": $0.expansion,
                 "line": $0.line,
                 "sentence": kept($0.id, "sentence", $0.sentence),
                 "surfaces": $0.surfaces.map(\.rawValue),
                 // Where it shows, every spelling a surface may print, and the FIT field
                 // behind it. All three are kit-owned: they are what a lint and a help
                 // topic read, not copy-editing decisions (20 September 2026).
                 "places": $0.places.map(\.rawValue),
                 "labels": $0.labels,
                 "fit": $0.fit]
            }
            try Self.write("glossary.json", ["entries": rows])
            return
        }

        let json = try Self.load("glossary.json")
        let listed = try #require(json["entries"] as? [[String: Any]],
                                  "glossary.json · entries is not a list of objects")
        #expect(listed.count == 19,
                "the glossary is nineteen entries, found \(listed.count)")
        #expect(listed.count == MetricGlossary.entries.count)
        for (kit, file) in zip(MetricGlossary.entries, listed) {
            Self.same(kit.id, file["id"], "glossary.json", "\(kit.id).id")
            Self.same(kit.term, file["term"], "glossary.json", "\(kit.id).term")
            Self.same(kit.expansion, file["expansion"], "glossary.json", "\(kit.id).expansion")
            Self.same(kit.line, file["line"], "glossary.json", "\(kit.id).line")
            Self.same(kit.surfaces.map(\.rawValue), file["surfaces"],
                      "glossary.json", "\(kit.id).surfaces")
            Self.same(kit.places.map(\.rawValue), file["places"],
                      "glossary.json", "\(kit.id).places")
            Self.same(kit.labels, file["labels"], "glossary.json", "\(kit.id).labels")
            Self.same(kit.fit, file["fit"], "glossary.json", "\(kit.id).fit")
        }
    }

    /// **The watch is not excused from the contract — it is held to it at its own width.**
    ///
    /// A MIP cell is about seven characters, and three watch labels shipped over that
    /// budget (`best 10s`, `takeoffs`, `foil dist`). The answer is a per-term `short`
    /// authored beside the term, so the budget fails a test rather than failing a rider.
    /// `sentence` is the same trick one level down for the two store descriptions, which
    /// are prose and print a clause where the app prints a label.
    @Test func everyGlossaryEntryCarriesAShortAndASentence() throws {
        let json = try Self.load("glossary.json")
        let listed = try #require(json["entries"] as? [[String: Any]],
                                  "glossary.json · entries is not a list of objects")
        for file in listed {
            let id = (file["id"] as? String) ?? "«no id»"
            let short = (file["short"] as? String) ?? ""
            let sentence = (file["sentence"] as? String) ?? ""
            #expect(!short.isEmpty,
                    """
                    glossary.json · \(id).short is missing — hand-author the watch's word \
                    for it, at most seven characters wherever surfaces names "watch"
                    """)
            #expect(!sentence.isEmpty,
                    """
                    glossary.json · \(id).sentence is missing — the clause the App Store \
                    and Connect IQ descriptions use instead of the label
                    """)
            let surfaces = (file["surfaces"] as? [String]) ?? []
            #expect(!surfaces.isEmpty, "glossary.json · \(id).surfaces is empty")
            for surface in surfaces {
                #expect(MetricSurface(rawValue: surface) != nil,
                        """
                        glossary.json · \(id).surfaces names "\(surface)", which is not \
                        a surface
                        """)
            }
            if surfaces.contains(MetricSurface.watch.rawValue) {
                #expect(short.count <= Self.watchCellBudget,
                        """
                        glossary.json · \(id).short is \(short.count) characters \
                        ("\(short)") and a MIP cell is \(Self.watchCellBudget). Shorten it, \
                        or take "watch" out of surfaces if the watch does not show it.
                        """)
            }
        }
        // The kit's seeds are what a new entry is born with, so they keep the same budget.
        for entry in MetricGlossary.entries {
            #expect(!entry.short.isEmpty, "\(entry.id) has no short in the kit")
            #expect(!entry.sentence.isEmpty, "\(entry.id) has no sentence in the kit")
            if entry.surfaces.contains(.watch) {
                #expect(entry.short.count <= Self.watchCellBudget,
                        "\(entry.id): the kit's short is \(entry.short.count) characters")
            }
        }
    }

    /// A MIP cell (`PageModel.label()`), measured against the watch's own drawn strings.
    static let watchCellBudget = 7

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
                "doors": Self.doors,
            ])
            return
        }
        let json = try Self.load("feedback.json")
        Self.same(prompts, json["prompts"], "feedback.json", "prompts")
        Self.same(FeedbackInvitation.sentence, json["invitation"],
                  "feedback.json", "invitation")
        Self.same(subjectPrefix, json["subjectPrefix"], "feedback.json", "subjectPrefix")
    }

    /// Every door to that mail, named as the rider finds it.
    static var doors: [String: String] {
        Dictionary(uniqueKeysWithValues: FeedbackDoors.all.map { ($0.id, $0.name) })
    }

    /// **One name per door, on every surface** (15 September 2026).
    ///
    /// There were five spellings of one door, and one of them — `Settings → Send feedback`,
    /// inside the app's own Help — named a row deleted in build 58. `feedback.json` pinned
    /// the three prompts, the invitation and the subject prefix, and **no door name**, so
    /// nothing on either side of the contract could notice. It does now.
    @Test func theFeedbackDoorsMatchTheirJSON() throws {
        let json = try Self.load("feedback.json")
        let listed = try #require(json["doors"] as? [String: String],
                                  """
                                  docs/copy/feedback.json · doors is missing. It is the \
                                  name of every door to the feedback mail; write it with \
                                  COPY_WRITE=1 swift test --filter CopyContractTests
                                  """)
        #expect(listed.count == Self.doors.count,
                """
                feedback.json · doors has \(listed.count) doors, the kit names \
                \(Self.doors.count)
                """)
        for (id, name) in Self.doors {
            Self.same(name, listed[id], "feedback.json", "doors.\(id)")
        }

        // The app's Help quotes three of them by name rather than retyping them: that
        // sentence is what sent riders to a deleted Settings row for a week.
        let prose = HelpCatalog.topic(.sendingFeedback).body.joined(separator: " ")
        for door in [FeedbackDoors.app, FeedbackDoors.footer, FeedbackDoors.share] {
            #expect(prose.contains(door), "the Sending feedback topic never names \"\(door)\"")
        }
        #expect(!prose.contains("Settings → Send feedback"),
                "the app's own Help still names the Settings row deleted in build 58")
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

    // MARK: - presentation.json

    /// **The words the presentation document points at, authored by the kit that prints
    /// them** (ADR-033, round 2).
    ///
    /// They were hand-authored in `docs/copy/presentation.json` in round 1 — the right file
    /// and the wrong author. The copy contract's rule is that the kit authors anything the
    /// app says (`docs/copy/README.md`, "The contract"), and every one of these strings is
    /// printed by a renderer in this package: a hand-authored label the kit prints is a
    /// label the kit cannot be held to, which is the exact shape of the drift this folder
    /// exists to stop. `PresentationCopy` is the author now and this is the artefact.
    ///
    /// `caption` is the one group with structure: a line with a singular form is an object
    /// (`{"one", "other"}`), a line without one is a plain string, which is how the file
    /// reads today and what the lab's `copy_ids()` walks.
    @Test func thePresentationCopyMatchesItsJSON() throws {
        let groups: [String: [String: Any]] = [
            "label": PresentationCopy.label,
            "rowMetric": PresentationCopy.rowMetric,
            "turnKind": PresentationCopy.turnKind,
            "caption": PresentationCopy.caption.mapValues { line -> Any in
                line.one.map { ["one": $0, "other": line.other] as Any } ?? line.other
            },
            "wristUnder": PresentationCopy.wristUnder,
            "divergence": PresentationCopy.divergence,
            "banner": PresentationCopy.banner,
            "card": PresentationCopy.card.mapValues { line -> Any in
                line.one.map { ["one": $0, "other": line.other] as Any } ?? line.other
            },
        ]
        if Self.isWriting {
            try Self.write("presentation.json", groups.mapValues { $0 as Any })
            return
        }

        let json = try Self.load("presentation.json")
        for (group, kit) in groups.sorted(by: { $0.key < $1.key }) {
            let listed = try #require(json[group] as? [String: Any],
                                      """
                                      docs/copy/presentation.json · \(group) is missing. \
                                      Write it with COPY_WRITE=1 swift test --filter \
                                      CopyContractTests
                                      """)
            #expect(Set(listed.keys) == Set(kit.keys),
                    """
                    docs/copy/presentation.json · \(group) has \
                    \(Set(listed.keys).symmetricDifference(Set(kit.keys)).sorted()) \
                    on one side only.
                    """)
            for (key, value) in kit {
                if let text = value as? String {
                    Self.same(text, listed[key], "presentation.json", "\(group).\(key)")
                } else if let forms = value as? [String: String] {
                    let file = listed[key] as? [String: String]
                    for (form, text) in forms {
                        Self.same(text, file?[form], "presentation.json",
                                  "\(group).\(key).\(form)")
                    }
                }
            }
        }
    }

    /// **Every id the document can emit has a home.**
    ///
    /// The lab asserts the same thing against `docs/copy/*.json` from the outside
    /// (`test_every_label_and_caption_is_an_id_that_exists_in_copy`); this asserts it
    /// against the resolver the phone actually calls, which is the half that decides
    /// whether a rider reads a word or an empty space. Both halves have to hold: a file the
    /// lab can read and a Swift switch that forgets a namespace is a label missing on one
    /// platform only.
    @Test func everyIdTheDocumentCanEmitHasAHome() throws {
        var ids: Set<String> = ["verdicts.notASession.tag",
                                "verdicts.notASession.lines.0",
                                "verdicts.notASession.lines.1"]
        for group in ["label", "caption", "wristUnder", "divergence"] {
            let keys: [String]
            switch group {
            case "label": keys = Array(PresentationCopy.label.keys)
            case "caption": keys = Array(PresentationCopy.caption.keys)
            case "wristUnder": keys = Array(PresentationCopy.wristUnder.keys)
            default: keys = Array(PresentationCopy.divergence.keys)
            }
            ids.formUnion(keys.map { "presentation.\(group).\($0)" })
        }
        ids.formUnion(RowMetric.allCases.map { "presentation.rowMetric.\($0.rawValue)" })
        ids.formUnion(PresentationCopy.turnKind.keys.map { "presentation.turnKind.\($0)" })
        ids.formUnion(RecordKind.allCases.map { "tokens.recordWindow.\($0.rawValue)" })
        ids.formUnion(MapLayer.allCases.map { "tokens.layer.\($0.rawValue)" })
        // The five the block and the row name by glossary id.
        ids.formUnion(["fellIn", "flewThrough", "dry", "jph", "cph", "tph", "wph"]
            .map { "glossary.\($0)" })

        for id in ids.sorted() {
            let text = PresentationCopy.text(id, args: ["durationS": "0", "distanceKm": "0"])
            #expect(text?.isEmpty == false,
                    """
                    the document can emit "\(id)" and PresentationCopy resolves it to \
                    nothing — a rider would read an empty label there.
                    """)
        }
        // And the other direction, on the namespaces: an id in no namespace resolves to
        // nothing rather than to a plausible-looking empty string.
        #expect(PresentationCopy.text("presentation.label.notAThing") == nil)
        #expect(PresentationCopy.text("nowhere.at.all") == nil)
    }

    // MARK: - phrases.json

    @Test func theSharedPhrasesMatchTheirJSON() throws {
        if Self.isWriting {
            try Self.write("phrases.json", [
                "promise": WelcomeGuide.promise,
                "headline": WelcomeGuide.headline,
                "callToAction": Branding.callToAction,
                "tagline": Branding.tagline,
                "captionOffer": ShareCaption.offer,
            ])
            return
        }
        let json = try Self.load("phrases.json")
        Self.same(WelcomeGuide.promise, json["promise"], "phrases.json", "promise")
        Self.same(WelcomeGuide.headline, json["headline"], "phrases.json", "headline")
        Self.same(Branding.callToAction, json["callToAction"], "phrases.json", "callToAction")
        Self.same(Branding.tagline, json["tagline"], "phrases.json", "tagline")
        Self.same(ShareCaption.offer, json["captionOffer"], "phrases.json", "captionOffer")
        Self.same(Copy.stravaFall, json["stravaFall"], "phrases.json", "stravaFall")

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
