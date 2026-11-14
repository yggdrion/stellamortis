# M13 Discord Rich Presence

Status: done (2026-11-09).

Written before the briefs existed, so this file keeps the milestone's original "done when" text. What was built is in `docs/PLAN.md` §4; what it left open is in §8.

## Done when

Discord application "Stellamortis", application ID `1563509032348557382` (public). A logo in the M12 style (SVG, exported 1024×1024 PNG for the app icon and the Rich Presence art, also used as the game icon); the user uploads it in the developer portal. Presence shows the mode (in the menu, Solo, Hosting), the party size (n of 6) and the elapsed time; no room code. Client: a GDExtension or the Discord IPC; skipped when Discord is not running
