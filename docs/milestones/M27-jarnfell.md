# M27 Jarnfell

Status: planned.

## Goal

The third realm, behind the jotun's gate: ash, slag and dead forges under heavy gravity. Jumps are short, rolls cost more, bolts drop fast, and the enemies are armored. It ends with the forge king and gives the tier 3 gear.

## Depends on

M26. File level detail is added by M26's last task.

## Design

- `RealmDef` `jarnfell`: gravity about 18 m/s². Gate open while `jotun_fallen`.
- Biome: black rock, ash fields, slag rivers that glow (the one warm color: it means damage), ruined forges and chains. Standing in slag burns (a damage zone in the sim).
- Enemies: the iron brute (heavy armor from every side, slow; only parries and heavy attacks open it), the ash crawler (weak, comes in groups of 4 to 6, the pool's cheap filler), the forge thrall (throws slag that leaves a burning area: reuses M26's ground areas).
- Resources: ore and coal; tier 3 recipes, two sets, perk tree tier 3.
- Boss: the forge king. A hammer combo, a gravity slam that pulls players in and then throws them back (reuses `Gravity.pull`, the Warden's well), and in phase 2 slag that floods parts of the arena. Sets `king_fallen`.

## Tasks

1. **Realm and biome (Sonnet).** Realm def, shaping, slag view and burn zone, scatter, light, ambience.
2. **Enemy kinds (Opus for behaviors, Sonnet for defs and looks).** Armor that only breaks on parry or heavy (`EnemyDef.armor`), groups that share one camp point, the thrall.
3. **Resources and tier 3 (Sonnet).**
4. **The forge king (Opus).** Then detail M28's brief and close the milestone.

## Out of scope

Heat as a survival stat. Mounts.

## Pitfalls

- Crawler groups fill the pool fast: check the load test with a group awake per player.
- High gravity changes `SimPlayer._step_up` and jump heights: rerun `movement_test.gd` on the realm.
- Slag glow must not break the color rule: warm glow means danger, nothing else in the realm glows warm except torches.
