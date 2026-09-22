> Part of `docs/presentation.md`. Engine 0.24.0.

## Gear & spots — one page of named things

A spot is the same kind of object as a wing: a named thing sessions reference, and a
top-level filter chip on both Records and Trends. The tab that owns the rider's named things
therefore owns both, **on one page** (Jan, build 58). Spots arrived here from four levels
down the Settings sheet as a row that pushed a sub-page of their own, which is one tap to
find out there is nothing to find out; they are now the first section of the same list, in
the three gear groups' own shape:

- **header** — an icon and a name, like *Wing* / *Board* / *Foil*;
- **one row per spot** — the name, a ✨ where the map named it rather than the rider, a
  chevron, and underneath the same caption figures a gear row carries: `12 sessions`,
  `last 30 Aug 2025`. Tapping a row renames it, in an alert with a field in it, because a
  rename is one short string and not a screen. The coordinates that the old sub-page printed
  are gone: a centroid to four decimal places is a fact about the clusterer, not about the
  place;
- **the section's own actions at its foot**, where every gear group keeps *Add wing*:
  **Re-cluster spots** and **Look up names again**;
- **the footer** — tap to rename, a typed name survives a re-cluster, sessions within the
  cluster radius are one spot, names come from the map when the network allows.

**A spot with no sessions is not listed.** Clustering can leave one behind — a session
deleted, a re-cluster that moved its afternoons into a neighbour — and an empty spot is a
name with nothing under it that still turns up in every spot filter. The count is the whole
of the evidence, so the count is the whole of the filter, on this page and in the *Manage
spots…* sheet the Records and Trends spot chip still opens (`SpotsView`, which is now reached
from there and nowhere else).

**The tab is called "Gear & spots".** It said *Gear*, because four labels share a 390 pt bar
— but spots are half of what is behind it, and a rider looking for the place his spots are
named has no reason to open a tab called Gear. The bar scales the label; the name tells the
truth, and it is the screen's own title as well.

## Session list — group by, and the filters that narrow it

A library is a list of afternoons until it is about forty of them, at which point the
questions a rider brings to it stop being "what did I do on Saturday" and start being about
*sets*: how many afternoons in August, everything at Torbole, what came in from Strava.
Flat and newest-first, the list answered those by scrolling. Two controls answer them
instead — **group by** at the top of the list, and one **filter** menu in the toolbar — and
both live only on the Sessions tab.

**Group by: All · Month · Year · Spot.** A segmented control at the top of the list,
because there are four fixed answers and the one in force is worth seeing without opening
anything. The first segment is **All** and not "None" (Jan, 14 Sep 2026): beside Month and
Year it names the whole library in one piece, where "None" read as nothing being shown. The
value behind it is still `none` — that is what `library.groupBy.v1` holds on every phone
already, and what `UI_GROUP_BY` takes. Groups are list sections, **newest group first**,
sessions inside a group newest first like the flat list they came from, and the header
carries the count: `August 2026 · 9 sessions`, `2025 · 41 sessions`,
`Nago-Torbole · 31 sessions`. Month names are written out in full and in en-GB, the same
table the period headings use ("Formatter rules"), so one month reads the same on both
screens.

Under **Spot**, sessions with no spot — and sessions whose spot the table can no longer name,
which is the same thing as far as a heading goes — fall into a last group called **No spot**.
Last whatever its dates say: it is not a place, so it has no place in the sequence.

The default is **Month from twenty sessions up, All below**, counted over the *unfiltered*
library. A library of nine is a screen and headings on it are furniture; a library of two
hundred is already being scrolled by month. The count is the whole library on purpose: the
default is a fact about how much the rider has, not about what a chip is showing him this
second, and a list that ungrouped itself because a filter narrowed it to nineteen would be
answering a different question at every tap. Once he moves the control the choice is
remembered (`library.groupBy.v1`), because "I read my library by month" is a fact about the
rider; the *filter* is not remembered, because a narrowing is a question and not a setting.

**The filter menu** is one toolbar menu next to Import, with four sections and a single
choice in each:

| section | entries |
|---|---|
| Spot | **All spots**, then every spot in the library |
| Source | **All sources**, then the doors this library actually holds — intervals.icu, File, Garmin export, AirDrop, Garmin watch, Apple Watch, Apple Health, Strava, Example |
| Discipline | **All**, Wingfoil, Windsurf foil, Windsurf fin — shown only with the windsurf switch on |
| Date | **All time**, This year, Last year, Custom range… |

