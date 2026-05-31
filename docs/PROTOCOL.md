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
3. **Language‑agnostic, no library required.** A complete client is "read a line, parse
   JSON, write a line." Both halves are in the standard library of every mainstream
   language — `readline`/`bufio.Scanner`/`makefile()` and a JSON parser. No mandatory
   serialization library, no schema compiler, no code generation, no FFI. A working
   subscriber is ~8 lines (§11).
4. **Routes on subject only.** The broker reads the message *envelope* to find its
   `op` and `subject`; it MUST NOT interpret the application `data`, which it forwards
   verbatim. Routing stays O(subject), independent of payload meaning.
5. **Native to norikit, open to everyone.** First‑party tools get standardized
   subjects and payloads; third parties can publish, subscribe, and register their
   own hotkey bindings on equal footing.

**Non‑goals**

- Not a general network protocol. NWP is local‑first (a host‑local IPC bus). A TCP
  fallback exists for constrained platforms but security/remote semantics are out of
  scope for v1.
- Not a durable message queue. Delivery is best‑effort and in‑memory; there is no
  persistence, replay, or guaranteed ordering across subjects.
- Not an RPC framework. A minimal request/response (`id` + `ack`/`err`) exists for
  control messages, but NWP is fundamentally fire‑and‑forget pub/sub.

---

## 2. Topology

noricut is a **hub (broker)**. Every other participant is a **client** that holds one
persistent connection to the hub. A client may act in any combination of three roles,
declared in its `hello`:

| Role | Meaning |
|------|---------|
| `pub` | May publish messages onto subjects. |
| `sub` | May subscribe to subjects and receive deliveries. |
| `bind` | May register/unregister OS hotkey bindings that publish to subjects. |

The hub itself is the canonical publisher of key events: it owns the OS event tap and,
on a chord match, publishes to the subject configured for that binding. From a
subscriber's point of view there is no difference between "a key fired" and "another
tool published" — both arrive as a `msg` from the hub on a subject. This uniformity is
deliberate: it is what makes noricut simultaneously a hotkey daemon *and* an event bus.

