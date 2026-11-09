class_name JumpPad
extends RefCounted
## Stand on it and jump to be launched along your up vector at `speed` (PLAN §4.4: how players
## reach the asteroid and come back). Pure data, checked in SimPlayer.step, so it rolls back.

var position := Vector3.ZERO
## Up of the surface it sits on, for drawing it.
var normal := Vector3.UP
var radius := 1.6
var speed := 12.0


static func at(where: Vector3, surface_normal: Vector3, launch_speed: float) -> JumpPad:
	var pad := JumpPad.new()
	pad.position = where
	pad.normal = surface_normal.normalized()
	pad.speed = launch_speed
	return pad


func reaches(feet: Vector3) -> bool:
	return feet.distance_to(position) <= radius
