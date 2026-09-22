> Part of `docs/presentation.md`. Engine 0.23.0.

## Not a session — the recording that was never an afternoon

Some recordings are not sessions: the rider presses start on the beach, walks to the water,
changes his mind, presses stop. Jan's library held thirteen of those on 14 September 2026 —
0:00–0:24 min, 0.0 km, 0 % on foil — and every one of them was inside "44 sessions", inside
the period and gear totals, and at the right-hand end of the Trends *on foil* line, which it
pulled to zero. The engine now says which is which (docs/algorithms/not-a-session.md, "Not a session":
no foil time **and** under 120 s or under 200 m). This is what the rider sees of that.

**Nothing is deleted, refused or hidden.** Not on import, not later, not ever. A recording is
the rider's; the app's job is to stop counting it, not to decide he should not have it. The
row is in the list, its page opens, its map draws, its own numbers are on its own page.

**The row carries four quiet words.** `No riding detected`, in the row's secondary colour, on
the line under the date — no capsule, no colour, no icon. It is a footnote and not a badge:
the badges on that row say what the session *is* (whose, which rig, from the watch), and this
says what the library is *not doing* with it. A provisional row does not get it: that row
already says "the recording has not synced yet" in blue, and one row does not need two ways
of saying "not yet".

**The page says why in one line**, directly under the key-metrics block, in the footnote size
and the secondary colour:

> No time on the foil, 0:24 long and 0 m covered — so this looks like a recording rather than
> a session. It is kept, and left out of totals, trends and records.

Three rules that line keeps. It **names the two numbers that decided**, so a rider whose real
session was mis-read can see the evidence and disagree with it rather than being told a
verdict. It says **kept**, because the first question a missing session raises is whether it
was thrown away. And it uses no engine vocabulary — not `isSession`, not `foilTimeS`, not
"success" or "carried". Distance under a kilometre is printed in metres: "0.0 km" is what put
the row on the screen, and saying it back is no answer.

A provisional row's version of the same line is about the recording, not the riding:

> Your watch says this afternoon happened, but its recording has not arrived yet — so it is
> not counted in totals, trends or records until it does.

**What excludes it, in one place per platform.** `LibraryStore.clause` on the phone —
alongside the example, the provisional row and a friend's session, the fourth of four — and
`counts_towards_records` on the web. Everything downstream inherits it: Trends and its week
histogram, the session and all-time records tables, every period and season block, the gear
totals, the spot's visit count, the "last session" and the week on the home-screen widget,
the clean-jibe personal bests, and the import screen's default gear.

**The count and the list are two different questions.** The list shows every recording; every
"N sessions" line counts the ones that are sessions (`LibraryListing.riddenCount`) — the
library footer, and each group header. A **provisional** row *is* counted there: the rider
counting his week does not care that the FIT is still in the air, and that row's
`no_recording` verdict is read past in this one place and nowhere else.

## Spots — how a place gets its name, and when it stops existing

A spot is a cluster of session start coordinates (`SpotClusterer`, 500 m). It is born nameless
— `Spot 1`, `Spot 7` — and gets a real one from a reverse geocoder.

**Naming is automatic, and runs wherever the set of spots can change.** Every import, sync,
restore, delete and re-cluster ends in the same library reload, and the naming pass hangs off
that, so a new place is named within a second or two of arriving. It used to run at launch
only, which is why a library synced from intervals.icu in one sitting showed "Spot 1 … Spot 7"
beside sessions that all said "Nago Torbole Wingfoil": the sessions were named from their
filenames, and nothing had asked the geocoder since before they existed.

**It retries when the network was not there.** A pass that resolved nothing schedules another
at 20 s, then 60 s, then 180 s, then stops and waits for the next launch, import, or the
rider's own tap. Three attempts because the failure this covers is a phone in a van in the
Alps, not an outage; stopping because a phone with no signal must not be asked sixty times.

**Only a placeholder is looked up.** The candidate set is "auto-named **and** still called
`Spot N`". `autoNamed` on its own means "the rider has not renamed this", which stays true
after a successful lookup — so asking on that flag alone re-geocoded every spot in the library
at every launch, which is a network round trip and one coordinate leaving the phone for an
answer already on the screen. **Look up names again** is offered only while at least one
placeholder is left.

**Re-clustering keeps every name somebody chose or looked up.** It rebuilds the table from the
sessions and re-matches each new centroid to the nearest old spot within the radius, carrying
that spot's id, name, creation date and `autoNamed` flag across. The test is
"is it still a placeholder", not "did the rider rename it" — the older rule discarded every
*geocoded* name on every re-cluster and put the numbers back on the screen. A named spot can
only be inherited once per rebuild; a second cluster that would claim it takes a placeholder
and is looked up like any new place.

**A spot with no sessions does not exist.** `session.spotId` carries no foreign key — on
purpose, so spots can be rebuilt without touching sessions — so the cascade is written down:
deleting a session and finishing a re-cluster each prune every spot no session points at, in
the same write. (An import cannot orphan one: a session is attached to its spot in the same
breath as the spot is created.) That is what "Spot 1 · 0 · Never sailed" was — a place left
behind by sessions the rider deleted — and migration v16 clears the ones already in a library.
After a re-cluster the count is exactly the number of places his sessions fall into, every
time, in any order, which is what makes 7 → 5 a result rather than a surprise.

**Placeholder numbers never repeat.** A new spot takes one past the highest `Spot N` in the
table, not `COUNT(*) + 1` — which minted a second "Spot 2" in any library where one spot had
been renamed and another removed.

