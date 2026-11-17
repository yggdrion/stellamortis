# M37 Generated terrain and scatter

Status: Planned.

## Goal

The Barrowlands looks like one hand made it: flat-shaded ground in palette colors, five tree species from saplings to old giants, rocks from pebbles to outcrops, and ground cover (grass, ferns, heather, bushes, logs) that makes the moor feel grown. The Kenney trees and rocks and the ambientCG ground are gone.

## Depends on

M36 (kit, palette, registry, measured budgets). `docs/STYLE.md`. M35's collision (`ScatterShape`, `Scatter.points`) is extended, not replaced.

## Design

- **Solid kinds** stay a pure function of the seed in `Scatter.points` and keep one `ScatterShape` each. `Scatter.Kind` grows: trees by species and age (`PINE`, `SPRUCE`, `BIRCH`, `OAK`, `DEAD_TREE`, each `_YOUNG`, `_GROWN`, `_OLD`; young trees of thin species may be non-solid, decided by the shape data), `ROCK` (0.5 to 2 m), `BOULDER` (2 to 5 m), `OUTCROP` (5 to 12 m), `STANDING_STONE`, `MOUND`. Age comes from a second low-frequency noise ("old wood" patches hold the giants), species from the forest noise, height and slope as today (`_kind`). Old trees need more room: a candidate is dropped when a bigger solid is within its footprint (deterministic order by rank).
- **Ground cover** is view-only and never in `Scatter.points`: `GroundCover.points(realm, seed, chunk)` (`scripts/client/ground_cover.gd`, pure, worker-safe) gives grass tufts, tall grass, ferns, heather, bushes, pebbles, fallen logs and stumps from the same field (wood noise, slope, height). Dense near the camera only: its own radius and density per `Graphics` preset (`COVER_RADIUS`, `COVER_DENSITY`), far smaller than `SCATTER_RADIUS`.
- **Variants:** per kind, `VARIANTS` (4 for trees and rocks, 3 for cover) meshes are built once per world from `hash(world_seed, kind, variant)` through `Generators.build`, on workers, before or while the first chunks load. Every placed point picks a variant from its rank. One `MultiMeshInstance3D` per (chunk, kind, variant, level of detail).
- **Levels of detail:** each chunk's scatter gets the level its distance from the camera asks for (full, half, far; distances from `Budgets`), swapped when the player moves `REFRESH_DISTANCE`, like chunks today. Far level only beyond the half range; cover has no far level.
- **Terrain:** `shaders/terrain.gdshader` loses the ambientCG samplers. Color per face from palette roles by slope, height and the wood noise (grass, heather, earth, stone), flat normals from the chunk mesh (unshared vertices in `TerrainView._grid_arrays`, or the derivative of world position in the shader: measure both, keep the cheaper). The far shell uses the same colors.
- `TerrainView.LOOKS`, `NATURE`, `_kind_mesh`, `_weather`, `_first_mesh` and the Kenney files go; `_transform` keeps placing points but takes scale from the generator's nominal size.

## Tasks

### 1. Kinds in the sim (Opus)

Files: `scripts/sim/scatter.gd`, `scripts/sim/scatter_shape.gd`, `data/scatter/*.tres` (one per solid kind), `scripts/sim/spawner.gd` (`Solids`), `scripts/sim/boss_site.gd` (the stone ring kind), `scripts/net/net.gd` (`PROTOCOL_VERSION`), `tests/scatter_collision_test.gd`, `tests/boss_site_test.gd`, the scatter fingerprint test, `docs/PLAN.md` §8.

Steps: the new kinds and their choice; shapes per kind (a trunk cylinder sized to the species and age; old trees 0.8 to 1.6 m across; outcrops a box or two); the spacing rule; bump the protocol version (peers on different builds would stand on different ground). Re-run `Spawner.points` under seed 1234 and record the new enemy count; run `python tools/run_load_test.py` with bots in camps, since more and bigger shapes cost broadphase time.

Tests: the fingerprint changes once and is pinned again; two builds agree; no solid inside another's footprint; nothing on the spawn ring, the dummy posts or the boss disc; camps and posts stay off solids.

Done when: checks green, 29 tps held, the client still draws (old meshes mapped to the nearest new kind until task 2 lands).

### 2. Tree generators (Sonnet)

Files: new `scripts/client/meshgen/kinds/pine.gd`, `spruce.gd`, `birch.gd`, `oak.gd`, `dead_tree.gd` (each registers young, grown and old); `data/palettes/barrowlands.tres` (roles if missing).

Steps: by `docs/STYLE.md` §6: trunks of 10 to 12 sides with taper, lean and root flare; pine with a bare lower trunk and layered needle masses high up; spruce full to the ground and narrow; birch pale, slender, with a few leaf clumps; oak wide with heavy limbs and 8 to 12 clumps; dead tree bare limbs only. Old ones are the landmarks: 15 to 25 m. Each fits its `ScatterShape` at the trunk.

Done when: gallery screenshots of all fifteen with variants and levels; registry tests green.

### 3. Rock, stone and cover generators (Sonnet)

Files: new `kinds/rock.gd` (replaces M36's sample; rock, boulder, outcrop), `standing_stone.gd`, `mound.gd`, `grass.gd` (tuft, tall), `fern.gd`, `heather.gd`, `bush.gd`, `log.gd` (log, stump), `pebble.gd`; new `scripts/client/ground_cover.gd`, `tests/ground_cover_test.gd`.

Done when: gallery screenshots; `GroundCover.points` is deterministic and never puts cover inside a solid's footprint or on the spawn ring.

### 4. Terrain and the view (Opus)

Files: `scripts/client/terrain_view.gd`, `shaders/terrain.gdshader`, `scripts/client/graphics.gd` (cover radius and density per preset), `scripts/client/map_panel.gd` and `shaders/map.gdshader` if they read the ground colors, `scripts/sim/arena.gd` only where it names the ground material.

Steps: palette ground; variants built on workers; `MultiMesh` per chunk, kind, variant and level; level swaps; cover around the camera. Remove `assets/kenney/nature/`, `assets/ambientcg/Ground020` and the rock sets no longer used, and their rows in `docs/RESOURCES.md`. Measure the presets on the realm (`--seed=1234 --spawn=2500,1004,1800 --look=180,-6`, and a spot inside old wood) and record frame times in `docs/PLAN.md` §3.1.

Done when: screenshots at the arrival, in old wood, on a steep rocky slope and on open moor, at Low and Ultra; frame rates on Low not below M36's stress numbers; `--show-collision` lines up with trunks and rocks; play-test items in `docs/PLAYTEST.md`; milestone closed.

## Out of scope

Wind sway and water (M42). Felling and mining (M44 uses these kinds). Other realms' palettes and species (their own milestones). The arrival's stones and props (M38).

## Pitfalls

- Changing `Scatter.points` moves gameplay: enemy camps, the boss site ring and saved worlds' cleared camps (`WorldSave`) are keyed on positions from it. Decide in task 1 whether old world files stay valid; if not, say so in the release note and version the save.
- The client's cover and scatter radius must never limit collision: collision comes from `TerrainChunks`, not from what is drawn.
- Old trees near a camp: `Enemy._around` sidesteps trunks up to a width; check the widest trunk does not trap a mob.
- A `MultiMesh` per chunk, kind, variant and level multiplies draw calls: merge kinds with few instances per chunk, and measure.
- Grass is the triangle risk: 12 triangles times tens of thousands. The cover radius is the knob, not the tuft.
