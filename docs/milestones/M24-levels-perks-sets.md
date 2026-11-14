# M24 Levels, perks and sets

Status: planned.

## Goal

A character grows: kills and discoveries give XP, each level gives a point for one of three perk trees, and gear sets grant perks of their own. Builds differ between players and every boss raises the ceiling.

## Depends on

M23 (items, character file, RPC pattern for per player data). File level detail is added by M23's last task.

## Design

- `Perk` (resource): id, name, text, a list of stat modifiers (`stat`, `add`, `mul`) and optional flags for effects the sim checks by name (for example `parry_stagger_long`, `roll_cheap`, `bolt_pierce`). Perks come from three sources and stack through one path: the trees, single items (`ItemDef.perks`) and full sets (`ItemDef.set`, `SetDef` with the pieces needed and its perks).
- `Stats`: one block per player (max health and stamina, regen, damage per weapon type, defense, roll cost, carry weight, gather speed, flags). The server recomputes it when level, perks or gear change and sends it to the owner by reliable RPC; `SimPlayer` and `Combat` read `Stats` instead of raw `Tuning` values on both sides. Not rolled back: it changes rarely, and a few ticks of mismatch correct themselves.
- XP: kills, first discovery of a camp, site or realm, bosses. The curve and all amounts are data.
- Group sharing: a kill gives its full XP to every living player within 40 m and to everyone who damaged the enemy, wherever they stand. It is not split, so playing together never pays less than playing alone. Dead players get none. Discoveries and bosses pay everyone in the realm.
- Death drops XP (the user's idea, 2026-11-14, like Dark Souls and Elden Ring): the XP gained toward the next level falls into the grave M23 leaves at the place of death, next to the bag. Touching the grave gives it back. Dying again before that replaces the grave's XP with the new, smaller amount: the old XP is lost. Levels already reached and perk points are never lost. The HUD shows how much lies in the grave and where it is.
- Level cap: 10 per fallen boss plus 10 (`World.flags`), so levels cannot outrun the realm order. The character keeps its level in a world with fewer flags; only gaining is capped.
- Trees (data, `game/data/perks/`): warrior (sword, shield, parry), ranger (crossbow, movement, stamina), crafter (gathering, carrying, crafting, building). About 10 perks each in tier 1, some with prerequisites; tiers 2 and 3 arrive with M26 and M27. Respec at the keep for a cost.

## Tasks

1. **Stats and perks in the sim (Opus).** `Perk`, `SetDef`, `Stats`, the recompute on the server, the RPC, `SimPlayer` and `Combat` reading stats, flags checked where their effect lives. Tests: a perk changes damage, stamina cost and the roll; a flag changes parry stagger; a set grants its perk only when complete; client and server agree after a gear change under simulated lag (network test bot).
2. **XP and levels (Opus).** Server-side XP sources, group sharing, the drop on death and the body run, curve, cap from flags, saved in the character file (the dropped XP is saved with the grave in the world file). Tests: every nearby living player and every damager gets the full amount, a dead one none; death moves progress XP into the grave and touching it returns it; a second death loses the first grave's XP; levels are never lost; the cap; no XP from the keep's dummies.
3. **Trees as data (Sonnet).** The three tier 1 trees with numbers small enough to stay balanced (single digit percents, one strong capstone per tree); respec.
4. **Character panel and level-up (Sonnet).** Level, XP bar, trees with prerequisites, active set bonuses, item tooltips that show set progress; the level-up moment (sound, glow, HUD banner). Then detail M25's brief and close the milestone.

## Out of scope

Skills that rise by use. Classes. Perks for realms that do not exist yet.

## Pitfalls

- `Stats` feeds prediction: the owner must have the same block as the server before the tick that uses it, or every swing is corrected. Send on change, apply at once on both sides, and test it under lag.
- Flags are checked by name in sim code: keep them few and each with a test, or they rot.
- Balance by data only; no perk may need a new rolled back field without a wire serializer and a protocol bump.
