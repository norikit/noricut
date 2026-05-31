# noricut Wire Protocol (NWP) v1

**Status:** Draft for review. This is the normative specification of the protocol
noricut uses to talk to subscribers, publishers, and binding clients.

NWP exists to do one thing well: deliver a keypress‑triggered (or tool‑triggered)
**message** to an already‑running process **without spawning anything on the hot
path**, in a way that is trivial to implement in any language on any mainstream OS.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are used as in RFC 2119.

---

## 1. Design goals & non‑goals

**Goals**

1. **No process spawns on the hot path.** From keypress to handler invocation must be
   a single `write()` to an already‑open file descriptor. Target: low‑single‑digit
   microseconds local dispatch, no allocation on the hot path.
2. **OS‑agnostic.** Works on macOS, Linux, the BSDs, and Windows 10+ using only
   facilities every modern OS provides.
3. **Language‑agnostic.** A complete client is implementable in well under ~150 lines
   in C, Rust, Go, Swift, Python, or even a shell with `socat`. No mandatory
   serialization library, no schema compiler, no code generation.
4. **Content‑agnostic routing.** The broker routes on a UTF‑8 *subject* only. It MUST
   NOT need to parse the payload. Payloads are opaque bytes forwarded verbatim.
5. **Native to norikit, open to everyone.** First‑party tools get standardized
   subjects and payloads; third parties can publish, subscribe, and register their
   own hotkey bindings on equal footing.

**Non‑goals**

- Not a general network protocol. NWP is local‑first (a host‑local IPC bus). A TCP
  fallback exists for constrained platforms but security/remote semantics are out of
  scope for v1.
- Not a durable message queue. Delivery is best‑effort and in‑memory; there is no
  persistence, replay, or guaranteed ordering across subjects.
- Not an RPC framework. A minimal request/response (ack + correlation id) exists for
  control messages, but NWP is fundamentally fire‑and‑forget pub/sub.

---

## 2. Topology

noricut is a **hub (broker)**. Every other participant is a **client** that holds one
persistent connection to the hub. A client may act in any combination of three roles,
declared in its `HELLO`:

| Role | Meaning |
|------|---------|
| `PUB` | May publish messages onto subjects. |
| `SUB` | May subscribe to subjects and receive deliveries. |
| `BIND` | May register/After‑unregister OS hotkey bindings that publish to subjects. |

The hub itself is the canonical publisher of key events: it owns the OS event tap and,
on a chord match, publishes to the subject configured for that binding. From a
subscriber's point of view there is no difference between "a key fired" and "another
tool published" — both arrive as a `DELIVER` frame on a subject. This uniformity is
deliberate: it is what makes noricut simultaneously a hotkey daemon *and* an event bus.

```
                       ┌─────────────────────────────┐
  OS keyboard  ───────▶│  noricut hub                │
  event tap            │   • binding table (trie)    │
                       │   • subject router (trie)   │──DELIVER──▶ noribar (SUB)
  third‑party  ──PUB──▶│   • per‑client send queues  │──DELIVER──▶ window mgr (SUB)
  tool                 │   • peer‑cred auth          │──DELIVER──▶ your script host
                       └─────────────────────────────┘
       ▲                                                              │
       └──────────────────────── BIND ────────────────────────────--─┘
            (a tool registers "cmd-alt-h" → subject, delivered back to itself)
```

---

## 3. Transport

### 3.1 Primary: Unix‑domain stream socket

- The hub MUST listen on a `SOCK_STREAM` `AF_UNIX` socket.
- Default path resolution order:
  1. `$NORICUT_SOCK` if set.
  2. `$XDG_RUNTIME_DIR/noricut/nwp.sock` if `XDG_RUNTIME_DIR` is set (Linux/BSD).
  3. `$TMPDIR/noricut-$UID/nwp.sock` otherwise (macOS).
- The socket file MUST be created with mode `0600`. The containing directory SHOULD be
  `0700` and owned by the user.
- `AF_UNIX` is available on macOS, Linux, the BSDs, and Windows 10 (1803+). This is the
  one transport that is both fast and present everywhere.

`SOCK_STREAM` (not `SOCK_DGRAM`/`SOCK_SEQPACKET`) is mandated for the baseline because
it is the only Unix‑socket type with reliable, well‑behaved support on *all* targets —
notably macOS, whose `AF_UNIX` `SOCK_SEQPACKET` support is historically absent. Stream
sockets do not preserve message boundaries, which is why NWP frames are
length‑prefixed (§4).

### 3.2 Optional optimizations

