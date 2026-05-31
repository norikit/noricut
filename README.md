# noricut

A fast, native keyboard‑shortcut daemon for the [norikit](https://github.com/norikit)
toolchain — built so a keypress turns into an **action in an already‑running app**,
not a freshly spawned process.

> **Status:** Design phase. This repository currently contains the protocol
> specification and architecture knowledge base. No daemon code has landed yet —
> see [`docs/knowledge-base/status.md`](docs/knowledge-base/status.md).

## Why noricut exists

Tools like [`skhd`](https://github.com/koekeishiya/skhd) bind a chord to a **shell
command**. Every time you press the key, the daemon does `fork()` + `execve("/bin/sh",
"-c", "…")`. That shell often then launches *another* client binary, which opens a
socket to a *long‑running* app to actually do the work:

```
keypress ─▶ skhd ─▶ fork/exec sh ─▶ exec client ─▶ connect() ─▶ app does the thing
            (≈1–5+ ms of process creation before any real work happens)
```

The work itself (focus a window, toggle a layer, switch a mode) is microseconds.
The **process spawn dominates**, adds jitter, and burns power. It is the same class
of problem noribar solved for the menu bar by replacing shell‑outs with in‑process
native providers.

noricut collapses the hot path to a single write on a connection that is **already
open**:

```
keypress ─▶ noricut (event tap + broker) ─▶ write() ─▶ subscriber handles in‑process
            (≈microseconds, zero process spawns, zero allocations on the hot path)
```

## What it is

noricut is two things in one small daemon:

1. **A hotkey frontend** — the single owner of the OS keyboard event tap.
2. **A tiny pub/sub broker** — when a chord matches, it *publishes a message on a
   subject* to whichever long‑running tools subscribed to it. Those tools (noribar,
   a window manager, your own script‑host) react in‑process.

It speaks the **noricut Wire Protocol (NWP)** — a small, newline‑delimited‑JSON,
OS‑/language‑agnostic protocol over a Unix‑domain socket. A complete client is "read a
line, parse JSON, write a line" — standard library in every mainstream language, no
client library and no FFI. NWP is the contract that lets first‑party norikit tools *and*
unrelated third‑party tooling share one hotkey registry and one event bus without any of
them spawning processes.

- **Native to norikit** — noribar can `subscribe` to noricut subjects exactly like it
  subscribes to its own providers.
- **Open** — the protocol is fully specified and dependency‑free to implement; any
  language that can open a socket can publish events, subscribe to them, or register
  its own bindings.
- **Performant** — persistent connections, no process spawns on the hot path,
  content‑agnostic routing (the broker never parses your payload).

## Read next

- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — the noricut Wire Protocol (NWP) v1 specification.
- [`docs/knowledge-base/architecture.md`](docs/knowledge-base/architecture.md) — how the daemon is structured.
- [`docs/knowledge-base/decisions.md`](docs/knowledge-base/decisions.md) — locked design decisions and the rationale behind them.
- [`docs/knowledge-base/language-evaluation.md`](docs/knowledge-base/language-evaluation.md) — the implementation‑language comparison.
- [`docs/knowledge-base/open-questions.md`](docs/knowledge-base/open-questions.md) — what is still undecided.

## License

AGPL‑3.0, consistent with the rest of the norikit org.
