> Part of `docs/presentation.md`. Engine 0.24.0.

## What leaves the phone — the privacy notes

The rule the app is built to and the privacy page states: the analysis runs on the device,
there is no account and no server of ours, and sessions are never uploaded. Every exception is
named, here and on the page, and the two say the same thing. Two of them are the rider's own
connections — **intervals.icu** and **Strava**, each only after he connects it, each carrying
his own credential to that one service. Two are Apple's **MapKit**: the map under a session,
and the coarse picture this phone renders for a Garmin watch. And one more, which the app
makes by itself:

> **Naming a sailing spot uses Apple's geocoder.** When CleanJibe finds a new place in your
> sessions it asks Apple's reverse-geocoding service what that place is called, so the spot
> reads "Nago-Torbole" instead of "Spot 3". What is sent is a single coordinate — the centre
> of that spot, rounded to about 110 m — and nothing else: no session, no track, no name, no
> identifier, and no account. It happens once per new spot, never for a spot that already has
> a name, and never at all if you name your spots yourself. Apple sees roughly where you sail,
> under Apple's own privacy policy.

The mechanics behind that sentence, so it stays true: it is `CLGeocoder.reverseGeocodeLocation`
(`SpotNamer`, in the kit) — Apple's framework, Apple's service, no third-party geocoder and no
HTTP client of ours anywhere in the project. The coordinate is rounded **before it is sent**
(`SpotNamer.roundedForLookup`, three decimal places), not merely on the way into a cache key,
because a privacy sentence that describes a rounding the code does not do is a false one. One
request per unnamed spot, at least 1.2 s apart, results cached. It needs no location
permission: the coordinate came out of a file the rider imported, not from the phone's own
GPS.

**This sentence is required wherever the network promise is made.** That is the privacy page
(`web/privacy/`, "The iPhone app — what leaves your phone"), and the App Store description's
privacy paragraph. Both currently name intervals.icu, Strava and Apple Maps; neither names the
geocoder, and until they do, both are incomplete.

## The first screen of a fresh install is "What CleanJibe does"

The welcome screen is the app's answer to the question a new rider actually has, and it is
owed to **every** install that has never had a session in it. Release candidate 58 opened on
the Sessions tab with the intervals.icu setup card instead — four steps and a key field in
front of somebody who had not been told what the app does — and the cause was the keychain:
iOS keeps keychain items across an app delete, so a reinstall gets the intervals.icu key
handed back before the first screen is drawn, and the rule counted a stored key as evidence
that this install had been welcomed already.

**Superseded on 25 September 2026** (Jan's plan of 24 September, section 7): the screen comes
up on *every launch* until the library holds a real session (the example does not count) or
an intervals.icu key is stored, and there is no "don't show this again" switch. The two facts
switch it off by themselves, so the once-only flag and the upgrade heuristic below are gone
from `WelcomePrompt`; `welcomeShown.v1` is still written and no longer read. A key does count
now: a reinstall with a key opens on the list, which fills from intervals.icu on the first
pull. The history below is kept for why it was once otherwise.

**Only a session is evidence** (`WelcomePrompt`, and its tests). A key says something
survived a delete; a session says the rider has been through the front door. So
`isAlreadyWelcomed(sessionCount:)` takes the library and nothing else, and both the silent
mark — the upgrade path, which stops a rider mid-season being greeted as a stranger — and the
decision to show the screen turn on it. `hasKey` is gone from all three functions. Everything
else about the screen is unchanged: it is shown at most once per install, the flag is written
the moment it goes up rather than when it is answered, another modal defers it rather than
cancelling it, and Menu → *What CleanJibe does* replays it without re-arming anything.

**One install can be owed it twice, and only one door does that**: Settings → Beta → *Start
over*, which writes `welcomeRequested.v1` after its wipe. A request beats both rules above —
see "Start over" — and the screen's own offers work from it exactly as on a first run, *Try
the example session* included: the example imports, and a rider who already owns that
recording lands on his own copy of it (`loadExampleSessionAndOpen`, which is unchanged and
never depended on the library being empty).

**The second and third offers left the screen on 25 September 2026.** *Set up intervals.icu*
and *Later* are gone: the X closes the screen, and **Get started** opens Getting started,
whose *Open CleanJibe Settings* closes the welcome and opens Settings, where the four steps
are. The rest of this paragraph is the history of the button that was there.

**The second offer is named for what it does** (15 September 2026). It read *"Connect your
Garmin"* and connected nothing: `onConnect` calls `dismissWelcome()` and that is the whole of
it, because on a genuine first run the four-step intervals.icu card is already the thing
underneath. A first-run button whose only visible effect is that the screen disappears reads
as a tap that failed. It is **`Set up intervals.icu`** now — the same name Settings and
`GettingStartedGuide.settingsIcu` give the same thing — and its detail keeps the *why*
(Garmin has no open API for a personal app) and adds the *what*: the screen closes, and the
4 steps are in Settings → intervals.icu, which the empty library's first row opens (reworded
on dev 70, when the steps left the first screen). The flow is unchanged and deliberately so: the excursion into
intervals.icu is intrinsic, honestly priced at *about five minutes, once*, and the
chicken-and-egg it used to cause is already solved by the first offer.

