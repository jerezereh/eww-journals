#!/usr/bin/env bash
# Open a scratch copy of the journal template with the default editor.

set -euo pipefail

JOURNAL_DIR="${HOME}/journals"
TEMPLATE_PATH="@@TEMPLATE_PATH@@"
SCRATCH_DIR="${XDG_RUNTIME_DIR:-/tmp}/eww-journals"

mkdir -p "$JOURNAL_DIR"

template=""
for candidate in \
  "$JOURNAL_DIR/template.md" \
  "$JOURNAL_DIR/_template.md" \
  "$TEMPLATE_PATH"; do
  if [ -f "$candidate" ]; then
    template="$candidate"
    break
  fi
done

if [ -z "$template" ]; then
  printf 'create_journal: no template found\n' >&2
  exit 1
fi

mkdir -p "$SCRATCH_DIR"

stamp=$(date '+%Y%m%d-%H%M%S')
path="$SCRATCH_DIR/new-journal-template-$stamp.md"

cp "$template" "$path"
xdg-open "$path" >/dev/null 2>&1 &
