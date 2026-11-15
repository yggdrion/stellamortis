class_name Layout
extends RefCounted
## Where things are (PLAN §4.4, §6 M12), shared by the server and every client: the two planets,
## gravity zones, the asteroid, jump pads and portals. Arena builds collision and visuals from it,
## Gravity and SimPlayer read it during simulation.
##
## The old realm (the encounter) sits at the origin: low-g zone east of the arrival with the
## asteroid floating above it, high-g zone to the west, the dead to the south. The generated
## realms (the Barrowlands, where every player starts) are round worlds far from it. All share one
## world, so the netcode needs no level loading; clients only show the place their player is in
## (Arena.show_place).

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

## Training dummies beside the first realm's arrival: how far ahead of it (along the way the
## players face), how far to the side (right is positive), and whether it only takes hits (true)
## or also swings back.
const DUMMIES := [[8.0, -4.0, true], [8.0, 4.0, false]]
## The old realm's arrival ring (players face the encounter, +Z).
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
## Where a realm's gate to the old barrow stands: this far behind the arrival, in the tangent
## plane.
const REALM_GATE_BEHIND := 10.0
## Arrivals on a realm's ground start this far above it (the capsule settles).
const ARRIVAL_LIFT := 0.1
## The name of the place a point is in when no realm reaches it (place_at).
const ORIGIN_PLACE := &"origin"
## Places on the spawn ring (more than GameServer.MAX_PLAYERS, so ids spread out).
const SPAWN_SLOTS := 10

static var _zones: Array[GravityZone] = []
static var _pads: Array[JumpPad] = []
static var _portals: Array[Portal] = []
static var _realms: Array[RealmDef] = []
## The world seed, set once by World.build before anyone travels: the gates on a realm's ground
## and every realm arrival depend on it.
static var _world_seed := 0


static func gravity_zones() -> Array[GravityZone]:
	if _zones.is_empty():
		_zones = [
			GravityZone.box("low gravity", LOW_G_CENTER, LOW_G_SIZE, LOW_G),
			GravityZone.box("high gravity", HIGH_G_CENTER, HIGH_G_SIZE, HIGH_G),
			GravityZone.sphere("asteroid", ASTEROID_CENTER, ASTEROID_REACH, ASTEROID_G),
		]
		for realm in realms():
			_zones.append(GravityZone.sphere(realm.id, realm.center, realm.reach(), realm.gravity))
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


## Sets the world seed (World.build) and drops the gates that depend on it.
static func set_world_seed(world_seed: int) -> void:
	_world_seed = world_seed
	_portals.clear()


## The old realm's way back to the first realm's arrival, the portal that opens where the Warden
## fell (also back), then each realm's gate to the old barrow (on its ground, so it moves with the
## world seed).
static func portals() -> Array[Portal]:
	if _portals.is_empty():
		var start := start_realm()
		_portals = [
			Portal.at(Vector3(-10, 0, -3), Vector3.ZERO, Vector3.BACK, "Home"),
			Portal.at(Vector3(0, 0, 22), Vector3.ZERO, Vector3.BACK, "Home", true),
		]
		_portals[0].realm = start.id
		_portals[1].realm = start.id
		for realm in realms():
			_portals.append(arrival_gate(realm))
	return _portals


## The gate standing behind a realm's arrival point, leading to the old realm at the origin.
static func arrival_gate(realm: RealmDef) -> Portal:
	var ground := Terrain.surface(realm, _world_seed, realm.arrival)
	var up := (ground - realm.center).normalized()
	var behind := Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	var direction := (ground - realm.center + behind.normalized() * REALM_GATE_BEHIND).normalized()
	var gate := Portal.at(
		Terrain.surface(realm, _world_seed, direction),
		REALM_ARRIVAL,
		Vector3.BACK,
		"To the old barrow"
	)
	gate.up = direction
	gate.seeded = true
	return gate


## Training dummy i's post on the first realm's ground, beside its arrival: [feet, up].
static func dummy_post(i: int) -> Array:
	var offset: Array = DUMMIES[i]
	return arrival_spot(start_realm(), float(offset[0]), float(offset[1]))


