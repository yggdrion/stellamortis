# M66 Boss powers

Status: Planned.

## Goal

A fallen boss leaves a trophy. Set on the stones at the arrival, it offers its power: one chosen active blessing with a long cooldown, such as the Warden's well that pulls enemies together. Each player picks one.

## Depends on

M22 (bosses, world flags), M52 (shrines, where a power is chosen). Each realm milestone adds its boss's power.

## Design

- Trophies are items dropped once per boss per world; placed at the arrival's ring they stay for everyone (world file).
- A power is chosen at the trophy or any shrine, one active at a time, saved with the character. Used with a key: an effect for a short time or an instant, then a cooldown of minutes.
  - Warden: a gravity well that drags enemies to a point (the boss's own trick, `Gravity.pull`). Later bosses: Myrkfen's jotun (leaps and no fall damage), the forge king (weapons burn), the Skyshards boss (a gust that throws enemies back).
- State: the chosen power is not rolled back; the active effect and cooldown are (small values on the player), since they change combat.

## Tasks

1. **Trophies and choice (Sonnet).** Items, the ring's stones as objects, saves, the choice panel.
2. **Powers in the sim (Opus).** The effect framework and the Warden's power, `STATE` and `wire.gd`, tests; `Net.PROTOCOL_VERSION`; load test.
3. **Views, bots, close (Sonnet).** Effects, HUD cooldown, bots use powers by skill; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Passive boss perks (the level cap rise is M57's). Powers shared with the party.

## Pitfalls

- A pull on enemies from a player is a player changing enemies: inside its own tick, with `_mutate`.
- Powers must not trivialize the boss they came from on a second kill.
