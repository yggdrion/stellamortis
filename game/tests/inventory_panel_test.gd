extends GdUnitTestSuite
## The inventory panel and hotbar (M23 task 3): cells show the stacks, every action emits one
## intent (the panel never changes the inventory itself), keys map to actions, the compare
## tooltip numbers, junk marking and sorting, and the server side of USE (a bandage heals).

var _intents: Array = []
var _file := PackedByteArray()
var _had_file := false
var _junk: Array[StringName] = []


func before_test() -> void:
	Controls.setup()
	_intents.clear()
	_junk = Settings.junk.duplicate()
	Settings.junk.clear()
	_had_file = FileAccess.file_exists(Graphics.SETTINGS)
	if _had_file:
		_file = FileAccess.get_file_as_bytes(Graphics.SETTINGS)


func after_test() -> void:
	Settings.junk = _junk
	if _had_file:
		var f := FileAccess.open(Graphics.SETTINGS, FileAccess.WRITE)
		f.store_buffer(_file)
	else:
		DirAccess.remove_absolute(Graphics.SETTINGS)


func _panel() -> InventoryPanel:
	var inv := Inventory.starting_kit()
	inv.cells[0] = Inventory.Stack.new(&"bandage", 6)
	inv.cells[1] = Inventory.Stack.new(&"sword_runed", 1)
	inv.cells[2] = Inventory.Stack.new(&"hide", 10)
	inv.cells[3] = Inventory.Stack.new(&"iron_scrap", 1)
	var panel := auto_free(InventoryPanel.new()) as InventoryPanel
	panel.persist = false
	add_child(panel)
	panel.intent_sent.connect(func(op: int, a: int, b: int) -> void: _intents.append([op, a, b]))
	panel.show_inventory(inv)
	return panel


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func test_cells_show_the_stacks_and_the_worn_kit() -> void:
	var panel := _panel()
	assert_str(panel._slots[0].stack.id).is_equal("bandage")
	assert_int(panel._slots[0].stack.count).is_equal(6)
	assert_object(panel._slots[4].stack).is_null()
	assert_str(panel._slots[Inventory.Cell.MAIN].stack.id).is_equal("sword")
	assert_int(panel._slots[Inventory.Cell.BOLTS].stack.count).is_equal(20)
	assert_object(panel._slots[Inventory.Cell.HELM].stack).is_null()
	assert_int(panel._slots.size()).is_equal(Inventory.CELLS)
	var total := 0.0
	for cell in Inventory.CELLS:
		var stack := panel.inventory.at(cell)
		if stack != null:
			total += Items.by_id(stack.id).weight * stack.count
	assert_str(panel._weight.text).is_equal("Weight  %.1f" % total)


func test_a_drag_emits_one_move_and_never_touches_the_inventory() -> void:
	var panel := _panel()
	var before := panel.inventory.cell_dict()
	var main: ItemSlot = panel._slots[Inventory.Cell.MAIN]
	assert_bool(main._can_drop_data(Vector2.ZERO, {"cell": 1})).is_true()
	# A material cannot go on a gear slot; an empty source or the same cell is nothing.
	assert_bool(main._can_drop_data(Vector2.ZERO, {"cell": 2})).is_false()
	assert_bool(main._can_drop_data(Vector2.ZERO, {"cell": 20})).is_false()
	assert_bool(main._can_drop_data(Vector2.ZERO, {"cell": Inventory.Cell.MAIN})).is_false()
	assert_bool(main._can_drop_data(Vector2.ZERO, "junk")).is_false()
	main._drop_data(Vector2.ZERO, {"cell": 1})
	panel.move(2, Inventory.Cell.MAIN)
	assert_array(_intents).is_equal([[Net.Op.MOVE, 1, Inventory.Cell.MAIN]])
	assert_dict(panel.inventory.cell_dict()).is_equal(before)
	assert_object(panel._slots[10]._get_drag_data(Vector2.ZERO)).is_null()


