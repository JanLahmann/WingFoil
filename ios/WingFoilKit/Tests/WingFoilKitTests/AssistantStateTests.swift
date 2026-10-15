import Foundation
import Testing
@testable import WingFoilKit

/// **Ask CleanJibe's state, held to its contract** — `docs/copy/assistant/
/// session-state.schema.json`, loaded from the repo and checked by the small validator
/// below (types, enums, const, patterns, required, no extra keys, maxItems, bounds), and
/// to the two worked examples beside it, built from the same corpus sessions.
@Suite struct AssistantStateTests {

    static let assistantDir = testFixturesDir.deletingLastPathComponent()
        .appendingPathComponent("docs/copy/assistant")

    static func schema() throws -> [String: Any] {
        let url = assistantDir.appendingPathComponent("session-state.schema.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                            as? [String: Any])
    }

    static func example(_ name: String) throws -> [String: Any] {
        let url = assistantDir.appendingPathComponent(name)
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                            as? [String: Any])
    }

    static let app = AssistantApp(channel: "beta", appVersion: "1.0.1", build: 133,
                                  speed: .knots)

    /// A library row for a corpus golden: the start off the stem's local minute (the
    /// corpus is CEST), the class letter off its suffix.
    static func row(_ stem: String, importSource: String = "file") throws -> SessionRow {
        let parts = stem.prefix(15)   // 2026-08-07-0754
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = fixtureZone
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let start = try #require(f.date(from: String(parts)), "\(stem): no start in the stem")
        let cls = stem.hasSuffix("_ciq") ? "a"
            : (stem.hasSuffix("nospeed") || stem.hasSuffix("nago-torbole")) ? "c" : "b"
        var row = SessionRow(startDate: start, durationS: 0, sourceClass: cls)
        row.startUtcOffsetS = fixtureZone.secondsFromGMT()
        row.importSource = importSource
        return row
    }

    static func state(_ stem: String) throws -> (data: Data, json: [String: Any]) {
        let analysis = try DocumentRendererTests.analysis(stem)
        let data = AssistantState.session(app, row: try row(stem), analysis: analysis)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (data, json)
    }

    // MARK: - The schema

    @Test func helpStateValidates() throws {
        let data = AssistantState.help(Self.app)
        let json = try JSONSerialization.jsonObject(with: data)
        let errors = SchemaCheck.validate(json, against: try Self.schema())
        #expect(errors.isEmpty, "\(errors)")
        let object = try #require(json as? [String: Any])
        #expect(object["session"] == nil)
        #expect(object["engineVersion"] as? String == AnalysisEngine.version)
        #expect(object["surface"] as? String == "ios")
        #expect(object["build"] as? Int == 133)
        #expect((object["units"] as? [String: Any])?["speed"] as? String == "kn")

        let kmh = AssistantState.help(AssistantApp(channel: "release", appVersion: "1.0.1",
                                                   speed: .kmh))
        let k = try #require(try JSONSerialization.jsonObject(with: kmh) as? [String: Any])
        #expect(k["build"] == nil)
        #expect((k["units"] as? [String: Any])?["speed"] as? String == "kmh")
        #expect(SchemaCheck.validate(k, against: try Self.schema()).isEmpty)
    }

