class_name Spawner
extends Node
## Who lives on the generated realms (M21): `points` lays out camps and lone roamers from the
## world seed (pure, same on every run), the Spawner node wakes the ones near a player into free
## pool slots and frees them again when everyone is far away. Server only: it decides after the
## tick's rollback step (NetworkRollback.after_process_tick, before netfox records the state), so
## a woken slot is state like any other change and clients only ever see slot state. What it
## remembers (which slot serves which camp member, who is dead, how long a camp stays cleared)
## lives on the server alone; a rollback that replays a tick decides again from the same state.

## Camps of CAMP_MIN to CAMP_MAX around a center, one per CAMP_AREA m2 of ground; lone roamers
## one per ROAMER_AREA. A player walking 6 m/s sweeps about 180 m of wake range, so one camp
## per 60000 m2 (about 245 m apart) is something to meet every minute or two.
const CAMP_AREA := 60000.0
const ROAMER_AREA := 150000.0
const CAMP_MIN := 3
const CAMP_MAX := 6
## Members stand within this many meters of the camp's center, at least MEMBER_GAP apart.
const CAMP_RADIUS := 7.0
const MEMBER_GAP := 2.5
const MEMBER_TRIES := 8
## Centers of camps and roamers keep this far apart.
const UNIT_GAP := 80.0
## Nothing lives this close to a realm's arrival: farther than WAKE, so arriving is calm.
const ARRIVAL_CLEAR := 120.0
## Ground steeper than this (cosine of the slope) is no place to stand a camp.
const WALKABLE := 0.85
const ARCHER_SHARE := 0.25
## Candidates tried per camp or roamer wanted before giving up.
const ATTEMPTS := 8
## Feet this far above the ground (the body settles).
const LIFT := 0.1
## Pool slots from here on are the spawner's (the old encounter holds the first ones, M22).
const FIRST_SLOT := 4
## A camp wakes when a player is this close (m), and sleeps when all are farther than SLEEP.
const WAKE := 90.0
const SLEEP := 140.0
## The decision runs every this many ticks.
const PERIOD := 6
## Seconds a fallen enemy lies there before its slot is free again.
const CORPSE_TIME := 20.0
## Seconds without damage before an enemy counts as out of a fight.
const FIGHT_QUIET := 6.0
## Minutes a camp whose enemies all died stays empty.
const RESPAWN_MINUTES := 10.0
## Chunks are made right under a camp before it wakes (a no-op when they stand).
const GROUND_RADIUS := 12.0


class SpawnPoint:
	extends RefCounted
	var realm: RealmDef
	## Index into Combat.ENEMY_KINDS.
	var kind := 0
	## World position, a little above the ground, and the direction from the realm's center.
	var position := Vector3.ZERO
	var up := Vector3.UP
	## Which way it faces, radians around up.
	var yaw := 0.0
	## A camp's id within its realm; a roamer is a camp of one.
	var camp := 0

	## Where an enemy stands, as a slot's `home`.
	func post() -> Transform3D:
		var facing := SimPlayer._tangent(Vector3.FORWARD, up).rotated(up, yaw)
		return Transform3D(SimPlayer.frame(up, facing), position)


var world: World
var _units: Array[Array] = []
var _centers := PackedVector3Array()
## Unit -> [realm id, camp id], as the clients' map knows a camp.
var _ids: Array[Array] = []
## Unit -> {member index: pool slot index} of the members awake.
var _awake := {}
## Unit -> {member index: tick first seen down}.
var _dead := {}
## Unit -> tick its camp is open again.
var _cleared_until := {}


func _init(for_world: World) -> void:
	name = "Spawner"
	world = for_world
	for realm in Layout.realms():
		var grouped := {}
		for point in points(realm, for_world.world_seed):
			if not grouped.has(point.camp):
				grouped[point.camp] = []
			grouped[point.camp].append(point)
		for camp: Array in grouped.values():
			var center := Vector3.ZERO
			for point: SpawnPoint in camp:
				center += point.position
			_units.append(camp)
			_ids.append([realm.id, (camp[0] as SpawnPoint).camp])
			_centers.append(center / camp.size())


func _ready() -> void:
	NetworkRollback.after_process_tick.connect(update)