func test_activate_equips_unequips_or_uses() -> void:
	var panel := _panel()
	panel.activate(1)
	panel.activate(Inventory.Cell.OFF)
	panel.activate(0)
	panel.activate(2)
	panel.activate(9)
	(
		assert_array(_intents)
		. is_equal(
			[
				[Net.Op.EQUIP, 1, 0],
				[Net.Op.UNEQUIP, Inventory.Cell.OFF, 0],
				[Net.Op.USE, 0, 0],
			]
		)
	)


func test_split_drop_and_sort() -> void:
	var panel := _panel()
	panel.split_half(2)
	panel.split_half(3)
	panel.drop(2)
	panel.drop(9)
	panel.sort()
	Settings.junk.append(&"hide")
	panel.sort()
	(
		assert_array(_intents)
		. is_equal(
			[
				[Net.Op.SPLIT, 2, 5],
				[Net.Op.DROP, 2, 10],
				[Net.Op.SORT, 0, 0],
				[Net.Op.SORT, 1 << Items.index(&"hide"), 0],
			]
		)
	)


func test_keys_map_to_actions() -> void:
	var panel := _panel()
	var expected := {
		KEY_R: &"inv_sort",
		KEY_X: &"inv_drop",
		KEY_V: &"inv_split",
		KEY_F: &"inv_junk",
		KEY_ENTER: &"inv_grab",
		KEY_E: &"interact",
		KEY_LEFT: &"ui_left",
		KEY_DOWN: &"ui_down",
	}
	for code: Key in expected:
		assert_str(String(panel.action_for(_key(code)))).is_equal(String(expected[code]))
	assert_str(panel.action_for(_key(KEY_Z))).is_equal("")
	assert_int(Hotbar.cell_for(_key(KEY_3))).is_equal(0)
	assert_int(Hotbar.cell_for(_key(KEY_8))).is_equal(5)
	assert_int(Hotbar.cell_for(_key(KEY_1))).is_equal(-1)
	assert_int(Hotbar.cell_for(_key(KEY_2))).is_equal(-1)


func test_every_action_works_from_the_keyboard() -> void:
	var panel := _panel()
	panel.set_cursor(1)
	assert_bool(panel.handle_event(_key(KEY_E))).is_true()
	assert_bool(panel.handle_event(_key(KEY_X))).is_true()
	panel.set_cursor(2)
	assert_bool(panel.handle_event(_key(KEY_V))).is_true()
	assert_bool(panel.handle_event(_key(KEY_R))).is_true()
	# Enter lifts the sword and puts it on the main hand slot: a move.
	panel.set_cursor(1)
	panel.handle_event(_key(KEY_ENTER))
	assert_int(panel.held).is_equal(1)
	panel.set_cursor(Inventory.Cell.MAIN)
	panel.handle_event(_key(KEY_ENTER))
	assert_int(panel.held).is_equal(-1)
	# Lifting and putting down on the same cell cancels; lifting nothing does nothing.
	panel.set_cursor(2)
	panel.handle_event(_key(KEY_ENTER))
	panel.handle_event(_key(KEY_ENTER))
	panel.set_cursor(20)
	panel.handle_event(_key(KEY_ENTER))
	assert_int(panel.held).is_equal(-1)
	assert_bool(panel.handle_event(_key(KEY_Z))).is_false()
	(
		assert_array(_intents)
		. is_equal(
			[
				[Net.Op.EQUIP, 1, 0],
				[Net.Op.DROP, 1, 1],
				[Net.Op.SPLIT, 2, 5],
				[Net.Op.SORT, 0, 0],
				[Net.Op.MOVE, 1, Inventory.Cell.MAIN],
			]
		)
	)


