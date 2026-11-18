# M22 Barrowlands bestiary and boss

Status: Built (2026-11-16, v0.23.0), play-test pending (`docs/PLAYTEST.md`).

## Goal

The Barrowlands gets its own cast and its boss fight on the realm itself. Five enemy kinds that ask for different answers, and the Warden rising from a barrow; its death opens the gate to the next realm at the arrival gate (M34). The hand-built PoC realm is removed.

## Depends on

M34 (start at the arrival gate, no keep) and M33 (map, for checking spawns). M21 (pool, `EnemyDef`, spawner; built, `World.POOL` is 20 after the load test, 16 slots for the spawner). M19 helps (flinch, deaths) but is not required.

## Design

Kinds (all on the humanoid UAL rig, looks from `Gear`):

| Kind | Role | Answer |
|---|---|---|
| Draugr swordsman | today's melee dead | basics |
| Draugr archer | today's ranged dead | close in, roll through bolts |
| Shield bearer | blocks everything from the front, slow heavy bash | parry the bash, or flank |
| Berserker | fast, low health, a leaping heavy from 8 m | roll the leap, punish the long recovery |
| Barrow elite | large, armored, two-hit combo and a ground slam; guards a camp's chest | all of it |

Boss site: each realm has one, placed from the seed (`BossSite`: a ring of standing stones on flattened ground far from the arrival point). Entering the ring starts the fight; the site's slots are reserved in the pool for its length (the old encounter holds `Pool0..3` and `Spawner.FIRST_SLOT` is 4; when `Encounter` moves to the site, lower `FIRST_SLOT` and reserve the boss slot there, keeping the pool at 20: a larger pool does not hold 29 tps, `docs/PLAN.md` §8). `Encounter` becomes this per realm: phases `IDLE`, `BOSS`, `CLEARED`; it resets when no living player is within the site's reach. `World.flags()` (names such as `warden_fallen`, read from the rolled back phase of the realms' encounters, `RealmDef.boss_flag`) records the kill; a gate with `Portal.needs_flag` is open while the flag is set (the gate to Myrkfen itself comes with M60; none stands at the arrival now).

## Tasks

### 1. Behaviors (Opus)

Files: `game/scripts/sim/enemy.gd`, `sim/enemy_def.gd`, `sim/sim_player.gd`, `sim/combat.gd`, `game/tests/combat_test.gd`, new `tests/bestiary_test.gd`.

Steps:

1. Frontal block: a new `EnemyDef.guard_arc` (the fields of `EnemyDef` are in `sim/enemy_def.gd`); `Enemy.take_hit` from inside that arc deals a fraction and plays a guard reaction, unless the enemy is staggered or in recovery. Player bolts too.
2. Leap: an attack with `AttackDef.leap` (distance) moves the enemy on a fixed arc during windup and lands the hit area at the end; it commits to the target point chosen at the start.
3. Two-hit combo for enemies through `AttackDef.next` (players use it already).

Tests: a front hit on a shield bearer is reduced, a flank hit is not, a parry opens it; a berserker's leap misses a player who rolled and hits one who stood; combo chains.

### 2. The kinds (Sonnet)

Files: `game/data/enemies/*.tres`, `game/data/attacks/*.tres`, `client/gear.gd`, `client/enemy_view.gd`, `client/sounds.gd`, `sim/spawner.gd` (camp recipes).

Reuse: `Gear.dead`, `helm`, `pauldrons`, `sword`, `shield`, `crossbow`, `eyes`; the clip tables at the top of `enemy_view.gd` (`HUMAN_CLIPS`, `UNDEAD_CLIPS`, `ARCHER_CLIPS`, `WARDEN_CLIPS`); `AttackDef.animation`.

Steps: one `.tres` per kind and attack, the kind added to `Combat.ENEMY_KINDS` (after `warden`; the index is rolled back state, a new kind is a protocol bump) and its look and clip table picked in `EnemyView._rebuild`; looks built in `Gear` (shield bearer: helm and tower shield; berserker: bare, two axes, war paint; elite: iron, larger scale); camp recipes that mix kinds (`Spawner._point` picks swordsman or archer by `ARCHER_SHARE` today; a camp wakes whole, so a recipe of 6 needs 6 free slots) (archers behind bearers); telegraph sounds per kind. Screenshots of each kind in idle, windup and strike.

### 3. Boss site and world flags (Opus)

Files: `sim/encounter.gd`, new `sim/boss_site.gd`, `sim/world.gd`, `sim/layout.gd`, `sim/portal.gd`, `sim/spawner.gd`, `sim/terrain.gd` (flatten around the site), `net/wire.gd`, `net/net.gd`, `client/hud.gd`, `client/presence.gd`, `tests/encounter_test.gd`.

Steps:

1. `BossSite.at(realm, world_seed)` (built: the flattest of 24 candidates 450 to 800 m from the arrival, cached under a mutex because every `Terrain.Field` asks for it); `Terrain.Field.height` blends to a flat disc around it (`FLAT` 24 m, `BLEND` 26 m; the height function stays pure). `Scatter.points` leaves the disc empty and adds the ring of `STANDING_STONE` points (solid through the M35 path); `Spawner._fits` keeps camps off it.
2. `Encounter` per realm as in the design (`World.encounters`, `Encounter.of`); the Warden uses the reserved pool slot `Pool0` (`Spawner.FIRST_SLOT` 1) with `EnemyDef` behavior `BOSS_WARDEN`; health scales with the living players inside the ring when it rises; it resets when no living player is within `BossSite.REACH` 80 m; `CLEARED` is permanent while the server runs.
3. World flags: no state of their own. `World.flags()` and `Encounter.flag_set(node, name)` read the encounters' rolled back phase, so a late joiner has them with the state netfox sends (a separate synced set would need its own node and join snapshot for nothing); gates read them through `Portal.needs_flag`/`is_open`, replacing `Encounter.won()`. Saves (M23) persist them.
4. Removed (done): the hand-built realm (`Layout.MOBS`, `BOSS`, `REALM_ARRIVAL`, the gravity boxes, the asteroid and pads, `Arena._build_realm`, `ORIGIN_PLACE` which is now `NO_PLACE`, the arrival's "To the old barrow" gate, the old realm's Home gates). `tests/asteroid_test.gd` walks a small test sphere built in the test (zones and pads appended to `Layout`; `JumpPad` and `Layout.pad_at` stay for M62); the combat, ranged, bestiary and movement tests stand on `tests/support/flat_ground.gd`. `--encounter=boss` spawns the players inside the ring.
5. HUD boss bar and presence strings read the per realm encounter (`Encounter.of`); the map marks the site; `Net.PROTOCOL_VERSION` 28.

Tests: entering the ring raises the Warden; leaving resets it; the kill sets the flag and opens the gate; a wipe resets; health per player; the fight works on the curved ground (slam area, volley, well).

### 4. Site look and the next brief (Sonnet)

Files: `sim/arena.gd` or a new `client/site_view.gd`, `docs/milestones/M23-inventory-loot-saves.md`.

Steps: standing stones, torches, a barrow door, embers when the Warden rises; then detail M23's brief to file level against the code as it is now, and close the milestone (`CLAUDE.md`, the status in `docs/PLAN.md` §6 and in this file, `VERSION`).

## Out of scope

Loot from the elite's chest (M23 fills it). Beasts. A second boss.

## Pitfalls

- The Warden's gravity well reads `Gravity.pull`, apart from `Gravity.sample`; on a realm the well must pull along the ground, not through it.
- `Enemy.take_hit` grows parameters across M19 and M22; keep one signature.
- Removing the old realm touches screenshots and flags documented in `CLAUDE.md` ("Boot", `--spawn` examples): update them.
- The slam and sweep telegraph meshes are built in the enemy's local space (`EnemyView._arc_meshes`); on slopes they clip into the ground. Raise or project them.
