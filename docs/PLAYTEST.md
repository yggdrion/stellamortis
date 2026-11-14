# Play-test checklist

The user plays several built milestones at once and gives all feedback in one round (decided 2026-11-14). Every task adds here what only a person playing can judge: feel, look, sound, numbers, anything not caught by tests or screenshots. Tick items off or write the verdict next to them during the play-test; settled items move out (fixes go into the next milestone, decisions into `docs/PLAN.md` §8).

How to start: the latest release from GitHub, or `python tools/dev.py` from a checkout. Solo is the main menu's Solo; the realm mobs are through the keep's portal. Two players: host from the menu and join with the room code.

## M16 Frame pacing

- [ ] Settings: vsync off and a cap of 60, 120 or 144: F3 shows the frame rate holding at the cap.
- [ ] Vsync on: F3 shows the vsync note; the cap still limits below the refresh rate.
- [ ] Leave to the menu and start another game: the saved cap still applies (not stuck from the last game).

## M19 Hit feel

Knockback and flinch (task 1, numbers in `game/data/attacks/*.tres` and `game/data/tuning.tres`):

- [ ] Light hits push a mob a little and do not stop its swing; the third light and the heavy push it clearly and interrupt its windup.
- [ ] The Warden never flinches and slides only a hair.
- [ ] Getting hit pushes you back; blocking pushes you about a quarter as far; a guard break pushes fully.
- [ ] Crossbow bolts nudge and briefly flinch mobs.

Hit stop, shake, blood and sparks (task 2, numbers in `client/hit_effects.gd`, `client/camera_rig.gd`):

- [ ] Hits land: the short freeze on both the attacker and the victim reads as weight, not as lag.
- [ ] Camera shake is noticeable on heavy hits and taken hits, not sickening; the "Camera shake" slider turns it down and off.
- [ ] Blood on mobs, sparks on the Warden, splinters and sparks on your blocked shield. Blood specks may be too small (0.1 m).
- [ ] Bigger damage numbers and a stronger flash on heavy hits.
- [ ] Nothing fires twice for one hit, also with a second player and some lag.

Deaths and hit sounds (task 3, `client/enemy_view.gd`, `shaders/burn_away.gdshader`):

- [ ] A killed mob falls, lies about 2 s, then burns away from the edges with a glowing rim and rising embers (never seen on a real kill yet).
- [ ] After a wipe or the encounter reset, the mobs come back whole (no half-burnt bodies).
- [ ] Hit sounds: a thud on every hit, the blade sound only on heavy hits, a low boom on a kill, the clang on the Warden. Light hits lost the slash sound: does that still feel right?

## M20 Big round realm

Built task by task; items are added as the tasks land.

- [ ] Joining a hosted game and a solo game still work (the world seed is sent on join; protocol 15).
