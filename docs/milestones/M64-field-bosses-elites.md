# M64 Field bosses and elites

Status: Planned.

## Goal

The realm has names to fear: a few field bosses that roam or guard a place, and elite versions of normal enemies that roll affixes such as burning, shielded or swift. Both drop the better loot.

## Depends on

M46, M50 (affixes use types and statuses), M51 (rare drops). M22's pool and spawner.

## Design

- Elites: any kind can spawn as an elite by seed (a small share of camps hold one): more health, larger, a name, and one or two affixes from data (`data/affixes/`): burning (fire damage and buildup), frozen, venomous, shielded (a guard arc), swift, vampiric, enraged at low health, splitting into two normal ones on death (uses free pool slots).
- An affix is a modifier on the `EnemyDef` values applied when the slot becomes the kind (`Enemy.become`), plus at most one rolled back flag; the look gets a tint, an aura and the name plate.
- Field bosses: two or three per realm at seeded sites, each a new `EnemyDef` with its own attacks and a health bar like the Warden's smaller cousin; they respawn after a long world time; some walk a patrol at night (M65).
- Rewards: guaranteed rare or better, runes, and each field boss's own legendary.

## Tasks

1. **Affixes and elites (Opus).** `sim/enemy_def.gd`, `sim/enemy.gd` (`become`, packing), `sim/spawner.gd`, data; tests; `Net.PROTOCOL_VERSION`; load test.
2. **Field bosses (Opus).** Sites, kinds and attacks for the Barrowlands, respawn by world time, saves.
3. **Looks, bots, close (Sonnet).** Tints, auras, name plates, map marks once found; suite scenarios; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

World bosses needing more than six players. Affixes on players.

## Pitfalls

- The pool has 19 spawner slots: splitting elites and boss adds must check for free slots and do nothing when there are none.
- Affix flags widen `Enemy.net_combat`: one byte for all of them.
