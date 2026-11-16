class_name BossSite
extends RefCounted
## Where a realm's boss fight happens (M22): a ring of standing stones on a flat disc far from
## the arrival. A pure function of (realm, world seed), so every peer and every worker thread
## agrees; Terrain.Field flattens the ground around it, Scatter stands the stones, Spawner keeps
## camps away, Encounter raises the Warden when a player enters the ring.
##
## The spot is the flattest of CANDIDATES random ones between MIN_ARC and MAX_ARC meters (along
## the ground) from the arrival, judged on the raw terrain (Terrain.Field without a site). The
## flat level is the mean raw height around it, so the blend into the surrounding ground is as
## gentle as the candidates allow. Cached per realm and seed: finding it samples the noise
## hundreds of times and every Terrain.Field asks for it.

## Distance from the arrival along the ground, meters.
const MIN_ARC := 450.0
const MAX_ARC := 800.0
const CANDIDATES := 24
const PROBES := 8
## The ring of standing stones, the fight starts when a player is inside it.
const RING_RADIUS := 12.0
const STONES := 8
## How far from the middle a debug spawn stands (--encounter=boss).
const SPAWN_RING := 8.0
## Dead flat out to FLAT, then a smoothstep back to the raw ground over BLEND meters.
const FLAT := 24.0
const BLEND := 26.0
## The fight resets when no living player is within this many meters of the center (the
## Warden notices players within 80 m).
const REACH := 80.0
## Nothing else stands within FLAT + BLEND + this of the center (camps, trees).
const CLEAR_MARGIN := 6.0

static var _cache := {}
static var _lock := Mutex.new()

var realm: RealmDef
## Unit direction from the realm's center.
var direction := Vector3.UP
## Height of the flat disc above the sea-level sphere, meters, quantized.
var level := 0.0


## The site of a realm under a seed (cached).
static func at(for_realm: RealmDef, world_seed: int) -> BossSite:
	var key := [
		for_realm.id,
		for_realm.radius,
		for_realm.seed_salt,
		for_realm.moor_height,
		for_realm.hill_height,
		for_realm.ridge_height,
		world_seed
	]
	_lock.lock()
	var found: BossSite = _cache.get(key)
	_lock.unlock()
	if found != null:
		return found
	found = _find(for_realm, world_seed)
	_lock.lock()
	_cache[key] = found
	_lock.unlock()
	return found


static func _find(for_realm: RealmDef, world_seed: int) -> BossSite:
	var raw := Terrain.Field.new(for_realm, world_seed, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(world_seed, for_realm.seed_salt)) + 31
	var arrival := for_realm.arrival.normalized()
	var east := arrival.cross(Vector3.UP if absf(arrival.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := arrival.cross(east)
	var farthest := minf(MAX_ARC, 0.45 * TAU * for_realm.radius)
	var nearest := minf(MIN_ARC, 0.5 * farthest)
	var best := Vector3.ZERO
	var best_spread := INF
	var best_level := 0.0
	for n in CANDIDATES:
		var angle := rng.randf() * TAU
		var arc := rng.randf_range(nearest, farthest) / for_realm.radius
		var away := east * cos(angle) + north * sin(angle)
		var candidate := (arrival * cos(arc) + away * sin(arc)).normalized()
		var heights := _probe(for_realm, raw, candidate)
		var spread: float = heights.max() - heights.min()
		if spread < best_spread:
			best_spread = spread
			best = candidate
			var mean := 0.0
			for h: float in heights:
				mean += h
			best_level = mean / heights.size()
	var site := BossSite.new()
	site.realm = for_realm
	site.direction = best
	site.level = roundi(best_level / Terrain.QUANTUM) * Terrain.QUANTUM
	return site


## Raw heights at the center and PROBES points around it at the edge of the blend.
static func _probe(for_realm: RealmDef, raw: Terrain.Field, center: Vector3) -> Array[float]:
	var east := center.cross(Vector3.UP if absf(center.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := center.cross(east)
	var step := (FLAT + BLEND) / for_realm.radius
	var found: Array[float] = [raw.raw_height(center)]
	for n in PROBES:
		var angle := TAU * n / PROBES
		var spot := center * cos(step) + (east * cos(angle) + north * sin(angle)) * sin(step)
		found.append(raw.raw_height(spot.normalized()))
	return found


## Meters along the ground from the center to a direction.
func distance(toward: Vector3) -> float:
	return direction.angle_to(toward) * realm.radius


## The ground height the site wants at a direction given the raw height there: the flat level
## inside the disc, blending back to the raw ground outside it.
func shape(toward: Vector3, raw_height: float) -> float:
	var meters := distance(toward)
	if meters >= FLAT + BLEND:
		return raw_height
	return lerpf(level, raw_height, smoothstep(FLAT, FLAT + BLEND, meters))


## Whether a direction is within meters (plus the blend) of the center, a cheap pre-check.
func near(toward: Vector3, meters: float) -> bool:
	return direction.dot(toward) > cos(meters / realm.radius)


## Whether something of this radius (m) would stand on the disc or its blend.
func covers(toward: Vector3, margin := 0.0) -> bool:
	var reach := FLAT + BLEND + CLEAR_MARGIN + margin
	return near(toward, reach) and distance(toward) < reach


## The center of the ring on the ground, world space.
func center() -> Vector3:
	return realm.center + direction * (realm.radius + level)


## A direction `meters` from the center along the ground, at `angle` around it (the same
## frame the stones use).
func spot(angle: float, meters: float) -> Vector3:
	var east := direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
	east = east.normalized()
	var north := direction.cross(east)
	var step := meters / realm.radius
	var around := east * cos(angle) + north * sin(angle)
	return (direction * cos(step) + around * sin(step)).normalized()


## The ring's stones as directions from the realm's center, evenly around the center (the first
## one a fixed way round: every peer finds the same ones).
func stones() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for n in STONES:
		found.append(spot(TAU * n / STONES, RING_RADIUS))
	return found


## Where a debug spawn stands inside the ring (--encounter=boss): a slot per peer, a few meters
## from the middle, on the flat ground.
func ring_spot(peer_id: int) -> Vector3:
	var middle := center()
	var around := Layout.ring_point(middle, peer_id, direction) - middle
	return middle + around.normalized() * SPAWN_RING + direction * Layout.ARRIVAL_LIFT
