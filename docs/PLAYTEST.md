# Play-test checklist

The user plays several built milestones at once and gives all feedback in one round (decided 2026-11-14). Every task adds here what only a person playing can judge: feel, look, sound, numbers, anything not caught by tests or screenshots. Tick items off or write the verdict next to them during the play-test; settled items move out (fixes go into the next milestone, decisions into `docs/PLAN.md` §8).

How to start: the latest release from GitHub, or `python tools/dev.py` from a checkout. Solo is the main menu's Play (Solo); since M34 you start on the Barrowlands, the old realm's mobs are through the "To the old barrow" gate behind the spawn. Two players: host from the menu and join with the room code.

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

- [ ] Fight a camp of 5 or 6 with a second player, then walk to a camp nearby: both stay awake and the frame time and ping (F3) stay steady; no rubberbanding in rolls and blocks while three or more camps are awake around you (the bots' load test held 29 tps with a tick loop of 60 to 90 ms, so a real fight is the check). (covered by bots, server side: tps, tick loop and corrections in `soak_30min`, `camp_party_mixed`, `boss_party_mixed_lag`; the frame time and the feel stay yours)
- [ ] With the pool full (three camps near), a fourth camp stays asleep until slots free up: it is not frozen half awake, and the camps you cleared do not make it wake with missing members.

## M33 Map

The map (task 1, `client/map_panel.gd`; hold M on the Barrowlands, the mouse is free while it is open; since M43 north is up and you can walk, see M43):

- [ ] M held on the Barrowlands shows the terrain with you in the middle as an arrow, north up; turning the camera turns only the arrow, walking moves the map, and releasing M gives the mouse back. Zoom with the wheel from about 150 m to the whole realm; the terrain image appears within a few seconds of the first opening (markers alone until then) with no frame hitch.
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
- [ ] Frame rate and the server tick (F3: tick loop, tps) look the same in the forest as on the open moor. (covered by bots, server side: tps, tick loop and corrections in `soak_30min`, `camp_party_mixed`, `boss_party_mixed_lag`; the frame time and the feel stay yours)
- [ ] Enemies chasing you slide around trunks and boulders instead of sticking: run around a tree with a skeleton behind you, then lead a camp through a forest. Note any that stay stuck, jitter at a trunk, or circle forever.
- [ ] No enemy wakes inside a tree, rock or stone (walk up to several camps; camps now stand a little differently than before M35).
- [ ] Is the forest too dense to walk and fight in? M35 task 1 found no 100 m straight line free of trees in 72 headings from one point. Note where it feels tight (pine woods?), and whether fighting a camp among trunks is fun or a chore.
- [ ] Opening the map (M) for the first time does not freeze noticeably (`Spawner.points` now takes about 1 s in a debug build).

## M22 Barrowlands bestiary and boss

Task 1 and 2 so far (`EnemyDef.guard_arc`, `AttackDef.leap`/`next`, the kinds `shield_bearer`, `berserker`, `barrow_elite`, camp recipes in `Spawner.RECIPES`; protocol 27). The map (hold M) colors each kind and shows the camps; camps now mix kinds, so walk up to a few. Numbers are first guesses, judge them by feel.

Shield bearer (helm, tower shield, 170 health, slow):
- [ ] From the front your sword and bolts barely hurt it (a fifth or so of the damage, a small guard flash, no knockback); from the side or back you deal full damage.
- [ ] Its bash telegraphs long enough to read (orange fan in front, shield arm out) and a well-timed block parries it; the parry opens it up (riposte, ember "PARRY" flash) and you can punish it.
- [ ] Circling it works: it turns slowly (turn rate 4), you can get behind it without being hit if you keep moving. Does it feel fair or does the guard make it a chore?
- [ ] A heavy attack (Q) staggers it out of its bash windup; a light attack does not.
- [ ] A camp with archers stands with the bearers in front and archers behind; the archers' bolts hit you while the bearers hold you.

Berserker (bare, two axes, war paint, 55 health, fast):
- [ ] It runs at you and hacks quickly in melee (short windup); is the hack readable at all, or too quick?
- [ ] From about 8 m and closer (but not in melee reach) it crouches and leaps: the orange fan appears where it will land, not on the berserker, and it lands as the windup ends. Rolling out of the fan avoids the hit; standing in it hurts (38).
- [ ] After a leap it stays open for a long recovery (1.7 s): you can punish it with a combo; two or three hits kill it.
- [ ] A pair of berserkers leaping together is hard but fair; they do not stack on one spot forever.
- [ ] Sounds: a high shriek on its windup (a pitched `telegraph`), a swoosh on the strike.

Barrow elite (tall, rust-iron armor, 340 health, two hits and a slam):
- [ ] It is clearly bigger than the others and its armor reads in the dark (a ruddy iron, ember eyes).
- [ ] Up close it chains a cleave into a backhand without a pause; the second hit's fan shows the moment the first ends. Can you roll the first and the second, or block through both?
- [ ] At 3 to 5 m it winds up a ground slam (full circle in front of it, 360 degrees, cannot be parried): rolling away or backing out of the circle avoids it.
- [ ] It is hard to flinch (poise 0.6: only a heavy interrupts a swing) and slides little when hit; it staggers on a parry of the cleave.
- [ ] The elite's camp (with two bearers and archers) is a real fight, not a wall: is 340 health too much or too little?
- [ ] Sounds: a deep telegraph (the giant one, pitched up a little) on each windup.

Boss site and world flag (task 3: the old hand-built realm is gone, `Net.PROTOCOL_VERSION` 28; no gate to Myrkfen yet, the flag `warden_fallen` is only read by tests and the map). Walk 450 to 800 m from the arrival to find the site (hold M: a purple ring marked "boss site"), or start with `--encounter=boss` to spawn inside it:
- [ ] The site reads as a place: a flat ground disc with a ring of eight tall standing stones around it, no trees or boulders on it, no camp within 60 m. The ground blends into the hills without a cliff or a step (walk around its edge, also a jump up the blend).
- [ ] Walking into the ring raises the Warden from the middle (3 s rise, unhittable while it rises); the boss bar and "THE WARDEN" appear. Standing just outside the ring (within 80 m) does not wake it.
- [ ] Two or three players inside the ring when it rises make it tougher (+50 percent health per extra player); a friend who arrives late does not.
- [ ] Walk away: out of 80 m of the site with everyone, it sinks back (hidden, full health) and rises again on the next visit. Dying with the whole party does the same.
- [ ] The fight on the round ground: the sweep, slam (the circle in front of it) and volley behave like on flat ground, the telegraph fan lies on the ground also when the Warden stands on a slope, the well (phase 2) drags you toward it along the ground, not into the air or the earth. The standing stones stop bolts and block the way: does the ring help (cover) or annoy (a stone in the way of a roll)?
- [ ] The Warden's fall: the boss bar goes, the HUD says it has fallen and the map's site ring turns grey. The corpse stays; nothing resets it while the server runs (restart: it is back).
- [ ] A friend who joins after the kill sees the Warden's corpse and the grey ring too.
- [ ] The site's look (task 4, client only; `--seed=1234 --encounter=boss` for a quick look): the standing stones are weathered grey rock and still show against the night on the side the moon misses; four torch posts stand between them; a mound with a brick door stands at the ring's edge (you can walk through it, it is only a picture); embers rise from the ring while the Warden is up and stop when it falls or the fight resets, with a burst as it rises. Does it read as an old barrow site, dark medieval, not a clearing with boxes? Do the site's torch lights (4 posts and the door's 2) hurt the frame rate on Medium and Low?
- [ ] Is 450 to 800 m far enough away and near enough? Is the ring easy to find on the map, and is the flat disc distinct from the ground around it?

