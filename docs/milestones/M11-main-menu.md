# M11 Main menu

Status: done (2026-11-09).

Written before the briefs existed, so this file keeps the milestone's original "done when" text. What was built is in `docs/PLAN.md` §4; what it left open is in §8.

## Done when

A start menu instead of booting straight into solo: Solo, Host (opens a room, the code shows in game as today), Join by code (text field), Settings (graphics preset, mouse sensitivity, fullscreen; key bindings later), Player name (saved in `user://settings.cfg`), Quit. Escape in game opens a pause menu (Resume, Settings, Leave to menu, Quit); the game keeps running behind it. When the host quits, friends see "The host left" and return to the menu (no host migration). Plain functional look; M12 restyles it. The command line flags keep working for tests
