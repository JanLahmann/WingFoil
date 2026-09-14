import Foundation
import Testing
@testable import WingFoilKit

/// The Sessions tab's two controls — group by, and the filter that narrows the list.
///
/// Everything here is a pure rule over `SessionRow`s built in memory: no database, no
/// fixture. What is being pinned is the part a rider would notice going wrong — the order
/// the headings come in, the bucket a spotless session falls in, the fact that a session
/// which arrived twice answers to both its doors, and that "12 July to 3 August" includes
/// the third of August.
@Suite struct LibraryListingTests {

    /// A UTC calendar, so a test that asserts "August" is not asserting the machine's zone.
    /// Every row below records its own offset too, which is what the grouping actually
    /// reads (`SessionRow.displayZone`).
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func row(_ id: String, _ date: Date, spot: String? = nil,
                    source: String? = "file", offsetS: Int = 0,
                    discipline: Discipline? = nil) -> SessionRow {
        var row = SessionRow(id: id, startDate: date, durationS: 3600, sourceClass: "b")
        row.startUtcOffsetS = offsetS
        row.spotId = spot
        row.importSource = source
        row.disciplineOverride = discipline?.rawValue
        return row
    }

    func names(_ id: String?) -> String? {
        switch id {
        case "garda": "Nago-Torbole"
        case "rhein": "Rhein"
        default: nil
        }
    }

    // MARK: - Grouping

