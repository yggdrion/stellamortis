extends GdUnitTestSuite
## Inventory (M23): every operation on plain data, hostile input, serialization.

const C := Inventory.Cell


func _bag(id: StringName, count: int) -> Inventory.Stack:
	return Inventory.Stack.new(id, count)


func test_items_ids_are_unique_and_every_file_loads() -> void:
	assert_str(String(Items.IDS[0])).is_empty()
	var seen := {}
	for i in range(1, Items.IDS.size()):
		var id := Items.IDS[i]
		assert_bool(seen.has(id)).override_failure_message("duplicate %s" % id).is_false()
		seen[id] = true
		var def := Items.def(i)
		assert_object(def).override_failure_message("no file for %s" % id).is_not_null()
		assert_str(String(def.id)).is_equal(String(id))
		assert_int(Items.index(id)).is_equal(i)
	assert_int(Items.index(&"nothing_like_it")).is_equal(0)
	assert_object(Items.def(999)).is_null()
	assert_object(Items.def(-3)).is_null()


func test_starting_kit_is_worn_and_the_bag_empty() -> void:
	var inv := Inventory.starting_kit()
	assert_str(String(inv.at(C.MAIN).id)).is_equal("sword")
	assert_str(String(inv.at(C.OFF).id)).is_equal("shield_wood")
	assert_str(String(inv.at(C.RANGED).id)).is_equal("crossbow")
	assert_int(inv.at(C.BOLTS).count).is_equal(20)
	for cell in Inventory.BAG_SIZE:
		assert_object(inv.at(cell)).is_null()


func test_add_stacks_first_then_empty_cells_and_reports_leftover() -> void:
	var inv := Inventory.new()
	assert_int(inv.add(&"hide", 30)).is_equal(0)
	assert_int(inv.add(&"hide", 40)).is_equal(0)
	assert_int(inv.at(0).count).is_equal(50)
	assert_int(inv.at(1).count).is_equal(20)
	assert_int(inv.count_of(&"hide")).is_equal(70)
	# Fill the bag to the brim: 32 cells of 50, 70 already in.
	assert_int(inv.add(&"hide", 1600)).is_equal(70)
	assert_int(inv.count_of(&"hide")).is_equal(32 * 50)
	assert_int(inv.add(&"bone", 5)).is_equal(5)
	assert_int(inv.add(&"nothing_like_it", 3)).is_equal(3)
	assert_int(inv.add(&"hide", 0)).is_equal(0)
	assert_int(inv.add(&"hide", -4)).is_equal(0)


func test_move_empty_merge_swap_and_refusals() -> void:
	var inv := Inventory.new()
	inv.cells[0] = _bag(&"hide", 40)
	inv.cells[1] = _bag(&"hide", 20)
	inv.cells[2] = _bag(&"bone", 3)
	assert_bool(inv.move(0, 5)).is_true()
	assert_object(inv.at(0)).is_null()
	assert_int(inv.at(5).count).is_equal(40)
	# Merge: 40 + 20 into a stack of 50.
	assert_bool(inv.move(1, 5)).is_true()
	assert_int(inv.at(5).count).is_equal(50)
	assert_int(inv.at(1).count).is_equal(10)
	# A full stack and the same id: nothing to do.
	inv.cells[6] = _bag(&"hide", 50)
	assert_bool(inv.move(1, 6)).is_false()
	# Swap in the bag.
	assert_bool(inv.move(2, 5)).is_true()
	assert_str(String(inv.at(5).id)).is_equal("bone")
	assert_str(String(inv.at(2).id)).is_equal("hide")
	# Empty source, same cell, out of range.
	assert_bool(inv.move(10, 11)).is_false()
	assert_bool(inv.move(5, 5)).is_false()
	assert_bool(inv.move(-1, 5)).is_false()
	assert_bool(inv.move(5, 42)).is_false()
	assert_bool(inv.move(5, 100000)).is_false()


func test_gear_cells_only_take_their_item() -> void:
	var inv := Inventory.new()
	inv.cells[0] = _bag(&"sword", 1)
	inv.cells[1] = _bag(&"helm_leather", 1)
	inv.cells[2] = _bag(&"hide", 5)
	assert_bool(inv.move(0, C.OFF)).is_false()
	assert_bool(inv.move(1, C.MAIN)).is_false()
	assert_bool(inv.move(2, C.HELM)).is_false()
	assert_bool(inv.move(0, C.MAIN)).is_true()
	assert_bool(inv.move(1, C.HELM)).is_true()
	# A swap needs the other stack to fit the source cell: a helm into the bag is fine, a bag
	# item that does not fit the gear cell it would take is not.
	inv.cells[3] = _bag(&"axe_bronze", 1)
	assert_bool(inv.move(C.MAIN, 3)).is_true()
	assert_str(String(inv.at(C.MAIN).id)).is_equal("axe_bronze")
	assert_str(String(inv.at(3).id)).is_equal("sword")
	inv.cells[4] = _bag(&"hide", 1)
	assert_bool(inv.move(4, C.MAIN)).is_false()


