#!/bin/zsh
# The 1.0.1 App Store set: six 6.9-inch shots from the RELEASE scheme, 1320 x 2868.
# Run from the repo root on an UNLOCKED Mac: a locked screen hangs every `simctl launch`.
# It builds the release scheme, makes its own simulator, stages each screen with the
# UI_* hooks of docs/testing.md, and deletes the simulator at the end. It never touches
# "iPhone 17 Pro" or any other existing device.
set -euo pipefail
ROOT=${0:A:h:h:h:h:h}
OUT=${0:A:h}
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

# Once: the fresh install, the fixture corpus and the example. The app takes ~75 s.
launch 120 UI_RESET=1 UI_IMPORT_FIXTURES=1 UI_LOAD_EXAMPLE=1

launch 20 UI_WELCOME=1;                                              shot 01-welcome.png
launch 25 UI_OPEN_SESSION=latest;                                    shot 02-session.png
launch 25 UI_OPEN_SESSION=latest UI_OPEN_TURNS=1;                    shot 03-turns.png
launch 25 UI_OPEN_SESSION=latest UI_OPEN_TURNS=1 UI_OPEN_TURN=3;     shot 04-turn.png
launch 20 UI_TAB=records;                                            shot 05-records.png
launch 30 UI_OPEN_SESSION=latest UI_SHEET=share UI_MAP=1 UI_STATS=complete
shot 06-share-card.png

sips -g pixelWidth -g pixelHeight "$OUT"/0*.png | grep pixel | sort | uniq -c
