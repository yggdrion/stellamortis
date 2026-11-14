# M23 Inventory, loot and saves

Status: planned.

## Goal

Killing things pays. Enemies burst into loot that is worth running for, gear changes how a fight goes, the inventory is pleasant to manage, and the world and the character survive a restart.

## Depends on

M22 (kinds, world flags, cleared camps). File level detail is added by M22's last task.

## Design

- `ItemDef` (resource, `game/data/items/`): id, name, kind (weapon, shield, ranged, armor piece, trinket, material, bolt, consumable), slot, stack size, rarity, weight, stats (damage, defense, stamina), icon, model.
- Inventory lives on the server per player: a bag of 32 cells and gear slots apart from it, so worn gear takes no bag space: main hand, off hand, ranged, helm, chest, legs, cape, two trinkets, bolts. Clients send intents (`move`, `split`, `equip`, `drop`, `sort`, `store_matching`), the server answers with deltas; a snapshot at join.
- Rolled back: only the equipped ids that combat needs (main hand, off hand, ranged, armor total as one small int each), in a packed group. `Combat` reads damage and defense from them.
- Drops are world objects: server-side entries (id, item, count, position), sent as deltas; clients animate them. Pickup is a server decision on an intent or on walking over (materials auto pick up).
- Loot tables per `EnemyDef` and per chest, as data.
- Death: the bag (not the worn gear) stays in a grave at the place of death; the grave is a world object, saved, and only its owner can open it for 10 minutes.
- Character file on the client: `user://characters/<name>.json` (player ID, inventory, gear; level and perks from M24). Sent with hello; the server uses it as is. The server sends the character back on change and the client writes it (temp file, rename), so a crash loses seconds, not the session.
- World file on the server: `user://worlds/<name>.json` (seed, flags, cleared camps with times, world objects). Autosave every few minutes and on exit.
- `Settings` gets a random player ID.

## Tasks

1. **Items, inventory, equipment (Opus).** `ItemDef`, `sim/inventory.gd` (pure logic: move, split, merge, sort, equip rules; fully unit tested), the server's per player inventory, RPCs and join snapshot in `net/net.gd`, equipped ids in `SimPlayer` state with wire serializers, `Combat` reading them, the starting kit. Tests: every inventory operation, including full bag and bad intents from a client; damage and block change with gear; wire size.
2. **Loot feel (Sonnet).** Drops fly out on an arc, land, glow by rarity with a light beam for rare ones, pull toward a nearby player, pickup sound and a HUD toast; chests in camps with an opening animation; the elite's chest. Screenshots and the user's verdict: this is a stated goal of the milestone.
3. **Inventory panel (Sonnet).** `Menus.theme()`. Paper doll with gear slots beside the bag grid, hotbar (1 to 8), drag and drop, stack and split, one-click sort, "store all that the chest already holds", shift-click to move or equip, compare tooltip against worn gear, junk marking, weight. Controller-free for now; every action also has a key.
4. **Saves and graves (Opus).** World file and character file as designed, graves, `--world=NAME`. Tests: save, restart, same flags, objects and inventory; a corrupt or missing file starts clean without crashing and keeps the bad file aside; a version field in both files.
5. **World list (Sonnet).** Main menu: new world (name, seed), continue, delete with confirmation; host and solo pick a world. Then detail M24's brief and close the milestone.

## Out of scope

Crafting and resources (M25). Levels and perks (M24). Trading. Server-side validation of characters (decided: trusted).

## Pitfalls

- Inventory is not rolled back, combat is: an equip arrives at a tick. Apply it on the server in the tick loop and let the equipped ids travel as state, so prediction corrects itself.
- Drops must not be nodes in rollback. They are plain server data with client views.
- Never write a save in place: temp file, flush, rename.
- The character comes from the client: clamp counts and reject unknown ids so a broken file cannot crash the server, even though cheating is accepted.
