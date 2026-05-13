#!/usr/bin/env bash
# eww-journals installer.
# Sets up eww configs, scripts, the systemd user service, and the journals directory.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EWW_CONFIG_DIR="${HOME}/.config/eww"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
JOURNAL_DIR="${HOME}/journals"

EWW_BIN="${EWW_BIN:-$(command -v eww || echo "${HOME}/.local/bin/eww")}"
COSMIC_RANDR_BIN="${COSMIC_RANDR_BIN:-$(command -v cosmic-randr || echo /usr/bin/cosmic-randr)}"
INOTIFYWAIT_BIN="${INOTIFYWAIT_BIN:-$(command -v inotifywait || echo /usr/bin/inotifywait)}"

say() { printf '\033[1;36m▶\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ─── Sanity checks ──────────────────────────────────────────────────────────

[ -x "$EWW_BIN" ] || fail "eww binary not found at $EWW_BIN. Set EWW_BIN env var or install eww first."
[ -x "$COSMIC_RANDR_BIN" ] || warn "cosmic-randr not found. launch.sh expects it; edit the script for your compositor."
[ -x "$INOTIFYWAIT_BIN" ] || fail "inotifywait not found. overlays will not update."
command -v python3 >/dev/null || fail "python3 not found. Install python3."

# ─── eww config and scripts ─────────────────────────────────────────────────

say "Installing eww config to $EWW_CONFIG_DIR"
mkdir -p "$EWW_CONFIG_DIR/scripts"

cp -v "$REPO_DIR/eww/eww.yuck" "$EWW_CONFIG_DIR/eww.yuck"
cp -v "$REPO_DIR/eww/eww.scss" "$EWW_CONFIG_DIR/eww.scss"

# Copy scripts and substitute paths
for script in scan_journals.sh scan_active.py launch.sh listen_active.sh; do
  src="$REPO_DIR/eww/scripts/$script"
  dst="$EWW_CONFIG_DIR/scripts/$script"
  sed \
    -e "s|@@EWW_BIN@@|$EWW_BIN|g" \
    -e "s|@@COSMIC_RANDR_BIN@@|$COSMIC_RANDR_BIN|g" \
    -e "s|@@HOME@@|$HOME|g" \
    "$src" > "$dst"
  chmod +x "$dst"
  echo "  installed $dst"
done

# ─── Journals directory ─────────────────────────────────────────────────────

if [ ! -d "$JOURNAL_DIR" ]; then
  say "Creating $JOURNAL_DIR"
  mkdir -p "$JOURNAL_DIR"
  cp -v "$REPO_DIR/templates/project-journal-template.md" "$JOURNAL_DIR/_template.md"
  say "A template journal was placed at $JOURNAL_DIR/_template.md (excluded from scans by leading underscore via convention; rename when starting a real journal)."
else
  say "$JOURNAL_DIR already exists, leaving alone"
fi

# ─── systemd user service ───────────────────────────────────────────────────

say "Installing systemd user service"
mkdir -p "$SYSTEMD_USER_DIR/default.target.wants"

sed \
  -e "s|@@EWW_BIN@@|$EWW_BIN|g" \
  -e "s|@@HOME@@|$HOME|g" \
  "$REPO_DIR/systemd/eww-journals.service" \
  > "$SYSTEMD_USER_DIR/eww-journals.service"

systemctl --user daemon-reload
systemctl --user enable eww-journals.service

# ─── Done ───────────────────────────────────────────────────────────────────

say "Installation complete."
echo
echo "To start now:    systemctl --user start eww-journals.service"
echo "To check status: systemctl --user status eww-journals.service"
echo "To see logs:     journalctl --user -u eww-journals.service -f"
echo
echo "The service is enabled and will start at next login."
