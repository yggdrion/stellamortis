extends GdUnitTestSuite
## Loot (M23 task 2): seeded tables, a kill and the Warden drop once (also when the spawner
## decides again on a replayed tick), the elite's chest opens once and only when its camp is
## clear, pickups add to the inventory and respect the reach and a full bag, drops expire.

const SEED := 1234
const PLAYER := 1

var _world: World
var _realm: RealmDef
var _spawner: Spawner
var _looting: Looting
var _inventories: Inventories
var _player: SimPlayer
var _tick := Spawner.PERIOD
var _added: Array[Dictionary] = []
var _removed: Array[int] = []
var _notices: Array[String] = []
var _loot_piles := 0


func before_test() -> void:
	_realm = Layout.realms()[0]
	_world = auto_free(World.new(false)) as World
	add_child(_world)
	_world.build(SEED, "test")
	_world.add_spawner()
	_spawner = _world.spawner
	_player = auto_free(SimPlayer.new()) as SimPlayer
	_player.peer_id = PLAYER
	_player.name = "Player%d" % PLAYER
	_world.players.add_child(_player)
	_inventories = auto_free(Inventories.new()) as Inventories
	_inventories.net = auto_free(Net.new()) as Net
	_inventories.world = _world
	add_child(_inventories)
	_inventories.add_peer(PLAYER)
	_looting = auto_free(Looting.new()) as Looting
	_looting.world = _world
	_looting.inventories = _inventories
	_added.clear()
	_removed.clear()
	_notices.clear()
	_loot_piles = 0
	_looting.added.connect(func(_id: int, data: Dictionary) -> void: _added.append(data))
	_looting.removed.connect(func(id: int, _by: int) -> void: _removed.append(id))
	_looting.notice.connect(func(_peer: int, text: String) -> void: _notices.append(text))
	_spawner.dropped.connect(
		func(_at: Vector3, _up: Vector3, _stacks: Array, _seed: int) -> void: _loot_piles += 1
	)
	add_child(_looting)
	_tick = Spawner.PERIOD


func after_test() -> void:
	Layout.set_world_seed(0)


func _update(times := 1) -> void:
	for i in times:
		_spawner.update(_tick)
		_tick += Spawner.PERIOD


## Puts the player on the ground at a spawn point's camp, `away` meters to the side.
func _stand(point: Spawner.SpawnPoint, away: float) -> void:
	var east := point.up.cross(Vector3.UP).normalized()
	var direction := (point.up * _realm.radius + east * away).normalized()
	var feet := Terrain.surface(_realm, SEED, direction) + direction * Layout.ARRIVAL_LIFT
	_world.chunks.ensure_around(feet)
	_player.place(feet)


func _first(camp: int) -> Spawner.SpawnPoint:
	for point in Spawner.points(_realm, SEED):
		if point.camp == camp:
			return point
	return null


func _kill_awake(unit: int) -> void:
	for slot: int in _spawner.slots_of(unit).values():
		var enemy := _world.pool_slot(slot)
		enemy.action = Enemy.Action.IDLE
		enemy.take_hit(100000.0, Vector3.ZERO)


## A drop lying a meter from the player.
func _drop(id: StringName, count: int) -> int:
	var at := _player.global_position + _player.up * 0.1
	return _looting.objects.add_drop(Inventory.Stack.new(id, count), at, _player.up, 0.0)


func _fill_bag() -> void:
	for cell in Inventory.BAG_SIZE:
		_inventories.inventory(PLAYER).cells[cell] = Inventory.Stack.new(&"sword", 1)


func test_table_rolls_are_seeded_and_respect_the_entries() -> void:
	var table := LootTable.by_id(&"swordsman")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var first := table.roll(rng)
	rng.seed = 77
	var again := table.roll(rng)
	assert_int(first.size()).is_equal(again.size())
	for i in first.size():
		assert_str(first[i].id).is_equal(again[i].id)
		assert_int(first[i].count).is_equal(again[i].count)
	var custom := LootTable.new()
	custom.rolls = 200
	custom.entries = [
		{"item": &"bone", "weight": 1, "min": 2, "max": 4, "chance": 1.0},
		{"item": &"hide", "weight": 1, "min": 1, "max": 1, "chance": 0.0},
	]
	var totals := {}
	for stack in custom.roll(rng):
		totals[stack.id] = totals.get(stack.id, 0) + stack.count
		assert_int(stack.count).is_less_equal(Items.by_id(stack.id).stack)
	assert_bool(totals.has(&"hide")).is_false()
	# About 100 picks of bone, 2 to 4 each.
	assert_int(totals[&"bone"]).is_between(150, 450)
	var none := LootTable.new()
	assert_array(none.roll(rng)).is_empty()
	assert_object(LootTable.by_id(&"")).is_null()
	assert_object(LootTable.by_id(&"no_such_table")).is_null()


