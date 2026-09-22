import Foundation

/// The KEY METRICS block that opens the session analysis on the phone and on the web.
///
/// `docs/app-ui-review.md` §1.1 measured the defect this closes: on a 6.9″ phone the first
/// actual result sat one and a third screens below the fold, under a map, ten legend chips
/// and three paragraphs of legend documentation. The rider finishes a session and wants
/// four things — how long was I out, how fast, how did the jibes go, how busy was it — and
/// every one of them was already in the analysis document.
///
/// Four rows, in this order, numbers big and labels small (the watch's established taste):
///
/// 1. `basics` — duration (`10:45 min` / `1:57 h`), distance, average speed.
/// 2. `maxSpeed` — the best 2 s record, labelled with the window it is, never "top speed".
/// 3. `tally` + `tacks` + `falls` + `streaks` — the outcome ladder's own three counts for
///    the jibes and, since 22 September 2026, the same three for the **tacks** where the
///    session had any; then every fall of the afternoon and the two streaks §5.1 flagged
///    as computed-and-never-shown on either platform. The jibe tally's caption carries the
///    **clean jibe** count as well as the total, so the one number a rider quotes about his
///    turns is in the block rather than three screens down.
/// 4. `rates` — the per-hour rates (`docs/algorithms/rates.md` "Session rates"); JPH counts
///    **dry** jibes since 0.7.0 and CPH the **clean** ones since 0.10.0, and both labels
///    say which set they count.
///
/// Everything resolves to a display string here so both platforms format one way and so
/// the *content* is testable without a renderer — the same arrangement `ShareCardStats`
/// uses, and for the same reason: a block that prints "0.0 JPH" where it means "there is
/// no hour to divide by" is a mistake no screenshot shows.
///
/// Mirrored in `web/js/render.js` (`keyMetrics`). A difference between the two is a bug.
public struct KeyMetrics: Sendable, Equatable {

    /// One number with the label that sits under it.
    public struct Metric: Sendable, Equatable, Identifiable {
        public let key: String
        public let label: String
        public let value: String
        /// The small line under the value, where the cell has something to qualify — the
        /// falls cell's split, and nothing else today. `Tally` has always had one; this is
        /// the same affordance for a plain cell, so a number that needs a qualifier does
        /// not have to become a tally to get one.
        public let caption: String?

        public var id: String { key }

        public init(key: String, label: String, value: String, caption: String? = nil) {
            self.key = key
            self.label = label
            self.value = value
            self.caption = caption
        }
    }

    /// The outcome tally, drawn on the ladder's own inks (green · orange · red) by the
    /// view. The counts stay numbers rather than a joined string precisely because the
    /// colour is the point — `docs/presentation/layers-map-colour-type.md`, "the outcome ladder is a verdict
    /// scale and nothing else may borrow it".
    ///
    /// Two of them since 22 September 2026: the jibe ladder, and the **tack** ladder
    /// beside it on the sessions where the rider tacked. One shape, one set of inks, two
    /// sets of turns — the captions say which is which.
    public struct Tally: Sendable, Equatable {
        public let flewThrough: Int
        public let touchdown: Int
        public let fellIn: Int
        /// What the three numbers are out of, and how many of them were **clean** —
        /// "of 50 jibes · 12 clean", or "of 51 turns · 12 clean" on a session whose wind
        /// axis never resolved and which therefore has no jibes.
        ///
        /// A *clean jibe* is a counted jibe flown all the way through with the speed
        /// carried — the engine's per-turn `clean` flag: `success` (`docs/algorithms.md`,
        /// `turnSuccessPct`) **and** `flew_through` (engine 0.12.0). It is a stricter
        /// verdict than the ladder's green and deliberately a different number: the three
        /// counts say how each turn ended, the clean count says how many of the ones that
        /// flew the rider actually rode. Clean can therefore never exceed `flewThrough`.
        public let caption: String
        /// **What the three inks are called** — "flew · touchdown · fell", the cell's own
        /// `labelId` resolved. It rides on the tally rather than being typed by each of the
        /// two surfaces that draw one: the block's view and the share card both printed
        /// that literal, which is one label with two homes.
        public let label: String

        public var total: Int { flewThrough + touchdown + fellIn }

        public init(flewThrough: Int, touchdown: Int, fellIn: Int, caption: String,
                    label: String = PresentationCopy.label["outcomeLadder"] ?? "") {
            self.flewThrough = flewThrough
            self.touchdown = touchdown
            self.fellIn = fellIn
            self.caption = caption
            self.label = label
        }
    }

