class_name SimPlayer
extends CharacterBody3D
## A player's body, movement and combat rules (PLAN §4.2, §4.5). netfox runs _rollback_tick on
## the server for every player and on the owning client for prediction and rollback
## (networked()). Movement happens in the plane of the current up vector, which follows gravity,
## so the same code walks on flat ground and around planetoids.
##
## Combat is a small state machine on `action`, counted in ticks (`action_time`) so it rolls
## back exactly. Enemy swings are checked here, in the defender's tick (_defend): when a dodge
## input arrives late, the server resimulates this player and the dodge still counts.

enum Action { NONE, ATTACK, ROLL, BLOCK, STAGGER, DEAD }
## What a press waits for in the input buffer.
enum Queued { NOTHING, LIGHT, HEAVY, ROLL }

const HEIGHT := 1.8
const RADIUS := 0.4
## Collision layers: 1 world, 2 players. Players do not block each other, so the client's
## prediction needs no other players in its physics world.
const LAYER_WORLD := 1
const LAYER_PLAYERS := 2

const GROUP := &"players"
const HEAVY_ATTACK := 3
## State netfox records, sends and rolls back. transform covers position and orientation.
const STATE := [
	"transform",
	"velocity",
	"up",
	"ref_forward",
	"facing",
	"grounded",
	"health",
	"stamina",
	"stamina_wait",
	"action",
	"action_time",
	"action_length",
	"action_dir",
	"attack",
	"swing_hits",
	"queued",
	"queued_age",
	"last_buttons",
	"invulnerable",
	"respawns",
]

var peer_id := 0
var player_name := ""
## The owning player's input; null until networked() (tests call step directly).
var controls: PlayerControls
## Turns toward -gravity over Tuning.up_turn_time.
var up := Vector3.UP
## The direction input yaw is measured from: a tangent vector carried along when up turns, so
## the camera keeps its heading while walking over a curved surface.
var ref_forward := Vector3.FORWARD
## Where the body looks (tangent), turns toward the walk direction.
var facing := Vector3.FORWARD
## Our own floor flag: CharacterBody3D's can't be restored from a server state.
var grounded := false

var health := 100.0
var stamina := 100.0
## Ticks until stamina regenerates again.
var stamina_wait := 0
var action := Action.NONE
## Ticks since the action started, and how long it lasts where that is fixed (stagger).
var action_time := 0
var action_length := 0
## Roll direction (tangent).
var action_dir := Vector3.FORWARD
## Index into Combat.PLAYER_ATTACKS while attacking.
var attack := 0
## Bits of Enemy.index already hit by the current swing.
var swing_hits := 0
var queued := Queued.NOTHING
var queued_age := 0
## Buttons held last tick, to tell presses from holds.
var last_buttons := 0
## Ticks left in which enemy swings pass through (after being hit).
var invulnerable := 0
## Counts deaths, so views know to snap instead of interpolating to the spawn.
var respawns := 0


func _init() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER_PLAYERS
	collision_mask = LAYER_WORLD
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = HEIGHT
	capsule.radius = RADIUS
	shape.shape = capsule
	shape.position = Vector3(0.0, HEIGHT / 2.0, 0.0)
	add_child(shape)


## Makes this body a networked player: server-owned state, input owned by peer, rollback, and
## on clients interpolation between ticks. Call before adding it to the tree, on every peer.
func networked(owner_peer: int, interpolate: bool) -> void:
	peer_id = owner_peer
	name = "Player%d" % owner_peer
	set_multiplayer_authority(1)
	controls = PlayerControls.new()
	controls.name = "Controls"
	controls.set_multiplayer_authority(owner_peer)
	add_child(controls)
	var rollback := RollbackSynchronizer.new()
	rollback.name = "Rollback"
	rollback.root = self
	rollback.enable_input_broadcast = false
	for property: String in STATE:
		rollback.state_properties.append(":" + property)
	for property: String in PlayerControls.INPUT:
		rollback.input_properties.append("Controls:" + property)
	add_child(rollback)
	if interpolate:
		var interpolator := TickInterpolator.new()
		interpolator.name = "Interpolator"
		interpolator.root = self
		interpolator.properties.append(":transform")
		add_child(interpolator)


## Puts the body's feet at a point, standing along the local gravity.
func place(feet: Vector3) -> void:
	var gravity := Gravity.sample(feet)
	up = -gravity.normalized() if gravity.length_squared() > 0.000001 else Vector3.UP
	ref_forward = _tangent(Vector3.FORWARD, up)
	facing = ref_forward
	global_transform = Transform3D(SimPlayer.frame(up, facing), feet)


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	step(controls.move, controls.yaw, controls.buttons, delta)


