import Foundation

/// The Takeoffs tab's own filter — the counterpart of `TurnFilter` on the Turns tab.
///
/// It lives in the kit for the reason `TurnFilter` does: the wording is the feature. "Free"
/// is not a fourth outcome beside success and failure, it is the *subset of the successes
/// that needed no pumping*, and a chip row that filed the three side by side would be
/// claiming a rider who got up on wind alone did not get up. Same shape as clean ⊂ flew
/// through on the Turns tab, and said here where a test can hold it.
///
/// **This is a data filter and not a map layer.** It chooses which attempts the page is
/// about — the pins, the list and the count in the caption move together. What is *drawn*
/// about those attempts is the legend's question (`MapLayerScope.takeoffs`: the takeoff
/// glyphs, the pumping spans, the splashes, the chevrons), and the two controls must never
/// be merged: hiding the takeoff layer is "I am looking at the water", filtering to failures
/// is "I am looking at what went wrong".
public enum TakeoffAttemptKind: String, CaseIterable, Sendable, Equatable, Codable {
    /// A flight, worked for.
    case pumped
    /// A flight, under `freeTakeoff` strokes: the wind did it.
    case free
    /// A real burst that produced no flight.
    case failed

    /// Whether the attempt ended up on the foil. `free` is a success; that is the entire
    /// point of the word.
    public var gotUp: Bool { self != .failed }

    /// The word the row and the chip print.
    public var label: String {
        switch self {
        case .pumped: return "pumped up"
        case .free: return "free"
        case .failed: return "failed"
        }
    }
}

public enum TakeoffOutcomeFilter: String, CaseIterable, Sendable, Identifiable, Codable {
    case all
    case success
    case failed
    case free

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "All"
        case .success: return "Success"
        case .failed: return "Failed"
        case .free: return "Free"
        }
    }

    /// `success` keeps every attempt that got up, **free ones included** — free is a
    /// narrowing of success, not a rival to it, so the chips are `all ⊇ success ⊇ free` with
    /// `failed` as the complement of success.
    public func accepts(_ kind: TakeoffAttemptKind) -> Bool {
        switch self {
        case .all: return true
        case .success: return kind.gotUp
        case .failed: return kind == .failed
        case .free: return kind == .free
        }
    }

    /// "failed attempts" — what the empty state and the caption say the reader is looking at.
    public var description: String {
        switch self {
        case .all: return "attempts"
        case .success: return "attempts that got up"
        case .failed: return "failed attempts"
        case .free: return "free takeoffs"
        }
    }
}