- **Abstract namespace (Linux only):** the hub MAY additionally bind an abstract socket
  `@noricut/nwp` to avoid filesystem cleanup. Clients SHOULD prefer the path‑based
  socket for portability.
- **`SOCK_SEQPACKET` (Linux only):** the hub MAY offer a SEQPACKET endpoint as a
  perf option; on it the length prefix is redundant but MUST still be sent so the same
  parser works on both endpoints.

### 3.3 Fallback: TCP loopback

For platforms or sandboxes without usable `AF_UNIX`, the hub MAY listen on
`127.0.0.1:<port>` (default `17631`). The framing and message format are identical.
TCP is **opt‑in** and carries weaker security guarantees (any local process may
connect); peer authentication (§8) becomes mandatory when TCP is enabled.

---

## 4. Framing

Every message — in both directions — is a single frame:

```
┌────────────┬───────────────────────────┐
│  u32 LEN   │   BODY  (LEN bytes)        │
│ little‑end │                            │
└────────────┴───────────────────────────┘
```

- `LEN` is an unsigned 32‑bit **little‑endian** integer: the number of bytes in `BODY`.
  Little‑endian is mandated (not network order) because every mainstream target is
  little‑endian and it avoids a byte‑swap on the hot path; clients on a big‑endian host
  MUST byte‑swap.
- `LEN` MUST NOT exceed `MaxFrame` (default `1 MiB`, negotiable down in `HELLO`). A frame
  exceeding the peer's advertised limit MUST be answered with `ERR` and the connection
  closed.
- Frames may be pipelined back‑to‑back in a single `write()`/`read()`. A reader MUST be
  prepared for partial frames and for multiple frames per read.

Length‑prefixing (vs. a delimiter) means a reader never scans the payload, payloads may
contain any bytes including NUL, and the broker can `writev` one buffer to many
subscribers without inspecting it.

---

## 5. Message body

The body is a small fixed header followed by two length‑prefixed byte strings. There is
**no** mandatory schema beyond this; in particular the **payload is opaque** to the hub.

```
Offset  Size  Field        Notes
------  ----  -----------  -------------------------------------------------------
0       1     ver          Protocol major version. v1 = 0x01.
1       1     type         Message type (§6).
2       2     flags        u16 LE bit flags (§5.1).
4       4     corr         u32 LE correlation id. 0 = none. Echoed in ACK/ERR.
8       2     subj_len     u16 LE length of subject in bytes (0..=65535).
10      2     ct           u16 LE payload content‑type hint (§5.2).
12      subj_len           subject: UTF‑8, dotted tokens (§7). NOT NUL‑terminated.
…       4     pay_len      u32 LE length of payload in bytes.
…       pay_len            payload: opaque bytes, forwarded verbatim.
```

The header is fixed‑offset and integer‑only: a hot‑path reader extracts `type`,
`subj`, and the payload slice with three integer reads and zero allocation. The hub
reads `type` and `subj` only; `ct` and `payload` are passed through untouched.

### 5.1 Flags

| Bit  | Name           | Meaning |
|------|----------------|---------|
| 0    | `WANT_ACK`     | Sender requests an `ACK` (or `ERR`) carrying the same `corr`. |
| 1    | `LOSSY`        | Hint: this message MAY be dropped under backpressure (§9). |
| 2    | `RETAINED`     | Publish: hub retains the last value on this subject and delivers it to new subscribers (e.g. current mode). |
| 3    | `NO_ECHO`      | Publish: do not deliver back to the publishing connection even if it matches. |
| 4–15 | reserved       | MUST be 0 in v1; receivers MUST ignore unknown bits. |

### 5.2 Content‑type hint (`ct`)

`ct` is advisory metadata so subscribers can decode without out‑of‑band agreement. The
hub never acts on it.

| Value | Encoding |
|-------|----------|
| `0`   | `kv` — the default noricut envelope: a sequence of `key=value` pairs, each field NUL‑terminated, UTF‑8 (§5.3). |
| `1`   | `raw` — uninterpreted bytes. |
| `2`   | `utf8` — a bare UTF‑8 string. |
| `3`   | `json` — UTF‑8 JSON. |
| `4`   | `msgpack` |
| `5`   | `cbor` |
| 6–1023 | reserved for future noricut use |
| 1024+ | application‑private; agree out of band |

### 5.3 The default `kv` envelope

The default payload encoding is intentionally the simplest thing that is both
shell‑friendly and zero‑dependency: NUL‑terminated `key=value` records.

```
app=Safari\0space=3\0modifiers=cmd,alt\0
```

