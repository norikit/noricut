---
paths:
  - "CLAUDE.md"
  - ".github/ISSUE_TEMPLATE/**"
---

# These files are managed by the norikit scaffold — do not hand-edit

`CLAUDE.md`'s `<!-- norikit:managed -->` block and everything under
`.github/ISSUE_TEMPLATE/` are **synced from the `template` repo** by
`norikit/tools/sync_scaffold.py`. Hand edits here are silently reverted on the
next sync.

**To change them:** edit the file in **`template/`** and run
`python3 tools/sync_scaffold.py` from the `norikit` repo — the change then fans
out to every repo.

**The one part you _may_ edit** is this repo's own content between the
`<!-- norikit:project:start -->` / `<!-- norikit:project:end -->` markers in
`CLAUDE.md`. Sync never touches that region.

> This rule itself is managed (synced from `template/.claude/rules/`). Same rule:
> change it in `template`, not here.