    /// Newest month first, newest session first inside it, and the header says how many.
    @Test func monthsRunNewestFirstAndSaySoInTheHeading() {
        let rows = [
            row("aug-late", day(2026, 8, 30)),
            row("jul", day(2026, 7, 4)),
            row("aug-early", day(2026, 8, 2)),
            row("sep", day(2026, 9, 1)),
        ]
        let groups = LibraryGrouping.month.groups(rows, spotName: names, calendar: utc)
        #expect(groups.map(\.key) == ["2026-09", "2026-08", "2026-07"])
        #expect(groups.map(\.title) == ["September 2026 · 1 session",
                                        "August 2026 · 2 sessions",
                                        "July 2026 · 1 session"])
        // …and inside the month, newest first, like the flat list it came from.
        #expect(groups[1].rows.map(\.id) == ["aug-late", "aug-early"])
    }

    /// A year is a heading and a count, and nothing else; a December session and a January
    /// one are two years even a fortnight apart.
    @Test func yearsRunNewestFirst() {
        let rows = [row("a", day(2025, 12, 28)), row("b", day(2026, 1, 3)),
                    row("c", day(2025, 2, 1))]
        let groups = LibraryGrouping.year.groups(rows, spotName: names, calendar: utc)
        #expect(groups.map(\.title) == ["2026 · 1 session", "2025 · 2 sessions"])
    }

    /// **A session belongs to the month the rider had.** 00:30 local on 1 August, recorded
    /// two hours east of UTC, is an August session and not a July one — the row's own zone
    /// decides, never the reader's.
    @Test func theMonthIsTheSessionsOwnMonth() {
        let midnight = utc.date(from: DateComponents(year: 2026, month: 7, day: 31,
                                                          hour: 22, minute: 30))!
        let rows = [row("late", midnight, offsetS: 2 * 3600)]
        let groups = LibraryGrouping.month.groups(rows, spotName: names, calendar: utc)
        #expect(groups.first?.heading == "August 2026")
    }

    /// Spots are ordered by their newest session, and **"No spot" is last** whatever its
    /// dates say: it is not a place, so it has no place in the sequence.
    @Test func noSpotIsTheLastGroup() {
        let rows = [
            row("newest", day(2026, 8, 30), spot: nil),
            row("garda-1", day(2026, 8, 10), spot: "garda"),
            row("rhein-1", day(2026, 8, 20), spot: "rhein"),
            row("garda-2", day(2026, 8, 9), spot: "garda"),
            // A spot the table can no longer name reads as no spot, which is what it is as
            // far as a heading is concerned.
            row("orphan", day(2026, 8, 25), spot: "deleted"),
        ]
        let groups = LibraryGrouping.spot.groups(rows, spotName: names, calendar: utc)
        #expect(groups.map(\.heading) == ["Rhein", "Nago-Torbole", "No spot"])
        #expect(groups.map(\.title).last == "No spot · 2 sessions")
        #expect(groups.last?.rows.map(\.id) == ["newest", "orphan"])
    }

    /// `.none` is one section with no heading at all — the flat list the library has always
    /// been, ordered newest first. Its segment is labelled **"All"** while its raw value
    /// stays `none`, which is what the stored preference and `UI_GROUP_BY` already hold.
    @Test func noneIsOneHeadlessSection() {
        #expect(LibraryGrouping.none.title == "All")
        #expect(LibraryGrouping.none.rawValue == "none")
        #expect(LibraryGrouping.allCases.map(\.title) == ["All", "Month", "Year", "Spot"])
        let rows = [row("b", day(2026, 7, 4)), row("a", day(2026, 8, 2))]
        let groups = LibraryGrouping.none.groups(rows, spotName: names, calendar: utc)
        #expect(groups.count == 1)
        #expect(groups[0].heading.isEmpty)
        #expect(groups[0].title.isEmpty)
        #expect(groups[0].rows.map(\.id) == ["a", "b"])
        #expect(LibraryGrouping.month.groups([], spotName: names, calendar: utc).isEmpty)
        #expect(LibraryGrouping.none.groups([], spotName: names, calendar: utc).isEmpty)
    }

    /// **Month from twenty up, none below.** The rule the first launch after this feature
    /// lands is decided by.
    @Test func groupingDefaultsToMonthOnlyOnceTheLibraryIsWorthIt() {
        #expect(LibraryGrouping.default(librarySize: 0) == LibraryGrouping.none)
        #expect(LibraryGrouping.default(librarySize: 19) == LibraryGrouping.none)
        #expect(LibraryGrouping.default(librarySize: 20) == .month)
        #expect(LibraryGrouping.default(librarySize: 400) == .month)
        #expect(LibraryGrouping.monthByDefaultFrom == 20)
    }

    // MARK: - The filter

    /// `importSource` is a `+`-joined **set**, so a session that arrived twice answers to
    /// both its doors — and to no third one. Emphatically not a substring test: `watch`
    /// must not match `applewatch`.
    @Test func aSourceFilterIsContainmentNotEquality() {
        let both = row("both", day(2026, 8, 1), source: "file+icu")
        #expect(LibraryListFilter(source: .icu).matches(both, calendar: utc))
        #expect(LibraryListFilter(source: .file).matches(both, calendar: utc))
        #expect(!LibraryListFilter(source: .strava).matches(both, calendar: utc))

        let apple = row("apple", day(2026, 8, 1), source: "applewatch")
        #expect(LibraryListFilter(source: .appleWatch).matches(apple, calendar: utc))
        #expect(!LibraryListFilter(source: .watch).matches(apple, calendar: utc))

        // A row that never recorded a door matches no door.
        let none = row("none", day(2026, 8, 1), source: nil)
        #expect(!LibraryListFilter(source: .file).matches(none, calendar: utc))
        #expect(LibraryListFilter().matches(none, calendar: utc))
    }

    /// **Both dates count**, and only the day of each end is read — the time a `DatePicker`
    /// happens to carry never decides whether an afternoon is in the range.
    @Test func aDateRangeIncludesBothItsEndDays() {
        let from = utc.date(from: DateComponents(year: 2026, month: 7, day: 12,
                                                      hour: 23, minute: 59))!
        let to = utc.date(from: DateComponents(year: 2026, month: 8, day: 3,
                                                    hour: 0, minute: 1))!
        let filter = LibraryListFilter(dateRange: from...to)
        let inside = [day(2026, 7, 12, hour: 6), day(2026, 7, 20),
                      day(2026, 8, 3, hour: 21)]
        for date in inside {
            #expect(filter.matches(row("x", date), calendar: utc))
        }
        #expect(!filter.matches(row("before", day(2026, 7, 11, hour: 23)),
                                calendar: utc))
        #expect(!filter.matches(row("after", day(2026, 8, 4, hour: 0)),
                                calendar: utc))
    }

    /// Spot and discipline, and the fact that the four clauses are ANDed.
    @Test func theClausesCompose() {
        let rows = [
            row("a", day(2026, 8, 1), spot: "garda", source: "icu"),
            row("b", day(2026, 8, 2), spot: "garda", source: "strava",
                     discipline: .windsurfFin),
            row("c", day(2026, 8, 3), spot: "rhein", source: "icu"),
        ]
        #expect(LibraryListFilter(spotId: "garda").apply(to: rows, calendar: utc)
                    .map(\.id) == ["a", "b"])
        #expect(LibraryListFilter(discipline: .windsurfFin)
                    .apply(to: rows, calendar: utc).map(\.id) == ["b"])
        // An unstamped row is a wingfoil row (`analysisDiscipline`), not a row with no answer.
        #expect(LibraryListFilter(discipline: .wingfoil)
                    .apply(to: rows, calendar: utc).map(\.id) == ["a", "c"])
        #expect(LibraryListFilter(spotId: "garda", source: .icu)
                    .apply(to: rows, calendar: utc).map(\.id) == ["a"])
        #expect(LibraryListFilter(spotId: "garda", source: .icu, discipline: .windsurfFin)
                    .apply(to: rows, calendar: utc).isEmpty)
        // An empty filter is the whole library, untouched and in its own order.
        #expect(!LibraryListFilter().isActive)
        #expect(LibraryListFilter().apply(to: rows, calendar: utc).map(\.id)
                == ["a", "b", "c"])
    }

    /// One chip per active narrowing, in menu order, each clearable on its own.
    @Test func chipsNameEachNarrowingAndClearIt() {
        var filter = LibraryListFilter(
            spotId: "garda", source: .strava, discipline: nil,
            dateRange: day(2026, 7, 12)...day(2026, 8, 3))
        let chips = filter.chips(spotName: { names($0) }, calendar: utc)
        #expect(chips.map(\.label) == ["Nago-Torbole", "Strava", "12 Jul – 3 Aug"])
        #expect(chips.map(\.field) == [.spot, .source, .dateRange])

        filter.clear(.source)
        #expect(filter.source == nil)
        #expect(filter.isActive)
        for field in LibraryFilterField.allCases { filter.clear(field) }
        #expect(!filter.isActive)
        #expect(filter.chips(spotName: { names($0) }, calendar: utc).isEmpty)
    }

    /// A whole calendar year is chipped as the year — there is no second way to have picked
    /// 1 January to 31 December.
    @Test func aWholeYearIsChippedAsTheYear() {
        let year = LibraryDateWindow.year(2025, calendar: utc)!
        let filter = LibraryListFilter(dateRange: year)
        #expect(filter.chips(spotName: { _ in nil }, calendar: utc).first?.label == "2025")
        // …and the menu ticks the row it came from.
        let now = day(2026, 8, 1)
        #expect(LibraryDateWindow.window(for: year, now: now, calendar: utc) == .lastYear)
        #expect(LibraryDateWindow.window(for: LibraryDateWindow.year(2026, calendar: utc),
                                         now: now, calendar: utc) == .thisYear)
        #expect(LibraryDateWindow.window(for: nil, now: now, calendar: utc) == .allTime)
        #expect(LibraryDateWindow.window(for: day(2026, 7, 12)...day(2026, 8, 3),
                                         now: now, calendar: utc) == .custom)
        // A year filter keeps that year's afternoons and no neighbour's.
        #expect(filter.matches(row("in", day(2025, 12, 31, hour: 22)),
                               calendar: utc))
        #expect(!filter.matches(row("out", day(2026, 1, 1, hour: 1)),
                                calendar: utc))
    }

    /// The doors in the rider's words, and the two demo ones that stay out of the menu
    /// unless the library actually holds such a row.
    @Test func everySourceHasARiderFacingLabel() {
        #expect(ImportSource.icu.libraryFilterLabel == "intervals.icu")
        #expect(ImportSource.watch.libraryFilterLabel == "Garmin watch")
        #expect(ImportSource.appleWatch.libraryFilterLabel == "Apple Watch")
        #expect(ImportSource.gdpr.libraryFilterLabel == "Garmin export")
        #expect(ImportSource.fixtures.libraryFilterLabel == "Example")
        #expect(ImportSource.example.libraryFilterLabel == "Example")
        for source in ImportSource.allCases {
            #expect(!source.libraryFilterLabel.isEmpty)
            #expect(!source.libraryFilterLabel.contains("—"))
        }
        #expect(ImportSource.allCases.filter { !$0.isOfferedUnconditionally }
                == [.fixtures, .example])
    }
}
