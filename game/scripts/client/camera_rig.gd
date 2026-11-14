class_name CameraRig
extends Node3D
## Third-person orbit camera (PLAN §4.4). Yaw and pitch are relative to the followed player's
## up vector and reference forward, so the horizon stays steady on any gravity. The yaw is also
## what the player's input yaw is measured in. While aiming it moves in over the shoulder to
## Combat's aim geometry, so the screen center is where bolts go.

const HEAD_HEIGHT := 1.5
const ARM_LENGTH := 4.5
const SHOULDER_OFFSET := 0.6
const PITCH_MIN := deg_to_rad(-70.0)
const PITCH_MAX := deg_to_rad(60.0)
## Per second, how fast the camera's up follows the player's (exponential).
const UP_FOLLOW := 8.0
## Per second, how fast it moves between the normal and the aiming position.
const AIM_FOLLOW := 12.0
const FOV := 70.0
const AIM_FOV := 55.0
## Shake: how fast trauma dies down (per second), and the largest offset (m) and roll (rad).
const SHAKE_DECAY := 2.5
const SHAKE_OFFSET := 0.12
const SHAKE_ROLL := 0.02

## Shake left, 0..1; views add to it with shake().
static var trauma := 0.0

var target: SimPlayer
var yaw := 0.0
var pitch := deg_to_rad(-15.0)
var camera: Camera3D
var aiming := false
var _up := Vector3.UP
var _arm: SpringArm3D
## 0 normal, 1 aiming.
var _aim := 0.0


func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = ARM_LENGTH
	_arm.collision_mask = SimPlayer.LAYER_WORLD
	_arm.margin = 0.2
	_arm.position.x = SHOULDER_OFFSET
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.1
	camera.far = 2000.0
	_arm.add_child(camera)
	camera.make_current()


## Kicks the camera for a hit (strength 0..1, scaled by Settings.shake).
static func shake(strength: float) -> void:
	trauma = minf(1.0, trauma + strength * Settings.shake)


func look(relative: Vector2) -> void:
	yaw = fposmod(yaw - relative.x * Controls.MOUSE_SENSITIVITY * Settings.sensitivity, TAU)
	pitch = clampf(
		pitch - relative.y * Controls.MOUSE_SENSITIVITY * Settings.sensitivity, PITCH_MIN, PITCH_MAX
	)


func _process(delta: float) -> void:
	if target == null:
		return
	_up = _up.slerp(target.up, minf(1.0, delta * UP_FOLLOW)).normalized()
	var base := SimPlayer.frame(_up, SimPlayer._tangent(target.ref_forward, _up))
	# netfox's TickInterpolator moves the body smoothly between ticks.
	var feet := target.global_position
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta * AIM_FOLLOW * 0.5)
	var a := smoothstep(0.0, 1.0, _aim)
	_arm.spring_length = lerpf(ARM_LENGTH, Combat.AIM_ARM, a)
	_arm.position.x = lerpf(SHOULDER_OFFSET, Combat.AIM_SHOULDER, a)
	camera.fov = lerpf(FOV, AIM_FOV, a)
	trauma = maxf(0.0, trauma - SHAKE_DECAY * delta)
	var kick := trauma * trauma
	camera.h_offset = randf_range(-1.0, 1.0) * kick * SHAKE_OFFSET
	camera.v_offset = randf_range(-1.0, 1.0) * kick * SHAKE_OFFSET
	camera.rotation.z = randf_range(-1.0, 1.0) * kick * SHAKE_ROLL
	global_transform = Transform3D(
		base * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch),
		feet + _up * lerpf(HEAD_HEIGHT, Combat.AIM_HEAD, a)
	)
