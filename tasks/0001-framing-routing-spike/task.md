---
id: 0001
title: Framing + subject‑routing tracer‑bullet spike
type: spike
status: open
created: 2026-05-31
owner: unassigned
depends_on: [Q1 language ratification]
---

# Goal

De‑risk the central performance claim of the project end‑to‑end: that a keypress‑shaped
event can be routed from a publisher, through the hub, to N subscribers as a single
`write()` per subscriber — with **microsecond‑scale local dispatch, zero hot‑path
allocation, and no process spawn**. Validate the NWP framing and subject‑routing design
against `../../ai-docs/protocol.md` before committing to product code.

This is a *tracer bullet*: thinnest possible vertical slice, not production code. No OS
keyboard tap yet — a synthetic publisher stands in for the event tap.

## In scope

1. Hub that listens on an `AF_UNIX` `SOCK_STREAM` socket (PROTOCOL §3.1) and runs a
   non‑blocking `epoll`/`kqueue` loop (architecture.md §3).
2. Frame codec: newline‑delimited JSON — read up to `\n`, parse one JSON object, write a
   single‑line object + `\n` (PROTOCOL §4–5). Must handle partial and coalesced reads.
   SHOULD also exercise the opt‑in binary framing (Appendix A) for the allocation test
   below, since the precomputed‑line claim applies to both.
3. Minimal control plane: `hello`/`welcome`, `sub`, `pub`→`msg`.
4. Subject token trie with `*`/`>` wildcard matching (PROTOCOL §7.1).
5. Bounded per‑client send queue with `lossy` drop‑oldest (PROTOCOL §9).
6. A load harness: 1 synthetic publisher → hub → {1, 8, 64} subscribers, fixed‑rate and
   burst publishing.

## Out of scope

OS keyboard tap, Lua config, `BIND`/`MODE`/`exec`, TCP fallback, retained subjects, auth
beyond a peer‑cred check, Windows.

## Success criteria

- **Correctness:** every non‑dropped `msg` carries JSON‑exact `data` with the published
  payload; wildcard matches resolve exactly; line framing survives partial/coalesced reads
  (fuzz the reader).
- **Latency:** median publish→deliver under ~10 µs and p99 under ~50 µs for the 8‑subscriber
  case on a developer laptop; capture the full distribution, not just the mean (tail is the
  point — see PROTOCOL §10).
- **No hot‑path allocation:** demonstrate zero heap allocation per delivered frame (reused
  buffers), shown via allocator counters / profiler.
- **No spawns:** confirm zero `fork`/`exec` during steady‑state dispatch (e.g. `strace`/
  `dtruss`).
- **Backpressure:** a deliberately stalled subscriber loses frames per the `lossy` policy
  without affecting the latency of healthy subscribers.

## Deliverables

- `code/` — the spike implementation (throwaway PoC; language per Q1, or whichever core
  candidate is being evaluated — the spike may itself inform Q1).
- `FINDINGS.md` — measured numbers, the latency distribution, anything that should change
  in `ai-docs/protocol.md`/`architecture.md`, and a recommendation on whether the design holds.

## Notes

If run before Q1 is ratified, this spike MAY be implemented in two candidate languages
(e.g. Rust and C) to produce real comparative latency/footprint data feeding
`language-evaluation.md`.
