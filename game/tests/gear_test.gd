extends GdUnitTestSuite
## Worn gear in the simulation (M23): a better sword hurts more, armor and shields take damage
## off, and an equip on the server reaches the rolled back ints. Same setup as combat_test.

const DELTA := 1.0 / 30.0
const B := PlayerControls.Buttons

var _world: Node3D
var _player: SimPlayer
var _passive: Enemy
var _swinger: Enemy


func before_test() -> void:
	_world = auto_free(Node3D.new()) as Node3D
	add_child(_world)
	FlatGround.add(_world)
	_passive = _dummy(0, Vector3(-4.0, 0.0, -10.0), true)
	_swinger = _dummy(1, Vector3(4.0, 0.0, -10.0), false)
	_player = SimPlayer.new()
	_world.add_child(_player)
	_player.place(Vector3(0, 0, 0))


func _dummy(index: int, at: Vector3, passive: bool) -> Enemy:
	var dummy := Enemy.new()
	dummy.kind = Combat.enemy_kind(&"dummy")
	dummy.index = index
	dummy.passive = passive
	dummy.facing = Vector3.BACK
	_world.add_child(dummy)
	dummy.global_transform = Transform3D(SimPlayer.frame(Vector3.UP, dummy.facing), at)
	return dummy


func _face(dummy: Enemy, distance := 1.6) -> void:
	_player.place(dummy.global_position + Vector3.BACK * distance)
	_player.facing = Vector3.FORWARD
	_player.ref_forward = Vector3.FORWARD


func _run(ticks: int, buttons := 0) -> void:
	for i in ticks:
		await get_tree().physics_frame
		_passive._rollback_tick(DELTA, 0, true)
		_swinger._rollback_tick(DELTA, 0, true)
		_player.step(Vector2.ZERO, 0.0, buttons, DELTA)


func _wear(main: StringName, off: StringName, bow: StringName, armor_value: int) -> void:
	_player.main_hand = Items.index(main)
	_player.off_hand = Items.index(off)
	_player.ranged = Items.index(bow)
	_player.armor = armor_value


## The damage one light swing deals to the passive dummy with the main hand worn.
func _swing_damage(main: StringName) -> float:
	_passive.health = _passive.max_health
	_player.main_hand = Items.index(main)
	_face(_passive)
	await _run(1, B.ATTACK)
	await _run(25)
	return _passive.max_health - _passive.health


func test_the_starting_kit_is_what_the_tests_without_gear_assume() -> void:
	var fresh := auto_free(SimPlayer.new()) as SimPlayer
	assert_float(Loadout.damage_scale(fresh.main_hand)).is_equal(1.0)
	assert_float(Loadout.damage_scale(fresh.ranged)).is_equal(1.0)
	assert_float(Loadout.block_share(fresh.off_hand)).is_equal(Tuning.data().block_reduction)
	assert_int(fresh.armor).is_equal(0)
	var worn := Loadout.of(Inventory.starting_kit())
	assert_int(worn.main_hand).is_equal(fresh.main_hand)
	assert_int(worn.off_hand).is_equal(fresh.off_hand)
	assert_int(worn.ranged).is_equal(fresh.ranged)
	assert_int(worn.armor).is_equal(0)


func test_a_better_sword_changes_the_damage_a_dummy_takes() -> void:
	var base := Combat.attack(&"light_1").damage
	var plain := await _swing_damage(&"sword")
	var runed := await _swing_damage(&"sword_runed")
	assert_float(plain).is_equal_approx(base, 0.01)
	assert_float(runed).is_equal_approx(base * Items.by_id(&"sword_runed").damage, 0.01)
	var bare := await _swing_damage(&"")
	assert_float(bare).is_equal_approx(base * Tuning.data().unarmed_damage, 0.01)
	assert_float(bare).is_less(plain)


func test_a_better_crossbow_changes_the_bolt_damage() -> void:
	var t := Tuning.data()
	_player.action_time = Combat.ticks(t.draw_time)
	_player.ranged = Items.index(&"crossbow")
	_player._shoot(0.0, 0.0, t)
	var plain := _player.bolt_damage[0]
	_player.ranged = Items.index(&"crossbow_ash")
	_player.action_time = Combat.ticks(t.draw_time)
	_player._shoot(0.0, 0.0, t)
	var ash := _player.bolt_damage[1]
	assert_float(plain).is_equal_approx(t.bolt_damage_max, 0.01)
	assert_float(ash).is_equal_approx(plain * Items.by_id(&"crossbow_ash").damage, 0.01)


func test_armor_lowers_the_damage_taken() -> void:
	var damage := Combat.attack(&"dummy_swing").damage
	_wear(&"sword", &"shield_wood", &"crossbow", 6)
	_face(_swinger)
	await _run(Combat.ticks(_swinger.def.rest) + 40)
	assert_float(_player.health).is_equal_approx(Tuning.data().max_health - (damage - 6.0), 0.01)
	# Never below a quarter of the hit, whatever the armor.
	assert_float(Loadout.damage_taken(damage, 255)).is_equal(damage * 0.25)
	assert_float(Loadout.damage_taken(damage, 0)).is_equal(damage)


