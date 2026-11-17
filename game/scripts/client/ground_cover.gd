class_name GroundCover
extends RefCounted
## What grows between the trees (M37 task 3): grass, ferns, heather, bushes, pebbles, fallen logs
## and stumps. View only, never in `Scatter.points`, never solid. A pure function of (realm, world
## seed, chunk, density): no scene tree, no shared state, so a worker thread can run it. It reads
## the same field as `Scatter` (forest noise, slope, height) and keeps off every footprint of the
## scatter's points (the chunk's and its neighbours'), the arrival clearing (so the spawn ring) and
## the boss disc. Kinds are named like their generator ids (`Kind.keys()` in lower case).
## The view sets the knobs per graphics preset: `density` here, the radius by which chunks it asks.

enum Kind { GRASS_TUFT, GRASS_TALL, FERN, HEATHER, BUSH, PEBBLE, LOG, STUMP }
enum Habitat { WOOD, FRINGE, MOOR }

## One jittered candidate per square of this size (m).
const SPACING := 2.0
## Cover keeps this far (m) from the edge of a solid's footprint.
const MARGIN := 0.3
## Ground steeper than this (cosine of the slope) grows nothing but pebbles.
const FLAT_FROM := 0.8
## Above this height (m) only heather and pebbles.
const BARE_HEIGHT := 14.0
## Chance of a candidate bearing anything at density 1.0, per habitat.
const CHANCE := {Habitat.WOOD: 0.45, Habitat.FRINGE: 0.55, Habitat.MOOR: 0.65}
## Per habitat: the kinds and their weights (picked by a roll over the sum).
const WEIGHTS := {
	Habitat.WOOD:
	[
		[Kind.FERN, 4.0],
		[Kind.GRASS_TUFT, 3.0],
		[Kind.BUSH, 0.7],
		[Kind.PEBBLE, 0.5],
		[Kind.LOG, 0.25],
		[Kind.STUMP, 0.25],
	],
	Habitat.FRINGE:
	[
		[Kind.GRASS_TUFT, 4.0],
		[Kind.FERN, 2.0],
		[Kind.GRASS_TALL, 1.5],
		[Kind.BUSH, 0.8],
		[Kind.HEATHER, 0.8],
		[Kind.PEBBLE, 0.5],
		[Kind.LOG, 0.1],
		[Kind.STUMP, 0.1],
	],
	Habitat.MOOR:
	[
		[Kind.HEATHER, 4.0],
		[Kind.GRASS_TUFT, 3.0],
		[Kind.GRASS_TALL, 2.5],
		[Kind.PEBBLE, 0.8],
		[Kind.BUSH, 0.3],
	],
}
## Spatial hash cell (m): more than the biggest footprint plus margin.
const HASH_CELL := 16.0


class Point:
	extends RefCounted
	var kind: Kind
	## Realm-relative, on the ground.
	var position: Vector3
	## The direction from the realm center (local up).
	var up: Vector3
	var yaw: float
	## 0.0 to 1.0, a size roll for the view.
	var size: float
	## 0.0 to 1.0: a view that wants fewer draws those under its share.
	var rank: float


