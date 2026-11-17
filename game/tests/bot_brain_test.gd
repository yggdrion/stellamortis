extends GdUnitTestSuite
## BotBrain (M24): skilled bots beat a swordsman without dying, a novice takes clearly more
## damage, no bot presses faster than its cap, and a seed gives one input sequence. Duels run
## side by side on one flat floor (every duel is a player and a swordsman, far from the rest).

const DELTA := 1.0 / 30.0
const DUELS := 20
const SPACING := 60.0
## Longest duel, in ticks (a minute).
const MAX_TICKS := 1800
const B := PlayerControls.Buttons

## Duel results by skill, shared by the tests (a duel takes a while).
static var _results := {}

var _world: Node3D


## One player against one swordsman.
class Duel:
	extends RefCounted
	var player: SimPlayer
	var enemy: Enemy
	var brain: BotBrain
	var controls := PlayerControls.new()
	var inputs := PackedInt32Array()
	var finished := false

	func won() -> bool:
		return enemy.action == Enemy.Action.DOWN


func before_test() -> void:
	_world = auto_free(Node3D.new()) as Node3D
	add_child(_world)
	FlatGround.box(_world, Vector3(0, -0.5, 0), Vector3(500, 1, 500))


func _skill(id: String) -> BotSkill:
	return load("res://data/bots/%s.tres" % id) as BotSkill


func _duel(skill_id: String, seed_value: int, slot: int) -> Duel:
	var duel := Duel.new()
	var post := Vector3((slot % 5 - 2) * SPACING, 0.0, (slot / 5 - 1.5) * SPACING)
	duel.enemy = Enemy.new()
	duel.enemy.kind = Combat.enemy_kind(&"swordsman")
	duel.enemy.index = slot
	_world.add_child(duel.enemy)
	duel.enemy.home = Transform3D(Basis(Vector3.UP, PI), post)
	duel.enemy.reset(Enemy.Action.IDLE)
	duel.player = SimPlayer.new()
	_world.add_child(duel.player)
	duel.player.place(post + Vector3(0, 0, 8))
	duel.brain = BotBrain.new(_skill(skill_id), &"camp", seed_value)
	duel.brain.me = duel.player
	return duel


## Runs `count` duels of a skill (seeds 1 to count) at once until all are over; returns for each
## whether it was won, how much health it cost, whether the player died and the inputs.
func _fight(skill_id: String, count: int) -> Array[Dictionary]:
	if _results.has(skill_id) and _results[skill_id].size() >= count:
		return _results[skill_id]
	var duels: Array[Duel] = []
	for i in count:
		duels.append(_duel(skill_id, i + 1, i))
	for tick in MAX_TICKS:
		await get_tree().physics_frame
		var open := false
		for duel in duels:
			if duel.finished:
				continue
			duel.enemy._rollback_tick(DELTA, 0, true)
			duel.brain.fill(duel.controls, tick * DELTA)
			var c := duel.controls
			duel.inputs.append(c.buttons)
			duel.player.step(c.move, c.yaw, c.buttons, DELTA, c.pitch, c.weapon)
			duel.finished = duel.won() or duel.player.action == SimPlayer.Action.DEAD
			open = open or not duel.finished
		if not open:
			break
	var found: Array[Dictionary] = []
	for duel in duels:
		(
			found
			. append(
				{
					"won": duel.won(),
					"damage": Tuning.data().max_health - duel.player.health,
					"dead": duel.player.health <= 0.0,
					"inputs": duel.inputs,
				}
			)
		)
		duel.controls.free()
	_results[skill_id] = found
	return found


static func _total_damage(duels: Array[Dictionary]) -> float:
	var total := 0.0
	for duel in duels:
		total += duel["damage"]
	return total


func test_expert_beats_a_swordsman_without_dying() -> void:
	var duels := await _fight("expert", DUELS)
	var wins := 0
	var deaths := 0
	for duel in duels:
		wins += 1 if duel["won"] else 0
		deaths += 1 if duel["dead"] else 0
	assert_int(wins).is_equal(DUELS)
	assert_int(deaths).is_equal(0)


func test_novice_takes_clearly_more_damage_than_expert() -> void:
	var expert := _total_damage(await _fight("expert", DUELS))
	var novice := _total_damage(await _fight("novice", DUELS))
	assert_float(novice).is_greater(expert * 1.5 + DUELS * 5.0)


func test_no_bot_presses_faster_than_its_cap() -> void:
	for id in ["novice", "average", "good", "expert"]:
		var duels := await _fight(id, 6)
		var cap := _skill(id).presses_per_second
		for duel in duels:
			assert_float(_most_presses_in_a_second(duel["inputs"])).is_less_equal(cap)


## The most new button presses (a bit going from up to down) in any second of the inputs.
static func _most_presses_in_a_second(inputs: PackedInt32Array) -> float:
	var times: Array[int] = []
	var most := 0
	var last := 0
	for tick in inputs.size():
		var rising := inputs[tick] & ~last
		last = inputs[tick]
		for bit: int in B.values():
			if rising & bit:
				times.append(tick)
		while not times.is_empty() and times[0] <= tick - Combat.TICKRATE:
			times.pop_front()
		most = maxi(most, times.size())
	return float(most)


## The same seed gives the same inputs against an enemy that winds up on a fixed script, another
## seed does not.
func test_a_seed_gives_one_input_sequence() -> void:
	var logs := await _scripted("good", [7, 7, 8])
	assert_array(logs[0]).is_equal(logs[1])
	assert_array(logs[0]).is_not_equal(logs[2])


## One bot per seed, each against its own swordsman that winds up, strikes and rests by the clock
## (the players stand 1.8 m from them, nothing moves): the inputs of 15 s for each.
func _scripted(skill_id: String, seeds: Array[int]) -> Array:
	var duels: Array[Duel] = []
	var logs := []
	for i in seeds.size():
		var duel := _duel(skill_id, seeds[i], i)
		duel.player.place(duel.enemy.home.origin + Vector3(0, 0, 1.8))
		duels.append(duel)
		logs.append([])
	var swing := duels[0].enemy.attack_def()
	var cycle := Combat.ticks(swing.windup + swing.active + swing.recover) + 30
	for tick in 450:
		await get_tree().physics_frame
		var phase := tick % cycle
		for i in duels.size():
			var duel := duels[i]
			duel.enemy.action_time = phase
			if phase < Combat.ticks(swing.windup):
				duel.enemy.action = Enemy.Action.WINDUP
			elif phase < Combat.ticks(swing.windup + swing.active):
				duel.enemy.action = Enemy.Action.STRIKE
			else:
				duel.enemy.action = Enemy.Action.IDLE
			duel.brain.fill(duel.controls, tick * DELTA)
			var c := duel.controls
			logs[i].append([c.buttons, snappedf(c.yaw, 0.001), snappedf(c.move.x, 0.001)])
	for duel in duels:
		duel.controls.free()
	return logs
