# M48 Moves and weapon skills

Status: Planned.

## Goal

More to do with a weapon in hand: a jump attack, a charged heavy, a guard counter after a block, and one special skill per weapon type on its own key. Fights have more decisions than light, heavy, block, roll.

## Depends on

M47 (weapon types). M24.

## Design

- Jump attack: attack while airborne is its own `AttackDef` per type, with a landing recovery.
- Charged heavy: holding the heavy key charges up to a cap for more damage and stagger; released early it is the normal heavy. The charge time is `action_time`, no new state.
- Guard counter: after a successful block (not parry) a heavy within a short window is a fast counter with high stagger.
- Weapon skill (new input bit `SKILL`): one per type, costs stamina and has a cooldown. Sword: lunge. Axe: spinning cleave. Mace: ground slam that staggers around. Spear: charging thrust. Greatsword: a stance that takes a hit without flinching, then a sweep. Daggers: quick step through the enemy. Bow: a three-arrow spread. Crossbow: a piercing bolt.
- Cooldown is one new rolled back value on the player (ticks left); it goes into `STATE`, a packed group and `net/wire.gd`.

## Tasks

1. **Moves (Opus).** `sim/sim_player.gd` (action machine: `JUMP_ATTACK`, `CHARGE`, `COUNTER`, `SKILL`), `sim/player_controls.gd`, `net/wire.gd`, `data/attacks/`; tests per move; `Net.PROTOCOL_VERSION`; load test (state size under 508 bytes).
2. **Skills content and views (Sonnet).** The eight skills' numbers, clips, trails and sounds, a cooldown mark on the HUD, key binding in settings.
3. **Bots and close (Sonnet).** `BotSkill.uses_skill`, suite expectations, play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Skills that can be swapped between weapons. Combo trees. Mounted combat.

## Pitfalls

- The input bit set is nearly full: check `PlayerControls` before adding `SKILL`.
- A step through an enemy (daggers) moves a body through another: do it as a short dash with enemy collision off, inside the player's own tick.
- Every new action needs its flinch, block and roll-cancel rules written down, or the state machine gets stuck states.
