#!/usr/bin/env python3
"""
Scan ~/journals/*.md (excluding active.md), extract Next + threads from each
journal's most recent stop note, and distribute projects across columns.

Output format:
{
  "columns": [
    [
      {"type": "bucket", "label": "TODAY"},
      {"type": "project", "name": "...", "path": "...", "ago": "...", "next": "...", "threads": [...]},
      ...
    ],
    [...],  # column 2
    ...
  ]
}

Column count is determined by project count:
  1-4 projects: 1 column
  5-8 projects: 2 columns
  9+ projects: 3 columns
"""

import json
import math
import re
import sys
from datetime import date, datetime
from pathlib import Path

JOURNAL_DIR = Path.home() / "journals"
EXCLUDE = {"active.md"}

ENTRY_RE = re.compile(r"^###\s+(\d{4}-\d{2}-\d{2})\s*$")
THREAD_RE = re.compile(r"^-\s+(.+)$")
CLOSED_RE = re.compile(r"^\[(resolved\b|dropped\b)", re.IGNORECASE)

SLOT_NAMES = {"state", "just did", "next", "threads"}
MAX_COLUMNS = 3
COLUMN_WIDTH = 320
COLUMN_GAP = 16
PANEL_X_PADDING = 32
PANEL_Y_PADDING = 28
HEADER_HEIGHT = 24
BUCKET_HEIGHT = 26
PROJECT_HEADER_HEIGHT = 22
PROJECT_BLOCK_MARGIN = 16
NEXT_LINE_HEIGHT = 18
THREAD_LINE_HEIGHT = 15
MIN_WINDOW_HEIGHT = 72


def _normalize_header(line: str) -> str:
    return line.strip().replace("*", "").rstrip(":").strip().lower()


def _strip_header_prefix(line: str) -> str:
    m = re.match(
        r"^\*{0,2}(state|just did|next|threads)\*{0,2}\s*:?\s*\*{0,2}\s*(.*)$",
        line.strip(),
        re.IGNORECASE,
    )
    if m:
        return m.group(2).strip()
    return ""


def parse_journal(path: Path):
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return None

    entries = []
    for i, line in enumerate(lines):
        m = ENTRY_RE.match(line)
        if m:
            entries.append((i, m.group(1)))

    if not entries:
        return None

    try:
        latest_idx, latest_date_str = max(
            entries, key=lambda e: datetime.strptime(e[1], "%Y-%m-%d")
        )
    except ValueError:
        return None

    end_idx = len(lines)
    for j in range(latest_idx + 1, len(lines)):
        s = lines[j].strip()
        if s.startswith("### ") or s == "---":
            end_idx = j
            break

    entry_lines = lines[latest_idx + 1 : end_idx]

    threads: list[str] = []
    next_text = ""
    current_slot: str | None = None
    next_collected_lines: list[str] = []

    for line in entry_lines:
        stripped = line.strip()
        header = _normalize_header(stripped)

        if header in SLOT_NAMES:
            if current_slot == "next" and next_collected_lines:
                next_text = " ".join(next_collected_lines).strip()
                next_collected_lines = []
            current_slot = header
            continue

        inline_value = _strip_header_prefix(stripped)
        first_token = re.match(
            r"^\*{0,2}(state|just did|next|threads)\*{0,2}\s*:?",
            stripped,
            re.IGNORECASE,
        )
        if first_token and inline_value:
            slot = first_token.group(1).lower()
            if slot == "next":
                next_text = inline_value
                current_slot = "next-done"
            elif slot == "threads":
                current_slot = "threads"
            else:
                current_slot = slot
            continue

        if current_slot == "threads":
            m = THREAD_RE.match(stripped)
            if m:
                text = m.group(1).strip()
                if not CLOSED_RE.match(text):
                    threads.append(text)
        elif current_slot == "next":
            if stripped:
                next_collected_lines.append(stripped)

    if current_slot == "next" and next_collected_lines:
        next_text = " ".join(next_collected_lines).strip()

    try:
        entry_date = datetime.strptime(latest_date_str, "%Y-%m-%d").date()
    except ValueError:
        return None

    return entry_date, next_text, threads


def bucket_for(entry_date: date, today: date) -> str:
    delta = (today - entry_date).days
    if delta <= 0:
        return "TODAY"
    if delta <= 7:
        return "THIS WEEK"
    if delta <= 30:
        return "THIS MONTH"
    return "OLDER"