General:
- [ ] Every kind's telegraph fan sits on the ground on slopes (no clipping into hills), and nobody leaps through a trunk.
- [ ] Camps of each recipe turn up often enough (about 40 percent plain dead, 25 percent bearers and archers, 20 percent berserkers, 15 percent elite with guards) and roamers (a lone swordsman, archer or berserker) are not too dangerous alone.
- [ ] The frame rate and the server tick (F3) hold in a camp of six, also an elite camp. (covered by bots, server side: tps, tick loop and corrections in `soak_30min`, `camp_party_mixed`, `boss_party_mixed_lag`; the frame time and the feel stay yours)

## M23 Inventory, loot and saves

Task 1 so far (items, inventory and worn gear on the server, `Net.PROTOCOL_VERSION` 29). There is no panel or loot yet, so nothing to see besides this; the real checks come with the loot and the panel (tasks 2 and 3).

- [ ] Combat feels exactly as before M23: the starting kit (sword, wooden shield, crossbow, 20 bolts) has the old numbers (a light swing, a block, a full draw deal and stop what they did). Nothing about gear shows in the HUD yet.

Task 2 (loot feel, `Net.PROTOCOL_VERSION` 30; `--debug-loot` drops a row of items ahead of you, `--debug-loot=open` also opens the elite chests):