func test_a_shield_changes_the_block() -> void:
	var t := Tuning.data()
	var damage := Combat.attack(&"dummy_swing").damage
	_wear(&"sword", &"shield_iron", &"crossbow", 0)
	_face(_swinger)
	await _run(1, B.BLOCK)
	while _swinger.action != Enemy.Action.RECOVER:
		await _run(1, B.BLOCK)
	var share := t.block_reduction + Items.by_id(&"shield_iron").defense
	assert_float(Loadout.block_share(Items.index(&"shield_iron"))).is_equal_approx(share, 0.0001)
	assert_float(_player.health).is_equal_approx(t.max_health - damage * (1.0 - share), 0.01)
	assert_float(Loadout.block_share(Items.index(&"shield_iron"))).is_greater(
		Loadout.block_share(Items.index(&"shield_wood"))
	)


func test_loadout_sums_the_armor_pieces_and_clamps() -> void:
	var inv := Inventory.new()
	inv.cells[Inventory.Cell.HELM] = Inventory.Stack.new(&"helm_leather", 1)
	inv.cells[Inventory.Cell.CHEST] = Inventory.Stack.new(&"chest_chain", 1)
	inv.cells[Inventory.Cell.LEGS] = Inventory.Stack.new(&"legs_barrow", 1)
	var worn := Loadout.of(inv)
	var expected := 0
	for id in [&"helm_leather", &"chest_chain", &"legs_barrow"]:
		expected += roundi(Items.by_id(id).defense)
	assert_int(worn.armor).is_equal(expected)
	assert_int(worn.main_hand).is_equal(0)
	assert_int(Loadout.of(Inventory.new()).armor).is_equal(0)


## The server side: an equip reaches the player's rolled back ints, and keeps reaching them
## when a tick is simulated again (netfox restores the recorded state first).
func test_an_equip_on_the_server_changes_the_rolled_back_ints() -> void:
	var world := auto_free(World.new(false)) as World
	add_child(world)
	var body := SimPlayer.new()
	body.name = "Player7"
	body.peer_id = 7
	world.players.add_child(body)
	var inventories := auto_free(Inventories.new()) as Inventories
	inventories.net = auto_free(Net.new()) as Net
	inventories.world = world
	add_child(inventories)
	var inv := Inventory.starting_kit()
	inv.cells[3] = Inventory.Stack.new(&"sword_runed", 1)
	inv.cells[4] = Inventory.Stack.new(&"chest_chain", 1)
	inventories.add_peer(7, inv)
	var deltas: Array[Dictionary] = []
	inventories.changed.connect(func(_id: int, cells: Dictionary) -> void: deltas.append(cells))
	var before := body.main_hand
	assert_bool(inventories.apply(7, Net.Op.EQUIP, 3, 0)).is_true()
	assert_int(deltas.size()).is_equal(1)
	assert_int(deltas[0].size()).is_equal(2)
	# Nothing changed in the body until the next rollback step ends.
	assert_int(body.main_hand).is_equal(before)
	inventories._apply_gear(1)
	assert_int(body.main_hand).is_equal(Items.index(&"sword_runed"))
	assert_bool(inventories.apply(7, Net.Op.EQUIP, 4, 0)).is_true()
	inventories._apply_gear(2)
	assert_int(body.armor).is_equal(roundi(Items.by_id(&"chest_chain").defense))
	# A resimulated tick restores older state; the next step puts the gear back.
	body.main_hand = before
	body.armor = 0
	inventories._apply_gear(1)
	assert_int(body.main_hand).is_equal(Items.index(&"sword_runed"))
	assert_int(body.armor).is_equal(roundi(Items.by_id(&"chest_chain").defense))
	# The ints travel in the packed combat group.
	var other := auto_free(SimPlayer.new()) as SimPlayer
	other.net_combat = body.net_combat
	assert_int(other.main_hand).is_equal(body.main_hand)
	assert_int(other.armor).is_equal(body.armor)


func test_bad_intents_change_nothing() -> void:
	var world := auto_free(World.new(false)) as World
	add_child(world)
	var body := SimPlayer.new()
	body.name = "Player8"
	world.players.add_child(body)
	var inventories := auto_free(Inventories.new()) as Inventories
	inventories.net = auto_free(Net.new()) as Net
	inventories.world = world
	add_child(inventories)
	inventories.add_peer(8)
	var before := inventories.snapshot(8)
	for op in [-1, 99, Net.Op.MOVE, Net.Op.EQUIP, Net.Op.DROP, Net.Op.SPLIT, Net.Op.STORE_MATCHING]:
		assert_bool(inventories.apply(8, op, -5, 1000000)).is_false()
		assert_bool(inventories.apply(8, op, 1000000, -5)).is_false()
	# A peer without a player or inventory is ignored.
	assert_bool(inventories.apply(9, Net.Op.SORT, 0, 0)).is_false()
	assert_dict(inventories.snapshot(8)).is_equal(before)
	# Rate limit: past 30 intents in a second the rest are dropped.
	var applied: Array[int] = [0]
	inventories.changed.connect(func(_id: int, _cells: Dictionary) -> void: applied[0] += 1)
	for i in 100:
		inventories._on_intent(
			8, Net.Op.UNEQUIP if i % 2 == 0 else Net.Op.EQUIP, 33 if i % 2 == 0 else 0, 0
		)
	assert_int(applied[0]).is_less_equal(Inventories.MAX_INTENTS_PER_SECOND)
	assert_int(applied[0]).is_greater(0)
