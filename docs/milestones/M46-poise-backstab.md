# M46 Poise break and backstab

Status: Planned.

## Goal

Pressure pays off: an enemy whose poise breaks kneels and takes a critical hit. Careful players are rewarded too: crouch, come from behind unseen, and the first strike hits hard.

## Depends on

M19 (poise, flinch), M44 (stagger per weapon type). M24.

## Design

- Poise break: `Enemy.poise` already drains (M19). At zero the enemy enters `BROKEN` for a short time; a heavy or a dagger light on a broken enemy is a critical (a damage multiplier, its own clip, a longer hit stop). Poise recovers after a pause. Bosses break too, more rarely.
- Players have poise as well: heavy armor and the greatsword stance resist flinching; a broken player is staggered, not executed.
- Sneak: a crouch toggle (slower, lower capsule not needed). Enemies get senses: a vision cone and range, hearing by the player's move speed, both as data in `EnemyDef`. An unaware enemy shows no mark; an alerted one turns and wakes its camp.
- Backstab: a hit from behind on an unaware enemy multiplies damage (more with daggers) and breaks poise.
- Awareness is rolled back state on the enemy (one small value in `Enemy.net_combat`, packed by hand).

## Tasks

1. **Poise break and criticals (Opus).** `sim/enemy.gd`, `sim/sim_player.gd`, `sim/enemy_def.gd`, `data/enemies/`; `tests/combat_test.gd`, `tests/bestiary_test.gd`; `Net.PROTOCOL_VERSION`.
2. **Senses and sneak (Opus).** `sim/mob.gd` (unaware, suspicious, alerted), crouch in `SimPlayer`, `Spawner` wakes camps unaware; tests; load test.
3. **Views, bots, close (Sonnet).** Kneel and critical clips, the awareness mark over an enemy, crouch pose, sneak sound levels; `BotBrain` uses criticals; suite; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Stealth kills that skip the fight. Light and shadow affecting sight. Distraction items.

## Pitfalls

- Camps wake as a whole today (`Spawner` wake at 90 m): "unaware" is a state after waking, not sleeping.
- Vision checks per enemy per tick cost: check on a few ticks' interval and only against players within range.
- With six players someone is always seen: backstab must still matter through poise breaks.