func test_every_kind_that_dies_has_a_table_and_the_chest_gives_uncommon_or_better() -> void:
	for kind in [&"swordsman", &"archer", &"berserker", &"shield_bearer", &"barrow_elite"]:
		assert_object(LootTable.by_id(Combat.enemy_def(Combat.enemy_kind(kind)).loot)).is_not_null()
	(
		assert_object(LootTable.by_id(Combat.enemy_def(Combat.enemy_kind(&"warden")).loot))
		. is_not_null()
	)
	assert_str(Combat.enemy_def(Combat.enemy_kind(&"dummy")).loot).is_equal("")
	assert_str(Combat.enemy_def(Combat.enemy_kind(&"free")).loot).is_equal("")
	var chest := LootTable.by_id(&"chest_elite")
	for entry in chest.entries:
		assert_int(Items.by_id(entry.item).rarity).is_greater_equal(1)
		assert_float(entry.chance).is_equal(1.0)


func test_a_kill_drops_once_even_when_the_spawner_decides_again() -> void:
	var point := _first(0)
	_stand(point, 60.0)
	_update()
	assert_int(_spawner.slots_of(0).size()).is_greater(0)
	var members := _spawner.slots_of(0).values()
	_kill_awake(0)
	_update()
	var piles := _loot_piles
	var drops := _added.size()
	assert_int(piles).is_greater(0)
	assert_int(drops).is_greater(0)
	assert_int(_looting.objects.entries.size()).is_equal(drops + _chests())
	# The same state again, and a rollback that showed them alive for a tick before they fell.
	_update(2)
	for slot: int in members:
		_world.pool_slot(slot).action = Enemy.Action.IDLE
	_update()
	_kill_awake(0)
	_update()
	assert_int(_loot_piles).is_equal(piles)
	assert_int(_added.size()).is_equal(drops)
	# Every drop lies on the ground near the camp.
	for data: Dictionary in _added:
		var spot: Vector3 = data.pos
		assert_float(spot.distance_to(_world.pool_slot(members[0]).global_position)).is_less(6.0)
		assert_bool(data.has("from")).is_true()


func test_a_kill_gives_the_same_pile_after_a_restart() -> void:
	var point := _first(0)
	_stand(point, 60.0)
	_update()
	_kill_awake(0)
	_update()
	var before: Array[String] = []
	for data: Dictionary in _added:
		before.append("%s x%d" % [data.item, data.count])
	assert_int(before.size()).is_greater(0)
	# A second world, as after a restart.
	var again := auto_free(World.new(false)) as World
	add_child(again)
	again.build(SEED, "test")
	again.add_spawner()
	var after: Array[String] = []
	again.spawner.dropped.connect(
		func(_at: Vector3, _up: Vector3, stacks: Array, _seed: int) -> void:
			for stack: Inventory.Stack in stacks:
				after.append("%s x%d" % [stack.id, stack.count])
	)
	var player := auto_free(SimPlayer.new()) as SimPlayer
	player.peer_id = 2
	again.players.add_child(player)
	player.place(_player.global_position)
	again.spawner.update(Spawner.PERIOD)
	for slot: int in again.spawner.slots_of(0).values():
		var enemy := again.pool_slot(slot)
		enemy.action = Enemy.Action.IDLE
		enemy.take_hit(100000.0, Vector3.ZERO)
	again.spawner.update(Spawner.PERIOD * 2)
	assert_array(after).is_equal(before)


