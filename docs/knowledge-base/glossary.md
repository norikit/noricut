# Glossary

- **Hub / broker** — the noricut daemon: owns the OS keyboard tap and routes messages
  between clients. The single point everything connects to.
- **Client** — any process holding a persistent NWP connection to the hub. Roles: `PUB`,
  `SUB`, `BIND` (see PROTOCOL §2).
- **NWP** — noricut Wire Protocol; the length‑prefixed, content‑agnostic IPC contract
  (`../PROTOCOL.md`).
- **Frame** — one `u32`‑length‑prefixed unit on the wire (PROTOCOL §4).
- **Subject** — a hierarchical dotted topic (`key.focus.west`) a message is published to;
  the only thing the hub routes on (PROTOCOL §7).
- **Payload** — opaque application bytes carried by a message; never parsed by the hub.
- **`kv` envelope** — the default payload encoding: NUL‑terminated `key=value` records;
  shell‑friendly, zero‑dependency (PROTOCOL §5.3).
- **`ct`** — content‑type hint advertising how a payload is encoded (`kv`/`json`/…).
- **Binding** — a mapping from a key chord to a subject (and optional `exec`), held in the
  hub's binding table.
- **Mode** — a sticky binding layer (the `skhd` "mode" concept) modeled as hub state.
- **DELIVER** — the frame the hub sends to a subscriber; structurally a re‑emitted
  `PUBLISH`, so keypress‑origin and tool‑origin events look identical to subscribers.
- **Retained subject** — a subject whose last `RETAINED` value the hub replays to new
  subscribers (e.g. current mode).
- **Slow consumer** — a subscriber that cannot keep up; handled by bounded per‑client
  queues and a drop‑oldest / disconnect policy (PROTOCOL §9).
- **Event tap / frontend** — the per‑OS, privileged component that reads the keyboard
  (macOS `CGEventTap`, Linux `evdev`/`libinput`) and feeds chord matches to the hub.
- **Hot path** — keypress → matched binding → `write()` to open fds. The path that must
  never spawn a process or allocate.
- **`libnwp`** — the planned C‑ABI client library every language binds against.
