# M25 Gather and craft

Status: planned.

## Goal

The land gives materials and the smithy turns them into gear. A player fells trees, breaks rock and ore, and crafts the Barrowlands tier, including two armor sets, which is what the next realm asks for.

## Depends on

M23 (items, world objects for drops, saves), M24 (set perks, crafter tree), M20's `Scatter.points`. File level detail is added by M24's last task.

## Design

- Resource nodes are world objects derived from the seed (`Scatter.points`, the same function the client used for visuals in M20): the world stores only what differs from the seed (felled, mined, regrowing with a time). Collision exists on every peer, built with the terrain chunks, so players and enemies walk around trees and rocks.
- Hitting a node is a server decision from the player's swing (the sim tells the server which node a swing with a tool reached; node health is not rolled back). A felled tree falls, breaks into logs as drops, and regrows after a long time; ore veins do not regrow.
- Tools are weapons with a `tool` kind and tier: axe (wood), pickaxe (stone, ore). A tool too weak for a node bounces off with a clear sound.
- `Recipe` (resource): station, inputs, output, required flag. Stations: the workbench and the smithy at the keep. Crafting takes materials from the bag and from chests within a few metres. Upgrades raise an item's level for more materials.
- Tier 1: sword, axe, shield, crossbow, bolts, a heavy set (iron scrap: defense, a set perk around blocking) and a light set (leather and bone: stamina, a set perk around rolling).

## Tasks

1. **Resource nodes (Opus).** Nodes in the sim from `Scatter.points`, collision with the chunks, the world's diff list, deltas and join snapshot, save and regrowth, tool hits. Tests: same seed gives the same nodes on two peers; a felled tree stays felled after a restart and for a late joiner; a player cannot walk through a tree; rollback replay near a node is deterministic.
2. **Tools and gathering feel (Sonnet).** Axe and pickaxe (attack defs, clips), chop and crack sounds, chips flying, the tree leaning and falling, logs and stones as drops (M23's loot feel), the bounce for weak tools.
3. **Recipes and stations (Sonnet).** `Recipe` data, the station panels (what you can make, what is missing, craft and upgrade), nearby chests as a source, tier 1 with both sets and their set perks. Then detail M26's brief and close the milestone.

## Out of scope

Placing stations in the world (M29). Farming and cooking (M30). Smelting chains (ore to bar is one recipe for now).

## Pitfalls

- A node's collision disappearing is a world change outside rollback: the owner may be predicted against a tree the server has already felled. Remove the collision on the tick the delta is applied and accept one small correction; never put nodes into rollback.
- Thousands of nodes: collision only inside loaded chunks; visuals stay `MultiMeshInstance3D`, with felled instances hidden by index.
- The seeded scatter is now gameplay: changing `Scatter.points` breaks saved worlds. Version it, and keep the old function for old saves or bump the save version on purpose.
