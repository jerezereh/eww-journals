#!/usr/bin/env bash
# Listener for ~/journals changes. Emits parsed active-thread JSON on startup
# and again on every file change.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOURNAL_DIR="${HOME}/journals"
PARSER="$SCRIPT_DIR/scan_active.py"
EWW="${EWW_BIN:-@@EWW_BIN@@}"
RANDR="${COSMIC_RANDR_BIN:-@@COSMIC_RANDR_BIN@@}"
DEBOUNCE_SECS="${LISTEN_DEBOUNCE_SECS:-0.3}"

# Helpful for debugging — uncomment to log events to stderr
# DEBUG=1

log() {
  if [ -n "${DEBUG:-}" ]; then
    printf 'listen_active: %s\n' "$*" >&2
  fi
}

emit() {
  log "emitting"
  json=$("$PARSER" | tr -d '\n')
  "$EWW" update active="$json" 2>/dev/null || true
  reopen_active_windows "$json"
  printf '%s\n' "$json"
}

json_field() {
  printf '%s' "$1" | python3 -c "import json, sys; print(json.load(sys.stdin)[$2])"
}

monitor_count() {
  count=$("$RANDR" list --kdl 2>/dev/null | grep -c '^output' || echo 1)
  if [ "$count" -eq 0 ]; then
    count=1
  fi
  printf '%s\n' "$count"
}

reopen_active_windows() {
  width=$(json_field "$1" '"width_px"')
  height=$(json_field "$1" '"height_px"')
  count=$(monitor_count)

  for i in $(seq 0 $((count - 1))); do
    "$EWW" open active-window \
      --id "active-$i" \
      --arg monitor="$i" \
      --arg active_width="$width" \
      --arg active_height="$height" \
      2>/dev/null || true
  done
}

# Ensure journals directory exists before watching
if [ ! -d "$JOURNAL_DIR" ]; then
  mkdir -p "$JOURNAL_DIR"
fi

# First emit — synchronous, before windows render.
emit

# Watch in a subshell that pipes events through a debounce filter.
# inotifywait emits one line per event. We collapse rapid bursts using
# `read -t` with a timeout: when no event arrives within DEBOUNCE_SECS,
# we know the burst is done and we emit once.
inotifywait -m -q -r \
  -e modify,create,delete,move,close_write \
  --format '%w%f %e' \
  "$JOURNAL_DIR" 2>/dev/null \
| {
  while IFS= read -r line; do
    log "event: $line"
    # Drain any additional events that arrive within DEBOUNCE_SECS.
    # When the read times out, the burst is over.
    while IFS= read -r -t "$DEBOUNCE_SECS" extra; do
      log "drained: $extra"
    done
    emit
  done
}
