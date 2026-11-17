class_name BotBrain
extends RefCounted
## A bot that plays like a person of a skill (M24): it fills PlayerControls where a person's
## input would go, from what a client sees (its own SimPlayer, the players, enemies and drops in
## the world as this client predicts and interpolates them, enemy actions as the telegraph a
## player sees) and nothing else. It never reads server state and calls no sim decision function
## (only pure geometry: Combat.in_arc, Combat.aim_basis, Combat.ray). Every observation (also the
## own health) goes through a delay queue first, so the bot reacts as late as its skill says.
## All randomness comes from the bot's seed; the same observations give the same inputs.
##
## What it does, in this order: dead: nothing; a telegraph it chose to answer: EVADE (a roll, a
## parry or a block, timed from the enemy's windup); an enemy it wants within reach of its eyes:
## ENGAGE (melee combos, or draws of the crossbow in the ranged role), or RECOVER when stamina or
## health ran low (backs away, eats a bandage); else the BODY run to where it died, LOOT, FOLLOW
## the party, or TRAVEL to the goal (a camp cleared is left alone).

enum State { TRAVEL, ENGAGE, EVADE, RECOVER, LOOT, BODY, FOLLOW }
enum Evade { NONE, ROLL, PARRY, BLOCK }
enum Slip { NONE, PANIC, INTO, WRONG_WAY }

const TICK := 1.0 / Combat.TICKRATE

## The bot's state this frame (tests and logs read it), and what it has killed.
var state := State.TRAVEL
var kills := 0
var skill: BotSkill
## camp, boss, roam, dummy or follow.
var goal: StringName = &"camp"
var me: SimPlayer
## Role: the crossbow instead of the sword.
var ranged := false
## Where to walk when it has nowhere known to go (null: it searches).
var goal_point: Variant = null
## Returns where the objects it could take lie (an Array of Vector3), and eats what heals.
var drops: Callable
var heal: Callable

var _rng := RandomNumberGenerator.new()
var _queue: Array[Seen] = []
var _last_ready := 0.0
var _last_now := 0.0
var _plans := {}
var _alive := {}
var _target_index := -1
## What this frame wants.
var _wish := Vector3.ZERO
var _look: Variant = null
var _aim: Variant = null
var _held := 0
var _taps := {}
var _bias_yaw := 0.0
var _bias_pitch := 0.0
var _bias_at := 0.0
var _last_out := 0
var _press_log: Array[float] = []
## Combo bookkeeping: links pressed so far, when the next link goes in, when the swing is over.
var _chain_n := 0
var _chain_id: StringName = &"light_1"
var _chain_link_at := INF
var _chain_ends := 0.0
var _rest_until := 0.0
var _recover_until := 0.0
var _armed := true
var _stamina_low := false
var _next_heal := 0.0
var _drawing := false
var _draw_end := 0.0
var _draw_rest := 0.0
var _dead := false
var _death_point := Vector3.ZERO
var _body_until := -1.0
var _search := Vector3.ZERO
var _search_until := -1.0
var _last_foe_at := 0.0
var _sprinting := false
var _following := false
var _loot_at := Vector3.INF
var _loot_since := 0.0
var _ignored: Array[Vector3] = []


func _init(bot_skill: BotSkill, bot_goal: StringName, seed_value: int) -> void:
	skill = bot_skill
	goal = bot_goal
	_rng.seed = seed_value


## Fills the controls for this tick loop; `now` is seconds on any steady clock.
func fill(controls: PlayerControls, now: float) -> void:
	var dt := clampf(now - _last_now, 0.0, 0.25)
	_last_now = now
	_observe(now)
	_wish = Vector3.ZERO
	_look = null
	_aim = null
	_held = 0
	controls.weapon = SimPlayer.Weapon.CROSSBOW if ranged else SimPlayer.Weapon.SWORD
	var view := _view(now)
	if view != null:
		_think(view, now, dt)
	_output(controls, now)


# --- Observing ------------------------------------------------------------------------------


## What one frame looked like, and when the brain may act on it.
class Seen:
	extends RefCounted
	var t := 0.0
	var ready := 0.0
	var health := 0.0
	var stamina := 0.0
	var action := SimPlayer.Action.NONE
	var foes: Array[Foe] = []
	var drops: Array[Vector3] = []
	var leader: Variant = null


