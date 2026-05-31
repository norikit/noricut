-- Example noricut configuration (illustrative; the daemon does not exist yet).
-- Mirrors noribar's embedded‑Lua, hot‑reloadable style. See docs/knowledge-base/
-- architecture.md §5 and docs/PROTOCOL.md for the underlying model.
--
-- The core idea: a chord publishes to a SUBJECT. Long‑running tools (noribar, a window
-- manager, your own script host) subscribe to that subject over NWP and react
-- in‑process. No shell command is spawned on the hot path.

-- ── Plain chord → subject ──────────────────────────────────────────────────────────
-- Subscribers do the work; noricut just delivers the event.
noricut.bind("cmd - h", "key.focus.west")
noricut.bind("cmd - j", "key.focus.south")
noricut.bind("cmd - k", "key.focus.north")
noricut.bind("cmd - l", "key.focus.east")

noricut.bind("cmd + shift - f", "key.window.fullscreen")

-- ── Carry data with the event (default `kv` envelope) ──────────────────────────────
noricut.bind("cmd - 1", "key.space.focus", { kv = { index = "1" } })
noricut.bind("cmd - 2", "key.space.focus", { kv = { index = "2" } })

-- ── Modes (sticky binding layers, skhd‑style) ──────────────────────────────────────
noricut.mode("resize", function(m)
  m.bind("h", "key.resize.shrink_x")
  m.bind("l", "key.resize.grow_x")
  m.bind("j", "key.resize.grow_y")
  m.bind("k", "key.resize.shrink_y")
  m.bind("escape", function() m.exit() end)
end)
noricut.bind("cmd - r", function() noricut.enter("resize") end)

-- ── In‑process handler (no external subscriber required) ────────────────────────────
noricut.on("key.focus.west", function(e)
  -- e.kv.chord, e.kv._ts, e.kv._src, ...
  -- (Lua handlers run inside the daemon; keep them tiny and non‑blocking.)
end)

-- ── Escape hatch: still allowed, explicitly off the hot path (see open‑question Q5) ──
-- Prefer a subject + subscriber for anything latency‑sensitive.
noricut.bind("cmd - return", { exec = "open -na Alacritty" })
