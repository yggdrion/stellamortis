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

enum Action { NONE, ATTACK, ROLL, BLOCK, STAGGER, DEAD, DRAW, SHOOT }
enum Weapon { SWORD, CROSSBOW }
## What a press waits for in the input buffer.
enum Queued { NOTHING, LIGHT, HEAVY, ROLL }

const HEIGHT := 1.8
const RADIUS := 0.4
## Collision layers: 1 world, 2 players. Players do not block each other, so the client's
## prediction needs no other players in its physics world.
const LAYER_WORLD := 1
const LAYER_PLAYERS := 2
## Enemies block players but not bolt and aim rays (those test enemies geometrically).
const LAYER_ENEMIES := 4

const GROUP := &"players"
## Bolts in flight per player: fixed slots, so they roll back with the player's state.
const MAX_BOLTS := 4
const HEAVY_ATTACK := 3
## The part of a roll (fraction of roll_time) in which the body travels. The Roll clip plants
## its feet there (PlayerView.ROLL_CLIP_TRAVEL). After it, without a direction held, the body
## brakes and stays put while the model stands up (any speed would show as gliding); with one
## held it walks on, and the view shows the walk instead of the stand-up.
const ROLL_TRAVEL := 0.7
## Braking after the travel, m/s²: stops what speed is left within two ticks.
const ROLL_BRAKE := 60.0
## The last part of the travel (fraction of it) eases from the roll speed to what comes next:
## walking along the held direction, or ROLL_END of the roll speed before the stop.
const ROLL_SLOW := 0.5
const ROLL_END := 0.25
## Highest ledge (stair riser) a grounded body walks up without jumping, in metres. The capsule's
## round bottom alone slides up only a few centimetres.
const STEP_HEIGHT := 0.45
## The rolled back state. transform covers position and orientation. netfox synchronizes it as
## SYNCED: transform and velocity as they are, the rest packed in groups (Wire.pack), one
## property each, because netfox's cost grows with the number of synced properties.
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
	"weapon",
	"charge",
	"bolt_pos",
	"bolt_vel",
	"bolt_life",
	"bolt_damage",
]
const MOTION := ["up", "ref_forward", "facing", "grounded", "action_dir"]
const COMBAT := [
	"health",
	"stamina",
	"stamina_wait",
	"action",
	"action_time",
	"action_length",
	"attack",
	"swing_hits",
	"queued",
	"queued_age",
	"last_buttons",
	"invulnerable",
	"respawns",
	"weapon",
	"charge",
]
const BOLTS := ["bolt_pos", "bolt_vel", "bolt_life", "bolt_damage"]
const SYNCED := ["transform", "velocity", "net_motion", "net_combat", "net_bolts"]

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
## Counts deaths and portal jumps, so views know to snap instead of interpolating.
var respawns := 0
var weapon := Weapon.SWORD
## How far the last bolt was drawn (0..1), for its look.
var charge := 0.0
var bolt_pos := PackedVector3Array()
var bolt_vel := PackedVector3Array()
## Ticks left in flight, 0 for a free slot.
var bolt_life := PackedInt32Array()
var bolt_damage := PackedFloat32Array()

## The packed groups netfox synchronizes (SYNCED).
var net_motion: PackedByteArray:
	get:
		return Wire.pack(self, MOTION)
	set(value):
		Wire.unpack(self, MOTION, value)
var net_combat: PackedByteArray:
	get:
		return Wire.pack(self, COMBAT)
	set(value):
		Wire.unpack(self, COMBAT, value)
var net_bolts: PackedByteArray:
	get:
		return Wire.pack(self, BOLTS)
	set(value):
		Wire.unpack(self, BOLTS, value)


