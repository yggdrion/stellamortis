extends GdUnitTestSuite
## Equip load and the roll classes (M42 task 1): only worn cells weigh, the class follows the
## load against Tuning.equip_load_max, and every scale array has one entry per class.

const BURDEN := Loadout.Burden


func _worn(extra := {}) -> Inventory:
	var inventory := Inventory.starting_kit()
	for cell: int in extra:
		inventory.cells[cell] = Inventory.Stack.new(extra[cell], 1)
	return inventory


func _burden_at(load_value: float) -> int:
	return Loadout.burden_of(load_value, Tuning.data())


func test_equip_load_counts_only_worn_cells() -> void:
	var inventory := Inventory.starting_kit()
	assert_float(Loadout.equip_load(inventory)).is_equal_approx(9.0, 0.001)
	for cell in Inventory.BAG_SIZE:
		inventory.cells[cell] = Inventory.Stack.new(&"chest_chain", 1)
	assert_float(Loadout.equip_load(inventory)).is_equal_approx(9.0, 0.001)
	inventory.cells[Inventory.Cell.CHEST] = Inventory.Stack.new(&"chest_chain", 1)
	assert_float(Loadout.equip_load(inventory)).is_equal_approx(15.0, 0.001)
	inventory.cells[Inventory.Cell.BOLTS].count = 40
	assert_float(Loadout.equip_load(inventory)).is_equal_approx(16.0, 0.001)


func test_burden_class_boundaries() -> void:
	var max_load := Tuning.data().equip_load_max
	assert_int(_burden_at(0.0)).is_equal(BURDEN.LIGHT)
	assert_int(_burden_at(max_load * 0.399)).is_equal(BURDEN.LIGHT)
	assert_int(_burden_at(max_load * 0.4)).is_equal(BURDEN.MEDIUM)
	assert_int(_burden_at(max_load * 0.699)).is_equal(BURDEN.MEDIUM)
	assert_int(_burden_at(max_load * 0.7)).is_equal(BURDEN.HEAVY)
	assert_int(_burden_at(max_load * 0.999)).is_equal(BURDEN.HEAVY)
	assert_int(_burden_at(max_load)).is_equal(BURDEN.OVERLOADED)
	assert_int(_burden_at(max_load * 2.0)).is_equal(BURDEN.OVERLOADED)


func test_starting_kit_is_light_and_chain_plus_cap_is_medium() -> void:
	assert_int(Loadout.of(Inventory.starting_kit()).burden).is_equal(BURDEN.LIGHT)
	var medium := _worn(
		{Inventory.Cell.CHEST: &"chest_chain", Inventory.Cell.HELM: &"helm_leather"}
	)
	assert_float(Loadout.equip_load(medium)).is_equal_approx(16.0, 0.001)
	assert_int(Loadout.of(medium).burden).is_equal(BURDEN.MEDIUM)
	var heavy := _worn(
		{
			Inventory.Cell.CHEST: &"chest_chain",
			Inventory.Cell.HELM: &"helm_leather",
			Inventory.Cell.OFF: &"shield_iron",
			Inventory.Cell.MAIN: &"axe_bronze",
		}
	)
	assert_float(Loadout.equip_load(heavy)).is_equal_approx(18.5, 0.001)
	assert_int(Loadout.of(heavy).burden).is_equal(BURDEN.HEAVY)


func test_every_scale_array_has_a_light_one_and_four_entries() -> void:
	var t := Tuning.data()
	for scales: PackedFloat32Array in [
		t.roll_time_scale,
		t.roll_speed_scale,
		t.roll_stamina_scale,
		t.roll_iframe_scale,
		t.regen_scale,
		t.delay_scale,
		t.move_scale,
	]:
		assert_int(scales.size()).is_equal(4)
		assert_float(scales[BURDEN.LIGHT]).is_equal(1.0)
