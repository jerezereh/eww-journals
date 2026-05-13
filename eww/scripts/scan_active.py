#!/usr/bin/env python3
"""
Scan ~/journals/*.md (excluding active.md), extract open threads from each
journal's most recent stop note, output JSON bucketed by entry age.

Output format:
{
  "buckets": [
    {
      "label": "TODAY",
      "projects": [{"name": "govtools", "path": "/home/.../govtools.md", "threads": ["...", "..."]}]
    },
    ...
  ]
}
"""

import json
import re
import sys
from datetime import date, datetime
from pathlib import Path

JOURNAL_DIR = Path.home() / "journals"
EXCLUDE = {"active.md"}

ENTRY_RE = re.compile(r"^###\s+(\d{4}-\d{2}-\d{2})\s*$")
THREAD_RE = re.compile(r"^-\s+(.+)$")
CLOSED_RE = re.compile(r"^\[(resolved\b|dropped\b)", re.IGNORECASE)

OTHER_SLOTS = {"state", "just did", "next"}


def _normalize_header(line: str) -> str:
    """Forgiving header matching — accepts '**Threads:**', '**Threads**:', etc."""
    return line.strip().replace("*", "").rstrip(":").strip().lower()


def parse_journal(path: Path):
    """Return (entry_date, [open_thread_lines]) for the most recent entry, or None."""
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

    threads = []
    in_threads = False
    for line in entry_lines:
        header = _normalize_header(line)
        if header == "threads":
            in_threads = True
            continue
        if header in OTHER_SLOTS:
            if in_threads:
                break
            continue
        if not in_threads:
            continue
        m = THREAD_RE.match(line.strip())
        if m:
            text = m.group(1).strip()
            if CLOSED_RE.match(text):
                continue
            threads.append(text)

    try:
        entry_date = datetime.strptime(latest_date_str, "%Y-%m-%d").date()
    except ValueError:
        return None

    return entry_date, threads


def bucket_for(entry_date: date, today: date) -> str:
    delta = (today - entry_date).days
    if delta <= 0:
        return "TODAY"
    if delta <= 7:
        return "THIS WEEK"
    if delta <= 30:
        return "THIS MONTH"
    return "OLDER"


def main():
    today = date.today()

    if not JOURNAL_DIR.is_dir():
        json.dump({"buckets": []}, sys.stdout)
        return

    # bucket -> {project_name: {"path": str, "threads": list}}
    bucketed: dict[str, dict[str, dict]] = {}

    for path in sorted(JOURNAL_DIR.rglob("*.md")):
        if path.name in EXCLUDE:
            continue
        result = parse_journal(path)
        if result is None:
            continue
        entry_date, threads = result
        if not threads:
            continue
        bucket = bucket_for(entry_date, today)
        project = path.stem
        entry = bucketed.setdefault(bucket, {}).setdefault(
            project, {"path": str(path), "threads": []}
        )
        entry["threads"].extend(threads)

    bucket_order = ["TODAY", "THIS WEEK", "THIS MONTH", "OLDER"]
    output = {"buckets": []}
    for label in bucket_order:
        if label not in bucketed:
            continue
        projects = [
            {"name": name, "path": data["path"], "threads": data["threads"]}
            for name, data in sorted(bucketed[label].items())
        ]
        output["buckets"].append({"label": label, "projects": projects})

    json.dump(output, sys.stdout)


if __name__ == "__main__":
    main()
