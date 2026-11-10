class_name Enemy
extends CharacterBody3D
## What players fight (PLAN §4.5, §4.6): server-owned, rolled back by netfox with prediction, so
## clients simulate it between server states. Players check enemy swings and bolts in their own
## rollback tick (SimPlayer._defend) and hit enemies with take_hit + NetworkRollback.mutate.
## Subclasses: TrainingDummy (M2), Mob and Warden (M5). Every enemy exists on every peer from the
## start (netfox finds them by path); the encounter hides, wakes and resets them.

enum Action { IDLE, WINDUP, STRIKE, RECOVER, STAGGER, DOWN, HIDDEN, RISE }

const HEIGHT := 1.8
const RADIUS := 0.5
const GROUP := &"enemies"
## Rolled back state; subclasses append their own.
const STATE := ["transform", "facing", "health", "action", "action_time", "parried", "quiet_time"]
## State of enemies that walk and shoot (Mob, Warden).
const ACTOR_STATE := ["velocity", "attack", "bolt_pos", "bolt_vel", "bolt_life"]
const BOLTS := ["bolt_pos", "bolt_vel", "bolt_life"]
## How close a bolt must pass a body's axis to hit it, on top of the body's radius.
const BOLT_RADIUS := 0.2

## Stable across peers (World assigns it): the bit in a player's swing_hits.
var index := 0
var max_health := 400.0
var attack_id: StringName = &"dummy_swing"
## Damage multiplier for hits while staggered by a parry.
var riposte := 2.5
var stagger_time := 1.5
var down_time := 2.0
## Body size; set_size() before adding to the tree changes it.
var height := HEIGHT
var radius := RADIUS
## Where reset() puts it.
var home := Transform3D.IDENTITY
## Attack ids this enemy can use, `attack` indexes it (rolled back).
var attacks: Array[StringName] = []
## The attack its bolts deal damage with.
var shot_attack: StringName = &""

var facing := Vector3.FORWARD
var health := 400.0
var action := Action.IDLE
var action_time := 0
## Staggered by a parry (riposte bonus), not by something else.
var parried := false
## Ticks since it last took damage.
var quiet_time := 0
var attack := 0
var bolt_pos := PackedVector3Array()
var bolt_vel := PackedVector3Array()
## Ticks left in flight, 0 for a free slot.
var bolt_life := PackedInt32Array()

## The packed groups netfox synchronizes (the synced list in networked()).
var net_combat: PackedByteArray:
	get:
		return Wire.pack(self, _combat_fields)
	set(value):
		Wire.unpack(self, _combat_fields, value)
var net_bolts: PackedByteArray:
	get:
		return Wire.pack(self, BOLTS)
	set(value):
		Wire.unpack(self, BOLTS, value)

var _shape: CollisionShape3D
## The rolled back fields besides transform, velocity and bolts, packed into net_combat.
var _combat_fields: Array = []


func _init() -> void:
	collision_layer = SimPlayer.LAYER_ENEMIES
	# Enemies shove each other aside instead of walking through one another; players don't
	# block them (players bump into enemies, not the other way round).
	collision_mask = SimPlayer.LAYER_WORLD | SimPlayer.LAYER_ENEMIES
	floor_snap_length = 0.3
	_shape = CollisionShape3D.new()
	add_child(_shape)
	set_size(RADIUS, HEIGHT)
	add_to_group(GROUP)


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


## Server-owned, predicted on clients. Call before adding it to the tree, on every peer. state
## is every rolled back field (Enemy.STATE, plus ACTOR_STATE and subclass fields); netfox
## synchronizes them as transform, velocity, net_combat and net_bolts (Wire.pack).
func networked(state: Array) -> void:
	var synced := ["transform", "net_combat"]
	_combat_fields = []
	for field: String in state:
		if field == "velocity":
			synced.append(field)
		elif field in BOLTS:
			if not "net_bolts" in synced:
				synced.append("net_bolts")
		elif field != "transform":
			_combat_fields.append(field)
	var rollback := RollbackSynchronizer.new()
	rollback.name = "Rollback"
	rollback.root = self
	rollback.enable_prediction = true
	for property: String in synced:
		rollback.state_properties.append(":" + property)
	rollback.set_schema(Wire.schema(synced))
	add_child(rollback)