**And the empty library leads with the same two ways in.** When the library is empty and the
welcome has been dismissed, the Sessions tab shows one short row first: the welcome's own
headline (the tagline *Your WingFoil session, measured.* since 25 September 2026), and two buttons, **What CleanJibe does**
(the welcome screen again) and **Try the example session** (the same call the welcome's first
offer makes, so both doors land on the same session). Deliberately a row and not a second
card: the card under it is the thing to *do*, and this is the thing to read first. On a
genuine first launch the welcome cover is in front of it, so on that run it is simply what is
underneath.

### The ways in — the empty library's one card (dev 70)

Under that row sat the four-step intervals.icu card: the steps, the key field, the example
offer and two help links. It was the first screen of a first launch and it named **one** way
in. Jan, on dev 70: *"initial sessions page mentions icu but not Strava"*, and *"better refer
to Settings than repeat the setup"*. A rider who owns a Suunto, a Strava account or a single
FIT file read four steps about a service he does not use, and the one screen in the app that
should say *there are four ways in* said *there is one, and here it is in full*.

It is **one row per way in** now (`LibraryView.waysInCard`), under the heading *How your
sessions get in*. Each row is an icon, the action, and one line of at most twelve words:

| row | line under it | where it goes | channel |
|---|---|---|---|
| **Set up intervals.icu in Settings** | Garmin has no open API. intervals.icu is the bridge. | Settings | release |
| **Record on your Apple Watch** `BETA` | The session comes to the phone by itself. | the help topic *Recording with the CleanJibe Apple Watch app* | beta |
| **Set up Strava in Settings** | Strava hands over positions. Records are uncertified. | Settings | release, and only where the build carries Strava keys |
| **Import a file** | A FIT from any watch. AirDrop and Files work. | the file picker, `ImportView.importableTypes` | release |

Five rules hold that table together.

* **The order is the order a rider meets a watch**, Apple straight after Garmin. They are the
  same doors `GettingStartedGuide.routes` carries — `garmin`, `appleWatchApp`, `strava`,
  `fit` — so the empty state, the Getting started topic and `/start` name the same four. The
  generated guide is reordered from the web side, so nothing in the app reads that array by
  position: the rows are declared here, and the route ids are the seam.
* **The rows name the action, the routes name the door.** This is a list of things to *do*;
  the guide is a list of things to read. *Set up intervals.icu in Settings* and
  *Any watch that writes a .fit* are the same door said to two different readers.
* **Two rows end in Settings and say so in the label** (*Import does, Settings configures*,
  build 63). The sheet opens on intervals.icu and Strava, the form's first two sections, so
  there is no anchor to scroll to and nothing to miss. Both take the one action the library
  already hands down, `openIcuSettings` — the same door Import's `SetUpInSettingsRow` and
  Help's *Open CleanJibe Settings* use.
* **A build with no Strava keys shows no Strava row.** Settings would answer it with
  *"Not available in this build"*, and the first screen a rider meets does not offer a door
  onto that sentence — the same rule the filter menu keeps.
* **The Strava row is not called "Connect Strava".** Strava's guidelines reserve the connect
  action for their own button artwork and their own wording, *Connect with Strava*
  (`StravaBrand`, rule 1), and that button lives in Settings → Strava. This row is the way to
  it, so it is named the way the intervals.icu row above it is.

**The four steps have one home**, and it is Settings → intervals.icu: the caption, the key
field, *Get a key in 4 steps* and *Sync not working?*. `IcuSetupGuide` is still the one source
both the Settings rows and the help topic render — nothing was deleted from Settings, and the
first screen simply stopped repeating it. The intervals.icu **problem banner** came with the
card rather than with the steps: a key that has been typed and refused is the one thing a list
of doors cannot say for itself, so `.problem` still prints the cause, the fix and *What to
check* above the rows.

