class_name TrainingDummy
extends Enemy
## A skeleton on a post (M2): stands still, turns toward the nearest player and, unless
## passive, swings at anyone in reach on a fixed rhythm, so rolls, blocks and parries can be
## practiced. Heals up after a few quiet seconds, gets back up after going down.

const NOTICE := 10.0
const REST := 1.2
const HEAL_AFTER := 4.0
const TURN_RATE := 6.0

var passive := false


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	action_time += 1
	quiet_time += 1
	var def := attack_def()
	if action != Action.DOWN and quiet_time > Combat.ticks(HEAL_AFTER):
		health = max_health
	match action:
		Action.IDLE:
			var target := nearest_player(NOTICE)
			if target:
				_turn_toward(target.global_position, TURN_RATE, delta)
				var in_reach := (
					target.global_position.distance_to(global_position) < def.reach + 0.5
				)
				if not passive and in_reach and action_time >= Combat.ticks(REST):
					_set_action(Action.WINDUP)
		Action.WINDUP:
			if action_time >= def.windup_ticks():
				_set_action(Action.STRIKE)
		Action.STRIKE:
			if action_time >= Combat.ticks(def.active):
				_set_action(Action.RECOVER)
		Action.RECOVER:
			if action_time >= Combat.ticks(def.recover):
				_set_action(Action.IDLE)
		Action.FLINCH:
			_end_flinch()
		Action.STAGGER:
			if action_time >= Combat.ticks(stagger_time):
				_set_action(Action.IDLE)
		Action.DOWN:
			if action_time >= Combat.ticks(down_time):
				health = max_health
				_set_action(Action.IDLE)
	_orient()
