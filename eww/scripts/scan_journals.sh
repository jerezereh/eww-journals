#!/usr/bin/env bash
# Scans ~/journals/*.md (excluding active.md), outputs JSON sorted by mtime desc.

JOURNAL_DIR="${HOME}/journals"

if [ ! -d "$JOURNAL_DIR" ]; then
  echo "[]"
  exit 0
fi

mapfile -t entries < <(
  find "$JOURNAL_DIR" -maxdepth 2 -name "*.md" ! -name "active.md" ! -name "template.md" -printf "%T@\t%p\n" 2>/dev/null \
    | sort -rn
)

echo -n "["
first=true
now=$(date +%s)

for entry in "${entries[@]}"; do
  mtime_float="${entry%%$'\t'*}"
  path="${entry#*$'\t'}"
  mtime=${mtime_float%.*}
  name=$(basename "$path" .md)

  # Human-readable "time ago"
  diff=$(( now - mtime ))
  if   [ $diff -lt 60 ];     then ago="just now"
  elif [ $diff -lt 3600 ];   then ago="$((diff/60))m ago"
  elif [ $diff -lt 86400 ];  then ago="$((diff/3600))h ago"
  elif [ $diff -lt 604800 ]; then ago="$((diff/86400))d ago"
  else                            ago="$((diff/604800))w ago"
  fi

  # Pull "**Status:** <value>" from journal header.
  status=$(head -n 20 "$path" 2>/dev/null \
    | grep -m1 -i '^\*\*Status:\*\*' \
    | sed -E 's/^\*\*Status:\*\*[[:space:]]*//I' \
    | tr -d '\r' \
    | xargs \
    | tr '[:upper:]' '[:lower:]')
  [ -z "$status" ] && status="unknown"

  status_display=$(echo "$status" | tr '[:lower:]' '[:upper:]')

  $first || echo -n ","
  first=false

  name_esc=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
  ago_esc=$(printf '%s' "$ago" | sed 's/\\/\\\\/g; s/"/\\"/g')
  status_esc=$(printf '%s' "$status" | sed 's/\\/\\\\/g; s/"/\\"/g')
  status_display_esc=$(printf '%s' "$status_display" | sed 's/\\/\\\\/g; s/"/\\"/g')
  path_esc=$(printf '%s' "$path" | sed 's/\\/\\\\/g; s/"/\\"/g')

  printf '{"name":"%s","ago":"%s","status":"%s","status_display":"%s","path":"%s","mtime":%d}' \
    "$name_esc" "$ago_esc" "$status_esc" "$status_display_esc" "$path_esc" "$mtime"
done

echo "]"
