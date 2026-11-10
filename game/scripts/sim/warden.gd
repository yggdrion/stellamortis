class_name Warden
extends Enemy
## The boss (PLAN §4.6): rises when the mobs are dead. A wide sweep (roll through it), a slam
## that hits an area in front of it (roll out of it) and a bolt volley (block or strafe). Below
## half health, phase 2: shorter windups, faster steps, and a gravity well that pulls players
## toward it (a GravityZone, read by Gravity.pull). Health scales with the player count.

enum Move { SWEEP, SLAM, VOLLEY, WELL }

## Rolled back on top of Enemy.STATE and Enemy.ACTOR_STATE.
const EXTRA_STATE := ["max_health", "well_time", "combo"]
const WELLS := &"gravity_wells"
const BASE_HEALTH := 900.0
## Extra health per player beyond the first, as a share of BASE_HEALTH.
const PER_PLAYER := 0.5
const RISE_TIME := 3.0
const TURN_RATE := 3.5
const WELL_TIME := 5.0
const WELL_REACH := 14.0
const WELL_PULL := 11.0
const PHASE_2_PACE := 0.7

## Ticks the well still pulls.
var well_time := 0
## Attacks started since it rose, picks the next one.
var combo := 0


func _init() -> void:
	super()
	set_size(1.2, 4.2)
	attacks = [&"warden_sweep", &"warden_slam", &"warden_volley", &"warden_well"]
	shot_attack = &"warden_volley"
	max_health = BASE_HEALTH
	health = max_health
	stagger_time = 1.8
	riposte = 2.0
	make_bolts(10)
	add_to_group(WELLS)


func phase_2() -> bool:
	return health < max_health / 2.0


func pace() -> float:
	return PHASE_2_PACE if phase_2() else 1.0


## Rises with health for this many players.
func wake(players: int) -> void:
	max_health = BASE_HEALTH * (1.0 + PER_PLAYER * maxi(0, players - 1))
	health = max_health
	combo = 0
	well_time = 0
	_set_action(Action.RISE)
	_sync_body()


func reset(start: Action) -> void:
	max_health = BASE_HEALTH
	well_time = 0
	combo = 0
	super(start)


## The pull while the well is up, null otherwise.
func well_zone() -> GravityZone:
	if well_time <= 0 or not alive():
		return null
	return GravityZone.sphere("gravity well", center(), WELL_REACH, WELL_PULL)


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	action_time += 1
	quiet_time += 1
	well_time = maxi(0, well_time - 1)
	_fly_bolts(delta)
	if action == Action.HIDDEN or action == Action.DOWN:
		_sync_body()
		return
	var target := nearest_player(80.0)
	var wish := Vector3.ZERO
	if action == Action.RISE:
		if action_time >= Combat.ticks(RISE_TIME):
			_set_action(Action.IDLE)
	elif _advance_attack():
		pass
	elif action == Action.STAGGER:
		if action_time >= Combat.ticks(stagger_time):
			_set_action(Action.IDLE)
	elif target:
		wish = _engage(target, delta)
	_walk(wish, 3.8 if phase_2() else 2.8, delta)
	_orient()
	_sync_body()


## Picks the next move by distance and phase; returns where to walk.
func _engage(target: SimPlayer, delta: float) -> Vector3:
	_turn_toward(target.global_position, TURN_RATE, delta)
	var to := SimPlayer._tangent(target.global_position - global_position, up())
	var distance := target.global_position.distance_to(global_position)
	if action_time < Combat.ticks(0.5 if phase_2() else 0.9):
		return to if distance > 4.0 else Vector3.ZERO
	if phase_2() and well_time == 0 and combo % 4 == 3:
		_begin(Move.WELL)
	elif distance < 4.5:
		_begin(Move.SWEEP if combo % 2 == 0 else Move.SLAM)
	elif distance < 18.0 and combo % 3 == 0:
		_begin(Move.VOLLEY)
	elif distance < 18.0 and distance > 8.0 and action_time > Combat.ticks(3.0):
		_begin(Move.VOLLEY)
	else:
		return to
	return Vector3.ZERO


func _begin(move: Move) -> void:
	combo += 1
	_start_attack(move)


func _on_strike(def: AttackDef) -> void:
	if attacks[attack] == &"warden_well":
		well_time = Combat.ticks(WELL_TIME)
		return
	super(def)
