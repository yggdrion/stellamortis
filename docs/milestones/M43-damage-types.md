# M43 Damage types and weaknesses

Status: Planned.

## Goal

Every hit has a type: slash, blunt, pierce, fire, frost, poison, spirit. Enemies are weak to some and resist others, and the hit number's color tells the player which. Choosing the right weapon for an enemy starts to matter.

## Depends on

M23 (items). M24 (the bot suite measures the balance change). Before M44, M47, M54 and M55, which all build on types.

## Design

- `Combat.DamageType` (enum; check the name shadows no native class). `AttackDef.damage` becomes a small set of (type, amount) parts; most attacks have one, a fire sword has two. Weapon items carry the parts; a player attack takes them from the worn weapon's `ItemDef`, the motion from the `AttackDef`.
- `EnemyDef.resist`: a multiplier per type (0.5 resists, 1.5 weak, 0 immune). Player armor gets flat resistance per type from worn gear, through the `Stats` block when M54 lands; until then from `ItemDef` directly.
- Damage is computed in the one place hits land today (`Enemy.take_hit`, `SimPlayer` taking enemy swings and bolts). No new rolled back state: types are data, health is already synced.
- View: `Hud._show_damage` and enemy hit numbers color by outcome (weak, normal, resisted, immune), a short "resists" or "weak" word on the first such hit per enemy kind, hit sounds per type (`Sounds`).
- The Barrowlands kinds get resist tables that make sense (the dead: weak to blunt and spirit, resist pierce and poison; the Warden: resists slash).

## Tasks

1. **Types in the sim (Opus).** `sim/combat.gd`, `sim/attack_def.gd`, `sim/enemy_def.gd`, `sim/item_def.gd`, `sim/enemy.gd`, `sim/sim_player.gd`, `data/attacks/`, `data/enemies/`, `data/items/`; `tests/combat_test.gd`, new `tests/damage_type_test.gd`. Bump `Net.PROTOCOL_VERSION` only if a synced value changes shape.
2. **Feedback (Sonnet).** Hit numbers, words, sounds, the item tooltip's damage lines and an enemy's known weaknesses (learned by hitting it, kept in the character file).
3. **Balance and close (Sonnet).** Resist tables, run the M24 suite, set new expectations, play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Status effects (M47). New weapons (M44). Elemental surfaces (burning ground, frozen water).

## Pitfalls

- Multipliers stack with block, parry and riposte: fix the order once (type multiplier, then armor, then block) and test it.
- A player who cannot hurt an enemy at all is stuck: no starting enemy is immune to the starting weapons.
- The M24 bots must pick a weapon by type, or the suite reports nonsense after this milestone.