    /// Duration · distance · average speed. Always three.
    public let basics: [Metric]
    /// The best 2 s record — the session's fastest *measured* window, not a peak sample.
    public let maxSpeed: Metric
    /// The two composites beside it on row 2 (Jan, 6 Sep 2026 — "the second row is a bit
    /// empty"): **5×10 s** and **alpha 500**, each "—" when the session did not produce
    /// one. Always two, so the row keeps its shape. They are **block-only**: the share card
    /// does not carry them (`ShareCardStats` reads `maxSpeed`, never this), because the
    /// card's rule is one speed, the one a rider quotes, and the Records page owns the set.
    public let speedExtras: [Metric]
    /// nil when no turn was counted: a tally of three zeros is not a verdict.
    public let tally: Tally?
    /// **The tacks, on the same ladder** (22 September 2026). The engine has typed both
    /// kinds of turn since 0.3.0 and this block only ever drew the jibes, so a rider who
    /// tacks read an afternoon with a quarter of its maneuvers missing from the one place
    /// that summarises it.
    ///
    /// Its caption carries no *clean* count: clean is a jibe word in this product and a
    /// tack has no clean reading to carry (`TurnSummary.tacksSuccessful`, and the Tacks
    /// card on the Turns tab, which dropped its fourth number for the same reason).
    ///
    /// nil on a session with no tack in it — and nil when the tally above it has fallen
    /// back to *every counted turn*, because the tacks are already inside those three
    /// numbers and a block that printed them twice would be answering one question with
    /// two cells (docs/review-checklist.md, pattern F).
    public let tacks: Tally?
    /// "5 flew · 11 dry", nil with no counted turns. Flying leads: it is the harder of
    /// the two runs and the one the rider is chasing, and `longestFlewStreak` is always
    /// the smaller number, so the pair reads strict-then-lenient in both halves.
    public let streaks: Metric?
    /// **Every fall of the session**, with the split in its caption. nil where no flight
    /// ended at all, which is the only state that is an absence rather than a zero.
    ///
    /// The tally three cells up is the *jibe* ladder and says so in its own caption ("of
    /// 57 jibes"), so its `fell in` count leaves out every swim that happened in a
    /// straight line. A tester fell three times on 19 September 2026, read the tally, and
    /// concluded the app had not noticed (docs/algorithms/rates.md, "Wet is every fall, not
    /// every fallen jibe"). This is the session's own number, from the flight-end channel
    /// WPH already divides — one event per actual swim, and the two halves of the caption
    /// add up to it exactly because they come from the same channel.
    public let falls: Metric?
    /// JPH + CPH (or TPH alone) and WPH. **Empty** when `durationS <= 0` — the engine reports the
    /// rates as null there, and "no hour to divide by" is an absence, not a 0.0.
    public let rates: [Metric]

    public init(basics: [Metric], maxSpeed: Metric, speedExtras: [Metric] = [],
                tally: Tally?, tacks: Tally? = nil, streaks: Metric?,
                falls: Metric? = nil, rates: [Metric]) {
        self.basics = basics
        self.maxSpeed = maxSpeed
        self.speedExtras = speedExtras
        self.tally = tally
        self.tacks = tacks
        self.streaks = streaks
        self.falls = falls
        self.rates = rates
    }

    // MARK: - Building

    /// **The block, rendered out of the presentation document** (ADR-033, round 2).
    ///
    /// Every gate that used to live here — the jibe tally's fallback to the counted-turn
    /// ladder, the tack cell's two conditions, the falls cell's absence where no flight
    /// ended, the rate row's `turns.jibes` test and its JPH→TPH degradation — is in
    /// `PresentationDocument.blockSection` now, once, beside the lab's twin of it. What is
    /// left here is formatting and the words: three decisions this file is entitled to make
    /// and the document is not (`docs/presentation/document.md`, "What stays with the
    /// renderer").
    ///
    /// The convenience overload is kept because a caller with an analysis in hand should not
    /// have to build a document to draw a block, and because it is what makes this a
    /// refactor: the same summary and the same records still produce the same strings.
    public static func make(summary: SessionSummary, records: GP3SRecords) -> KeyMetrics {
        make(block: PresentationDocument.blockSection(summary, records))
    }

