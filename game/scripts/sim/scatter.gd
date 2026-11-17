class_name Scatter
extends RefCounted
## What stands on a generated realm's ground (M20, M37): trees of five species and three ages,
## rocks, boulders, outcrops, standing stones and burial mounds, a pure function of (realm, world
## seed, chunk). No scene tree and no shared state, so a worker thread can run it; the client
## draws the points (TerrainView) and the server and clients give the same points collision
## (ScatterShape). Points carry a rank in [0, 1): a view that wants fewer (lower graphics
## presets) draws those under its density and every peer's solid objects stay the same.
## Bigger things push smaller ones away (`_spaced`): a candidate is dropped when a bigger one
## (by its room, ties by rank) is within that one's room plus the candidate's own body, in this
## chunk or across its edge, so a neighbouring chunk makes the same call.

## Trees by species then age (young, grown, old: `tree(species, age)`), then the rest.
enum Kind {
	PINE_YOUNG,
	PINE_GROWN,
	PINE_OLD,
	SPRUCE_YOUNG,
	SPRUCE_GROWN,
	SPRUCE_OLD,
	BIRCH_YOUNG,
	BIRCH_GROWN,
	BIRCH_OLD,
	OAK_YOUNG,
	OAK_GROWN,
	OAK_OLD,
	DEAD_TREE_YOUNG,
	DEAD_TREE_GROWN,
	DEAD_TREE_OLD,
	ROCK,
	BOULDER,
	OUTCROP,
	STANDING_STONE,
	MOUND
}
enum Species { PINE, SPRUCE, BIRCH, OAK, DEAD_TREE }
enum Age { YOUNG, GROWN, OLD }

## Candidate spacing in meters (one jittered candidate per square of this size).
const SPACING := 5.0
## Nothing stands this close to the arrival (the gates stand around it), plus its own footprint.
const CLEARING := 30.0
const FOREST_WAVELENGTH := 140.0
## The "old wood" noise: patches this wide. Above OLD_FROM the trees are old, below YOUNG_BELOW
## young (a point's own roll blurs the edges by AGE_BLUR).
const AGE_WAVELENGTH := 260.0
const OLD_FROM := 0.3
const YOUNG_BELOW := -0.25
const AGE_BLUR := 0.2
## Forest noise above SPRUCE_FROM is spruce wood, down to PINE_FROM pine wood, down to
## BIRCH_FROM a birch fringe; below OAK_FROM the moor has dead trees only, between OAK_FROM and
## BIRCH_FROM oaks on low ground.
const SPRUCE_FROM := 0.3
const PINE_FROM := 0.1
const BIRCH_FROM := -0.05
const OAK_FROM := -0.3
const OAK_HEIGHT := 12.0
## Trees keep to ground flatter than this (cosine of the slope) and lower than TREE_LINE m.
const TREE_SLOPE := 0.85
const TREE_LINE := 20.0
const SPRUCE_CHANCE := 0.6
const PINE_CHANCE := 0.55
const BIRCH_CHANCE := 0.2
const OAK_CHANCE := 0.07
## Dead trees stand alone on the moor, the roll band [DEAD_ROLL, DEAD_ROLL + DEAD_CHANCE).
const DEAD_ROLL := 0.5
const DEAD_CHANCE := 0.015
## Ground steeper than this (cosine) gets many rocks, else the moor gets a few. A roll `variant`
## under the first share is a rock, under the second a boulder, else an outcrop.
const STEEP := 0.8
const STEEP_ROCK_CHANCE := 0.3
const STEEP_SHARES := Vector2(0.5, 0.9)
const MOOR_ROCK_CHANCE := 0.025
const MOOR_SHARES := Vector2(0.6, 0.96)
## Standing stones on flat high ground, mounds on flat low ground.
const STONE_HEIGHT := 14.0
const STONE_SLOPE := 0.93
const STONE_CHANCE := 0.02
const MOUND_HEIGHT := 8.0
const MOUND_SLOPE := 0.97
const MOUND_CHANCE := 0.002
## A roll from IDLE_FROM up to IDLE_TO makes nothing anywhere, so the ground is not even read.
const IDLE_FROM := 0.6
const IDLE_TO := 1.0 - MOOR_ROCK_CHANCE
## Candidates this close (m) to a chunk's edge, from the chunks around it, take part in its
## spacing: more than the biggest room plus the biggest body.
const BAND := 16.0
## Spatial hash cell of the spacing pass (m): at least the biggest reach (room plus body).
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
	var rank: float
	## Meters: how much ground the thing keeps for itself (its spacing) and its solid footprint.
	var room := 0.0
	var body := 0.0