func _init() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER_PLAYERS
	collision_mask = LAYER_WORLD | LAYER_ENEMIES
	for i in MAX_BOLTS:
		bolt_pos.append(Vector3.ZERO)
		bolt_vel.append(Vector3.ZERO)
		bolt_life.append(0)
		bolt_damage.append(0.0)
	# Long enough to follow a stair down; snapping never applies while moving up (jumps).
	floor_snap_length = STEP_HEIGHT
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
	for property: String in SYNCED:
		rollback.state_properties.append(":" + property)
	for property: String in PlayerControls.INPUT:
		rollback.input_properties.append("Controls:" + property)
	var schema := Wire.schema(SYNCED)
	schema.merge(Wire.schema(PlayerControls.INPUT, "Controls"))
	rollback.set_schema(schema)
	add_child(rollback)
	if interpolate:
		var interpolator := TickInterpolator.new()
		interpolator.name = "Interpolator"
		interpolator.root = self
		interpolator.properties.append(":transform")
		add_child(interpolator)


## Puts the body's feet at a point, standing along the local gravity and looking along forward.
func place(feet: Vector3, forward := Vector3.FORWARD) -> void:
	var gravity := Gravity.sample(feet)
	up = -gravity.normalized() if gravity.length_squared() > 0.000001 else Vector3.UP
	ref_forward = _tangent(forward, up)
	facing = ref_forward
	global_transform = Transform3D(SimPlayer.frame(up, facing), feet)


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	step(controls.move, controls.yaw, controls.buttons, delta, controls.pitch, controls.weapon)


## One tick of movement and combat from one input.
func step(
	move: Vector2, yaw: float, buttons: int, delta: float, pitch := 0.0, wanted_weapon := -1
) -> void:
	var t := Tuning.data()
	var gravity := Gravity.sample(global_position)
	var strength := gravity.length()
	if strength > 0.001:
		_turn_frame(-gravity / strength, minf(1.0, delta / t.up_turn_time))

	var pressed := buttons & ~last_buttons
	last_buttons = buttons
	var look_forward := ref_forward.rotated(up, yaw)
	var look_right := look_forward.cross(up)
	var wish := look_right * move.x + look_forward * move.y
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	_count_down(t)
	_buffer(pressed, t)
	if action == Action.NONE and wanted_weapon >= 0 and wanted_weapon != weapon:
		weapon = wanted_weapon as Weapon
		queued = Queued.NOTHING
	_advance_action(buttons, wish, look_forward, t, yaw, pitch)
	var aiming := weapon == Weapon.CROSSBOW and buttons & PlayerControls.Buttons.BLOCK != 0

	var horizontal_target := Vector3.ZERO
	var accel := t.ground_accel if grounded else t.air_accel
	match action:
		Action.NONE when aiming:
			horizontal_target = wish * t.aim_speed
			facing = look_forward
		Action.NONE:
			var sprinting := (
				buttons & PlayerControls.Buttons.SPRINT != 0 and move.y > 0.3 and stamina > 0.0
			)
			if sprinting:
				_spend(t.sprint_stamina * delta, t)
			horizontal_target = wish * (t.sprint_speed if sprinting else t.walk_speed)
		Action.DRAW, Action.SHOOT:
			horizontal_target = wish * t.aim_speed
			facing = look_forward
		Action.BLOCK:
			horizontal_target = wish * t.block_speed
			facing = look_forward
		Action.ATTACK:
			var def := Combat.player_attack(attack)
			if action_time < def.active_end_ticks():
				horizontal_target = facing * def.lunge
			accel = t.ground_accel
		Action.ROLL:
			# Travel, easing into what follows: walking on with a direction held, else a stop
			# while the model stands up.
			var walk_on := wish.length_squared() > 0.01
			var after := wish * t.walk_speed if walk_on else action_dir * t.roll_speed * ROLL_END
			if action_time < roll_travel_ticks(t):
				var left := 1.0 - float(action_time) / roll_travel_ticks(t)
				var rolling := clampf(left / ROLL_SLOW, 0.0, 1.0)
				horizontal_target = after.lerp(action_dir * t.roll_speed, rolling)
				accel = 1000.0
			elif walk_on:
				horizontal_target = after
				accel = t.ground_accel
			else:
				accel = ROLL_BRAKE
	# A gravity well drags the body toward its center: walking out is slow, sprints and rolls
	# get away. Its pull turns into a drift speed (well_drag seconds of its acceleration).
	var pull := Gravity.pull(self, global_position)
	if pull != Vector3.ZERO and action != Action.DEAD:
		horizontal_target += (pull - up * pull.dot(up)) * t.well_drag

	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	horizontal = horizontal.move_toward(horizontal_target, accel * delta)
	if grounded and action == Action.NONE and buttons & PlayerControls.Buttons.JUMP != 0:
		var pad := Layout.pad_at(global_position)
		vertical = up * (pad.speed if pad else t.jump_speed)
	vertical += gravity * delta

	velocity = horizontal + vertical
	up_direction = up
	var was_grounded := grounded
	var start := global_transform
	# move_and_slide assumes the physics delta, netfox ticks may differ (rollback caveats).
	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor
	grounded = is_on_floor()
	# Probes with the speed the input wants: the slide has eaten the speed into the riser, and
	# the capsule's round bottom finds a floor on the edge only once it is ~0.1 m past it.
	var probe := (
		horizontal_target if horizontal_target.length() > horizontal.length() else horizontal
	)
	if was_grounded and vertical.dot(up) <= 0.0 and _step_up(start, probe * delta):
		velocity = horizontal
		grounded = true

	if action == Action.NONE and not aiming and wish.length_squared() > 0.01:
		facing = facing.slerp(wish.normalized(), minf(1.0, delta * t.turn_rate))
	facing = _tangent(facing, up)
	_orient()

	if action != Action.DEAD:
		_defend(t)
		_use_portal()
	if action == Action.ATTACK:
		_strike()
	_fly_bolts(delta, t)


