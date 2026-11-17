# M62 Anomalies and harder nights

Status: Planned.

## Goal

The world turns against the player at times. At night the dead are stronger and other things walk. And now and then a gravity anomaly opens somewhere: a zone where weight shifts, strange enemies gather, and rare loot waits for those who go in before it closes.

## Depends on

M41 (time of day from world time). M61 (elites to fill them), M48 (the loot).

## Design

- Night in the sim: `Daylight.at(world_seconds)` (pure, from M41) now feeds rules: at night `Spawner` wakes camps with a higher share of elites and night-only kinds, roamers increase, enemies see less far but hit harder. Shrines and lit torches are the safe places.
- Anomalies: a pure function of (realm, seed, world time) opens one zone at a time per realm for some minutes, announced by a sound, a column of light and a map mark. Inside, gravity differs (low, high, or pulsing: a `GravityZone` added and removed on every peer at the same world time), enemies are a special table, and a core object at the center gives the reward when the wave around it is beaten.
- This is the game's own version of a danger zone: it uses the gravity system the game is built on.
- All timing is world time, so every peer agrees without extra sync; the zone itself must enter and leave `Gravity` deterministically.

## Tasks

1. **Night rules (Opus).** `sim/spawner.gd`, `sim/enemy_def.gd` (night values), tests with a pinned world time; load test at night.
2. **Anomalies (Opus).** New `sim/anomaly.gd`, `sim/layout.gd` and `sim/gravity.gd` (a zone by world time), spawns, the core object, rewards; tests that two peers agree.
3. **Views, bots, close (Sonnet).** The column, sky and sound cues, map mark, night look checks; suite at night; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Weather that changes the sim. Seasons. Anomalies that change terrain.

## Pitfalls

- Gravity is read inside rollback: a zone that appears mid-resimulation must depend only on the tick's world time, never on arrival of an RPC.
- Too-dark nights were M41's risk; harder nights add to it. Keep the ambient floor.
- World time only advances while the server runs: an anomaly must not be missed forever by short sessions; schedule by play time.
