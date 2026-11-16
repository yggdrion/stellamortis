class_name Mob
extends RefCounted
## The skeletons' behavior (PLAN §4.6), run by Enemy._rollback_tick for the MELEE and RANGED
## kinds: wakes when a player comes near, chases within a leash around its post and attacks with a
## telegraph. Melee mobs walk up and chop; the ranged one keeps its distance and shoots bolts
## that fall with gravity. Stays down when killed, until its slot is reset. No state of its own:
## the numbers are the enemy's EnemyDef, the rest is the enemy's rolled back state.


static func tick(enemy: Enemy, delta: float) -> void:
	var ranged := enemy.def.behavior == EnemyDef.Behavior.RANGED
	enemy._fly_bolts(delta)
	if enemy.action == Enemy.Action.DOWN:
		enemy._sync_body()
		return
	var target := _target(enemy)
	var wish := Vector3.ZERO
	if enemy.action == Enemy.Action.RISE:
		enemy._end_rise()
	elif enemy._advance_attack():
		# Melee commits to its swing, ranged keeps aiming through the windup.
		if ranged and target and enemy.action == Enemy.Action.WINDUP:
			enemy._turn_toward(target.global_position, enemy.def.turn_rate, delta)
	elif enemy.action == Enemy.Action.STAGGER:
		if enemy.action_time >= Combat.ticks(enemy.def.stagger_time):
			enemy._set_action(Enemy.Action.IDLE)
	elif enemy.action == Enemy.Action.FLINCH:
		enemy._end_flinch()
	elif enemy.action == Enemy.Action.GUARD:
		enemy._end_guard()
	elif target:
		wish = _engage(enemy, target, ranged, delta)
	elif enemy.global_position.distance_to(enemy.home.origin) > 1.0:
		wish = SimPlayer._tangent(enemy.home.origin - enemy.global_position, enemy.up)
		enemy._turn_toward(enemy.home.origin, enemy.def.turn_rate, delta)
	enemy._walk(wish, enemy.def.speed, delta)
	enemy._orient()
	enemy._sync_body()


## The nearest player it may chase: noticed and within the leash.
static func _target(enemy: Enemy) -> SimPlayer:
	var home := enemy.home.origin
	var target := enemy.nearest_player(enemy.def.notice + enemy.global_position.distance_to(home))
	if target and target.global_position.distance_to(home) > enemy.def.leash:
		return null
	return target


## Turns to the target, attacks when it can and returns where to walk.
static func _engage(enemy: Enemy, target: SimPlayer, ranged: bool, delta: float) -> Vector3:
	var def := enemy.def
	enemy._turn_toward(target.global_position, def.turn_rate, delta)
	var to := SimPlayer._tangent(target.global_position - enemy.global_position, enemy.up)
	var distance := target.global_position.distance_to(enemy.global_position)
	var rested := enemy.action_time >= Combat.ticks(def.rest)
	if ranged:
		if rested and distance < def.keep_far + 4.0 and _in_sight(enemy, target):
			enemy._start_attack(0)
			return Vector3.ZERO
		if distance > def.keep_far:
			return to
		if distance < def.keep_near:
			return -to
		return Vector3.ZERO
	var close := Combat.attack(def.attacks[0]).reach + 0.2
	if rested and distance >= close:
		var closer := _gap_closer(def, distance)
		if closer > 0:
			enemy._start_attack(closer)
			return Vector3.ZERO
	if distance < close:
		if rested:
			enemy._start_attack(0)
		return Vector3.ZERO
	return to


## The attack (after the first) that closes a gap of this distance: a leap or a slam, never one
## that is only a combo's follow-up. 0: none, walk up.
static func _gap_closer(def: EnemyDef, distance: float) -> int:
	for i in range(1, def.attacks.size()):
		var swing := Combat.attack(def.attacks[i])
		var follow := false
		for id in def.attacks:
			follow = follow or Combat.attack(id).next == def.attacks[i]
		if not follow and distance <= swing.gap_range():
			return i
	return 0


static func _in_sight(enemy: Enemy, target: SimPlayer) -> bool:
	return Combat.ray(enemy, enemy.center(), target.center()).is_empty()
