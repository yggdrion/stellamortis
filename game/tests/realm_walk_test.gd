extends GdUnitTestSuite
## The streamed realm collision (M20 task 3) with the real SimPlayer: walking a great circle,
## across a cube face edge, jumping, freeing chunks behind, replaying a rolled back state, steep
## slopes, and the realm's far side from the origin (32 bit floats).

const DELTA := 1.0 / 30.0
const SEED := 1234
## Ticks run per physics frame (the headless runner keeps real time, 30 frames a second), so
## 500 m take seconds and not minutes. Streaming sees the player 6 times as fast as in a game.
const TICKS_PER_FRAME := 6
const SPRINT := PlayerControls.Buttons.SPRINT
## How far below the height function the feet may be: triangles cut the curve between vertices.
const BELOW := 0.3
## Standing still on the far side may not move the feet by more than this (m).
const JITTER := 0.005
const WALKABLE_DEGREES := 50.0
## Normals come from the height function, the collision from triangles.
const SLOPE_SLACK_DEGREES := 6.0
## The mob walk: a player this far (m) ahead of it, LEGS times.
const LEG := 12.0
const LEGS := 6

var _realm: RealmDef
var _field: Terrain.Field
var _chunks: TerrainChunks
var _player: SimPlayer


func before_test() -> void:
	_realm = Layout.realms()[0]
	_field = Terrain.Field.new(_realm, SEED)
	_chunks = auto_free(TerrainChunks.new(SEED)) as TerrainChunks
	_chunks.anchors = func() -> Array: return [_player]
	add_child(_chunks)


func _spawn(direction: Vector3, forward := Vector3.FORWARD) -> void:
	_player = auto_free(SimPlayer.new()) as SimPlayer
	add_child(_player)
	var feet := _realm.center + _field.surface(direction) + direction * 0.05
	_player.place(feet, forward)


## Meters above the height function under the player.
func _over() -> float:
	var local := _player.global_position - _realm.center
	return local.length() - (_realm.radius + _field.height(local.normalized()))


## One tick of input. Returns the height over the ground.
func _tick(move: Vector2, yaw := 0.0, buttons := 0) -> float:
	_player.stamina = 100.0
	_player.step(move, yaw, buttons, DELTA)
	return _over()


## Runs ticks, TICKS_PER_FRAME per physics frame (the first frame presses buttons for one tick
## unless hold). Returns the lowest height over the ground and the ticks spent grounded.
func _walk(ticks: int, move := Vector2(0, 1), buttons := 0, hold := false) -> Dictionary:
	var lowest := INF
	var grounded := 0
	for i in ticks:
		if i % TICKS_PER_FRAME == 0:
			await get_tree().physics_frame
		lowest = minf(lowest, _tick(move, 0.0, buttons if hold or i == 0 else 0))
		grounded += 1 if _player.grounded else 0
	return {"lowest": lowest, "grounded": grounded}


func _settle() -> void:
	await _walk(20, Vector2.ZERO)


func _arc(from: Vector3, to: Vector3) -> float:
	return (from - _realm.center).angle_to(to - _realm.center) * _realm.radius


func test_walk_500_m_great_circle() -> void:
	_spawn(_realm.arrival)
	_chunks.ensure_around(_player.global_position)
	await _settle()
	var start := _player.global_position
	var start_key: Variant = _chunks.key_at(start)
	var started := Time.get_ticks_msec()
	# 62 s of sprinting (8 m/s).
	var result: Dictionary = await _walk(1900, Vector2(0, 1), SPRINT, true)
	print(
		(
			"walk 500 m: %d ms, lowest %.3f m, chunks %d"
			% [Time.get_ticks_msec() - started, result.lowest, _chunks.bodies.size()]
		)
	)
	assert_float(_arc(start, _player.global_position)).is_greater(450.0)
	assert_float(result.lowest).is_greater(-BELOW)
	assert_float(result.grounded / 1900.0).is_greater(0.9)
	# Chunks behind were freed, and the set around us stayed small.
	assert_bool(_chunks.bodies.has(start_key)).is_false()
	assert_int(_chunks.bodies.size()).is_less(80)
	assert_bool(_chunks.bodies.has(_chunks.key_at(_player.global_position))).is_true()


func test_walk_across_cube_face_edge() -> void:
	# 38 degrees from the pole towards -Z: the +Y face ends at 45 degrees, 122 m ahead.
	var tilt := deg_to_rad(38.0)
	_spawn(Vector3(0, cos(tilt), -sin(tilt)))
	_chunks.ensure_around(_player.global_position)
	await _settle()
	var faces := {}
	var lowest := INF
	for i in 900:
		if i % TICKS_PER_FRAME == 0:
			await get_tree().physics_frame
		lowest = minf(lowest, _tick(Vector2(0, 1), 0.0, SPRINT))
		var local := _player.global_position - _realm.center
		faces[Terrain.chunk_at(_realm, local.normalized()).x] = true
	assert_int(faces.size()).is_greater_equal(2)
	assert_float(lowest).is_greater(-BELOW)


