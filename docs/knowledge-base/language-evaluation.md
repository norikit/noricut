# Implementation‑language evaluation

The protocol (`../PROTOCOL.md`) is language‑agnostic on the wire. This document decides
what the **broker core** should be *written in*. The choice is long‑lived and
hard‑to‑reverse, so it is tracked as an open question (Q1) pending owner ratification —
this is the analysis to ratify against.

The architecture (`architecture.md` §1) splits noricut into a **portable broker core** and
**OS event‑tap frontends**. These have different language pressures and the decision is
made per part:

- **Broker core:** a long‑lived, multi‑client, non‑blocking socket server that must not
  crash, must idle near 0% CPU, must have bounded tail latency, and should be a small
  dependency‑free static binary that is easy to bind from other languages.
- **Event‑tap frontends:** per‑OS, privileged, native API code. Here "match the platform"
  dominates — Swift on macOS (shares idioms/tooling with noribar), C/Rust against
  evdev/libinput on Linux. This document does **not** force one language on the frontends.

## What actually matters for the broker

Weighted by relevance to *this* daemon:

| Factor | Why it matters here | Weight |
|--------|---------------------|--------|
| Crash‑proneness / robustness | A broker that segfaults takes every tool's hotkeys down with it. Must be rock‑solid over weeks of uptime. | ★★★★★ |
| Memory safety | Many concurrent connections, reused frame buffers, opaque payloads → classic use‑after‑free / overflow territory. | ★★★★★ |
| Tail latency / determinism | The whole point is bounded, jitter‑free dispatch. GC pauses or unpredictable allocation hurt the headline feature. | ★★★★☆ |
| Idle footprint (CPU/RAM) | Must idle at ~0% like noribar. Runtime/GC overhead works against this. | ★★★★☆ |
| FFI / bindability | We ship a C‑ABI client lib (`libnwp`) that every language binds. The core should expose or interop with a C ABI cleanly. | ★★★★☆ |
| Raw throughput | Real but secondary — dispatch is tiny; correctness and tails matter more than peak ops/sec. | ★★★☆☆ |
| Portability of toolchain | Must build cleanly on macOS/Linux/BSD/Windows. | ★★★☆☆ |
| Dev velocity / maintainability | Small team; the code should stay legible and safe to change. | ★★★☆☆ |
| Org fit | noribar is Swift + vendored C; pragmatic, dependency‑light. | ★★☆☆☆ |

## Candidates

### C
- **Performance / footprint:** best‑in‑class. Tiny static binary, instant startup, zero
  runtime, deterministic, no GC. Trivial `epoll`/`kqueue`. Universal C ABI — `libnwp` is
  native.
- **Memory safety:** none. Manual lifetimes across many connections + reused buffers +
  opaque payloads is exactly where C produces use‑after‑free, double‑free, and buffer
  overflows.
- **Crash‑proneness:** high. A single pointer bug downs the whole hotkey system; some
  classes are also security bugs on a socket that other local processes talk to.
- **Verdict:** unbeatable on perf/footprint/FFI, worst on the two ★★★★★ factors. Great for
  the *client lib*; risky for a long‑lived multi‑client *server*.

### Rust
- **Performance / footprint:** within noise of C; no GC; predictable latency; small static
  binary (musl). `mio`/`tokio` or hand‑rolled `epoll`/`kqueue` all viable; std‑only is
  feasible for a daemon this small.
- **Memory safety:** compile‑time guaranteed (no UAF/overflow/data‑race in safe code) with
  no GC cost — uniquely strong on the two factors that matter most here.
- **Crash‑proneness:** low. No segfaults in safe code; errors are `Result`, not crashes;
  `panic = "abort"` plus connection‑level isolation contains the rare logic panic to one
  client.
- **FFI:** first‑class C ABI via `#[no_mangle]`/`extern "C"` and `cdylib` → `libnwp` ships
  as a Rust `cdylib` with a C header, bindable everywhere.
- **Cost:** steeper learning curve; longer compile times; borrow‑checker friction around
  the connection graph (resolved with arena/slotmap indices instead of `Rc` cycles).
- **Verdict:** best alignment with the broker's weighted priorities — C‑class
  perf/footprint/FFI *and* the memory safety + crash resistance a long‑lived broker needs.

### Zig
- **Performance / footprint:** C‑class, excellent cross‑compilation, clean C interop, no
  GC. Comptime is pleasant for the framing code.
- **Memory safety:** better than C (bounds checks in safe builds, no hidden UB in many
  spots) but still manual lifetimes — not the compile‑time guarantee Rust gives.
- **Crash‑proneness:** medium, and the language is **pre‑1.0**: breaking changes and a
  thinner ecosystem are a real maintenance risk for a foundational daemon.
- **Verdict:** attractive and very close to the ideal on perf/interop, but the safety gap
  vs Rust plus pre‑1.0 instability make it a gamble for the core. Strong alternative for
  the client lib.

