# Jan's block — the clicks nobody else can make (release round E, 1.0.1)

Everything else in this round is code, docs and a build proven to compile. These five are not
code at all — each one needs an account, a key or a signature that lives only with Jan, and
none of them was run from here.

## 1. Turn on branch protection

`docs/engineering.md`, "Branch protection — one command, Jan's to run": needs admin on
`JanLahmann/WingFoil`, which this session does not have and should not be given.

```sh
gh api -X PUT repos/JanLahmann/WingFoil/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  -F "required_status_checks[strict]=true" \
  -f "required_status_checks[checks][][context]=lab — pytest" \
  -f "required_status_checks[checks][][context]=kit — swift test" \
  -f "required_status_checks[checks][][context]=web — verifiers and copy" \
  -f "required_status_checks[checks][][context]=repo — release check and the Makefile" \
  -F "enforce_admins=false" \
  -F "required_pull_request_reviews=null" \
  -F "restrictions=null" \
  -F "allow_force_pushes=false" \
  -F "allow_deletions=false" \
  -F "required_conversation_resolution=false" \
  -F "required_linear_history=false"
```

Still not run as of this round — `main` is unprotected today. `enforce_admins=false` is
deliberate (Jan's own bypass for a release that has to go out while a runner is queued), and
`required_pull_request_reviews=null` keeps the one-owner habit of pushing straight to `main`.

## 2. Push the tags

`make tag-ios`, `make tag-garmin` and `make tag-web` each create a **local** annotated tag and
refuse on a dirty tree; none of them push. This round created none — no code changed here that
needed a new one, and a retrospective tag is a claim about which commit was uploaded that only
Jan can confirm. When a build ships:

```sh
make tag-ios                  # after archiving/uploading a release or beta build
git push origin ios/1.0.1-111 # Jan's, like every other push in this repo
```

The two tags still open from the retrospective list in `docs/engineering.md` ("The tags that
should exist today") also wait on him: eight watch versions with no commit named in
`garmin/store/listing.md` (`garmin/0.9.13` down to `garmin/0.9.4`), and every iPhone build
before this round's tagging discipline began.

## 3. The Strava review form

`docs/channels.md`, "The Strava review": the HubSpot form linked from
developers.strava.com/docs/getting-started, at
share.hsforms.com/1VXSwPUYqSH6IxK0y51FjHwcnkd8. It asks for Jan's name, `jan@lahmann-online.de`,
the company name, the app, client id `279015`, and the **current authenticated rider count** —
which is why it is filed the day the tenth rider connects and not before (rule 2 of "Four
rules for 'proven'": Strava denies applications below the cap it is meant to lift). The
prepared *Application description* and the *Images* list are already written in
`docs/channels.md`; only the click and the count are his.

## 4. The App Store Connect privacy answers

`docs/release/privacy-labels.md` is a draft, not a submission — every row is "ready for Jan to
click in," and three rows are explicitly flagged as his judgment call rather than a fact this
document can settle on its own:

- **Location — Coarse**: recommended Not Collected, flagged as the row App Review is most
  likely to query given the location prompt in beta/dev.
- **Identifiers** (the feedback mail's device facts) and **Diagnostics — Crash Data** (the
  MetricKit digest): both recommended Not Collected on the "a rider composing his own mail is
  not the app transmitting to a server" reasoning, with "Not Linked to You / App Functionality"
  named as the safe fallback if he would rather declare defensively.

The questionnaire itself only exists inside App Store Connect's own UI (App → App Privacy),
one record for release + beta and a second, shorter one for the dev app
(`de.lahmann.wingfoil.dev`) — no API reaches it from here.

## 5. Submit

Everything that turns an archive into something a rider can install:

- **App Store submission** — the release build's "Add for Review" / "Submit to App Review" in
  App Store Connect, after the metadata (screenshots, privacy labels above, support and privacy
  URLs, age rating, review notes) is filled in (`docs/channels.md`, "Before the release is
  submitted", items 5–6).
- **External TestFlight review** — `ios/tools/testflight_publish.py <build> --group external
  --app release --wait` submits the *beta* build for Apple's review, but the script reads its
  App Store Connect API key from `~/.appstoreconnect/private_keys/AuthKey_HZT9694JZ4.p8`, which
  is Jan's machine only (`docs/engineering.md`'s Secrets finding: today it is hardcoded rather
  than read from the environment). Internal-group attaches (`--group internal`) need no review
  and could in principle be run by anyone holding that key — nobody but Jan holds it.
- **Signing the archive itself** — step 4 of "Building 1.0.1 release from its tag"
  (`docs/engineering.md`) needs `DEVELOPMENT_TEAM: 685X8YLYSB` and its provisioning profiles,
  present only on Jan's machine; this round's builds all ran with `CODE_SIGNING_ALLOWED=NO`,
  which proves the code compiles and nothing more.
- **Connect IQ store submission** — the watch listing's own review, on the Connect IQ
  Developer Portal, is a separate account from every one of the above.

None of the five above was clicked, pushed, filed or submitted from this session — reading and
writing what each one needs was the whole of this round's release-engineering work.
