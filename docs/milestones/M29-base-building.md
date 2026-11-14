# M29 Base building

Status: planned.

## Goal

A group builds a hall of its own on any realm: floors, walls, roofs, doors, stairs and stations, placed for materials, snapped together and saved with the world.

## Depends on

M25 (materials, recipes, stations, world objects with collision). Can run before M26 to M28 if the user wants building earlier. File level detail is added when it starts.

## Design

- A piece is a world object: `PieceDef` (resource: model, collision shape, snap points, cost, health) and an entry in the world (def, transform, health). Server-authoritative, deltas plus join snapshot, saved. Collision exists on every peer in loaded chunks.
- Placement: build mode shows a ghost that snaps to the snap points of nearby pieces and to the ground, aligned to the local up (pieces keep the up of where they were placed, so a hall on a round realm is built in its own tangent frame: the first piece of a structure sets the frame, later pieces snap into it). The client sends an intent; the server checks cost, reach, overlap and the budget.
- Removal returns the materials. Enemies do not attack pieces in M29.
- Stations as pieces: workbench, forge, chest, bed (sets the owner's respawn point, replacing the keep).
- Budget: a piece count per world from a load test of join snapshot size, collision cost and frame time; start at 2000 and measure.
- Pieces: floor, wall, half wall, roof slope, door, stairs, beam, fence, torch. The Medieval Village MegaKit has more than is vendored: add the pieces used and record them.

## Tasks

1. **Pieces in the world (Opus).** `PieceDef`, placement and removal on the server, snap and overlap rules, collision per chunk, deltas, snapshot (chunked if large), save, the budget. Tests: place, snap, reject overlap, remove and refund, restart, late joiner, a player standing on a placed floor through a rollback.
2. **Build mode (Sonnet).** The piece wheel, ghost preview (green or red), rotation, snapping feedback, hammer sounds, dust.
3. **Stations and bed (Sonnet).** Station pieces reuse M25's panels; bed respawn in `SimPlayer._respawn`'s spawn choice (a server decision). Then detail M30's brief and close the milestone.

## Out of scope

Structural integrity, raids on bases, terrain editing, decay.

## Pitfalls

- Placing a floor under a predicted player is a collision change outside rollback, like felling a tree (M25): accept one correction.
- Flat pieces on a sphere: a structure's frame is fixed by its first piece, so a very long hall lifts off the ground at its ends. That is acceptable at 1000 m radius (0.5 m over 30 m); do not bend pieces.
- Snapshot size: thousands of pieces must not go through one RPC packet. Send by chunk as the player's chunks load.