## Ticks of a roll in which the body travels.
static func roll_travel_ticks(t: Tuning) -> int:
	return roundi(Combat.ticks(t.roll_time) * ROLL_TRAVEL)


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
func _advance_action(
	buttons: int, wish: Vector3, look_forward: Vector3, t: Tuning, yaw: float, pitch: float
) -> void:
	if _keep_acting(buttons, look_forward, t, yaw, pitch):
		return
	# Free to act.
	if queued == Queued.ROLL and stamina > 0.0:
		queued = Queued.NOTHING
		_spend(t.roll_stamina, t)
		# Without a direction: where the camera looks (Valheim).
		action_dir = look_forward
		if wish.length_squared() > 0.01:
			action_dir = wish.normalized()
		facing = action_dir
		_set_action(Action.ROLL)
	elif weapon == Weapon.CROSSBOW:
		if queued == Queued.LIGHT and stamina > 0.0:
			queued = Queued.NOTHING
			_set_action(Action.DRAW)
		elif queued == Queued.HEAVY:
			queued = Queued.NOTHING
	elif queued == Queued.LIGHT and stamina > 0.0:
		_start_attack(0, look_forward, t)
	elif queued == Queued.HEAVY and stamina > 0.0:
		_start_attack(HEAVY_ATTACK, look_forward, t)
	elif buttons & PlayerControls.Buttons.BLOCK and grounded:
		_set_action(Action.BLOCK)


## Runs the current action on: true while it goes on (or chained into the next swing or the
## shot), false once it ended and the player is free to start another.
func _keep_acting(buttons: int, look_forward: Vector3, t: Tuning, yaw: float, pitch: float) -> bool:
	var busy := true
	match action:
		Action.DEAD:
			if action_time >= Combat.ticks(t.death_time):
				_respawn(t)
		Action.STAGGER:
			busy = action_time < action_length
		Action.ROLL:
			busy = action_time < Combat.ticks(t.roll_time)
		Action.ATTACK:
			var def := Combat.player_attack(attack)
			var in_recover := action_time >= def.active_end_ticks()
			if in_recover and queued == Queued.ROLL:
				busy = false
			elif in_recover and queued == Queued.LIGHT and def.next != &"":
				_start_attack(Combat.PLAYER_ATTACKS.find(def.next), look_forward, t)
			else:
				busy = action_time < def.total_ticks()
		Action.DRAW:
			if queued == Queued.ROLL:
				busy = false
			elif buttons & PlayerControls.Buttons.ATTACK == 0:
				_shoot(yaw, pitch, t)
		Action.SHOOT:
			busy = action_time < Combat.ticks(t.shoot_recover)
		Action.BLOCK:
			busy = buttons & PlayerControls.Buttons.BLOCK != 0 and queued == Queued.NOTHING
		_:
			busy = false
	if not busy and action != Action.NONE:
		_set_action(Action.NONE)
	return busy


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
		var origin := enemy.strike_origin()
		if not Combat.in_arc(
			origin, enemy.facing, enemy.up, def.reach, def.arc_degrees, center(), RADIUS
		):
			continue
		if dodging():
			continue
		_take(enemy, def, t)
		return
	if not dodging():
		_catch_bolts(t)


