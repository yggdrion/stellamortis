# M38 Generated props and sites

Status: Planned.

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
3. **Remove the kits, close (Sonnet).** Delete `assets/quaternius/props/`, `assets/quaternius/village/`, the remaining `assets/ambientcg/` sets and their `docs/RESOURCES.md` rows (the shield and the berserker's axes stay until M39 if they are still used: then say so in the row). Play-test items, milestone closed.

File level detail is added when M37 lands.

## Out of scope

Building pieces for players (M64 builds them with the kit). Weapons and worn gear (M39). Crafting stations beyond the anvil and cauldron already placed (M55).

## Pitfalls

- `Arena` builds collision on the server and looks on clients in the same file: keep generator calls behind the client check, or a headless server builds meshes.
- The torch flame and the gate glow are meaning colors: emission only through the palette's `ember` and `gate` roles.
- A chest's lid and a banner's sway are animated by views today; keep the part split and the pivot where the view expects them.
