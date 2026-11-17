# M60 Barrow crypts

Status: Planned.

## Goal

Some burial mounds have a door. Behind it lies a small generated crypt: a few dark rooms and corridors, the dead waiting, traps, and at the end a chest, a shrine upgrade or a mini-boss.

## Depends on

M38 (generated props and built stone), M48 (loot worth the trip), M49 (shrine upgrades as rewards). Each realm milestone can add its own kind of dungeon the same way.

## Design

- A crypt is a pure function of (realm, seed, mound): rooms and corridors on a grid, built from a handful of piece shapes, with collision from boxes on every peer, like the arrival's solids. It sits in its own pocket of space far below the realm's surface inside the same gravity zone, so the terrain above needs no holes; the mound's door is a small gate (`Portal`) down and back.
- About ten per realm, of three sizes. Enemies inside come from the same pool (the spawner treats a crypt as a camp that wakes when a player enters); a large crypt ends with a mini-boss kind.
- Traps as server objects: pressure plates with darts, a falling gate, a floor of spikes on a timer.
- Light: none but torches the players carry or light; this is where the flat look and darkness earn their keep.
- Cleared crypts are saved in the world file; their chest stays empty, enemies do not return.

## Tasks

1. **Layout and collision (Opus).** New `sim/crypt.gd` (pure, tested for determinism and connectivity), chunks or a static body per crypt, gates, `Layout`; tests.
2. **Spawns, traps, rewards (Opus).** `sim/spawner.gd`, trap objects, loot, saves; load test with a party inside.
3. **Look, bots, close (Sonnet).** Piece generators, torches, sounds, the map marks; a bot scenario through a crypt; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Large multi-level dungeons. Puzzles. Digging into mounds.

## Pitfalls

- Players in a crypt and on the surface are far apart: both are terrain and enemy anchors; check the pool is not starved.
- Camera in narrow corridors: the rig needs collision pull-in that works at 2 m width.
- Bolts and aim rays use world layer 1: crypt boxes must be on it.
