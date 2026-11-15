# Play-test checklist

The user plays several built milestones at once and gives all feedback in one round (decided 2026-11-14). Every task adds here what only a person playing can judge: feel, look, sound, numbers, anything not caught by tests or screenshots. Tick items off or write the verdict next to them during the play-test; settled items move out (fixes go into the next milestone, decisions into `docs/PLAN.md` §8).

How to start: the latest release from GitHub, or `python tools/dev.py` from a checkout. Solo is the main menu's Solo; since M34 you start on the Barrowlands, the old realm's mobs are through the "To the old barrow" gate behind the spawn. Two players: host from the menu and join with the room code.

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

Enemy kinds as data (task 2, `data/enemies/*.tres`, protocol 18; the old realm's encounter is the only place it shows until the pool exists):

- [ ] The old realm's swordsmen, archer and the Warden fight as before: chase, chop, keep distance and shoot, sweep, slam, volley, phase 2 and the well, the dummies in the keep swing and heal.
- [ ] Seen from a second client (also one that joins mid-fight), mobs and the Warden look right and carry the right health bar (none on the Warden).
- [ ] Enemy body hitboxes feel the same (the Warden is 4.2 m tall, 1.2 m wide) and enemies still flinch, slide and parry as in M19.

The pool (task 3, `World._add_pool`, protocol 19; hidden slots, 24 then and 20 after task 5; only the old realm's four are awake):

- [ ] The keep and the old realm play as before with the hidden slots in the world: swings land on every mob and the Warden once per swing, bolts hit, no new hitching on a client (F3 frame time at the keep, in the realm fight).
- [ ] A second client joining mid-fight sees the same mobs and Warden, and no stray enemy models at the world origin.

The spawner (task 4, `sim/spawner.gd`; camps and roamers on the Barrowlands):

- [ ] Walking the Barrowlands you meet something every minute or two (a camp of 3 to 6 or a lone skeleton); too many or too few: tune `Spawner.CAMP_AREA`, `ROAMER_AREA`.
- [ ] Camps wake as you come near (about 90 m: they rise from the ground over 3 s) and are gone again once you are well away (about 140 m); no enemy pops in or out in view, none stands in a tree or boulder or on a cliff, and the arrival and gates are calm.
- [ ] A camp you cleared stays empty while you stay near and comes back after about 10 minutes; leaving one mid-fight does not make the survivors vanish while you can still see them.
- [ ] Two players near the same camp see the same enemies at the same places; one who walks up later sees them already there (no flicker).
- [ ] Camps feel right: skeletons reach you one or two at a time or all at once (notice 16 m, leash 24 m), the archers are placed so they can be hunted.

The pool size (task 5, `World.POOL` 20 after the load test with bots):

- [ ] Fight a camp of 5 or 6 with a second player, then walk to a camp nearby: both stay awake and the frame time and ping (F3) stay steady; no rubberbanding in rolls and blocks while three or more camps are awake around you (the bots' load test held 29 tps with a tick loop of 60 to 90 ms, so a real fight is the check).
- [ ] With the pool full (three camps near), a fourth camp stays asleep until slots free up: it is not frozen half awake, and the camps you cleared do not make it wake with missing members.

## M33 Map

The map (task 1, `client/map_panel.gd`; hold M on the Barrowlands, the mouse is free while it is open and the player stands still):

- [ ] M held on the Barrowlands shows the terrain with you in the middle as an arrow, the camera's forward up; turning the camera turns the map, walking moves it, and releasing M gives the mouse back. Zoom with the wheel from about 150 m to the whole realm; the terrain image appears within a few seconds of the first opening (markers alone until then) with no frame hitch.
- [ ] The terrain matches the ground: a hill or ridge you can see in the world is light and shaded on the map in the same place and direction; the arrival gate "To the old barrow" stands 10 m behind where you arrived.
- [ ] Camps (rings with their size) and roamers (dots) match what you meet; awake enemies show colored by kind and move; hovering a marker names it (kind, slot, action, camp, distance); a second player shows as a green dot.
- [ ] In the old realm the map says "No map here". It does not pause the game: enemies keep moving while it is open.

Debug details (task 2; the wake and sleep rings always, cleared camps only in solo, as host, or on a server started with `--debug-map`):

- [ ] Two rings around every player: yellow at 90 m (camps wake) and blue at 140 m (camps sleep), matching the distances at which you see a camp's enemies appear and vanish.
- [ ] Kill a whole camp, open the map: its ring shows dimmed with a cross and hovering says "cleared, N s left" counting down from 600; after 10 minutes (or on a fresh world) it is a normal ring again and the enemies are back. On a friend's client (not host, no `--debug-map`) camps are never shown as cleared.

## M34 Start at the gate

Spawn on the realm (task 1, `sim/layout.gd`, `sim/world.gd`; protocol 23; the gate has no look until task 2, only the old stone arch):

- [ ] A fresh solo start puts you on the Barrowlands ground by the arrival, facing the two training dummies about 8 m ahead; no void, no falling, no keep.
- [ ] Hitting the dummies works as it did in the keep (the left one only takes hits, the right one swings back).
- [ ] Dying sends you back to the same spot, standing on the ground, with the dummies still there.
- [ ] Behind you, 10 m back, stands the arch "To the old barrow": walking in lands you in the old realm at the origin (mobs and Warden as before); its "Home" gates, also the portal after the Warden, lead back to the Barrowlands spawn.
- [ ] The old realm resets (mobs back, Warden hidden) once everybody has left it, also when the last player dies there.
- [ ] Two or more players join one after another: each appears on the ring around the arrival on the ground, and sees the other standing on it.
- [ ] The HUD goal line, the Discord presence ("In the Barrowlands") and the wind match the Barrowlands from the first second.

The gate's look (task 2, `Arena._arrival_look`; scatter was already clear 30 m around the arrival):

- [ ] The arrival reads as a place: a ring of standing stones (dark gray, about 2.5 m tall, no runes carved yet) around the spawn with gaps ahead (dummies) and behind (the arch), and two torches on posts with flickering light left and right just behind the spawn.
- [ ] No stone, post or torch floats above the ground or sinks into a slope, and no tree or boulder grows through the ring, the dummies or the arch.
- [ ] The stones are solid since M35 (see "M35 Scatter collision").

## M35 Scatter collision

Task 1 (`sim/scatter_shape.gd`, `data/scatter/*.tres`, `sim/terrain_chunks.gd`, `Arena.add_arrival_solids`; protocol 24). Run with `--show-collision` to see the shapes (blue wireframes, the ground too):

- [ ] Pines, birches, boulders and standing stones stop you: you cannot walk, sprint or roll through a trunk or rock, and you slide along them instead of sticking when you hit one at an angle.
- [ ] The shapes match what you see: a trunk stops you at the trunk (not at the crown, you can walk under branches), a boulder at its rock, a standing stone at the stone; no invisible walls beside them and no gaps you walk through.
- [ ] Burial mounds are low domes you can walk up and over without getting stuck.
- [ ] Crossbow bolts stop in trunks and rocks, and you cannot aim or shoot through a tree at an enemy behind it.
- [ ] The arrival's stone ring is solid: the stones stop you, the gaps between them let you through, and the two gaps ahead (dummies) and behind (arch) are open.
- [ ] The arch "To the old barrow": its two pillars are solid, the opening between them is not; walking through the middle still takes you to the old realm. The lintel is over your head (jump under it).
- [ ] Nobody spawns, respawns or arrives through a gate stuck inside a tree, rock or stone, and the dummies stand free.
- [ ] Two players in a forest (or a friend on a worse connection) walk around trees without rubberbanding at them; tree collision shows the same on every peer, also with graphics on Low (fewer trees drawn, same trees solid).
- [ ] Frame rate and the server tick (F3: tick loop, tps) look the same in the forest as on the open moor.
- [ ] Enemies chasing you slide around trunks and boulders instead of sticking: run around a tree with a skeleton behind you, then lead a camp through a forest. Note any that stay stuck, jitter at a trunk, or circle forever.
- [ ] No enemy wakes inside a tree, rock or stone (walk up to several camps; camps now stand a little differently than before M35).
- [ ] Is the forest too dense to walk and fight in? M35 task 1 found no 100 m straight line free of trees in 72 headings from one point. Note where it feels tight (pine woods?), and whether fighting a camp among trunks is fun or a chore.
- [ ] Opening the map (M) for the first time does not freeze noticeably (`Spawner.points` now takes about 1 s in a debug build).
