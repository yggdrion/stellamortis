class_name Enemy
extends CharacterBody3D
## What players fight (PLAN §4.5, §4.6): server-owned, rolled back by netfox with prediction, so
## clients simulate it between server states. Players check enemy swings and bolts in their own
## rollback tick (SimPlayer._defend) and hit enemies with take_hit + NetworkRollback.mutate.
## One class runs every kind (M21): `kind` (rolled back) picks the EnemyDef, whose behavior
## dispatches the tick to TrainingDummy, Mob or Warden (static logic without state of their own),
## so a slot can change kind at runtime. Every enemy exists on every peer from the start (netfox
## finds them by path); the encounter hides, wakes and resets them.

enum Action { IDLE, WINDUP, STRIKE, RECOVER, STAGGER, DOWN, HIDDEN, RISE, FLINCH, GUARD }

const HEIGHT := 1.8
const RADIUS := 0.5
const GROUP := &"enemies"
## Enemies with a gravity well (the Warden's kind), read by Gravity.pull.
const WELLS := &"gravity_wells"
## Rolled back state, the same for every kind (`kind` before what depends on it, `action` first:
## net_combat of a hidden slot is that one byte).
const STATE := [
	"transform",
	"action",
	"up",
	"facing",
	"kind",
	"health",
	"max_health",
	"action_time",
	"parried",
	"quiet_time",
	"flinch_time",
	"well_time",
	"combo",
	"velocity",
	"attack",
	"leap_to",
	"bolt_pos",
	"bolt_vel",
	"bolt_life",
]
const BOLTS := ["bolt_pos", "bolt_vel", "bolt_life"]
## How close a bolt must pass a body's axis to hit it, on top of the body's radius.
const BOLT_RADIUS := 0.2
## How far ahead (m) a walker looks for a wall to slide around.
const SIDESTEP_LOOKAHEAD := 0.6

## net_combat of a hidden slot (its action alone), _pack_bolts without a bolt in flight (the count).
static var _hidden_net := PackedByteArray([Action.HIDDEN])
static var _no_bolts := PackedByteArray([0])

## Stable across peers (World assigns it): the bit in a player's swing_hits.
var index := 0
## Dummy: swings at no one (set by World, not rolled back).
var passive := false
## The kind's numbers, Combat.enemy_def(kind).
var def := Combat.enemy_def(0)
## Body size, from the def (set_size).
var height := HEIGHT
var radius := RADIUS
## Where reset() puts it.
var home := Transform3D.IDENTITY

## Index into Combat.ENEMY_KINDS (rolled back); a free slot is 0. Changing it swaps the def and
## the body; health, action and home are the waker's job (become).
var kind := 0:
	set(value):
		kind = value
		def = Combat.enemy_def(kind)
		_apply_def()
## Which way is up for it: follows the local gravity like a player's up (rolled back; the
## transform is rebuilt from it and facing every tick).
var up := Vector3.UP
var facing := Vector3.FORWARD
var health := 90.0
var max_health := 90.0
var action := Action.IDLE
var action_time := 0
## Staggered by a parry (riposte bonus), not by something else.
var parried := false
## Ticks since it last took damage.
var quiet_time := 0
## Ticks the current FLINCH lasts.
var flinch_time := 0
## Boss: ticks the gravity well still pulls, and attacks started since it rose (picks the next).
var well_time := 0
var combo := 0
## Which of the kind's attacks (def.attacks) runs.
var attack := 0
## Where the running leap lands (ZERO: none; chosen when the attack begins).
var leap_to := Vector3.ZERO
var bolt_pos := PackedVector3Array()
var bolt_vel := PackedVector3Array()
## Ticks left in flight, 0 for a free slot.
var bolt_life := PackedInt32Array()

## The packed property netfox synchronizes (the synced list in networked()): every field, then
## the bolts in flight (_pack_bolts; a slot has room for the biggest kind's bolts, World.
## _add_pool, most of the time none fly). A hidden slot is its action byte alone: nothing else
## of it matters until it wakes (become).
var net_combat: PackedByteArray:
	get:
		if action == Action.HIDDEN:
			return _hidden_net
		return _pack_state() + _pack_bolts()
	set(value):
		if value.size() == 1:
			action = value[0] as Action
			return
		_unpack_bolts(value.slice(_unpack_state(value)))

var _shape: CollisionShape3D
var _probe := KinematicCollision3D.new()


