# M28 Skyshards

## Goal

The fourth realm, behind the forge king's gate: a broken land hanging in the night sky. Many small rocks, each with its own pull, joined by launch stones. This is the one place that is meant to feel small and strange underfoot; it brings back the PoC's asteroid and jump pads as a whole realm.

## Depends on

M27. File level detail is added by M27's last task.

## Design

- Not a `Terrain` sphere: a seeded cluster of 15 to 25 shards (radius 15 to 60 m, point gravity each, as the PoC's asteroid: `GravityZone.sphere`, `Layout.pad_at`, `JumpPad`), spread over a few hundred metres. `ShardField.shards(seed)` and `ShardField.pads(seed)` are pure functions; pads come in pairs that are tested to land (a simulated launch per pair at generation, as `tests/asteroid_test.gd` does by hand).
- Shards are small enough to build whole at load: displaced spheres with collision, no streaming.
- Biome: pale rock, frost, old runestones, the launch stones as carved rings that glow blue (the gate color: travel).
- Enemies: sentries (ranged, hold a shard and shoot across the gap: bolts bend through two gravity fields), frost draugr (melee, pull players off balance at the edge), and flyers if a CC0 model fits (a flyer needs movement outside `_walk`: decide in the brief detail whether it is worth it).
- Resources: sky iron; tier 4 recipes and sets.
- Boss: fought across three shards. It leaps between them, and the players follow by pad; one shard breaks away in phase 2.

## Tasks

1. **Shard field generator (Opus).** Shards, gravity zones, pads with landing proof, collision, arrival, spawn points on shards. Tests: every pad pair lands; walking around every shard works; same seed, same field.
2. **Look (Sonnet).** Shard meshes and materials, launch stones, sky.
3. **Enemies (Opus for behaviors, Sonnet for defs and looks).**
4. **Resources and tier 4 (Sonnet).**
5. **The boss (Opus).** Then detail M29's brief and close the milestone.

## Out of scope

Free flight for players. Moving shards outside the boss fight.

## Pitfalls

- Enemies must stay on their shard: leash to the shard, never path across gaps.
- A player falling between shards needs a rule: the nearest shard's gravity reaches far enough that they always land somewhere; a kill depth below the field respawns them.
- Overlapping gravity spheres use zone priority (`Gravity.sample` takes the highest priority zone): give nearer or smaller shards a clear order so the pull never flips each tick at a border.
