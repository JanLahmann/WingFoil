import Foundation

/// **Whether a speed record from a track that never measured a speed may stand.**
///
/// Jan, 22 September 2026. A *verified* record comes off a recording that carries the
/// receiver's own Doppler speed channel — the CleanJibe watch app's FIT, a native Garmin
/// FIT, anything `SourceCapabilities.hasSpeed` is true for, which the library stores as
/// source class `a` or `b`. An *unverified* one comes off class `c`: a GPX, a TCX with no
/// speed, a Strava activity, an Apple Health workout. There the speed was differentiated
/// from positions, and a differentiated speed reads high (docs/algorithms.md, "Speed
/// records", and the plausibility gate `UNCERTIFIED_SHORT_WINDOW_MAX`).
///
/// Until this setting existed the answer was fixed: an unverified record entered the
/// all-time table, the personal bests, the trends series, the card and the celebration,
/// wearing a mark. That is one of three reasonable answers and it is now the rider's to
/// pick.
///
/// **One rule, one function.** `SpeedRecordRule.eligible(_:policy:verified:)` is the whole
/// decision, and every surface that can show an all-time record calls it: the records
/// table (`LibraryStore.records`), the personal bests and the celebration
/// (`PersonalBestDetector`), the Trends best-2 s series, the share card and the widget
/// snapshot. Pattern L in docs/review-checklist.md: one taxonomy per concept, and a second
/// copy of this ladder in a view would be a second answer waiting to disagree.
///
/// **It is applied at query time, never stored.** The digest, the `record_effort` rows and
/// the analysis document all keep every record they ever held; the setting decides what is
/// read back out of them. So a rider who changes his mind gets the other answer at once,
/// with nothing to re-import.
public enum SpeedRecordPolicy: String, Codable, Sendable, CaseIterable, Identifiable {

    /// An unverified record never stands. It is still on its own session's page, marked.
    case onlyVerified

    /// **The default.** Per record kind, a verified record wins whenever there is one; an
    /// unverified record fills the row only where no verified record of that kind exists,
    /// and it carries the mark.
    case preferVerified

    /// Every record stands, marked where it could not be verified. What the app did before
    /// this setting.
    case includeUnverified

    public var id: String { rawValue }

    /// The word in the picker.
    public var label: String {
        switch self {
        case .onlyVerified: "Only verified"
        case .preferVerified: "Prefer verified"
        case .includeUnverified: "Include unverified"
        }
    }

    /// One line under the choice, so the picker is legible before it is moved.
    public var summary: String {
        switch self {
        case .onlyVerified: "Only records your watch measured. Nothing else counts."
        case .preferVerified:
            "A measured record wins. An estimated one fills an empty row, marked."
        case .includeUnverified: "Every record counts. Estimated ones are marked."
        }
    }
}

/// **The one function that answers "may this record stand".**
///
/// Generic over the row type because the same question is asked of five different shapes —
/// a `RecordEffortRow`, a `RecordBest`, a `TrendPoint`, a session row, a card's stats —
/// and the answer depends on exactly two things: the policy, and whether the candidate was
/// verified.
///
/// Call it **once per record kind**. `preferVerified` is a statement about a kind: best 2 s
/// may be filled by an unverified effort while best 500 m is not, because the library holds
/// a verified 500 m and no verified 2 s. Handing it a mixed bag of kinds would answer the
/// question for the wrong set.
public enum SpeedRecordRule {

    /// The candidates of one record kind that the policy lets stand, in the order given.
    ///
    /// - Parameters:
    ///   - candidates: every effort of one record kind, verified and unverified together.
    ///   - policy: the rider's choice.
    ///   - verified: whether one candidate came off a recording with its own speed channel.
    /// - Returns: the subset that may stand. Empty is a real answer: a kind whose only
    ///   efforts are unverified simply has no row under `onlyVerified`.
    public static func eligible<T>(_ candidates: [T],
                                   policy: SpeedRecordPolicy,
                                   verified: (T) -> Bool) -> [T] {
        switch policy {
        case .includeUnverified:
            return candidates
        case .onlyVerified:
            return candidates.filter(verified)
        case .preferVerified:
            let certified = candidates.filter(verified)
            return certified.isEmpty ? candidates : certified
        }
    }

    /// The same question about one candidate that has no siblings to be preferred over —
    /// a single session's card, a widget fact, one row's speed cell.
    ///
    /// `preferVerified` cannot prefer anything here, so it answers like
    /// `includeUnverified`: the record is the only one there is, and it stands marked.
    public static func stands(verified: Bool, policy: SpeedRecordPolicy) -> Bool {
        policy == .onlyVerified ? verified : true
    }
}

/// The one stored copy of the rider's choice, the shape `SpeedUnitStore` already uses.
///
/// An unreadable or unknown stored value falls back to `preferVerified`: a build that adds
/// a fourth mode must not strand an older app on an empty records table.
public enum SpeedRecordPolicyStore {

    public static let defaultsKey = "speedRecords.v1"

    public static func load(from defaults: UserDefaults) -> SpeedRecordPolicy {
        defaults.string(forKey: defaultsKey)
            .flatMap(SpeedRecordPolicy.init(rawValue:)) ?? .preferVerified
    }

    public static func save(_ policy: SpeedRecordPolicy, to defaults: UserDefaults) {
        defaults.set(policy.rawValue, forKey: defaultsKey)
    }
}
