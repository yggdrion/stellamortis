# M53 Downed and revive

Status: Planned.

## Goal

In a party a fallen player is not dead at once: they go down, can crawl, and an ally can pull them up within a short time. Alone, death is as before.

## Depends on

M24 (bots measure what it does to boss difficulty). After M49 (flask) so revive health and flask rules fit.

## Design

- At zero health with a living ally within range, a player enters `DOWNED` (a rolled back action) with a bleed-out timer; otherwise they die as today. Downed players crawl slowly, cannot act, and enemies lose interest in them unless no one else is near.
- Revive: an ally holds the use key next to them for a few seconds (interrupted by damage or moving); the revived player stands with part of their health and a short grace. Each revive in a fight shortens the next bleed-out.
- Bleed-out or a hit by a boss's area while downed is death: grave, XP drop and respawn as today.
- A wipe (everyone downed) kills all at once.
- View: a marker and timer over the downed ally, on the compass and map, a call sound; the downed player's screen is dimmed with the timer.

## Tasks

1. **Downed in the sim (Opus).** `sim/sim_player.gd` (`DOWNED`, revive progress as rolled back state), `sim/mob.gd` and `sim/warden.gd` (target choice), `sim/encounter.gd` (wipe rule); tests; `Net.PROTOCOL_VERSION`; load test.
2. **Views, bots, close (Sonnet).** Clips, markers, HUD; bots revive by skill and safety; suite expectations for party boss fights; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Revive items. Carrying downed players. Spectating after death.

## Pitfalls

- Revive progress is shared between two players' rollback ticks: the reviver changes the downed player's state only inside its own tick and calls `_mutate`, as with enemies.
- Party fights get easier: the boss's health scaling for the players in the ring may need a step up; let the suite say so.
