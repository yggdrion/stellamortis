class_name SimPlayer
extends CharacterBody3D
## A player's body and movement rules (PLAN §4.2). netfox runs _rollback_tick on the server for
## every player and on the owning client for prediction and rollback (networked()). Movement
## happens in the plane of the current up vector, which follows gravity, so the same code walks
## on flat ground and around planetoids.

const HEIGHT := 1.8
const RADIUS := 0.4
## Collision layers: 1 world, 2 players. Players do not block each other, so the client's
## prediction needs no other players in its physics world.
const LAYER_WORLD := 1
const LAYER_PLAYERS := 2

## State netfox records, sends and rolls back. transform covers position and orientation.
const STATE := ["transform", "velocity", "up", "ref_forward", "facing", "grounded"]

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


func _init() -> void:
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
	for property: String in ["move", "yaw", "buttons"]:
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


## One tick of movement from one input.
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
	var sprinting := buttons & PlayerControls.Buttons.SPRINT != 0 and move.y > 0.3
	var speed := t.sprint_speed if sprinting else t.walk_speed

	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	var accel := t.ground_accel if grounded else t.air_accel
	horizontal = horizontal.move_toward(wish * speed, accel * delta)
	if grounded and buttons & PlayerControls.Buttons.JUMP != 0:
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

	if wish.length_squared() > 0.01:
		facing = facing.slerp(wish.normalized(), minf(1.0, delta * t.turn_rate))
	facing = _tangent(facing, up)
	_orient()


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
