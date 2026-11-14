class_name Warden
extends RefCounted
## The boss's behavior (PLAN §4.6), run by Enemy._rollback_tick for BOSS_WARDEN: rises when the
## mobs are dead. A wide sweep (roll through it), a slam that hits an area in front of it (roll
## out of it) and a bolt volley (block or strafe). Below half health, phase 2: shorter windups,
## faster steps, and a gravity well that pulls players toward it (Enemy.well_zone, read by
## Gravity.pull). Health scales with the player count (Enemy.wake). The numbers are its
## EnemyDef; `attack` indexes the moves below in the def's attack list.

enum Move { SWEEP, SLAM, VOLLEY, WELL }


static func tick(enemy: Enemy, delta: float) -> void:
	enemy.well_time = maxi(0, enemy.well_time - 1)
	enemy._fly_bolts(delta)
	if enemy.action == Enemy.Action.DOWN:
		enemy._sync_body()
		return
	var target := enemy.nearest_player(80.0)
	var wish := Vector3.ZERO
	if enemy.action == Enemy.Action.RISE:
		enemy._end_rise()
	elif enemy._advance_attack():
		pass
	elif enemy.action == Enemy.Action.STAGGER:
		if enemy.action_time >= Combat.ticks(enemy.def.stagger_time):
			enemy._set_action(Enemy.Action.IDLE)
	elif enemy.action == Enemy.Action.FLINCH:
		enemy._end_flinch()
	elif target:
		wish = _engage(enemy, target, delta)
	enemy._walk(wish, enemy.def.phase_2_speed if enemy.phase_2() else enemy.def.speed, delta)
	enemy._orient()
	enemy._sync_body()


## Picks the next move by distance and phase; returns where to walk.
static func _engage(enemy: Enemy, target: SimPlayer, delta: float) -> Vector3:
	enemy._turn_toward(target.global_position, enemy.def.turn_rate, delta)
	var to := SimPlayer._tangent(target.global_position - enemy.global_position, enemy.up)
	var distance := target.global_position.distance_to(enemy.global_position)
	var phase_2 := enemy.phase_2()
	var combo := enemy.combo
	if enemy.action_time < Combat.ticks(0.5 if phase_2 else 0.9):
		return to if distance > 4.0 else Vector3.ZERO
	if phase_2 and enemy.well_time == 0 and combo % 4 == 3:
		_begin(enemy, Move.WELL)
	elif distance < 4.5:
		_begin(enemy, Move.SWEEP if combo % 2 == 0 else Move.SLAM)
	elif distance < 18.0 and combo % 3 == 0:
		_begin(enemy, Move.VOLLEY)
	elif distance < 18.0 and distance > 8.0 and enemy.action_time > Combat.ticks(3.0):
		_begin(enemy, Move.VOLLEY)
	else:
		return to
	return Vector3.ZERO


static func _begin(enemy: Enemy, move: Move) -> void:
	enemy.combo += 1
	enemy._start_attack(move)