## The kind of a tree of a species and age.
static func tree(species: Species, age: Age) -> Kind:
	return (species * 3 + age) as Kind


## The points of chunk (face, x, y) (Terrain.chunk_at), in a fixed order.
static func points(realm: RealmDef, world_seed: int, chunk: Vector3i) -> Array[Point]:
	var field := Terrain.Field.new(realm, world_seed)
	var forest := _noise(realm, world_seed, 11, FOREST_WAVELENGTH)
	var age := _noise(realm, world_seed, 13, AGE_WAVELENGTH)
	var mine := _candidates(realm, field, forest, age, world_seed, chunk, [])
	# The candidates of the chunks around, near this chunk's edges, only to push mine away.
	var frame := _frame(realm, chunk)
	var around: Array[Point] = []
	var seen := {chunk: true}
	var along_x: Vector3 = frame[1]
	var along_y: Vector3 = frame[2]
	var middle: Vector3 = (frame[0] as Vector3) + (along_x + along_y) * 0.5
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var spot: Vector3 = (middle + (along_x * dx + along_y * dy) * 0.95).normalized()
			var other := Terrain.chunk_at(realm, spot)
			if not seen.has(other):
				seen[other] = true
				around.append_array(
					_candidates(realm, field, forest, age, world_seed, other, frame)
				)
	var found := _spaced(mine, around)
	found.append_array(_ring(realm, field, chunk))
	return found


static func _noise(
	realm: RealmDef, world_seed: int, offset: int, wavelength: float
) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = hash(Vector2i(world_seed, realm.seed_salt)) + offset
	noise.frequency = 1.0 / wavelength
	return noise


## A chunk's corner direction and its two edges as chord vectors, plus the band margin as a
## fraction of each edge: [corner, along x, along y, margin x, margin y].
static func _frame(realm: RealmDef, chunk: Vector3i) -> Array:
	var cells := Terrain.grid_cells(realm)
	var first := Vector2i(chunk.y, chunk.z) * Terrain.CHUNK_CELLS
	var span := Terrain.CHUNK_CELLS
	var corner := Terrain.vertex_direction(chunk.x, first.x, first.y, cells)
	var along_x := Terrain.vertex_direction(chunk.x, first.x + span, first.y, cells) - corner
	var along_y := Terrain.vertex_direction(chunk.x, first.x, first.y + span, cells) - corner
	return [
		corner,
		along_x,
		along_y,
		BAND / (along_x.length() * realm.radius),
		BAND / (along_y.length() * realm.radius)
	]


## The things a chunk would hold before spacing. With a `band` (another chunk's _frame) only the
## candidates within BAND meters of that chunk are made; every roll is drawn whatever the
## outcome, so the stream never depends on the ground or the band.
static func _candidates(
	realm: RealmDef,
	field: Terrain.Field,
	forest: FastNoiseLite,
	age_noise: FastNoiseLite,
	world_seed: int,
	chunk: Vector3i,
	band: Array
) -> Array[Point]:
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
	var arrival := realm.arrival.normalized()
	var site := field.site
	var found: Array[Point] = []
	for iy in count_y:
		for ix in count_x:
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
			if roll >= IDLE_FROM and roll <= IDLE_TO:
				continue
			if not band.is_empty() and not _in_band(direction, band):
				continue
			if direction.dot(arrival) > cos(CLEARING / realm.radius):
				continue
			if site.covers(direction):
				continue
			var height := field.height(direction)
			var flat := Terrain._normal(field, direction).dot(direction)
			var at := direction * realm.radius
			var wood := forest.get_noise_3d(at.x, at.y, at.z)
			var old_wood := age_noise.get_noise_3d(at.x, at.y, at.z) + (variant - 0.5) * AGE_BLUR
			var kind := _kind(roll, variant, height, flat, wood, old_wood)
			if kind < 0:
				continue
			point.kind = kind as Kind
			var shape := ScatterShape.of_kind(kind)
			var scale_by := 0.8 + 0.5 * point.size
			point.body = shape.footprint(shape.size * scale_by)
			point.room = maxf(point.body, shape.room * scale_by)
			# Not on the arrival's clearing nor the boss disc, by the thing's own reach.
			if direction.dot(arrival) > cos((CLEARING + point.body) / realm.radius):
				continue
			if site.covers(direction, point.body):
				continue
			point.up = direction
			point.position = direction * (realm.radius + height)
			found.append(point)
	return found