    /// The `block` section of a presentation document as the strings the phone draws.
    ///
    /// A row the document left out is a row with nothing in it — which is how row 4
    /// disappears on a recording with no hour to divide by — so every lookup here is by
    /// **key** rather than by position, and an absent cell is an absent `Metric`.
    public static func make(block: PresentationValue) -> KeyMetrics {
        var cells: [String: PresentationValue] = [:]
        var order: [String] = []
        for row in block["rows"]?.arrayValue ?? [] {
            for cell in row["cells"]?.arrayValue ?? [] {
                guard let key = cell["key"]?.stringValue else { continue }
                cells[key] = cell
                order.append(key)
            }
        }
        func metric(_ key: String) -> Metric? { cells[key].map(Self.metric) }

        return KeyMetrics(
            basics: ["duration", "distance", "avgSpeed"].compactMap(metric),
            // Labelled with the window it actually is. The record set's own contract
            // (docs/presentation/records.md, "Record windows") is that a chip names the
            // window it is highlighting; "max speed" over a 2 s peak would be the same
            // overclaim.
            maxSpeed: metric("max2s") ?? Metric(key: "max2s", label: "", value: "—"),
            speedExtras: ["best5x10s", "alpha500"].compactMap(metric),
            tally: cells["tally"].map(Self.tally),
            tacks: cells["tacks"].map(Self.tally),
            streaks: metric("streaks"),
            falls: metric("falls"),
            // In the document's order, so a rate added to the row lands here with no edit.
            rates: order.filter { ["jph", "cph", "tph", "wph"].contains($0) }
                .compactMap(metric))
    }

    // MARK: - One cell

    /// One document cell as a number, a word and the line under it.
    ///
    /// The three things a renderer decides are all here. **The unit** — `Speed` reads
    /// Settings → Units, which is exactly why the document carries a raw knot and a
    /// `unitKind` instead of a string. **The form of the word** — the rate row wants the
    /// glossary's `labelled` ("JPH · dry jibes per hour"), the falls cell its `term`
    /// lowercased, because a capital under a number reads as a title. **The pair**, where a
    /// cell carries two different metrics rather than one: "1 flew · 4 dry" is the only one
    /// today and each half takes the glossary's watch-width `short`.
    static func metric(_ cell: PresentationValue) -> Metric {
        let key = cell["key"]?.stringValue ?? ""
        let labelID = cell["labelId"]?.stringValue ?? ""
        let caption = (cell["captions"]?.arrayValue ?? []).first
            .flatMap(PresentationCopy.captionText)
        return Metric(key: key,
                      label: PresentationCopy.text(labelID, glossary: glossaryForm(key)) ?? "",
                      value: value(cell),
                      caption: caption)
    }

    /// Which spelling of a glossary word this cell's label wants. Only two cells name one:
    /// the rates, which want the expansion under them, and the falls cell, which does not.
    static func glossaryForm(_ key: String) -> PresentationCopy.GlossaryForm {
        ["jph", "cph", "tph", "wph"].contains(key) ? .labelled : .lowercased
    }

    /// A cell's value, formatted. A cell with `counts` is the pair, joined; otherwise it is
    /// one scalar in the unit its `unitKind` names, and `null` is the em dash — an absent
    /// answer, never a zero (`docs/presentation/labels.md`, "Formatter rules").
    static func value(_ cell: PresentationValue) -> String {
        if let counts = cell["counts"]?.arrayValue, !counts.isEmpty {
            return counts.map { part in
                let label = part["labelId"]?.stringValue ?? ""
                return PresentationCopy.plain(part["value"] ?? .null) + " "
                    + (PresentationCopy.text(label, glossary: .short) ?? "")
            }.joined(separator: " · ")
        }
        return format(cell["value"] ?? .null,
                      unitKind: cell["unitKind"]?.stringValue ?? "none")
    }

    /// The document's raw value in the unit the rider reads. The one place a `unitKind`
    /// becomes a string on this surface.
    static func format(_ value: PresentationValue, unitKind: String) -> String {
        var scalar: Double?
        switch value {
        case .int(let v): scalar = Double(v)
        case .number(let v): scalar = v
        default: scalar = nil
        }
        switch unitKind {
        case "durationS": return duration(scalar ?? 0)
        case "distanceKm": return scalar.map(km) ?? "—"
        case "speedKn": return knots(scalar)
        case "rate": return scalar.map(rate) ?? "—"
        case "percent": return scalar.map { String(format: "%.1f %%", $0) } ?? "—"
        default: return scalar.map { String(Int($0)) } ?? "—"
        }
    }