func test_equip_swaps_with_the_worn_item_and_refuses_what_cannot_be_worn() -> void:
	var inv := Inventory.starting_kit()
	inv.cells[7] = _bag(&"sword_runed", 1)
	assert_bool(inv.equip(7)).is_true()
	assert_str(String(inv.at(C.MAIN).id)).is_equal("sword_runed")
	assert_str(String(inv.at(7).id)).is_equal("sword")
	# A material, an empty cell, a worn cell, out of range.
	inv.cells[8] = _bag(&"hide", 3)
	assert_bool(inv.equip(8)).is_false()
	assert_bool(inv.equip(9)).is_false()
	assert_bool(inv.equip(C.MAIN)).is_false()
	assert_bool(inv.equip(77)).is_false()
	assert_bool(inv.equip(-1)).is_false()
	assert_int(inv.at(8).count).is_equal(3)


func test_two_trinkets_fill_both_cells_then_replace_the_first() -> void:
	var inv := Inventory.new()
	inv.cells[0] = _bag(&"ring_ember", 1)
	inv.cells[1] = _bag(&"charm_bone", 1)
	inv.cells[2] = _bag(&"charm_bone", 1)
	assert_bool(inv.equip(0)).is_true()
	assert_bool(inv.equip(1)).is_true()
	assert_str(String(inv.at(C.TRINKET_A).id)).is_equal("ring_ember")
	assert_str(String(inv.at(C.TRINKET_B).id)).is_equal("charm_bone")
	# Both cells full: the first one is replaced and its item goes back to the bag.
	assert_bool(inv.equip(2)).is_true()
	assert_str(String(inv.at(C.TRINKET_A).id)).is_equal("charm_bone")
	assert_str(String(inv.at(2).id)).is_equal("ring_ember")
	assert_int(inv.count_of(&"ring_ember")).is_equal(1)


func test_unequip_goes_to_the_bag_and_fails_when_it_is_full() -> void:
	var inv := Inventory.starting_kit()
	assert_bool(inv.unequip(C.OFF)).is_true()
	assert_object(inv.at(C.OFF)).is_null()
	assert_str(String(inv.at(0).id)).is_equal("shield_wood")
	assert_bool(inv.unequip(C.OFF)).is_false()
	assert_bool(inv.unequip(3)).is_false()
	for cell in Inventory.BAG_SIZE:
		inv.cells[cell] = _bag(&"hide", 50)
	assert_bool(inv.unequip(C.MAIN)).is_false()
	assert_str(String(inv.at(C.MAIN).id)).is_equal("sword")


func test_unequipped_bolts_merge_into_a_bag_stack() -> void:
	var inv := Inventory.starting_kit()
	inv.cells[0] = _bag(&"bolt", 50)
	assert_bool(inv.unequip(C.BOLTS)).is_true()
	assert_int(inv.at(0).count).is_equal(60)
	assert_int(inv.at(1).count).is_equal(10)
	assert_object(inv.at(C.BOLTS)).is_null()


func test_split_takes_part_into_the_first_empty_cell() -> void:
	var inv := Inventory.new()
	inv.cells[0] = _bag(&"hide", 10)
	assert_bool(inv.split(0, 4)).is_true()
	assert_int(inv.at(0).count).is_equal(6)
	assert_int(inv.at(1).count).is_equal(4)
	# 0, more than held, all of it, empty cell, out of range.
	assert_bool(inv.split(0, 0)).is_false()
	assert_bool(inv.split(0, -2)).is_false()
	assert_bool(inv.split(0, 7)).is_false()
	assert_bool(inv.split(0, 6)).is_false()
	assert_bool(inv.split(9, 1)).is_false()
	assert_bool(inv.split(99, 1)).is_false()
	assert_int(inv.count_of(&"hide")).is_equal(10)
	for cell in Inventory.BAG_SIZE:
		if inv.cells[cell] == null:
			inv.cells[cell] = _bag(&"bone", 1)
	assert_bool(inv.split(0, 1)).is_false()


func test_drop_returns_what_it_removed() -> void:
	var inv := Inventory.new()
	inv.cells[0] = _bag(&"hide", 10)
	var part := inv.drop(0, 3)
	assert_int(part.count).is_equal(3)
	assert_int(inv.at(0).count).is_equal(7)
	assert_object(inv.drop(0, 8)).is_null()
	assert_object(inv.drop(0, 0)).is_null()
	assert_object(inv.drop(5, 1)).is_null()
	assert_object(inv.drop(500, 1)).is_null()
	var rest := inv.drop(0, 7)
	assert_int(rest.count).is_equal(7)
	assert_object(inv.at(0)).is_null()