## An enemy as seen: where, what it is doing and the attack it runs (the telegraph).
class Foe:
	extends RefCounted
	var index := 0
	var kind: StringName = &""
	var pos := Vector3.ZERO
	var center := Vector3.ZERO
	var facing := Vector3.FORWARD
	var action := Enemy.Action.IDLE
	var action_time := 0
	var radius := 0.5
	var parried := false
	var swing: AttackDef
	var windup := 0.0


## An answer to one enemy swing: what to press and when (seconds on the brain's clock).
class Plan:
	extends RefCounted
	var kind := Evade.NONE
	var slip := Slip.NONE
	var start := 0.0
	var strike_at := 0.0
	var press_at := 0.0
	var end_at := 0.0
	var fired := false
	var move_until := 0.0
	var roll_dir := Vector3.ZERO
	var side := 1.0


func _observe(now: float) -> void:
	var seen := Seen.new()
	seen.t = now
	var delay := maxf(0.0, _rng.randfn(skill.reaction_ms, skill.reaction_spread_ms)) / 1000.0
	_last_ready = maxf(_last_ready, now + delay)
	seen.ready = _last_ready
	seen.health = me.health
	seen.stamina = me.stamina
	seen.action = me.action
	var tree := me.get_tree()
	for node in tree.get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy.action == Enemy.Action.HIDDEN or enemy.attack >= enemy.def.attacks.size():
			continue
		if enemy.global_position.distance_to(me.global_position) <= skill.sight:
			seen.foes.append(_foe_of(enemy))
	var lowest := 0
	for node in tree.get_nodes_in_group(SimPlayer.GROUP):
		var other := node as SimPlayer
		if other != me and other.action != SimPlayer.Action.DEAD:
			if seen.leader == null or other.peer_id < lowest:
				lowest = other.peer_id
				seen.leader = other.global_position
	if drops.is_valid():
		seen.drops.assign(drops.call())
	_queue.append(seen)


static func _foe_of(enemy: Enemy) -> Foe:
	var foe := Foe.new()
	foe.index = enemy.index
	foe.kind = Combat.ENEMY_KINDS[enemy.kind]
	foe.pos = enemy.global_position
	foe.center = enemy.center()
	foe.facing = enemy.facing
	foe.action = enemy.action
	foe.action_time = enemy.action_time
	foe.radius = enemy.radius
	foe.parried = enemy.parried
	foe.swing = enemy.attack_def()
	foe.windup = enemy.windup_ticks() * TICK
	return foe


## The newest observation that is old enough, null before the first one is.
func _view(now: float) -> Seen:
	while _queue.size() > 1 and _queue[1].ready <= now:
		_queue.pop_front()
	return _queue[0] if _queue[0].ready <= now else null


## Notes deaths and kills, and makes a plan for every swing that begins.
func _track(view: Seen, now: float) -> void:
	if view.action == SimPlayer.Action.DEAD:
		if not _dead:
			_dead = true
			_death_point = me.global_position
			_plans.clear()
			_chain_n = 0
			_drawing = false
	elif _dead:
		_dead = false
		if _flat(_death_point - me.global_position).length() > 8.0:
			_body_until = now + skill.body_seconds
	for foe in view.foes:
		if foe.action != Enemy.Action.DOWN:
			_alive[foe.index] = true
		elif _alive.erase(foe.index):
			kills += 1
		if foe.action != Enemy.Action.WINDUP:
			continue
		var start := view.t - foe.action_time * TICK
		var plan := _plans.get(foe.index) as Plan
		if plan == null or absf(plan.start - start) > 0.25:
			_plans[foe.index] = _plan(foe, start, now)


# --- Answering telegraphs -------------------------------------------------------------------


