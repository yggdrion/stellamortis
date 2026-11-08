class_name Gravity
extends RefCounted
## The gravity vector at a point (PLAN §4.4). A pure function of the position, so the server
## and the client (prediction, later projectiles) always agree. M1 adds zones.

const DEFAULT := Vector3(0.0, -9.8, 0.0)


static func sample(_position: Vector3) -> Vector3:
	return DEFAULT
