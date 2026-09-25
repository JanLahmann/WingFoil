# Support and triage — where a rider's problem goes, and what happens to it

Written for release round E (1.0.1): the first release-channel riders are strangers, not
testers, and a problem from one of them has to reach us and become either an answer or a
backlog entry, on a routine rather than by luck. Four doors, one cadence, one path from a
mail to a public issue, and the words we reply in — `docs/voice.md`'s register, because a
reply is rider-facing even though this file is not.

## Where release crashes arrive

**There is no crash reporter and no server** (docs/security.md, "the one fact that shapes
everything"). Two routes exist for a release-channel crash, and neither needs code:

1. **App Store Connect / Xcode Organizer** — Apple's own aggregate. A rider who has opted in
   under Settings → Privacy & Security → Analytics & Improvements → Share With App
   Developers sends Apple a symbolicated crash automatically; App Store Connect groups them
   by crashing frame within about a day. To read them: Xcode → **Window → Organizer →
   Crashes**, sign in with the account that owns `de.lahmann.wingfoil`, select **CleanJibe**,
   pick a build. Each group shows a stack trace, the OS version and device spread, and a
   count. This needs no build from this tree — any Mac with Xcode signed into the account
   sees the same list — and it is the only one of the two that is symbolicated by name
   rather than by binary offset.
2. **The MetricKit digest in the feedback mail** — `ios/WingFoil/App/CrashDiagnostics.swift`
   subscribes to `MXMetricManager` in every channel including release, reduces each payload
   to four fields through the kit's `CrashLog` (`ios/WingFoilKit/Sources/WingFoilKit/Presentation/CrashDigest.swift`),
   and keeps the newest ten in the app's own Application Support directory. Nothing is sent
   anywhere by that type: the digests only leave the phone if the rider opens a feedback
   mail and reads the **Recent crashes** block before tapping Send (`FeedbackReport.blocks`,
   `crashHeading`). Reading one is reading the mail — there is no separate console or
   dashboard for it, which is the point: it is the one field-failure signal a release-channel
   rider can hand us without either of us running a server (docs/analytics.md, "(c) MetricKit
   crash digests").

The two overlap on purpose and answer different questions: Organizer says **how often**,
across every phone that opted in, symbolicated; the mail's block says **what a specific
reporting rider's phone saw**, unsymbolicated (`WingFoil +0x1b2c3`, an `atos` run away from a
name) but tied to the sentence the rider wrote above it. A crash worth chasing gets both:
Organizer for the frequency and the stack, the mail (if one arrives) for the rider's own
account of what he was doing.

**Symbolicating an offset from the mail**, when Organizer has not caught the same crash
(different OS build, or the rider never opted in to Apple's analytics): `atos -o
WingFoil.app.dSYM/Contents/Resources/DWARF/WingFoil -arch arm64 -l <slide> <offset>` against
the `.dSYM` the matching build's archive produced. The slide is not in the mail today — a
gap, not a fix, tracked as an open item below.

## Where feedback arrives

Four doors, in the order a report is likely to use them:

| door | who reaches it | what it carries | reaches us how |
|---|---|---|---|
| **Support & ideas mail** (`info@cleanjibe.org`) | every channel, `FeedbackDoors.menuRow` | device, build, channel, engine version, library shape, the Most-wanted ticks, the Recent crashes block, and — from a session's share sheet — that session's own facts and an attached recording | an ordinary mail, in whichever inbox reads that address |
| **TestFlight feedback** (`FeedbackDoors.testflight`, Apple's own "Send Beta Feedback") | beta and dev testers only, from a screenshot taken inside the build | the screenshot, the tester's sentence, and Apple's own device/OS metadata — no MetricKit digest, no Most-wanted block | App Store Connect → TestFlight → the build → Feedback |
| **GitHub issues** (`github.com/JanLahmann/WingFoil/issues`) | anybody who reads the public repo; not linked from inside the app | a title and, per the repo rule, as little else as the reporter chooses (CLAUDE.md: "the repo is public: GitHub issues stay terse") | the repo's own notifications |
| **Garmin Connect IQ store reviews** | Garmin watch owners, on the store listing | a star rating and sometimes a sentence, in Garmin's own console, with no reply channel back to the reviewer except a developer response Garmin publishes alongside it | Connect IQ Developer Portal → the app's listing → Reviews |

The mail is the one door built for the purpose — it is the only one that arrives with the
diagnostics already attached — and is worded to invite an idea as readily as a fault
(`FeedbackInvitation`, Jan 14 Sep 2026: "nothing in the app ever invited an idea"). The other
three are Apple's or Garmin's own surfaces and carry only what those platforms choose to
carry.

## How often we look

A fixed routine beats a hunch about whether today is a mail day. Starting point, adjustable
by Jan at any time:

- **The mail address, every day it is a riding day** — it is the fastest route to an answer
  and the only one carrying facts, so it is checked whenever the inbox is open anyway.
- **TestFlight feedback and GitHub issues, weekly** — a fixed day (a wet one is as good as
  any), since neither notifies as insistently as mail and both can sit unread for a while
  with no cost to a rider who is not waiting on a reply.
- **Connect IQ store reviews, at every watch release** — Garmin's console has no feed to
  watch between uploads, so it is read at the one moment it is already open.
- **Xcode Organizer, monthly or after a spike** — checked on a schedule regardless of whether
  a mail mentioned a crash, since a rider who crashed and did not write is exactly the rider
  Organizer is for.

## From a report to a backlog entry

1. **Read it against the four rules** (`docs/channels.md`, "Four rules for 'proven'") if it
   is a feature ask, or reproduce it if it is a fault. A Most-wanted tick is a vote, not a
   report on its own — tally it, do not file it.
2. **File the public issue first, terse.** One line, no diagnostics, no rider's name, no
   session details, no device model beyond what the title needs — `gh issue list` above shows
   the house style: "iOS: save/sync the library to iCloud Drive", "Watch map page: real map
   background under the breadcrumb". The repo is public; a title is a pointer, not a report.
3. **Keep the detail private.** The mail itself (device, build, engine version, crash
   digests, a spot name) is the record of what was actually reported, and it stays in the
   inbox — never pasted into the issue body. A private artifact (a doc, a note to Jan) carries
   the plan when one is needed; the issue links to nothing that is not already public.
4. **Duplicate reports close under the first issue**, `duplicate` labelled, one line pointing
   at it — the label already exists on the repo.
5. **A fault becomes `bug`, an ask becomes `enhancement`**, the two labels already on the
   repo; `question` for anything that turns out to be a Settings walkthrough rather than a
   defect (issue #11, #12 are both this shape today).

## Replying, in the team's own voice

Every reply is rider-facing text, so it is written to `docs/voice.md`: second person, present
tense, the rider's vocabulary, one thought per sentence, *we* only where a person is meant
(rule 7). None of the four below is a script to paste unread — each is a shape to fill in,
the way the feedback mail itself is a template and not a form letter.

**Acknowledging a bug report** (mail or TestFlight feedback):

> Thanks — got it, and I can see build \<n> and \<device> in what you sent. I'll try to
> reproduce this and let you know what I find.

**Acknowledging a feature idea** (a Most-wanted tick, a mail, or an issue):

> Thanks for the idea. CleanJibe is built with its riders, so this goes on the list — new
> features are chosen by demand and tested in the beta first.

(the second sentence is `FeedbackInvitation.community`, already the one wording for this on
the footer and the Beta page — a reply that said it differently would be a fourth spelling of
a sentence `docs/presentation.md` already pins to one.)

**Closing a fixed bug:**

> Fixed in build \<n>, out on TestFlight now (release riders get it in the next App Store
> update). Thanks for flagging it.

**A Garmin store review with a real fault in it** (the one door with no private reply):

> Sorry about that — could you write to info@cleanjibe.org with your watch model? I can't
> reply here with anything specific, but I read every review.

## What this file does not yet cover

- No `SECURITY.md` exists yet for a security-shaped report to be routed under; today one
  would arrive through the same mail address as everything else (docs/engineering.md,
  "Findings" table, Privacy row references a scan but not a disclosure address).
- The feedback mail's crash block does not carry the load address a symbolication needs
  (`CrashDigest.topFrame` is a binary name and a text-segment offset only); until it does,
  a mail-reported crash Organizer has not already grouped needs the matching build's `.dSYM`
  and a manual `atos` run, as above.