func test_sort_orders_by_kind_rarity_and_id_and_merges() -> void:
	var inv := Inventory.new()
	inv.cells[0] = _bag(&"hide", 30)
	inv.cells[3] = _bag(&"axe_bronze", 1)
	inv.cells[4] = _bag(&"hide", 40)
	inv.cells[9] = _bag(&"sword_runed", 1)
	inv.cells[10] = _bag(&"bandage", 2)
	inv.cells[11] = _bag(&"bone", 4)
	inv.cells[12] = _bag(&"sword", 1)
	assert_bool(inv.sort()).is_true()
	var order: Array[String] = []
	for cell in Inventory.BAG_SIZE:
		if inv.cells[cell] != null:
			order.append("%s:%d" % [inv.cells[cell].id, inv.cells[cell].count])
	# Weapons (rarity high first), then materials by id (full stack first), then consumables.
	(
		assert_array(order)
		. is_equal(
			[
				"sword_runed:1",
				"axe_bronze:1",
				"sword:1",
				"bone:4",
				"hide:50",
				"hide:20",
				"bandage:2",
			]
		)
	)
	# Sorting a sorted bag changes nothing and is stable.
	assert_bool(inv.sort()).is_false()
	assert_int(inv.count_of(&"hide")).is_equal(70)


func test_store_matching_moves_only_what_the_other_holds() -> void:
	var chest := Inventory.new()
	chest.cells[0] = _bag(&"hide", 49)
	chest.cells[1] = _bag(&"bone", 1)
	var inv := Inventory.new()
	inv.cells[0] = _bag(&"hide", 5)
	inv.cells[1] = _bag(&"ember", 2)
	inv.cells[2] = _bag(&"bone", 4)
	inv.cells[C.MAIN] = _bag(&"sword", 1)
	assert_bool(inv.store_matching(chest)).is_true()
	assert_int(chest.count_of(&"hide")).is_equal(54)
	assert_int(chest.count_of(&"bone")).is_equal(5)
	assert_int(chest.count_of(&"ember")).is_equal(0)
	assert_int(inv.count_of(&"hide")).is_equal(0)
	assert_int(inv.count_of(&"ember")).is_equal(2)
	assert_object(inv.at(C.MAIN)).is_not_null()
	assert_bool(inv.store_matching(chest)).is_false()


func test_a_full_chest_keeps_the_rest() -> void:
	var chest := Inventory.new()
	for cell in Inventory.BAG_SIZE:
		chest.cells[cell] = _bag(&"hide", 50)
	var inv := Inventory.new()
	inv.cells[0] = _bag(&"hide", 5)
	assert_bool(inv.store_matching(chest)).is_false()
	assert_int(inv.at(0).count).is_equal(5)


func test_dict_round_trip_through_json_text() -> void:
	var inv := Inventory.starting_kit()
	inv.cells[4] = _bag(&"hide", 12)
	inv.cells[C.TRINKET_B] = _bag(&"ring_ember", 1)
	var text := JSON.stringify(inv.to_dict())
	var back := Inventory.from_dict(JSON.parse_string(text))
	assert_bool(back.same_as(inv)).is_true()
	# The deltas too: apply what changed onto a copy.
	var copy := Inventory.from_dict(inv.cell_dict())
	var old := inv.cell_dict()
	inv.move(4, 9)
	inv.unequip(C.OFF)
	copy.apply_cells(inv.changes_since(old))
	assert_bool(copy.same_as(inv)).is_true()


func test_from_dict_survives_hostile_data() -> void:
	var hostile := {
		"0": {"id": "hide", "count": 1000000000},
		"1": {"id": "hide", "count": -5},
		"2": {"id": "hide", "count": 0},
		"3": {"id": "unobtainium", "count": 3},
		"4": {"id": "bone", "count": 2.0e30},
		"5": {"id": "bone", "count": "many"},
		"6": {"id": 7, "count": 1},
		"7": "sword",
		"8": null,
		"-1": {"id": "hide", "count": 1},
		"42": {"id": "hide", "count": 1},
		"500": {"id": "hide", "count": 1},
		"x": {"id": "hide", "count": 1},
		"32": {"id": "hide", "count": 1},
		"33": {"id": "shield_iron", "count": 9},
		"9": {"id": "ember", "count": 7.9},
		3.5: {"id": "hide", "count": 1},
	}
	for i in 500:
		hostile[str(100 + i)] = {"id": "hide", "count": 1}
	var inv := Inventory.from_dict(hostile)
	assert_int(inv.at(0).count).is_equal(50)
	assert_object(inv.at(1)).is_null()
	assert_object(inv.at(2)).is_null()
	assert_object(inv.at(3)).is_null()
	assert_int(inv.at(4).count).is_equal(50)
	assert_object(inv.at(5)).is_null()
	assert_object(inv.at(6)).is_null()
	assert_object(inv.at(7)).is_null()
	# A hide in the main hand cell is not allowed there; the iron shield in the off hand is.
	assert_object(inv.at(C.MAIN)).is_null()
	assert_int(inv.at(C.OFF).count).is_equal(1)
	assert_int(inv.at(9).count).is_equal(7)
	assert_int(inv.cells.size()).is_equal(Inventory.CELLS)
	for not_a_dict: Variant in [null, 5, "x", [1, 2], 2.5]:
		assert_int(Inventory.from_dict(not_a_dict).cell_dict().size()).is_equal(0)
	var target := Inventory.new()
	target.apply_cells(hostile)
	assert_int(target.at(0).count).is_equal(50)