func attack_def() -> AttackDef:
	if attacks.is_empty():
		return Combat.attack(attack_id)
	return Combat.attack(attacks[attack])


func shot_def() -> AttackDef:
	return Combat.attack(shot_attack)


func center() -> Vector3:
	return global_position + global_basis.y * (height / 2.0)


func up() -> Vector3:
	return global_basis.y


## Where the current attack's hit area is centered.
func strike_origin() -> Vector3:
	return center() + facing * attack_def().offset


func alive() -> bool:
	return action != Action.DOWN and action != Action.HIDDEN


## In the hit window of a melee attack this tick.
func striking() -> bool:
	return action == Action.STRIKE and attack_def().melee()


## Windup length scale (the Warden speeds up in phase 2).
func pace() -> float:
	return 1.0


func windup_ticks() -> int:
	return maxi(1, roundi(attack_def().windup_ticks() * pace()))


## A player's hit. Returns the damage dealt.
func take_hit(amount: float) -> float:
	if not alive() or action == Action.RISE:
		return 0.0
	if action == Action.STAGGER and parried:
		amount *= riposte
	health -= amount
	quiet_time = 0
	if health <= 0.0:
		health = 0.0
		_set_action(Action.DOWN)
	return amount


## A player parried its swing.
func parry() -> void:
	_set_action(Action.STAGGER)
	parried = true


## Back to where and how it started (encounter reset).
func reset(start: Action) -> void:
	global_transform = home
	facing = -home.basis.z
	velocity = Vector3.ZERO
	health = max_health
	attack = 0
	quiet_time = 0
	for i in bolt_life.size():
		bolt_life[i] = 0
	_set_action(start)
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
	var def := attack_def()
	match action:
		Action.WINDUP:
			if action_time >= windup_ticks():
				_set_action(Action.STRIKE)
				_on_strike(def)
		Action.STRIKE:
			if action_time >= Combat.ticks(def.active):
				_set_action(Action.RECOVER)
		Action.RECOVER:
			if action_time >= Combat.ticks(def.recover):
				_set_action(Action.IDLE)
				return false
		_:
			return false
	return true


func _start_attack(which: int) -> void:
	attack = which
	_set_action(Action.WINDUP)


## The strike begins: ranged attacks fire here (melee ones are checked by the players).
func _on_strike(def: AttackDef) -> void:
	if def.bolts == 0:
		return
	var target := nearest_player(60.0)
	if target:
		_fire(def, target.center())


## Fires def.bolts in a fan toward a point, aimed up to make up for the gravity on the way.
func _fire(def: AttackDef, at: Vector3) -> void:
	var muzzle := center() + facing * (radius + 0.3)
	var to := at - muzzle
	var flight := to.length() / def.bolt_speed
	var gravity := Gravity.sample(muzzle)
	var base := to.normalized() * def.bolt_speed - gravity * (flight / 2.0)
	for n in def.bolts:
		var slot := bolt_life.find(0)
		if slot < 0:
			return
		var fan := 0.0
		if def.bolts > 1:
			fan = deg_to_rad(def.spread_degrees) * (float(n) / (def.bolts - 1) - 0.5)
		bolt_pos[slot] = muzzle
		bolt_vel[slot] = base.rotated(up(), fan)
		bolt_life[slot] = Combat.ticks(4.0)


## Moves its bolts one tick under the local gravity; walls end them (players end them in
## their own tick, SimPlayer._defend).
func _fly_bolts(delta: float) -> void:
	for i in bolt_life.size():
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


## Walks along wish (tangent, length up to 1) at speed, under gravity, on its own up.
func _walk(wish: Vector3, speed: float, delta: float) -> void:
	var body_up := up()
	var vertical := body_up * velocity.dot(body_up)
	var horizontal := velocity - vertical
	horizontal = horizontal.move_toward(wish * speed, 30.0 * delta)
	vertical += Gravity.sample(global_position) * delta
	velocity = horizontal + vertical
	up_direction = body_up
	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor


func _turn_toward(point: Vector3, rate: float, delta: float) -> void:
	var to := SimPlayer._tangent(point - global_position, up())
	facing = SimPlayer._tangent(facing.slerp(to, minf(1.0, delta * rate)), up())


func _orient() -> void:
	global_basis = SimPlayer.frame(up(), facing)
