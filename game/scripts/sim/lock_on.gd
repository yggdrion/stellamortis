class_name LockOn
extends RefCounted
## Lock-on target picking (PLAN §4.5). Pure functions over the enemies in the tree, so the
## player's rollback tick can call them: the target is an Enemy.index in the player's state.

const NONE := -1
## Locking and switching look from about the camera's position.
const EYE_HEIGHT := 1.5


## The living enemy with this index, null if none.
static func enemy(from_node: Node, index: int) -> Enemy:
	if index == NONE:
		return null
	for node in from_node.get_tree().get_nodes_in_group(Enemy.GROUP):
		var candidate := node as Enemy
		if candidate.index == index:
			return candidate if candidate.alive() else null
	return null


## The enemy nearest to where the camera looks (yaw, pitch), within lock_range and lock_angle
## and in sight; NONE if there is none.
static func pick(player: SimPlayer, yaw: float, pitch: float) -> int:
	var t := Tuning.data()
	var look := -Combat.aim_basis(player, yaw, pitch).z
	var best := NONE
	var best_angle := deg_to_rad(t.lock_angle)
	for candidate in _in_sight(player, t.lock_range):
		var angle := look.angle_to(candidate.center() - _eye(player))
		if angle < best_angle:
			best = candidate.index
			best_angle = angle
	return best


## The next enemy to the right (side > 0) or left (side < 0) of the current target as seen
## from the player, the closest by angle; the current target if there is none that way.
static func switch(player: SimPlayer, current: int, side: int) -> int:
	var locked := enemy(player, current)
	if locked == null:
		return current
	var t := Tuning.data()
	var eye := _eye(player)
	var forward := SimPlayer._tangent(locked.center() - eye, player.up)
	var right := forward.cross(player.up)
	var best := current
	var best_angle := PI
	for candidate in _in_sight(player, t.lock_range):
		if candidate == locked:
			continue
		var to := candidate.center() - eye
		var angle := atan2(to.dot(right), to.dot(forward)) * signf(side)
		if angle > 0.0 and angle < best_angle:
			best = candidate.index
			best_angle = angle
	return best


## Whether a lock on this enemy holds: alive, within lock_keep_range.
static func holds(player: SimPlayer, target: Enemy) -> bool:
	return (
		target != null
		and (
			target.global_position.distance_to(player.global_position)
			<= Tuning.data().lock_keep_range
		)
	)


static func _in_sight(player: SimPlayer, within: float) -> Array[Enemy]:
	var found: Array[Enemy] = []
	var eye := _eye(player)
	for node in player.get_tree().get_nodes_in_group(Enemy.GROUP):
		var candidate := node as Enemy
		if not candidate.alive():
			continue
		if candidate.global_position.distance_to(player.global_position) > within:
			continue
		if not Combat.ray(player, eye, candidate.center()).is_empty():
			continue
		found.append(candidate)
	return found


static func _eye(player: SimPlayer) -> Vector3:
	return player.global_position + player.up * EYE_HEIGHT
