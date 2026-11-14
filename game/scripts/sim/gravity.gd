class_name Gravity
extends RefCounted
## The gravity vector at a point (PLAN §4.4). A pure function of the position and the fixed
## zones in Layout, so the server and the client (prediction, rollback, later projectiles)
## always agree. Godot's physics gravity (Area3D overrides) is not used for gameplay.

const DEFAULT := Vector3(0.0, -9.8, 0.0)


static func sample(position: Vector3) -> Vector3:
	var zone := zone_at(position)
	return DEFAULT if zone == null else zone.gravity_at(position)


## Which way is up at a point: against the gravity, world up where there is none.
static func up_at(position: Vector3) -> Vector3:
	var gravity := sample(position)
	return -gravity.normalized() if gravity.length_squared() > 0.000001 else Vector3.UP


## The winning zone at a point, null for the world default.
static func zone_at(position: Vector3) -> GravityZone:
	var best: GravityZone = null
	for zone in Layout.gravity_zones():
		if (best == null or zone.priority > best.priority) and zone.contains(position):
			best = zone
	return best


## The pull of active gravity wells (the Warden's, PLAN §4.6) at a point. Kept apart from
## sample(): a well drags players sideways without turning their up vector.
static func pull(from_node: Node, position: Vector3) -> Vector3:
	var total := Vector3.ZERO
	for node in from_node.get_tree().get_nodes_in_group(Enemy.WELLS):
		var zone := (node as Enemy).well_zone()
		if zone and zone.contains(position):
			total += zone.gravity_at(position)
	return total
