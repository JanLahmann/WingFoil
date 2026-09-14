"""Attach a processed TestFlight build to a group, set What to Test, and (for external groups)
submit it for beta review.

usage:
  uv run --with pyjwt --with cryptography --with requests \
      python ios/tools/testflight_publish.py <build-number> [--wait] \
          [--group internal|external] [--app release|dev]

`--group external` (the default, and everything this script did before) attaches the build to
every external group and SUBMITS IT FOR BETA REVIEW. `--group internal` attaches it to the
internal group only and skips the submission — internal testers need no review, which is the
whole point of sending the dev build that way.

`--app` names which App Store Connect record to work on (docs/channels.md, "Three channels").
`release` is the default and is `de.lahmann.wingfoil` — the App Store app, which carries both
the release channel's builds and the beta channel's. `dev` is the separate "CleanJibe Dev"
record (`de.lahmann.wingfoil.dev`). `CJ_DEV_APP_ID` in the environment overrides the id below,
which is the one escape hatch if the record is ever recreated.

Edit WHATS_NEW below before running. The API key file is read from ~/.appstoreconnect and is
not in the repo. The one lesson this file exists to keep: attaching a build to an external
group through the API does not submit it for beta review, and external testers never see a
build that was not reviewed — builds 6-15 sat unreviewed for weeks while testers stayed on
build 5. This script submits.
"""
import os, sys, time, json, requests, jwt

KEY_ID = "HZT9694JZ4"
ISSUER = "b9e6ccaa-e24a-4d37-bc1d-87f5be210572"
KEY_PATH = "/Users/majl/.appstoreconnect/private_keys/AuthKey_HZT9694JZ4.p8"
# The App Store record: release and beta share it, because they share a bundle id.
APP_RELEASE = "6800401377"
# "CleanJibe Dev" (de.lahmann.wingfoil.dev), created 14 Sep 2026.
APP_DEV = "6811840646"
# Overrides APP_DEV when set; the escape hatch if the record is ever recreated.
DEV_APP_ID_ENV = "CJ_DEV_APP_ID"
BASE = "https://api.appstoreconnect.apple.com/v1"


def app_id(app):
    """The ASC app id for the channel named on the command line."""
    if app == "release":
        return APP_RELEASE
    return os.environ.get(DEV_APP_ID_ENV, "").strip() or APP_DEV

WHATS_NEW = """New here? cleanjibe.org/start — the routes from your watch to the app, and where to send feedback.

0.15.0 (build 53) — the beta channel, with its own icon.

This is the first build of the BETA channel: the same app that goes to the App Store, plus the doors that are still proving themselves (GPX and TCX files, the Garmin export ZIP, Apple Health, the video export, grouping and filters in Sessions, the Apple Watch app). Settings → Beta lists them and has a "Request a feature" line.

- The icon and the start screen wear a red BETA label, so this build and the App Store one are told apart at a glance.
- The app follows your phone's text size everywhere now, including the largest accessibility sizes; the dense tables stop growing where they would break.
- Send feedback from the foot of every page, or Menu → Support & ideas; the mail starts with three blanks for you and the facts below them.
- Settings → Beta → Send usage report: a mail with counters kept on your phone (imports, syncs, share cards, failures). Nothing is sent unless you send it; delete any line.
- Sessions can be grouped by month, year or spot, and filtered by source.
- Strava: the official Connect with Strava button on Import and in Settings; a Strava-imported session links back with View on Strava.
- The three recording classes (Garmin watch app, any speed FIT, positions only) are named before you import, and in Help.
- Since 51: a session that arrived as a card from the watch opens on its own numbers; the grouping segment reads "All"; the start screen carries cleanjibe.org.

The site: cleanjibe.org has a light theme, a shorter homepage with the card on top, and cleanjibe.org/learn for the long read. On Android, "Add to home screen" installs the analyzer and it appears in the share sheet for .fit, .gpx and .tcx files.

Please check: does the BETA icon show on your home screen? Does the text-size setting (Settings → Display → Text Size) change the app without cutting anything off?

Ideas and wishes are as welcome as bugs: Menu → Support & ideas in the app, or info@cleanjibe.org."""

# What the dev app's testers are told instead. It is a second app ("CleanJibe Dev") beside the
# App Store one, so saying which one this is matters more than the release notes do.
WHATS_NEW_INTERNAL = """New here? cleanjibe.org/start — the routes from your watch to the app, and where to send feedback.

CleanJibe Dev, build 54 — the first build of the dev channel as its own app.

It installs BESIDE the App Store/beta app (bundle de.lahmann.wingfoil.dev), with its own library. Its icon is the mark mirrored — wing upper right — and the start screen shows the same. Everything the beta has (build 53's notes), plus: the Garmin link (summary card from the watch, map to the watch with the spot picker and "Where I am now"), windsurf discipline, iPad, and Settings → Tuning with the sliders and the turn workbench. Settings → About says "· dev".

Moving any slider re-analyses your library with the new thresholds and marks every screen that shows a tuned number with a "tuned thresholds" chip — those numbers are not comparable with anyone else's. "Reset all" puts the published defaults back.

The Garmin link talks to the dev-beta watch build (0.9.10-dev4, mirrored icon on the watch too) as well as the invite and public builds.

Please check: both apps on one phone, told apart by their icons; a map sent to the watch; the text-size setting at its largest.

Ideas and wishes are as welcome as bugs: Menu → Support & ideas in the app, or info@cleanjibe.org."""