    /// Every corpus session's state validates, and stays under the server's bar.
    @Test func everyCorpusSessionValidates() throws {
        let schema = try Self.schema()
        let dir = testFixturesDir.appendingPathComponent("goldens")
        let stems = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".expected.json") && $0.hasPrefix("20") }
            .map { String($0.dropLast(".expected.json".count)) }
            .sorted()
        try #require(stems.count >= 2)
        for stem in stems {
            let (data, json) = try Self.state(stem)
            let errors = SchemaCheck.validate(json, against: schema)
            #expect(errors.isEmpty, "\(stem): \(errors)")
            #expect(data.count < 12_000, "\(stem): \(data.count) bytes")
            #expect(data.count <= AssistantState.maxBytes, "\(stem): \(data.count) bytes")
        }
    }

    /// The largest session in the corpus (by counted turns) — the one the cap is for.
    @Test func largestSessionStaysUnderTheBar() throws {
        let stem = "2026-08-05-1356_nago-torbole-foilmotion_foilmotion"
        let analysis = try DocumentRendererTests.analysis(stem)
        let counted = analysis.turns.filter(\.counted).count
        let (data, json) = try Self.state(stem)
        #expect(data.count < 12_000, "\(data.count) bytes")
        let list = try #require((json["session"] as? [String: Any])?["turnList"] as? [Any])
        #expect(list.count <= counted)
        #expect(list.count > 0)
        #expect(SchemaCheck.validate(json, against: try Self.schema()).isEmpty)
    }

    // MARK: - The examples' meaning

    /// The CleanJibe watch app session of 7 Aug: field for field what the example says,
    /// except `device` (the row does not record the watch) and `watchVsPhone` (no watch
    /// summary was paired).
    @Test func watchAppSessionMatchesItsExample() throws {
        try matchExample("example-session-watch-app.json",
                         stem: "2026-08-07-0754_nago-torbole-windsurfen_ciq",
                         ignoredSource: ["device"])
    }

    /// The Garmin's own recording of 1 Aug, imported from a GDPR export (the door that
    /// names the maker).
    @Test func garminNativeSessionMatchesItsExample() throws {
        try matchExample("example-session-garmin-native.json",
                         stem: "2026-08-01-0804_nago-torbole-windsurfen_native",
                         importSource: "gdpr", ignoredSource: ["device"])
    }

    /// A positions-only recording under the rate floor: estimated records, nulls for
    /// every rate, `tooShort`.
    @Test func positionsOnlyShortSession() throws {
        let (_, json) = try Self.state("2026-08-30-1407_nago-torbole-nospeed")
        let s = try #require(json["session"] as? [String: Any])
        #expect((s["source"] as? [String: Any])?["kind"] as? String == "positionsOnly")
        #expect((s["source"] as? [String: Any])?["hasDoppler"] as? Bool == false)
        #expect((s["records"] as? [String: Any])?["estimated"] as? Bool == true)
        let rates = try #require(s["rates"] as? [String: Any])
        #expect(rates["tooShort"] as? Bool == true)
        #expect(rates["cph"] is NSNull)
        #expect(rates["wph"] is NSNull)
        #expect((s["takeoff"] as? [String: Any])?["attempts"] is NSNull)
        #expect(s["jumps"] is NSNull)
    }

    @Test func tipsAndDivergencesReachTheState() throws {
        let stem = "2026-08-07-0754_nago-torbole-windsurfen_ciq"
        let analysis = try DocumentRendererTests.analysis(stem)
        let index = analysis.turns.firstIndex { $0.counted }
        let first = try #require(index)
        let tip = TurnCoach.tipText(.comeInFaster, type: "jibe")
        let lines = [Divergence(metricId: "jibes", labelId: "presentation.divergence.jibes",
                                watchValue: 29, phoneValue: 31, unitKind: "count")]
        let data = AssistantState.session(Self.app, row: try Self.row(stem), analysis: analysis,
                                          tips: [first: tip], divergences: lines)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(SchemaCheck.validate(json, against: try Self.schema()).isEmpty)
        let s = try #require(json["session"] as? [String: Any])
        let list = try #require(s["turnList"] as? [[String: Any]])
        #expect(list.first?["tip"] as? String == tip)
        let wvp = try #require(s["watchVsPhone"] as? [[String: Any]])
        #expect(wvp.count == 1)
        #expect(wvp.first?["watch"] as? Int == 29)
        #expect(wvp.first?["phone"] as? Int == 31)
    }

    private func matchExample(_ file: String, stem: String, importSource: String = "file",
                              ignoredSource: Set<String>) throws {
        let want = try #require(try Self.example(file)["session"] as? [String: Any])
        let analysis = try DocumentRendererTests.analysis(stem)
        let data = AssistantState.session(Self.app,
                                          row: try Self.row(stem, importSource: importSource),
                                          analysis: analysis)
        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(SchemaCheck.validate(top, against: try Self.schema()).isEmpty)
        let got = try #require(top["session"] as? [String: Any])

        for (key, value) in want where !["source", "turnList", "watchVsPhone"].contains(key) {
            #expect(SchemaCheck.same(got[key], value), "\(stem): session.\(key) \(String(describing: got[key])) vs \(value)")
        }
        let wantSource = try #require(want["source"] as? [String: Any])
        let gotSource = try #require(got["source"] as? [String: Any])
        for (key, value) in wantSource where !ignoredSource.contains(key) {
            #expect(SchemaCheck.same(gotSource[key], value), "\(stem): source.\(key)")
        }
        #expect(gotSource["device"] == nil)
        #expect(got["watchVsPhone"] == nil)

        // The turn list: the same turns in the same order, as far as the byte cap let it go.
        let wantList = try #require(want["turnList"] as? [[String: Any]])
        let gotList = try #require(got["turnList"] as? [[String: Any]])
        #expect(!gotList.isEmpty)
        #expect(gotList.count <= wantList.count)
        for (i, item) in gotList.enumerated() {
            for (key, value) in wantList[i] {
                #expect(SchemaCheck.same(item[key], value),
                        "\(stem): turnList[\(i)].\(key) \(String(describing: item[key])) vs \(value)")
            }
            #expect(Set(item.keys) == Set(wantList[i].keys), "\(stem): turnList[\(i)] keys")
        }
        if gotList.count < wantList.count {
            #expect(data.count > AssistantState.maxBytes - 400,
                    "\(stem): turnList cut to \(gotList.count) at only \(data.count) bytes")
        }
    }
}