## One tick of movement and combat from one input.
func step(move: Vector2, yaw: float, buttons: int, delta: float) -> void:
	var t := Tuning.data()
	var gravity := Gravity.sample(global_position)
	var strength := gravity.length()
	if strength > 0.001:
		_turn_frame(-gravity / strength, minf(1.0, delta / t.up_turn_time))

	var look_forward := ref_forward.rotated(up, yaw)
	var look_right := look_forward.cross(up)
	var wish := look_right * move.x + look_forward * move.y
	if wish.length_squared() > 1.0:
		wish = wish.normalized()

	var pressed := buttons & ~last_buttons
	last_buttons = buttons
	_count_down(t)
	_buffer(pressed, t)
	_advance_action(buttons, wish, look_forward, t)

	var horizontal_target := Vector3.ZERO
	var accel := t.ground_accel if grounded else t.air_accel
	match action:
		Action.NONE:
			var sprinting := (
				buttons & PlayerControls.Buttons.SPRINT != 0 and move.y > 0.3 and stamina > 0.0
			)
			if sprinting:
				_spend(t.sprint_stamina * delta, t)
			horizontal_target = wish * (t.sprint_speed if sprinting else t.walk_speed)
		Action.BLOCK:
			horizontal_target = wish * t.block_speed
			facing = look_forward
		Action.ATTACK:
			var def := Combat.player_attack(attack)
			if action_time < def.active_end_ticks():
				horizontal_target = facing * def.lunge
			accel = t.ground_accel
		Action.ROLL:
			horizontal_target = action_dir * t.roll_speed
			accel = 1000.0

	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	horizontal = horizontal.move_toward(horizontal_target, accel * delta)
	if grounded and action == Action.NONE and buttons & PlayerControls.Buttons.JUMP != 0:
		var pad := Layout.pad_at(global_position)
		vertical = up * (pad.speed if pad else t.jump_speed)
	vertical += gravity * delta

	velocity = horizontal + vertical
	up_direction = up
	# move_and_slide assumes the physics delta, netfox ticks may differ (rollback caveats).
	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor
	grounded = is_on_floor()

	if action == Action.NONE and wish.length_squared() > 0.01:
		facing = facing.slerp(wish.normalized(), minf(1.0, delta * t.turn_rate))
	facing = _tangent(facing, up)
	_orient()

	if action != Action.DEAD:
		_defend(t)
	if action == Action.ATTACK:
		_strike()


## In the roll's invulnerable window.
func dodging() -> bool:
	var t := Tuning.data()
	return (
		action == Action.ROLL
		and action_time >= Combat.ticks(t.roll_iframes_start)
		and action_time <= Combat.ticks(t.roll_iframes_end)
	)


func center() -> Vector3:
	return global_position + up * (HEIGHT / 2.0)


func _count_down(t: Tuning) -> void:
	action_time += 1
	invulnerable = maxi(0, invulnerable - 1)
	if stamina_wait > 0:
		stamina_wait -= 1
	elif action != Action.BLOCK or stamina <= 0.0:
		stamina = minf(t.max_stamina, stamina + t.stamina_regen / Combat.TICKRATE)


func _spend(amount: float, t: Tuning) -> void:
	stamina = maxf(0.0, stamina - amount)
	stamina_wait = Combat.ticks(t.stamina_delay)


func _buffer(pressed: int, t: Tuning) -> void:
	if pressed & PlayerControls.Buttons.ROLL:
		queued = Queued.ROLL
	elif pressed & PlayerControls.Buttons.ATTACK:
		queued = Queued.LIGHT
	elif pressed & PlayerControls.Buttons.HEAVY:
		queued = Queued.HEAVY
	else:
		queued_age += 1
		if queued_age > Combat.ticks(t.input_buffer):
			queued = Queued.NOTHING
		return
	queued_age = 0


## Ends finished actions and starts the buffered one when the current action allows it.
func _advance_action(buttons: int, wish: Vector3, look_forward: Vector3, t: Tuning) -> void:
	match action:
		Action.DEAD:
			if action_time >= Combat.ticks(t.death_time):
				_respawn(t)
			return
		Action.STAGGER:
			if action_time < action_length:
				return
			_set_action(Action.NONE)
		Action.ROLL:
			if action_time < Combat.ticks(t.roll_time):
				return
			_set_action(Action.NONE)
		Action.ATTACK:
			var def := Combat.player_attack(attack)
			var in_recover := action_time >= def.active_end_ticks()
			if in_recover and queued == Queued.ROLL:
				_set_action(Action.NONE)
			elif in_recover and queued == Queued.LIGHT and def.next != &"":
				_start_attack(Combat.PLAYER_ATTACKS.find(def.next), look_forward, t)
				return
			elif action_time >= def.total_ticks():
				_set_action(Action.NONE)
			else:
				return
		Action.BLOCK:
			if buttons & PlayerControls.Buttons.BLOCK == 0 or queued != Queued.NOTHING:
				_set_action(Action.NONE)
			else:
				return
	# Free to act.
	if queued == Queued.ROLL and stamina > 0.0:
		queued = Queued.NOTHING
		_spend(t.roll_stamina, t)
		action_dir = wish.normalized() if wish.length_squared() > 0.01 else facing
		facing = action_dir
		_set_action(Action.ROLL)
	elif queued == Queued.LIGHT and stamina > 0.0:
		_start_attack(0, look_forward, t)
	elif queued == Queued.HEAVY and stamina > 0.0:
		_start_attack(HEAVY_ATTACK, look_forward, t)
	elif buttons & PlayerControls.Buttons.BLOCK and grounded:
		_set_action(Action.BLOCK)


