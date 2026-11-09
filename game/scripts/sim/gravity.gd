class_name Gravity
extends RefCounted
## The gravity vector at a point (PLAN §4.4). A pure function of the position and the fixed
## zones in Layout, so the server and the client (prediction, rollback, later projectiles)
## always agree. Godot's physics gravity (Area3D overrides) is not used for gameplay.

const DEFAULT := Vector3(0.0, -9.8, 0.0)


static func sample(position: Vector3) -> Vector3:
	var zone := zone_at(position)
	return DEFAULT if zone == null else zone.gravity_at(position)


## The winning zone at a point, null for the world default.
static func zone_at(position: Vector3) -> GravityZone:
	var best: GravityZone = null
	for zone in Layout.gravity_zones():
		if (best == null or zone.priority > best.priority) and zone.contains(position):
			best = zone
	return best