func _init() -> void:
	collision_layer = SimPlayer.LAYER_ENEMIES
	# Enemies shove each other aside instead of walking through one another; players don't
	# block them (players bump into enemies, not the other way round).
	collision_mask = SimPlayer.LAYER_WORLD | SimPlayer.LAYER_ENEMIES
	floor_snap_length = 0.3
	_shape = CollisionShape3D.new()
	add_child(_shape)
	add_to_group(GROUP)
	_apply_def()


## The body and the well group follow the def.
func _apply_def() -> void:
	if _shape.shape == null or radius != def.radius or height != def.height:
		set_size(def.radius, def.height)
	if def.well_time > 0.0:
		add_to_group(WELLS)
	elif is_in_group(WELLS):
		remove_from_group(WELLS)


func set_size(body_radius: float, body_height: float) -> void:
	radius = body_radius
	height = body_height
	var capsule := CapsuleShape3D.new()
	capsule.height = height
	capsule.radius = radius
	_shape.shape = capsule
	_shape.position = Vector3(0.0, height / 2.0, 0.0)


## Gives it bolt slots (fixed, so they roll back with its state).
func make_bolts(slots: int) -> void:
	for i in slots:
		bolt_pos.append(Vector3.ZERO)
		bolt_vel.append(Vector3.ZERO)
		bolt_life.append(0)


## Bolts this kind can have in flight, within the slot's room.
func bolt_slots() -> int:
	return mini(def.bolt_slots, bolt_life.size())


## The fields of STATE besides the bolts, written by hand because netfox reads and sets every
## awake slot on every resimulated tick: action, kind, attack and parried as bytes, seven vectors
## (the basis' three axes, the origin, up, facing, velocity) as 32 bit floats, health and
## max_health, then action_time, quiet_time, flinch_time, well_time and combo as varuints, then
## leap_to (12 bytes) only while a leap runs (bit 1 of the parried byte).
## A field added to STATE must be added here (tests/wire_test.gd fails otherwise).
func _pack_state() -> PackedByteArray:
	var at := transform
	var leaping := leap_to != Vector3.ZERO
	var flags := (1 if parried else 0) | (2 if leaping else 0)
	var bytes := PackedByteArray([action, kind, attack, flags])
	var vectors := PackedVector3Array(
		[at.basis.x, at.basis.y, at.basis.z, at.origin, up, facing, velocity]
	)
	bytes.append_array(vectors.to_byte_array())
	bytes.append_array(PackedFloat32Array([health, max_health]).to_byte_array())
	for counter: int in [action_time, quiet_time, flinch_time, well_time, combo]:
		var rest := counter
		while rest > 127:
			bytes.append((rest & 127) | 128)
			rest >>= 7
		bytes.append(rest)
	if leaping:
		bytes.append_array(PackedVector3Array([leap_to]).to_byte_array())
	return bytes


## Reads what _pack_state wrote and returns how many bytes it took.
func _unpack_state(bytes: PackedByteArray) -> int:
	if bytes[1] != kind:
		kind = bytes[1]
	action = bytes[0] as Action
	attack = bytes[2]
	parried = bytes[3] & 1 != 0
	var vectors := bytes.slice(4, 88).to_vector3_array()
	transform = Transform3D(Basis(vectors[0], vectors[1], vectors[2]), vectors[3])
	up = vectors[4]
	facing = vectors[5]
	velocity = vectors[6]
	health = bytes.decode_float(88)
	max_health = bytes.decode_float(92)
	var counters := [0, 0, 0, 0, 0]
	var at := 96
	for i in 5:
		var value := 0
		var shift := 0
		while bytes[at] > 127:
			value |= (bytes[at] & 127) << shift
			shift += 7
			at += 1
		counters[i] = value | (bytes[at] << shift)
		at += 1
	action_time = counters[0]
	quiet_time = counters[1]
	flinch_time = counters[2]
	well_time = counters[3]
	combo = counters[4]
	leap_to = Vector3.ZERO
	if bytes[3] & 2:
		leap_to = bytes.slice(at, at + 12).to_vector3_array()[0]
		at += 12
	return at


func _pack_bolts() -> PackedByteArray:
	if bolt_slots() == 0 or action == Action.HIDDEN:
		return _no_bolts
	var flying := 0
	for i in bolt_slots():
		if bolt_life[i] > 0:
			flying += 1
	if flying == 0:
		return _no_bolts
	var buffer := StreamPeerBuffer.new()
	buffer.put_u8(flying)
	for i in bolt_slots():
		if bolt_life[i] <= 0:
			continue
		buffer.put_u8(i)
		var at := bolt_pos[i]
		var toward := bolt_vel[i]
		for value in [at.x, at.y, at.z, toward.x, toward.y, toward.z]:
			buffer.put_float(value as float)
		buffer.put_u8(clampi(bolt_life[i], 0, 255))
	return buffer.data_array


