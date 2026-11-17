# M50 Throwables, bolt types and trinkets

Status: Planned.

## Goal

More tools on the belt: fire pots and frost flasks to throw, special bolts and arrows, cures for statuses, and two trinket slots for charms with passive effects.

## Depends on

M43, M47 (types and statuses to apply and cure), M48 (trinkets use attributes), M49 (the belt beside the flask).

## Design

- Throwables: a hotbar item thrown along the aim arc with local gravity (the bolt slots' code path, a second small projectile kind), bursting in an area on impact: fire pot (burn, lingering flames for a few seconds as a server-side area), frost flask, poison jar, a noise stone that draws unaware enemies (M46).
- Ammunition: bolts and arrows are items; plain ones are free, special ones (fire, frost, barbed for bleed, heavy for stagger) are crafted or found and chosen on the hotbar.
- Cures: bandage (bleed), salve (burn), warm draught (frost), antidote (poison): a short use action.
- Trinkets: two gear slots; each trinket is one strong passive (more stamina, a second wind once per rest, faster flask, damage after a parry). Found in chests and crypts, a few crafted.

## Tasks

1. **Throwing and areas (Opus).** `sim/sim_player.gd` (throw action, projectile slots), lingering areas as server world objects that hurt inside rollback only through a rolled back list kept small; tests; `Net.PROTOCOL_VERSION`; load test.
2. **Ammunition, cures, trinkets (Sonnet).** Items, recipes or loot, the slots in `Inventory` and the panel, effects through the attribute sum.
3. **Views, bots, close (Sonnet).** Projectiles, bursts, flames, HUD belt; bots throw and cure by skill; suite; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Traps. Bombs that break terrain or buildings. Potions that buff for minutes (meals are M66).

## Pitfalls

- A lingering fire that damages must exist identically on every peer during resimulation: either rolled back (costly) or resolved server-side with a short delay; decide and measure in task 1.
- Friendly fire is off today: areas must not hurt allies unless the user wants it.
