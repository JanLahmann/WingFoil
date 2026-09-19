#!/bin/zsh
# The three streams from one commit, one version (docs/channels.md, "The watch"):
#   bin/CleanJibe-release-<v>.iq   monkey.jungle        app id b1ef484c  the public listing
#   bin/CleanJibe-beta-<v>.iq      monkey-beta.jungle   app id 28942317  the open beta
#   bin/CleanJibe-dev-<v>-devN.iq  monkey-dev.jungle    app id 953f7547  the private listing
# Usage: garmin/tools/package.sh [N]   — N is the dev suffix (default 1); the version comes
# from manifest.xml, which the three manifests keep identical.
set -e
cd "$(dirname "$0")/.."
# The SDK is PINNED, not "the newest folder": `ls | sort | tail -1` is a lexicographic sort
# and would pick 9.2.0 over a future 10.x (docs/engineering.md, item 8). Bump the pin on
# purpose, after the unit suite has run on the new SDK.
SDK_VERSION="connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/$SDK_VERSION/bin"
[ -x "$SDK/monkeyc" ] || { echo "Connect IQ SDK $SDK_VERSION is not installed (SDK Manager)"; exit 1; }
V=$(grep -o 'entry="WingfoilApp" version="[0-9.]*"' manifest.xml | cut -d'"' -f4)
N=${1:-1}
for m in manifest-beta.xml manifest-dev.xml; do
  grep -q "entry=\"WingfoilApp\" version=\"$V\"" $m || { echo "$m is not at $V"; exit 1; }
done
mkdir -p bin
"$SDK/monkeyc" -e -r -f monkey.jungle      -y developer_key.der -o bin/CleanJibe-release-$V.iq
"$SDK/monkeyc" -e -r -f monkey-beta.jungle -y developer_key.der -o bin/CleanJibe-beta-$V.iq
"$SDK/monkeyc" -e -r -f monkey-dev.jungle  -y developer_key.der -o bin/CleanJibe-dev-$V-dev$N.iq
ls -la bin/CleanJibe-release-$V.iq bin/CleanJibe-beta-$V.iq bin/CleanJibe-dev-$V-dev$N.iq | awk '{print $5, $9}'
