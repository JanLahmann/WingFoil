import Foundation

/// **"Is this a wingfoil session?" — the question the import cannot answer itself**
/// (docs/presentation/labels.md, "Confirming the discipline on import").
///
/// Wingfoil is not a sport in Garmin, Strava, intervals.icu or Apple Health. Every recording
/// that is not the CleanJibe watch app's own therefore arrives saying either nothing or
/// something else, and the something else — sport 43, *windsurfing* — is the code ADR-004
/// files a wingfoil afternoon under. So the import states a preset from the rider's declared
/// default (`SessionIngestor.riderDiscipline`), marks that it was nobody's answer
/// (`SessionRow.disciplineGuessed`), and this type is what the app asks him about afterwards.
///
/// *Afterwards*, not before: a bulk import of two hundred files must not stop on its first
/// question, and a session analysed under the wrong preset loses nothing — every number is
/// re-derived from the archived recording the moment he says otherwise.
public enum DisciplineReview {

    /// **The switch this whole question hangs off** — Settings → Analysis → *"Windsurf
    /// (experimental)"*, off until a rider asks for it (docs/presentation.md, Settings).
    ///
    /// Everything here exists because a session might not be a wingfoil session. On a phone
    /// whose owner only ever wings, that is not a question at all: asking it after every
    /// import is the app being uncertain out loud about something it has no reason to doubt.
    /// So the flag is threaded through the two rules the library reads rather than checked in
    /// the views — `pending` below, and `showsBadge`/`showsGuessMark` — and each of them
    /// defaults to `true`, so a caller that has never heard of the switch behaves exactly as
    /// this type did before it existed.
    ///
    /// It hides *controls*, never analysis. A session somebody already analysed as windsurf
    /// keeps its preset, its numbers and its amber chip with the switch off; turning the
    /// switch off is not an answer to any question, so it re-derives nothing.

    /// The sessions nobody has confirmed, newest first — what the review sheet lists and what
    /// the library banner counts.
    ///
    /// **Empty while the windsurf switch is off**, which is what makes the review sheet and
    /// the library banner disappear without either of them learning about the setting: with
    /// no windsurf preset on offer, "which rig was this?" has one possible answer and is not
    /// worth a sheet. The import marks those sessions confirmed on the way in
    /// (`SessionIngestor.windsurfEnabled`), so turning the switch on later does not bring a
    /// season's worth of unasked questions with it.
    ///
    /// `dismissed` is the ids he has already skipped past. They keep their `?` on the library
    /// row (nothing was confirmed, and pretending otherwise would be the app answering for
    /// him) but they stop raising a banner, because a banner that returns after being
    /// dismissed is not a reminder, it is a nag.
    ///
    /// Two sessions are never asked about, whatever the column says. **The example** is a
    /// recording nobody in this library rode — it is a demonstration, we know what it is, and
    /// a first launch that answers "try the example session" with a question about its rig has
    /// made a worse first impression than no example at all. **A provisional row** is the
    /// watch's BLE card with no recording behind it yet: there is nothing to re-derive, so the
    /// question cannot be acted on, and the FIT that replaces it will carry the real answer.
    public static func pending(in rows: [SessionRow],
                               dismissed: Set<String> = [],
                               windsurfEnabled: Bool = true) -> [SessionRow] {
        guard windsurfEnabled else { return [] }
        // A recording that is not a session (engine 0.19.0) is out for the provisional row's
        // reason one step along: asking which rig a thirty-second beach recording was made
        // on is a question about nothing, and its answer would change no number.
        return rows.filter {
            $0.disciplineGuessed && !$0.isExample && !$0.isProvisional && $0.isSession
                && !dismissed.contains($0.id)
        }
        .sorted { $0.startDate > $1.startDate }
    }