## A spot on a realm's ground this far ahead of (+Z in the tangent plane) and to the right of its
## arrival point: [feet, up]. Pure in the realm and the world seed.
static func arrival_spot(realm: RealmDef, ahead_m: float, right_m: float) -> Array:
	var ground := Terrain.surface(realm, _world_seed, realm.arrival)
	var up := (ground - realm.center).normalized()
	var ahead := SimPlayer._tangent(Vector3.BACK, up)
	var right := up.cross(ahead)
	var spot := ground + ahead * ahead_m + right * right_m
	var direction := (spot - realm.center).normalized()
	return [Terrain.surface(realm, _world_seed, direction), direction]


## The portal whose ring this body (standing along its local up) is in.
static func portal_at(feet: Vector3) -> Portal:
	var gravity := Gravity.sample(feet)
	var up := -gravity.normalized() if gravity.length_squared() > 0.000001 else Vector3.UP
	for portal in portals():
		if portal.reaches(feet, up):
			return portal
	return null


## Where a body arrives through a portal: a ring spot around its destination, on the ground when
## the destination is a generated realm (found from the world seed, the same on every peer).
static func arrival_point(portal: Portal, peer_id: int) -> Vector3:
	var realm := realm_by_id(portal.realm)
	if realm == null:
		return ring_point(portal.to, peer_id)
	return _ring_on_ground(realm, peer_id)


## A place on the ring around a realm's arrival, on its ground (found from the world seed, the
## same on every peer).
static func _ring_on_ground(realm: RealmDef, peer_id: int) -> Vector3:
	var ground := Terrain.surface(realm, _world_seed, realm.arrival)
	var up := (ground - realm.center).normalized()
	var spot := ring_point(ground, peer_id, up)
	var direction := (spot - realm.center).normalized()
	return Terrain.surface(realm, _world_seed, direction) + direction * ARRIVAL_LIFT


static func realm_by_id(id: String) -> RealmDef:
	for realm in realms():
		if realm.id == id:
			return realm
	return null


## The generated realms (M20), loaded from res://data/realms.
static func realms() -> Array[RealmDef]:
	if _realms.is_empty():
		_realms = [load("res://data/realms/barrowlands.tres") as RealmDef]
	return _realms


## The first realm: where players start and the old realm leads back to.
static func start_realm() -> RealmDef:
	return realms()[0]


## The realm whose gravity reaches this point (the nearest center), null in the old realm.
static func realm_at(point: Vector3) -> RealmDef:
	var best: RealmDef = null
	var best_distance := INF
	for realm in realms():
		var distance := point.distance_to(realm.center)
		if distance <= realm.reach() and distance < best_distance:
			best = realm
			best_distance = distance
	return best


## Which place a point is in: a generated realm (its id) or the old realm at the origin.
static func place_at(point: Vector3) -> StringName:
	var realm := realm_at(point)
	if realm != null:
		return StringName(realm.id)
	return ORIGIN_PLACE


static func pad_at(feet: Vector3) -> JumpPad:
	for pad in jump_pads():
		if pad.reaches(feet):
			return pad
	return null


## Where a player (re)spawns: the ring around the first realm's arrival gate, on the ground, by
## peer id (the chunks under it are pinned, World.build).
static func spawn_point(peer_id: int) -> Vector3:
	return _ring_on_ground(start_realm(), peer_id)


## A place on the ring around center for this peer (spawns and portal arrivals), in the plane
## perpendicular to up (the world's XZ plane for the default).
static func ring_point(center: Vector3, peer_id: int, up := Vector3.UP) -> Vector3:
	var angle := (peer_id % SPAWN_SLOTS) * TAU / SPAWN_SLOTS
	var seed_axis := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	var x_axis := (seed_axis - up * seed_axis.dot(up)).normalized()
	var z_axis := x_axis.cross(up)
	return center + (x_axis * cos(angle) + z_axis * sin(angle)) * SPAWN_RADIUS
