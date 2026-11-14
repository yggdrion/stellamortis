# M26 Myrkfen

## Goal

The second realm, behind the Warden's gate: a drowned moor under low gravity. Long floating jumps, fog, black water, dead trees, and enemies built around the gravity. It ends with the drowned jotun and gives the tier 2 gear.

## Depends on

M25 (gear tier 1, recipes, resource nodes). File level detail is added by M25's last task.

## Design

- `RealmDef` `myrkfen`: gravity about 3.5 m/s² (jumps carry 3 times as far, bolts fly flat), its own seed salt, biome and arrival. Gate open while `warden_fallen`.
- Biome: low ground under shallow black water (wading slows; deep pools are not swimmable yet: they are avoided by terrain shaping), reed, dead birches, hanging fog, pale lights. Water is a view plus a slow zone in the sim (`Terrain.height` below a water level).
- Enemies: the leaping drowned (melee, long low-gravity leaps: uses M22's leap), the bog wight (ranged, lobbed spit that leaves a slowing pool for a few seconds), the wisp (floats toward a player and bursts; kill it at range or roll away). Camps mix them. Search for a CC0 creature model that fits before building the wisp from particles and a light.
- Resources: resin (dead trees), bog iron (nodes in the water). Tier 2 recipes, two sets, perk tree tier 2 (unlocks with the level cap).
- Boss: the drowned jotun, a giant (Warden scale or larger) at a boss site on an island. Hurls rocks on long arcs that leave no safe standing still, a wading sweep, and in phase 2 a wave that must be jumped (low gravity makes it a long jump). Sets `jotun_fallen`.

## Tasks

1. **Realm and biome (Sonnet).** `RealmDef`, terrain shaping parameters for the biome, water view and wading zone (the zone is sim: Opus reviews it), scatter, fog and light, ambience. Screenshots.
2. **Enemy kinds (Opus for behaviors, Sonnet for defs and looks).** Lobbed shots that leave a ground area (enemy bolt slots plus a rolled back area slot), the wisp's burst, defs, attacks, looks, sounds, camp recipes. Tests for each behavior.
3. **Resources and tier 2 (Sonnet).** Nodes, items, recipes, two sets with set perks, perk tree tier 2.
4. **The drowned jotun (Opus).** Boss behavior, site, health scaling, tests like `encounter_test.gd` (each move, phase 2, the flag, the gate). Then detail M27's brief and close the milestone.

## Out of scope

Swimming and boats. Weather.

## Pitfalls

- Low gravity changes every arc: enemy bolts aim with `Gravity.sample` already; check lobbed shots and leaps land where the telegraph says.
- Ground areas left by shots are rolled back state: fixed slots, like bolts, never spawned nodes.
- Players can jump very far: `TerrainChunks.LOAD_RADIUS` must still cover a sprint jump.
