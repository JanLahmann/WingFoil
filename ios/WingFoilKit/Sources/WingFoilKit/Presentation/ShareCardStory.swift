import Foundation

/// **The session card, layout B v2** (Jan, 26 Sep 2026): the jibe story, resolved.
///
/// The card used to be the key-metrics block laid out as a grid of tiles. Layout B tells
/// the one story only this app can: a hero number (clean jibes by default), the jibe
/// outcome bar, a tack bar when the session had tacks, the best streak, and one ribbon of
/// rates in words plus max 2 s, duration and distance. Everything here is still the
/// block's own numbers — `make` reads `KeyMetrics`, and nothing on the card is computed
/// that the block does not carry. What this type adds is the *choice* (which number is the
/// hero) and the *words* (`PresentationCopy.card`).
///
/// The twin of `cardStory` in web/js/cardstats.js. Both are pinned against one fixture,
/// `fixtures/cards/stories.expected.json`, so a card made on the phone and a card made in
/// the browser say the same thing about the same session.
public extension ShareCardStats {

    /// Which number the card is headlined with. The rider's choice, per device
    /// (`ShareCardHeroStore`); clean jibes is the default.
    enum Hero: String, CaseIterable, Sendable, Identifiable, Codable {
        case clean
        case max2s
        case tacks

        public var id: String { rawValue }

        /// The composer's picker label.
        public var label: String {
            switch self {
            case .clean: PresentationCopy.card("optionClean")
            case .max2s: PresentationCopy.card("optionMax2s")
            case .tacks: PresentationCopy.card("optionTacks")
            }
        }
    }

    struct Story: Sendable, Equatable {

        /// The big number and its two words beside it.
        public struct HeroNumber: Sendable, Equatable {
            public let kind: Hero
            public let value: String
            public let unit: String
            public let sub: String
        }

        /// One outcome bar: the three ladder counts, and the caption on its right.
        public struct Bar: Sendable, Equatable {
            /// "jibes", "tacks", or "turns" on a session whose wind axis named no jibes.
            public let kind: String
            public let label: String
            public let flewThrough: Int
            public let touchdown: Int
            public let fellIn: Int
            /// nil where the hero already says it ("of 56 jibes" beside ★ 25).
            public let right: String?
            /// The caption ends in the clean star.
            public let star: Bool

            public var total: Int { flewThrough + touchdown + fellIn }
        }

        /// A run of text in one ink: "muted", "paper", "flew" or "fell".
        public struct Segment: Sendable, Equatable {
            public let text: String
            public let role: String

            public init(text: String, role: String) {
                self.text = text
                self.role = role
            }
        }

        /// One ribbon cell: the label above, the value under it.
        public struct Cell: Sendable, Equatable, Identifiable {
            public let key: String
            public let label: String
            public let value: String
            /// Drawn in the clean ink (clean jibes / h).
            public let clean: Bool
            public var id: String { key }
        }

        public let dateLine: String
        public let hero: HeroNumber?
        /// The heroes this session can carry, in picker order.
        public let heroOptions: [Hero]
        public let bars: [Bar]
        public let streak: [Segment]
        public let falls: [Segment]
        public let ribbon: [Cell]
        /// "speed estimated from GPS positions" on a positions-only recording, when a speed
        /// is on the card. Drawn next to the speed: under the hero when the hero is the speed,
        /// under the ribbon otherwise.
        public let speedNote: String?
        /// The three ladder words, in the bar legend's order.
        public let legend: [String]

        /// The flew / touchdown / fell words the legend prints, from the glossary.
        public static var legendWords: [String] {
            ["flewThrough", "touchdown", "fellIn"].map {
                PresentationCopy.text("glossary.\($0)", glossary: .lowercased) ?? ""
            }
        }