A door that brought nothing in is not offered: a filter that can only ever empty the list is
not a filter, it is a trap. The demo doors (the bundled example, the repo's fixtures) are
hidden until the library holds such a row and are then called **Example** — "fixtures" is a
thing this repository has, not a thing the rider imported. **Source is containment, never
equality**: `session.importSource` is a `+`-joined set (`file+icu` once the same afternoon has
arrived twice), so a session that came in both ways answers to both doors — and `watch` never
matches `applewatch`, which is a Garmin summary card being mistaken for an Apple Watch
recording. Discipline reads the preset the session is *analysed* under, the rider's override
first and the recording's own tag second, so the menu agrees with the chip on the row.

Dates are read on **each session's own clock** where it recorded one: an evening session
either side of midnight belongs to the month the rider had, not to the month the reader's
phone is in. The two ends of a custom range are the other way round — they are days picked
off the reader's own calendar — and they are **inclusive at day granularity**, with the
Periods screen's own sentence under them: *Both dates count.*

**The chips say what is on without being opened.** When any filter is active a row of
capsules sits under the title, above the group-by control, one per narrowing, in menu
order: `Nago-Torbole ×`, `Strava ×`, `2025 ×`, `12 Jul – 3 Aug ×`. Tapping a chip clears
that one; from two chips up a plain **Clear all** sits at the end. A whole calendar year is
chipped as the year, because there is no second way to have picked 1 January to 31 December.
The failure this row exists to prevent is a list quietly three sessions long because a chip
was left on last week.

The footer counts what is shown against what there is — `3 of 41 sessions · pull to sync
intervals.icu` — and a filter that matches nothing gets its own empty state, **"No session
matches these filters"** with a **Clear filters** button. Not the fresh-library card: telling
a rider with forty sessions that he has none is the app being wrong about him.

**Records, Trends, Periods, the gear rollups and the widget keep reading the whole library**
(docs/decisions.md ADR-025). The filter is a view of one list. A chip that hides half the
list must never be able to hide half a personal best — "best 2 s: 24.1 kn" that quietly meant
"…at this spot, this year" is a number the rider would go on quoting long after the chip was
forgotten. Those screens have their own spot and gear pickers, which say so on the screen
they narrow.

iOS: `LibraryListing.swift` in the kit (`LibraryListFilter`, `LibraryGrouping`,
`LibraryGroup`, `LibraryDateWindow`), pinned by `LibraryListingTests`; the list itself is
`LibraryView`, the menu and the chips `LibraryFilterMenu.swift`. Not on the web session
viewer, which has no library to group.

### The row's three numbers, and the words under them

A row carried `37 % · 3 · 13.25 kn` under three glyphs and `4 · 1 · 0 · 2.1 km` under none.
Jan read the middle glyph — a turning arrow — as his jibes, and it was drawing the **flight**
count (Beta 75; pattern H, docs/review-checklist.md). A number a reader has to decode is a
number the row is not carrying, and a glyph is a guess until it has been read once with its
word beside it.

So **every number on a row has its word within reach**. The three metric cells put the word
directly under the value in caption type, which is how the watch draws the same three facts,
and the outcome tally spells itself out: `4 flew · 1 touch · 0 fell`, each word in its own
number's ink. The key-metrics block is unchanged — its three counts already stand under a
caption that says what they are out of.

And **which three is the rider's**: Settings → Session list → *Row shows*, three pickers in
the order the row draws them. The options are `RowMetric` in the kit — foil, flights, jibes,
clean, turns, best 2 s, best 10 s, distance, time, dry streak — and each case owns its word,
its glyph and how its value is spelled, so the picker, the row and the session page cannot
drift apart. The default triple is **foil · jibes · best 2 s**: what the list always drew,
with the middle cell corrected to the jibes its glyph always promised. The choice is one
stored string (`sessionRowMetrics`), and a slot that cannot be read falls back to the default
rather than leaving the row a cell short (`RowMetricTests`).

## The session page: source, name, neighbours

The header names where the recording came from in one line under the date
(`SessionProvenance.line(importSource:)`: *Apple Watch · CleanJibe*, *intervals.icu*, *Strava*,
*Apple Health*, *File*) — provenance used to live on the Details tab only, so an Apple Watch
recording and a Health import looked alike. The title is a button: a tap opens a rename sheet
writing the same `customTitle` the share composer's field writes, so renaming is not a
side-effect of sharing. A swipe moves to the next or previous session in the list's own order
(`SessionStore.visibleSessionIDs`), with a greyed ‹ › pair beside the date at the ends; the
drag needs a horizontal intent (dx over 2.5 × dy) so the inline map keeps its pan.

**The finger drags the content**: a drag left takes the page left and brings in the *next*
session in the list's order, a drag right walks back to the previous one — the platform's
rule, and a sign that is read right and written backwards, so it is `SessionPaging` in the
kit with `SessionPagingTests` on it rather than a ternary in a gesture closure. The page
**slides** rather than swapping (Jan, Beta 75): it follows the finger while the drag is on
the glass (`SessionPaging.follow`, rubber-banded, and barely moving at the ends of the list
where there is nothing to turn to), then the outgoing page leaves by the edge it was pushed
towards while the incoming one arrives from the other. The ‹ › pair runs the same animation —
both go through one `turn(_:)`. A short flick counts when it was thrown hard enough
(`predictedEndTranslation`), the way a paged scroll view reads one.

The library row's track outline can sit on a map: Settings → Session list → *Map behind the
track in the list*, off by default, an `MKMapSnapshotter` image per session cached beside the
thumbnail and rebuilt with it. The snapshot is a picture of **the square the outline is drawn
in** — the tile's shorter side less one inset on both edges — widened to the tile's own shape
and centred on the track's bounding box (`TrackTileRegion`, pinned by `TrackTileRegionTests`).
There is one inset constant (`ListMapBackdrop.inset`) and the row hands it to the outline
view: it was two numbers, so the map was computed for a 40 pt square under a line drawn in a
34 pt one, and the track sat off towards an edge of a map of somewhere slightly else. The app-wide menu (What CleanJibe does · Getting started ·
Settings · Help · Support & ideas) is one `AppMenuButton` on all four tab roots (pattern M).

