import Foundation

/// `Int(someDouble)` **traps** when the Double is NaN, infinite, or past `Int`'s range, and a
/// trap is not catchable: the app dies where it stands, with no error the sync can report and
/// — because iOS files an out-of-range conversion as a `SIGTRAP` in a thread the rider never
/// started — often no crash report either.
///
/// Every Double that reaches one of those conversions in this kit came out of a **file**:
/// a float32 developer field written by another app, a timestamp from a download that was cut
/// off mid-stream, a duration divided by a span that turned out to be zero. So none of them
/// may use `Int(_:)` directly. `Int(clamped:)` is the one way in: NaN is 0 ("this said
/// nothing"), ±infinity and anything past the range saturate, and the caller keeps running.
///
/// It is deliberately not a general-purpose numeric shim — it exists for the importer's
/// boundary, where the alternative is a crash on a rider's phone.
extension Int {
    /// `Int(v.rounded())` that cannot trap. NaN → 0; out of range → `.min` / `.max`.
    public init(clamped v: Double) {
        guard !v.isNaN else { self = 0; return }
        let rounded = v.rounded()
        // 2^63 exactly; the first Double at or above it is out of Int's range.
        if rounded >= 9_223_372_036_854_775_808.0 { self = .max }
        else if rounded < -9_223_372_036_854_775_808.0 { self = .min }
        else { self = Int(rounded) }
    }
}

/// A ZIP entry's *declared* uncompressed size is a number in the archive's own directory —
/// written by whoever built the file, never checked against what is actually inside it.
///
/// Reserving that many bytes up front is an optimisation, so it must never be more than an
/// optimisation: `Int(_:)` of a UInt64 past `Int.max` traps, and a declaration of ten
/// gigabytes reserves ten gigabytes on a phone before a single byte has been inflated. The
/// buffer grows on its own as the entry is extracted, so a capped reservation costs one
/// reallocation on the only files where the cap bites.
enum ZipSizes {
    /// The largest reservation worth making up front. Bigger entries simply grow.
    static let maxReservationBytes = 64 * 1024 * 1024

    static func reservation(_ declared: UInt64) -> Int {
        Int(min(declared, UInt64(maxReservationBytes)))
    }
}