func test_jump_lands() -> void:
	_spawn(_realm.arrival)
	_chunks.ensure_around(_player.global_position)
	await _settle()
	var result: Dictionary = await _walk(75, Vector2.ZERO, PlayerControls.Buttons.JUMP)
	assert_bool(_player.grounded).is_true()
	assert_float(result.lowest).is_greater(-BELOW)
	assert_float(absf(_over())).is_less(BELOW)
	assert_int(result.grounded).is_less(75)


func _copy(value: Variant) -> Variant:
	return value.duplicate() if typeof(value) >= TYPE_ARRAY else value


func _snapshot() -> Dictionary:
	var state := {}
	for property: String in SimPlayer.STATE:
		var value: Variant = _player.get(property)
		state[property] = _copy(value)
	return state


func _restore(state: Dictionary) -> void:
	for property: String in state:
		var value: Variant = state[property]
		_player.set(property, _copy(value))


func _replay(ticks: int) -> Array[Vector3]:
	var trace: Array[Vector3] = []
	for i in ticks:
		if i % TICKS_PER_FRAME == 0:
			await get_tree().physics_frame
		_tick(Vector2(sin(i * 0.05), 1), i * 0.01)
		trace.append(_player.global_position)
		trace.append(_player.velocity)
	return trace


func test_replay_from_rolled_back_state_is_identical() -> void:
	_spawn(_realm.arrival)
	_chunks.ensure_around(_player.global_position)
	await _settle()
	await _walk(120)
	var state := _snapshot()
	var first := await _replay(400)
	var first_loaded := _chunks.bodies.keys()
	_restore(state)
	var second := await _replay(400)
	assert_int(second.size()).is_equal(first.size())
	var same := true
	for i in first.size():
		same = same and first[i] == second[i]
	assert_bool(same).is_true()
	# Streaming ran meanwhile (the walk moved on 65 m each time) and did not change the result.
	assert_bool(first_loaded.size() > 0).is_true()


func test_far_side_does_not_jitter() -> void:
	var far := _realm.center.normalized()
	far.y = 0.0
	far = far.normalized()
	var results := {}
	for direction: Vector3 in [far, -far]:
		_spawn(direction)
		_chunks.ensure_around(_player.global_position)
		await _settle()
		await _walk(30, Vector2.ZERO)
		var low := INF
		var high := -INF
		var at := _player.global_position
		var moved := 0.0
		for i in 90:
			await get_tree().physics_frame
			var over := _tick(Vector2.ZERO)
			low = minf(low, over)
			high = maxf(high, over)
			moved = maxf(moved, _player.global_position.distance_to(at))
		results[direction] = [high - low, moved, _player.global_position.length()]
	print(
		(
			"jitter far side (%.0f m from origin): over %.6f moved %.6f; near side (%.0f m): %.6f %.6f"
			% [
				results[far][2],
				results[far][0],
				results[far][1],
				results[-far][2],
				results[-far][0],
				results[-far][1]
			]
		)
	)
	assert_float(results[far][0]).is_less(JITTER)
	assert_float(results[far][1]).is_less(JITTER)


## A hillside steeper than the walk limit is not climbed as stairs (SimPlayer._step_up).
func test_steep_slope_is_not_climbed() -> void:
	var steepest := Vector3.UP
	var worst := 0.0
	for direction in Terrain.sample_directions(4000):
		var tilt := Terrain._normal(_field, direction).angle_to(direction)
		if tilt > worst:
			worst = tilt
			steepest = direction
	print("steepest sampled slope: %.1f degrees" % rad_to_deg(worst))
	var normal := Terrain._normal(_field, steepest)
	var uphill := -(normal - steepest * normal.dot(steepest)).normalized()
	# Start a few meters below it, on the way up, with the camera looking uphill.
	var below := (steepest * _realm.radius - uphill * 4.0).normalized()
	_spawn(below, uphill)
	_chunks.ensure_around(_player.global_position)
	await _settle()
	var yaw := _player.ref_forward.signed_angle_to(uphill, _player.up)
	var climbed := 0
	for i in 150:
		await get_tree().physics_frame
		_tick(Vector2(0, 1), yaw)
		var local := (_player.global_position - _realm.center).normalized()
		var slope := rad_to_deg(Terrain._normal(_field, local).angle_to(local))
		if _player.grounded and slope > WALKABLE_DEGREES + SLOPE_SLACK_DEGREES:
			climbed += 1
	assert_int(climbed).is_equal(0)


## --- Enemies on the realm (M21 task 1): they stand and walk along the local gravity. ---


func _feet(direction: Vector3) -> Vector3:
	return _realm.center + _field.surface(direction) + direction * 0.05


