# M69 Base raids

Status: Planned.

## Goal

What the players build draws attention. After a boss falls, the dead of its realm sometimes march on the homestead: a warning horn, a few waves, walls and gates to hold. A defended raid pays; a lost one costs repairs.

## Depends on

M64 (pieces with health), M61 (elites lead waves), M62 (raids prefer the night), M68 only for its place at the end.

## Design

- A raid is scheduled by world time and progress (which bosses fell), only where enough pieces stand and a player is home. A horn and a map mark give a minute's warning.
- Waves use the enemy pool (so they are small groups, not hordes): kinds from the realms whose bosses fell, an elite leader in the last wave. They walk at the nearest player or the base's heart (a placed hearth).
- Pieces have health; raiders attack what blocks them. Damage is repaired with a share of the materials. Nothing is destroyed for good unless the user wants that harder mode.
- Reward on success: a raid chest. On failure: damaged pieces, stolen stacks from open chests.
- A world setting turns raids off, lowers or raises them.

## Tasks

1. **Scheduling and waves (Opus).** New `sim/raid.gd`, `sim/spawner.gd` (raid camps), enemy targeting of pieces, piece health in world objects; tests; load test during a raid.
2. **Views, settings, bots, close (Sonnet).** Horn, marks, the raid HUD, world setting in the world list; a bot scenario defending a base; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Sieges with machines. Enemies that build. Raids on empty bases while nobody is online.

## Pitfalls

- Enemies walk straight lines with a trunk sidestep: around player-built walls they need a simple "attack what blocks me" rule, not a navigation mesh.
- A raid takes pool slots from normal camps nearby: decide which sleeps.
- Losing hours of building to a raid ends play sessions badly: keep the default gentle.