func test_the_cursor_walks_the_bag_and_the_doll() -> void:
	var main := Inventory.Cell.MAIN
	var helm := Inventory.Cell.HELM
	assert_int(InventoryPanel.neighbor(-1, Vector2i.RIGHT)).is_equal(0)
	assert_int(InventoryPanel.neighbor(0, Vector2i.RIGHT)).is_equal(1)
	assert_int(InventoryPanel.neighbor(0, Vector2i.UP)).is_equal(0)
	assert_int(InventoryPanel.neighbor(7, Vector2i.RIGHT)).is_equal(7)
	assert_int(InventoryPanel.neighbor(7, Vector2i.DOWN)).is_equal(15)
	assert_int(InventoryPanel.neighbor(31, Vector2i.DOWN)).is_equal(31)
	# Left out of the bag lands on the right gear column, right out of it comes back.
	assert_int(InventoryPanel.neighbor(8, Vector2i.LEFT)).is_equal(Inventory.Cell.OFF)
	assert_int(InventoryPanel.neighbor(Inventory.Cell.OFF, Vector2i.RIGHT)).is_equal(8)
	assert_int(InventoryPanel.neighbor(main, Vector2i.DOWN)).is_equal(Inventory.Cell.OFF)
	assert_int(InventoryPanel.neighbor(main, Vector2i.LEFT)).is_equal(helm)
	assert_int(InventoryPanel.neighbor(helm, Vector2i.UP)).is_equal(helm)
	# Every cell can be reached from the first one by arrows.
	var seen := {0: true}
	var open := [0]
	while not open.is_empty():
		var cell: int = open.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := InventoryPanel.neighbor(cell, step)
			assert_bool(Inventory.valid(next)).is_true()
			if not seen.has(next):
				seen[next] = true
				open.append(next)
	assert_int(seen.size()).is_equal(Inventory.CELLS)


func test_junk_is_starred_sorts_last_and_survives_a_reload() -> void:
	var panel := _panel()
	panel.persist = true
	var changed := [0]
	panel.junk_changed.connect(func() -> void: changed[0] += 1)
	panel.toggle_junk(2)
	assert_array(Settings.junk).is_equal([&"hide"])
	assert_bool(panel._slots[2].junk).is_true()
	assert_int(changed[0]).is_equal(1)
	# The character file keeps the list: what is written reads back.
	var saved := CharacterSave.make("id", "x", Inventory.new(), Settings.junk)
	Settings.junk.clear()
	Settings.junk = CharacterSave.junk_of(saved["junk"])
	assert_array(Settings.junk).is_equal([&"hide"])
	panel.toggle_junk(2)
	assert_array(Settings.junk).is_empty()
	panel.toggle_junk(20)
	assert_array(Settings.junk).is_empty()
	# The server's sort puts starred items after all others.
	var inv := Inventory.new()
	inv.add(&"bandage", 2)
	inv.add(&"hide", 3)
	inv.add(&"sword", 1)
	inv.sort()
	assert_str(inv.at(0).id).is_equal("sword")
	assert_str(inv.at(2).id).is_equal("bandage")
	inv.sort(1 << Items.index(&"sword"))
	assert_str(inv.at(0).id).is_equal("hide")
	assert_str(inv.at(2).id).is_equal("sword")
	assert_bool(Inventory.is_junk(1 << Items.index(&"hide"), &"hide")).is_true()
	assert_bool(Inventory.is_junk(-1, &"")).is_false()


func test_the_tooltip_compares_with_the_worn_item() -> void:
	var runed := Items.by_id(&"sword_runed")
	var plain := Items.by_id(&"sword")
	var better := ItemTooltip.rows(runed, plain)
	assert_str(better[0]["name"]).is_equal("Damage")
	assert_str(better[0]["diff"]).is_equal("+0.40")
	assert_bool(better[0]["better"]).is_true()
	var worse := ItemTooltip.rows(plain, runed)
	assert_str(worse[0]["diff"]).is_equal("-0.40")
	assert_bool(worse[0]["better"]).is_false()
	assert_str(ItemTooltip.rows(runed, null)[0]["diff"]).is_equal("")
	var armor := ItemTooltip.rows(Items.by_id(&"chest_chain"), Items.by_id(&"helm_leather"))
	assert_str(armor[0]["name"]).is_equal("Defense")
	assert_str(ItemTooltip.rows(Items.by_id(&"hide"), null)[-1]["name"]).is_equal("Weight")
	var tip := auto_free(ItemTooltip.new()) as ItemTooltip
	add_child(tip)
	tip.show_item(Inventory.Stack.new(&"sword_runed", 1), Inventory.Stack.new(&"sword", 1), true)
	assert_bool(tip.visible).is_true()


