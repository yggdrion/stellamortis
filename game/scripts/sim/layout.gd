class_name Layout
extends RefCounted
## Where things are (PLAN §4.4, §6 M12), shared by the server and every client: the generated
## realms (round worlds far apart, the Barrowlands is where every player starts), their gravity
## zones, the gates between them and the places on a realm's ground. Arena builds collision and
## visuals from it, Gravity and SimPlayer read it during simulation. All realms share one world,
## so the netcode needs no level loading; clients only show the place their player is in
## (Arena.show_place).

## Training dummies beside the first realm's arrival: how far ahead of it (along the way the
## players face), how far to the side (right is positive), and whether it only takes hits (true)
## or also swings back.
const DUMMIES := [[8.0, -4.0, true], [8.0, 4.0, false]]
const SPAWN_RADIUS := 3.0
## Arrivals on a realm's ground start this far above it (the capsule settles).
const ARRIVAL_LIFT := 0.1
## The name of the place a point is in when no realm reaches it (place_at).
const NO_PLACE := &""
## Places on the spawn ring (more than GameServer.MAX_PLAYERS, so ids spread out).
const SPAWN_SLOTS := 10

static var _zones: Array[GravityZone] = []
static var _pads: Array[JumpPad] = []
static var _portals: Array[Portal] = []
static var _realms: Array[RealmDef] = []
## The world seed, set once by World.build before anyone travels: the gates on a realm's ground
## and every realm arrival depend on it.
static var _world_seed := 0


## One gravity zone per realm, a sphere pulling to its center (tests may append more).
static func gravity_zones() -> Array[GravityZone]:
	if _zones.is_empty():
		for realm in realms():
			_zones.append(GravityZone.sphere(realm.id, realm.center, realm.reach(), realm.gravity))
	return _zones


## Pads that launch a jumping player along their up (none now; the Skyshards bring them back
## in M28, tests add their own).
static func jump_pads() -> Array[JumpPad]:
	return _pads


## Sets the world seed (World.build) and drops the gates that depend on it.
static func set_world_seed(world_seed: int) -> void:
	_world_seed = world_seed
	_portals.clear()


## The gates between realms (none yet: M26 adds the one to Myrkfen at the arrival, shut until
## the Warden's flag is set; tests add their own).
static func portals() -> Array[Portal]:
	return _portals


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


## The first realm: where players start and respawn.
static func start_realm() -> RealmDef:
	return realms()[0]


## The realm whose gravity reaches this point (the nearest center), null in open space.
static func realm_at(point: Vector3) -> RealmDef:
	var best: RealmDef = null
	var best_distance := INF
	for realm in realms():
		var distance := point.distance_to(realm.center)
		if distance <= realm.reach() and distance < best_distance:
			best = realm
			best_distance = distance
	return best


## Which place a point is in: a generated realm (its id), NO_PLACE in open space.
static func place_at(point: Vector3) -> StringName:
	var realm := realm_at(point)
	if realm != null:
		return StringName(realm.id)
	return NO_PLACE


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
