# Status

Current phase and changelog. Newest first.

## Phase

**P0 — Protocol & architecture design.** No product code yet. This mirrors how noribar
began: lock the durable design and de‑risk before writing the daemon. The deliverable of
this phase is a complete, implementable wire‑protocol spec plus the knowledge base and the
first spike brief.

### Done
- noricut Wire Protocol (NWP) v1 specified (`../PROTOCOL.md`).
- Architecture split into portable broker core + per‑OS event‑tap frontends
  (`architecture.md`).
- Locked decisions D1–D13 recorded (`decisions.md`).
- Implementation‑language comparison written; **Rust recommended** for the core, Swift for
  the macOS frontend (`language-evaluation.md`).
- First spike brief drafted: end‑to‑end framing + routing PoC (`../../tasks/`).

### Next
- Owner ratifies the core language (open question Q1).
- Run the framing/routing spike to validate the hot‑path latency claim end‑to‑end.
- Resolve Q3 (Linux tap strategy) and Q5 (`exec` sidecar vs in‑hub) before frontend work.

## Changelog

### 2026‑05‑31
- **Wire encoding switched to newline‑delimited JSON (NDJSON) as the default** (new D13;
  supersedes D4, amends D5). Rationale: make third‑party integration trivial in any
  language with no client library or FFI — "read a line, parse JSON, write a line," ~8
  lines (PROTOCOL §11). The length‑prefixed binary framing survives as an opt‑in
  (`framing=binary`, PROTOCOL Appendix A) for byte‑exact/large payloads; the hot path is
  unaffected (per‑binding lines are precomputable). Updated PROTOCOL.md, decisions.md,
  architecture.md, glossary.md.
- Repository bootstrapped from empty: README, CLAUDE.md, knowledge base, PROTOCOL.md,
  language evaluation, and the first task/spike. Design phase opened.
