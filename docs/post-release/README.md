# Post-release backlog — typed mini-briefs

One `.yaml` per out-of-scope enhancement, bug or decision that the owner parked during the build-10 round (owner rule, 2026-11-12: "park it in a post-release folder; mini briefs, typed, so I can act on them with code later"). Not a status home — [ROADMAP](../issues/ROADMAP.md) stays the single home for scheduled work; an item leaves this folder by getting a ROADMAP row (set `status: scheduled` and link the row in the same commit).

- **Schema:** [`schema.yaml`](schema.yaml) — every field, its type and allowed values. Items that break it fail the export.
- **Items:** [`items/`](items/) — `PR-NNN-slug.yaml`, IDs never reused.
- **Export:** `python3 tools/post_release_export.py` → `docs/post-release/backlog.csv` (the owner's spreadsheet columns: ID, Title, Type, Priority, Status, Area, Owner, Effort, Reported, Found in, Fixed in); `--check` validates only. Standard library only — no PyYAML on this Mac — so items use the flat subset the script documents (one `key: value` per line, `|` blocks for prose, `- ` lists for links/sources).

Field meanings follow the owner's sheet mock (2026-11-12): **Type** Bug / Enhancement / Polish / Decision; **Priority** Critical / High / Medium / Low; **Status** Backlog / Needs decision / In progress / Scheduled / Done; **Effort** S / M / L; **Found in** the marketing version + build the item was observed on.