        /// The story, from the block. `hero` is the rider's choice; the card falls back
        /// when the session cannot carry it: clean jibes → best 2 s → tacks → none. With
        /// 0 clean jibes the clean number is left out everywhere (Jan, 26 Sep 2026) — no
        /// "★ 0", no "0 clean", no 0.0 clean jibes an hour.
        ///
        /// `maxSpeed` is nil when the speed record does not stand (Settings → Speed records
        /// under `onlyVerified` on a class-(c) recording), and then no speed is on the card.
        public static func make(metrics: KeyMetrics, maxSpeed: KeyMetrics.Metric?,
                                hero wanted: Hero, dateLine: String,
                                speedNote: String?) -> Story {
            let clean = metrics.cleanJibes.flatMap { Int($0.value) }.flatMap { $0 > 0 ? $0 : nil }
            let jibesCounted = metrics.cleanJibes != nil
            let speed = maxSpeed.flatMap { $0.value == "—" ? nil : $0 }
            let tacks = metrics.tacks

            var options: [Hero] = []
            if clean != nil { options.append(.clean) }
            if speed != nil { options.append(.max2s) }
            if tacks != nil { options.append(.tacks) }
            let kind: Hero? = options.contains(wanted) ? wanted : options.first

            let jibeTotal = metrics.tally?.total ?? 0
            let jibePhrase = PresentationCopy.card("jibeCount", count: jibeTotal,
                                                   ["jibes": String(jibeTotal)])
            let ofJibes = PresentationCopy.text("presentation.caption.ofJibes",
                                                args: ["jibes": String(jibeTotal),
                                                       "_count": String(jibeTotal)]) ?? ""

            var heroNumber: HeroNumber?
            switch kind {
            case .clean?:
                let n = clean ?? 0
                heroNumber = HeroNumber(kind: .clean, value: String(n),
                                        unit: PresentationCopy.card("heroClean", count: n),
                                        sub: ofJibes)
            case .max2s?:
                let (number, unit) = split(speed?.value ?? "—")
                heroNumber = HeroNumber(kind: .max2s, value: number, unit: unit,
                                        sub: PresentationCopy.card("heroMax2s"))
            case .tacks?:
                let t = tacks!
                let dry = String(t.flewThrough + t.touchdown)
                let sub = jibesCounted && jibeTotal > 0
                    ? PresentationCopy.card("heroTacksBeside", ["dry": dry, "jibes": jibePhrase])
                    : PresentationCopy.card("heroTacksDry", ["dry": dry])
                heroNumber = HeroNumber(kind: .tacks, value: String(t.total),
                                        unit: PresentationCopy.card("heroTacks", count: t.total),
                                        sub: sub)
            case nil:
                heroNumber = nil
            }

            var bars: [Bar] = []
            if let tally = metrics.tally {
                let right: String?
                var star = false
                if !jibesCounted {
                    right = tally.caption
                } else if kind == .clean {
                    right = nil
                } else if let clean {
                    right = ofJibes + " · " + PresentationCopy.card("barClean",
                                                                    ["clean": String(clean)])
                    star = true
                } else {
                    right = ofJibes
                }
                bars.append(Bar(kind: jibesCounted ? "jibes" : "turns",
                                label: PresentationCopy.card(jibesCounted ? "barJibes" : "barTurns"),
                                flewThrough: tally.flewThrough, touchdown: tally.touchdown,
                                fellIn: tally.fellIn, right: right, star: star))
            }
            if let tacks {
                bars.append(Bar(kind: "tacks", label: PresentationCopy.card("barTacks"),
                                flewThrough: tacks.flewThrough, touchdown: tacks.touchdown,
                                fellIn: tacks.fellIn,
                                right: kind == .tacks ? nil : tacks.caption, star: false))
            }

            var streak: [Segment] = []
            if let pair = metrics.streaks, !pair.parts.isEmpty {
                streak.append(Segment(text: PresentationCopy.card("streak") + " ", role: "muted"))
                for (i, part) in pair.parts.enumerated() {
                    if i > 0 { streak.append(Segment(text: " · ", role: "muted")) }
                    streak.append(Segment(text: part.value,
                                          role: part.colourRole == "outcome.flew" ? "flew" : "paper"))
                    streak.append(Segment(text: " " + part.label, role: "muted"))
                }
            }
            var falls: [Segment] = []
            if let count = metrics.falls.flatMap({ Int($0.value) }) {
                falls = fallSegments(count)
            }

            var ribbon: [Cell] = []
            let rates = Dictionary(metrics.rates.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            if clean != nil, let cph = rates["cph"] {
                ribbon.append(Cell(key: "cph", label: PresentationCopy.card("rateCph"),
                                   value: cph.value, clean: true))
            }
            if let tph = rates["tph"] {
                ribbon.append(Cell(key: "tph", label: PresentationCopy.card("rateTph"),
                                   value: tph.value, clean: false))
            } else if let jph = rates["jph"] {
                ribbon.append(Cell(key: "jph", label: PresentationCopy.card("rateJph"),
                                   value: jph.value, clean: false))
            }
            if let speed, kind != .max2s {
                ribbon.append(Cell(key: speed.key, label: speed.label, value: speed.value,
                                   clean: false))
            }
            for basic in metrics.basics where basic.key == "duration" || basic.key == "distance" {
                ribbon.append(Cell(key: basic.key, label: basic.label, value: basic.value,
                                   clean: false))
            }

            return Story(dateLine: dateLine, hero: heroNumber, heroOptions: options,
                         bars: bars, streak: streak, falls: falls, ribbon: ribbon,
                         speedNote: speed == nil ? nil : speedNote, legend: legendWords)
        }

        /// The card before the analysis has loaded: the three facts the index row carries
        /// that cannot disagree with the block, and no ladder at all.
        static func rowOnly(_ stats: [Stat], hero wanted: Hero, dateLine: String,
                            speedNote: String?) -> Story {
            let speed = stats.first { $0.key == Key.maxSpeed && $0.value != "—" }
            let options: [Hero] = speed == nil ? [] : [.max2s]
            let heroNumber = speed.map { stat -> HeroNumber in
                let (number, unit) = split(stat.value)
                return HeroNumber(kind: .max2s, value: number, unit: unit,
                                  sub: PresentationCopy.card("heroMax2s"))
            }
            let ribbon = stats.filter { $0.key == Key.duration || $0.key == Key.distance }
                .map { Cell(key: $0.key, label: $0.label, value: $0.value, clean: false) }
            return Story(dateLine: dateLine, hero: heroNumber, heroOptions: options, bars: [],
                         streak: [], falls: [], ribbon: ribbon,
                         speedNote: speed == nil ? nil : speedNote, legend: legendWords)
        }

        /// "fell in 25 times", with the number in the fell-in ink.
        static func fallSegments(_ count: Int) -> [Segment] {
            if count == 0 { return [Segment(text: PresentationCopy.card("fellInNone"), role: "muted")] }
            let template = PresentationCopy.card[ "fellIn" ]?.form(for: count) ?? ""
            let halves = template.components(separatedBy: "{falls}")
            guard halves.count == 2 else { return [Segment(text: template, role: "muted")] }
            return [Segment(text: halves[0], role: "muted"),
                    Segment(text: String(count), role: "fell"),
                    Segment(text: halves[1], role: "muted")].filter { !$0.text.isEmpty }
        }

        /// "13.21 kn" → ("13.21", "kn"): the hero draws the number big and the unit beside it.
        static func split(_ value: String) -> (String, String) {
            guard let space = value.lastIndex(of: " ") else { return (value, "") }
            return (String(value[..<space]), String(value[value.index(after: space)...]))
        }
    }

    /// "29 August 2026 · 14:40" — the date and the start time, on the session's own clock.
    static func startLine(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return dateLine(date, timeZone: timeZone) + " · " + formatter.string(from: date)
    }
}

/// The rider's hero choice, per device — the twin of `ShareCardPresetStore`. An unknown or
/// missing value is clean jibes, the default.
public enum ShareCardHeroStore {

    public static let defaultsKey = "shareCardHero.v1"

    public static func load(from defaults: UserDefaults) -> ShareCardStats.Hero {
        defaults.string(forKey: defaultsKey)
            .flatMap(ShareCardStats.Hero.init(rawValue:)) ?? .clean
    }

    public static func save(_ hero: ShareCardStats.Hero, to defaults: UserDefaults) {
        defaults.set(hero.rawValue, forKey: defaultsKey)
    }
}