```
                       ┌─────────────────────────────┐
  OS keyboard  ───────▶│  noricut hub                │
  event tap            │   • binding table (trie)    │
                       │   • subject router (trie)   │──msg──▶ noribar (sub)
  third‑party  ──pub──▶│   • per‑client send queues  │──msg──▶ window mgr (sub)
  tool                 │   • peer‑cred auth          │──msg──▶ your script host
                       └─────────────────────────────┘
       ▲                                                        │
       └──────────────────────── bind ──────────────────────---─┘
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
sockets do not preserve message boundaries, which is why NWP frames are newline‑delimited
(§4).

### 3.2 Optional optimizations

- **Abstract namespace (Linux only):** the hub MAY additionally bind an abstract socket
  `@noricut/nwp` to avoid filesystem cleanup. Clients SHOULD prefer the path‑based
  socket for portability.

### 3.3 Fallback: TCP loopback

For platforms or sandboxes without usable `AF_UNIX`, the hub MAY listen on
`127.0.0.1:<port>` (default `17631`). The framing and message format are identical.
TCP is **opt‑in** and carries weaker security guarantees (any local process may
connect); peer authentication (§8) becomes mandatory when TCP is enabled.

The TCP fallback is also the universal‑reach backstop: any language that can open a TCP
socket — with no Unix‑socket support and no extra dependency — can speak NWP.

---

## 4. Framing

### 4.1 Default: newline‑delimited JSON (NDJSON)

Every message — in both directions — is **one JSON object on a single line, terminated
by a single line feed** (`\n`, `0x0A`):

```
{"op":"pub","subject":"key.focus.west","data":{"chord":"cmd-alt-h"}}\n
```

- The line is UTF‑8 JSON. Because JSON encoders escape literal newlines inside strings
  (as `\n`), a serialized JSON object never contains a raw `0x0A`; the byte therefore
  unambiguously delimits messages.
- A reader frames by reading bytes up to the next `\n`, then parsing the preceding bytes
  as one JSON object. This is exactly what `readline`, `bufio.Scanner`,
  `socket.makefile()`, and friends already do — **the framing layer is the standard
  library**, in every direction.
- A reader MUST tolerate partial lines (a read that ends mid‑line) and coalesced lines
  (multiple `\n`‑terminated objects in one read). Stdlib line iterators handle both.
- A line (excluding the terminating `\n`) MUST NOT exceed `MaxFrame` (default `1 MiB`,
  negotiable in `hello`). An over‑long line MUST be answered with `err`
  (`code=frame_too_large`) and the connection closed.
- Pretty‑printing is **forbidden**: every message MUST be a single physical line.
  Insignificant whitespace inside the object is allowed but pointless.

Newline framing (vs. a binary length prefix) was chosen because the cost of locating a
message boundary is identical to "read a line," which needs no protocol‑specific code in
any mainstream language. See Appendix A for the opt‑in binary framing for payloads that
need to be byte‑exact or are large.

### 4.2 Why JSON does not slow the hot path

The hub builds the outgoing `msg` line **once** per event and `writev`s that single byte
buffer to every matching subscriber (§9, §11) — fan‑out is one serialization, N writes,
unchanged from a binary design. For hub‑published key events the line is largely
**precomputable per binding** (subject and static `data` are known when the binding is
registered); only the small `meta` tail varies, so the allocation‑free hot‑path goal
(D2) is preserved. A per‑message JSON parse on the receiving side is sub‑microsecond and
happens off the hub, at keyboard‑event rates where it is irrelevant.

---

## 5. Message format

Every message is a JSON object. Exactly one field is mandatory in all messages:

| Field | Type | Meaning |
|-------|------|---------|
| `op`  | string | The operation (§6). Unknown ops → `err(code=unknown_op)`. |

The remaining top‑level fields are per‑op. The common ones:

| Field | Type | Used by | Meaning |
|-------|------|---------|---------|
| `subject` | string | `sub`,`unsub`,`pub`,`msg`,`bind`,`unbind` | Dotted subject (§7). |
| `data` | any JSON value | `pub`,`msg` | The application payload. Opaque to the hub; forwarded verbatim. |
| `sid` | string/number | `sub`,`unsub`,`msg` | Client‑chosen subscription id, echoed on deliveries. |
| `id` | string/number | any request | Correlation id; echoed in the matching `ack`/`err`/`pong`. Absent = fire‑and‑forget. |
| `meta` | object | `msg` | Hub‑appended origin metadata (§5.2). |

Receivers MUST ignore unknown top‑level fields (forward compatibility). Field order is
not significant.

### 5.1 The `data` payload

`data` is any JSON value and is **opaque to the hub** — it is never inspected and is
re‑emitted byte‑for‑byte in the `msg`. The default noricut convention is a JSON
**object** of `key → value`:

```json
{"chord":"cmd-alt-h","app":"Safari","space":3}
```

This replaces the old NUL‑terminated `kv` envelope with the same mental model — a flat
bag of named fields — now expressed as ordinary JSON every language already decodes.
Applications MAY put any JSON value in `data` (string, number, array, nested object);
norikit first‑party subjects use a flat object so values map cleanly onto environment
variables when handed to the `exec` escape hatch.

Bytes that are not valid UTF‑8 / not representable in JSON (raw binary blobs) MUST use
the opt‑in binary framing of Appendix A; they are out of scope for the default mode.

### 5.2 Hub‑appended `meta`

On a `msg`, the hub MAY attach a `meta` object with origin information. It is namespaced
under `meta` (rather than mixed into `data`) so the publisher's `data` stays exact:

| `meta` key | Meaning |
|-----------|---------|
| `src` | Publisher client id (`0` = the hub itself, i.e. a key event). |
| `ts`  | Hub monotonic timestamp (ms) when the message was emitted. |
| `seq` | Per‑hub monotonic sequence number. |

Subscribers that do not care simply ignore `meta`.

---

## 6. Operations (`op`)

| `op` | Dir | Purpose |
|------|-----|---------|
| `hello`   | C→H | Open a session: declare version, name, roles, caps, framing, optional auth. |
| `welcome` | H→C | Accept: assigned client id, negotiated version, server caps & limits. |
| `sub`     | C→H | Subscribe a subject pattern (`subject`, `sid`, options). |
| `unsub`   | C→H | Remove a subscription by `sid`. |
| `pub`     | C→H | Publish `data` onto `subject`. |
| `msg`     | H→C | Delivery of a published message to a matching subscriber. |
| `bind`    | C→H | Register an OS hotkey chord that publishes to a subject. |
| `unbind`  | C→H | Remove a binding owned by this client. |
| `mode`    | C→H | Enter/exit a modal binding layer (§7.3). |
| `ack`     | H→C | Success response to a request carrying `id`; echoes `id`. |
| `err`     | H→C | Failure response; echoes `id`; carries `code` and `msg`. |
| `ping`    | C↔H | Keepalive / RTT probe. |
| `pong`    | C↔H | Reply to `ping`; echoes `id`. |
| `bye`     | C→H | Graceful close; hub releases the client's subs and bindings. |

`C→H` = client to hub, `H→C` = hub to client. Unknown `op` values MUST be answered with
`err(code=unknown_op)` and otherwise ignored (forward compatibility).

A `msg` is structurally a `pub` re‑emitted by the hub. Subscribers therefore parse
exactly one delivery shape regardless of whether a human's keypress or another tool was
the origin; the only difference is the hub‑added `meta`.

### 6.1 Request options as fields

What were binary bit‑flags are now optional boolean fields on the relevant op, ignored
by simple clients:

| Field | On | Meaning |
|-------|----|---------|
| `ack: true`    | any request | Sender requests an `ack` (or `err`) carrying the same `id`. |
| `lossy: true`  | `sub`,`pub` | This message MAY be dropped first under backpressure (§9). |
| `retain: true` | `pub` | Hub retains the last value on this subject and delivers it to new subscribers (e.g. current mode). |
| `no_echo: true`| `pub` | Do not deliver back to the publishing connection even if it matches. |

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
Entering mode `m` causes the hub to publish `mode.m.enter` (with `retain`) and to make
that mode's bindings active. `mode` messages let a client drive modes programmatically;
bindings may also switch modes declaratively in config.

---

## 8. Session lifecycle & authentication

1. Client connects, sends `hello`:
   `{"op":"hello","ver":1,"name":"mytool","roles":["sub"],"max_frame":1048576}`.
   Optional: `"framing":"binary"` (Appendix A), `"token":"…"` (TCP).
2. Hub authenticates the peer:
   - **Unix socket:** the hub MUST verify peer credentials via `SO_PEERCRED` (Linux) or
     `LOCAL_PEERCRED`/`getpeereid` (macOS/BSD) and MUST reject a UID that does not match
     the hub's own UID. No token is required on a `0600` user‑owned socket.
   - **TCP:** a shared `token` (from `$NORICUT_TOKEN` or config) is REQUIRED; the hub
     MUST reject mismatches with `err(code=unauthorized)` and close.
3. Hub replies
   `{"op":"welcome","id":7,"ver":1,"framing":"ndjson","max_frame":1048576,"caps":[…]}`
   (assigned client id, negotiated `ver` = `min(client, hub)`, effective framing and
   `max_frame`, capability list).
4. Client may now `sub` / `pub` / `bind` per its roles. A message requiring a role the
   client did not request MUST be answered `err(code=forbidden_role)`.
5. Either side MAY `ping`; a peer that misses `KeepaliveMax` (default 30 s) of liveness
   MAY be disconnected. The hub publishes `noricut.client.gone` when a client drops.

Version negotiation is by the single integer `ver`; v1 hubs and clients interoperate by
agreeing on the lower major and ignoring unknown fields/ops. There is no minor version
on the wire — capabilities, not versions, gate optional features.

---

## 9. Backpressure & the slow‑consumer problem

A GUI subscriber that stalls MUST NOT be able to delay key dispatch to other
subscribers. The hub therefore:

- Uses **non‑blocking** writes and one **bounded** send queue per client
  (default `SendQueueMax` = 1024 messages or 4 MiB, whichever first).
- On overflow, applies the per‑subscription **delivery policy**:
  - `lossy` (default for `lossy`‑flagged or `key.`/`mode.` traffic): drop the **oldest**
    queued message for that client and enqueue the new one. A key event is only useful
    fresh; dropping a stale one is correct.
  - `reliable`: stop reading the offending client and, if the queue stays full past
    `SlowConsumerGrace` (default 2 s), disconnect it with `err(code=slow_consumer)`.
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
| Allocations per action | shell heap, argv, env copy | none on the hot path (line precomputed per binding) |
| Failure mode under load | unbounded (process table, swap) | bounded (drop‑oldest / disconnect) |
| Power | wakes scheduler, pages in `sh` | one wakeup on an existing fd |

An escape hatch is still available: a binding may target the hub's built‑in `exec`
handler to run a shell command for the rare case that genuinely needs one — backward
compatible with the `skhd` model, but off the hot path by default and explicitly opted
into per binding. This is the universal fallback for third‑party apps that expose **no**
integration surface: noricut publishes to subscribers when it can, and runs a command
when it cannot.

---

## 11. Worked example (default NDJSON)

A user presses `cmd‑alt‑h`, bound in config to publish `key.focus.west`.

A complete subscriber, no libraries:

```javascript
// Node.js — stdlib only
import net from 'net'
import readline from 'readline'