func test_the_hotbar_shows_the_first_eight_bag_cells() -> void:
	var bar := auto_free(Hotbar.new()) as Hotbar
	add_child(bar)
	var inv := Inventory.new()
	inv.cells[0] = Inventory.Stack.new(&"bandage", 3)
	inv.cells[7] = Inventory.Stack.new(&"bone", 2)
	inv.cells[8] = Inventory.Stack.new(&"hide", 2)
	bar.show_inventory(inv)
	assert_int(bar._slots.size()).is_equal(8)
	assert_int(bar._slots[0].stack.count).is_equal(3)
	assert_str(bar._slots[7].stack.id).is_equal("bone")
	assert_str(bar._slots[0].key_hint).is_equal("3")
	assert_str(bar._slots[5].key_hint).is_equal("8")
	assert_str(bar._slots[6].key_hint).is_equal("")


func _server(health: float) -> Array:
	var world := auto_free(World.new(false)) as World
	add_child(world)
	var body := SimPlayer.new()
	body.name = "Player5"
	body.peer_id = 5
	world.players.add_child(body)
	body.health = health
	var inventories := auto_free(Inventories.new()) as Inventories
	inventories.net = auto_free(Net.new()) as Net
	inventories.world = world
	add_child(inventories)
	var inv := Inventory.starting_kit()
	inv.cells[0] = Inventory.Stack.new(&"bandage", 2)
	inv.cells[1] = Inventory.Stack.new(&"chest_chain", 1)
	inv.cells[2] = Inventory.Stack.new(&"hide", 1)
	inventories.add_peer(5, inv)
	return [inventories, body, inv]


func test_use_heals_once_per_tick_and_wears_gear() -> void:
	var parts := _server(40.0)
	var inventories: Inventories = parts[0]
	var body: SimPlayer = parts[1]
	var inv: Inventory = parts[2]
	var tick := NetworkTime.tick + 1
	var healed := 40.0 + Items.by_id(&"bandage").heal
	assert_bool(inventories.apply(5, Net.Op.USE, 0, 0)).is_true()
	assert_int(inv.at(0).count).is_equal(1)
	inventories._apply_gear(tick - 1)
	assert_float(body.health).is_equal(40.0)
	inventories._apply_gear(tick)
	assert_float(body.health).is_equal(healed)
	# A resimulated tick restores older health first; the heal comes again, only at its tick.
	body.health = 40.0
	inventories._apply_gear(tick)
	assert_float(body.health).is_equal(healed)
	inventories._apply_gear(tick + 1)
	assert_float(body.health).is_equal(healed)
	# Armor is worn by USE; a material is not usable; full health keeps the bandage.
	assert_bool(inventories.apply(5, Net.Op.USE, 1, 0)).is_true()
	assert_object(inv.at(Inventory.Cell.CHEST)).is_not_null()
	assert_bool(inventories.apply(5, Net.Op.USE, 2, 0)).is_false()
	body.health = Tuning.data().max_health
	assert_bool(inventories.apply(5, Net.Op.USE, 0, 0)).is_false()
	assert_int(inv.at(0).count).is_equal(1)
	assert_bool(inventories.apply(5, Net.Op.USE, -3, 0)).is_false()
	assert_bool(inventories.apply(5, Net.Op.USE, 99, 0)).is_false()


func test_use_while_dead_does_nothing() -> void:
	var parts := _server(0.0)
	var body: SimPlayer = parts[1]
	body.action = SimPlayer.Action.DEAD
	assert_bool((parts[0] as Inventories).apply(5, Net.Op.USE, 0, 0)).is_false()
	assert_int((parts[2] as Inventory).at(0).count).is_equal(2)
