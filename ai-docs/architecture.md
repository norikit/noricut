# Architecture (evolving)

How noricut is structured. Locked invariants live in `decisions.md`; the wire contract is
`../PROTOCOL.md`. This document is allowed to change as the design matures.

---

## 1. The two halves

noricut deliberately splits into a **portable broker core** and a thin **OS event‑tap
frontend**. They are separated because they have opposite constraints:

| | Broker core | Event‑tap frontend |
|--|-------------|--------------------|
| Concern | sockets, routing, queues, backpressure | reading the OS keyboard, chord matching |
| Portability | one codebase for all OSes | one implementation per OS, privileged |
| Risk | concurrency / memory safety of a long‑lived multi‑client daemon | OS API quirks, accessibility permissions |
| Language pressure | safe, fast, small static binary | native to the platform (e.g. Swift on macOS, shares idioms with noribar) |

The frontend is, to the broker, just another `BIND`+`PUB` client — it could even live in
a separate process. Keeping the boundary at the protocol means the macOS tap (CGEventTap)
and a Linux tap (evdev/libinput) are interchangeable behind the same `key.*` subjects.

```
┌────────────────────────── noricut process ──────────────────────────┐
│                                                                      │
│   OS event tap  ──chord match──▶  binding table ──▶ subject router   │
│   (CGEventTap /                       (trie)            (trie)        │
│    evdev / …)                                            │           │
│                                                          ▼           │
│   Lua config  ──▶ binding/mode registry          per‑client send     │
│   (hot reload)                                     queues (bounded)   │
│                                                          │           │
└──────────────────────────────────────────────────────────┼─────────┘
                                                            ▼
                              AF_UNIX SOCK_STREAM  ◀──▶  clients
                              (noribar, window mgr, your scripts)
```

## 2. Core data structures

- **Binding table** — a trie keyed by `(modifiers, keycode)` → subject (+ optional mode
  scope, optional `exec` payload). Built from Lua config and from runtime `BIND` requests.
  Chord match is O(1) on the resolved keycode.
- **Subject router** — a token trie over dotted subjects with `*`/`>` wildcard edges. A
  publish walks the trie once, collecting the set of subscriber connections. O(tokens),
  independent of subscriber count.
- **Connection** — fd + role mask + negotiated caps + a bounded outgoing frame queue +
  the set of subscriptions it owns. Cleaned up atomically on disconnect (subscriptions
  and bindings released; `noricut.client.gone` published).
- **Retained store** — last `RETAINED` frame per subject (e.g. current mode), replayed to
  new matching subscribers.

## 3. The event loop

A single‑threaded, non‑blocking reactor (`kqueue` on macOS/BSD, `epoll` on Linux,
`IOCP`/`WSAPoll` on Windows). One thread is intentional: the routing work per event is
tiny, and a single loop sidesteps lock contention and ordering hazards. The event tap, if
in‑process, feeds the same loop via a self‑pipe / event source so chord matches and socket
I/O are serialized without locks.

Hot‑path budget per key event: trie lookup → build one frame → `writev` to N fds. No
heap allocation (frame buffers are reused), no payload parse.

## 4. Backpressure (see PROTOCOL §9)

Each connection has a bounded queue. Writes are non‑blocking; when the kernel socket
buffer is full the frame sits in the queue, drained on `EPOLLOUT`/writable. Overflow
triggers the per‑subscription policy (`lossy` drop‑oldest vs `reliable` disconnect). The
accept/dispatch loop never blocks on a single slow client — this bounds tail latency,
which is the real advantage over `fork/exec`.

## 5. Configuration & hot reload

Lua config declares bindings, modes, and (optionally) in‑process handlers:

```lua
-- bind a chord to a subject; long‑running subscribers react in‑process
noricut.bind("cmd - h",        "key.focus.west")
noricut.bind("cmd - j",        "key.focus.south")

-- a sticky mode layer (skhd‑style)
noricut.mode("resize", function(m)
  m.bind("h", "key.resize.shrink_x")
  m.bind("l", "key.resize.grow_x")
  m.bind("escape", function() m.exit() end)
end)
noricut.bind("cmd - r", function() noricut.enter("resize") end)

-- escape hatch: still allowed, explicitly off the hot path
noricut.bind("cmd - return", { exec = "open -na Alacritty" })

-- in‑process Lua handler (no external subscriber needed)
noricut.on("key.focus.west", function(e)
  -- e.data.chord, e.meta.ts, …
end)
```

Editing `config.lua` while noricut runs reparses bindings and atomically swaps the binding
table; existing connections and subscriptions are untouched. A `noricut.reload` event is
published so subscribers can refresh derived state.

## 6. Client libraries

With NDJSON as the default wire (D13), a client *is* "read a line, parse JSON, write a
line" — so there is no mandatory client library to write or maintain, and no FFI. Inline
implementation is the supported, documented path (see PROTOCOL §11 for full Node and
Python subscribers in ~8 lines each). The project will still ship **optional** idiomatic
convenience wrappers where ergonomics help adoption:

- Thin, native wrappers (Swift for noribar, plus at least one of Rust/Go/Python) — each
  implemented directly on the language's stdlib sockets + JSON, not on a shared C ABI.
- noribar integration mirrors its own provider API: `bar.subscribe("key.focus.west", cb)`
  resolves to an NWP subscription under the hood.

The convenience surface is intentionally tiny: `connect`, `subscribe(pattern, cb)`,
`publish(subject, data)`, `bind(chord, subject)`, `request(subject, data) → ack`. A C‑ABI
`libnwp` is no longer on the critical path; it may still be offered later for languages
that prefer linking over a few lines of socket code, and for the opt‑in binary framing
(PROTOCOL Appendix A) where a shared codec earns its keep.

## 7. Platform notes

- **macOS:** event tap via `CGEventTap` (needs Accessibility permission); Swift frontend
  can share idioms/tooling with noribar. `LOCAL_PEERCRED` for auth. Socket under `$TMPDIR`.
- **Linux:** tap via `evdev`/`libinput` (needs input‑group/udev access) or a Wayland/X
  shortcuts portal where global taps are restricted; `SO_PEERCRED` for auth; socket under
  `$XDG_RUNTIME_DIR`; abstract‑namespace option.
- **Windows:** low‑level keyboard hook (`WH_KEYBOARD_LL`); `AF_UNIX` since Win10 1803, TCP
  fallback otherwise.

These taps are explicitly future spikes; v1 of *this repo* specifies the protocol and
broker so the taps can be built against a stable contract.
