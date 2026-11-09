class_name Layout
extends RefCounted
## Where things are in the PoC arena (PLAN §4.4), shared by the server and every client: gravity
## zones, the asteroid and the jump pads. Arena builds collision and visuals from it, Gravity
## and SimPlayer read it during simulation.
##
## Low-g zone east of the spawn with the asteroid floating above it, high-g zone to the west.

const LOW_G_CENTER := Vector3(40.0, 9.0, 0.0)
const LOW_G_SIZE := Vector3(30.0, 18.0, 40.0)
const LOW_G := 3.0
const HIGH_G_CENTER := Vector3(-40.0, 10.0, 0.0)
const HIGH_G_SIZE := Vector3(30.0, 20.0, 40.0)
const HIGH_G := 22.0
const ASTEROID_CENTER := Vector3(40.0, 50.0, 0.0)
const ASTEROID_RADIUS := 18.0
## Gravity reaches this far from the asteroid's center.
const ASTEROID_REACH := 34.0
const ASTEROID_G := 7.0
## Launch speeds, along the up of whoever stands on the pad.
const GROUND_PAD_SPEED := 12.0
const RETURN_PAD_SPEED := 17.0

## Training dummies: position and whether it only takes hits (true) or also swings back.
const DUMMIES := [[Vector3(-4.0, 0.0, -10.0), true], [Vector3(4.0, 0.0, -10.0), false]]
## The encounter, south of the spawn in front of the long wall: melee mobs, the ranged mob
## (true), and where the Warden rises. All face north, toward the spawn.
const MOBS := [
	[Vector3(-6.0, 0.0, 24.0), false],
	[Vector3(6.0, 0.0, 24.0), false],
	[Vector3(0.0, 0.0, 33.0), true]
]
const BOSS := Vector3(0.0, 0.0, 30.0)
const SPAWN_RADIUS := 3.0
const MAX_PLAYERS := 10

static var _zones: Array[GravityZone] = []
static var _pads: Array[JumpPad] = []


static func gravity_zones() -> Array[GravityZone]:
	if _zones.is_empty():
		_zones = [
			GravityZone.box("low gravity", LOW_G_CENTER, LOW_G_SIZE, LOW_G),
			GravityZone.box("high gravity", HIGH_G_CENTER, HIGH_G_SIZE, HIGH_G),
			GravityZone.sphere("asteroid", ASTEROID_CENTER, ASTEROID_REACH, ASTEROID_G),
		]
	return _zones


static func jump_pads() -> Array[JumpPad]:
	if _pads.is_empty():
		_pads = [
			# Off the pole below the asteroid, so the launch lands beside the return pad.
			JumpPad.at(Vector3(40.0, 0.0, 6.0), Vector3.UP, GROUND_PAD_SPEED),
			# The asteroid's bottom pole: its up points at the ground.
			JumpPad.at(
				ASTEROID_CENTER + Vector3.DOWN * ASTEROID_RADIUS, Vector3.DOWN, RETURN_PAD_SPEED
			),
		]
	return _pads


static func pad_at(feet: Vector3) -> JumpPad:
	for pad in jump_pads():
		if pad.reaches(feet):
			return pad
	return null


## Where a player (re)spawns: a ring around the origin, by peer id.
static func spawn_point(peer_id: int) -> Vector3:
	var angle := (peer_id % MAX_PLAYERS) * TAU / MAX_PLAYERS
	return Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