- Trivially produced in a shell: `printf 'app=%s\0space=%s\0' "$APP" "$SPACE"`.
- Trivially parsed anywhere: split on `\0`, then on the first `=`.
- Mirrors the environment‑variable mental model `skhd`/`sketchybar` users already have,
  which is exactly the data those tools pass to spawned commands — except here it is
  delivered without spawning anything.

Structured callers SHOULD set `ct` to `json`/`msgpack`/`cbor` and use those instead.

---

## 6. Message types

| `type` | Name         | Dir    | Purpose |
|--------|--------------|--------|---------|
| `0x01` | `HELLO`      | C→H    | Open a session: declare version, name, roles, caps, optional auth. |
| `0x02` | `WELCOME`    | H→C    | Accept: assigned client id, negotiated version, server caps & limits. |
| `0x03` | `SUBSCRIBE`  | C→H    | Subscribe a subject pattern with delivery options. |
| `0x04` | `UNSUBSCRIBE`| C→H    | Remove a previously added subscription. |
| `0x05` | `PUBLISH`    | C→H    | Publish a message onto a subject. |
| `0x06` | `DELIVER`    | H→C    | Delivery of a published message to a matching subscriber. |
| `0x07` | `BIND`       | C→H    | Register an OS hotkey chord that publishes to a subject. |
| `0x08` | `UNBIND`     | C→H    | Remove a binding owned by this client. |
| `0x09` | `MODE`       | C→H    | Enter/exit a modal binding layer (§7.3). |
| `0x0A` | `ACK`        | H→C    | Success response to a `WANT_ACK` request; echoes `corr`. |
| `0x0B` | `ERR`        | H→C    | Failure response; echoes `corr`; payload is `kv` with `code`/`msg`. |
| `0x0C` | `PING`       | C↔H    | Keepalive / RTT probe. |
| `0x0D` | `PONG`       | C↔H    | Reply to `PING`; echoes `corr`. |
| `0x0E` | `GOODBYE`    | C→H    | Graceful close; hub releases the client's subs and bindings. |

`C→H` = client to hub, `H→C` = hub to client. Unknown `type` values MUST be answered
with `ERR(code=unknown_type)` and otherwise ignored (forward compatibility).

`DELIVER` is structurally a `PUBLISH` re‑emitted by the hub. Subscribers therefore parse
exactly one delivery shape regardless of whether a human's keypress or another tool was
the origin. Origin metadata (publisher client id, monotonic timestamp) is appended to
the `kv` payload by the hub under reserved keys prefixed `_` (e.g. `_src`, `_ts`,
`_seq`) and only when the payload `ct` is `kv`; for other content‑types this metadata is
omitted to keep the payload byte‑exact.

---

## 7. Subjects

Subjects are hierarchical, dot‑separated tokens of `[a-z0-9_]` (lowercase). They give
NWP its event‑bus character and map one‑to‑one onto noribar's `subscribe(event, cb)`.

### 7.1 Wildcards (subscriptions only)

- `*` matches exactly one token. `key.*.left` matches `key.focus.left`.
- `>` matches one or more trailing tokens and MUST be the final token. `key.>` matches
  every key event.

Publishers MUST publish to fully‑qualified subjects (no wildcards). Subscriptions MAY
use wildcards. Matching is performed against a per‑hub token trie so a publish is
`O(tokens)`, not `O(subscribers)`.

### 7.2 Reserved namespaces

| Prefix | Owner | Examples |
|--------|-------|----------|
| `key.` | hub key bindings | `key.focus.west`, `key.window.fullscreen` |
| `mode.`| hub modes | `mode.resize.enter`, `mode.resize.exit` |
| `noricut.` | hub lifecycle | `noricut.ready`, `noricut.reload`, `noricut.client.gone` |
| `app.` | norikit providers | `app.front_changed`, `app.launched` |
| everything else | applications | `myapp.scratchpad.toggle` |

Subject *names* under `key.` are user‑chosen in config; the prefix is a convention so
subscribers can wildcard‑subscribe to whole families.

### 7.3 Modes

Modes are sticky binding layers (the `skhd` "mode" feature) modeled as state in the hub.
Entering mode `m` causes the hub to publish `mode.m.enter` (with `RETAINED`) and to make
that mode's bindings active. `MODE` messages let a client drive modes programmatically;
bindings may also switch modes declaratively in config.

---

## 8. Session lifecycle & authentication

1. Client connects, sends `HELLO` (`ver`, name, roles, `MaxFrame`, optional `token`).
2. Hub authenticates the peer:
   - **Unix socket:** the hub MUST verify peer credentials via `SO_PEERCRED` (Linux) or
     `LOCAL_PEERCRED`/`getpeereid` (macOS/BSD) and MUST reject a UID that does not match
     the hub's own UID. No token is required on a `0600` user‑owned socket.
   - **TCP:** a shared `token` (from `$NORICUT_TOKEN` or config) is REQUIRED; the hub
     MUST reject mismatches with `ERR(code=unauthorized)` and close.