const sock = net.createConnection({ path: process.env.NORICUT_SOCK })
sock.write('{"op":"hello","ver":1,"roles":["sub"]}\n')
sock.write('{"op":"sub","subject":"key.>","sid":1}\n')

readline.createInterface({ input: sock }).on('line', (line) => {
  const m = JSON.parse(line)
  if (m.op === 'msg') console.log(m.subject, m.data)   // key.focus.west { chord: 'cmd-alt-h' }
})
```

```python
# Python — stdlib only
import os, socket, json
s = socket.socket(socket.AF_UNIX); s.connect(os.environ["NORICUT_SOCK"])
s.sendall(b'{"op":"hello","ver":1,"roles":["sub"]}\n')
s.sendall(b'{"op":"sub","subject":"key.>","sid":1}\n')
for line in s.makefile():
    m = json.loads(line)
    if m["op"] == "msg":
        print(m["subject"], m["data"])
```

On the wire:

1. Hub's event tap matches the chord and builds one line once:
   `{"op":"msg","subject":"key.focus.west","data":{"chord":"cmd-alt-h"},"meta":{"src":0,"ts":1748649600123,"seq":42}}\n`.
2. Hub looks up `key.focus.west` in the subject trie → `[fd_noribar, fd_wm]`.
3. Hub `writev`s the *same* line buffer to both fds. No re‑serialization per subscriber.
4. The window manager (a long‑running `sub` client) reads the line, `JSON.parse`s it,
   and focuses the western window in‑process.

No process was spawned at any point after the daemons started.

---

## 12. Conformance checklist

A minimal conforming client MUST:

- frame by reading lines terminated by `\n` and tolerate partial/coalesced reads;
- serialize every message as a single‑line UTF‑8 JSON object terminated by one `\n`;
- send a valid `hello` and wait for `welcome` before other traffic;
- ignore unknown top‑level fields and unknown `op`s rather than crashing.

A minimal conforming hub MUST:

- parse the JSON envelope, route on `subject` only, and forward `data` verbatim
  (re‑emitting it JSON‑exact, modulo the hub‑added `meta`);
- implement bounded per‑client queues with a documented slow‑consumer policy;
- enforce peer‑credential auth on the Unix socket and `0600` socket permissions;
- never block dispatch on a single client.

---

## Appendix A — Opt‑in binary framing (capability `framing=binary`)

The default NDJSON mode cannot carry raw (non‑UTF‑8) bytes and pays a small encode/parse
cost. A client that needs **byte‑exact binary payloads** or **large zero‑copy bodies**
MAY request binary framing in `hello` (`"framing":"binary"`); the hub confirms it in
`welcome`. The negotiation is per‑connection; NDJSON and binary clients coexist on the
same hub and interoperate (the hub transcodes on fan‑out when a subject has subscribers
of both framings).

In binary mode, every frame is:

```
┌────────────┬───────────────────────────┐
│  u32 LEN   │   BODY  (LEN bytes)        │
│ little‑end │                            │
└────────────┴───────────────────────────┘
```

- `LEN` is an unsigned 32‑bit **little‑endian** byte count of `BODY`; clients on a
  big‑endian host MUST byte‑swap. Little‑endian avoids a swap on every mainstream target.
- `BODY` is a fixed‑offset header followed by the subject and an opaque payload:

```
Offset  Size  Field        Notes
------  ----  -----------  -------------------------------------------------------
0       1     ver          Protocol major version. v1 = 0x01.
1       1     op           Operation code mirroring §6 (hello=0x01 … bye=0x0E).
2       2     flags        u16 LE bit flags (WANT_ACK, LOSSY, RETAINED, NO_ECHO).
4       4     corr         u32 LE correlation id. 0 = none. Echoed in ack/err.
8       2     subj_len     u16 LE length of subject in bytes.
10      2     ct           u16 LE payload content‑type hint (raw/utf8/json/msgpack/cbor).
12      subj_len           subject: UTF‑8, dotted tokens (§7). NOT NUL‑terminated.
…       4     pay_len      u32 LE length of payload in bytes.
…       pay_len            payload: opaque bytes, forwarded verbatim.
```

This is the original NWP framing; it remains available for performance‑critical or
binary‑safe first‑party clients. The routing rules, subjects, backpressure, and auth of
the main spec apply unchanged — only the framing/encoding of the envelope differs.

---

*Open questions that affect this spec live in
[`knowledge-base/open-questions.md`](knowledge-base/open-questions.md). Changes here
MUST be reflected in [`knowledge-base/decisions.md`](knowledge-base/decisions.md).*
</content>
</invoke>
