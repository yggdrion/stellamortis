class_name Mob
extends Enemy
## An encounter skeleton (PLAN §4.6): wakes when a player comes near, chases within a leash
## around its post and attacks with a telegraph. Melee mobs walk up and chop; the ranged one
## keeps its distance and shoots bolts that fall with gravity. Stays down when killed, until
## the encounter resets.

const NOTICE := 16.0
## It gives up on players this far from its post and walks back.
const LEASH := 24.0
const TURN_RATE := 6.0
## Ranged: the distance band it tries to keep.
const KEEP_NEAR := 7.0
const KEEP_FAR := 13.0

var ranged := false
var speed := 3.6
## Seconds between attacks.
var rest := 0.8


func _init() -> void:
	super()
	max_health = 90.0
	health = max_health
	stagger_time = 1.4


## Makes it the ranged kind (before it enters the tree).
func make_ranged() -> void:
	ranged = true
	attacks = [&"mob_shot"]
	shot_attack = &"mob_shot"
	speed = 3.0
	rest = 1.6
	max_health = 70.0
	health = max_health
	make_bolts(2)


func make_melee() -> void:
	ranged = false
	attacks = [&"mob_chop"]


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	action_time += 1
	quiet_time += 1
	_fly_bolts(delta)
	if action == Action.HIDDEN or action == Action.DOWN:
		_sync_body()
		return
	var target := _target()
	var wish := Vector3.ZERO
	if _advance_attack():
		# Melee commits to its swing, ranged keeps aiming through the windup.
		if ranged and target and action == Action.WINDUP:
			_turn_toward(target.global_position, TURN_RATE, delta)
	elif action == Action.STAGGER:
		if action_time >= Combat.ticks(stagger_time):
			_set_action(Action.IDLE)
	elif target:
		wish = _engage(target, delta)
	elif global_position.distance_to(home.origin) > 1.0:
		wish = SimPlayer._tangent(home.origin - global_position, up())
		_turn_toward(home.origin, TURN_RATE, delta)
	_walk(wish, speed, delta)
	_orient()
	_sync_body()


## The nearest player it may chase: noticed and within the leash.
func _target() -> SimPlayer:
	var target := nearest_player(NOTICE + global_position.distance_to(home.origin))
	if target and target.global_position.distance_to(home.origin) > LEASH:
		return null
	return target


## Turns to the target, attacks when it can and returns where to walk.
func _engage(target: SimPlayer, delta: float) -> Vector3:
	_turn_toward(target.global_position, TURN_RATE, delta)
	var to := SimPlayer._tangent(target.global_position - global_position, up())
	var distance := target.global_position.distance_to(global_position)
	var rested := action_time >= Combat.ticks(rest)
	if ranged:
		if rested and distance < KEEP_FAR + 4.0 and _in_sight(target):
			_start_attack(0)
			return Vector3.ZERO
		if distance > KEEP_FAR:
			return to
		if distance < KEEP_NEAR:
			return -to
		return Vector3.ZERO
	if distance < attack_def().reach + 0.2:
		if rested:
			_start_attack(0)
		return Vector3.ZERO
	return to


func _in_sight(target: SimPlayer) -> bool:
	return Combat.ray(self, center(), target.center()).is_empty()