3. Hub replies `WELCOME` (client id, negotiated `ver` = `min(client, hub)`, caps,
   effective `MaxFrame`, retained‑subject support flag).
4. Client may now `SUBSCRIBE` / `PUBLISH` / `BIND` per its roles. A message requiring a
   role the client did not request MUST be answered `ERR(code=forbidden_role)`.
5. Either side MAY `PING`; a peer that misses `KeepaliveMax` (default 30 s) of liveness
   MAY be disconnected. The hub publishes `noricut.client.gone` when a client drops.

Version negotiation is by the single `ver` byte; v1 hubs and clients interoperate by
agreeing on the lower major and ignoring unknown flags/types. There is no minor version
on the wire — capabilities, not versions, gate optional features.

---

## 9. Backpressure & the slow‑consumer problem

A GUI subscriber that stalls MUST NOT be able to delay key dispatch to other
subscribers. The hub therefore:

- Uses **non‑blocking** writes and one **bounded** send queue per client
  (default `SendQueueMax` = 1024 frames or 4 MiB, whichever first).
- On overflow, applies the per‑subscription **delivery policy**:
  - `lossy` (default for `LOSSY`‑flagged or `key.`/`mode.` traffic): drop the **oldest**
    queued frame for that client and enqueue the new one. A key event is only useful
    fresh; dropping a stale one is correct.
  - `reliable`: stop reading the offending client and, if the queue stays full past
    `SlowConsumerGrace` (default 2 s), disconnect it with `ERR(code=slow_consumer)`.
    Reliable subscribers that fall behind are removed rather than allowed to back up the
    whole hub.
- Never blocks the accept/dispatch loop on any single client.

This is the crux of beating `skhd` on *consistency*, not just mean latency: a persistent
bus with explicit backpressure has bounded tail latency, whereas per‑event `fork/exec`
has unbounded tail latency under memory pressure.

---

## 10. Why this is faster than spawning (informative)

| | `skhd`‑style | noricut / NWP |
|--|--------------|---------------|
| Hot‑path syscalls | `fork`+`execve` (×1–2) + dynamic link + shell init + `connect` | one `write` to an open fd |
| Typical latency | ~1–5+ ms, high variance | low‑single‑digit µs, low variance |
| Allocations per action | shell heap, argv, env copy | none on the hot path |
| Failure mode under load | unbounded (process table, swap) | bounded (drop‑oldest / disconnect) |
| Power | wakes scheduler, pages in `sh` | one wakeup on an existing fd |

An escape hatch is still available: a binding may target the hub's built‑in `exec`
handler to run a shell command for the rare case that genuinely needs one — backward
compatible with the `skhd` model, but off the hot path by default and explicitly opted
into per binding.

---

## 11. Worked example (default `kv`)

A user presses `cmd‑alt‑h`, bound in config to publish `key.focus.west`.

1. Hub's event tap matches the chord, builds one frame once:
   `type=DELIVER, subj="key.focus.west", ct=kv, payload="chord=cmd-alt-h\0_src=0\0_ts=…\0"`.
2. Hub looks up `key.focus.west` in the subject trie → `[fd_noribar, fd_wm]`.
3. Hub `writev`s the *same* buffer to both fds. No payload parse, no copy beyond the
   socket buffers.
4. The window manager (a long‑running `SUB` client) reads the frame, splits the payload
   on `\0`, and focuses the western window in‑process.

No process was spawned at any point after the daemons started.

---

## 12. Conformance checklist

A minimal conforming client MUST:

- frame with `u32` LE length prefixes and tolerate partial/coalesced reads;
- send a valid `HELLO` and wait for `WELCOME` before other traffic;
- ignore unknown `flags` bits and reply `ERR` to unknown `type`s rather than crashing;
- byte‑swap integers if running on a big‑endian host.

A minimal conforming hub MUST:

- enforce peer‑credential auth on the Unix socket and `0600` socket permissions;
- route on subject only and forward payloads byte‑exact (modulo `_`‑prefixed `kv`
  metadata it appends);
- implement bounded per‑client queues with a documented slow‑consumer policy;
- never block dispatch on a single client.

---

*Open questions that affect this spec live in
[`knowledge-base/open-questions.md`](knowledge-base/open-questions.md). Changes here
MUST be reflected in [`knowledge-base/decisions.md`](knowledge-base/decisions.md).*
