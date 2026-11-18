# M59 Upgrades and runes

Status: Planned.

## Goal

Gear grows with the player: the smithy raises an item's level with materials, and runes found in the world are set into sockets for extra effects. A good find stays useful for longer.

## Depends on

M58 (materials, stations, recipes), M51 (item instances and attributes).

## Design

- Upgrade level on the item instance (0 to 4 per tier): each level raises base damage or armor by a fixed share and costs rising amounts of that tier's materials; done at the smithy. The cap rises with the station's level.
- Sockets: an item rolls 0 to 2 sockets by rarity. Runes are items (`data/runes/`): a damage type added to a weapon, resistance or buildup on armor, a small utility effect. Setting a rune is free at the workbench; removing one destroys it unless a rare tool is used.
- Rerolling one attribute at a cost, at a later station level.
- Salvage: breaking an item returns part of its materials and its runes' dust.
- All of it is server-side inventory work; nothing new is rolled back.

## Tasks

1. **Instances, upgrade, sockets (Opus).** `sim/inventory.gd`, item instance fields, station actions as RPCs, saves; tests.
2. **Runes, salvage, reroll, views (Sonnet).** Data, the station panels, tooltip lines, sounds; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Enchanting with random outcomes that can destroy items. Rune words.

## Pitfalls

- Every instance field must survive the character file round trip and old files.
- Upgrades multiply with rarity and perks: let the M24 suite check the top end does not trivialize bosses.
