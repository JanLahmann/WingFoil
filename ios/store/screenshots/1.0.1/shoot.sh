#!/bin/zsh
# The 1.0.1 App Store set: six 6.9-inch shots from the RELEASE scheme, 1320 x 2868.
# Run from the repo root on an UNLOCKED Mac: a locked screen hangs every `simctl launch`.
# It builds the release scheme, makes its own simulator, stages each screen with the
# UI_* hooks of docs/testing.md, and deletes the simulator at the end. It never touches
# "iPhone 17 Pro" or any other existing device.
# OUT=<dir> writes the shots elsewhere (a smoke run, say); ONLY=<file> takes that one shot.
set -euo pipefail
ROOT=${0:A:h:h:h:h:h}
OUT=${OUT:-${0:A:h}}
ONLY=${ONLY:-}
mkdir -p "$OUT"
DD=${TMPDIR:-/tmp}/cj-shots-dd
BUNDLE=de.lahmann.wingfoil

if ioreg -n Root -d1 | grep -q '"CGSSessionScreenIsLocked"=Yes'; then
  echo "The screen is locked; simulator apps cannot launch. Unlock and run again." >&2
  exit 1
fi

(cd "$ROOT/ios" && xcodegen generate >/dev/null &&
 xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Release" -configuration Debug \
   -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" \
   CODE_SIGNING_ALLOWED=NO build -quiet)
APP="$DD/Build/Products/Debug-iphonesimulator/WingFoil.app"

UDID=$(xcrun simctl create "CleanJibe shots 6.9" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)
trap 'xcrun simctl shutdown $UDID 2>/dev/null; xcrun simctl delete $UDID' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

# launch <seconds to settle> KEY=VALUE ...
launch() {
  local wait=$1; shift
  xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
  env ${@/#/SIMCTL_CHILD_} xcrun simctl launch "$UDID" $BUNDLE >/dev/null
  sleep "$wait"
}
shot() { xcrun simctl io "$UDID" screenshot "$OUT/$1" >/dev/null; echo "$1"; }
# take <file> <seconds to settle> KEY=VALUE ... — skipped when ONLY names another shot.
take() {
  local file=$1; shift
  [[ -z $ONLY || $ONLY == $file ]] || return 0
  launch "$@"; shot "$file"
}

# Once: the fresh install, the fixture corpus and the example. The app takes ~75 s.
launch 120 UI_RESET=1 UI_IMPORT_FIXTURES=1 UI_LOAD_EXAMPLE=1

take 01-welcome.png 20 UI_WELCOME=1
take 02-session.png 25 UI_OPEN_SESSION=latest
take 03-turns.png   30 UI_OPEN_SESSION=latest UI_OPEN_TURNS=1 UI_SCROLL_TO=turnList
take 04-turn.png    25 UI_OPEN_SESSION=latest UI_OPEN_TURNS=1 UI_OPEN_TURN=3
take 05-records.png 20 UI_TAB=records
# Layout B v2 (26 Sep 2026) took the Lean/Complete presets and `UI_STATS` with them; the
# card's big number is `UI_HERO` now, and the shape is pinned so a stored choice cannot move it.
take 06-share-card.png 30 UI_OPEN_SESSION=latest UI_SHEET=share UI_MAP=1 UI_HERO=clean \
  UI_SHAPE=portrait

sips -g pixelWidth -g pixelHeight "$OUT"/0*.png | grep pixel | sort | uniq -c
