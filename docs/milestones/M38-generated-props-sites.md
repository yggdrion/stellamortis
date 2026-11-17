# M38 Generated props and sites

Status: Built (2026-11-17, v0.28.0), play-test pending.

## Goal

Everything built by hands in the world comes from generators in the game's own look: torches, chests, barrels, crates, graves, banners, the arrival's stone ring and gate arches, the boss site. The Quaternius MegaKit props and village pieces and the last ambientCG textures are gone.

## Depends on

M36 (kit, registry). `docs/STYLE.md`. Independent of M39; after M37 only because M37 removes the ground textures `Arena._surface` shares.

## Design

- One generator per prop in `scripts/client/meshgen/kinds/`, registered with budget kind "prop, small" or "prop, large": `torch` (post, iron basket, a flame mesh on the emission role), `chest` (lid as its own part so it can open), `barrel`, `crate`, `anvil`, `cauldron`, `weapon_stand`, `banner` (cloth as a bent sheet, heraldry by two palette roles), `grave_slab`, `grave_marker` (the player's grave), `gate_arch` (the portal frame; the portal surface stays its shader), `ring_stone` (the arrival's stones), `brazier`.
- Worked surfaces replace `Arena._surface`'s tiling materials: stone walls and paving are built from `MeshKit.box` courses with bevels and color variation per block, not from a texture. `Arena._prop()` becomes a lookup into `Generators`.
- World objects (`client/objects_view.gd`: drops, chests, graves) take their meshes from the same generators.
- Collision is untouched: `Arena.add_arrival_solids` and the boss site's `STANDING_STONE` points decide what is solid; the meshes must fit them (the registry's shape test covers the scatter kinds; the arrival boxes get their own check).
- Variants per world seed where it adds life (stones, graves, banners), fixed shapes where players learn them (chests, torches).

## Tasks