func test_the_warden_drops_once_per_cleared_realm() -> void:
	var fight := _world.encounter
	fight.phase = Encounter.Phase.CLEARED
	_update()
	assert_int(_loot_piles).is_equal(1)
	assert_bool(_spawner.boss_looted.has(_realm.id)).is_true()
	assert_int(_added.size()).is_greater(0)
	var drops := _added.size()
	_update(2)
	fight.phase = Encounter.Phase.BOSS
	_update()
	fight.phase = Encounter.Phase.CLEARED
	_update()
	assert_int(_loot_piles).is_equal(1)
	assert_int(_added.size()).is_equal(drops)


func test_the_elite_chest_opens_once_and_only_when_its_camp_is_clear() -> void:
	assert_array(_spawner.chest_spots).is_not_empty()
	var spot: Spawner.ChestSpot = _spawner.chest_spots[0]
	assert_int(spot.unit).is_greater_equal(0)
	var chest_id := -1
	for id: int in _looting.objects.entries:
		if _looting.objects.at(id).kind == WorldObjects.Kind.CHEST:
			chest_id = id
			break
	assert_int(chest_id).is_greater(0)
	# The chest stands behind its camp, on walkable ground, and is seeded once.
	assert_bool(_looting.objects.has_chest(spot.key())).is_true()
	_looting.seed_chests()
	assert_int(_chests()).is_equal(_spawner.chest_spots.size())
	var camp_point := _first(spot.camp)
	_stand(camp_point, 80.0)
	_world.chunks.ensure_around(spot.position)
	_player.place(spot.position + spot.up * Layout.ARRIVAL_LIFT)
	# The guards live (and the camp is even asleep): shut.
	assert_bool(_looting.open(PLAYER, chest_id)).is_false()
	assert_array(_notices).contains(["The guards still stand"])
	_update()
	assert_int(_spawner.slots_of(spot.unit).size()).is_greater(0)
	assert_bool(_looting.open(PLAYER, chest_id)).is_false()
	_kill_awake(spot.unit)
	_update()
	assert_bool(_spawner.camp_clear(spot.unit)).is_true()
	var before := _added.size()
	# Too far: nothing.
	_player.place(spot.position + spot.up * Layout.ARRIVAL_LIFT + spot.up.cross(Vector3.UP) * 20.0)
	assert_bool(_looting.open(PLAYER, chest_id)).is_false()
	_player.place(spot.position + spot.up * Layout.ARRIVAL_LIFT)
	assert_bool(_looting.open(PLAYER, chest_id)).is_true()
	assert_bool(_looting.objects.at(chest_id).flags.opened).is_true()
	var given := _added.size() - before
	assert_int(given).is_greater(0)
	# Every stack is the elite table's, at least one piece of uncommon or better rarity.
	var best := 0
	for i in range(before, _added.size()):
		best = maxi(best, Items.by_id(StringName(_added[i].item)).rarity)
	assert_int(best).is_greater_equal(1)
	assert_bool(_looting.open(PLAYER, chest_id)).is_false()
	assert_int(_added.size() - before).is_equal(given)


func test_pickup_adds_to_the_inventory_and_checks_the_reach() -> void:
	_stand(_first(0), 60.0)
	var id := _drop(&"sword_runed", 1)
	assert_bool(_looting.pickup(PLAYER, id)).is_true()
	assert_int(_inventories.inventory(PLAYER).count_of(&"sword_runed")).is_equal(1)
	assert_object(_looting.objects.at(id)).is_null()
	assert_array(_removed).contains([id])
	# Not the same drop twice, nor a peer without a player.
	assert_bool(_looting.pickup(PLAYER, id)).is_false()
	var far := _drop(&"hide", 2)
	_looting.objects.at(far).position += _player.up.cross(Vector3.UP).normalized() * 10.0
	assert_bool(_looting.pickup(PLAYER, far)).is_false()
	assert_object(_looting.objects.at(far)).is_not_null()
	assert_bool(_looting.pickup(99, far)).is_false()


func test_a_full_bag_leaves_the_drop_on_the_ground() -> void:
	_stand(_first(0), 60.0)
	_fill_bag()
	var id := _drop(&"ember", 3)
	assert_bool(_looting.pickup(PLAYER, id)).is_false()
	assert_object(_looting.objects.at(id)).is_not_null()
	assert_array(_notices).contains(["Bag full"])
	# Room for part of it: the rest stays.
	var inventory := _inventories.inventory(PLAYER)
	inventory.cells[0] = Inventory.Stack.new(&"ember", Items.by_id(&"ember").stack - 2)
	assert_bool(_looting.pickup(PLAYER, id)).is_true()
	assert_int(inventory.at(0).count).is_equal(Items.by_id(&"ember").stack)
	assert_int(_looting.objects.at(id).stack().count).is_equal(1)