## The camps and roamers of a realm under a seed, in a fixed order.
static func points(realm: RealmDef, world_seed: int) -> Array[SpawnPoint]:
	var field := Terrain.Field.new(realm, world_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(world_seed, realm.seed_salt)) + 23
	var area := 4.0 * PI * realm.radius * realm.radius
	var found: Array[SpawnPoint] = []
	var centers: Array[Vector3] = []
	var camp := 0
	for lone in [false, true]:
		var wanted := roundi(area / (ROAMER_AREA if lone else CAMP_AREA))
		var made := 0
		var tries := 0
		while made < wanted and tries < wanted * ATTEMPTS:
			tries += 1
			var direction := _random_direction(rng)
			if not _fits(realm, field, direction, centers):
				continue
			var count := 1 if lone else rng.randi_range(CAMP_MIN, CAMP_MAX)
			var members := _members(realm, field, rng, direction, count)
			if members.size() < (1 if lone else CAMP_MIN):
				continue
			for position in members:
				found.append(_point(realm, field, rng, position, camp))
			centers.append(direction)
			camp += 1
			made += 1
	return found


static func _random_direction(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var angle := rng.randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(angle), r * sin(angle), z)


## A camp or roamer may stand here: walkable, clear of the arrival and of the others.
static func _fits(
	realm: RealmDef, field: Terrain.Field, direction: Vector3, centers: Array[Vector3]
) -> bool:
	if direction.dot(realm.arrival.normalized()) > cos(ARRIVAL_CLEAR / realm.radius):
		return false
	if not _walkable(field, direction):
		return false
	var near := cos(UNIT_GAP / realm.radius)
	for other in centers:
		if direction.dot(other) > near:
			return false
	return true


static func _walkable(field: Terrain.Field, direction: Vector3) -> bool:
	return Terrain._normal(field, direction).dot(direction) > WALKABLE


