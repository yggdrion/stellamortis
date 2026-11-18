extends GdUnitTestSuite
## The weapon bar (M42 task 3): worn main hand, off hand and crossbow with its bolts, the
## active set lit from SimPlayer.weapon, empty cells empty.


func _bar(inv: Inventory) -> WeaponBar:
	var bar := auto_free(WeaponBar.new()) as WeaponBar
	add_child(bar)
	bar.show_inventory(inv)
	return bar


func test_slots_follow_the_worn_gear() -> void:
	var inv := Inventory.starting_kit()
	var bar := _bar(inv)
	assert_str(bar.slots[0].stack.id).is_equal("sword")
	assert_str(bar.slots[1].stack.id).is_equal("shield_wood")
	assert_str(bar.slots[2].stack.id).is_equal("crossbow")
	assert_int(bar.slots[2].stack.count).is_equal(20)
	inv.cells[Inventory.Cell.OFF] = Inventory.Stack.new(&"shield_iron", 1)
	inv.cells[Inventory.Cell.RANGED] = null
	bar.show_inventory(inv)
	assert_str(bar.slots[1].stack.id).is_equal("shield_iron")
	assert_object(bar.slots[2].stack).is_null()


func test_active_set_is_lit() -> void:
	var bar := _bar(Inventory.starting_kit())
	bar.set_active(SimPlayer.Weapon.SWORD)
	assert_bool(bar.slots[0].cursor and bar.slots[1].cursor).is_true()
	assert_bool(bar.slots[2].cursor).is_false()
	bar.set_active(SimPlayer.Weapon.CROSSBOW)
	assert_bool(bar.slots[0].cursor or bar.slots[1].cursor).is_false()
	assert_bool(bar.slots[2].cursor).is_true()