    /// The library banner, or nil when there is nothing to review.
    ///
    /// It names the preset the sessions were read under rather than asking a question,
    /// because the honest headline here is *what the app has already done* — the numbers are
    /// on screen and they were produced under some preset. "3 new sessions analysed as
    /// Wingfoil" is checkable at a glance; "3 sessions need attention" is an alarm about
    /// something that is very probably right.
    public static func banner(_ pending: [SessionRow]) -> String? {
        guard !pending.isEmpty else { return nil }
        let word = pending.count == 1 ? " new session" : " new sessions"
        let noun = String(pending.count) + word
        let presets = Set(pending.map(\.analysisDiscipline))
        guard presets.count == 1, let only = presets.first else {
            return noun + " analysed. Check the discipline."
        }
        return noun + " analysed as " + only.title
    }

    /// **Does the library row wear a discipline badge at all?**
    ///
    /// With the switch on, always — the library may hold two rigs and the row has to say which
    /// one it is reading. With the switch off it wears one only when it says something other
    /// than `Wingfoil`: a wingfoil-only library repeating the word on every row is a column of
    /// noise, and the rows that *do* differ — a session analysed as windsurf back when the
    /// controls were visible, a recording whose own field says `Kitefoil` — are exactly the
    /// ones a reader would be surprised by, so they keep their badge either way.
    ///
    /// It takes the rendered badge rather than the row because the badge has three rungs
    /// (`SessionDisplay.badge`) and the honest question here is the one the reader asks: does
    /// this capsule say anything but "Wingfoil"?
    public static func showsBadge(_ badge: String, windsurfEnabled: Bool = true) -> Bool {
        windsurfEnabled
            || badge.caseInsensitiveCompare(Discipline.wingfoil.title) != .orderedSame
    }

    /// **The `?` after the badge** — "nobody has said this is what it is".
    ///
    /// Never drawn while the switch is off. It is the visible half of a question the app is no
    /// longer asking, and a mark of doubt beside a session nobody will ever be asked about is
    /// just a blemish. Sessions imported while the switch is off are not marked as guesses in
    /// the first place; this covers the ones imported before it was turned off.
    public static func showsGuessMark(guessed: Bool, windsurfEnabled: Bool = true) -> Bool {
        guessed && windsurfEnabled
    }

    /// What the recording's sport code says, as a **hint on the row and never as a decision**.
    ///
    /// It is shown because leaving it out would make the app look wrong on exactly the
    /// sessions a rider is most likely to query — his Garmin says windsurfing, CleanJibe says
    /// Wingfoil, and without this line the disagreement is silent. Saying it out loud, next to
    /// the reason, turns a bug into a sentence he can agree with in one tap.
    ///
    /// nil for a sport that says nothing about the question (no code at all, or a watersport
    /// this app has no opinion about), because a hint that adds nothing is noise on every row.
    public static func sportHint(_ sport: String?) -> String? {
        guard let name = sportName(sport) else { return nil }
        if name == "windsurfing" {
            return "Filed as windsurfing. A Garmin files a wingfoil session the same way."
        }
        return "Filed as " + name
    }

    /// The FIT sport code (or its name) in the rider's words, lowercase, or nil for one this
    /// app has nothing to say about. Sport 43 is windsurfing, 44 kitesurfing (ADR-004).
    static func sportName(_ sport: String?) -> String? {
        switch (sport ?? "").lowercased() {
        case "windsurfing", "43": "windsurfing"
        case "kitesurfing", "44": "kitesurfing"
        case "sailing", "32": "sailing"
        case "stand_up_paddleboarding": "stand-up paddleboarding"
        case "surfing": "surfing"
        default: nil
        }
    }

    /// The footer under the sheet's list: what skipping costs, said plainly, because the
    /// answer is "nothing" and a rider who does not know that will answer questions he has no
    /// way to answer rather than leave them.
    public static let footnote =
        "Wingfoil does not exist in Garmin, Strava, intervals.icu or Apple Health. "
        + "So a recording cannot say which rig it was ridden on.\n\n"
        + "You can change this later on any session with Details → \"Analyse as\". Everything "
        + "is then worked out again from the original file."
}
