# noricut: project structure & conventions

Guidance for AI agents and contributors. noricut follows the same working model as
[noribar](https://github.com/norikit/noribar).

## Documentation & knowledge management

**Single source of truth:** durable design lives in `docs/knowledge-base/`, read in this
order:
1. `decisions.md` — locked architectural choices
2. `architecture.md` — evolving system design
3. `language-evaluation.md` — implementation‑language analysis (core is Rust‑leaning, pending Q1)
4. `open-questions.md` — undecided items
5. `status.md` — current phase + changelog
6. `glossary.md` — terminology

The normative wire‑protocol spec is `docs/PROTOCOL.md`.

**Standing instruction:** whenever you make a decision, land a change, or learn something
durable, update the knowledge base **in the same change**. Record resolved questions,
meaningful progress, and user‑facing updates. A change to `PROTOCOL.md` MUST be reflected
in `decisions.md`.

## Locked architectural constraints

See `decisions.md` for the full list with rationale. The load‑bearing ones:
- **Hub/broker topology**, one OS event tap (D1).
- **No process spawn on the hot path** — a keypress is a socket write (D2).
- **Transport:** Unix‑domain `SOCK_STREAM`; TCP loopback opt‑in fallback (D3).
- **Framing:** `u32` little‑endian length prefix, fixed‑offset header (D4).
- **Content‑agnostic routing:** payloads opaque; default `kv` envelope (D5).
- **Subjects:** dotted tokens with `*`/`>` wildcards (D6).
- **Config:** embedded, hot‑reloadable Lua (D8).
- **License:** AGPL‑3.0 (D11).

The broker core's implementation language is **not yet locked** (Q1); do not write product
code until it is ratified.

## Git workflow

**Standing instruction:** never commit directly to `main`.
- Branch off an up‑to‑date `origin/main`; sync (`git fetch origin`) before branching.
- Open a PR when complete and treat the PR as the deliverable; keep its title/body current.
- Push with `git push -u origin <branch>`.

## Code style & conventions

- Favor clarity and low‑latency, allocation‑free code on the hot path; match surrounding
  style once a language is chosen.
- All work items (spikes, tasks, chores) live under `tasks/` as folders containing a
  `task.md` (frontmatter + brief). Optional `FINDINGS.md` and `code/` (PoC research only).
- Product code will live under `src/` (or the language's idiomatic root) at repo root once
  Q1 closes; keep PoC code inside its task folder until then.
- The de‑risking‑spike‑before‑product‑code methodology from noribar applies here too.
