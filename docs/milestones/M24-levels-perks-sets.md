# M24 Levels, perks and sets

Status: planned.

## Goal

A character grows: kills and discoveries give XP, each level gives a point for one of three perk trees, and gear sets grant perks of their own. Builds differ between players and every boss raises the ceiling.

## Depends on

M23 (items, character file, RPC pattern for per player data). File level detail is added by M23's last task.

## Design

- `Perk` (resource): id, name, text, a list of stat modifiers (`stat`, `add`, `mul`) and optional flags for effects the sim checks by name (for example `parry_stagger_long`, `roll_cheap`, `bolt_pierce`). Perks come from three sources and stack through one path: the trees, single items (`ItemDef.perks`) and full sets (`ItemDef.set`, `SetDef` with the pieces needed and its perks).
- `Stats`: one block per player (max health and stamina, regen, damage per weapon type, defense, roll cost, carry weight, gather speed, flags). The server recomputes it when level, perks or gear change and sends it to the owner by reliable RPC; `SimPlayer` and `Combat` read `Stats` instead of raw `Tuning` values on both sides. Not rolled back: it changes rarely, and a few ticks of mismatch correct themselves.
- XP: kills (shared among players within 40 m), first discovery of a camp, site or realm, bosses. The curve and all amounts are data.
- Level cap: 10 per fallen boss plus 10 (`World.flags`), so levels cannot outrun the realm order. The character keeps its level in a world with fewer flags; only gaining is capped.
- Trees (data, `game/data/perks/`): warrior (sword, shield, parry), ranger (crossbow, movement, stamina), crafter (gathering, carrying, crafting, building). About 10 perks each in tier 1, some with prerequisites; tiers 2 and 3 arrive with M26 and M27. Respec at the keep for a cost.

## Tasks

1. **Stats and perks in the sim (Opus).** `Perk`, `SetDef`, `Stats`, the recompute on the server, the RPC, `SimPlayer` and `Combat` reading stats, flags checked where their effect lives. Tests: a perk changes damage, stamina cost and the roll; a flag changes parry stagger; a set grants its perk only when complete; client and server agree after a gear change under simulated lag (network test bot).
2. **XP and levels (Opus).** Server-side XP sources, sharing, curve, cap from flags, saved in the character file. Tests: sharing, the cap, no XP from the keep's dummies.
3. **Trees as data (Sonnet).** The three tier 1 trees with numbers small enough to stay balanced (single digit percents, one strong capstone per tree); respec.
4. **Character panel and level-up (Sonnet).** Level, XP bar, trees with prerequisites, active set bonuses, item tooltips that show set progress; the level-up moment (sound, glow, HUD banner). Then detail M25's brief and close the milestone.

## Out of scope

Skills that rise by use. Classes. Perks for realms that do not exist yet.

## Pitfalls

- `Stats` feeds prediction: the owner must have the same block as the server before the tick that uses it, or every swing is corrected. Send on change, apply at once on both sides, and test it under lag.
- Flags are checked by name in sim code: keep them few and each with a test, or they rot.
- Balance by data only; no perk may need a new rolled back field without a wire serializer and a protocol bump.