## Reads what _pack_bolts wrote: bolts not in the bytes are over (their position and velocity
## are not read until fired again).
func _unpack_bolts(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	bolt_life.fill(0)
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	for n in buffer.get_u8():
		var slot := buffer.get_u8()
		bolt_pos[slot] = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
		bolt_vel[slot] = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
		bolt_life[slot] = buffer.get_u8()


## Server-owned, predicted on clients. Call before adding it to the tree, on every peer. Every
## rolled back field (Enemy.STATE) is synchronized as one property,
## net_combat (_pack_state, then the bolts in flight): netfox's cost grows with the properties
## of every node, and the pool has dozens.
func networked() -> void:
	var synced := ["net_combat"]
	var rollback := RollbackSynchronizer.new()
	rollback.name = "Rollback"
	rollback.root = self
	rollback.enable_prediction = true
	for property: String in synced:
		rollback.state_properties.append(":" + property)
	rollback.set_schema(Wire.schema(synced))
	add_child(rollback)


func attack_def() -> AttackDef:
	return Combat.attack(def.attacks[attack])


func shot_def() -> AttackDef:
	return Combat.attack(def.shot_attack)


func center() -> Vector3:
	return global_position + global_basis.y * (height / 2.0)


## Where the current attack's hit area is centered.
func strike_origin() -> Vector3:
	return center() + facing * attack_def().offset


func alive() -> bool:
	return action != Action.DOWN and action != Action.HIDDEN


## In the hit window of a melee attack this tick.
func striking() -> bool:
	return action == Action.STRIKE and attack_def().melee()


## The boss is below half health.
func phase_2() -> bool:
	return def.behavior == EnemyDef.Behavior.BOSS_WARDEN and health < max_health / 2.0


## Windup length scale (the Warden speeds up in phase 2).
func pace() -> float:
	return def.phase_2_pace if phase_2() else 1.0


func windup_ticks() -> int:
	return maxi(1, roundi(attack_def().windup_ticks() * pace()))


## The pull while the well is up, null otherwise.
func well_zone() -> GravityZone:
	if well_time <= 0 or not alive():
		return null
	return GravityZone.sphere("gravity well", center(), def.well_reach, def.well_pull)


## A player's hit from a point: pushes it away along its ground and flinches it (a swing in
## progress only if the flinch beats its poise). Returns the damage dealt.
func take_hit(amount: float, from: Vector3, knockback := 0.0, flinch := 0.0) -> float:
	if not alive() or action == Action.RISE:
		return 0.0
	if action == Action.STAGGER and parried:
		amount *= def.riposte
	var guarded := _guards(from)
	if guarded:
		amount *= def.guard_damage
	health -= amount
	quiet_time = 0
	if health <= 0.0:
		health = 0.0
		_set_action(Action.DOWN)
		return amount
	if guarded:
		if action == Action.IDLE:
			_set_action(Action.GUARD)
		return amount
	velocity += SimPlayer._tangent(global_position - from, up) * knockback * def.shove
	var busy := action == Action.WINDUP or action == Action.STRIKE or action == Action.RECOVER
	if (
		def.flinches
		and flinch > 0.0
		and action != Action.STAGGER
		and (not busy or flinch >= def.poise)
	):
		_set_action(Action.FLINCH)
		flinch_time = Combat.ticks(flinch)
	return amount


## Whether a hit from this point lands on its raised guard: inside guard_arc ahead of it, while
## idle or winding up (striking, recovering, staggered, flinching and rising are open).
func _guards(from: Vector3) -> bool:
	if def.guard_arc <= 0.0:
		return false
	if action != Action.IDLE and action != Action.GUARD and action != Action.WINDUP:
		return false
	var to := SimPlayer._tangent(from - global_position, up)
	return to != Vector3.ZERO and facing.angle_to(to) <= deg_to_rad(def.guard_arc) / 2.0


## GUARD counts down, then it is idle again.
func _end_guard() -> void:
	if action_time >= Combat.ticks(def.guard_react):
		_set_action(Action.IDLE)


## FLINCH counts down, then it is idle again.
func _end_flinch() -> void:
	if action_time >= flinch_time:
		_set_action(Action.IDLE)


## RISE counts down, then it is idle again.
func _end_rise() -> void:
	if action_time >= Combat.ticks(def.rise_time):
		_set_action(Action.IDLE)


## A player parried its swing.
func parry() -> void:
	_set_action(Action.STAGGER)
	parried = true


## Makes the slot a kind at a post and resets it (waking a pool slot is this, never a spawn).
func become(new_kind: int, post: Transform3D, start: Action) -> void:
	kind = new_kind
	home = post
	reset(start)


## Back to where and how it started (encounter reset).
func reset(start: Action) -> void:
	global_transform = home
	up = home.basis.y
	facing = -home.basis.z
	velocity = Vector3.ZERO
	max_health = def.health
	health = max_health
	attack = 0
	leap_to = Vector3.ZERO
	quiet_time = 0
	well_time = 0
	combo = 0
	for i in bolt_life.size():
		bolt_life[i] = 0
	_set_action(start)
	_sync_body()


## Rises with health for this many players (def.per_player of def.health for each beyond the
## first).
func wake(players := 1) -> void:
	max_health = def.health * (1.0 + def.per_player * maxi(0, players - 1))
	health = max_health
	combo = 0
	well_time = 0
	_set_action(Action.RISE)
	_sync_body()


func _set_action(next: Action) -> void:
	action = next
	action_time = 0
	if next != Action.STAGGER:
		parried = false


## Hidden and fallen enemies don't block anyone.
## Only on change: setting it rebuilds the body in the physics server, even to the same value.
func _sync_body() -> void:
	if _shape.disabled == alive():
		_shape.disabled = not alive()


## Hidden slots do next to nothing; the rest run their kind's behavior.
func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	if action == Action.HIDDEN:
		_sync_body()
		return
	action_time += 1
	quiet_time += 1
	match def.behavior:
		EnemyDef.Behavior.DUMMY:
			TrainingDummy.tick(self, delta)
		EnemyDef.Behavior.MELEE, EnemyDef.Behavior.RANGED:
			Mob.tick(self, delta)
		EnemyDef.Behavior.BOSS_WARDEN:
			Warden.tick(self, delta)


## Nearest living player within range, null if none.
func nearest_player(within: float) -> SimPlayer:
	var best: SimPlayer = null
	var best_distance := within
	for node in get_tree().get_nodes_in_group(SimPlayer.GROUP):
		var player := node as SimPlayer
		if player.action == SimPlayer.Action.DEAD:
			continue
		var distance := player.global_position.distance_to(global_position)
		if distance < best_distance:
			best = player
			best_distance = distance
	return best


## Runs windup, strike and recover of the current attack; false once it is over (or none runs).
## The strike's first tick calls _on_strike.
func _advance_attack() -> bool:
	var swing := attack_def()
	match action:
		Action.WINDUP:
			if action_time >= windup_ticks():
				_set_action(Action.STRIKE)
				_on_strike(swing)
		Action.STRIKE:
			if action_time >= Combat.ticks(swing.active):
				var follow := def.attacks.find(swing.next) if swing.next != &"" else -1
				if follow >= 0 and alive():
					_start_attack(follow)
				else:
					_set_action(Action.RECOVER)
		Action.RECOVER:
			if action_time >= Combat.ticks(swing.recover):
				_set_action(Action.IDLE)
				return false
		_:
			return false
	return true


## Begins an attack; a leap commits to where the nearest player stands now, at most
## AttackDef.leap metres away along the ground.
func _start_attack(which: int) -> void:
	attack = which
	_set_action(Action.WINDUP)
	leap_to = Vector3.ZERO
	var reach := attack_def().leap
	var target := nearest_player(60.0) if reach > 0.0 else null
	if target:
		var to := _along_ground(target.global_position - global_position)
		if to.length() > 0.01:
			facing = to.normalized()
			leap_to = global_position + to.limit_length(reach)


## A leap is running (its windup).
func _leaping() -> bool:
	return action == Action.WINDUP and leap_to != Vector3.ZERO


## The ground speed that lands at leap_to on the windup's last tick, from where it is now.
func _leap_velocity(delta: float) -> Vector3:
	var left := maxi(1, windup_ticks() - action_time + 1)
	return _along_ground(leap_to - global_position) / (left * delta)


## A vector without its part along up (SimPlayer._tangent also normalizes).
func _along_ground(v: Vector3) -> Vector3:
	return v - up * v.dot(up)


## The strike begins: the well opens, ranged attacks fire (melee ones are checked by the
## players).
func _on_strike(swing: AttackDef) -> void:
	if def.well_attack != &"" and def.attacks[attack] == def.well_attack:
		well_time = Combat.ticks(def.well_time)
		return
	if swing.bolts == 0:
		return
	var target := nearest_player(60.0)
	if target:
		_fire(swing, target.center())


## Fires swing.bolts in a fan toward a point, aimed up to make up for the gravity on the way.
func _fire(swing: AttackDef, at: Vector3) -> void:
	var muzzle := center() + facing * (radius + 0.3)
	var to := at - muzzle
	var flight := to.length() / swing.bolt_speed
	var gravity := Gravity.sample(muzzle)
	var base := to.normalized() * swing.bolt_speed - gravity * (flight / 2.0)
	for n in swing.bolts:
		var slot := _free_bolt()
		if slot < 0:
			return
		var fan := 0.0
		if swing.bolts > 1:
			fan = deg_to_rad(swing.spread_degrees) * (float(n) / (swing.bolts - 1) - 0.5)
		bolt_pos[slot] = muzzle
		bolt_vel[slot] = base.rotated(up, fan)
		bolt_life[slot] = Combat.ticks(4.0)


## A bolt slot of this kind (bolt_slots()) not in flight, -1 if none.
func _free_bolt() -> int:
	for i in bolt_slots():
		if bolt_life[i] <= 0:
			return i
	return -1


## Moves its bolts one tick under the local gravity; walls end them (players end them in
## their own tick, SimPlayer._defend).
func _fly_bolts(delta: float) -> void:
	for i in bolt_slots():
		if bolt_life[i] <= 0:
			continue
		bolt_life[i] -= 1
		var from := bolt_pos[i]
		var velocity_now := bolt_vel[i] + Gravity.sample(from) * delta
		var to := from + velocity_now * delta
		bolt_vel[i] = velocity_now
		bolt_pos[i] = to
		var wall := Combat.ray(self, from, to)
		if not wall.is_empty():
			bolt_pos[i] = wall.position
			bolt_life[i] = 0


## Turns up toward the local gravity's opposite and carries facing along.
func _follow_gravity(gravity: Vector3, delta: float) -> void:
	var strength := gravity.length()
	if strength < 0.001:
		return
	var weight := minf(1.0, delta / Tuning.data().up_turn_time)
	var turn := SimPlayer.up_turn(up, -gravity / strength, weight, facing)
	if turn == Quaternion.IDENTITY:
		return
	up = (turn * up).normalized()
	facing = SimPlayer._tangent(turn * facing, up)


## Head-on into a wall (a trunk, a boulder, M35) a body would stick: a wish that the wall ahead
## mostly stops turns along the wall instead, to the side it already leans to (on the dead
## center: by the slot's parity). No state: the probe reads the position alone, so every peer
## and every resimulated tick picks the same way.
func _around(wish: Vector3, speed: float, delta: float) -> Vector3:
	if wish == Vector3.ZERO:
		return wish
	var ahead := wish.normalized() * maxf(SIDESTEP_LOOKAHEAD, speed * delta * 3.0)
	if not test_move(global_transform, ahead, _probe):
		return wish
	var wall := _probe.get_normal()
	if absf(wall.dot(up)) > 0.5 or _probe.get_collider() is Enemy:
		return wish
	var along := SimPlayer._tangent(up.cross(wall), up).normalized()
	var lean := along.dot(wish)
	if absf(lean) < 0.05:
		lean = 1.0 if index % 2 == 0 else -1.0
	var length := wish.length()
	var open := wish - wall * wish.dot(wall)
	if open.length() > length * 0.7:
		return wish
	return along * signf(lean) * length


## Walks along wish (tangent, length up to 1) at speed, under gravity, on its own up.
func _walk(wish: Vector3, speed: float, delta: float) -> void:
	wish = _around(wish, speed, delta)
	var gravity := Gravity.sample(global_position)
	_follow_gravity(gravity, delta)
	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	if _leaping():
		horizontal = _leap_velocity(delta)
		if action_time == 1:
			# A hop that comes down as the windup ends: half the windup rising, half falling.
			vertical = up * (gravity.length() * attack_def().windup / 2.0)
	else:
		horizontal = horizontal.move_toward(wish * speed, 30.0 * delta)
	vertical += gravity * delta
	velocity = horizontal + vertical
	up_direction = up
	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor


func _turn_toward(point: Vector3, rate: float, delta: float) -> void:
	var to := SimPlayer._tangent(point - global_position, up)
	facing = SimPlayer._tangent(facing.slerp(to, minf(1.0, delta * rate)), up)


func _orient() -> void:
	global_basis = SimPlayer.frame(up, facing)
