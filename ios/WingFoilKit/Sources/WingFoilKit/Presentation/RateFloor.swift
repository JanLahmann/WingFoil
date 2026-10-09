import Foundation

/// **A rate needs 20 minutes on the timer behind it** (Jan, 9 Oct 2026; rider review I12;
/// docs/algorithms/rates.md, "Too short for a rate").
///
/// A ten-minute paddle with five clean jibes read "28.1 clean jibes an hour" on the page,
/// the card and the Trends line — a number the afternoon never earned. Below the floor a
/// session shows "—" for every rate with the reason where the number goes, holds no point
/// on a rate trend and no rate record. The engine's own `summary.*PerHour` fields are left
/// as they are: the arithmetic is right, the rider-facing reading of it is what waits.
///
/// The clock is **timer time** (`summary.timerTimeS`, `SessionRow.timerSeconds`) — the
/// one every rate already divides by, so "20 minutes" means 20 minutes of the hour the
/// number is per. A period applies the same floor to its own Σ timer time: ten 10-minute
/// sessions are 100 minutes and hold a rate, one of them alone does not.
///
/// Twins: the lab's `presentation.RATE_MIN_TIMER_S` and the analyzer's
/// `library.RATE_MIN_TIMER_S`, asserted equal by `lab/tests/test_library.py`.
public enum RateFloor {
    /// 20 minutes, in seconds of timer time.
    public static let minTimerS: Double = 20 * 60

    /// Does this much timer time hold a rate? `>=`: exactly 20 minutes does.
    public static func holds(timerS: Double) -> Bool { timerS >= minTimerS }

    /// The rate, or nil when the clock behind it is under the floor.
    public static func gate(_ rate: Double?, timerS: Double) -> Double? {
        holds(timerS: timerS) ? rate : nil
    }
}
