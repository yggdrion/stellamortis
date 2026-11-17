# M39 Generated gear

Status: Built (2026-11-17, v0.29.0), play-test pending.

## Goal

Every weapon, shield, helm and armor piece is built from the item's data in the game's own look, so each tier and set reads at a glance and new gear costs a data entry, not a model search. Item icons are rendered from the same meshes.

## Left by M38

`assets/quaternius/props/` holds only `Shield_Wooden`, `Axe_Bronze`, `Sword_Bronze` and the `T_Trim_*` textures. `Gear.SHIELD`, `Gear.AXE` and the `model =` of `sword`, `sword_runed`, `shield_wood`, `shield_iron` and `axe_bronze` (`data/items/`) read them. The last gear task deletes the folder and its `docs/RESOURCES.md` row.

## Depends on

M36 (kit, registry), M23 (items, worn gear, `InventoryPanel`). `docs/STYLE.md` §8. Independent of M38.

## Design

- An item's look is data: `ItemDef` gains `look` (a generator id: `sword`, `greatsword`, `axe`, `crossbow`, `round_shield`, `kite_shield`, `helm`, `cuirass`, `pauldrons`, `greaves`, `cape`, ...) and `look_params` (a small dictionary: lengths, widths, guard and pommel shapes, crest, horn count, material roles such as `steel` or `iron`, a wear amount). Tiers and sets differ by parameters and roles, not by code.
- Generators in `scripts/client/meshgen/kinds/gear/`. The shapes already built in `client/gear.gd` (steel sword, crossbow, the Warden's armor, helm, horns, crown, cape, pauldrons, greatsword) move there and onto `MeshKit`; `Gear` keeps deciding who wears what and asks `Generators`.
- Attachment stays `CharacterModel.show_prop` by bone name. Armor that covers a body part names it, so M40's bodies can hide what is below.
- Icons: `ItemIcons` (`scripts/client/item_icons.gd`) renders each item's mesh once in a small `SubViewport` at a fixed angle and light and caches the texture by item id; `InventoryPanel` and loot labels use it. Headless builds none.
- Enemy gear (rusted swords, the berserker's axes, shields of the shield bearers) uses the same generators with a high wear amount and the `rot` and dark roles.

## Tasks

1. **Weapon and shield generators (Sonnet).** Port `gear.gd`'s sword and crossbow, add axe, greatsword, shields; `ItemDef.look` and `look_params` on the existing items in `data/items/`; gallery screenshots of every item.
2. **Armor generators (Sonnet).** Helms, cuirass, pauldrons, greaves, capes for the player kit, the Warden and the barrow elite; the covered body parts named.
3. **Icons, enemies, close (Sonnet).** `ItemIcons`, the panel and loot views; enemy looks in `EnemyView`; remove the MegaKit shield and axe files and rows. `--inventory=1 --debug-bag` screenshots. Play-test items, milestone closed.

File level detail is added when M36 lands (and M38, if it comes first).

## Out of scope

Bodies, heads and hair (M40). New items, tiers or sets (M54, M55 add data; their gear then needs only parameters). Dropped items' world meshes beyond reusing the same generators.

## Pitfalls

- `AttackDef` reach and arcs are sim numbers. A longer generated blade must not suggest more reach than the attack has: derive the blade length parameter from the weapon's reach, or check it in a test.
- Equipped item ids are rolled back state; looks are not. A view must rebuild gear when the id changes, without assuming it changes once.
- Icon rendering on first open must not hitch the panel: render at load, a few per frame.
- Mirrored armor is exempt from the asymmetry rule, wear and dents are not (style sheet §6).