## Whether a direction is within the band of a chunk's frame (see _frame).
static func _in_band(direction: Vector3, frame: Array) -> bool:
	var apart: Vector3 = direction - (frame[0] as Vector3)
	var along_x: Vector3 = frame[1]
	var along_y: Vector3 = frame[2]
	var a := apart.dot(along_x) / along_x.length_squared()
	var b := apart.dot(along_y) / along_y.length_squared()
	return a > -frame[3] and a < 1.0 + frame[3] and b > -frame[4] and b < 1.0 + frame[4]


## `mine` without the points a bigger one of `mine` or `around` keeps ground from. Bigger is by
## room, a tie goes to the higher rank. Order is kept.
static func _spaced(mine: Array[Point], around: Array[Point]) -> Array[Point]:
	var cells := {}
	for list: Array[Point] in [mine, around]:
		for point in list:
			var key := Vector3i((point.position / HASH_CELL).floor())
			if not cells.has(key):
				cells[key] = [] as Array[Point]
			(cells[key] as Array[Point]).append(point)
	var found: Array[Point] = []
	for point in mine:
		var middle := Vector3i((point.position / HASH_CELL).floor())
		var pushed := false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var near: Array = cells.get(middle + Vector3i(dx, dy, dz), [])
					for other: Point in near:
						if other == point or other.room < point.room:
							continue
						if other.room == point.room and other.rank < point.rank:
							continue
						if other.position.distance_to(point.position) < other.room + point.body:
							pushed = true
		if not pushed:
			found.append(point)
	return found


## The boss site's ring of standing stones that fall in this chunk, after the random points.
## Their size and yaw come from the stone's number, not a generator, so they never move.
static func _ring(realm: RealmDef, field: Terrain.Field, chunk: Vector3i) -> Array[Point]:
	var found: Array[Point] = []
	var stones := field.site.stones()
	for n in stones.size():
		if Terrain.chunk_at(realm, stones[n]) != chunk:
			continue
		var point := Point.new()
		point.kind = Kind.STANDING_STONE
		point.up = stones[n]
		point.position = field.surface(stones[n])
		point.yaw = TAU * n / stones.size() + PI / 2.0
		point.size = 0.75
		point.rank = 0.0
		found.append(point)
	return found


## The thing standing at a spot (roll and variant in [0, 1)), -1 for none. Height in meters above
## sea level, flat the cosine of the slope, wood the forest noise, old_wood the age noise (blurred
## by the point's own roll).
static func _kind(
	roll: float, variant: float, height: float, flat: float, wood: float, old_wood: float
) -> int:
	if flat < STEEP:
		if roll < STEEP_ROCK_CHANCE:
			return _rock(variant, STEEP_SHARES)
		return -1
	if height > STONE_HEIGHT and flat > STONE_SLOPE and roll < STONE_CHANCE:
		return Kind.STANDING_STONE
	if height < MOUND_HEIGHT and flat > MOUND_SLOPE and wood < BIRCH_FROM and roll < MOUND_CHANCE:
		return Kind.MOUND
	if flat > TREE_SLOPE and height < TREE_LINE:
		var age := Age.GROWN
		if old_wood > OLD_FROM:
			age = Age.OLD
		elif old_wood < YOUNG_BELOW:
			age = Age.YOUNG
		if wood > SPRUCE_FROM and roll < SPRUCE_CHANCE:
			return tree(Species.SPRUCE, age)
		if wood > PINE_FROM and wood <= SPRUCE_FROM and roll < PINE_CHANCE:
			return tree(Species.PINE, age)
		if wood > BIRCH_FROM and wood <= PINE_FROM and roll < BIRCH_CHANCE:
			return tree(Species.BIRCH, age)
		if wood <= BIRCH_FROM:
			if wood > OAK_FROM and height < OAK_HEIGHT and roll < OAK_CHANCE:
				return tree(Species.OAK, age)
			if roll >= DEAD_ROLL and roll < DEAD_ROLL + DEAD_CHANCE:
				return tree(Species.DEAD_TREE, age)
	if roll > 1.0 - MOOR_ROCK_CHANCE:
		return _rock(variant, MOOR_SHARES)
	return -1


## A rock, boulder or outcrop by the variant roll: under shares.x a rock, under shares.y a
## boulder, else an outcrop.
static func _rock(variant: float, shares: Vector2) -> int:
	if variant < shares.x:
		return Kind.ROCK
	return Kind.BOULDER if variant < shares.y else Kind.OUTCROP
