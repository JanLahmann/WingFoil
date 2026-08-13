import Foundation
import GRDB

/// What happened to a card that arrived from the watch.
public enum CompanionIngestOutcome: Sendable, Equatable {
    /// No FIT for these minutes yet: a provisional row now holds the session's place.
    case provisional(SessionRow)
    /// A newer card for a session that was still provisional — the same row was refreshed
    /// (the watch re-sends its pending slot on reconnect, so this is routine, not an error).
    case refreshed(SessionRow)
    /// The FIT is already in the library. The card is dropped: real analysis outranks
    /// twenty integers, always. The row is returned with `watch` added to its sources.
    case alreadyAnalysed(SessionRow)
}

/// Reconciliation of the watch's BLE card with the FIT that follows it (phase 5).
///
/// THE WHOLE PROBLEM IN ONE SENTENCE: the same session reaches this app twice, minutes
/// apart at best and days apart at worst, and it must appear exactly once.
///
/// The card wins on *speed* and the FIT wins on *truth*, so whichever arrives first holds
/// the row and the other one is reconciled into it:
///
///     card, then FIT   → provisional row is filled with real analysis, flag cleared
///     FIT, then card   → card dropped, existing row noted as also seen over the watch
///     card, no FIT     → provisional row stays for ever; the rider did that session
///
/// All three go through `SessionIngestor.duplicate` — the ±60 s / ±60 s rule the FIT
/// importers already use. Not a second rule that agrees most of the time: two rules would
/// disagree on exactly the sessions a rider does back to back, and the failure is silent.
extension SessionIngestor {

    /// Ingests one validated card. Never throws for "we already have this" — that is the
    /// expected outcome once Garmin Connect catches up, not a failure.
    @discardableResult
    public func ingest(card: CompanionSummary) async throws -> CompanionIngestOutcome {
        let (startDate, durationS) = card.dedupeKey

        if let existing = try await duplicate(startDate: startDate, durationS: durationS) {
            guard existing.isProvisional else {
                // The FIT beat the card here (a phone that was in range all along, or a
                // card that arrived after the next morning's sync). Nothing to update but
                // the provenance.
                let noted = try await note(existing, source: .watch, icuActivityId: nil)
                return .alreadyAnalysed(noted)
            }
            // Still provisional: the watch's pending slot is newest-wins, so a second card
            // for the same session carries better numbers than the first (a resend after a
            // failed transmit). Take the numbers — but NOT the start/duration: identity
            // stays with the card that first claimed the row, so repeated resends cannot
            // walk the dedupe key sixty seconds at a time away from the FIT still to come.
            var refreshed = existing
            refreshed.apply(card)
            let stored = refreshed
            try await database.writer.write { db in try stored.update(db) }
            return .refreshed(stored)
        }

        var row = SessionRow(id: UUID().uuidString, startDate: startDate,
                             durationS: durationS,
                             // Only our own CIQ app can produce a card, and that app
                             // records a class-a FIT — so the row is already labelled the
                             // way the FIT it is waiting for will be.
                             sourceClass: "a")
        row.discipline = "wingfoil"
        row.importSource = ImportSource.watch.rawValue
        row.isProvisional = true
        row.apply(card)

        let inserted = row
        try await database.writer.write { db in try inserted.insert(db) }
        // The rider's usual kit, same as any other import: the combo is a fact about the
        // afternoon, and it is knowable before the FIT is.
        _ = try? await library.applyDefaultGear(sessionId: inserted.id)
        return .provisional(inserted)
    }
}

extension SessionRow {

    /// Fills the summary columns from a watch card.
    ///
    /// Deliberately the same *shape* as `apply(_ analysis:)` and deliberately not the same
    /// coverage: the card carries twenty numbers, and every column it cannot fill is left
    /// nil rather than zeroed. nil means "not known yet" everywhere else in this schema —
    /// a 0 kn best-500 m would read as "you were slow", which is a different claim from
    /// "the FIT has not arrived".
    ///
    /// `engineVersion` stays nil for the same reason: no engine produced these numbers.
    mutating func apply(_ card: CompanionSummary) {
        distanceKm = card.distanceM / 1000
        foilPct = card.foilPct
        foilTimeS = card.foilTimeS
        flightCount = card.flightCount
        longestFlightS = card.longestFlightS
        longestFlightM = card.longestFlightM
        best2sKn = card.best2sKn
        best10sKn = card.best10sKn
        turnsCounted = card.turnCount
        tacks = card.tacks
        jibes = card.jibes
        turnsFlewThrough = card.flewThrough
        turnsTouchdown = card.touchdowns
        turnsFellIn = card.fellIn
        takeoffAttempts = card.takeoffAttempts
        takeoffSuccesses = card.takeoffSuccesses
        windDirDeg = card.windDirDeg
        windSource = card.windDirDeg == nil ? nil : "watch"
    }
}
