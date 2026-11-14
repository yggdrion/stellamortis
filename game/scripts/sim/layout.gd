class_name Layout
extends RefCounted
## Where things are (PLAN §4.4, §6 M12), shared by the server and every client: the two planets,
## gravity zones, the asteroid, jump pads and portals. Arena builds collision and visuals from it,
## Gravity and SimPlayer read it during simulation.
##
## The realm (the encounter) sits at the origin: low-g zone east of the arrival with the
## asteroid floating above it, high-g zone to the west, the dead to the south. The hub, a keep on
## a plateau of a small planet, floats far above it. Both share one world, so the netcode needs no
## level loading; clients only show the planet their player is on (Arena.show_planet).

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

## The keep's yard floor center. Players spawn and respawn here.
const HUB := Vector3(0.0, 400.0, -600.0)
## The yard inside the keep walls (x by z) and the wall height.
const HUB_YARD := Vector2(40.0, 44.0)
const HUB_WALL := 7.0
const HUB_PLANET_RADIUS := 60.0
## Anything this close to the hub is on the hub planet; everything else is the realm.
const HUB_REACH := 200.0
## Training dummies in the keep's yard: position and whether it only takes hits (true) or also
## swings back.
const DUMMIES := [[HUB + Vector3(-4.0, 0.0, -10.0), true], [HUB + Vector3(4.0, 0.0, -10.0), false]]
## The realm's arrival ring (players face the encounter, +Z).
const REALM_ARRIVAL := Vector3.ZERO
## The encounter, south of the spawn in front of the long wall: melee mobs, the ranged mob
## (true), and where the Warden rises. All face north, toward the spawn.
const MOBS := [
	[Vector3(-6.0, 0.0, 24.0), false],
	[Vector3(6.0, 0.0, 24.0), false],
	[Vector3(0.0, 0.0, 33.0), true]
]
const BOSS := Vector3(0.0, 0.0, 30.0)
const SPAWN_RADIUS := 3.0
## Places on the spawn ring (more than GameServer.MAX_PLAYERS, so ids spread out).
const SPAWN_SLOTS := 10

static var _zones: Array[GravityZone] = []
static var _pads: Array[JumpPad] = []
static var _portals: Array[Portal] = []
static var _realms: Array[RealmDef] = []


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


## The keep's gate to the realm (south of the spawn), the realm's way home behind the arrival,
## and the portal that opens where the Warden fell.
static func portals() -> Array[Portal]:
	if _portals.is_empty():
		_portals = [
			Portal.at(HUB + Vector3(0, 0, 15), REALM_ARRIVAL, Vector3.BACK, "To the Barrows"),
			Portal.at(Vector3(-10, 0, -3), HUB, Vector3.BACK, "Home"),
			Portal.at(Vector3(0, 0, 22), HUB, Vector3.BACK, "Home", true),
		]
	return _portals


static func portal_at(feet: Vector3) -> Portal:
	for portal in portals():
		if portal.reaches(feet):
			return portal
	return null


## The generated realms (M20), loaded from res://data/realms.
static func realms() -> Array[RealmDef]:
	if _realms.is_empty():
		_realms = [load("res://data/realms/barrowlands.tres") as RealmDef]
	return _realms


## The realm whose gravity reaches this point (the nearest center), null in the hub or the old
## realm.
static func realm_at(point: Vector3) -> RealmDef:
	var best: RealmDef = null
	var best_distance := INF
	for realm in realms():
		var distance := point.distance_to(realm.center)
		if distance <= realm.reach() and distance < best_distance:
			best = realm
			best_distance = distance
	return best


static func on_hub(point: Vector3) -> bool:
	return point.distance_to(HUB) < HUB_REACH


static func pad_at(feet: Vector3) -> JumpPad:
	for pad in jump_pads():
		if pad.reaches(feet):
			return pad
	return null


## Where a player (re)spawns: a ring in the keep's yard, by peer id.
static func spawn_point(peer_id: int) -> Vector3:
	return ring_point(HUB, peer_id)


## A place on the ring around center for this peer (spawns and portal arrivals).
static func ring_point(center: Vector3, peer_id: int) -> Vector3:
	var angle := (peer_id % SPAWN_SLOTS) * TAU / SPAWN_SLOTS
	return center + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
