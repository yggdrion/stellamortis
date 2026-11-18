# M35 Scatter collision

Status: Built (2026-11-15, v0.22.0), play-test pending (`docs/PLAYTEST.md`).

## Goal

Trees, boulders, standing stones and burial mounds are solid: players, enemies and bolts stop at them instead of passing through (noticed by the user, 2026-11-15). The arrival's stone ring and gate arch are solid too.

## Depends on

M20 (`Scatter.points`, `TerrainChunks`), M34 (the arrival look). Comes before M22. M58 builds felling and mining on top of this collision instead of adding its own.

## Design

- Collision comes only from `Scatter.points(realm, world_seed, chunk)`, a pure function of the seed: never from the client's meshes. Every peer builds the same shapes.
- Simple shapes per `Scatter.Kind`, sized from the point's scale: a capsule or cylinder for a trunk (only the trunk, not the crown), a sphere or box for a boulder, a box for a standing stone, a low cylinder or sphere cap for a mound. The numbers live in data (one table per kind), not in code.
- Built with the terrain chunk: the same job that builds a chunk's faces also lists its scatter shapes (on the worker), and `TerrainChunks._add_body` adds them to that chunk's `StaticBody3D` on the main thread. Freeing the chunk frees them. World layer 1, so players, enemies and `Combat.ray` (bolts, aim) see them with no other change.
- Clients build them around their own player as they do terrain collision; the server around every anchor (players, awake enemies).
- The arrival's stones and the gate arch (`Arena._arrival_look`, the portal arch) get static boxes from the same `Layout.arrival_spot` positions, on every peer.

## Tasks

### 1. Shapes in the chunks (Opus)

Files: `sim/scatter.gd`, `sim/terrain_chunks.gd`, new `data/scatter_shapes.tres` (or constants in a resource class), `sim/arena.gd` or `sim/world.gd` (arrival stones and arch), `client/terrain_view.gd` (check the visual sizes match), new `tests/scatter_collision_test.gd`.

Steps: the shape table per kind; shapes listed in the chunk job and added in `_add_body`; the arrival stones and arch. Line up each shape with its mesh in a screenshot (`--seed=1234`, a debug flag that draws collision shapes is fine).

Tests: two builds of the same chunk give identical shapes; a player walking into a tree stops; a bolt shot at a trunk ends there; a player cannot walk through the stone ring; nothing stands on the spawn ring or the dummy posts (the scatter clearing still holds).

### 2. Enemies and the load test (Opus)

Files: `sim/enemy.gd` (`_walk`), `sim/mob.gd`, `sim/spawner.gd`, `docs/PLAN.md` §8, `docs/PLAYTEST.md`.

Steps: enemies walk straight at their target today; with trees they must slide around a trunk instead of sticking (move_and_slide does most of it; add a small sidestep when blocked for a few ticks, deterministic, no navigation mesh). Spawner points must not sit inside a shape (check `Spawner.points` against the scatter clearing per camp, or clear scatter around camps). Run `python tools/run_load_test.py` with bots in camps (`--seed=1234 --spawn=...`) and record tps and tick loop: more static shapes add Jolt broadphase cost, and every resimulated tick moves bodies through them. Play-test checks in `docs/PLAYTEST.md`; close the milestone.

Tests: a mob chasing a player around a tree reaches them within a few seconds; no woken enemy starts inside a shape.

## Out of scope

Felling, mining and resource nodes (M58). Navigation meshes. Collision for grass and small props.

## Pitfalls

- A client predicting its player against a shape the server does not have (or the other way) rubberbands every step: only `Scatter.points` decides, and the client's visual scatter radius (`Graphics` preset) must not limit the collision radius.
- Changing `Scatter.points` now changes gameplay: tests that fingerprint scatter catch it, and M58 versions it for saves.
- Shape counts: a dense chunk may hold hundreds of trees. Keep one body per chunk with many shapes, not one body per tree.
