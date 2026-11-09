class_name Combat
extends RefCounted
## Combat formulas and lookups (PLAN §4.5); the numbers live in data/.

## Must match netfox/time/tickrate: rollback state counts ticks, data uses seconds.
const TICKRATE := 30
## Player attacks by index, so the rolled back state can hold an int.
const PLAYER_ATTACKS: Array[StringName] = [&"light_1", &"light_2", &"light_3", &"heavy"]

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
