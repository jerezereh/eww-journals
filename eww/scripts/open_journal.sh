#!/usr/bin/env bash
# Copy a fresh stop-note skeleton to the clipboard, then open the journal.

set -euo pipefail

path="${1:?journal path required}"

if [ ! -f "$path" ]; then
  printf 'open_journal: not a file: %s\n' "$path" >&2
  exit 1
fi

today=$(date '+%Y-%m-%d')
note=$(mktemp)
cleanup() {
  rm -f "$note"
}
trap cleanup EXIT

cat > "$note" << EOF_NOTE

### $today

**State:**

**Just did:**

**Next:**

**Threads:**

---
EOF_NOTE

if command -v wl-copy >/dev/null 2>&1; then
  wl-copy < "$note"
elif command -v xclip >/dev/null 2>&1; then
  xclip -selection clipboard < "$note"
elif command -v xsel >/dev/null 2>&1; then
  xsel --clipboard --input < "$note"
else
  printf 'open_journal: no clipboard command found; install wl-clipboard, xclip, or xsel\n' >&2
fi

xdg-open "$path" >/dev/null 2>&1 &
