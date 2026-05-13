#!/usr/bin/env bash
# Open eww windows on each connected monitor.
# Called by the systemd service via ExecStartPost after the daemon is up.
#
# The 'active' variable uses deflisten with a synchronous first emit, so
# windows render with real data on first paint. No pre-poll workaround needed.

EWW="@@EWW_BIN@@"
RANDR="@@COSMIC_RANDR_BIN@@"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

monitor_count=$("$RANDR" list --kdl 2>/dev/null | grep -c '^output' || echo 1)

if [ "$monitor_count" -eq 0 ]; then
  monitor_count=1
fi

active_json=$("$SCRIPT_DIR/scan_active.py")
active_width=$(printf '%s' "$active_json" | python3 -c 'import json, sys; print(json.load(sys.stdin)["width_px"])')
active_height=$(printf '%s' "$active_json" | python3 -c 'import json, sys; print(json.load(sys.stdin)["height_px"])')
for _ in $(seq 1 20); do
  if "$EWW" update active="$active_json" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

for i in $(seq 0 $((monitor_count - 1))); do
  "$EWW" open journals-window --id "journals-$i" --arg monitor="$i"
  "$EWW" open active-window   --id "active-$i"   --arg monitor="$i" --arg active_width="$active_width" --arg active_height="$active_height"
done
