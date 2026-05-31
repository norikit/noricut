# Decisions (locked)

Durable, hard‑to‑reverse choices. Append‑only in spirit: if a decision changes, record
the supersession rather than deleting history. See `architecture.md` for the evolving
"how" and `open-questions.md` for what is still undecided.

---

### D1 — noricut is a hub/broker, not a fan of independent key handlers
A single daemon owns the OS keyboard event tap and acts as a tiny pub/sub broker. Tools
do not each install their own global tap; they connect to noricut and receive events.
**Why:** one event tap avoids duplicated privileged code and chord conflicts, and makes
"share one hotkey registry" possible (D7).

### D2 — The hot path is a socket write, never a process spawn
On a chord match, noricut writes a pre‑built frame to already‑open connections. Spawning
a shell/command is an explicit, opt‑in escape hatch (`exec` subject), never the default.
**Why:** this is the entire reason the project exists — `skhd`'s `fork`+`execve` per
keypress is the performance/jitter/power problem we are removing.

### D3 — Transport is a Unix‑domain `SOCK_STREAM` socket; TCP loopback is an opt‑in fallback
**Why:** `AF_UNIX` stream sockets are the only transport that is simultaneously fast,
secure‑by‑file‑permission, and present on macOS, Linux, BSD, and Windows 10+. macOS lacks
reliable `SOCK_SEQPACKET`, so stream + length framing is the portable baseline.

### D4 — Length‑prefixed binary framing (`u32` little‑endian), fixed‑offset header
**Why:** delimiter‑free framing lets payloads carry any bytes, lets the broker `writev`
without inspecting payloads, and keeps the hot‑path parser to a few integer reads with
zero allocation. Little‑endian avoids a byte‑swap on every mainstream target.

### D5 — The broker is content‑agnostic; payloads are opaque and forwarded verbatim
The hub routes on the UTF‑8 *subject* only and never parses the payload. A `ct`
content‑type hint and a default `kv` (NUL‑terminated `key=value`) envelope are provided
for interop, but are advisory. **Why:** keeps routing O(subject), keeps the protocol free
of a mandatory schema/serialization dependency, and lets every ecosystem use its own
encoding.

### D6 — Subjects are hierarchical dotted tokens with `*` / `>` wildcards
**Why:** gives noricut a real event‑bus shape, maps one‑to‑one onto noribar's
`subscribe(event, cb)`, and lets subscribers wildcard whole families (`key.>`).

### D7 — Clients may register their own bindings at runtime (`BIND`)
noricut is a *shared* hotkey registry: a third‑party tool can ask the daemon to bind a
chord and deliver its events back. **Why:** removes per‑app global event taps and chord
conflicts; this is the main thing that makes noricut "open for integration," not just a
norikit‑internal tool.

### D8 — Configuration is embedded Lua, hot‑reloadable
Consistent with noribar (variables, functions, reusable modules; edit‑while‑running).
**Why:** org consistency and a real programming surface beat imperative CLI/`.conf` lines.
The *protocol* remains independent of the config language (D5), so non‑Lua front‑ends
stay possible.

### D9 — Peer‑credential authentication on the Unix socket; token required only on TCP
The hub verifies `SO_PEERCRED`/`LOCAL_PEERCRED` and a `0600` socket; no token needed
locally. **Why:** strong, zero‑config local security without a secrets‑management burden.

### D10 — Bounded per‑client queues with an explicit slow‑consumer policy
Non‑blocking writes; `lossy` drop‑oldest for `key.`/`mode.` traffic, `reliable` clients
disconnected if they stall. **Why:** bounded tail latency is the real win over
`fork/exec` (which has unbounded tail latency under load); a stalled GUI must never delay
key dispatch.

### D11 — License is AGPL‑3.0
Consistent with the norikit org.

### D12 — Knowledge‑base‑first, task/spike methodology, never commit to `main`
Mirrors noribar: durable decisions live here; work happens on branches and lands via PRs;
de‑risking spikes precede product code. See `CLAUDE.md`.

> **Not yet locked:** the daemon's implementation language. A full comparison lives in
> `language-evaluation.md`; the final choice is tracked in `open-questions.md` (Q1)
> pending owner ratification, because it is a long‑lived, hard‑to‑reverse commitment.