// MARK: - A small JSON Schema checker

/// Enough of draft 2020-12 for the assistant's schema: `type` (one or a list), `enum`,
/// `const`, `pattern`, `required`, `properties`, `additionalProperties: false`, `items`,
/// `maxItems`, `minimum`, `maximum`, `maxLength`. A keyword it does not know fails loudly,
/// so the schema cannot outgrow it in silence.
enum SchemaCheck {

    static let known: Set<String> = [
        "$schema", "$id", "title", "description", "type", "enum", "const", "pattern",
        "required", "properties", "additionalProperties", "items", "maxItems", "minimum",
        "maximum", "maxLength",
    ]

    static func validate(_ value: Any, against schema: [String: Any],
                         path: String = "$") -> [String] {
        var errors: [String] = []
        for key in schema.keys where !known.contains(key) {
            errors.append("\(path): schema keyword \(key) is not checked")
        }
        if let type = schema["type"] {
            let types = (type as? [String]) ?? [(type as? String) ?? ""]
            if !types.contains(where: { matches(value, type: $0) }) {
                errors.append("\(path): \(String(describing: value)) is not \(types)")
                return errors
            }
        }
        if let options = schema["enum"] as? [Any], !options.contains(where: { same(value, $0) }) {
            errors.append("\(path): \(String(describing: value)) not in \(options)")
        }
        if let constant = schema["const"], !same(value, constant) {
            errors.append("\(path): \(String(describing: value)) is not \(constant)")
        }
        if let string = value as? String, !isBool(value) {
            if let pattern = schema["pattern"] as? String,
               string.range(of: pattern, options: .regularExpression) == nil {
                errors.append("\(path): \(string) does not match \(pattern)")
            }
            if let max = schema["maxLength"] as? Int, string.count > max {
                errors.append("\(path): longer than \(max)")
            }
        }
        if let number = value as? NSNumber, !isBool(value), !(value is String) {
            if let min = (schema["minimum"] as? NSNumber)?.doubleValue, number.doubleValue < min {
                errors.append("\(path): \(number) < \(min)")
            }
            if let max = (schema["maximum"] as? NSNumber)?.doubleValue, number.doubleValue > max {
                errors.append("\(path): \(number) > \(max)")
            }
        }
        if let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: Any] ?? [:]
            for key in (schema["required"] as? [String]) ?? [] where object[key] == nil {
                errors.append("\(path): missing required \(key)")
            }
            for (key, child) in object {
                if let sub = properties[key] as? [String: Any] {
                    errors += validate(child, against: sub, path: path + "." + key)
                } else if (schema["additionalProperties"] as? Bool) == false {
                    errors.append("\(path): unexpected key \(key)")
                }
            }
        }
        if let array = value as? [Any] {
            if let max = schema["maxItems"] as? Int, array.count > max {
                errors.append("\(path): \(array.count) items > \(max)")
            }
            if let items = schema["items"] as? [String: Any] {
                for (i, child) in array.enumerated() {
                    errors += validate(child, against: items, path: "\(path)[\(i)]")
                }
            }
        }
        return errors
    }

    static func isBool(_ value: Any) -> Bool {
        guard let n = value as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    static func matches(_ value: Any, type: String) -> Bool {
        switch type {
        case "null": return value is NSNull
        case "boolean": return isBool(value)
        case "string": return value is String
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "number": return value is NSNumber && !isBool(value) && !(value is String)
        case "integer":
            guard let n = value as? NSNumber, !isBool(value), !(value is String) else {
                return false
            }
            return n.doubleValue.rounded() == n.doubleValue
        default: return false
        }
    }

    /// JSON equality: numbers by value (1 == 1.0), booleans apart from numbers.
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (x?, y?):
            if x is NSNull || y is NSNull { return x is NSNull && y is NSNull }
            if isBool(x) || isBool(y) {
                return isBool(x) && isBool(y) && (x as? Bool) == (y as? Bool)
            }
            if let p = x as? String, let q = y as? String { return p == q }
            if let p = x as? NSNumber, let q = y as? NSNumber {
                return abs(p.doubleValue - q.doubleValue) < 1e-9
            }
            if let p = x as? [Any], let q = y as? [Any] {
                return p.count == q.count && zip(p, q).allSatisfy { same($0, $1) }
            }
            if let p = x as? [String: Any], let q = y as? [String: Any] {
                return Set(p.keys) == Set(q.keys) && p.allSatisfy { same($0.value, q[$0.key]) }
            }
            return false
        }
    }
}
