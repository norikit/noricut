# Open questions

Undecided items that affect the design. Resolve into `decisions.md` (and update
`../PROTOCOL.md`) as they close.

### Q1 — Broker core implementation language
Recommendation is **Rust** (see `language-evaluation.md`), with C as a defensible lean
alternative and Swift reserved for the macOS event‑tap frontend. **Owner ratification
needed** before any product code lands — it is long‑lived and hard to reverse.

### Q2 — `request`/response scope
v1 keeps `WANT_ACK` + `corr` minimal (control‑plane acks, errors, `PING`/`PONG`). Do we
want a fuller request/reply (e.g. a subscriber answering "what is the current window?")
in v1, or is that better left to application subjects? Affects whether the hub needs a
reply‑routing table keyed by `corr`.

### Q3 — Linux global‑tap strategy under Wayland
`evdev`/`libinput` needs input‑group access and is compositor‑agnostic but sees raw
keys; the Wayland route is the desktop‑portal global‑shortcuts API (more sandbox‑friendly,
less universal). Pick a default and document the trade. Pure‑Wayland environments may
constrain how much of `skhd`'s behavior is reproducible.

### Q4 — Retained subjects: scope & eviction
`RETAINED` is specified for things like current mode. Do we cap the retained store size,
and what evicts entries (TTL? explicit clear? publisher disconnect)? Currently
publisher‑disconnect does **not** clear retained values — confirm that is desired.

### Q5 — Built‑in `exec` escape hatch: keep, or push to a sidecar?
The hub can offer a built‑in `exec` for the rare binding that must run a shell command.
Keeping it in‑hub is convenient but reintroduces `fork/exec` inside the daemon. Alternative
is to ship a tiny `noricut-exec` subscriber that owns that responsibility, keeping the hub
spawn‑free. Leaning toward the sidecar.

### Q6 — Config language reach
Lua is locked for config (D8). Do we also want a static, non‑Lua declarative format (e.g.
TOML) for users who refuse an embedded interpreter, given the protocol is config‑language
independent? Affects scope, not the wire.

### Q7 — Windows posture for v1
`AF_UNIX` exists on Win10 1803+, low‑level keyboard hook exists, but is Windows a v1
target or a "protocol stays portable, frontend later" deferral? Currently treated as
deferred (architecture.md §7).

### Q8 — Wire compatibility & versioning policy
v1 negotiates a single `ver` byte and gates features by capability. Confirm we are
comfortable with "no minor version on the wire" before publishing, since it is itself
hard to change later.