func test_materials_walk_into_the_bag_and_dropped_items_wait() -> void:
	_stand(_first(0), 60.0)
	var material := _drop(&"bone", 2)
	var piece := _drop(&"sword_runed", 1)
	_looting.advance(Looting.PERIOD + 0.01)
	assert_object(_looting.objects.at(material)).is_null()
	assert_int(_inventories.inventory(PLAYER).count_of(&"bone")).is_equal(2)
	# Gear is never taken by walking over it.
	assert_object(_looting.objects.at(piece)).is_not_null()
	# What the player drops is not taken straight back.
	_inventories.inventory(PLAYER).add(&"hide", 4)
	var cell := -1
	for i in Inventory.BAG_SIZE:
		var stack := _inventories.inventory(PLAYER).at(i)
		if stack != null and stack.id == &"hide":
			cell = i
	assert_bool(_inventories.apply(PLAYER, Net.Op.DROP, cell, 4)).is_true()
	var dropped := _looting.objects.entries.keys().back() as int
	assert_int(_looting.objects.at(dropped).stack().count).is_equal(4)
	_looting.advance(Looting.PERIOD + 0.01)
	assert_object(_looting.objects.at(dropped)).is_not_null()
	# Standing on it, it is taken once the hold is over.
	_player.place(_looting.objects.at(dropped).position)
	_looting.advance(Looting.PERIOD + 0.01)
	assert_object(_looting.objects.at(dropped)).is_not_null()
	_looting.advance(Looting.DROP_HOLD)
	assert_object(_looting.objects.at(dropped)).is_null()


func test_a_drop_nobody_takes_expires() -> void:
	_stand(_first(0), 60.0)
	var id := _drop(&"sword_runed", 1)
	_looting.objects.at(id).position += _player.up.cross(Vector3.UP).normalized() * 50.0
	_looting.advance(WorldObjects.DROP_LIFETIME - 10.0)
	assert_object(_looting.objects.at(id)).is_not_null()
	_looting.advance(20.0)
	assert_object(_looting.objects.at(id)).is_null()
	assert_array(_removed).contains([id])
	# Chests do not expire.
	assert_int(_chests()).is_equal(_spawner.chest_spots.size())


func test_objects_survive_a_round_trip_and_a_hostile_file() -> void:
	var objects := WorldObjects.new()
	var drop := objects.add_drop(Inventory.Stack.new(&"bone", 5), Vector3(1, 2, 3), Vector3.UP, 4.0)
	var chest := objects.add(
		WorldObjects.Kind.CHEST,
		Inventory.new(),
		Vector3(4, 5, 6),
		Vector3.RIGHT,
		7.0,
		"",
		{"key": "barrowlands:3", "opened": true}
	)
	var again := WorldObjects.from_dict(JSON.parse_string(JSON.stringify(objects.to_dict())))
	assert_int(again.entries.size()).is_equal(2)
	assert_int(again.at(drop).stack().count).is_equal(5)
	assert_vector(again.at(drop).position).is_equal(Vector3(1, 2, 3))
	assert_bool(again.at(chest).flags.opened).is_true()
	assert_bool(again.has_chest("barrowlands:3")).is_true()
	assert_int(again.next_id).is_equal(objects.next_id)
	var bad := (
		WorldObjects
		. from_dict(
			{
				"next_id": "x",
				"entries":
				{
					"1": {"kind": 0, "contents": {"0": {"id": "nope", "count": 3}}},
					"2": {"kind": 99},
					"3": "junk",
					"4": {"kind": 0, "contents": {"0": {"id": "bone", "count": 1000000000}}},
				}
			}
		)
	)
	assert_int(bad.entries.size()).is_equal(1)
	assert_int(bad.at(4).stack().count).is_equal(Items.by_id(&"bone").stack)
	assert_int(WorldObjects.from_dict("no").entries.size()).is_equal(0)


func _chests() -> int:
	var count := 0
	for id: int in _looting.objects.entries:
		count += int(_looting.objects.at(id).kind == WorldObjects.Kind.CHEST)
	return count
