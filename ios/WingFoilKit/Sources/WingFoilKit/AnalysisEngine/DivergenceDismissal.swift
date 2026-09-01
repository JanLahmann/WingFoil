import Foundation

/// Which watch-vs-phone banners the rider has waved away, and when one comes back.
///
/// The banner (`DivergenceBanner`) is a provenance footnote, not an error: the phone's
/// recompute is authoritative and there is nothing for the rider to do about it. That makes
/// it exactly the sort of thing a rider wants gone — out of a screenshot, or just out of the
/// way — so it is dismissible, per session, for good.
///
/// "For good" has one exception, and it is the reason a dismissal is fingerprinted rather
/// than a plain "hide it on this session" flag: a session can be analyzed again — a new
/// engine, a re-import, a repaired file — and the banner that comes out of *that* run may be
/// saying something different. A dismissal therefore hides the divergence the rider actually
/// read; a divergence that is not the same one is a new statement and shows again.
///
/// The store is a UserDefaults string array used as a set (the same shape as
/// `healthExported` in `SessionStore`): a fingerprint is ~30 bytes and only sessions with a
/// divergence the rider bothered to dismiss ever get one.
public enum DivergenceDismissal {

    /// UserDefaults key for the dismissed fingerprints.
    public static let defaultsKey = "divergenceDismissed"

    /// How many dismissals are kept. Oldest fall off the front; a rider who scrolls back to
    /// a session past the cap sees the banner once more, which is the harmless failure.
    public static let cap = 200

    /// Session identity plus *what the banner says*, hashed to a short stable key.
    ///
    /// The metric names and both formatted values go in, sorted so that the order the checks
    /// happen to run in cannot change the key. The delta does not: it is derived from the
    /// two values already in the fingerprint.
    public static func fingerprint(sessionID: String, divergences: [Divergence]) -> String {
        let body = divergences
            .map { "\($0.metric)|\($0.watch)|\($0.phone)" }
            .sorted()
            .joined(separator: ";")
        return "\(sessionID):\(fnv1a(body))"
    }

    /// True when this exact divergence, on this session, has been dismissed.
    ///
    /// An empty divergence list is never "dismissed" — there is no banner to hide, and the
    /// caller should not be drawing one.
    public static func isDismissed(sessionID: String, divergences: [Divergence],
                                   dismissed: [String]) -> Bool {
        guard !divergences.isEmpty else { return false }
        return dismissed.contains(fingerprint(sessionID: sessionID, divergences: divergences))
    }

    /// The store with this banner dismissed. Any earlier fingerprint for the same session is
    /// dropped: a session only ever has one live divergence, so keeping the superseded ones
    /// would grow the list once per re-analysis and hide nothing.
    public static func dismissing(sessionID: String, divergences: [Divergence],
                                  in dismissed: [String]) -> [String] {
        guard !divergences.isEmpty else { return dismissed }
        let key = fingerprint(sessionID: sessionID, divergences: divergences)
        var out = dismissed.filter { !$0.hasPrefix("\(sessionID):") }
        out.append(key)
        if out.count > cap { out.removeFirst(out.count - cap) }
        return out
    }

    /// FNV-1a, spelled out rather than reached for: `Hasher` is seeded per process, so its
    /// values do not survive the app relaunch this dismissal is meant to outlive.
    private static func fnv1a(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(h, radix: 16)
    }
}
