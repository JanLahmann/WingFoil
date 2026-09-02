"""Attach a processed TestFlight build to the external groups, set What to Test, and submit it
for beta review.

usage: uv run --with pyjwt --with cryptography --with requests python ios/tools/testflight_publish.py <build-number> [--wait]

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

WHATS_NEW = """0.14.0 - the clean jibe round.

- CPH, clean jibes per hour, now sits beside JPH and TPH in the key metrics and on the share card.
- Clean jibes get a star on the map with their own legend chip, a personal-best moment, and a line in the replay commentary.
- Records: a second table of session records - longest flight, most flights, foil share, most clean jibes, best CPH, best clean-jibe rate, streaks, longest session, most distance.
- Trends: clean jibes and CPH per session; the weekly chart now bins by ISO weeks (Monday).
- Periods: trips (auto-detected), months, seasons and custom ranges, each with one aggregate block, and a share card for a period with its tracks stacked.
- The option row under the map is regrouped: route layers, event markers, utilities.

On first launch after this update the library re-analyses itself once (new record columns); give it a minute on a big library. Please check: does the star land on the jibes you remember as clean? Does your Garda week come out as one trip?"""


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


def main():
    number = sys.argv[1]
    wait = "--wait" in sys.argv
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
    for g in groups:
        if g["attributes"].get("isInternalGroup"):
            print("skip internal group", g["attributes"]["name"], "(builds arrive automatically)")
            continue
        req(f"/betaGroups/{g['id']}/relationships/builds", "POST", {"data": [{"type": "builds", "id": bid}]})
        print("attached to", g["attributes"]["name"], "public" if g["attributes"].get("isInternalGroup") is False else "internal")
    locs = req(f"/builds/{bid}/betaBuildLocalizations")["data"]
    if locs:
        req(f"/betaBuildLocalizations/{locs[0]['id']}", "PATCH",
            {"data": {"type": "betaBuildLocalizations", "id": locs[0]["id"], "attributes": {"whatsNew": WHATS_NEW}}})
    else:
        req("/betaBuildLocalizations", "POST",
            {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": WHATS_NEW},
                      "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
    print("what to test set")
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
