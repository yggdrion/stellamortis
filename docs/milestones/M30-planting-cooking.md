# M30 Planting and cooking

Status: planned.

## Goal

A base feeds its people. Players till fields beside their hall, sow seeds found in the realms, harvest what grows and cook it into meals that raise health and stamina for a while, so a trip into a hard realm starts at the hearth.

## Depends on

M29 (pieces, fields stand inside a base), M25 (gathering, recipes, stations), M24 (`Stats`, which meals feed), M23 (items, food as items, saves). File level detail is added by M29's last task.

## Design

- World time: the world file keeps `world_time` (seconds the server has run in this world). Growth, cooking and everything later (M31, M32) counts in world time, never wall clock: a world left alone does not grow, and nothing jumps when the host's clock changes.
- Seeds: found as loot and by gathering wild plants (M25's resource nodes get wild barley, flax and turnips in the Barrowlands). Each realm adds crops of its own that only grow on that realm's soil: Myrkfen bog onions and cloudberries, Jarnfell ash root, the Skyshards' sky thistle. A crop is `CropDef` (resource: seed item, realm, grow time, stages with a model each, yield range, harvest tool if any).
- Fields: a cultivator tool turns ground into tilled soil (a world object on a grid that follows the local up, like M29's pieces), only within a base (near a bed or workbench). Planting puts a crop on a free soil cell. Crops are world objects: server-authoritative, deltas plus join snapshot, saved as (cell, crop, planted at). The stage is computed from `world_time - planted_at`, so a chunk that was not loaded catches up when it loads and no tick runs for crops.
- Harvest: a use on a ripe crop (server decision) drops its yield as M23 drops; a share of seeds comes back. No watering, weeds or seasons.
- Cooking: stations as M29 pieces: the cooking fire (roast meat and roots, instant) and the cauldron and the oven (meals from recipes, take world time to finish, keep a small queue: the start of M32's station queues). Recipes are M25's `Recipe` with a station.
- Food: three meal slots per player. Eating (an inventory action, server decision) puts a meal in a free slot; each meal adds max health, max stamina and regen for its duration, fading over its last third, through the `Stats` block of M24. The same meal cannot fill two slots. The HUD shows the slots and their time left. Meals come in tiers that follow the realms.
- Flax also makes linen and rope for M25's light armor and M29's pieces.

## Tasks

1. **World time, crops and fields (Opus).** `world_time` in the world file and in the hello snapshot, `CropDef`, tilled soil and crops as world objects, the cultivator, sow and harvest decisions, growth by world time, catch-up on chunk load, save. Tests: a crop is ripe after its grow time of world time and not before; a restart keeps growth; a late joiner sees the same stage; a crop of one realm will not take on another's soil; no tilling outside a base.
2. **Food in Stats (Opus).** Meal slots in the character file, eating on the server, the fade, `Stats` recompute when a meal is eaten or ends, max health above the base without healing for free. Tests: a meal raises max health and stamina; two of the same meal are refused; it fades and ends on time; owner and server agree under lag (network test bot).
3. **Field and kitchen look (Sonnet).** Crop stage models (CC0 plant packs; record them), tilled soil decal, sowing and harvest sounds and particles, the cooking fire, cauldron and oven pieces with smoke and a bubbling loop, the meal slot HUD.
4. **Crops and recipes as data (Sonnet).** Barrowlands crops and meals, the wild plants as resource nodes, numbers small enough that food matters but does not replace gear. Then detail M31's brief and close the milestone.

## Out of scope

Watering, weeds, seasons, rot. Animals (M31). Automated harvest and long station queues (M32). Hunger that hurts.

## Pitfalls

- Max health from food changes a value the sim reads every tick: the owner must apply the new `Stats` on the same tick as the server, as M24 warns, or every hit is corrected.
- Thousands of crop cells: draw them with `MultiMeshInstance3D` per crop and stage, no node per crop; no collision for crops.
- World time must be saved and sent with the snapshot before any crop is shown, or a joining client draws every field as seeds for a moment.
