#!/bin/zsh
# One harness cycle on one simulator device, photographed frame by frame, deduplicated and
# tiled into one sheet. The harness (source/ShotsApp.mc, not committed) cycles the 17 screens
# every 3 s; this script starts a fresh simulator, runs the harness, captures the device
# window by its window id (the window lands wherever macOS last had it, on any display),
# and tiles the distinct frames six per row.
#
#   garmin/screenshots/tools/capture.sh <device> <outdir>
#
# Needs: the harness compiled for <device> at bin/shots-<device>.prg (see docs/testing.md,
# "Every family, photographed"), PIL for python3, swiftc for the window lister (built once).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
GARMIN=$(cd "$HERE/../.." && pwd)
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/$(ls "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" | sort | tail -1)/bin"
DEV=$1; OUT=$2; PRG="$GARMIN/bin/shots-$DEV.prg"
[ -f "$PRG" ] || { echo "no $PRG — compile the harness first"; exit 1; }
[ -x "$HERE/winfo" ] || swiftc -O -o "$HERE/winfo" "$HERE/winfo.swift"
pkill -f monkeydo || true; pkill -f "ConnectIQ.app/Contents/MacOS/simulator" || true; sleep 2
open "$SDK/ConnectIQ.app"; sleep 15
(nohup "$SDK/monkeydo" "$PRG" $DEV > "$OUT.log" 2>&1 &)
sleep 15
rm -rf "$OUT"; mkdir -p "$OUT"
for i in $(seq -w 1 56); do
  WID=$("$HERE/winfo" | head -1 | cut -d' ' -f1)
  [ -n "$WID" ] && screencapture -x -o -l $WID "$OUT/cap-$i.png"
  sleep 0.8
done
pkill -f monkeydo || true; pkill -f "ConnectIQ.app/Contents/MacOS/simulator" || true
python3 "$HERE/sheet.py" "$OUT" "$OUT.png"
