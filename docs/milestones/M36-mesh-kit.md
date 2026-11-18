# M36 Mesh kit and palette

Status: built (2026-11-17, v0.25.0), play-test pending (`docs/PLAYTEST.md`).

## Goal

The tools every later art milestone builds with: a mesh kit that makes flat-shaded, vertex-colored models from code, a palette per realm, one shader, a gallery to look at generated kinds, and tests that hold every generator to `docs/STYLE.md`. The player sees nothing new yet except a gallery; M37 to M40 replace the art.

## Depends on

Nothing. First of the art block (M36 to M45); `docs/STYLE.md` is its specification.

## Design

- `MeshKit` (`game/scripts/client/meshgen/mesh_kit.gd`, static): builds on `SurfaceTool`. Every helper emits unshared vertices (flat normals) with a vertex color and returns arrays, so it can run on a worker thread; `MeshKit.commit(parts) -> ArrayMesh` joins them on the main thread. Helpers: `lathe(profile, sides, wobble)`, `extrude(outline, depth, bevel)`, `box(size, bevel)`, `tube(path, radii, sides)` (trunks, limbs, horns), `blob(radius, detail, noise, flatten)` (displaced icosphere: rocks, leaf clumps), `cone_stack(layers)` (conifers), `blade(points, width)` (grass, fronds, sword blades), `chip(arrays, planes)` (cut corners off), `decimate_to(arrays, triangles)` is **not** built: each generator makes its three levels of detail by calling the helpers with fewer sides and parts.
- Color: `MeshKit.paint(arrays, color, rng)` applies the style sheet's variation (per instance, per face, darkening toward a given `down`), so no generator does color math itself.
- `Palette` (`game/scripts/client/palette.gd`, a `Resource`; `game/data/palettes/barrowlands.tres`): one `Color` and one roughness per role (`docs/STYLE.md` §3). `Palette.of(realm_id)` loads and caches; `palette.color(role)` asserts the role exists. The sim never loads a palette.
- `shaders/flat.gdshader`: vertex color as albedo, roughness from the color's alpha, optional emission for the meaning roles, the wind hook left as uniforms at zero (M45); burn away is `shaders/flat_burn.gdshader`, `MeshKit.burn_material()` (split off in task 3: the discard cost GPU time on every model). One shared `ShaderMaterial` (`MeshKit.material()`).
- `Budgets` (`game/scripts/client/meshgen/budgets.gd`, `game/data/style/budgets.tres`): the table of `docs/STYLE.md` §5 as data, and the level of detail distances.
- `Generators` (`game/scripts/client/meshgen/generators.gd`): the registry. `Generators.register(id, budget_kind, callable)`; `Generators.build(id, variant_seed, palette) -> Array[ArrayMesh]` (full, half, far); `Generators.ids()`. A generator is a static function `(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array` (mesh arrays).
- Gallery: `--gallery[=ID]` in `scripts/boot/main.gd` (added to `DIRECT`; no server, no world). `game/scripts/client/gallery.gd` stands every registered kind (or the one named) on a flat ground in rows: variants left to right, levels of detail front to back, a 1.8 m figure for scale, dusk light from `Arena`'s environment. Works with `--screenshot`, `--look`, `--graphics`.
- Two sample generators prove the kit: `rock` (blob, chipped) and `pine_young` (tube trunk, cone stack). M37 replaces or extends them.

## Tasks

### 1. Kit, palette, shader (Opus)

Files: new `scripts/client/meshgen/mesh_kit.gd`, `scripts/client/palette.gd`, `data/palettes/barrowlands.tres`, `shaders/flat.gdshader`, `scripts/client/meshgen/budgets.gd`, `data/style/budgets.tres`, new `tests/meshgen_test.gd`.

Reuse: how `client/terrain_view.gd` builds arrays on workers and commits them on the main thread (`_array_mesh`, `Job`); `client/gear.gd` for the shapes the Warden's armor already needs (its helpers move into `MeshKit` in M39, not here).

Steps: the helpers; `paint`; `Palette` with the Barrowlands colors taken from today's recolors (`TerrainView.LOOKS`, `Gear`) and muted to the style sheet's limits; the shader; the budget table. Check each engine call against the 4.7 docs (`SurfaceTool`, `ArrayMesh.add_surface_from_arrays`, vertex color with alpha in Forward+).

Tests: each helper's triangle count is what its parameters say; two builds with the same seed give byte-identical arrays, a different seed does not; no two vertices share a normal that differs from the face normal (flat); `paint` stays inside the variation ranges.

Done when: the tests pass headless (arrays only, no mesh commit) and a scene with one `blob` and one `tube` renders flat and colored.

### 2. Registry, gallery, sample generators (Sonnet)

Files: new `scripts/client/meshgen/generators.gd`, `scripts/client/gallery.gd`, `scripts/client/meshgen/kinds/rock.gd`, `kinds/pine_young.gd`; `scripts/boot/main.gd` (`DIRECT`, `--gallery`); `tests/meshgen_test.gd`; `README.md` (the flag); `docs/PLAYTEST.md`.

Steps: the registry; the gallery scene; the two generators with three levels of detail each. The registry tests run over `Generators.ids()`, so every later generator is tested without a new test: budget per level, determinism, only palette colors (every vertex color is within the variation range of one role), far level keeps the bounding box within 10 % of full.

Done when: `python tools/godot.py -- --gallery --screenshot=PATH` shows both kinds with variants and levels; screenshots are in the commit message's notes.

### 3. Cost, and close the milestone (Opus)

Files: `scripts/client/gallery.gd` (a `--gallery-stress=N` mode: N instances per kind through `MultiMesh`), `docs/PLAN.md` §3.1 and §8, `docs/STYLE.md` (tuned numbers), `CLAUDE.md`, `VERSION`.

Steps: measure on the presets what the budgets cost: build time per kind on a worker (the join must not stall: under 2 ms per variant on the main thread for the commit), draw cost of 5000 trees and 20000 grass tufts at the three levels. Adjust `budgets.tres` and the style sheet together. Detail M37's brief to the measured numbers. Close the milestone (README "Done means").

Done when: the numbers are in `docs/PLAN.md` §8 and the Low preset keeps its frame rate in the stress scene.

## Out of scope

Replacing any existing art (M37 on). Terrain. Skinned meshes (M40). Level of detail switching in the world (M37 decides how: visibility ranges per `MultiMeshInstance3D`).

## Pitfalls

- Mesh building is client only. `tests/meshgen_test.gd` runs headless, so it checks arrays, never rendered meshes.
- `SurfaceTool.generate_normals()` smooths shared vertices: the kit must emit three own vertices per triangle.
- Vertex color alpha as roughness needs the shader to ignore it for transparency; check the render mode.
- A `Resource` named `Palette` or an enum named after a native class would shadow it: check with a headless `extends SceneTree` script before naming.
- Workers on Windows: keep files UTF-8 and LF.