- [ ] Loot feel (the milestone's stated goal): kills burst into drops that fly out on an arc, land with a thud and glints, bob and turn; it is worth running for and the burst is satisfying, not noisy. Verdict, and what to change (arc height, glow size, sound, how many stacks per kill).
- [ ] Rarity reads at a glance: white, green and blue glow on the ground, blue and up stand under a light beam you see from far away. Only rarity 0 to 2 items exist so far, so purple and gold are unchecked (the chest is the only gold).
- [ ] E picks up the drop the prompt names (nearest within 2.5 m, the line above the notice); materials (hide, scrap, bone, ember) lean toward you and walk into the bag within 1.2 m; "+2 Iron scrap" toasts show; a full bag says "Bag full" and the item stays.
- [ ] The elite camp's chest stands behind the camp, shut and gold-lit; E says "The guards still stand" until every member is dead, then it opens (lid, creak, embers) and bursts out 3 pieces of uncommon or better. It stays open afterwards.
- [ ] The Warden's pile is generous (5 rolls, uncommon and better) and drops once, also when the fight is lost and retried.
- [ ] Items you drop (task 3 panel, or the bot) lie 3 s before they can be taken again, so you do not pick them straight back up.
- [ ] Drops on the ground, 31 chests and the bursts do not cost frame time or server tick time (F3) in a camp.

Task 3 (inventory panel and hotbar, `Net.PROTOCOL_VERSION` 31; `--debug-bag` joins with a mixed bag and part of the kit worn, `--inventory[=CELL]` opens the panel):

- [ ] I or Tab opens the panel, the mouse is free, the world runs on behind it (enemies keep moving, you stand still); I, Tab or Esc closes it and the mouse is captured again. Esc with the panel open closes the panel, not the pause menu.
- [ ] Drag and drop moves, merges and swaps stacks, bag to gear slot and back; dropping on a wrong slot does nothing. Each move shows only after the server answers: say if the delay (try `--lag`) feels bad without prediction.
- [ ] Without the mouse: arrows move the cursor (bag grid, doll, across), Enter lifts a stack and puts it down, E equips, unequips or uses, V splits half, X drops, R sorts, F stars junk. Say which key is awkward.
- [ ] Right click or shift click equips, unequips or uses; ctrl click splits half a stack.
- [ ] Hover (or arrow to) a wearable bag item: the tooltip shows its stats, the worn item of that slot below and the differences in green (better) or red (worse). Read it for the swords, armor pieces and the two trinkets.
- [ ] Junk: F stars an item kind, the star shows on every stack of it, Sort puts starred kinds last; the stars are still there after a restart (kept in the character file since task 4).
- [ ] Hotbar: bag cells 0 to 7 at the bottom; keys 3 to 8 use cells 0 to 5 (a bandage heals 35 and is used up, wearable gear is worn). Keys 3 to 8 sit far from the left hand on WASD: say if it is awkward in a fight, or if the hotbar should be its own cells. Play-test 2026-11-18: 1 and 2 should show as the primary and secondary weapon in a bar (M42).
- [ ] Sorting, dropping and picking up in a camp: is the panel quick enough to use between fights, and is anything missing (a "drop one", a mark all junk, storing into chests)?
- [ ] The item glyphs (drawn shapes, no art yet) are readable and tell weapons from armor from materials; say if you want real icons.

Task 4 (saves and graves, `Net.PROTOCOL_VERSION` 32; `--world=NAME` keeps the world in `user://worlds/NAME.json`, without it nothing is saved; the character is always in `user://characters/<name>.json`; `%APPDATA%/Godot/app_userdata/...` on Windows):

- [ ] Character: pick things up, quit, start again with the same player name: the bag and worn gear are as you left them (also after Alt+F4 within a second of the last change, and after the host's server crashed).
- [ ] World (`--world=test --seed=1234`): kill the Warden and clear a camp, leave, start with `--world=test` again: the Warden lies dead, its gate flag is set, the camp stays empty for the rest of its 10 minutes (a few minutes later it fills again), chests you opened stay open, drops that lay on the ground are still there.
- [ ] A world file from another seed wins over `--seed` (a note is printed); delete the file to start fresh. A broken file is renamed `.bad-<time>` and the game starts a new world.
- [ ] Death leaves a grave where you fell with your whole bag in it (gear stays on you); E at the grave (within 3 m) gives it all back, "Bag full" keeps what does not fit. Someone else gets "Not your grave" for 10 minutes, then can take it. Die twice: two graves, nothing lost. Check that the grave is easy to see and find.
- [ ] A grave survives a restart of the world, and is still yours after a restart of the game (the player ID is in the character file).

Task 5 (world list; the main menu's Play replaces Solo and Host):

- [ ] Play opens the world list. With no worlds it says so; New world with a name and an empty seed starts a solo game, and the next start lists that world with its seed, size and "just now".
- [ ] A name with spaces or symbols becomes a clean file name (`My World!` is `my_world_`); a seed field with letters is refused with a note; a seed you type gives that world (compare with `--seed`).
- [ ] Continue starts the most recently saved world; Play on a row starts that one. "Play as" Host opens a room for it, a friend joins by code and is never asked for a world.
- [ ] Delete asks first and names the world; afterwards it says whether the files went to the trash (check the Recycle Bin) or were removed. Keep it cancels.
- [ ] Put garbage in a file under `user://worlds/` (`%APPDATA%/Godot/app_userdata/...`): it shows as "unreadable" with Delete only, and nothing renames it.
- [ ] Say if the world list is clear enough, or if a world needs more on its row (last boss, play time).

## M36 Mesh kit and palette

Task 1 (kit, palette, shader; nothing visible in the game yet, the gallery comes with task 2):

- [ ] Look at the Barrowlands palette (`game/data/palettes/barrowlands.tres`) once the gallery exists: muted, dark, one family with the old Kenney trees and rocks? Say which roles feel off (bark, leaf, stone are the ones other kinds copy).
- [ ] The flat shader's sRGB conversion of vertex colors: does a `stone` face look like the old boulders' gray, not washed out or too dark?

Task 2 (gallery: `python tools/godot.py -- --gallery`, or `--gallery=rock` / `--gallery=pine_young`):

- [ ] Rocks and young pines read as one family: flat facets, muted colors, no shiny or washed-out faces. Say which look wrong (the palette roles `stone`, `stone_dark`, `bark`, `needle` are used).
- [ ] The three levels of each kind (front to back: full, half, far) keep the same silhouette and size; the far level is plainly cruder but not a different object.
- [ ] The five variants of a kind differ enough (size, lean of the cuts, layer count) without looking like another species.
- [ ] Next to the 1.8 m figure a rock is knee to hip high and a young pine about 3 to 5 m: right for the Barrowlands?
- [ ] The dusk light: shadow sides still readable, faces not black; is the facet size right (visible, not noisy)?

Task 3 (cost: `python tools/godot.py -- --gallery-stress=5000 --seconds=3 --graphics=low`, then `medium`, `high`; prints `STRESS` lines; without `--seconds` it keeps running and shows the last test):

- [ ] On your machine (and on the GTX 1050 Ti if you can): the `STRESS` lines for Low, Medium and High. Send the pine full line (`frame_avg`, `gpu`) and the grass full line (20000 tufts); in the numbers I measured on an RTX 4080 they were 0.8 to 1.0 ms and 0.7 to 0.9 ms. On the 1050 Ti above about 12 ms for 5000 pines at full detail means the budgets need cutting before M37.
- [ ] Look at the stress scene (`--gallery-stress=5000`, no `--seconds`): 5000 pines in a field, flat-shaded and colored, no flicker, no shimmering shadows; the grass and rock tests after it look like their gallery selves (the scene steps through all tests, about 40 s at 3 s each).

## M37 Generated terrain and scatter

Task 2 (tree generators: `python tools/godot.py -- --gallery=pine`, also `spruce`, `birch`, `oak`, `dead_tree`, or one id such as `--gallery=oak_old`; rows front to back are full, half, far):

- [ ] Each species reads as itself as a black shape: pine bare below, flat needle pads high up; spruce a narrow full cone to the ground; birch pale and slender with a few small clumps; oak short, thick, wide with heavy limbs; dead tree bare limbs only.
- [ ] Old trees (15 to 25 m) are landmarks next to the 1.8 m figure, trunks 0.8 to 1.6 m across with root ridges; grown ones are plainly smaller, young ones sapling size.
- [ ] The three levels keep silhouette and size; the far level is cruder, not another tree. No floating limbs, no dark flipped faces.
- [ ] Dusk light: leaf and needle colors read as green and muted, not brown or black (the gallery light is warm).

Task 3 (rock, stone and cover generators: `python tools/godot.py -- --gallery=rock`, also `boulder`, `outcrop`, `standing_stone`, `mound`, `grass`, `fern`, `heather`, `bush`, `log`, `stump`, `pebble`):

- [ ] Rocks, boulders and outcrops read as chipped, flattened, sunk stone of the right size beside the 1.8 m figure (rock about 1.2 m, boulder 3 m, outcrop 8 m); the outcrop is a ridge of lumps, not a ball.
- [ ] Standing stones are 4 m slabs that narrow upward and lean a little; mounds are low turf domes with kerb stones.
- [ ] Cover reads as grass, fern, heather, bush, log and stump at 2 to 5 m (tiny in the gallery shot: judge in the world once task 4 lands); blades and fronds are one sided, so check none vanish from behind.
- [ ] Moor, fringe and wood get different cover (heather on the moor, ferns in the wood); none stands on the spawn ring or the 30 m arrival clearing, nor inside a trunk or rock.

Task 4 (terrain and the view: `client/terrain_view.gd`, `shaders/terrain.gdshader`, `client/graphics.gd`; the realm now has no textures and no Kenney models):

- [ ] The ground reads as flat-shaded faces in muted palette colors: grass, a heather purple on the moor, earth under the dark woods and on the way to steep ground, grey stone on slopes and on the high ridges. Say which is off (too purple at the arrival? too uniform? faces too visible or too flat?). Numbers: the palette roles `grass`, `heather`, `earth`, `stone` and the uniforms in `shaders/terrain.gdshader`.
- [ ] Forest: five species, young to old (spruce in the dark high wood, pines in the middle, a birch fringe, oaks on low ground, the odd dead tree on the moor); old trees are landmarks in "old wood" patches. Is it a forest (dense enough, no bald patches, no walls of identical trees)? The four variants per kind should not repeat obviously.
- [ ] Levels of detail: walking through a wood, no tree pops visibly at 40 m or 120 m (a chunk swaps whole; the 8 to 72 m ring draws both levels on purpose), and nothing flickers or shimmers where both are drawn.
- [ ] Ground cover (grass, tall grass, ferns, heather, bushes, pebbles, logs, stumps): the moor is not bare, the wood floor has ferns, nothing grows inside trunks or rocks or on the arrival ring; cover thins out toward its radius without a visible line, and blades are visible from all sides.
- [ ] Rocks, boulders, outcrops, standing stones and mounds sit in the ground (no floating, no gap on slopes) and your feet and the Warden's camps meet the same shapes: run into a trunk, a boulder, an outcrop and stand on a mound (`--show-collision` draws the shapes).
- [ ] F3 shows `scatter triangles` (debug builds): under 1.5 M on Low, 2 M on Medium and High, 2.5 M on Ultra in the thickest wood you can find. Send the number if it is over.
- [ ] Frame time on your machine (and the GTX 1050 Ti if you can) per preset in old wood and on open moor: F3 render CPU and GPU time. On the RTX 4080 the numbers are in `docs/PLAN.md` section 3.1; above about 12 ms of GPU on the 1050 Ti the cover radius (`Graphics.COVER_RADIUS`) or the scatter radius is the knob.
- [ ] Switching the preset with F4 rebuilds the trees and cover around you within a second or two, with no stall and no leftovers of the old preset. Every preset shows the same trees nearby (only how far they reach, their detail and the cover change): walk into a trunk on Low, it is drawn.
- [ ] No hitch while running across the realm (chunks stream in with up to 100 model nodes each).

## M24 Bot play-tests

Task 1 (bot brain and skills):

- [ ] Skill calibration: play one camp and the Warden yourself, then watch `--bot --bot-skill=novice|average|good|expert --bot-goal=camp` (and `--encounter=boss --bot-goal=boss`) on the same spot. Say which skill plays like you: the numbers in `game/data/bots/*.tres` (reaction, dodge and parry chances and timing errors, stamina reserve, mistake rate, press cap) are guesses until you do.
- [ ] Baselines (task 4, numbers in `docs/PLAN.md` §8): the bots say the Warden is easy for experts (a solo expert wins 10 of 10 in 45 s, four experts in 12 s) and never lost to by novice or average, and a camp of four swordsmen is no threat to anyone. Does that match you? Say which of the two feels off: the Warden's health and damage, or the camp.
- [ ] A skill bot looks like a player and not a machine: it does not stare at the target with perfect aim, it rolls and parries visibly, it backs off to get its stamina back, and a novice swings itself empty and gets hit. Say what looks wrong.

## Join stall

- [ ] Start a solo game with `--seed=1234`: no "No word from the server" on the HUD in the first 15 s, and the ping in the debug overlay (F3) stays low; other players seen moving smoothly right after joining.

## M38 Generated props and sites

- [ ] The arrival: the ring stones (10, a gap ahead and behind) read as worked standing stones, not blobs; you cannot walk through them and the walls match what you see.
- [ ] The torches at the arrival and around the boss ring: flame glows, light flickers, the iron looks like iron; nothing floats or sinks.
- [ ] The boss site: barrow mound, door jambs and lintel, torch posts; the dark doorway sits in the mound's face.
- [ ] A gate (the test gate in a debug build, or after M60): the arch looks right around the veil; you can walk through the opening and not through the pillars.
- [ ] An elite's chest: it opens with the lid swinging up on its back edge (about 0.4 s), the glow and beam go out; it looks right from the front and the side.
- [ ] Colors: stone, wood and iron are readable at night and not pinkish.
- [ ] `python tools/godot.py -- --gallery` shows every prop at three levels; say which read badly at the far level.

## M39 Generated gear

- [ ] `python tools/godot.py -- --gallery=items`: sword, runed sword, axe, shields, crossbows, helm, chain shirt and greaves each read as what they are; tier differences (runed sword's gold, iron shield's steel rim) show at a glance.
- [ ] In the hand: the sword, the round shield and the crossbow look right on your character and swing without clipping; equip the runed sword, the iron shield and the ash crossbow and the held model changes at once.
- [ ] Inventory (`I`): icons match the held models and are readable at slot size; the first open does not hitch.
- [ ] Dropped weapons and shields on the ground lie sensibly and are not tiny or huge.
- [ ] Enemies: the dead's swords look rusted, the berserker's axes dark and worn, the shield bearer's tower shield and helm fit; the Warden's helm, horns, crown, pauldrons and cape look like the old ones or better.
- [ ] No blade looks longer than the swing reaches (the sword and axe against what they hit).

## M40 Own bodies (tasks 1 to 4)

- [ ] Players: four looks by player (male A lean with short hair and beard, female A slim with long hair, male B broad with long hair and a full beard, female B with a bun) read as different people from the camera's distance; the faces are plain but not ugly.
- [ ] Animations: swings, roll, block, walk, sprint, crossbow aim and hit/death play without a bad bend at shoulders, hips or wrists; the sword stays in the hand; no model snaps back after a combo (the rubberband check).
- [ ] The dead (sunken, bone arms and shins, skull jaw), the squires, the berserker, the elites and the Warden look like what they are; the dead's flesh reads rotten, not just green; the Warden at twice the size is not a stretched sack.
- [ ] Death: bodies burn away as before (the flat burn material, embers).
- [ ] Hit flash and telegraph tints still show on the new bodies.
- [ ] Body colors: skin and hair colors are readable at night.
- [ ] Body pick: the main menu shows four turning previews (male A, male B, female A, female B) under the name; a click highlights one and the choice is still there after a restart; Solo and Host show it in game; a joiner on another machine shows as the body they picked on the host and on a third client; bots and an old settings file (no pick) start as male A.
- [ ] Training dummies: the two ahead of the arrival read as dummies (post, straw sack, target on the chest, a shield), not people; a hit flashes and sways one and plays the thud; a kill tips it over, it vanishes after about 2 s and stands up again when it rises; the telegraph tint and the fan still show when it swings.

## M41 Play-test fixes

- [ ] Shadows (task 1): press F4 through Low, Medium, High and Ultra at the arrival and in old wood at night; shade (rock faces away from the moon, under the canopy, the player's shadow) is about as bright and readable on all four, none near black. Ultra still has SSR and TAA; SSIL and SDFGI are gone on purpose.
- [ ] Trees, grass and bushes (task 3): in old wood a few giant trees stand among the old ones (up to about twice the old trees' size, trunks solid: walk into one, you stop at the trunk, not inside it); the moor and the wood edge have clearly more grass than before on every preset; bushes read as leafy bushes (dark inside, a few clumps on short stems), not rocks. Check Low is still smooth.
- [ ] Hands (task 2): the sword leaves the closed fist past the thumb (grip inside the fist, blade up when the arm is raised, not along the fingers); with the shield up (hold block) the shield's face looks out and away from the outer forearm, not at your chest; the crossbow aimed sits along the hands and points where you look. Swordsmen, berserkers (axes in both fists), shield bearers and the Warden hold their gear the same way. Idle and mid-swing both.

- [ ] Faces and hair (task 4): in the main menu body picker and in the world, all four bodies show a skin face (forehead, eyes, nose, cheeks, ears), hair only on the scalp and nape (long hair falls behind the head), the beard on the chin and jaw only (male A short, male B full); the dead (male, female) show rot-green faces with the same hair. No dark mask over the face from the front or the three-quarter view.

## M42 Loadout and equip load

Task 1 (the sim; the inventory panel's equip load line, the weapon bar and the spare starting gear come with tasks 2 and 3). Until the spares exist, reach the classes by editing a character file or `data/tuning.tres` (`equip_load_max` 20, then 10) or `--debug-bag`.

- [ ] Light is the roll you know: with the starting kit (9.0 of 25) nothing feels different from before (roll length, distance, stamina, walking).
- [ ] Medium (chain shirt and cap worn, 16.0 = 64 %): the roll is a little slower and shorter, costs more stamina, stamina comes back a little slower; noticeable, not punishing. Walking is 5 % slower.
- [ ] Heavy (`equip_load_max` 20 with the same gear): the roll is slow with a long recovery and a short invulnerable window; walking is 10 % slower; a dodge that works light fails if pressed on the light timing. The roll clip plays slower to match and the feet still plant when the body stops.
- [ ] Overloaded (`equip_load_max` 10): the roll key does nothing, attacks and blocks still start, walking and sprinting are 25 % slower, stamina comes back at 40 % after a long wait.
- [ ] Task 2 (spare gear): a new character (new name) has the cap, chain shirt, iron shield and bronze axe on the hotbar (keys 3 to 6); try each on and see the equip load change; a loaded old character has no spares and a saved one does not get them again.
- [ ] A gear swap (keys 3 to 6) in the middle of a roll does not change that roll; the next roll uses the new class.
- [ ] Walk and jog clips match the slower speed (no foot sliding) in Medium, Heavy and Overloaded.
- [ ] Task 3 (weapon bar and panel): the weapon bar left of the hotbar shows the sword and shield (set 1) and the crossbow with its bolt count (set 2, key 2); the active set is lit and follows keys 1, 2 and the wheel; the bar does not crowd the hotbar, the bars or the prompt at 1280 by 720 and 1920 by 1080. The inventory shows "Equip load x / 25" with the class (Light, Medium, Heavy, Overloaded) in its color; the bag does not change it.

## M43 Minimap, compass and map

- [ ] The compass shows N, E, S, W and ticks; turning the camera slides it; at the start you face north (the N in the middle) and the arrival marker is a few meters off (you start on the ring around it; beside or behind you, an arrow at the edge when outside the window), the boss site marker 450 to 800 m away.
- [ ] The minimap shows the ring of stones, the dummies and any awake enemy as dots around you, north up, only your arrow turns; it is hidden while M is held and comes back on release.
- [ ] Hold M and walk with WASD, Shift, Space and the roll key: you move, the camera does not turn, attack and block do nothing; releasing M gives the mouse back.
- [ ] The map keeps north up when you turn; the same hill is in the same place whichever way you face.
- [ ] Settings has a "Minimap" check box; off hides the minimap, the compass stays; it is remembered after a restart.
- [ ] At 1280 by 720 the compass, the minimap and the room code label do not overlap each other, the goal text or the boss bar.
