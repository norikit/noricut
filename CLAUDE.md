# CLAUDE.md — entry point for agents working in noricut

<!-- norikit:managed — synced from `template/CLAUDE.md`; do NOT hand-edit.
     Change the template and re-run sync_scaffold. Edit only the project region below. -->

**Read this, then the operating manual.** You are working in a repo of the **norikit** org.

## ⇒ The operating manual

**[`norikit/ai-docs/framework.md`](https://github.com/norikit/norikit/blob/main/ai-docs/framework.md)**
is the single entry point for *how we work* — task tracking, the working agreement, branching, and
quality. Read it before substantive work. The ecosystem mission/conventions live in
[`norikit/ai-docs/`](https://github.com/norikit/norikit/tree/main/ai-docs); this repo's design
knowledge lives in [`ai-docs/`](ai-docs/).

## The essentials (do not violate)

- **Work within the project — no code without a tracked issue.** Find/create a GitHub issue on the
  right board, meet Definition of Ready (typed · Priority + Size · rich description), pull one to
  In Progress, then work. Decompose big asks into an epic + sub-issues first. **GitHub issues are the
  source of truth.**
- **Always branch, always PR — never commit to `main`.** Branch off fresh `origin/main` as
  `<type>/<issue#>-<slug>` (`type ∈ feat, fix, chore, spike, docs`); Conventional-Commit messages; open
  a PR that `Closes #<issue>`; squash-merge after the gates pass (a deliberate human click — no auto-merge).
- **Standalone-first.** This tool must work on its own; ecosystem integrations (noricore, noriglaze, …)
  are optional, availability-gated enhancements — never hard dependencies.
- **Keep `ai-docs/` current in the same change.** If you change reality, change the knowledge base in the
  same PR. Stale docs are worse than none.
- **Definition of Done:** merged via PR · `ai-docs` updated · CI green · behavior **verified** (not just
  green CI) · standalone-first respected · no token/scaffold leftovers. (The issue form carries the checklist.)

## Conventions

- Match surrounding code style; favor clarity and low-latency, main-thread-safe code.
- Throwaway PoC/spike code lives in `tasks/<id>/code/` and is **not** the product; real product code
  lives under `Sources/`.
- License: **AGPL-3.0**.

<!-- /norikit:managed -->

<!-- norikit:project:start — this repo's own content; sync never overwrites between these markers. -->

## This project: noricut

**noricut** — a cross-app hotkey and shortcut daemon. A keypress is a socket write, not a process
spawn. The normative wire protocol (NWP) is specified in **[ai-docs/protocol.md](ai-docs/protocol.md)**.

Durable design knowledge lives in **[`ai-docs/`](ai-docs/)** — decisions · architecture ·
open-questions · status · glossary, plus **[protocol.md](ai-docs/protocol.md)** (NWP spec) and
**[language-evaluation.md](ai-docs/language-evaluation.md)**. Read **[decisions.md](ai-docs/decisions.md)** first.

### Locked decisions (see [ai-docs/decisions.md](ai-docs/decisions.md))

- **Standalone-first** — runs as an independent daemon; ecosystem integration is optional, availability-gated.
- **Hub/broker topology**, one OS event tap (D1) · **no process spawn on the hot path** (D2) · Unix-domain
  `SOCK_STREAM`, TCP-loopback opt-in (D3) · newline-delimited JSON default, length-prefixed binary opt-in (D13).
- **Subject-only routing** with `*`/`>` wildcards (D5/D6) · embedded hot-reloadable **Lua** config (D8) · AGPL-3.0.
- **Implementation language is NOT yet locked (Q1)** — do not write product code until ratified; de-risking
  spikes only, under `tasks/<id>/code/`.

<!-- norikit:project:end -->
