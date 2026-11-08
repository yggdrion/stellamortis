class_name SimPlayer
extends CharacterBody3D
## A player's body and movement rules (PLAN §4.2). Runs on the server for every player and on
## the client for its own player (prediction). Movement happens in the plane of the current up
## vector, which follows gravity, so the same code walks on flat ground and around planetoids.

const HEIGHT := 1.8
const RADIUS := 0.4
## Collision layers: 1 world, 2 players. Players do not block each other, so the client's
## prediction needs no other players in its physics world.
const LAYER_WORLD := 1
const LAYER_PLAYERS := 2

var peer_id := 0
var player_name := ""
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


## One tick of movement from one input.
func step(input: PlayerInput, delta: float) -> void:
	var t := Tuning.data()
	var gravity := Gravity.sample(global_position)
	var strength := gravity.length()
	if strength > 0.001:
		_turn_frame(up.slerp(-gravity / strength, minf(1.0, delta / t.up_turn_time)))

	var look_forward := ref_forward.rotated(up, input.yaw)
	var look_right := look_forward.cross(up)
	var wish := look_right * input.move.x + look_forward * input.move.y
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var sprinting := input.has(PlayerInput.Buttons.SPRINT) and input.move.y > 0.3
	var speed := t.sprint_speed if sprinting else t.walk_speed

	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	var accel := t.ground_accel if grounded else t.air_accel
	horizontal = horizontal.move_toward(wish * speed, accel * delta)
	if grounded and input.has(PlayerInput.Buttons.JUMP):
		vertical = up * t.jump_speed
	vertical += gravity * delta

	velocity = horizontal + vertical
	up_direction = up
	move_and_slide()
	grounded = is_on_floor()

	if wish.length_squared() > 0.01:
		facing = facing.slerp(wish.normalized(), minf(1.0, delta * t.turn_rate))
	facing = _tangent(facing, up)
	_orient()


func get_state() -> PlayerState:
	var state := PlayerState.new()
	state.position = global_position
	state.velocity = velocity
	state.up = up
	state.ref_forward = ref_forward
	state.facing = facing
	state.grounded = grounded
	return state


func apply_state(state: PlayerState) -> void:
	global_position = state.position
	velocity = state.velocity
	up = state.up
	ref_forward = state.ref_forward
	facing = state.facing
	grounded = state.grounded
	_orient()


## Turns up to new_up and carries ref_forward and facing along (parallel transport).
func _turn_frame(new_up: Vector3) -> void:
	new_up = new_up.normalized()
	if up.is_equal_approx(new_up):
		return
	var turn := Quaternion(up, new_up)
	ref_forward = _tangent(turn * ref_forward, new_up)
	facing = _tangent(turn * facing, new_up)
	up = new_up


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
