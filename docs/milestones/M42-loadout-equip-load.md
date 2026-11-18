# M42 Loadout and equip load

Status: Planned (detailed 2026-11-18, after M41).

## Goal

A new character has spare gear in the bag to try on. The bag weighs nothing; only what is worn counts, and the equip load decides how fast stamina comes back and how the player rolls: light, medium, a heavy "fat" roll, or no roll at all. A bar shows weapon sets 1 and 2.

## Depends on

M23 (items, inventory, saves), M24 (the suite judges the roll change). Independent of M41 and M43.

## Design

- **Equip load:** the sum of `ItemDef.weight * stack.count` over the worn cells (`Inventory.Cell.MAIN` to `BOLTS`; the bolts count: 20 bolts weigh 1.0), against `Tuning.equip_load_max` (25.0; M57's `Stats` takes it over). The bag counts for nothing. Today's kit weighs 9.0 (sword 2, wooden shield 3, crossbow 3, bolts 1). The panel's "Weight" line (`InventoryPanel.show_inventory`) sums every cell including the bag: that is the line that changes.
- **Classes** (`Loadout.Burden { LIGHT, MEDIUM, HEAVY, OVERLOADED }`, not `Class`, which shadows a native name). Ratio = load / max. Under `load_light_ratio` 0.4 LIGHT (today's roll), under `load_medium_ratio` 0.7 MEDIUM, under 1.0 HEAVY, 1.0 and over OVERLOADED (no roll). Boundaries: ratio below the limit is the lower class, so exactly 40% is MEDIUM. The max is chosen so a new character reaches the three classes that roll with its own spares: the starting kit (9.0 of 25 = 36%) is LIGHT; the chain shirt (6.0) and leather cap (1.0) on top give 16.0 = 64%, MEDIUM; all four spares worn (bronze axe, iron shield, cap, chain: 18.5 = 74%) give HEAVY. OVERLOADED needs heavier finds (the heaviest full set today is 24.0 = 96%); tests set it directly. Heavier gear comes with M47.
- **Numbers** are `data/tuning.tres` (`sim/tuning.gd`). Existing `roll_time`, `roll_speed`, `roll_stamina`, `roll_iframes_*`, `stamina_regen`, `stamina_delay`, `walk_speed`, `sprint_speed` stay the LIGHT values (so every current test and the bots read the same numbers). New `@export var ... := PackedFloat32Array([1.0, ...])`, one entry per `Burden`, scale factors on those:
  - `roll_time_scale` [1.0, 1.15, 1.4, 1.0], `roll_speed_scale` [1.0, 0.9, 0.7, 1.0], `roll_stamina_scale` [1.0, 1.2, 1.6, 1.0], `roll_iframe_scale` [1.0, 0.9, 0.7, 1.0] (applied to the start and end times), `regen_scale` [1.0, 0.85, 0.6, 0.4], `delay_scale` [1.0, 1.0, 1.4, 1.6] (on `stamina_delay`: the longer recovery), `move_scale` [1.0, 0.95, 0.9, 0.75] (on walk and sprint speed). The OVERLOADED roll entries are never used. All are first guesses for the play-test. Also `equip_load_max`, `load_light_ratio`, `load_medium_ratio`.
  - Read them only through the static helpers on `SimPlayer` (task 1), so no call site indexes an array by hand.
- **Where the class lives: rolled back, server-set, one byte.** `SimPlayer.armor` is only the sum of the worn pieces' defense (`Loadout.of`), so the weight cannot be recovered from the state; and the worn item ids of the armor slots are not in the state at all (only `main_hand`, `off_hand`, `ranged`, `armor`). So add one field `burden` (u8, the `Burden` value) to `SimPlayer`, set by the server exactly like `armor`: `Loadout.of(inventory)` computes it, `Inventories._loadout_ints` returns it as a fifth int, `Inventories._apply_gear` writes it after every rollback step. It joins `STATE`, `GEAR` and the `COMBAT` group, with `"burden": u8` in `Wire`. Never derive it from the bag or from `armor`.
- **The roll in flight does not change.** `burden` can change mid-roll (a gear swap by `Net.Op.USE`/`EQUIP` is applied at the next tick). So a second rolled back u8, `roll_burden`, is copied from `burden` in `_advance_action` when the roll starts, and everything about the roll (length, travel, speed, i-frames, the view's pose) reads `roll_burden`. Regen, walking and sprint speed read `burden` live. Two bytes added to `COMBAT`; `tests/wire_test.gd` keeps the 508 byte rule.
- **No roll when OVERLOADED:** `_buffer` does not queue `Queued.ROLL`, and `_advance_action` checks `burden != OVERLOADED` as well (a queued roll from before a gear change must not start). The player keeps `Queued.NOTHING` instead of a stuck ROLL that blocks the attack branches.
- **Protocol:** `Net.PROTOCOL_VERSION` 34 to 35 (rolled back state and `Tuning` change). No change to the character file (`CharacterSave` keeps inventory only) or the world file; no new RPC. The class is not saved.
- **Starting kit:** `Inventory.starting_kit()` stays the worn kit only: `test_starting_kit_is_worn_and_the_bag_empty`, the save, loot and panel tests and `Inventories.add_peer`'s default depend on an empty bag. A new `Inventory.new_character_kit()` is `starting_kit()` plus `add()` of four spares: `helm_leather` (Leather Cap, 1.0), `chest_chain` (Chain Shirt, 6.0), `shield_iron` (Iron Shield, 5.0), `axe_bronze` (Bronze Axe, 2.5). All four exist in `data/items/`, with look and icon. They land in bag cells 0 to 3, so they sit on the hotbar and keys 3 to 6 wear them (`Net.Op.USE`). `GameServer` line `var inventory := Inventory.starting_kit()` in the join path (the one followed by `if character.get("inventory") is Dictionary`) becomes `new_character_kit()`; `_debug_inventory` keeps `starting_kit()` (it adds its own spares). A saved character always has an `inventory` dictionary, so it never gets the spares again; a broken file that reads as not-a-dictionary does (it starts as a new character).
- **Weapon bar:** `WeaponBar` (`client/weapon_bar.gd`, an `HBoxContainer` of `ItemSlot`s with mouse ignored, like `Hotbar`): set 1 = `Cell.MAIN` and `Cell.OFF`, set 2 = `Cell.RANGED` (with the bolt count from `Cell.BOLTS` as its stack count shown on the slot), a key hint "1" and "2", the active set lit through `ItemSlot.mark(true, false)`. "Set 1/2" in the sim are `SimPlayer.Weapon.SWORD`/`CROSSBOW` (keys 1, 2, wheel; `GameClient._wanted_weapon`), not a new concept. It replaces the HUD's `_weapon` text label (`"1  SWORD · SHIELD"`). Icons come from `ItemSlot` through `ItemIcons.texture`.

## Tasks

### 1. Equip load and roll classes (Opus)

Files and changes:

- `scripts/sim/tuning.gd`, `data/tuning.tres`: the exports above.
- `scripts/sim/loadout.gd`: `enum Burden { LIGHT, MEDIUM, HEAVY, OVERLOADED }`; `var burden := 0` (an int, like the other fields, so it packs); `static func equip_load(inventory: Inventory) -> float` (cells `Cell.MAIN` to `Cell.BOLTS`, `Items.def(...).weight * count`); `static func burden_of(load: float, t: Tuning) -> int`; `Loadout.of` sets `burden`. Reuse `_worn`, `Items.def`.
- `scripts/sim/sim_player.gd`:
  - fields `burden`, `roll_burden` in `STATE`, `COMBAT`; `burden` in `GEAR`; both default 0 (so tests that call `step` directly are LIGHT).
  - static helpers next to `roll_travel_ticks`: `roll_ticks(t, cls := 0)`, `roll_travel_ticks(t, cls := 0)` (existing signature kept), `roll_speed_of(t, cls)`, `roll_stamina_of(t, cls)`, `iframe_scale_of(t, cls)`, `iframe_ticks(t, cls) -> Vector2i` (start, end), `delay_ticks(t, cls)`, `move_scale_of(t, cls)`; all index through one private `_scale` that clamps. `dodging()` uses `roll_burden`.
  - `_keep_acting` `Action.ROLL`: `busy = action_time < roll_ticks(t, roll_burden)`. `step`: the ROLL branch uses `roll_speed_of`, `roll_travel_ticks(t, roll_burden)`; the walk and sprint lines multiply by `t.move_scale[burden]`. `_count_down` multiplies `stamina_regen` by `regen_scale[burden]`; `_spend` and the block's stamina wait in `_defend` use `delay_ticks(t, burden)`. `_advance_action`: the roll start sets `roll_burden = burden`, spends `roll_stamina_of(t, burden)`. `_buffer`: no ROLL queue when overloaded. `_respawn`/`_use_portal` keep `burden` (it is gear, not life).
- `scripts/net/wire.gd`: `"burden": u8`, `"roll_burden": u8` in `_fill()`.
- `scripts/net/inventories.gd`: `_loadout_ints` returns five ints, the comment on `_gear` and `_apply_gear` compare and write the fifth. Fix the doc comment "[main_hand, off_hand, ranged, armor]".
- `scripts/net/net.gd`: `PROTOCOL_VERSION := 35`.
- `scripts/client/player_view.gd` `_pose`: the roll branch uses `SimPlayer.roll_ticks(t, player.roll_burden)` and `t.roll_time * t.roll_time_scale[...]` where it uses `t.roll_time` (lines ~226 to 244), so a slow roll plays its clip slower; `_locomotion` speed ratios divide by the scaled walk speed (the jog/sprint clip choice at line ~284 compares to `walk_speed`/`sprint_speed`; scale both by `move_scale[player.burden]`).
- `scripts/client/bot/bot_brain.gd`: `roll_at` (line ~242) multiplies the window's seconds by `SimPlayer.iframe_scale_of(t, burden)` (not `iframe_ticks`: the tick center is 0.2333 s against 0.23 s and would move the LIGHT numbers); `_plan` takes `burden` as a fourth argument; if `view.burden == OVERLOADED` the evade choice never picks ROLL (falls to PARRY/BLOCK). `Seen` gets `burden` (copied where `seen.stamina = me.stamina`). Bots wear the starting kit (LIGHT), so numbers do not move; this keeps the suite honest once a bot is heavy.

Steps: 1 tuning, loadout, tests for `Loadout` alone; 2 sim_player and wire; 3 inventories and protocol; 4 view and bot.

Tests (`tests/loadout_test.gd` for the pure ones, `tests/burden_test.gd` for the sim ones, `tests/gear_test.gd` for the Inventories one, `tests/wire_test.gd`; the sim ones are not in `combat_test.gd`, which is at gdlint's 20 public methods):

- `test_equip_load_counts_only_worn_cells`: a bag full of `chest_chain` adds nothing; wearing it adds 6.0; the bolts add 0.05 each.
- `test_burden_class_boundaries`: exactly 40% is MEDIUM, 69.9% MEDIUM, 70% HEAVY, 100% OVERLOADED.
- `test_starting_kit_is_light_and_chain_plus_cap_is_medium` (and all four spares worn are HEAVY).
- `test_each_burden_rolls_as_tuned` (burden_test): set `_player.burden` to each class, roll, and check the roll's length in ticks, the distance covered, the stamina spent and the i-frame window against the scaled tuning.
- `test_overloaded_cannot_roll_and_attacks_still_start`: a ROLL press does nothing and the next LIGHT press attacks.
- `test_burden_change_mid_roll_keeps_the_roll`: start a light roll, set `burden = HEAVY`, the roll ends at the light length and covers the light distance.
- `test_regen_and_delay_fall_with_burden`: stamina after N ticks per class.
- `test_walk_speed_scales_with_burden`.
- `wire_test`: the two new fields round trip and a full state fits 508 bytes.
- Gear: `test_inventories_write_burden_to_the_player` (gear_test): equipping the chain shirt through `Inventories.apply(peer, Net.Op.EQUIP, cell, 0)` and one `_apply_gear` call sets `player.burden` MEDIUM; a resimulated tick keeps it.

Done when: checks green; `python tools/playtest.py --suite` against the baselines in `docs/PLAN.md` §8 (all bots LIGHT: no number should move; if one does, the class leaked into LIGHT); `python tools/run_load_test.py` still 29 tps with 6 bots, numbers in the commit message (the state grew by 2 bytes per player); desync check clean (`tools/desync.py`).

### 2. Starting kit (Sonnet)

Files: `scripts/sim/inventory.gd` (`new_character_kit`), `scripts/net/game_server.gd` (the join path), `tests/inventory_test.gd`, `tests/save_test.gd`.

Reuse: `Inventory.starting_kit()`, `Inventory.add`, `GameServer._debug_inventory` (stays as is).

Tests: `test_new_character_kit_wears_the_old_kit_and_bags_four_spares` (ids `helm_leather`, `chest_chain`, `shield_iron`, `axe_bronze` in bag cells 0 to 3, worn cells as `starting_kit`); `test_a_saved_character_does_not_get_the_spares_again` (a join with `character = {"inventory": starting_kit().to_dict()}` keeps an empty bag; a join with `{}` gets the spares); the existing `test_starting_kit_is_worn_and_the_bag_empty` stays green; wearing each spare with `equip` moves the worn piece to the bag.

Done when: checks green; a fresh solo start shows the four items on the hotbar (screenshot `--seed=1234 --delay=6 --screenshot=PATH`, no `--debug-bag`).

### 3. Weapon bar and panel, close (Sonnet)

Files: new `scripts/client/weapon_bar.gd`; `scripts/client/hud.gd` (add the bar beside `hotbar`, remove the `_weapon` label and its `1 / 2 / wheel weapon` text stays in the help line; `update` line ~189 lights the active set from `player.weapon`; a `show_inventory` hook like `hotbar.show_inventory`); `scripts/client/game_client.gd` `_show_inventory` (also calls `_hud.weapon_bar.show_inventory(inventory)`); `scripts/client/inventory_panel.gd` `show_inventory` (the `Weight` line becomes `Equip load 16.0 / 40  Medium roll`, computed from the gear cells only through `Loadout.equip_load(inventory)` and `Loadout.burden_of`; color it with the class, red for no roll); `scripts/client/item_tooltip.gd` (it already shows weight; add the load the item adds if worn, `+x.x`, optional); `docs/PLAYTEST.md`; `CLAUDE.md` "Where we are"; `docs/PLAN.md` §6 and §8; `VERSION` minor +1.

Layout: the bar sits left of the hotbar on the same baseline (hotbar is 8 slots of 44 px plus gaps, about 380 px, bottom centre, 16 px up). At 1280 by 720 the bar must not overlap the hotbar, the health and stamina bars or the prompt line; check with `--screenshot` at that window size and at 1920 by 1080.

Tests: `tests/inventory_panel_test.gd` gets `test_weight_line_shows_equip_load_and_class` (starting kit: "9.0 / 25", Light; with the chain shirt worn: Medium; a full bag changes nothing); a `tests/weapon_bar_test.gd` (the bar shows the worn main hand, off hand and crossbow icons' slots, lights set 2 when `player.weapon` is CROSSBOW, an empty cell shows an empty slot).

Play-test items to add to `docs/PLAYTEST.md` under "M42 Loadout and equip load":

- [ ] A new character has the cap, chain shirt, iron shield and bronze axe on the hotbar (cells 0 to 3); keys 3 to 6 wear them; a saved character does not get them again.
- [ ] The inventory shows equip load against the max with the roll class; the bag does not change it.
- [ ] Wearing the chain shirt and cap makes the roll a little slower and shorter and stamina comes back slower; it should be noticeable but not punishing.
- [ ] The heavy and no-roll classes: lower `equip_load_max` in `data/tuning.tres` (try 20, then 10) to reach them; the heavy roll is slow with long recovery; over the max the roll key does nothing and walking is slower.
- [ ] The weapon bar shows the sword and shield for 1 and the crossbow with bolts for 2, the active set lit, and does not crowd the hotbar at 1280 by 720.
- [ ] A gear swap in the middle of a roll does not change that roll.

Done when: checks green, screenshots of the bar and the panel attached to the task, play-test items written, milestone status "Built (date, release), play-test pending" in this file and in `docs/PLAN.md` §6, `CLAUDE.md` "Where we are" updated (move M42 to built, Next becomes M43).

## Out of scope

A second weapon set of any type (two-handed, bow): M47. A carry limit for the bag. Perks or levels raising the max (M57). Showing worn armor on the model (open since M40; the burden byte is not item ids). Saving the class (it is derived from the inventory at join).

## Pitfalls

- The roll's length and speed are sim truth: a class change mid-roll must not change the roll in flight (`roll_burden`, read when the roll starts).
- `burden` is server-set outside the rollback tick, like `armor`: a resimulation restores older state and the next `_apply_gear` writes it again. Do not compute it inside `_rollback_tick`.
- `PackedFloat32Array` exports in `Tuning` index by the enum value: an array shorter than 4 reads out of range. A test checks every scale array has four entries and LIGHT is 1.0.
- Bots roll too: without knowing the heavy roll, the suite's dodge rates drop for the wrong reason. All bots wear the starting kit (LIGHT), so the suite must not move; the new characters' spare gear sits in the bag and weighs nothing.
- `Inventory.starting_kit()` is used by many tests with an empty bag; the spares are a separate `new_character_kit()`.
- `armor` (defense total) and `burden` are different things: a light leather cap and a heavy plate can have the same defense.
- The weapon bar must not crowd the hotbar at 1280 by 720.
