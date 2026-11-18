extends GdUnitTestSuite
## The roll classes in the simulation (M42 task 1): each Burden rolls, regenerates and walks as
## tuned, OVERLOADED cannot roll, and a class change in the middle of a roll changes nothing.

const DELTA := 1.0 / 30.0
const B := PlayerControls.Buttons

var _player: SimPlayer


func before_test() -> void:
	var world := auto_free(Node3D.new()) as Node3D
	add_child(world)
	FlatGround.add(world)
	_player = SimPlayer.new()
	world.add_child(_player)
	_player.place(Vector3.ZERO)


func _run(ticks: int, buttons := 0, move := Vector2.ZERO) -> void:
	for i in ticks:
		await get_tree().physics_frame
		_player.step(move, 0.0, buttons, DELTA)


func _press(button: int, hold := 1) -> void:
	await _run(hold, button)


## Rolls once from a full stamina bar in the given class; returns what it measured.
func _roll_as(cls: int) -> Dictionary:
	var t := Tuning.data()
	_player.place(Vector3.ZERO)
	_player.burden = cls
	_player.stamina = t.max_stamina
	_player.stamina_wait = 0
	var from := _player.global_position
	await _run(1, B.ROLL, Vector2(0, 1))
	var spent := t.max_stamina - _player.stamina
	var ticks := 1
	var dodged := []
	while _player.action == SimPlayer.Action.ROLL:
		if _player.dodging():
			dodged.append(_player.action_time)
		await _run(1)
		ticks += 1
	return {
		"ticks": ticks,
		"spent": spent,
		"dodged": dodged,
		"distance": _player.global_position.distance_to(from),
	}


func test_each_burden_rolls_as_tuned() -> void:
	var t := Tuning.data()
	var light := await _roll_as(Loadout.Burden.LIGHT)
	for cls in [Loadout.Burden.LIGHT, Loadout.Burden.MEDIUM, Loadout.Burden.HEAVY]:
		var rolled := await _roll_as(cls)
		var label := "class %d" % cls
		assert_int(rolled["ticks"]).override_failure_message(label).is_equal(
			SimPlayer.roll_ticks(t, cls) + 1
		)
		assert_float(rolled["spent"]).override_failure_message(label).is_equal_approx(
			SimPlayer.roll_stamina_of(t, cls), 0.01
		)
		var window := SimPlayer.iframe_ticks(t, cls)
		assert_int(rolled["dodged"].front()).override_failure_message(label).is_equal(window.x)
		assert_int(rolled["dodged"].back()).override_failure_message(label).is_equal(window.y)
		# Distance follows speed times duration; the easing keeps its shape in every class.
		var ratio := float(rolled["distance"]) / float(light["distance"])
		var expected := t.roll_speed_scale[cls] * t.roll_time_scale[cls]
		assert_float(ratio).override_failure_message(label).is_equal_approx(expected, 0.1)


func test_overloaded_cannot_roll_and_attacks_still_start() -> void:
	_player.burden = Loadout.Burden.OVERLOADED
	await _press(B.ROLL)
	assert_int(_player.action).is_equal(SimPlayer.Action.NONE)
	assert_int(_player.queued).is_equal(SimPlayer.Queued.NOTHING)
	await _press(B.ATTACK)
	assert_int(_player.action).is_equal(SimPlayer.Action.ATTACK)


## A roll queued before a gear change does not start once the player is overloaded.
func test_a_queued_roll_does_not_start_when_overloaded() -> void:
	_player.queued = SimPlayer.Queued.ROLL
	_player.burden = Loadout.Burden.OVERLOADED
	await _run(2)
	assert_int(_player.action).is_equal(SimPlayer.Action.NONE)


func test_burden_change_mid_roll_keeps_the_roll() -> void:
	var t := Tuning.data()
	var from := _player.global_position
	await _run(1, B.ROLL, Vector2(0, 1))
	_player.burden = Loadout.Burden.HEAVY
	var ticks := 1
	while _player.action == SimPlayer.Action.ROLL:
		await _run(1)
		ticks += 1
	assert_int(ticks).is_equal(SimPlayer.roll_ticks(t, Loadout.Burden.LIGHT) + 1)
	var light := _player.global_position.distance_to(from)
	assert_float(light).is_greater(3.8)


func test_regen_and_delay_fall_with_burden() -> void:
	var t := Tuning.data()
	var after: Array[float] = []
	for cls in 4:
		_player.burden = cls
		_player.stamina = 10.0
		_player.stamina_wait = 0
		await _run(15)
		after.append(_player.stamina)
		var expected := 10.0 + t.stamina_regen * t.regen_scale[cls] * 15.0 / Combat.TICKRATE
		assert_float(_player.stamina).is_equal_approx(expected, 0.05)
	assert_bool(after[0] > after[1] and after[1] > after[2] and after[2] > after[3]).is_true()
	for cls in 4:
		_player.burden = cls
		_player.stamina = 50.0
		_player._spend(10.0, t)
		assert_int(_player.stamina_wait).is_equal(SimPlayer.delay_ticks(t, cls))
	assert_int(SimPlayer.delay_ticks(t, Loadout.Burden.LIGHT)).is_equal(
		Combat.ticks(t.stamina_delay)
	)
	assert_int(SimPlayer.delay_ticks(t, Loadout.Burden.OVERLOADED)).is_greater(
		SimPlayer.delay_ticks(t, Loadout.Burden.HEAVY)
	)


func test_walk_speed_scales_with_burden() -> void:
	var t := Tuning.data()
	for cls in 4:
		_player.place(Vector3.ZERO)
		_player.burden = cls
		await _run(40, 0, Vector2(0, 1))
		assert_float(_player.velocity.length()).is_equal_approx(
			t.walk_speed * t.move_scale[cls], 0.1
		)
		await _run(40, B.SPRINT, Vector2(0, 1))
		assert_float(_player.velocity.length()).is_equal_approx(
			t.sprint_speed * t.move_scale[cls], 0.1
		)
		_player.stamina = t.max_stamina
