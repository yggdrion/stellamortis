# M48 Rarity and rolled attributes

Status: Planned.

## Goal

Loot has a rarity: common, uncommon, rare, epic, legendary. Rarer items roll more and stronger attributes, glow in their color on the ground, and make every chest and elite worth opening.

## Depends on

M23 (items, loot, saves), M43 (attributes name damage types). Before M54 (perks and sets read the same attributes).

## Design

- An item instance is no longer only an id: it carries `rarity` and a short list of rolled attributes (`{stat, value}`), stored in the inventory cell, the character file and world objects. Equipped item ids stay the only item data in rolled back state; the server computes what the attributes do.
- `AttributeDef` (`data/attributes/`): stat (damage of a type, resistance, stamina cost, buildup, move speed, health, ...), value range per rarity, which item kinds can roll it. Rarity decides the count (0 to 4) and the range.
- Legendaries are named, hand-made items with one unique effect each, dropped by bosses and elites only.
- Loot tables (`data/loot/`) gain rarity weights per source: common from the dead, better from chests, elites and bosses; a party-size bonus stays out.
- View: rarity color on the drop's beam, the name, the slot border and the tooltip (compare view shows attribute differences); a sound per rarity; the color set is added to the palette's meaning colors and `docs/STYLE.md`.
- Old character and world files load: an item without rarity is common.

## Tasks

1. **Instances and rolls (Opus).** `sim/inventory.gd`, `sim/items.gd`, `sim/item_def.gd`, new `sim/attribute_def.gd`, `net/looting.gd`, `sim/save_file.gd` users, `net/net.gd` RPCs; `tests/inventory_test.gd`, `tests/save_test.gd`, new `tests/rarity_test.gd`; `Net.PROTOCOL_VERSION`.
2. **Effects of attributes (Opus).** One place sums worn attributes into what combat reads (becomes M54's `Stats` block); tests.
3. **Content and views (Sonnet).** Attribute data, loot weights, legendaries for the Barrowlands, drop beam, tooltip, sounds; suite expectations; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Rerolling and upgrading (M56). Trading between players beyond dropping. Set bonuses (M54).

## Pitfalls

- The server trusts the character file (§4.8): fine among friends, but validate ranges on load so a broken file cannot crash a fight.
- Stack rules: rolled items never stack.
- Meaning colors are reserved (§3.2): rarity colors must not collide with ember, gate blue and gold; legendary needs its own.