## Decides how (and whether) to answer a swing, and when to press.
func _plan(foe: Foe, start: float, now: float) -> Plan:
	var t := Tuning.data()
	var swing := foe.swing
	var plan := Plan.new()
	plan.start = start
	plan.strike_at = start + foe.windup
	if swing.bolts > 0:
		plan.strike_at += _dist(foe) / swing.bolt_speed
	plan.end_at = plan.strike_at + swing.active + 0.2
	plan.side = 1.0 if _rng.randf() < 0.5 else -1.0
	var roll_at := plan.strike_at - (t.roll_iframes_start + t.roll_iframes_end) / 2.0
	roll_at += swing.active / 2.0 - TICK
	if _rng.randf() < skill.mistake_rate:
		plan.slip = _rng.randi_range(1, 3) as Slip
	match plan.slip:
		Slip.PANIC:
			plan.kind = Evade.ROLL
			plan.press_at = roll_at + _rng.randf_range(0.25, 0.5) * plan.side
		Slip.WRONG_WAY:
			plan.kind = Evade.ROLL
			plan.press_at = roll_at + _rng.randfn(0.0, skill.dodge_error_ms) / 1000.0
		Slip.NONE:
			var parry := swing.parryable and swing.bolts == 0
			if parry and _rng.randf() < skill.parry_chance:
				plan.kind = Evade.PARRY
				plan.press_at = plan.strike_at - t.parry_window / 2.0 - TICK
				plan.press_at += _rng.randfn(0.0, skill.parry_error_ms) / 1000.0
			elif _rng.randf() < skill.dodge_chance:
				plan.kind = Evade.ROLL
				plan.press_at = roll_at + _rng.randfn(0.0, skill.dodge_error_ms) / 1000.0
			elif _rng.randf() < skill.block_chance:
				plan.kind = Evade.BLOCK
				plan.press_at = plan.strike_at - 0.35
				plan.press_at += _rng.randfn(0.0, skill.block_error_ms) / 1000.0
	# Seen too late to still press in time.
	if plan.kind != Evade.NONE and plan.end_at < now + TICK:
		plan.kind = Evade.NONE
	return plan


## Presses what the plans say now; true while an answer takes over the controls.
func _evade(view: Seen, now: float) -> bool:
	var busy := false
	for index: int in _plans.keys():
		var plan: Plan = _plans[index]
		if now > plan.end_at + 0.5:
			_plans.erase(index)
			continue
		if plan.kind == Evade.ROLL and plan.fired:
			if now < plan.move_until:
				_wish = plan.roll_dir
				busy = true
			continue
		var foe := _foe_at(view, index)
		if plan.kind == Evade.NONE or foe == null or now < plan.press_at or now > plan.end_at:
			continue
		if not plan.fired and not _threat(foe):
			plan.kind = Evade.NONE
			continue
		var to := _flat(foe.pos - me.global_position).normalized()
		plan.fired = true
		_chain_n = 0
		_drawing = false
		if plan.kind == Evade.ROLL:
			plan.roll_dir = to if plan.slip == Slip.WRONG_WAY else _side_step(to, plan.side)
			plan.move_until = now + skill.tap_seconds + TICK
			_tap(PlayerControls.Buttons.ROLL, now)
			_wish = plan.roll_dir
		else:
			_held |= PlayerControls.Buttons.BLOCK
			_look = to
		busy = true
	return busy


## Sideways to the enemy, a little away from it.
func _side_step(to: Vector3, side: float) -> Vector3:
	return (me.up.cross(to) * side * 0.8 - to * 0.4).normalized()


func _foe_at(view: Seen, index: int) -> Foe:
	for foe in view.foes:
		if foe.index == index:
			return foe
	return null


## Whether a swing of this enemy would reach the bot (a little generously).
func _threat(foe: Foe) -> bool:
	var swing := foe.swing
	if swing.bolts > 0:
		return _dist(foe) < 60.0
	if swing.leap > 0.0:
		return _dist(foe) <= swing.leap + swing.reach + 0.5
	var origin := foe.center + foe.facing * swing.offset
	return Combat.in_arc(
		origin,
		foe.facing,
		me.up,
		swing.reach + 0.5,
		swing.arc_degrees,
		me.center(),
		SimPlayer.RADIUS
	)


## Whether an answer is due before a swing of `commit` seconds would be over.
func _attack_blocked(now: float, commit: float) -> bool:
	for index: int in _plans:
		var plan: Plan = _plans[index]
		if plan.kind != Evade.NONE and now < plan.end_at and plan.press_at < now + commit + 0.05:
			return true
	return false


# --- Deciding -------------------------------------------------------------------------------


func _think(view: Seen, now: float, dt: float) -> void:
	_track(view, now)
	if _dead:
		return
	_update_bias(now, dt)
	var foe := _pick(view)
	if foe != null or _any_foe(view):
		_last_foe_at = now
	if _evade(view, now):
		state = State.EVADE
	elif foe != null and _recovering(view, now):
		state = State.RECOVER
		_back_away(foe)
	elif foe != null:
		state = State.ENGAGE
		if ranged:
			_shoot(view, now, foe)
		else:
			_melee(view, now, foe)
	else:
		_idle(view, now)