## The cover of chunk (face, x, y) (Terrain.chunk_at), in a fixed order. `density` (0 to 1) scales
## how many candidates bear anything: the same points stay when it rises. `scatter` is the
## `Scatter.points` of this chunk and the chunks around it when the caller has them (the view does
## already); empty, they are made here.
static func points(
	realm: RealmDef,
	world_seed: int,
	chunk: Vector3i,
	density := 1.0,
	scatter: Array[Scatter.Point] = []
) -> Array[Point]:
	var found: Array[Point] = []
	if density <= 0.0:
		return found
	var field := Terrain.Field.new(realm, world_seed)
	var forest := Scatter._noise(realm, world_seed, 11, Scatter.FOREST_WAVELENGTH)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector4i(world_seed, realm.seed_salt + 101, chunk.x, chunk.y * 4096 + chunk.z))
	var cells := Terrain.grid_cells(realm)
	var first := Vector2i(chunk.y, chunk.z) * Terrain.CHUNK_CELLS
	var span := Terrain.CHUNK_CELLS
	var corner := Terrain.vertex_direction(chunk.x, first.x, first.y, cells)
	var along_x := Terrain.vertex_direction(chunk.x, first.x + span, first.y, cells)
	var along_y := Terrain.vertex_direction(chunk.x, first.x, first.y + span, cells)
	var count_x := maxi(1, roundi(corner.distance_to(along_x) * realm.radius / SPACING))
	var count_y := maxi(1, roundi(corner.distance_to(along_y) * realm.radius / SPACING))
	var arrival := realm.arrival.normalized()
	var clear := cos(Scatter.CLEARING / realm.radius)
	var solids: Dictionary = {}
	var cover_by_kind := _weights()
	for iy in count_y:
		for ix in count_x:
			var jitter_x := rng.randf()
			var jitter_y := rng.randf()
			var present := rng.randf()
			var pick := rng.randf()
			var point := Point.new()
			point.yaw = rng.randf() * TAU
			point.size = rng.randf()
			point.rank = rng.randf()
			var direction := Terrain.vertex_direction(
				chunk.x,
				first.x + (ix + jitter_x) / count_x * span,
				first.y + (iy + jitter_y) / count_y * span,
				cells
			)
			if present >= density * (CHANCE[Habitat.MOOR] as float):
				continue
			if direction.dot(arrival) > clear or field.site.covers(direction):
				continue
			var height := field.height(direction)
			var flat := Terrain._normal(field, direction).dot(direction)
			var at := direction * realm.radius
			var wood := forest.get_noise_3d(at.x, at.y, at.z)
			var habitat := _habitat(wood)
			if present >= density * (CHANCE[habitat] as float):
				continue
			var kind := _kind(pick, habitat, height, flat, cover_by_kind)
			if kind < 0:
				continue
			point.kind = kind as Kind
			point.up = direction
			point.position = direction * (realm.radius + height)
			if solids.is_empty():
				solids = _solids(realm, world_seed, chunk, scatter)
			if _blocked(solids, point.position):
				continue
			found.append(point)
	return found


static func _habitat(wood: float) -> Habitat:
	if wood > Scatter.PINE_FROM:
		return Habitat.WOOD
	return Habitat.FRINGE if wood > Scatter.BIRCH_FROM else Habitat.MOOR


## The kind at a spot, -1 for none. `pick` is a roll in [0, 1) over the habitat's weights.
static func _kind(
	pick: float, habitat: Habitat, height: float, flat: float, weights: Dictionary
) -> int:
	if flat < FLAT_FROM:
		return Kind.PEBBLE if pick < 0.12 else -1
	if height > BARE_HEIGHT:
		return Kind.HEATHER if pick < 0.7 else Kind.PEBBLE
	var list: Array = weights[habitat]
	var total: float = list.back()[2]
	var at := pick * total
	for entry: Array in list:
		if at < entry[2]:
			return entry[0]
	return -1


## WEIGHTS with a running sum as the third item of every entry.
static func _weights() -> Dictionary:
	var out := {}
	for habitat: Habitat in WEIGHTS:
		var sum := 0.0
		var list: Array = []
		for entry: Array in WEIGHTS[habitat]:
			sum += entry[1] as float
			list.append([entry[0], entry[1], sum])
		out[habitat] = list
	return out


## The footprints of the scatter around the chunk in a spatial hash: cell -> [[position, radius]].
static func _solids(
	realm: RealmDef, world_seed: int, chunk: Vector3i, given: Array[Scatter.Point]
) -> Dictionary:
	var things := given
	if things.is_empty():
		things = _scatter_around(realm, world_seed, chunk)
	var cells := {}
	for thing in things:
		var shape := ScatterShape.of_kind(thing.kind)
		var radius := shape.footprint(shape.size * (0.8 + 0.5 * thing.size)) + MARGIN
		var key := Vector3i((thing.position / HASH_CELL).floor())
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append([thing.position, radius])
	return cells


## The scatter of the chunk and the chunks around it (same walk as Scatter.points).
static func _scatter_around(
	realm: RealmDef, world_seed: int, chunk: Vector3i
) -> Array[Scatter.Point]:
	var frame := Scatter._frame(realm, chunk)
	var along_x: Vector3 = frame[1]
	var along_y: Vector3 = frame[2]
	var middle: Vector3 = (frame[0] as Vector3) + (along_x + along_y) * 0.5
	var found: Array[Scatter.Point] = []
	var seen := {}
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var spot: Vector3 = (middle + (along_x * dx + along_y * dy) * 0.95).normalized()
			var other := Terrain.chunk_at(realm, spot)
			if not seen.has(other):
				seen[other] = true
				found.append_array(Scatter.points(realm, world_seed, other))
	return found


static func _blocked(solids: Dictionary, position: Vector3) -> bool:
	var middle := Vector3i((position / HASH_CELL).floor())
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for entry: Array in solids.get(middle + Vector3i(dx, dy, dz), []):
					if (entry[0] as Vector3).distance_to(position) < (entry[1] as float):
						return true
	return false
