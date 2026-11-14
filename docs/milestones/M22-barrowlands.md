# M22 Barrowlands bestiary and boss

## Goal

The Barrowlands gets its own cast and its boss fight on the realm itself. Five enemy kinds that ask for different answers, and the Warden rising from a barrow; its death opens the keep's gate to the next realm. The hand-built PoC realm is removed.

## Depends on

M21 (pool, `EnemyDef`, spawner). M19 helps (flinch, deaths) but is not required.

## Design

Kinds (all on the humanoid UAL rig, looks from `Gear`):

| Kind | Role | Answer |
|---|---|---|
| Draugr swordsman | today's melee dead | basics |
| Draugr archer | today's ranged dead | close in, roll through bolts |
| Shield bearer | blocks everything from the front, slow heavy bash | parry the bash, or flank |
| Berserker | fast, low health, a leaping heavy from 8 m | roll the leap, punish the long recovery |
| Barrow elite | large, armored, two-hit combo and a ground slam; guards a camp's chest | all of it |

Boss site: each realm has one, placed from the seed (`BossSite`: a ring of standing stones on flattened ground far from the arrival point). Entering the ring starts the fight; the site's slots are reserved in the pool for its length. `Encounter` becomes this per realm: phases `IDLE`, `BOSS`, `CLEARED`; it resets when no living player is within the site's reach. `World.flags` (a rolled back or reliably synced set of names, e.g. `warden_fallen`) records the kill; the keep's next gate is open while the flag is set.

## Tasks

### 1. Behaviors (Opus)

Files: `game/scripts/sim/enemy.gd`, `sim/enemy_def.gd`, `sim/sim_player.gd`, `sim/combat.gd`, `game/tests/combat_test.gd`, new `tests/bestiary_test.gd`.

Steps:

1. Frontal block: `EnemyDef.guard_arc`; `Enemy.take_hit` from inside that arc deals a fraction and plays a guard reaction, unless the enemy is staggered or in recovery. Player bolts too.
2. Leap: an attack with `AttackDef.leap` (distance) moves the enemy on a fixed arc during windup and lands the hit area at the end; it commits to the target point chosen at the start.
3. Two-hit combo for enemies through `AttackDef.next` (players use it already).

Tests: a front hit on a shield bearer is reduced, a flank hit is not, a parry opens it; a berserker's leap misses a player who rolled and hits one who stood; combo chains.

### 2. The kinds (Sonnet)

Files: `game/data/enemies/*.tres`, `game/data/attacks/*.tres`, `client/gear.gd`, `client/enemy_view.gd`, `client/sounds.gd`, `sim/spawner.gd` (camp recipes).

Reuse: `Gear.dead`, `helm`, `pauldrons`, `sword`, `shield`, `crossbow`, `eyes`; the clip tables in `enemy_view.gd:14`; `AttackDef.animation`.

Steps: one `.tres` per kind and attack; looks built in `Gear` (shield bearer: helm and tower shield; berserker: bare, two axes, war paint; elite: iron, larger scale); camp recipes that mix kinds (archers behind bearers); telegraph sounds per kind. Screenshots of each kind in idle, windup and strike.

### 3. Boss site and world flags (Opus)

Files: `sim/encounter.gd`, new `sim/boss_site.gd`, `sim/world.gd`, `sim/layout.gd`, `sim/portal.gd`, `sim/spawner.gd`, `sim/terrain.gd` (flatten around the site), `net/wire.gd`, `net/net.gd`, `client/hud.gd`, `client/presence.gd`, `tests/encounter_test.gd`.

Steps:

1. `BossSite.at(realm)` from the seed; `Terrain.height` blends to a flat disc around it (the height function stays pure: the site position is derived from the same seed).
2. `Encounter` per realm as in the design; the Warden uses a reserved pool slot with `EnemyDef` behavior `BOSS_WARDEN`; health scales with the players inside the ring when it rises.
3. `World.flags` with a wire serializer; gates read it (`Layout.portals()`, `Portal`), replacing `Encounter.won()`.
4. Remove the hand-built realm: `Layout.MOBS`, `BOSS`, `REALM_ARRIVAL`, the low and high gravity boxes, the asteroid and pads at the origin, `Arena._build_realm`, and their tests. Keep `tests/asteroid_test.gd`'s coverage by pointing it at a small test sphere built in the test (the Skyshards need that behavior in M28). The keep's gate now leads only to the Barrowlands. `--encounter=boss` starts the fight at the site.
5. HUD boss bar and presence strings read the per realm encounter. Protocol bump.

Tests: entering the ring raises the Warden; leaving resets it; the kill sets the flag and opens the gate; a wipe resets; health per player; the fight works on the curved ground (slam area, volley, well).

### 4. Site look and the next brief (Sonnet)

Files: `sim/arena.gd` or a new `client/site_view.gd`, `docs/milestones/M23-inventory-loot-saves.md`.

Steps: standing stones, torches, a barrow door, embers when the Warden rises; then detail M23's brief to file level against the code as it is now, and close the milestone (`CLAUDE.md`, the row moved to `docs/milestones/DONE.md`, `VERSION`).

## Out of scope

Loot from the elite's chest (M23 fills it). Beasts. A second boss.

## Pitfalls

- The Warden's gravity well reads `Gravity.pull`, apart from `Gravity.sample`; on a realm the well must pull along the ground, not through it.
- `Enemy.take_hit` grows parameters across M19 and M22; keep one signature.
- Removing the old realm touches screenshots and flags documented in `CLAUDE.md` ("Boot", `--spawn` examples): update them.
- The slam and sweep telegraph meshes are built in the enemy's local space (`EnemyView._arc_meshes`); on slopes they clip into the ground. Raise or project them.
