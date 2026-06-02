# Tasks

Every discrete unit of work on **{{PROJECT}}** — spikes, milestones, chores — lives here as
a **task folder**, regardless of type. This is the live view of *what is being worked on*;
durable *design* truth lives in [`ai-docs/`](../ai-docs/), which tasks link back to via their
`resolves:` / `decisions:` fields.

## Current tasks

| Task | Type | Status | Verdict | Resolves | Decisions |
|---|---|---|---|---|---|
| _none yet_ | | | | | |

## Layout

Each task is a folder named by its `id`:

```
tasks/<id>/
  task.md        # REQUIRED — stateful frontmatter + the brief / description
  FINDINGS.md    # optional — results/report once the task produces them
  code/          # optional — throwaway PoC/research code (NOT the product)
```

`code/` is present only for PoC / research / testing tasks (e.g. spikes). Real product code
lives under `Sources/` at the repo root, never under `tasks/`.

## Frontmatter schema

Every `task.md` starts with YAML frontmatter:

```yaml
---
id: my-task-id                    # kebab-case, matches the folder name
name: Human-readable task title
type: spike                       # spike | milestone | chore
status: ready                     # draft | ready | in-progress | blocked | complete | superseded
verdict: n/a                      # spikes: GO | NO-GO | n/a ; others: n/a
created: {{DATE}}
updated: {{DATE}}
resolves: [Q1]                    # open-questions this task closes (see ai-docs/open-questions.md)
decisions: [D2]                   # decisions it produced (see ai-docs/decisions.md)
depends_on: []                    # other task ids this one builds on
artifacts: ./code                 # path to runnable code, or null
findings: ./FINDINGS.md           # path to the results doc, or null
---
```

### `status` values

- **draft** — being written, not ready to pick up.
- **ready** — fully specified, ready to start.
- **in-progress** — actively being worked.
- **blocked** — waiting on a dependency or decision.
- **complete** — done; results captured (and `decisions:` / `resolves:` folded into the KB).
- **superseded** — replaced by another task; keep for history, point to the replacement.

## Adding a task

1. Create `tasks/<id>/task.md` with the frontmatter above (`status: draft` or `ready`).
2. Add a row to the table in this file.
3. When it lands, set `status: complete`, fill `verdict` / `findings`, and record any
   `decisions:` / `resolves:` into [`ai-docs/`](../ai-docs/) **in the same change** (see
   [CLAUDE.md](../CLAUDE.md)).

> Write a spike's brief **self-contained for an autonomous agent** ("you have no prior
> context; everything you need is below"), and label any throwaway de-risking code as *not
> the product*.
