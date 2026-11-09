class_name GravityZone
extends RefCounted
## A volume with its own gravity (PLAN §4.4): a box with a fixed direction, or a sphere pulling
## toward its center. Where zones overlap, the highest priority wins.

enum Mode { DIRECTIONAL, POINT }

var mode := Mode.DIRECTIONAL
## Box zones: center and full size, axis-aligned. Point zones: center and radius of influence.
var center := Vector3.ZERO
var size := Vector3.ZERO
var radius := 0.0
## Directional zones: where gravity pulls (normalized).
var direction := Vector3.DOWN
## m/s².
var strength := 9.8
var priority := 0
## What the zone is called in the debug overlay.
var label := ""


static func box(
	zone_label: String, at: Vector3, extent: Vector3, pull: float, prio := 1, down := Vector3.DOWN
) -> GravityZone:
	var zone := GravityZone.new()
	zone.label = zone_label
	zone.center = at
	zone.size = extent
	zone.strength = pull
	zone.priority = prio
	zone.direction = down.normalized()
	return zone


static func sphere(
	zone_label: String, at: Vector3, reach: float, pull: float, prio := 2
) -> GravityZone:
	var zone := GravityZone.new()
	zone.label = zone_label
	zone.mode = Mode.POINT
	zone.center = at
	zone.radius = reach
	zone.strength = pull
	zone.priority = prio
	return zone


func contains(point: Vector3) -> bool:
	if mode == Mode.POINT:
		return point.distance_squared_to(center) <= radius * radius
	var d := (point - center).abs()
	return d.x <= size.x / 2.0 and d.y <= size.y / 2.0 and d.z <= size.z / 2.0


func gravity_at(point: Vector3) -> Vector3:
	if mode == Mode.DIRECTIONAL:
		return direction * strength
	var to_center := center - point
	if to_center.length_squared() < 0.0001:
		return Vector3.ZERO
	return to_center.normalized() * strength
