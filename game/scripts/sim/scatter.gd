class_name Scatter
extends RefCounted
## What stands on a generated realm's ground (M20): pines, birches, boulders, standing stones and
## burial mounds, a pure function of (realm, world seed, chunk). No scene tree and no shared
## state, so a worker thread can run it; the client draws the points (TerrainView) and M25 gives
## the same points collision and health on the server. Points carry a rank in [0, 1): a view
## that wants fewer (lower graphics presets) draws those under its density and every peer's
## solid objects stay the same.

enum Kind { PINE_TALL, PINE_FULL, BIRCH, BOULDER_A, BOULDER_B, STANDING_STONE, MOUND }

## Candidate spacing in meters (one jittered candidate per square of this size).
const SPACING := 5.0
## Nothing stands this close to the arrival (the gates stand around it).
const CLEARING := 30.0
const FOREST_WAVELENGTH := 140.0
## Forest noise above this is pine wood, down to BIRCH_FROM a birch fringe.
const PINE_FROM := 0.1
const BIRCH_FROM := -0.05
## Trees keep to ground flatter than this (cosine of the slope) and lower than TREE_LINE m.
const TREE_SLOPE := 0.85
const TREE_LINE := 20.0
const PINE_CHANCE := 0.55
const BIRCH_CHANCE := 0.2
## Ground steeper than this (cosine) gets many boulders, else the moor gets a few.
const STEEP := 0.8
const STEEP_BOULDER_CHANCE := 0.3
const MOOR_BOULDER_CHANCE := 0.025
## Standing stones on flat high ground, mounds on flat low ground.
const STONE_HEIGHT := 14.0
const STONE_SLOPE := 0.93
const STONE_CHANCE := 0.02
const MOUND_HEIGHT := 8.0
const MOUND_SLOPE := 0.97
const MOUND_CHANCE := 0.002


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
	var rank: float


## The points of chunk (face, x, y) (Terrain.chunk_at), in a fixed order.
static func points(realm: RealmDef, world_seed: int, chunk: Vector3i) -> Array[Point]:
	var field := Terrain.Field.new(realm, world_seed)
	var forest := FastNoiseLite.new()
	forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest.seed = hash(Vector2i(world_seed, realm.seed_salt)) + 11
	forest.frequency = 1.0 / FOREST_WAVELENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector4i(world_seed, realm.seed_salt, chunk.x, chunk.y * 4096 + chunk.z))
	var cells := Terrain.grid_cells(realm)
	var first := Vector2i(chunk.y, chunk.z) * Terrain.CHUNK_CELLS
	var span := Terrain.CHUNK_CELLS
	var corner := Terrain.vertex_direction(chunk.x, first.x, first.y, cells)
	var along_x := Terrain.vertex_direction(chunk.x, first.x + span, first.y, cells)
	var along_y := Terrain.vertex_direction(chunk.x, first.x, first.y + span, cells)
	var count_x := maxi(1, roundi(corner.distance_to(along_x) * realm.radius / SPACING))
	var count_y := maxi(1, roundi(corner.distance_to(along_y) * realm.radius / SPACING))
	var clear_dot := cos(CLEARING / realm.radius)
	var arrival := realm.arrival.normalized()
	var found: Array[Point] = []
	for iy in count_y:
		for ix in count_x:
			# Every roll is drawn whatever the outcome, so the stream never depends on the ground.
			var jitter_x := rng.randf()
			var jitter_y := rng.randf()
			var roll := rng.randf()
			var variant := rng.randf()
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
			if direction.dot(arrival) > clear_dot:
				continue
			var height := field.height(direction)
			var flat := Terrain._normal(field, direction).dot(direction)
			var wood := forest.get_noise_3d(
				direction.x * realm.radius, direction.y * realm.radius, direction.z * realm.radius
			)
			var kind := _kind(roll, variant, height, flat, wood)
			if kind < 0:
				continue
			point.kind = kind as Kind
			point.up = direction
			point.position = direction * (realm.radius + height)
			found.append(point)
	return found


## The thing standing at a spot (roll and variant in [0, 1)), -1 for none. Height in meters above
## sea level, flat the cosine of the slope, wood the forest noise.
static func _kind(roll: float, variant: float, height: float, flat: float, wood: float) -> int:
	if flat < STEEP:
		if roll < STEEP_BOULDER_CHANCE:
			return Kind.BOULDER_A if variant < 0.5 else Kind.BOULDER_B
		return -1
	if height > STONE_HEIGHT and flat > STONE_SLOPE and roll < STONE_CHANCE:
		return Kind.STANDING_STONE
	if height < MOUND_HEIGHT and flat > MOUND_SLOPE and wood < BIRCH_FROM and roll < MOUND_CHANCE:
		return Kind.MOUND
	if flat > TREE_SLOPE and height < TREE_LINE:
		if wood > PINE_FROM and roll < PINE_CHANCE:
			return Kind.PINE_TALL if variant < 0.5 else Kind.PINE_FULL
		if wood > BIRCH_FROM and wood <= PINE_FROM and roll < BIRCH_CHANCE:
			return Kind.BIRCH
	if roll > 1.0 - MOOR_BOULDER_CHANCE:
		return Kind.BOULDER_A if variant < 0.5 else Kind.BOULDER_B
	return -1
