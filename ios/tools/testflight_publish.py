"""Attach a processed TestFlight build to a group, set What to Test, and (for external groups)
submit it for beta review.

usage:
  uv run --with pyjwt --with cryptography --with requests \
      python ios/tools/testflight_publish.py <build-number> [--wait] [--group internal|external]

`--group external` (the default, and everything this script did before) attaches the build to
every external group and SUBMITS IT FOR BETA REVIEW. `--group internal` attaches it to the
internal group only and skips the submission — internal testers need no review, which is the
whole point of sending the dev build (the `TUNING` variant, docs/testing.md "Two TestFlight
variants") that way.

Edit WHATS_NEW below before running. The API key file is read from ~/.appstoreconnect and is
not in the repo. The one lesson this file exists to keep: attaching a build to an external
group through the API does not submit it for beta review, and external testers never see a
build that was not reviewed — builds 6-15 sat unreviewed for weeks while testers stayed on
build 5. This script submits.
"""
import sys, time, json, requests, jwt

KEY_ID = "HZT9694JZ4"
ISSUER = "b9e6ccaa-e24a-4d37-bc1d-87f5be210572"
KEY_PATH = "/Users/majl/.appstoreconnect/private_keys/AuthKey_HZT9694JZ4.p8"
APP = "6800401377"
BASE = "https://api.appstoreconnect.apple.com/v1"

WHATS_NEW = """New here? cleanjibe.org/start — a 20-minute test of the watch routes, and where to send feedback.

0.15.0 (build 47) — you choose which maps the watch gets.

- Map for the watch is a page now: the two most-ridden spots by default, or up to two picks among your spots and "Where I am now". The phone reads its own position once per send, only when you picked it, never in the background. Settings → Garmin watch → Map for the watch.

Still in from build 45: the grouped and filtered Sessions list, the reordered menu, Send feedback at the foot of every page, Connect Strava under Settings, the full-screen map legend fix.

Please check: pick "Where I am now" at a spot the library has never seen, send, and see whether the watch draws the shore there."""

# What the dev variant's testers are told instead. It is a different build of the same version,
# so saying which one this is matters more than the release notes do.
WHATS_NEW_INTERNAL = """New here? cleanjibe.org/start — a 20-minute test of the watch routes, and where to send feedback.

Dev build 48 (tuning). Same 0.15.0 as public build 47, plus Settings → Tuning: the analysis thresholds on sliders, and the workbench on the turn page.

Settings → About says "· dev" on this one. Moving any slider re-analyses your library with the new thresholds and marks every screen that shows a tuned number with a "tuned thresholds" chip — those numbers are not comparable with anyone else's. "Reset all" puts the published defaults back.

New since 46, same as the public build: Map for the watch opens a picker with the automatic pair, every spot with its session count, and "Where I am now", read once per send. A third pick replaces the oldest.

Please check: does the location prompt appear only when you tap "Where I am now", and does a relaunch stay quiet?"""


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


def find_build(number):
    d = req(f"/builds?filter[app]={APP}&filter[version]={number}&sort=-uploadedDate&limit=5")
    return d["data"][0] if d["data"] else None


def parse_args(argv):
    number, wait, group = None, False, "external"
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
        elif a.startswith("--"):
            raise SystemExit(f"unknown option {a}")
        else:
            number = a
        i += 1
    if number is None:
        raise SystemExit(__doc__)
    if group not in ("internal", "external"):
        raise SystemExit("--group takes 'internal' or 'external'")
    return number, wait, group


def main():
    number, wait, group = parse_args(sys.argv[1:])
    internal = group == "internal"
    print("target group:", group)
    while True:
        b = find_build(number)
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
    b = find_build(number)
    print("usesNonExemptEncryption:", b["attributes"].get("usesNonExemptEncryption"))


if __name__ == "__main__":
    main()
