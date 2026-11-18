# M42 Loadout and equip load

Status: Planned.

## Goal

A new character has spare gear in the bag to try on. The bag weighs nothing; only what is worn counts, and the equip load decides how fast stamina comes back and how the player rolls: light, medium, a heavy "fat" roll, or no roll at all. A bar shows weapon sets 1 and 2.

## Depends on

M23 (items, inventory, saves), M24 (the suite judges the roll change). Independent of M41 and M43.

## Design

- Equip load: the sum of `ItemDef.weight` over the worn slots, against a max in `data/tuning.tres` (`equip_load_max`; M57's `Stats` takes it over). The bag's weight counts for nothing.
- The load ratio picks the roll class (as Elden Ring's equip load): under 30% light (today's roll), under 70% medium (a little slower and shorter), under 100% heavy (slow, short, more stamina, longer recovery), over 100% no roll and slower walking. Stamina regen falls with the load. Every number in `data/tuning.tres`.
- The class follows from the worn item ids. Weapons are rolled back already (`main_hand`, `off_hand`, `ranged`); if the armor slots are not in the state, the class goes into `STATE` and a packed group as one byte with a `wire.gd` serializer, set by the server when gear changes. Never compute it from the bag.
- Starting kit: `Inventory.starting_kit()` (`sim/inventory.gd`) keeps sword, wooden shield, crossbow and 20 bolts worn, and adds spare pieces to the bag to try on: the leather helm, the chain chest, the iron shield and the bronze axe (`data/items/`). Only new characters get it; saved ones keep theirs.
- Weapon bar: beside the hotbar, set 1 (main and off hand icons) and set 2 (ranged), the active set lit, keys 1 and 2 on them; icons from `ItemIcons`.

## Tasks

1. **Equip load and roll classes (Opus).** `sim/sim_player.gd` (the roll by class, regen by load), `sim/inventory.gd` (equip load), `data/tuning.tres`, `net/wire.gd` if a field is added; `Net.PROTOCOL_VERSION`; tests in `tests/combat_test.gd` (each class rolls as specified, over 100% cannot roll, the bag does not count); the suite and the load test.
2. **Starting kit (Sonnet).** `sim/inventory.gd` `starting_kit`, `tests/save_test.gd` (a saved character does not get the spares again).
3. **Weapon bar and panel, close (Sonnet).** `client/hotbar.gd` or a new `client/weapon_bar.gd`, `client/hud.gd`, `client/inventory_panel.gd` (the weight line becomes "Equip load x / max" with the roll class); `BotBrain` knows the heavy roll is slower; play-test items; milestone closed.

## Out of scope

A second weapon set of any type (two-handed, bow): M47. A carry limit for the bag. Perks or levels raising the max (M57).

## Pitfalls

- The roll's length and speed are sim truth: a class change mid-roll must not change the roll in flight (read the class when the roll starts).
- Bots roll too: without knowing the heavy roll, the suite's dodge rates drop for the wrong reason.
- The weapon bar must not crowd the hotbar at 1280 by 720.
