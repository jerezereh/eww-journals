#!/usr/bin/env bash
# Open eww windows on each connected monitor.
# Called by the systemd service via ExecStartPost after the daemon is up.

EWW="@@EWW_BIN@@"
RANDR="@@COSMIC_RANDR_BIN@@"

# Count connected monitors. Adapt this line for non-COSMIC compositors:
#   wlr-randr: wlr-randr | grep -c '^[^ ]'
#   sway:      swaymsg -t get_outputs | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"
monitor_count=$("$RANDR" list --kdl 2>/dev/null | grep -c '^output' || echo 1)

if [ "$monitor_count" -eq 0 ]; then
  monitor_count=1
fi

for i in $(seq 0 $((monitor_count - 1))); do
  "$EWW" open journals-window --id "journals-$i" --arg monitor="$i"
  "$EWW" open active-window   --id "active-$i"   --arg monitor="$i"
done

# Force initial poll so windows render with real data, not placeholder JSON.
sleep 0.5
"$EWW" poll journals 2>/dev/null || true
"$EWW" poll active 2>/dev/null || true
