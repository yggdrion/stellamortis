# M50 Status buildup

Status: Planned.

## Goal

Bleed, burn, frostbite and poison build up with each hit and trigger when the bar fills: a burst of blood damage, fire over time, a slow that cuts stamina, health draining away. On players and on enemies.

## Depends on

M46 (types cause the matching status). M24.

## Design

- Four statuses, each with a meter per body: buildup from attacks (`AttackDef` parts carry a buildup amount), decay when not fed, a trigger at full, resistance per body (`EnemyDef`, player gear).
  - Bleed (slash, pierce): at full, a burst of a share of max health. Burn (fire): damage over time, spreads no further. Frostbite (frost): slower movement and stamina regain, more damage taken once. Poison: slow drain for long.
- State: per body four meters and the active effects' remaining ticks. Rolled back, so they go into `STATE`, the packed groups and `wire.gd`; quantize meters to a byte each.
- Bosses resist most; each realm's enemies bring their own (Myrkfen poison, Jarnfell burn, Skyshards frost), which is why this comes before the realms.
- View: meters near the health bar (own) and over a target once it has buildup, a tint and particles on an affected body, icons with a timer.

## Tasks

1. **Meters and effects (Opus).** `sim/status.gd` (pure helpers), `sim/sim_player.gd`, `sim/enemy.gd` (`_pack_state`/`_unpack_state`), `net/wire.gd`, `data/`; `tests/status_test.gd`, `tests/wire_test.gd`; `Net.PROTOCOL_VERSION`; load test with the pool full (bytes per player).
2. **Content and views (Sonnet).** Buildup on weapons and enemy attacks, resist data, HUD meters, effects, sounds.
3. **Bots and close (Sonnet).** Bots back off when burning or bleeding; suite; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Cures as items (M53 adds them). Status on world objects. Madness, sleep and other exotic statuses.

## Pitfalls

- Eight more bytes per body times 20 pool slots: measure the snapshot size; hidden enemies must still pack to 1 byte.
- Damage over time must tick inside rollback and be deterministic: integer amounts per tick, no floats accumulating.
- Bleed's burst on a boss with huge health needs a cap.