### Go
- **Performance / footprint:** fast enough; goroutines make the concurrent server trivial
  to write. But a GC and a multi‑MB runtime mean a larger idle RSS and **GC pauses**
  (usually sub‑ms, but nonzero and not fully controllable) — directly at odds with the
  "bounded tail latency, ~0% idle" headline.
- **Memory safety:** safe (GC), though data races are still possible without care.
- **Crash‑proneness:** low for memory bugs; nil‑deref panics exist but are recoverable.
- **FFI:** the weak point. `cgo` is awkward and slow, and exporting a clean C ABI
  (`c-shared`) drags in the Go runtime — poor fit for the "tiny embeddable `libnwp`" plan.
- **Verdict:** great ergonomics, but GC tail‑latency + heavy/awkward FFI conflict with two
  of our top factors. Not the core; fine for tooling.

### Swift
- **Performance / footprint:** good; ARC (deterministic, no tracing‑GC pauses) but
  retain/release has cost and the runtime + stdlib add footprint. SwiftNIO makes the
  server easy.
- **Memory safety:** memory‑safe under ARC, **but** force‑unwraps, `fatalError`, and
  precondition failures are idiomatic crash points; retain cycles leak rather than crash.
- **Crash‑proneness:** medium — the language *traps* on many error conditions by design.
- **Portability:** excellent on Apple platforms; server‑side Swift on Linux is real but
  less battle‑tested for a low‑level socket daemon, and Windows support is weakest.
- **Org fit:** highest — same as noribar; ideal for the **macOS event‑tap frontend**,
  where it should likely be used regardless of the core choice.
- **Verdict:** best for the macOS frontend, weakest as the portable, OS‑agnostic broker
  core (footprint, cross‑platform maturity, trap‑on‑error model).

### C++
- C‑class performance with RAII/smart pointers improving on raw C, and a rich ecosystem.
  But it remains UB‑prone, the safety story is opt‑in and partial, and build/dependency
  complexity is high. Offers no decisive advantage over Rust on our top factors. Not
  recommended for a greenfield core.

## Scorecard (broker core, 5 = best)

| | C | Rust | Zig | Go | Swift | C++ |
|--|---|------|-----|----|----|-----|
| Crash‑proneness (robust) ★★★★★ | 2 | 5 | 3 | 4 | 3 | 3 |
| Memory safety ★★★★★ | 1 | 5 | 3 | 4 | 4 | 3 |
| Tail latency / determinism ★★★★☆ | 5 | 5 | 5 | 3 | 4 | 5 |
| Idle footprint ★★★★☆ | 5 | 5 | 5 | 3 | 3 | 4 |
| FFI / bindability ★★★★☆ | 5 | 5 | 5 | 2 | 3 | 4 |
| Throughput ★★★☆☆ | 5 | 5 | 5 | 4 | 4 | 5 |
| Toolchain portability ★★★☆☆ | 5 | 4 | 4 | 5 | 3 | 4 |
| Dev velocity ★★★☆☆ | 2 | 3 | 3 | 5 | 4 | 3 |
| Org fit ★★☆☆☆ | 4 | 3 | 2 | 2 | 5 | 3 |

Reading the table against the weights, the two ★★★★★ rows (robustness + memory safety)
are decisive for a daemon that must never take the system's hotkeys down. C and Zig win
footprint/FFI but lose exactly there; Go and Swift are safe but pay in FFI and
tail‑latency/footprint respectively.

## Recommendation

- **Broker core → Rust.** It is the only candidate that scores top marks on *both*
  decisive factors (crash‑proneness, memory safety) while staying C‑class on tail latency,
  footprint, throughput, and C‑ABI FFI. It yields a single small static binary, idles near
  0%, and exposes `libnwp` as a `cdylib` for every other language. The costs (compile
  times, learning curve, borrow‑checker friction on the connection graph) are one‑time and
  bounded for a codebase this size.
- **Client library → ship the C ABI from the Rust `cdylib`** (`libnwp`), so C, Python, Go,
  Lua, etc. all bind one artifact. A hand‑written C client may also be kept as a
  reference/conformance implementation because the protocol is small enough to make that
  cheap.
- **macOS event‑tap frontend → Swift**, sharing idioms and tooling with noribar and using
  `CGEventTap` natively. It talks to the core purely over NWP, so this choice is
  independent of the core.
- **Strong alternative:** if the org prefers to stay maximally lean and C‑forward, **C for
  the core** is defensible *provided* it is paired with disciplined practice
  (ASan/UBSan/fuzzing in CI, a strict allocation/lifetime model). The trade is explicitly
  accepting manual memory safety on a socket‑facing, always‑on daemon — the analysis above
  argues Rust removes that risk at negligible perf cost.

Final ratification is owner's call — tracked in `open-questions.md` (Q1).
