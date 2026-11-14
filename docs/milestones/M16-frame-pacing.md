# M16 Frame pacing

Status: in progress. Built on 2026-11-14 (`python tools/check.py` green); the user's check that the cap holds in F3 with vsync off is open. Required; independent of M19 to M29.

## Goal

The player chooses how frames are paced: vsync on or off, or a frame rate cap. Saved with the other settings and shown in the F3 overlay.

## Depends on

Nothing.

## Task (Sonnet)

Files: `game/scripts/client/settings.gd`, `client/settings_panel.gd`, `client/debug_overlay.gd`, `scripts/boot/main.gd`, a test in `game/tests/`.

Reuse: `Settings.load_saved`, `Settings.save`, `Settings.apply_window` (`settings.gd:18`, `:32`, `:48`), the option rows in `SettingsPanel._ready` (`settings_panel.gd:14`), the FPS line in `DebugOverlay._process` (`debug_overlay.gd:34`).

Steps:

1. `Settings.vsync` (bool, default on) and `Settings.max_fps` (int, 0 is unlimited, default 0), loaded and saved in `user://settings.cfg` with the rest.
2. `Settings.apply_window` sets `DisplayServer.window_set_vsync_mode` (enabled or disabled) and `Engine.max_fps`. Check both against the Godot 4.7 docs.
3. `SettingsPanel`: a vsync checkbox and a cap choice (Unlimited, 60, 120, 144, 165, 240). The cap applies whether vsync is on or off; with vsync on the display still limits it. Both menus share the panel, so both get it.
4. F3 overlay: show vsync and the cap next to the FPS line; its "incl. vsync wait" note only when vsync is on.
5. Flags for tests and benchmarks: `--vsync=on|off`, `--max-fps=N`, not saved.

Tests: settings round-trip through a temp config file; `apply_window` sets `Engine.max_fps`.

Done when: `python tools/check.py` is green and the user sees the cap hold in F3 with vsync off.

## Out of scope

Adaptive vsync, mailbox mode, a frame time graph, per preset caps.

## Pitfalls

- Headless servers and bots must not be capped: apply only where a window exists (`apply_window` is client only).
- The server tick is `NetworkTime` at 30 Hz and does not depend on the frame rate, but the client's tick loop runs inside frames: a cap below 30 would starve it. The lowest choice is 60.
- A menu that applies the cap must not leave `Engine.max_fps` set when the client returns to the main menu and starts another game: apply from the saved setting each time.
