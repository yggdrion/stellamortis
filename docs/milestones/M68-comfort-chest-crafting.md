# M68 Comfort and chest crafting

Status: Planned.

## Goal

A home is worth furnishing: resting among fire, bed and furniture gives a rested buff that lasts into the next trip. And stations take materials straight from nearby chests, with one key to stash everything where it belongs.

## Depends on

M67 (base building, pieces and stations), M57 (`Stats` for the buff).

## Design

- Comfort: each furniture piece has a comfort kind and value; the best of each kind within range of a bed or fire counts. Sitting or sleeping there for a short time gives "rested": better stamina and health regain for a time that grows with comfort. Shown as a buff with a timer; saved with the character.
- Sleeping through the night when everyone in the world lies in a bed (skips world time to dawn; M65's night can be slept away only at home).
- Chest crafting: a station sees the chests within a radius of itself; recipes count and take from them and the bag. Chests can be named and given an icon.
- Quick stash: one key near chests moves every item whose kind is already in a chest into it; a lock mark keeps chosen bag cells out. Sorting buttons for chests like the bag's.

## Tasks

1. **Comfort and rested (Sonnet).** Piece data, the range check on the server, the buff through `Stats`, sleep and time skip; tests.
2. **Chest crafting and stash (Sonnet).** Station queries over world objects, RPCs, panel changes; tests for counts and races between two players.
3. **Close (Sonnet).** HUD, sounds, play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Automation between chests (M71's hoppers and chutes). Decoration with no comfort value beyond what M67 has.

## Pitfalls

- Two players crafting from the same chest at once: the server takes materials atomically or refuses.
- Skipping time jumps growth, breeding and anomalies: they are all computed from world time, so it must hold, but test it.
