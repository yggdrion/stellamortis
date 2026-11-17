# M44 Weapon types

Status: Planned.

## Goal

Weapons differ by how they fight, not only by numbers: sword, axe, mace, spear, greatsword, daggers and bow each have their own attack chain, reach, speed and stamina cost. A player finds the type that suits them.

## Depends on

M43 (types give each weapon its damage). M39 (gear generators draw the new weapons). M24.

## Design

- `WeaponType` data (`data/weapons/<type>.tres`): the light chain (a list of `AttackDef` ids, linked by `next` as enemy combos already are), the heavy, block strength, parry window, move speed while swinging, the UAL clips.
  - Sword: balanced three-hit chain. Axe: two wide slow hits, high damage. Mace: blunt, short reach, high stagger. Spear: long thrusts in a narrow arc, keeps enemies away. Greatsword: two-handed, slow sweeps, no shield. Daggers: fast four-hit chain, short reach, bonus from behind (M46). Bow: faster than the crossbow, weaker, arcs more.
- `SimPlayer` looks the chain up by the worn weapon's type instead of `Combat.PLAYER_ATTACKS`; `SimPlayer.weapon` (sword or crossbow today) becomes "melee or ranged slot", the type comes from the item id that is already rolled back.
- Two-handed weapons empty the off hand; the inventory shows it.
- Enemies can use the same types (`EnemyDef` names a weapon type or keeps its own attacks).

## Tasks

1. **Chains by type (Opus).** `sim/sim_player.gd`, `sim/combat.gd`, new `sim/weapon_type.gd`, `data/weapons/`, `data/attacks/`; `tests/combat_test.gd`, new `tests/weapon_type_test.gd`; `Net.PROTOCOL_VERSION`; load test.
2. **Content (Sonnet).** The seven types' attacks and numbers, items per type in `data/items/`, loot tables, generators' parameters (M39).
3. **Views and bots (Sonnet).** Clips per type in `PlayerView`, telegraph arcs, HUD weapon name; `BotBrain` learns reach and chain length per type; suite expectations; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Special moves and weapon skills (M45). Magic staves. Dual wielding two different weapons.

## Pitfalls

- UAL has sword, shield and zombie clips but few spear or two-handed ones: check the clip list first; a type without a fitting clip waits or reuses one at a different speed.
- Reach and arc are sim truth; the generated weapon's length must match (M39's pitfall).
- Every `AttackDef` id is state on the wire: adding many attacks must not widen the synced field.
