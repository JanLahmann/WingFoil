import Foundation
import Testing
@testable import WingFoilKit

/// **A rate needs 20 minutes on the timer behind it** (Jan, 9 Oct 2026; rider review I12;
/// docs/algorithms/rates.md, "Too short for a rate").
///
/// The session page's cells are held by the presentation goldens (`PresentationTests`
/// against `fixtures/presentation/`, where the ten-minute Torbole paddle sits four ways).
/// This suite holds the library half: no rate point on a trend, no rate record, a period's
/// rate over its own Σ timer time — and the one dry-turn trend the range gets (I20).
@Suite struct RateFloorTests {

    static func row(_ id: String, timerS: Double, elapsedS: Double = 7200,
                    clean: Int = 5, tacks: Int = 0, day: Double = 0) -> SessionRow {
        var row = SessionRow(id: id, startDate: Date(timeIntervalSince1970: 1_785_000_000
                                                         + day * 86_400),
                             durationS: elapsedS, sourceClass: "a")
        row.rateDurationS = elapsedS
        row.timerTimeS = timerS
        row.jibes = 10
        row.tacks = tacks
        row.jibesSuccessful = clean
        row.engineCleanJibesPerHour = Double(clean) * 3600 / timerS
        row.engineJibesPerHour = 8 * 3600 / timerS
        row.engineTurnsPerHour = 9 * 3600 / timerS
        row.wetExits = 2
        row.turnsCounted = 10 + tacks
        row.turnsFlewThrough = 6
        row.turnsTouchdown = 2
        row.turnsFellIn = 2
        return row
    }

    @Test func theFloorIsTwentyMinutesAndInclusive() {
        #expect(RateFloor.minTimerS == 1200)
        #expect(RateFloor.holds(timerS: 1200))
        #expect(!RateFloor.holds(timerS: 1199.9))
        #expect(RateFloor.gate(4.2, timerS: 600) == nil)
        #expect(RateFloor.gate(4.2, timerS: 1200) == 4.2)
    }

    /// The floor reads **timer** time: two hours on the clock with ten minutes on the timer
    /// is a ten-minute rate, and it is gone. The count stays.
    @Test func aShortSessionHasNoRatePointAndKeepsItsCount() {
        let short = TrendPoint(Self.row("short", timerS: 600, elapsedS: 7200))
        #expect(short.cleanJibesPerHour == nil)
        #expect(short.jibesPerHour == nil)
        #expect(short.turnsPerHour == nil)
        #expect(short.cleanJibes == 5)
        let edge = TrendPoint(Self.row("edge", timerS: 1200))
        #expect(edge.cleanJibesPerHour == 15)
        #expect(edge.jibesPerHour == 24)
    }

    @Test func aShortSessionHoldsNoRateRecord() {
        let short = Self.row("short", timerS: 600)
        let long = Self.row("long", timerS: 3600, day: 1)
        #expect(SessionRecordKind.bestCph.value(in: short) == nil)
        #expect(SessionRecordKind.bestCph.value(in: long) == 5)
        #expect(SessionRecordKind.mostCleanJibes.value(in: short) == 5)
        let bests = PersonalBestDetector.cleanJibeBests([short, long])
        #expect(bests.first { $0.kind == .cleanJibesPerHour }?.sessionId == "long")
        #expect(SessionRecordKind.bestCph.caption
                    == "Clean jibes per hour on the timer. Sessions of at least 20 minutes.")
    }

    /// A period divides its Σ counts by its Σ timer time, and the floor is on that total:
    /// one ten-minute paddle has no rate, two of them have twenty minutes and do.
    @Test func aPeriodNeedsTwentyMinutesOnItsOwnTimer() {
        let one = LibraryStore.facts([Self.row("p1", timerS: 600)])
        #expect(one.cph == nil && one.wph == nil && one.cleanJibes == 5)
        #expect(LibraryStore.card([Self.row("p1", timerS: 600)]).dryRate == nil)
        let two = LibraryStore.facts([Self.row("p1", timerS: 600),
                                      Self.row("p2", timerS: 600, day: 1)])
        #expect(two.cph.map { ($0 * 10).rounded() / 10 } == 30)
        #expect(two.wph.map { ($0 * 10).rounded() / 10 } == 12)
    }

    /// I20: JPH while no session in the range has a tack, TPH once one does.
    @Test func oneDryTurnRateOverARange() {
        let jibesOnly = [TrendPoint(Self.row("a", timerS: 3600)),
                         TrendPoint(Self.row("b", timerS: 3600, day: 1))]
        #expect(TrendPoint.dryTurnRate(jibesOnly) == .jph)
        let tacked = jibesOnly + [TrendPoint(Self.row("c", timerS: 3600, tacks: 3, day: 2))]
        #expect(TrendPoint.dryTurnRate(tacked) == .tph)
        #expect(TrendPoint.dryTurnRate([]) == .jph)
    }
}