def ago_label(entry_date: date, today: date) -> str:
    delta = (today - entry_date).days
    if delta <= 0:
        return "today"
    if delta == 1:
        return "1d ago"
    if delta < 7:
        return f"{delta}d ago"
    if delta < 30:
        weeks = delta // 7
        return f"{weeks}w ago"
    months = delta // 30
    return f"{months}mo ago"


def column_count_for(project_count: int) -> int:
    if project_count <= 4:
        return 1
    if project_count <= 8:
        return 2
    return MAX_COLUMNS


def distribute(items: list[dict], col_count: int) -> list[list[dict]]:
    """
    Distribute items across columns. Items is a flat list of bucket and project
    entries in display order. A column should not end with a bucket label
    (orphan rule); if that would happen, push the label to the next column.
    """
    if col_count == 1:
        return [items]

    # First pass: equal-ish split by item count
    per_col = math.ceil(len(items) / col_count)
    columns: list[list[dict]] = []
    idx = 0
    for c in range(col_count):
        end = min(idx + per_col, len(items))
        columns.append(items[idx:end])
        idx = end

    # Second pass: fix orphan bucket labels at column ends.
    # Walk columns left-to-right; if a column ends with a bucket label, move
    # it to the start of the next column.
    for c in range(col_count - 1):
        while columns[c] and columns[c][-1].get("type") == "bucket":
            orphan = columns[c].pop()
            columns[c + 1].insert(0, orphan)

    # Filter out any columns that became empty (rare edge case)
    return [col for col in columns if col]


def estimated_line_count(text: str, chars_per_line: int) -> int:
    if not text:
        return 1
    return max(1, math.ceil(len(text) / chars_per_line))


def estimated_item_height(item: dict) -> int:
    if item.get("type") == "bucket":
        return BUCKET_HEIGHT

    if item.get("type") != "project":
        return 0

    # These estimates intentionally run a little tall. GTK/Eww can clip the
    # layer surface if the requested height is too optimistic.
    height = PROJECT_BLOCK_MARGIN + PROJECT_HEADER_HEIGHT
    height += estimated_line_count(item.get("next", ""), 48) * NEXT_LINE_HEIGHT
    for thread in item.get("threads", []):
        height += estimated_line_count(thread, 54) * THREAD_LINE_HEIGHT
    return height


def estimated_column_height(column: list[dict]) -> int:
    return sum(estimated_item_height(item) for item in column)


def geometry_for(columns: list[list[dict]]) -> dict[str, int | str]:
    col_count = max(1, len(columns))
    content_width = col_count * (COLUMN_WIDTH + COLUMN_GAP)
    content_height = max((estimated_column_height(col) for col in columns), default=0)
    width = content_width + PANEL_X_PADDING
    height = max(MIN_WINDOW_HEIGHT, content_height + PANEL_Y_PADDING + HEADER_HEIGHT)

    return {
        "width": width,
        "height": height,
        "width_px": f"{width}px",
        "height_px": f"{height}px",
        "column_width": COLUMN_WIDTH,
        "column_width_px": f"{COLUMN_WIDTH}px",
    }


def main():
    today = date.today()

    if not JOURNAL_DIR.is_dir():
        json.dump({"columns": []}, sys.stdout)
        return

    bucketed: dict[str, list[dict]] = {}

    for path in sorted(JOURNAL_DIR.rglob("*.md")):
        if path.name in EXCLUDE:
            continue
        result = parse_journal(path)
        if result is None:
            continue
        entry_date, next_text, threads = result
        if not threads and not next_text:
            continue
        bucket = bucket_for(entry_date, today)
        bucketed.setdefault(bucket, []).append({
            "type": "project",
            "name": path.stem,
            "path": str(path),
            "ago": ago_label(entry_date, today),
            "next": next_text,
            "threads": threads,
        })

    # Flatten into ordered sequence of bucket labels + projects
    bucket_order = ["TODAY", "THIS WEEK", "THIS MONTH", "OLDER"]
    flat: list[dict] = []
    project_count = 0
    for label in bucket_order:
        if label not in bucketed:
            continue
        flat.append({"type": "bucket", "label": label})
        for proj in sorted(bucketed[label], key=lambda p: p["name"]):
            flat.append(proj)
            project_count += 1

    col_count = column_count_for(project_count)
    columns = distribute(flat, col_count)

    output: dict[str, object] = {"columns": columns}
    output.update(geometry_for(columns))

    json.dump(output, sys.stdout)


if __name__ == "__main__":
    main()