## Without a target: the body run, loot, following, the goal.
func _idle(view: Seen, now: float) -> void:
	var near := _nearest_drop(view, now)
	if _body_until > now:
		state = State.BODY
		if _go(view, _death_point) < 2.5:
			_body_until = -1.0
	elif near.is_finite():
		state = State.LOOT
		if _go(view, near, false) < 1.5:
			_wish = Vector3.ZERO
	elif goal == &"follow" and view.leader != null:
		state = State.FOLLOW
		_follow(view)
	elif goal == &"camp" and kills > 0 and now - _last_foe_at >= skill.camp_quiet:
		state = State.TRAVEL
	elif goal_point != null and _go(view, goal_point) < 3.0:
		state = State.TRAVEL
		_wish = Vector3.ZERO
	else:
		state = State.TRAVEL
		if goal_point == null:
			_wander(now)


func _follow(view: Seen) -> void:
	var dist := _flat(view.leader - me.global_position).length()
	if dist > skill.follow_far:
		_following = true
	elif dist < skill.follow_near:
		_following = false
	if _following:
		_go(view, view.leader)


## The nearest living enemy the goal wants within notice, with a little loyalty to the last one.
func _pick(view: Seen) -> Foe:
	var best: Foe = null
	var best_distance := skill.notice
	for foe in view.foes:
		if foe.action == Enemy.Action.DOWN or not _wants(foe):
			continue
		var distance := _dist(foe) - (3.0 if foe.index == _target_index else 0.0)
		if distance < best_distance:
			best = foe
			best_distance = distance
	_target_index = best.index if best != null else -1
	return best


func _wants(foe: Foe) -> bool:
	match goal:
		&"dummy":
			return foe.kind == &"dummy"
		&"boss":
			return foe.kind == &"warden"
	return foe.kind != &"dummy"


func _any_foe(view: Seen) -> bool:
	for foe in view.foes:
		if foe.action != Enemy.Action.DOWN and foe.kind != &"dummy":
			return true
	return false


## Low on stamina or health: back away until it has both again (health only for a while).
func _recovering(view: Seen, now: float) -> bool:
	var t := Tuning.data()
	if view.health < skill.retreat_health * t.max_health:
		if _armed:
			_armed = false
			_recover_until = now + skill.recover_seconds
		if heal.is_valid() and now >= _next_heal:
			_next_heal = now + 2.5
			heal.call()
	else:
		_armed = true
	if view.stamina < skill.stamina_reserve * 0.6:
		_stamina_low = true
	elif view.stamina >= skill.stamina_reserve + skill.recover_margin:
		_stamina_low = false
	return now < _recover_until or _stamina_low


func _back_away(foe: Foe) -> void:
	_chain_n = 0
	_drawing = false
	var to := _flat(foe.pos - me.global_position)
	_look = to.normalized()
	if to.length() < skill.ranged_near + 2.0:
		_wish = -to.normalized()


# --- Fighting -------------------------------------------------------------------------------


func _melee(view: Seen, now: float, foe: Foe) -> void:
	var to := _flat(foe.pos - me.global_position)
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	_look = dir
	var light := Combat.attack(&"light_1")
	var stand := light.reach * 0.7 + foe.radius
	if dist > stand + 0.3:
		_wish = _clear(dir)
		if dist > 10.0 and _can_sprint(view):
			_held |= PlayerControls.Buttons.SPRINT
	elif dist < stand - 0.8 or (now < _rest_until and dist < stand + 2.0):
		_wish = -dir * 0.6
	if view.action == SimPlayer.Action.STAGGER or view.action == SimPlayer.Action.ROLL:
		_chain_n = 0
	if _chain_n > 0 and now >= _chain_ends:
		_chain_n = 0
		_rest_until = now + (1.0 - skill.aggression) * skill.pause_seconds
	var facing := dir.rotated(me.up, _bias_yaw)
	var reach := Combat.in_arc(
		me.center(), facing, me.up, light.reach, light.arc_degrees, foe.center, foe.radius
	)
	var riposte := skill.uses_riposte and foe.action == Enemy.Action.STAGGER and foe.parried
	var into := _plan_slip(foe) == Slip.INTO
	if not reach or view.stamina <= skill.stamina_reserve * 0.6:
		return
	if _chain_n > 0:
		if now >= _chain_link_at and not _attack_blocked(now, light.windup + light.active):
			_swing(Combat.attack(_chain_id).next, now, PlayerControls.Buttons.ATTACK)
	elif (now >= _rest_until or riposte) and view.stamina > skill.stamina_reserve:
		var heavy := _wants_heavy(view, foe)
		var id := &"heavy" if heavy else &"light_1"
		var def := Combat.attack(id)
		if into or not _attack_blocked(now, def.windup + def.active):
			var bit := PlayerControls.Buttons.HEAVY if heavy else PlayerControls.Buttons.ATTACK
			_swing(id, now, bit)