## Enemy bolts reaching this body: the first one hits (blocks work, parries don't) and ends.
## Rolling through them is safe and leaves them flying.
func _catch_bolts(t: Tuning) -> void:
	var foot := global_position + up * RADIUS
	var head := global_position + up * (HEIGHT - RADIUS)
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		for i in enemy.bolt_life.size():
			if enemy.bolt_life[i] <= 0:
				continue
			var at := enemy.bolt_pos[i]
			var closest := Geometry3D.get_closest_point_to_segment(at, foot, head)
			if closest.distance_to(at) > RADIUS + Enemy.BOLT_RADIUS:
				continue
			enemy.bolt_life[i] = 0
			_mutate(enemy)
			_take(enemy, enemy.shot_def(), t)
			return


func _take(enemy: Enemy, def: AttackDef, t: Tuning) -> void:
	invulnerable = Combat.ticks(t.hurt_invulnerable)
	# Share of the attack's knockback: a block stops most of it, a guard break none.
	var push := 1.0 if action != Action.BLOCK else t.block_knockback
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
			push = 1.0
			_set_action(Action.STAGGER, Combat.ticks(t.guard_break_time))
	else:
		health -= def.damage
		_set_action(Action.STAGGER, Combat.ticks(t.hurt_time))
	velocity += _tangent(global_position - enemy.global_position, up) * def.knockback * push
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
			center(), facing, up, def.reach, def.arc_degrees, enemy.center(), enemy.radius
		):
			swing_hits |= bit
			enemy.take_hit(def.damage, global_position, def.knockback, def.flinch)
			_mutate(enemy)


## Releases the drawn bolt toward what the crosshair is on (Combat.aim_target).
func _shoot(yaw: float, pitch: float, t: Tuning) -> void:
	charge = clampf(float(action_time) / Combat.ticks(t.draw_time), 0.0, 1.0)
	_set_action(Action.SHOOT)
	var slot := bolt_life.find(0)
	if slot < 0:
		slot = 0
	var right := facing.cross(up)
	var muzzle := global_position + up * 1.3 + facing * 0.4 + right * 0.15
	var aim := Combat.aim_target(self, yaw, pitch)
	bolt_pos[slot] = muzzle
	bolt_vel[slot] = (
		(aim - muzzle).normalized() * lerpf(t.bolt_speed_min, t.bolt_speed_max, charge)
	)
	bolt_life[slot] = Combat.ticks(t.bolt_life)
	bolt_damage[slot] = lerpf(t.bolt_damage_min, t.bolt_damage_max, charge)
	_spend(lerpf(t.bolt_stamina_min, t.bolt_stamina_max, charge), t)


## Moves this player's bolts one tick under the gravity where they are, and ends them on the
## first wall or enemy they reach.
func _fly_bolts(delta: float, t: Tuning) -> void:
	for i in MAX_BOLTS:
		if bolt_life[i] <= 0:
			continue
		bolt_life[i] -= 1
		var from := bolt_pos[i]
		var velocity_now := bolt_vel[i] + Gravity.sample(from) * delta
		var to := from + velocity_now * delta
		bolt_vel[i] = velocity_now
		bolt_pos[i] = to
		var enemy := Combat.enemy_on_segment(self, from, to)
		if enemy:
			enemy.take_hit(bolt_damage[i], from, t.bolt_knockback, t.bolt_flinch)
			_mutate(enemy)
			bolt_pos[i] = Combat.closest_on_segment(from, to, enemy.center())
			bolt_life[i] = 0
			continue
		var wall := Combat.ray(self, from, to)
		if not wall.is_empty():
			bolt_pos[i] = wall.position
			bolt_life[i] = 0


