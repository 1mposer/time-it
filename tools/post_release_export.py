#!/usr/bin/env python3
"""Validate docs/post-release/items/*.yaml and export docs/post-release/backlog.csv.

Standard library only (no PyYAML on the owner's Mac). Reads the flat YAML subset the
schema documents: `key: value` scalars, `key: |` block strings, `key:` followed by
`  - item` lists, and `[]` for an empty list. Run `--check` to validate without writing.
"""
import csv, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "docs" / "post-release"
ITEMS = ROOT / "items"
OUT = ROOT / "backlog.csv"

ENUMS = {
    "type": {"Bug", "Enhancement", "Polish", "Decision"},
    "priority": {"Critical", "High", "Medium", "Low"},
    "status": {"Backlog", "Needs decision", "In progress", "Scheduled", "Done"},
    "area": {"Dashboard", "Detail", "Wizard", "Settings", "Location", "Notifications",
             "Opening", "Server", "Build", "Docs"},
    "effort": {"S", "M", "L"},
}
REQUIRED = ["id", "title", "type", "priority", "status", "area", "owner", "effort",
            "reported", "found_in", "source", "summary", "proposal", "acceptance"]
COLUMNS = [("id", "ID"), ("title", "Title"), ("type", "Type"), ("priority", "Priority"),
           ("status", "Status"), ("area", "Area"), ("owner", "Owner"), ("effort", "Effort"),
           ("reported", "Reported"), ("found_in", "Found in"), ("fixed_in", "Fixed in")]


def parse(text):
    data, lines, i = {}, text.splitlines(), 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1; continue
        m = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if not m:
            raise ValueError(f"unexpected line {i+1}: {line!r}")
        key, rest = m.group(1), m.group(2).strip()
        if rest == "|":
            block = []
            i += 1
            while i < len(lines) and (lines[i].startswith("  ") or not lines[i].strip()):
                block.append(lines[i][2:]); i += 1
            data[key] = "\n".join(block).rstrip()
            continue
        if rest == "":
            items = []
            i += 1
            while i < len(lines) and lines[i].startswith("  - "):
                items.append(lines[i][4:].strip()); i += 1
            data[key] = items
            continue
        data[key] = None if rest == "null" else ([] if rest == "[]" else rest.strip('"'))
        i += 1
    return data


def validate(path, data):
    errors = [f"{path.name}: missing {k}" for k in REQUIRED if k not in data or data[k] in (None, "", [])]
    for k, allowed in ENUMS.items():
        if data.get(k) not in allowed:
            errors.append(f"{path.name}: {k}={data.get(k)!r} not in {sorted(allowed)}")
    if not re.match(r"^PR-\d{3}$", str(data.get("id", ""))):
        errors.append(f"{path.name}: id {data.get('id')!r} is not PR-NNN")
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", str(data.get("reported", ""))):
        errors.append(f"{path.name}: reported {data.get('reported')!r} is not YYYY-MM-DD")
    if data.get("status") == "Needs decision" and not data.get("decision_needed"):
        errors.append(f"{path.name}: Needs decision without decision_needed")
    return errors


def main():
    check_only = "--check" in sys.argv
    rows, errors, seen = [], [], set()
    for path in sorted(ITEMS.glob("*.yaml")):
        data = parse(path.read_text())
        errors += validate(path, data)
        if data.get("id") in seen:
            errors.append(f"{path.name}: duplicate id {data['id']}")
        seen.add(data.get("id"))
        rows.append(data)
    if errors:
        print("\n".join(errors)); sys.exit(1)
    print(f"{len(rows)} items valid")
    if check_only:
        return
    with OUT.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow([c for _, c in COLUMNS])
        for r in rows:
            w.writerow([r.get(k) if r.get(k) is not None else "" for k, _ in COLUMNS])
    print(f"wrote {OUT.relative_to(ROOT.parents[1])}")


if __name__ == "__main__":
    main()
