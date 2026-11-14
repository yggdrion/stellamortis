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

Streamed collision (task 3, `sim/terrain_chunks.gd`; needs the gate of task 4 to reach the realm, or `--spawn` in the realm):

- [ ] Running across the Barrowlands never shows a hitch from chunks being added (watch F3 frame time while sprinting over hills).
- [ ] You never fall through the ground, also when jumping off a ridge and landing on a slope.
- [ ] A steep hillside is not climbed like stairs: a slope near 50 degrees stops you or lets you slide, with no jerking up the slope.
- [ ] Two players in the realm see each other standing on the ground, not sunk in or floating.

Gates and places (task 4, `sim/layout.gd`, `sim/portal.gd`; protocol 16; the realm has no look until task 5, so the ground is invisible):

- [ ] The keep has two gates side by side in its south wall, "To the Barrows" and "To the Barrowlands"; stepping into the second lands you on the ground at the realm arrival and does not drop you.
- [ ] In the Barrowlands the gate home stands about 10 m behind the arrival, looks the same as the keep gates, and takes you back to the keep.
- [ ] Walking around in the Barrowlands the HUD goal line names the place, the wind sound is the Barrows wind, steps sound like grass, and nothing of the keep or the old realm is drawn.
- [ ] Gravity feels normal (9.8) on the Barrowlands ground and pulls toward the realm center, also on a hillside; leaving its reach in a jump pad-less fall is not possible to test yet.
- [ ] Two players travelling together through the gate each arrive on a different spot of the ring on the same ground.

The look (task 5, `client/terrain_view.gd`, `sim/scatter.gd`, `shaders/terrain.gdshader`, `client/graphics.gd`; the realm now has ground, forest and a moving moon):

- [ ] It reads as land, not as a ball: walk 300 m in one direction and over a hill; the ground never feels like a small planet. If it does, raise `radius` and hill height in `data/realms/barrowlands.tres` before anything else.
- [ ] The horizon is never empty or ragged: from a hilltop the far hills are there (the coarse shell), with no bright or dark seam where the near chunks end and the shell begins, and no ground flickering through the near ground (the shell hangs 4 m below).
- [ ] Fog and night: dim and cold but never black, trees and stones readable at 100 m; the moon and the banded planet in the sky move with you around the realm (the moon follows your local up, `Arena.follow_up`) and the sky never turns upside down after a long walk, also near the realm's cube-face corners.
- [ ] The big banded planet in the sky (from the old space sky) may read as sci-fi against the northern look: keep, swap for a moon or remove?
- [ ] Trees (Kenney Nature Kit, recolored) may read too cartoonish next to the characters: good enough, or look for other CC0 trees?
- [ ] Grass, heather and rock: the ground changes with height and slope (grey rock on steep ground and on the high ridges, a purple-brown heather in patches); is the heather visible at all, and does the rock read as rock?
- [ ] Scatter: pines in clumps, a pale-trunked birch fringe, boulders on steep slopes, standing stones on high flat ground and low burial mounds in the open. Tune the numbers in `Scatter` (chances, `PINE_FROM`, `SPACING`) and the sizes and colors in `TerrainView.LOOKS`: trunks look thick, foliage and bark are dark (nearly black bark), boulders are flat.
- [ ] The arrival is clear of trees (30 m) and the home gate stands in view of it.
- [ ] Scatter density and view distance per preset (F4): Low 35% density out to 120 m and ground to 250 m, Medium 60%, High and Ultra everything out to 260 and 340 m. Is each preset still a forest? Does switching preset while standing in the realm rebuild the scatter without a hitch?
- [ ] Frame time on Low and High while running through the forest and over the ridge: no hitch when chunks stream in (meshes and scatter are built on workers, 2 chunks per frame), the F3 frame time near the numbers in `docs/PLAN.md` §3.1 (measured on an RTX 4080 only: vsync-bound, GPU 1.3 to 2.4 ms on Low and High; the 1050 Ti numbers were not measured).
- [ ] Two players on the realm see the same trees and stones in the same places (the scatter is seeded, nothing is sent).

## M21 Enemy pool

Enemies follow gravity (task 1, `sim/enemy.gd`, `client/enemy_view.gd`; protocol 17; only reachable once task 4 puts enemies on the realm, or by placing one there with a test):

- [ ] An enemy standing or walking on a Barrowlands hillside stands upright along the local up, its feet on the ground, also over a ridge, and turns to follow a player round a hill without sliding sideways or sinking in.
- [ ] Seen from another client, the same enemy has the same posture (no wobble when `up` follows the gravity while it walks).
- [ ] Keep dummies, the old realm's mobs and the Warden behave as before.
