class_name Combat
extends RefCounted
## Combat formulas and lookups (PLAN §4.5); the numbers live in data/.

## Must match netfox/time/tickrate: rollback state counts ticks, data uses seconds.
const TICKRATE := 30
## Player attacks by index, so the rolled back state can hold an int.
const PLAYER_ATTACKS: Array[StringName] = [&"light_1", &"light_2", &"light_3", &"heavy"]

## The aiming camera's geometry, shared with CameraRig so the crosshair is where bolts go.
const AIM_HEAD := 1.7
const AIM_SHOULDER := 0.9
const AIM_ARM := 3.0
const AIM_RANGE := 120.0

static var _attacks := {}


static func ticks(seconds: float) -> int:
	return roundi(seconds * TICKRATE)


static func attack(id: StringName) -> AttackDef:
	if not _attacks.has(id):
		_attacks[id] = load("res://data/attacks/%s.tres" % id) as AttackDef
	return _attacks[id]


static func player_attack(index: int) -> AttackDef:
	return attack(PLAYER_ATTACKS[index])


## Whether a swing from origin toward forward (both in the plane of up) reaches a body of
## radius at target: within reach of its edge and inside the arc, widened by the body's size.
static func in_arc(
	origin: Vector3,
	forward: Vector3,
	up: Vector3,
	reach: float,
	arc_degrees: float,
	target: Vector3,
	radius: float
) -> bool:
	var to := target - origin
	to -= up * to.dot(up)
	var distance := to.length()
	if distance > reach + radius:
		return false
	if distance < radius:
		return true
	var half := deg_to_rad(arc_degrees) / 2.0 + asin(clampf(radius / distance, 0.0, 1.0))
	return forward.angle_to(to) <= half


## The aiming camera's basis for a player looking at yaw and pitch (CameraRig uses it too).
static func aim_basis(player: SimPlayer, yaw: float, pitch: float) -> Basis:
	return (
		SimPlayer.frame(player.up, player.ref_forward)
		* Basis(Vector3.UP, yaw)
		* Basis(Vector3.RIGHT, pitch)
	)


## Where the crosshair points: the first wall or enemy along the aiming camera's ray, or far
## along it.
static func aim_target(player: SimPlayer, yaw: float, pitch: float) -> Vector3:
	var basis := aim_basis(player, yaw, pitch)
	var origin := (
		player.global_position + player.up * AIM_HEAD + basis.x * AIM_SHOULDER + basis.z * AIM_ARM
	)
	var end := origin - basis.z * AIM_RANGE
	var enemy := enemy_on_segment(player, origin, end)
	if enemy:
		end = closest_on_segment(origin, end, enemy.center())
	var wall := ray(player, origin, end)
	return end if wall.is_empty() else wall.position


## The world (not enemies or players) along a segment: Godot's ray result, empty if clear. The
## arena never moves, so this is safe during rollback.
static func ray(from_node: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, SimPlayer.LAYER_WORLD)
	return from_node.get_world_3d().direct_space_state.intersect_ray(query)


## The first living enemy whose body (a capsule) a segment passes through, null if none.
static func enemy_on_segment(from_node: Node, from: Vector3, to: Vector3) -> Enemy:
	var best: Enemy = null
	var best_distance := INF
	for node in from_node.get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if not enemy.alive():
			continue
		var foot := enemy.global_position + enemy.up() * enemy.radius
		var head := enemy.global_position + enemy.up() * (enemy.height - enemy.radius)
		var closest := Geometry3D.get_closest_points_between_segments(from, to, foot, head)
		if closest[0].distance_to(closest[1]) > enemy.radius:
			continue
		var distance := from.distance_to(closest[0])
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best


static func closest_on_segment(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	return Geometry3D.get_closest_point_to_segment(point, from, to)