## A mob standing on the realm ground in a direction (its post), facing forward.
func _mob_at(direction: Vector3, ranged := false) -> Mob:
	var mob := auto_free(Mob.new()) as Mob
	if ranged:
		mob.make_ranged()
	else:
		mob.make_melee()
	mob.home = Transform3D(SimPlayer.frame(direction, Vector3.FORWARD), _feet(direction))
	add_child(mob)
	mob.reset(Enemy.Action.IDLE)
	return mob


## One tick of the mob (and of the player when it is stepped), TICKS_PER_FRAME per frame.
func _mob_ticks(mob: Mob, ticks: int, step_player := false) -> void:
	for i in ticks:
		if i % TICKS_PER_FRAME == 0:
			await get_tree().physics_frame
		_player.health = 100.0
		mob._rollback_tick(DELTA, 0, true)
		if step_player:
			_tick(Vector2.ZERO)


## Meters above the height function under a point.
func _over_ground(point: Vector3) -> float:
	var local := point - _realm.center
	return local.length() - (_realm.radius + _field.height(local.normalized()))


## The direction `arc` meters further along the great circle around axis.
func _ahead(from: Vector3, axis: Vector3, arc: float) -> Vector3:
	return from.rotated(axis, arc / _realm.radius)


## The axis of the great circle through a direction, heading forward (-Z).
func _axis(from: Vector3) -> Vector3:
	return from.cross(SimPlayer._tangent(Vector3.FORWARD, from)).normalized()


func test_mob_chases_a_player_over_the_hills_and_stays_on_the_ground() -> void:
	var start := _realm.arrival
	var axis := _axis(start)
	_spawn(start)
	var mob := _mob_at(start)
	_chunks.ensure_around(mob.global_position)
	var low := INF
	var high := -INF
	var low_ground := INF
	var worst := 0.0
	var direction := start
	for leg in LEGS:
		direction = _ahead(direction, axis, LEG)
		var feet := _feet(direction)
		_chunks.ensure_around(feet)
		_player.place(feet)
		mob.home.origin = feet
		await _mob_ticks(mob, 150)
		var local := mob.global_position - _realm.center
		low = minf(low, _over_ground(mob.global_position))
		high = maxf(high, _field.height(local.normalized()))
		low_ground = minf(low_ground, _field.height(local.normalized()))
		worst = maxf(worst, mob.up.angle_to(local.normalized()))
	var walked := _arc(_feet(start), mob.global_position)
	print(
		(
			"mob walked %.0f m, lowest %.3f m, up off by %.1f degrees"
			% [walked, low, rad_to_deg(worst)]
		)
	)
	print("ground heights %.1f to %.1f m" % [low_ground, high])
	assert_float(high - low_ground).is_greater(1.0)
	assert_float(walked).is_greater(55.0)
	assert_float(low).is_greater(-BELOW)
	assert_float(_over_ground(mob.global_position)).is_less(BELOW + 0.5)
	# Its up is the local gravity's opposite (the terrain is not the sphere: slack for the lag
	# of 0.25 s up_turn_time while it walks).
	assert_float(rad_to_deg(worst)).is_less(8.0)
	assert_vector(mob.global_basis.y).is_equal_approx(mob.up, Vector3.ONE * 0.001)
	assert_float(mob.global_position.distance_to(_player.global_position)).is_less(6.0)


func test_ranged_mob_bolts_hit_on_the_realm() -> void:
	var start := _realm.arrival
	_spawn(_ahead(start, _axis(start), 11.0))
	var mob := _mob_at(start, true)
	_chunks.ensure_around(mob.global_position)
	await _settle()
	_player.health = 100.0
	var lowest := 100.0
	for i in 240:
		if i % TICKS_PER_FRAME == 0:
			await get_tree().physics_frame
		mob._rollback_tick(DELTA, 0, true)
		_tick(Vector2.ZERO)
		lowest = minf(lowest, _player.health)
	assert_float(lowest).is_less(100.0)
	assert_vector(mob.global_basis.y).is_equal_approx(mob.up, Vector3.ONE * 0.001)


func test_mob_replay_from_rolled_back_state_is_identical() -> void:
	var start := _realm.arrival
	_spawn(_ahead(start, _axis(start), 30.0))
	var mob := _mob_at(start)
	mob.home.origin = _player.global_position
	_chunks.ensure_around(_player.global_position)
	await _mob_ticks(mob, 60)
	var state := {}
	for property: String in Enemy.STATE + Enemy.ACTOR_STATE:
		state[property] = _copy(mob.get(property))
	var traces: Array = []
	for run in 2:
		for property: String in state:
			mob.set(property, _copy(state[property]))
		var trace: Array[Vector3] = []
		for i in 150:
			if i % TICKS_PER_FRAME == 0:
				await get_tree().physics_frame
			_player.health = 100.0
			mob._rollback_tick(DELTA, 0, true)
			trace.append(mob.global_position)
			trace.append(mob.up)
		traces.append(trace)
	assert_array(traces[1]).is_equal(traces[0])
