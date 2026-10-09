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
    /// (`ShareCardHeroStore`); clean jibes is the default. `sessions` is the period card's
    /// alone — a session card never offers it, and a period card never offers `tacks`
    /// (a stored row has no tack ladder to sub-caption it with).
    enum Hero: String, CaseIterable, Sendable, Identifiable, Codable {
        case clean
        case max2s
        case tacks
        case sessions

        public var id: String { rawValue }

        /// The composer's picker label.
        public var label: String {
            switch self {
            case .clean: PresentationCopy.card("optionClean")
            case .max2s: PresentationCopy.card("optionMax2s")
            case .tacks: PresentationCopy.card("optionTacks")
            case .sessions: PresentationCopy.card("optionSessions")
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
            case .sessions?, nil:
                // `sessions` is never among a session's options.
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
            // A rate under the floor reads "—" and the block says "too short for a rate"
            // once under the row (`RateFloor`, `KeyMetrics.ratesNote`). A card has no room
            // for the sentence and "—" on a picture is a number with no answer, so the
            // ribbon simply goes without the rates. The bundled example is exempt.
            let rates = Dictionary((metrics.ratesNote == nil ? metrics.rates : [])
                                       .map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
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

        /// **What a period card draws for one turn kind** (GRDB v19) — its bar, the caption
        /// beside it and, beside the jibe's (whose hero is the clean count), a hero of its own.
        /// The twin of `PERIOD_KINDS` in web/js/cardstats.js. A kind the stored rows count but
        /// this table does not name draws nothing: the 360s, whose detector is off and
        /// unvalidated, get a row here — and words — only once they are counted.
        struct PeriodKind {
            let bar: String
            let label: String
            let caption: String
            let arg: String
            let hero: Hero?
        }

        static let periodKinds: [TurnKindTally.Kind: PeriodKind] = [
            .jibe: PeriodKind(bar: "jibes", label: "barJibes", caption: "ofJibes", arg: "jibes",
                              hero: nil),
            .tack: PeriodKind(bar: "tacks", label: "barTacks", caption: "ofTacks", arg: "tacks",
                              hero: .tacks),
        ]

        /// **The period card's story** (layout B v2 for a trip, a month, a season or a range):
        /// the twin of `periodCardStory` in web/js/cardstats.js.
        ///
        /// Every number is the period's own — its block (`Period.block`) or the story facts
        /// beside it (`Period.card`, `library.period_card`). Heroes: clean jibes → best 2 s →
        /// tacks → sessions. The bars are the session card's — the jibe bar, and the tack bar
        /// beside it where the period had a tack — from the per-kind ladders the rows carry
        /// (`card.kinds`); a period with no jibe draws the one turn bar, as a session does. A
        /// period one of whose rows carries no split keeps the old single bar: the jibe bar
        /// only when every counted turn was a jibe, the turn bar otherwise. With 0 clean jibes
        /// the clean number and clean jibes / h are left out, as on the session card.
        public static func make(period: Period, hero wanted: Hero) -> Story {
            let block = Dictionary(period.block.map { ($0.key, $0) },
                                   uniquingKeysWith: { a, _ in a })
            let card = period.card
            let clean = block[PeriodBlock.Key.cleanJibes].flatMap { Int($0.value) }
                .flatMap { $0 > 0 ? $0 : nil }
            let speed = block[PeriodBlock.Key.best2s]

            // The kinds this card draws a bar for: the named ones with a ladder and a turn in
            // it, and only where the jibe ladder has one — otherwise the turn bar below
            // already counts them.
            let jibeKind = card.kinds?.first { $0.kind == .jibe }
            let drawn: [TurnKindTally] = (jibeKind?.count ?? 0) > 0
                ? (card.kinds ?? []).filter {
                    periodKinds[$0.kind] != nil && $0.outcomes != nil && $0.count > 0
                }
                : []

            var options: [Hero] = []
            if clean != nil { options.append(.clean) }
            if speed != nil { options.append(.max2s) }
            for k in drawn { if let hero = periodKinds[k.kind]?.hero { options.append(hero) } }
            if period.sessions > 0 { options.append(.sessions) }
            let kind: Hero? = options.contains(wanted) ? wanted : options.first

            let jibes = card.jibes ?? 0
            let ofJibes = PresentationCopy.text("presentation.caption.ofJibes",
                                                args: ["jibes": String(jibes),
                                                       "_count": String(jibes)]) ?? ""
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
                if let t = drawn.first(where: { $0.kind == .tack }), let o = t.outcomes {
                    let dry = String(o.flewThrough + o.touchdown)
                    let j = jibeKind?.count ?? 0
                    let sub = j > 0
                        ? PresentationCopy.card("heroTacksBeside", [
                            "dry": dry,
                            "jibes": PresentationCopy.card("jibeCount", count: j,
                                                           ["jibes": String(j)]),
                        ])
                        : PresentationCopy.card("heroTacksDry", ["dry": dry])
                    heroNumber = HeroNumber(kind: .tacks, value: String(t.count),
                                            unit: PresentationCopy.card("heroTacks",
                                                                        count: t.count),
                                            sub: sub)
                }
            case .sessions?:
                let spots = block[PeriodBlock.Key.spots]?.value ?? "1"
                heroNumber = HeroNumber(
                    kind: .sessions, value: String(period.sessions),
                    unit: PresentationCopy.card("heroSessions", count: period.sessions),
                    sub: PresentationCopy.card("heroSessionsSpots", count: Int(spots),
                                               ["spots": spots]))
            case nil:
                heroNumber = nil
            }

            var bars: [Bar] = []
            if !drawn.isEmpty {
                for k in drawn {
                    guard let words = periodKinds[k.kind], let o = k.outcomes else { continue }
                    let mine = words.hero.map { kind == $0 } ?? (kind == .clean)
                    var right: String? = mine ? nil : PresentationCopy.text(
                        "presentation.caption.\(words.caption)",
                        args: [words.arg: String(k.count), "_count": String(k.count)])
                    var star = false
                    // The clean clause is the jibe's own count, over the jibes this bar draws.
                    if k.kind == .jibe, kind != .clean, let c = k.clean, c > 0 {
                        right = (right ?? "") + " · "
                            + PresentationCopy.card("barClean", ["clean": String(c)])
                        star = true
                    }
                    bars.append(Bar(kind: words.bar, label: PresentationCopy.card(words.label),
                                    flewThrough: o.flewThrough, touchdown: o.touchdown,
                                    fellIn: o.fellIn, right: right, star: star))
                }
            } else if let o = card.outcomes, o.total > 0 {
                let isJibes = card.kinds == nil && card.dryKind == "jibes"
                var right: String?
                var star = false
                if isJibes {
                    right = kind == .clean ? nil : ofJibes
                } else {
                    right = PresentationCopy.text("presentation.caption.ofTurns",
                                                  args: ["turns": String(o.total),
                                                         "_count": String(o.total)])
                }
                if kind != .clean, let clean {
                    right = (right ?? "") + " · "
                        + PresentationCopy.card("barClean", ["clean": String(clean)])
                    star = true
                }
                bars.append(Bar(kind: isJibes ? "jibes" : "turns",
                                label: PresentationCopy.card(isJibes ? "barJibes" : "barTurns"),
                                flewThrough: o.flewThrough, touchdown: o.touchdown,
                                fellIn: o.fellIn, right: right, star: star))
            }

            var streak: [Segment] = []
            let parts: [(Int, String, String)] = [
                card.flewStreak.map { ($0, "glossary.flewThrough", "flew") },
                card.dryStreak.map { ($0, "glossary.dry", "paper") },
            ].compactMap { $0 }
            if !parts.isEmpty {
                streak.append(Segment(text: PresentationCopy.card("streak") + " ", role: "muted"))
                for (i, part) in parts.enumerated() {
                    if i > 0 { streak.append(Segment(text: " · ", role: "muted")) }
                    streak.append(Segment(text: String(part.0), role: part.2))
                    streak.append(Segment(text: " " + (PresentationCopy.text(
                        part.1, glossary: .short) ?? ""), role: "muted"))
                }
            }
            let falls = card.falls.map(fallSegments) ?? []

            var ribbon: [Cell] = []
            if clean != nil, let cph = block[PeriodBlock.Key.cph] {
                ribbon.append(Cell(key: "cph", label: PresentationCopy.card("rateCph"),
                                   value: cph.value, clean: true))
            }
            if let rate = card.dryRate {
                let jibesOnly = card.dryKind == "jibes"
                ribbon.append(Cell(key: jibesOnly ? "jph" : "tph",
                                   label: PresentationCopy.card(jibesOnly ? "rateJph" : "rateTph"),
                                   value: rate, clean: false))
            }
            if kind != .sessions, let sessions = block[PeriodBlock.Key.sessions] {
                ribbon.append(Cell(key: sessions.key, label: sessions.label,
                                   value: sessions.value, clean: false))
            }
            if let hours = block[PeriodBlock.Key.hours] {
                ribbon.append(Cell(key: hours.key, label: PresentationCopy.card("ribbonHours"),
                                   value: hours.value, clean: false))
            }
            if let distance = block[PeriodBlock.Key.distance] {
                ribbon.append(Cell(key: distance.key, label: distance.label,
                                   value: distance.value, clean: false))
            }

            return Story(dateLine: period.dateLine, hero: heroNumber, heroOptions: options,
                         bars: bars, streak: streak, falls: falls, ribbon: ribbon,
                         speedNote: nil, legend: legendWords)
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

        /// "never fell in", and nothing for any other count.
        static func fallSegments(_ count: Int) -> [Segment] {
            // **The card never prints the falls** (UX review, 26 Sep 2026): the picture a
            // rider posts is the afternoon he is proud of, and "fell in 6 times" beside his
            // streak is the one line he would crop out. "never fell in" stays, because that
            // is a boast; any other count is on the session page, where it helps. Twin of
            // `fallSegments` in web/js/cardstats.js.
            count == 0 ? [Segment(text: PresentationCopy.card("fellInNone"), role: "muted")] : []
        }

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