## Steps through a portal the player stands in (a victory portal only once the Warden fell).
func _use_portal() -> void:
	var portal := Layout.portal_at(global_position)
	if portal == null or (portal.needs_victory and not Encounter.won(self)):
		return
	velocity = Vector3.ZERO
	var arrival := Layout.arrival_point(portal, peer_id)
	# A realm's ground must stand before the body does (no-op where it already does).
	var chunks := get_tree().get_first_node_in_group(TerrainChunks.GROUP) as TerrainChunks
	if chunks:
		chunks.ensure_around(arrival)
	place(arrival, portal.facing)
	respawns += 1
	queued = Queued.NOTHING
	_set_action(Action.NONE)


## Back at the keep (PLAN §6 M12: dying sends players home; a wipe empties the realm).
func _respawn(t: Tuning) -> void:
	health = t.max_health
	stamina = t.max_stamina
	velocity = Vector3.ZERO
	place(Layout.spawn_point(peer_id), Vector3.BACK)
	respawns += 1
	_set_action(Action.NONE)


## Tells netfox another node changed during rollback (outside rollback, e.g. tests, a no-op).
static func _mutate(target: Node) -> void:
	if NetworkRollback.is_rollback():
		NetworkRollback.mutate(target)


## Turns up by weight (0..1) of the way to target and carries ref_forward and facing along
## (parallel transport; the rotation comes from up_turn).
func _turn_frame(target: Vector3, weight: float) -> void:
	var turn := up_turn(up, target, weight, ref_forward)
	if turn == Quaternion.IDENTITY:
		return
	up = (turn * up).normalized()
	ref_forward = _tangent(turn * ref_forward, up)
	facing = _tangent(turn * facing, up)


## The rotation that turns up_vector by weight (0..1) of the way to target, identity when it
## is there already; apply it to every vector carried along (players and enemies). Axis-angle,
## because slerp and arc quaternions are undefined for opposite vectors, which happens when
## leaving the asteroid's underside; fallback is the axis then.
static func up_turn(
	up_vector: Vector3, target: Vector3, weight: float, fallback: Vector3
) -> Quaternion:
	var angle := up_vector.angle_to(target)
	if angle < 0.0001:
		return Quaternion.IDENTITY
	var axis := up_vector.cross(target)
	if axis.length_squared() < 0.000001:
		axis = fallback
	return Quaternion(axis.normalized(), angle * weight)


## Walks up a step the slide stopped at: from where the tick began, lifts by STEP_HEIGHT, moves
## the tick's horizontal motion, drops back onto a floor. Takes that only if it gets further
## than the slide did. Uses test_move only, so it replays the same in rollback.
func _step_up(start: Transform3D, motion: Vector3) -> bool:
	var wanted := motion.length()
	if wanted < 0.001:
		return false
	var slid := global_position - start.origin
	slid -= up * slid.dot(up)
	if slid.length() > wanted * 0.9:
		return false
	var hit := KinematicCollision3D.new()
	var at := start
	var lift := up * STEP_HEIGHT
	if test_move(at, lift, hit):
		lift = hit.get_travel()
	at.origin += lift
	var forward := motion
	if test_move(at, motion, hit):
		forward = hit.get_travel()
	at.origin += forward
	if not test_move(at, -lift - up * 0.05, hit):
		return false
	if hit.get_normal().dot(up) < cos(floor_max_angle):
		return false
	at.origin += hit.get_travel()
	var moved := at.origin - start.origin
	var rise := moved.dot(up)
	moved -= up * rise
	if rise < 0.02 or moved.length() <= slid.length() + 0.01:
		return false
	global_transform = at
	return true


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
