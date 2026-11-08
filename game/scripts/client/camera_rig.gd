class_name CameraRig
extends Node3D
## Third-person orbit camera (PLAN §4.4). Yaw and pitch are relative to the followed player's
## up vector and reference forward, so the horizon stays steady on any gravity. The yaw is also
## what the player's input yaw is measured in.

const HEAD_HEIGHT := 1.5
const ARM_LENGTH := 4.5
const SHOULDER_OFFSET := 0.6
const PITCH_MIN := deg_to_rad(-70.0)
const PITCH_MAX := deg_to_rad(60.0)
## Per second, how fast the camera's up follows the player's (exponential).
const UP_FOLLOW := 8.0

var target: SimPlayer
var yaw := 0.0
var pitch := deg_to_rad(-15.0)
var camera: Camera3D
var _up := Vector3.UP


func _ready() -> void:
	var arm := SpringArm3D.new()
	arm.spring_length = ARM_LENGTH
	arm.collision_mask = SimPlayer.LAYER_WORLD
	arm.margin = 0.2
	arm.position.x = SHOULDER_OFFSET
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 2000.0
	arm.add_child(camera)
	camera.make_current()


func look(relative: Vector2) -> void:
	yaw = fposmod(yaw - relative.x * Controls.MOUSE_SENSITIVITY, TAU)
	pitch = clampf(pitch - relative.y * Controls.MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)


func _process(delta: float) -> void:
	if target == null:
		return
	_up = _up.slerp(target.up, minf(1.0, delta * UP_FOLLOW)).normalized()
	var base := SimPlayer.frame(_up, SimPlayer._tangent(target.ref_forward, _up))
	var feet := target.get_global_transform_interpolated().origin
	global_transform = Transform3D(
		base * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), feet + _up * HEAD_HEIGHT
	)
