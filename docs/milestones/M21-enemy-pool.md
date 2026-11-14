# M21 Enemy pool

Status: planned.

## Goal

The Barrowlands is inhabited: camps and roamers everywhere, generated from the seed. Enemies stay rolled back, so rolls, blocks and parries are as exact as today; a fixed pool of 24 slots serves whatever is near the players.

## Depends on

M20 (realm, terrain, `Layout.realm_at`). M19 task 1 if merged (its `FLINCH` and `poise` move into `EnemyDef`).

## Design

- All enemy nodes exist on every peer from the start, at fixed paths, as today (`World._add_enemy`, `world.gd:76`). Indices: the keep's dummies 0–1, pool slots 2–25. The old encounter's mobs and Warden (2–5 today) become pool slots in this milestone; M22 moves the boss fight.
- A slot is an `Enemy` with a rolled back `kind` (index into `EnemyDef` list; 0 is "free"). Waking a slot sets `kind`, `home`, health and `Action.RISE` or `IDLE`; freeing sets `Action.HIDDEN`. Both happen on the server inside the rollback tick and reach clients as state.
- `EnemyDef` (resource, `game/data/enemies/*.tres`): health, speed, turn rate, radius and height, poise, notice and leash ranges, behavior (`MELEE`, `RANGED`, `BOSS_WARDEN`), attack ids, bolt slots, look id.
- `Spawner` (server side decision, rolled back result): spawn points are a pure function of seed and realm (`Spawner.points(realm) -> Array[SpawnPoint]`: position direction, kind, camp id). Each tick slice it wakes points within `WAKE` (about 90 m) of a player while free slots exist, nearest first, and frees slots further than `SLEEP` (about 140 m) from every player and not in a fight. A camp whose enemies all died is cleared and stays cleared for `RESPAWN` minutes (server memory in M21, saved in M23).

## Tasks

### 1. Enemies follow gravity (Opus)

Files: `game/scripts/sim/enemy.gd`, `sim/mob.gd`, `sim/warden.gd`, `sim/world.gd`, `client/enemy_view.gd`, `game/tests/encounter_test.gd`, new test in `tests/realm_walk_test.gd`.

Reuse: `SimPlayer.up_turn` (the rotation behind `_turn_frame`), `SimPlayer.frame`, `SimPlayer._tangent`, `Gravity.up_at`, `Combat.in_arc` (already up aware).

Steps: give `Enemy` an `up` that follows `-Gravity.sample` like the player's (move the shared frame math to a static helper instead of copying it); `up` is a variable (`Enemy.up()` is gone, as `SimPlayer.up`); `_walk`, `_orient`, `_turn_toward` use it; `home` is built from the ground normal (`World._add_enemy` uses `Gravity.up_at`); `up` joins `Enemy.STATE` with a wire serializer.

Tests: a mob placed on the realm chases a player 60 m over a hill and stays on the ground; a ranged mob's bolts still hit; the old encounter tests pass unchanged.

### 2. Enemy kinds as data (Opus)

Files: new `sim/enemy_def.gd`, `game/data/enemies/*.tres`, `sim/enemy.gd`, `sim/mob.gd`, `sim/warden.gd`, `sim/training_dummy.gd`, `net/wire.gd`, `client/enemy_view.gd`, `client/gear.gd`, `tests/wire_test.gd`, `tests/combat_test.gd`.

Steps:

1. `EnemyDef` and `Combat.enemy_def(kind)` (loaded like `Combat.attack`). Move the constants out of `Mob` (`NOTICE`, `LEASH`, `KEEP_NEAR`, `KEEP_FAR`, health, speed) and `Warden` (`BASE_HEALTH` and so on) into `.tres` files.
2. One `Enemy` class runs every kind: its `_rollback_tick` dispatches on `def.behavior` to the existing mob and Warden logic (keep those as script-level functions or small behavior objects; do not create one node class per kind, a slot must be able to change kind). The Warden's extra state (`max_health`, `well_time`, `combo`) becomes part of every slot's state; check the 508 byte limit.
3. `kind` in `Enemy.STATE` and the packed group; `EnemyView` rebuilds its model when `kind` changes (`_make_model`, `enemy_view.gd:95`, picks look and clip table from the def instead of `is Warden`).

Tests: wire test covers the new fields and the size; a slot switched from swordsman to archer behaves as an archer; existing encounter tests pass with defs.

### 3. The pool (Opus)

Files: `sim/world.gd`, `sim/sim_player.gd`, `net/wire.gd`, `net/net.gd`, `tests/wire_test.gd`, `tests/combat_test.gd`.

Steps: `World.POOL := 24`; create the slots hidden; `swing_hits` becomes 32 bit (`wire.gd:94` is `u16`; indices above 15 are silently lost today); every loop over `Enemy.GROUP` in a player's tick (`_defend`, `_catch_bolts`, `_strike`, `Combat.enemy_on_segment`) skips hidden slots first. Protocol bump.

Tests: a hit on slot index 20 registers once per swing; wire round trip of a 32 bit mask.

### 4. Spawner (Opus)

Files: new `sim/spawner.gd`, `sim/world.gd`, `sim/terrain_chunks.gd` (enemy anchors), new `tests/spawner_test.gd`.

Steps: `Spawner.points(realm)` from the seed (camps of 3 to 6 around a center on walkable ground, roamers alone; density tuned so a player meets something every minute or two); wake and free as in the design; awake enemies are terrain anchors; cleared camps. The spawner node is server only; clients learn everything from slot state.

Tests: same seed gives the same points; walking toward a camp wakes it, walking away frees it; a full pool wakes nothing more and never frees a fighting enemy; a cleared camp stays empty; late joiner sees awake enemies (state only).

### 5. Measure (Sonnet)

Run `python tools/run_load_test.py --players=6` and `--lag=100` with bots standing in a camp so the pool is full (add a bot spawn flag if needed), and `--bench`. Write tps, tick loop and kB/s to `docs/PLAN.md` §8. If 29 tps does not hold, lower `World.POOL` until it does and record the number; do not optimise netfox here.

## Out of scope

New enemy kinds and the boss site (M22). Saving cleared camps (M23). Loot.

## Pitfalls

- Waking a slot is a state change inside rollback, not a spawn. Never `add_child` or `queue_free` an enemy after `World.build`.
- netfox's cost grows with synced properties and nodes: keep new enemy fields inside the packed groups.
- Hidden slots must cost almost nothing per tick: return first thing in `_rollback_tick`, and keep their body disabled (`Enemy._sync_body`).
- `Encounter` holds `mobs` and `boss` node references (`encounter.gd:17`); keep it working on pool slots until M22 replaces it.
- `EnemyView` creation happens once per node today; rebuilding the model on `kind` change must not leak the old one or its sounds.