## Directions for count members around a center (the first stands on it), walkable and apart.
static func _members(
	realm: RealmDef, field: Terrain.Field, rng: RandomNumberGenerator, center: Vector3, count: int
) -> Array[Vector3]:
	var east := center.cross(Vector3.UP if absf(center.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := center.cross(east)
	var found: Array[Vector3] = [center]
	var spots: Array[Vector3] = [field.surface(center)]
	for n in range(1, count):
		for attempt in MEMBER_TRIES:
			var angle := rng.randf() * TAU
			var distance := CAMP_RADIUS * sqrt(rng.randf())
			var offset := (east * cos(angle) + north * sin(angle)) * distance
			var direction := (center * realm.radius + offset).normalized()
			if not _walkable(field, direction):
				continue
			var spot := field.surface(direction)
			var apart := true
			for other in spots:
				apart = apart and other.distance_to(spot) >= MEMBER_GAP
			if apart:
				found.append(direction)
				spots.append(spot)
				break
	return found


static func _point(
	realm: RealmDef, field: Terrain.Field, rng: RandomNumberGenerator, direction: Vector3, id: int
) -> SpawnPoint:
	var point := SpawnPoint.new()
	point.realm = realm
	point.camp = id
	point.up = direction
	point.position = realm.center + field.surface(direction) + direction * LIFT
	point.yaw = rng.randf() * TAU
	var archer := rng.randf() < ARCHER_SHARE
	point.kind = Combat.enemy_kind(&"archer" if archer else &"swordsman")
	return point


func unit_count() -> int:
	return _units.size()


## Debug map (M33): camp id -> seconds until the camp is open again, for the cleared camps of
## a realm. Read only.
func cleared_camps(realm_id: StringName, tick: int) -> Dictionary:
	return cleared_left(_ids, _cleared_until, realm_id, tick)


## The answer builder of cleared_camps: `ids` are [realm id, camp id] per unit, `until` unit ->
## tick the camp is open again.
static func cleared_left(
	ids: Array[Array], until: Dictionary, realm_id: StringName, tick: int
) -> Dictionary:
	var left := {}
	for unit: int in until:
		if ids[unit][0] == realm_id:
			left[ids[unit][1]] = maxf(0.0, float(until[unit] - tick) / Combat.TICKRATE)
	return left


## Slots now serving a unit (camp), member index -> slot index.
func slots_of(unit: int) -> Dictionary:
	return _awake.get(unit, {})


## Wakes camps near players and frees the ones left behind (a few times a second).
func update(tick: int) -> void:
	if tick % PERIOD != 0:
		return
	var players := _players()
	_reconcile(players)
	for unit: int in _awake.keys():
		_tend(unit, tick, players)
	for unit: int in _cleared_until.keys():
		if tick >= _cleared_until[unit]:
			_cleared_until.erase(unit)
			_dead.erase(unit)
	_wake_near(players)


## Netfox restores and replays ticks on the server, which puts slots back to an older state
## while this memory stays: a slot meant to be awake that is hidden again rises again, and a
## slot nobody assigned that is awake again (a camp freed since) goes back to sleep. Runs on
## every decision, so a rolled back wake or sleep is made good within PERIOD ticks.
func _reconcile(players: Array[SimPlayer]) -> void:
	var assigned := {}
	for unit: int in _awake:
		var dead: Dictionary = _dead.get(unit, {})
		for member: int in _awake[unit]:
			var index: int = _awake[unit][member]
			assigned[index] = true
			var enemy := world.pool_slot(index)
			if dead.has(member) or enemy.kind != 0 and enemy.action != Enemy.Action.HIDDEN:
				continue
			var count := 0
			for player in players:
				if player.global_position.distance_to(_centers[unit]) <= WAKE:
					count += 1
			_rise(enemy, _units[unit][member], maxi(1, count))
	for i in range(FIRST_SLOT, World.POOL):
		var enemy := world.pool_slot(i)
		if not assigned.has(i) and enemy.action != Enemy.Action.HIDDEN:
			_free(enemy)


## Alive players on a realm (nobody else is near anything that lives there).
func _players() -> Array[SimPlayer]:
	var found: Array[SimPlayer] = []
	for node in get_tree().get_nodes_in_group(SimPlayer.GROUP):
		var player := node as SimPlayer
		if player.action != SimPlayer.Action.DEAD and Layout.realm_at(player.global_position):
			found.append(player)
	return found


static func _nearest(players: Array[SimPlayer], point: Vector3) -> float:
	var best := INF
	for player in players:
		best = minf(best, player.global_position.distance_to(point))
	return best


## One awake camp: note the dead, free corpses that lay long enough, put the rest to sleep when
## everyone is far and none is in a fight.
func _tend(unit: int, tick: int, players: Array[SimPlayer]) -> void:
	var slots: Dictionary = _awake[unit]
	var dead: Dictionary = _dead.get(unit, {})
	var calm := true
	var living := 0
	for member: int in slots:
		var enemy := world.pool_slot(slots[member])
		if enemy.action == Enemy.Action.DOWN:
			dead[member] = dead.get(member, tick)
			continue
		dead.erase(member)
		living += 1
		var fighting := enemy.quiet_time < Combat.ticks(FIGHT_QUIET) or _attacking(enemy)
		if fighting or _nearest(players, enemy.global_position) <= SLEEP:
			calm = false
	_dead[unit] = dead
	if dead.size() == _units[unit].size() and not _cleared_until.has(unit):
		_cleared_until[unit] = tick + Combat.ticks(RESPAWN_MINUTES * 60.0)
	for member: int in slots.keys():
		var enemy := world.pool_slot(slots[member])
		var corpse := dead.has(member)
		var gone := tick - int(dead.get(member, tick)) >= Combat.ticks(CORPSE_TIME)
		if (corpse and gone) or (not corpse and calm and living > 0):
			_free(enemy)
			slots.erase(member)
	if slots.is_empty():
		_awake.erase(unit)


static func _attacking(enemy: Enemy) -> bool:
	return enemy.action in [Enemy.Action.WINDUP, Enemy.Action.STRIKE, Enemy.Action.STAGGER]


func _free(enemy: Enemy) -> void:
	enemy.become(Combat.enemy_kind(&"free"), enemy.home, Enemy.Action.HIDDEN)
	SimPlayer._mutate(enemy)


## Camps within WAKE of a player, nearest first, as long as free slots are left for them.
func _wake_near(players: Array[SimPlayer]) -> void:
	if players.is_empty():
		return
	var free := _free_slots()
	if free.is_empty():
		return
	var near: Array[Vector2] = []
	for unit in _units.size():
		if _awake.has(unit) or _cleared_until.has(unit):
			continue
		var distance := _nearest(players, _centers[unit])
		if distance <= WAKE:
			near.append(Vector2(distance, unit))
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for entry in near:
		var unit := int(entry.y)
		var members := _living_members(unit)
		if members.size() > free.size():
			continue
		var count := 0
		for player in players:
			if player.global_position.distance_to(_centers[unit]) <= WAKE:
				count += 1
		var slots := {}
		for member in members:
			slots[member] = free.pop_back()
			_rise(world.pool_slot(slots[member]), _units[unit][member], count)
		_awake[unit] = slots
		if free.is_empty():
			return


func _living_members(unit: int) -> Array[int]:
	var dead: Dictionary = _dead.get(unit, {})
	var found: Array[int] = []
	for member in _units[unit].size():
		if not dead.has(member):
			found.append(member)
	return found


## Free pool slots after the old encounter's, the lowest index last (popped first).
func _free_slots() -> Array[int]:
	var free: Array[int] = []
	for i in range(World.POOL - 1, FIRST_SLOT - 1, -1):
		if world.pool_slot(i).action == Enemy.Action.HIDDEN:
			free.append(i)
	return free


func _rise(enemy: Enemy, point: SpawnPoint, players: int) -> void:
	if world.chunks != null:
		world.chunks.ensure_around(point.position, GROUND_RADIUS)
	enemy.become(point.kind, point.post(), Enemy.Action.IDLE)
	enemy.wake(players)
	SimPlayer._mutate(enemy)