## Presses an attack and notes when the next link goes in and when the swing is over.
func _swing(id: StringName, now: float, bit: int) -> void:
	var def := Combat.attack(id)
	_tap(bit, now)
	_chain_n += 1
	_chain_id = id
	var link := def.next != &"" and id != &"heavy" and _chain_n < skill.combo_length
	_chain_link_at = now + def.windup + def.active + TICK if link else INF
	_chain_ends = now + def.windup + def.active + def.recover + 2.0 * TICK


func _wants_heavy(view: Seen, foe: Foe) -> bool:
	var open := foe.action == Enemy.Action.STAGGER or foe.action == Enemy.Action.RECOVER
	var cost := Combat.attack(&"heavy").stamina
	return skill.uses_heavy and open and view.stamina >= skill.stamina_reserve + cost


## The slip chosen for the enemy's swing now winding up, if any.
func _plan_slip(foe: Foe) -> Slip:
	var plan := _plans.get(foe.index) as Plan
	return plan.slip if plan != null else Slip.NONE


## Ranged role: keeps its distance, aims and draws full, releases, draws again.
func _shoot(view: Seen, now: float, foe: Foe) -> void:
	var to := _flat(foe.pos - me.global_position)
	var dist := to.length()
	var t := Tuning.data()
	_aim = foe.center
	if dist < skill.ranged_near:
		_wish = -to / maxf(dist, 0.001)
	elif dist > skill.ranged_far:
		_wish = _clear(to / dist)
	_held |= PlayerControls.Buttons.BLOCK
	if not _drawing and now >= _draw_rest and view.stamina > skill.stamina_reserve:
		if not _attack_blocked(now, t.draw_time):
			_drawing = true
			_draw_end = now + t.draw_time
			_bias_yaw = deg_to_rad(_rng.randfn(0.0, skill.aim_error_deg))
			_bias_pitch = deg_to_rad(_rng.randfn(0.0, skill.aim_error_deg))
	if _drawing:
		_held |= PlayerControls.Buttons.ATTACK
		if now >= _draw_end:
			_drawing = false
			_draw_rest = now + t.shoot_recover + 0.1
			_held &= ~PlayerControls.Buttons.ATTACK


## Melee aim error is rolled anew now and then, a drawing crossbow's settles.
func _update_bias(now: float, dt: float) -> void:
	if ranged:
		if _drawing:
			var settle := exp(-skill.aim_settle * dt)
			_bias_yaw *= settle
			_bias_pitch *= settle
	elif now >= _bias_at:
		_bias_yaw = deg_to_rad(_rng.randfn(0.0, skill.aim_error_deg))
		_bias_at = now + skill.aim_period


# --- Moving ---------------------------------------------------------------------------------


## Walks toward a point along the ground; returns the distance left.
func _go(view: Seen, point: Vector3, sprint := true) -> float:
	var to := _flat(point - me.global_position)
	var dist := to.length()
	if dist > 0.05:
		_wish = _clear(to / dist)
	if sprint and dist > 10.0 and _can_sprint(view):
		_held |= PlayerControls.Buttons.SPRINT
	return dist


## Sprints while stamina is over 60 until it is under 20.
func _can_sprint(view: Seen) -> bool:
	if view.stamina > 60.0:
		_sprinting = true
	elif view.stamina < 20.0:
		_sprinting = false
	return _sprinting


func _wander(now: float) -> void:
	if now >= _search_until:
		_search = me.ref_forward.rotated(me.up, _rng.randf_range(0.0, TAU))
		_search_until = now + skill.search_leg / Tuning.data().walk_speed
	_wish = _clear(_flat(_search).normalized())