    /// An outcome-ladder cell as the three counts, its label and the caption that says what
    /// they are out of. The ladder's own `tally` field is why the counts stay numbers: the
    /// colour is the point (`docs/presentation/layers-map-colour-type.md`).
    static func tally(_ cell: PresentationValue) -> Tally {
        let counts = cell["tally"]
        func count(_ key: String) -> Int {
            if case .int(let v)? = counts?[key] { return v }
            return 0
        }
        return Tally(flewThrough: count("flewThrough"),
                     touchdown: count("touchdown"),
                     fellIn: count("fellIn"),
                     caption: (cell["captions"]?.arrayValue ?? []).first
                        .flatMap(PresentationCopy.captionText) ?? "",
                     label: PresentationCopy.text(cell["labelId"]?.stringValue ?? "") ?? "")
    }

    // MARK: - Formatting
    //
    // Local and POSIX-stable, like `ShareCardStats`: the same strings have to come out of
    // the Swift and the JavaScript halves of this block, and a locale's decimal comma
    // would silently split them.

    static func rate(_ value: Double) -> String { String(format: "%.1f", value) }

    /// How long the session was: `1:57 h` past an hour, `10:45 min` under one.
    ///
    /// **Why the short form exists.** This was `h:mm` at every length, so a ten minute
    /// forty-five second session printed **`0:11`** — the two most interesting digits
    /// rounded away, and a leading zero where the number should be. That is survivable on
    /// a page the rider can scroll past; it is not survivable on the share card, which is
    /// a PNG in somebody else's chat thread with no re-render and nothing beside it to
    /// check against. A short session is exactly the kind a rider shares ("first
    /// flight!"), and `0:11` is the one string that makes it look like nothing happened.
    ///
    /// **Why the unit rides inside the value.** Every other cell in this block carries its
    /// own unit in the big type — `2.6 km`, `13.47 kn` — so a duration doing the same is
    /// the block's own habit rather than a special case. It also settles the ambiguity the
    /// bare digits create: `10:45` under the word "duration" reads as ten and three
    /// quarter *hours* just as easily as it reads as ten and three quarter minutes, and at
    /// cell size, on a card, with no second number to calibrate against, there is nothing
    /// to resolve it. `10:45 min` cannot be misread, and needs no caption to say so —
    /// which matters, because the card's caption slot is a layout affordance the tally
    /// already owns.
    ///
    /// Both forms keep `m:ss`/`h:mm` colon arithmetic rather than "10 m 45 s": the colon
    /// is what a clock looks like, it stays narrow at 75 px type, and it is the shape the
    /// flight table and the replay caption already print (`FlightPairing.clock`).
    ///
    /// Rounded to the nearest minute above the hour and to the nearest second below it —
    /// never truncated, in both cases for the same reason: `0:00` over a recording that
    /// exists reads as a failure to measure. Twin of `hm` in web/js/cardstats.js.
    /// **Public**, because it is the platform's one session-duration formatter and the app
    /// target prints session durations too — the library row, the Distance card's caption,
    /// the "Longest session" record. They read `Fmt.duration` (`1 h 24 m`) and the block
    /// read this, so the same afternoon came out in two spellings a tap apart
    /// (docs/presentation/one-clock.md, "One clock"). `Fmt.duration` stays for a *clip* or a
    /// *flight* clock, which is minutes and seconds by design.
    public static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            let minutes = Int((Double(total) / 60).rounded())
            return String(format: "%d:%02d h", minutes / 60, minutes % 60)
        }
        return String(format: "%d:%02d min", total / 60, total % 60)
    }

    static func km(_ value: Double) -> String { String(format: "%.1f km", value) }

    /// **Every speed on the phone comes out of here**, and `Speed` is what decides the
    /// unit (Settings → Units, 20 September 2026). The name stays `knots` because the
    /// *argument* is knots — the engine reports knots and always will — and the return is
    /// whatever the rider reads in.
    public static func knots(_ value: Double?) -> String { Speed.format(value) }

    /// The rider's unit is knots everywhere in both apps (records, chart axis, callouts),
    /// so the one summary number the engine reports in km/h is converted rather than
    /// printed beside a column of knots.
    static func knFromKmh(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return value / 1.852
    }
}