func _start_attack(index: int, look_forward: Vector3, t: Tuning) -> void:
	queued = Queued.NOTHING
	attack = index
	swing_hits = 0
	_spend(Combat.player_attack(index).stamina, t)
	# Attacks go where the camera looks (Valheim), not where the body faced.
	facing = _tangent(look_forward, up)
	_set_action(Action.ATTACK)


func _set_action(next: Action, length := 0) -> void:
	action = next
	action_time = 0
	action_length = length


## Enemy swings landing on this player this tick: dodged, parried, blocked or taken.
func _defend(t: Tuning) -> void:
	if invulnerable > 0:
		return
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if not enemy.striking():
			continue
		var def := enemy.attack_def()
		var origin := enemy.center()
		if not Combat.in_arc(
			origin, enemy.facing, enemy.up(), def.reach, def.arc_degrees, center(), RADIUS
		):
			continue
		if dodging():
			continue
		_take(enemy, def, t)
		return


func _take(enemy: Enemy, def: AttackDef, t: Tuning) -> void:
	invulnerable = Combat.ticks(t.hurt_invulnerable)
	if action == Action.BLOCK:
		if def.parryable and action_time <= Combat.ticks(t.parry_window):
			enemy.parry()
			_mutate(enemy)
			return
		var blocked := def.damage * t.block_reduction
		health -= def.damage - blocked
		stamina -= blocked * t.block_stamina
		stamina_wait = Combat.ticks(t.stamina_delay)
		if stamina < 0.0:
			# Guard break: the rest of the hit goes through and the guard drops.
			health -= -stamina / t.block_stamina
			stamina = 0.0
			_set_action(Action.STAGGER, Combat.ticks(t.guard_break_time))
	else:
		health -= def.damage
		_set_action(Action.STAGGER, Combat.ticks(t.hurt_time))
	if health <= 0.0:
		health = 0.0
		_set_action(Action.DEAD)


## The current swing's hits: each enemy at most once per swing.
func _strike() -> void:
	var def := Combat.player_attack(attack)
	if action_time <= def.windup_ticks() or action_time > def.active_end_ticks():
		return
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		var bit := 1 << enemy.index
		if swing_hits & bit or not enemy.alive():
			continue
		if Combat.in_arc(
			center(), facing, up, def.reach, def.arc_degrees, enemy.center(), Enemy.RADIUS
		):
			swing_hits |= bit
			enemy.take_hit(def.damage)
			_mutate(enemy)


func _respawn(t: Tuning) -> void:
	health = t.max_health
	stamina = t.max_stamina
	velocity = Vector3.ZERO
	place(Layout.spawn_point(peer_id))
	respawns += 1
	_set_action(Action.NONE)


## Tells netfox another node changed during rollback (outside rollback, e.g. tests, a no-op).
static func _mutate(target: Node) -> void:
	if NetworkRollback.is_rollback():
		NetworkRollback.mutate(target)


## Turns up by weight (0..1) of the way to target and carries ref_forward and facing along
## (parallel transport). Axis-angle, because slerp and arc quaternions are undefined for
## opposite vectors, which happens when leaving the asteroid's underside.
func _turn_frame(target: Vector3, weight: float) -> void:
	var angle := up.angle_to(target)
	if angle < 0.0001:
		return
	var axis := up.cross(target)
	if axis.length_squared() < 0.000001:
		axis = ref_forward
	var turn := Quaternion(axis.normalized(), angle * weight)
	up = (turn * up).normalized()
	ref_forward = _tangent(turn * ref_forward, up)
	facing = _tangent(turn * facing, up)


func _orient() -> void:
	global_basis = SimPlayer.frame(up, facing)


## A basis with Y along up and -Z along forward.
static func frame(up_vector: Vector3, forward: Vector3) -> Basis:
	var z := -forward
	var x := up_vector.cross(z).normalized()
	return Basis(x, up_vector, x.cross(up_vector))


## v projected onto the plane of up_vector, normalized; any tangent if v is along up_vector.
static func _tangent(v: Vector3, up_vector: Vector3) -> Vector3:
	var t := v - up_vector * v.dot(up_vector)
	if t.length_squared() < 0.0001:
		t = up_vector.cross(Vector3.RIGHT)
		if t.length_squared() < 0.0001:
			t = up_vector.cross(Vector3.FORWARD)
	return t.normalized()