## The nearest drop in reach of its legs that it has not given up on, INF for none.
func _nearest_drop(view: Seen, now: float) -> Vector3:
	var best := Vector3.INF
	var best_distance := skill.loot_radius
	for point in view.drops:
		var distance := _flat(point - me.global_position).length()
		if distance < best_distance and not _is_ignored(point):
			best = point
			best_distance = distance
	if not best.is_finite():
		_loot_at = Vector3.INF
	elif best != _loot_at:
		_loot_at = best
		_loot_since = now
	elif now - _loot_since > skill.loot_seconds:
		_ignored.append(best)
		_loot_at = Vector3.INF
		return Vector3.INF
	return best


func _is_ignored(point: Vector3) -> bool:
	for spot in _ignored:
		if spot.distance_to(point) < 1.0:
			return true
	return false


## A wish that a wall ahead would stop turns along the wall (the idea of Enemy._around).
func _clear(wish: Vector3) -> Vector3:
	if wish == Vector3.ZERO:
		return wish
	var from := me.global_position + me.up * 0.6
	var hit := Combat.ray(me, from, from + wish.normalized() * 1.5)
	if hit.is_empty():
		return wish
	var wall: Vector3 = hit.normal
	if absf(wall.dot(me.up)) > 0.5:
		return wish
	var along := me.up.cross(wall).normalized()
	return along * (1.0 if along.dot(wish) >= 0.0 else -1.0)


func _flat(v: Vector3) -> Vector3:
	return v - me.up * v.dot(me.up)


func _dist(foe: Foe) -> float:
	return _flat(foe.pos - me.global_position).length()


# --- Output ---------------------------------------------------------------------------------


func _tap(bit: int, now: float) -> void:
	_taps[bit] = now + skill.tap_seconds


## Turns what the frame wants into controls, keeping to the cap on new presses per second.
func _output(controls: PlayerControls, now: float) -> void:
	var buttons := _held
	for bit: int in _taps.keys():
		if now < _taps[bit]:
			buttons |= bit
		else:
			_taps.erase(bit)
	while not _press_log.is_empty() and _press_log[0] <= now - 1.0:
		_press_log.pop_front()
	for bit: int in PlayerControls.Buttons.values():
		if buttons & bit == 0 or _last_out & bit != 0:
			continue
		if _press_log.size() + 1 > skill.presses_per_second:
			buttons &= ~bit
		else:
			_press_log.append(now)
	_last_out = buttons
	var yaw := 0.0
	var pitch := 0.0
	if _aim != null:
		var angles := _aim_toward(_aim)
		yaw = angles.x + _bias_yaw
		pitch = angles.y + _bias_pitch
	elif _look != null:
		yaw = _yaw_of(_look) + _bias_yaw
	else:
		yaw = _yaw_of(_wish if _wish.length_squared() > 0.01 else me.facing)
	var forward := me.ref_forward.rotated(me.up, yaw)
	controls.yaw = yaw
	controls.pitch = pitch
	controls.buttons = buttons
	controls.move = Vector2(_wish.dot(forward.cross(me.up)), _wish.dot(forward)).limit_length(1.0)


## The input yaw that looks along a direction (the reverse of ref_forward.rotated(up, yaw)).
func _yaw_of(dir: Vector3) -> float:
	var local := SimPlayer.frame(me.up, me.ref_forward).transposed() * dir
	return atan2(-local.x, -local.z)


## The yaw and pitch that put the crosshair (the camera's ray, which starts behind the shoulder)
## on a point: the ray's start depends on the yaw, so it settles over a few rounds.
func _aim_toward(point: Vector3) -> Vector2:
	var frame := SimPlayer.frame(me.up, me.ref_forward).transposed()
	var from := me.global_position + me.up * Combat.AIM_HEAD
	var angles := Vector2.ZERO
	for i in 3:
		var local := frame * (point - from).normalized()
		angles = Vector2(atan2(-local.x, -local.z), asin(clampf(local.y, -1.0, 1.0)))
		var basis := Combat.aim_basis(me, angles.x, angles.y)
		from = (
			me.global_position
			+ me.up * Combat.AIM_HEAD
			+ basis.x * Combat.AIM_SHOULDER
			+ basis.z * Combat.AIM_ARM
		)
	return angles
