class_name TrainingDummy
extends RefCounted
## A skeleton on a post (M2), the DUMMY behavior run by Enemy._rollback_tick: stands still,
## turns toward the nearest player and, unless passive, swings at anyone in reach on a fixed
## rhythm, so rolls, blocks and parries can be practiced. Heals up after a few quiet seconds,
## gets back up after going down.


static func tick(enemy: Enemy, delta: float) -> void:
	var def := enemy.def
	var swing := enemy.attack_def()
	if enemy.action != Enemy.Action.DOWN and enemy.quiet_time > Combat.ticks(def.heal_after):
		enemy.health = enemy.max_health
	match enemy.action:
		Enemy.Action.IDLE:
			var target := enemy.nearest_player(def.notice)
			if target:
				enemy._turn_toward(target.global_position, def.turn_rate, delta)
				var in_reach := (
					target.global_position.distance_to(enemy.global_position) < swing.reach + 0.5
				)
				if not enemy.passive and in_reach and enemy.action_time >= Combat.ticks(def.rest):
					enemy._set_action(Enemy.Action.WINDUP)
		Enemy.Action.WINDUP:
			if enemy.action_time >= swing.windup_ticks():
				enemy._set_action(Enemy.Action.STRIKE)
		Enemy.Action.STRIKE:
			if enemy.action_time >= Combat.ticks(swing.active):
				enemy._set_action(Enemy.Action.RECOVER)
		Enemy.Action.RECOVER:
			if enemy.action_time >= Combat.ticks(swing.recover):
				enemy._set_action(Enemy.Action.IDLE)
		Enemy.Action.FLINCH:
			enemy._end_flinch()
		Enemy.Action.STAGGER:
			if enemy.action_time >= Combat.ticks(def.stagger_time):
				enemy._set_action(Enemy.Action.IDLE)
		Enemy.Action.DOWN:
			if enemy.action_time >= Combat.ticks(def.down_time):
				enemy.health = enemy.max_health
				enemy._set_action(Enemy.Action.IDLE)
	enemy._orient()