def tok():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      open(KEY_PATH).read(), algorithm="ES256", headers={"kid": KEY_ID})


def req(path, method="GET", body=None):
    r = requests.request(method, BASE + path if path.startswith("/") else path,
                         headers={"Authorization": f"Bearer {tok()}", "Content-Type": "application/json"},
                         data=json.dumps(body) if body else None, timeout=60)
    if r.status_code >= 400:
        raise SystemExit(f"{method} {path} -> {r.status_code}\n{r.text[:800]}")
    return r.json() if r.text else {}


def find_build(app, number):
    d = req(f"/builds?filter[app]={app}&filter[version]={number}&sort=-uploadedDate&limit=5")
    return d["data"][0] if d["data"] else None


def parse_args(argv):
    number, wait, group, app = None, False, "external", "release"
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--wait":
            wait = True
        elif a == "--group":
            i += 1
            group = argv[i] if i < len(argv) else ""
        elif a.startswith("--group="):
            group = a.split("=", 1)[1]
        elif a == "--app":
            i += 1
            app = argv[i] if i < len(argv) else ""
        elif a.startswith("--app="):
            app = a.split("=", 1)[1]
        elif a.startswith("--"):
            raise SystemExit(f"unknown option {a}")
        else:
            number = a
        i += 1
    if number is None:
        raise SystemExit(__doc__)
    if group not in ("internal", "external"):
        raise SystemExit("--group takes 'internal' or 'external'")
    if app not in ("release", "dev"):
        raise SystemExit("--app takes 'release' or 'dev'")
    return number, wait, group, app


def main():
    number, wait, group, app = parse_args(sys.argv[1:])
    APP = app_id(app)
    internal = group == "internal"
    print("target app:", app, APP)
    print("target group:", group)
    while True:
        b = find_build(APP, number)
        state = b["attributes"]["processingState"] if b else None
        print("build", number, "->", b["id"] if b else None, state)
        if b and state == "VALID":
            break
        if not wait:
            raise SystemExit("not ready")
        time.sleep(60)
    bid = b["id"]
    groups = req(f"/betaGroups?filter[app]={APP}")["data"]
    attached = 0
    for g in groups:
        is_internal = bool(g["attributes"].get("isInternalGroup"))
        if is_internal != internal:
            print("skip", "internal" if is_internal else "external", "group",
                  g["attributes"]["name"])
            continue
        # An internal group with "automatic distribution" on (`hasAccessToAllBuilds`) gets
        # every processed build by itself, and Apple *refuses* a manual assignment to it
        # (422 "Builds cannot be assigned to this internal group", build 29, 7 Sep 2026).
        # Only a group without that flag needs the relationship POSTed.
        if g["attributes"].get("hasAccessToAllBuilds"):
            print("already in", g["attributes"]["name"], "— the group receives every build")
            attached += 1
            continue
        req(f"/betaGroups/{g['id']}/relationships/builds", "POST",
            {"data": [{"type": "builds", "id": bid}]})
        attached += 1
        print("attached to", g["attributes"]["name"], "internal" if is_internal else "external")
    if not attached:
        print(f"WARNING: no {group} group found for app {APP} — nothing was attached")
    whats_new = WHATS_NEW_INTERNAL if internal else WHATS_NEW
    locs = req(f"/builds/{bid}/betaBuildLocalizations")["data"]
    if locs:
        req(f"/betaBuildLocalizations/{locs[0]['id']}", "PATCH",
            {"data": {"type": "betaBuildLocalizations", "id": locs[0]["id"], "attributes": {"whatsNew": whats_new}}})
    else:
        req("/betaBuildLocalizations", "POST",
            {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": whats_new},
                      "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
    print("what to test set")
    if internal:
        # Internal testers (App Store Connect users on the team) see a build the moment it
        # finishes processing. Submitting a dev build for beta review would put a build we
        # never intend to ship in front of Apple's reviewers and hold up the queue for the
        # public one.
        print("internal group: no beta review needed, not submitting")
    else:
        # External testers only ever see builds that passed TestFlight beta review. Attaching a
        # build to an external group via the API does NOT submit it (the web UI does); builds
        # 6-15 sat at READY_FOR_BETA_SUBMISSION for weeks and testers stayed on build 5.
        sub = requests.get(BASE + f"/builds/{bid}/betaAppReviewSubmission",
                           headers={"Authorization": f"Bearer {tok()}"}, timeout=60).json().get("data")
        if not sub:
            d = req("/betaAppReviewSubmissions", "POST",
                    {"data": {"type": "betaAppReviewSubmissions",
                              "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
            print("beta review:", d["data"]["attributes"]["betaReviewState"])
        else:
            print("beta review already:", sub["attributes"]["betaReviewState"])
    # export compliance: ITSAppUsesNonExemptEncryption=false is in the Info.plist, so no prompt expected
    b = find_build(APP, number)
    print("usesNonExemptEncryption:", b["attributes"].get("usesNonExemptEncryption"))


if __name__ == "__main__":
    main()