1. **Props (Sonnet).** The generators above with three levels of detail; gallery screenshots. Files: `scripts/client/meshgen/kinds/*.gd`, `data/palettes/barrowlands.tres`.
2. **Arrival, gates and boss site (Sonnet).** `scripts/sim/arena.gd` (`_arrival_look`, `add_site_looks`, `add_seeded_portals`, `_surface`, `_prop`), `scripts/client/objects_view.gd`. Screenshots: `--seed=1234` (arrival), `--seed=1234 --encounter=boss`, `--show-collision` on both.
3. **Remove the kits, close (Sonnet).** Delete `assets/quaternius/props/`, `assets/quaternius/village/`, the remaining `assets/ambientcg/` set (Ground020) and `assets/kenney/nature/` (`stone_tallA`, the last Kenney file) and their `docs/RESOURCES.md` rows (the shield and the berserker's axes stay until M39 if they are still used: then say so in the row). Play-test items, milestone closed.

### File level detail (added when M37 landed, from the code as it is)

How a kind is built (read `kinds/log.gd`, `kinds/standing_stone.gd` and `meshgen/generators.gd` first): a class `<Name>Kind` in `scripts/client/meshgen/kinds/<name>.gd` with a `NOMINAL` size (meters, width, height, depth) and `static func build(rng, palette, lod[, id]) -> Array` (mesh arrays from `MeshKit` helpers, colors only from `palette.color(role)` through `MeshKit.paint`, the same random draws at every level, sizes from `NOMINAL`). Register it in `Generators._builtins` (`register(id, budget_kind, Kind.build)`, `.bind(id)` when one file serves several ids). `tests/meshgen_test.gd` loops over every registered id (budget per level, determinism, palette-only colors, far level keeps the size), so a new id is held to the style sheet without a new test; add one `test_prop_sizes` that holds the sized kinds to the numbers below. Nothing here touches the sim: the generators stay in `client/`.

Task 1 ids, files, budget rows (`data/style/budgets.tres`, no new rows) and sizes (the sizes the code uses today; the solid ones must fit their boxes):

| Id | File | Budget row | Nominal (w, h, d) m | Fits / replaces |
|---|---|---|---|---|
| `ring_stone` | `ring_stone.gd` | `prop_large` | 2.0 x 2.4 x 1.4 | `Arena.STONE_SOLID` (1.9, 2.3, 1.3), replaces `kenney/nature/stone_tallA.glb` in `Arena._arrival_look` (10 stones around the arrival, `STONE_SCALE` 2.4 goes) |
| `gate_arch` | `gate_arch.gd` | `prop_large` | 4.2 x 4.65 x 0.8, opening 2.8 wide and 3.9 high | `Arena.GATE_PILLAR` (0.6, 4.0, 0.7) at x +-1.7, `GATE_LINTEL` (4.2, 0.7, 0.8) at y 4.3; replaces the `_block` pillars and lintel in `Arena._portal`; the veil quad (2.8 x 3.9) and its light stay |
| `torch` | `torch.gd` | `prop_small` | 0.3 x 1.1 x 0.5 (plate at the origin, reaches out along +Z, like `Torch_Metal`) | `Arena._torch`; the flame is `torch_flame` (a second small kind, `ember` role, 0.14 x 0.3, drawn with its own copy of `MeshKit.material()` and `glow` set) |
| `chest`, `chest_lid` | `chest.gd` | `prop_small` | 1.0 x 0.55 x 0.65 (body), lid the same width, hinge on its back lower edge at the origin | `ObjectsView.CHEST_MODEL` (`ChestLook`, scale `CHEST_SCALE` 1.25 goes into the nominal) |
| `barrel`, `crate` | `barrel.gd`, `crate.gd` | `prop_small` | 0.7 x 0.9 x 0.7 and 0.8 x 0.8 x 0.8 | the site and arrival dressing of task 2 |
| `anvil`, `cauldron`, `weapon_stand`, `brazier` | one file each | `prop_small` (`brazier` `prop_large`) | 0.5 x 0.8 x 0.9, 1.0 x 0.9 x 1.0, 1.2 x 1.4 x 0.5, 0.9 x 1.1 x 0.9 | M49 and M55 stations later; placed by task 2 where the site needs them |
| `banner` | `banner.gd` | `prop_small` | 0.9 x 2.2 x 0.1 (cloth as a bent sheet, hung from a bar) | heraldry from `cloth` and `cloth_dark` (no new palette roles: saturated roles are `ember`, `gate`, `gold` only) |
| `grave_slab`, `grave_marker` | `grave.gd` | `prop_small` | 1.0 x 0.3 x 2.0 and 0.6 x 1.2 x 0.15 | `Graves` and the world objects of M23 (`ObjectsView`) |

Palette: every role used exists (`wood`, `iron`, `stone`, `stone_dark`, `cloth`, `cloth_dark`, `thatch`, `leather`, `ember`, `gate`, `moss`); `ember` and `gate` only on faces that are meant to glow (`test_every_generator_uses_only_palette_colors` accepts any role, so review these two by eye in the gallery).

Gallery: `python tools/godot.py -- --gallery=torch` (a prefix shows `torch` and `torch_flame`), one id, or `--gallery` for everything; screenshots by `--gallery=<id> --screenshot=<abs path>`.

Tasks 2 and 3 hook in at these places of `scripts/sim/arena.gd` (line numbers of v0.26.0): `_arrival_look` (stones, line 171, `_prop` call with `NATURE + "stone_tallA.glb"`), `_site_look` (line 197: the ring torches by `_torch`, the barrow door `VILLAGE + "DoorFrame_Round_Brick.gltf"` at line 225, the mound dome with `_surface(GROUND, 0.2)` at line 221: that is where the last ambientCG texture is used; `MoundKind` of M37 is the replacement), `_portal` (line 391, `_surface(BRICK, 0.6)` blocks), `_torch` (line 356, `PROPS + "Torch_Metal.gltf"`), `_surface` and `_prop` (lines 158 and 449, both go with the kits), and `client/objects_view.gd` (`CHEST_MODEL`, line 44, `ChestLook`). `Arena._materials` and `_surface`'s `village:` branch go when the last caller does. `Gear.SHIELD` and `Gear.AXE` (`client/gear.gd` lines 10 and 11) still read `assets/quaternius/props/`: M39 replaces them, so task 3 keeps `Shield_Wooden.gltf`, `Axe_Bronze.gltf` and their textures and says so in the row. Generated meshes on the arena are made only when `visual` is true (the server builds none).

## Out of scope

Building pieces for players (M64 builds them with the kit). Weapons and worn gear (M39). Crafting stations beyond the anvil and cauldron already placed (M55).

## Pitfalls

- `Arena` builds collision on the server and looks on clients in the same file: keep generator calls behind the client check, or a headless server builds meshes.
- The torch flame and the gate glow are meaning colors: emission only through the palette's `ember` and `gate` roles.
- A chest's lid and a banner's sway are animated by views today; keep the part split and the pivot where the view expects them.
