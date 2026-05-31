# Glossary

- **Hub / broker** — the noricut daemon: owns the OS keyboard tap and routes messages
  between clients. The single point everything connects to.
- **Client** — any process holding a persistent NWP connection to the hub. Roles: `PUB`,
  `SUB`, `BIND` (see PROTOCOL §2).
- **NWP** — noricut Wire Protocol; the newline‑delimited‑JSON, subject‑routed IPC
  contract (`../PROTOCOL.md`).
- **Frame / line** — one message: a single‑line UTF‑8 JSON object terminated by `\n`
  (PROTOCOL §4). Binary length‑prefixed frames are an opt‑in (Appendix A).
- **NDJSON** — newline‑delimited JSON; the default framing/encoding (D13). "Read a line,
  parse JSON, write a line" — all standard‑library, no client library required.
- **Subject** — a hierarchical dotted topic (`key.focus.west`) a message is published to;
  the only thing the hub routes on (PROTOCOL §7).
- **`data`** — the application payload of a message: any JSON value; opaque to the hub and
  forwarded verbatim. Default convention is a flat JSON object of named fields.
- **`meta`** — hub‑appended origin info on a delivery (`src`/`ts`/`seq`), namespaced so the
  publisher's `data` stays exact (PROTOCOL §5.2).
- **Binding** — a mapping from a key chord to a subject (and optional `exec`), held in the
  hub's binding table.
- **Mode** — a sticky binding layer (the `skhd` "mode" concept) modeled as hub state.
- **`msg`** — the delivery the hub sends to a subscriber; structurally a re‑emitted `pub`,
  so keypress‑origin and tool‑origin events look identical to subscribers.
- **Retained subject** — a subject whose last `retain:true` value the hub replays to new
  subscribers (e.g. current mode).
- **Slow consumer** — a subscriber that cannot keep up; handled by bounded per‑client
  queues and a drop‑oldest / disconnect policy (PROTOCOL §9).
- **Event tap / frontend** — the per‑OS, privileged component that reads the keyboard
  (macOS `CGEventTap`, Linux `evdev`/`libinput`) and feeds chord matches to the hub.
- **Hot path** — keypress → matched binding → `write()` to open fds. The path that must
  never spawn a process or allocate (the per‑binding line is precomputed, §4.2).
- **`framing=binary`** — the opt‑in length‑prefixed binary mode (PROTOCOL Appendix A) for
  byte‑exact or large payloads; negotiated in `hello`. The default is NDJSON.
