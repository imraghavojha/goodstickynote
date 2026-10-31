#!/bin/zsh
# Measures launch-to-ready time, memory footprint and idle CPU on an isolated fixture library.
# Usage: scripts/bench.sh [path/to/GoodSticky.app] [visible-note-count]
set -euo pipefail
cd "${0:A:h:h}"
APP="${1:-dist/GoodSticky.app}"
COUNT="${2:-10}"
BIN="$APP/Contents/MacOS/GoodSticky"
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/Attachments"
sips -s format png -Z 900 "/System/Library/Desktop Pictures/.thumbnails/Big Sur Coastline.heic" --out "$FIXTURE/Attachments/photo.png" >/dev/null 2>&1 || true
python3 - "$FIXTURE" "$COUNT" <<'PY'
import json, sys, uuid, datetime
root, count = sys.argv[1], int(sys.argv[2])
now = (datetime.datetime.now() - datetime.datetime(2001, 1, 1)).total_seconds()
themes = ["butter", "sage", "rose", "sky", "lilac", "linen", "graphite"]
notes = []
for i in range(count + 2):
    n = {"id": str(uuid.uuid4()).upper(), "text": f"Note {i}\n" + "A line of text for the benchmark. " * 12, "themeID": themes[i % 7],
         "opacity": 1.0, "x": 60 + (i % 5) * 240, "y": 120 + (i // 5) * 200, "width": 220, "height": 180,
         "hidden": i >= count, "pinned": False, "attachments": [], "created": now, "modified": now}
    if i == 0: n["attachments"] = [{"id": str(uuid.uuid4()).upper(), "name": "photo.png", "storedName": "photo.png"}]; n["height"] = 280
    notes.append(n)
json.dump({"notes": notes, "preferences": {"keyCode": 45, "modifiers": 6144, "defaultTheme": "butter", "defaultOpacity": 1.0, "desktopLayoutVersion": 2}}, open(f"{root}/notes.json", "w"))
PY
export GOODSTICKY_DATA_DIR="$FIXTURE"
START=$(python3 -c 'import time; print(time.time())')
"$BIN" >"$FIXTURE/out.log" 2>&1 &
PID=$!
# Ready = all visible note windows are on screen.
python3 - "$PID" "$COUNT" "$START" <<'PY'
import sys, time, subprocess
pid, count, start = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
src = 'import CoreGraphics\nlet a = CommandLine.arguments\nlet i = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []\nprint(i.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(a[1]) && ($0[kCGWindowLayer as String] as? Int ?? 0) < 0 }.count)\n'
import os, tempfile
exe = os.path.join(tempfile.gettempdir(), "gs-wincount")
if not os.path.exists(exe):
    open(exe + ".swift", "w").write(src); subprocess.run(["swiftc", "-O", exe + ".swift", "-o", exe], check=True, capture_output=True)
while time.time() - start < 15:
    n = int(subprocess.run([exe, pid], capture_output=True, text=True).stdout.strip() or 0)
    if n >= count: print(f"ready_ms={int((time.time() - start) * 1000)}"); break
    time.sleep(0.01)
else: print("ready_ms=timeout")
PY
sleep 6
FOOT=$(footprint "$PID" 2>/dev/null | sed -nE 's/.*Footprint: ([0-9.]+ [KMG]B).*/\1/p' | head -1)
CPU0=$(ps -o time= -p "$PID")
sleep 15
CPU1=$(ps -o time= -p "$PID")
RSS=$(ps -o rss= -p "$PID")
kill "$PID"; wait "$PID" 2>/dev/null || true
print "footprint=$FOOT rss_kb=$RSS cpu_before_idle=$CPU0 cpu_after_15s_idle=$CPU1"
