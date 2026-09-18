"""Attach a processed TestFlight build to a group, set What to Test, and (for external groups)
submit it for beta review.

usage:
  uv run --with pyjwt --with cryptography --with requests \
      python ios/tools/testflight_publish.py <build-number> [--wait] \
          [--group internal|external] [--app release|dev] \
          [--notes <file>] [--print-notes]

`--group external` (the default, and everything this script did before) attaches the build to
every external group and SUBMITS IT FOR BETA REVIEW. `--group internal` attaches it to the
internal group only and skips the submission — internal testers need no review, which is the
whole point of sending the dev build that way.

`--app` names which App Store Connect record to work on (docs/channels.md, "Three channels").
`release` is the default and is `de.lahmann.wingfoil` — the App Store app, which carries both
the release channel's builds and the beta channel's. `dev` is the separate "CleanJibe Dev"
record (`de.lahmann.wingfoil.dev`). `CJ_DEV_APP_ID` in the environment overrides the id below,
which is the one escape hatch if the record is ever recreated.

The *What to Test* text is **not** written here any more. It comes from
`docs/copy/whats-new.json`, the one source the website's /whats-new/ cards and the app's own
What's new screen are also written from (`web/tools/make_whats_new.py`). This script takes
the newest entry of the channel it is publishing to: `dev` for `--app dev`, `beta` for the
release app's external groups. `--notes <file>` overrides it for the one-off case, and
`--print-notes` shows what would be sent without touching App Store Connect.

The API key file is read from ~/.appstoreconnect and is not in the repo. The one lesson this
file exists to keep: attaching a build to an external group through the API does not submit
it for beta review, and external testers never see a build that was not reviewed — builds
6-15 sat unreviewed for weeks while testers stayed on build 5. This script submits.
"""
import os, sys, time, json, pathlib, requests, jwt

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

# The frame around the notes, which is the same in every build and is therefore not a release
# note: the door for a tester who has just joined, and the one for a tester with something to
# say. The notes themselves come from docs/copy/whats-new.json.
NOTES_SOURCE = pathlib.Path(__file__).resolve().parents[2] / "docs" / "copy" / "whats-new.json"
INTRO = ("New here? cleanjibe.org/start — the routes from your watch to the app, and where to "
         "send feedback.")
OUTRO = ("Ideas and wishes are as welcome as bugs: Menu → Support & ideas in the app, or "
         "info@cleanjibe.org.")


def notes_channel(app, internal):
    """Which channel's notes this run is publishing (docs/channels.md).

    The dev record is a second app and only ever carries dev builds. The App Store record
    carries both the release channel's build and the beta channel's; what goes to external
    testers is the beta, which is what `--group external` on it means.
    """
    if app == "dev":
        return "dev"
    return "release" if internal else "beta"


def whats_new(app, internal, override=None):
    """The *What to Test* text: the newest entry of this channel, in TestFlight's layout.

    One source for three surfaces (docs/copy/README.md): the same JSON writes the cards on
    cleanjibe.org/whats-new and the app's own What's new screen, so a tester, a reader and
    the phone in his hand cannot be told three different things about one build.
    """
    if override:
        return pathlib.Path(override).read_text(encoding="utf-8").strip()
    channel = notes_channel(app, internal)
    entries = json.loads(NOTES_SOURCE.read_text(encoding="utf-8"))["entries"]
    entry = next((e for e in entries if e["channel"] == channel and e["build"] is not None),
                 None)
    if entry is None:
        raise SystemExit(f"no {channel} entry with a build number in "
                         f"{NOTES_SOURCE}. Add one, or pass --notes <file>")
    if channel == "dev":
        head = f"CleanJibe Dev, build {entry['build']}"
    elif channel == "beta":
        head = f"Beta build {entry['build']}"
    else:
        head = f"Build {entry['build']}"
    body = "\n".join("- " + line for line in entry["lines"])
    return f"{INTRO}\n\n{head} — {entry['title']}.\n\n{body}\n\n{OUTRO}"


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
    notes, print_only = None, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--wait":
            wait = True
        elif a == "--print-notes":
            print_only = True
        elif a == "--notes":
            i += 1
            notes = argv[i] if i < len(argv) else ""
        elif a.startswith("--notes="):
            notes = a.split("=", 1)[1]
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
    if number is None and not print_only:
        raise SystemExit(__doc__)
    if group not in ("internal", "external"):
        raise SystemExit("--group takes 'internal' or 'external'")
    if app not in ("release", "dev"):
        raise SystemExit("--app takes 'release' or 'dev'")
    return number, wait, group, app, notes, print_only


def main():
    number, wait, group, app, notes, print_only = parse_args(sys.argv[1:])
    APP = app_id(app)
    internal = group == "internal"
    text = whats_new(app, internal, notes)
    # Read before anything is attached, so a missing entry fails here rather than after the
    # build is already in front of testers with the previous build's notes on it.
    if print_only:
        print(text)
        return
    print("target app:", app, APP)
    print("target group:", group)
    print("notes channel:", notes_channel(app, internal))
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
    locs = req(f"/builds/{bid}/betaBuildLocalizations")["data"]
    if locs:
        req(f"/betaBuildLocalizations/{locs[0]['id']}", "PATCH",
            {"data": {"type": "betaBuildLocalizations", "id": locs[0]["id"], "attributes": {"whatsNew": text}}})
    else:
        req("/betaBuildLocalizations", "POST",
            {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
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
