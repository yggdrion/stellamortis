class_name Terrain
extends RefCounted
## The ground of a generated realm (M20): a pure function of (realm, world seed, direction), the
## only source of height. Server collision and client meshes both come from here, so heights are
## quantized and nothing touches the scene tree (safe on a worker thread: every call builds its
## own FastNoiseLite instances, nothing is shared).
##
## Cube sphere: 6 faces, each a grid of grid_cells() cells per side, cut into chunks of
## CHUNK_CELLS cells. A vertex is named by integers (face, i, j); its cube point is built from
## exact integer ratios, so two chunks, or two faces, that share a vertex build the identical
## Vector3 and with it the identical height and position.
##
## Vertex positions are relative to the realm center (put the chunk body at realm.center).
## Triangles wind clockwise seen from outside (Godot's front face).

const CHUNK_CELLS := 32
## Meters per cell at the center of a cube face (cells shrink toward the corners).
const CELL := 2.0
## Heights snap to this step, meters.
const QUANTUM := 0.01
const SAMPLES := 10000
## Face frames (normal, u axis, v axis) with u x v = normal.
const FACES := [
	[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
	[Vector3.LEFT, Vector3.BACK, Vector3.UP],
	[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
	[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
]


## The noise layers of one realm under one seed.
class Field:
	extends RefCounted
	var realm: RealmDef
	var moor: FastNoiseLite
	var hills: FastNoiseLite
	var ridges: FastNoiseLite
	var mask: FastNoiseLite

	func _init(for_realm: RealmDef, world_seed: int) -> void:
		realm = for_realm
		var base := hash(Vector2i(world_seed, for_realm.seed_salt))
		moor = _noise(base + 1, for_realm.moor_wavelength, 3)
		hills = _noise(base + 2, for_realm.hill_wavelength, 3)
		ridges = _noise(base + 3, for_realm.ridge_wavelength, 1)
		mask = _noise(base + 4, for_realm.ridge_mask_wavelength, 2)

	static func _noise(noise_seed: int, wavelength: float, octaves: int) -> FastNoiseLite:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = noise_seed
		n.frequency = 1.0 / wavelength
		n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
		n.fractal_octaves = octaves
		return n

	## Height above the sea-level sphere in meters, quantized.
	func height(direction: Vector3) -> float:
		var p := direction * realm.radius
		var h := moor.get_noise_3d(p.x, p.y, p.z) * realm.moor_height
		h += hills.get_noise_3d(p.x, p.y, p.z) * realm.hill_height
		var ridge := 1.0 - absf(ridges.get_noise_3d(p.x, p.y, p.z))
		var where := smoothstep(0.05, 0.4, mask.get_noise_3d(p.x, p.y, p.z))
		h += ridge * ridge * where * realm.ridge_height
		return roundi(h / QUANTUM) * QUANTUM

	## Realm-relative surface point.
	func surface(direction: Vector3) -> Vector3:
		return direction * (realm.radius + height(direction))


## Cells along one cube face edge: enough that the center cells are at most CELL wide, a whole
## number of chunks.
static func grid_cells(realm: RealmDef) -> int:
	return ceili(2.0 * realm.radius / (CELL * CHUNK_CELLS)) * CHUNK_CELLS


static func chunks_per_face(realm: RealmDef) -> int:
	return grid_cells(realm) / CHUNK_CELLS


## The unit direction of grid vertex (face, i, j), i and j in 0..cells. Only exact integer ratios
## and one normalize, so every caller gets the same bits.
static func vertex_direction(face: int, i: int, j: int, cells: int) -> Vector3:
	var frame: Array = FACES[face]
	var u := float(2 * i - cells) / float(cells)
	var v := float(2 * j - cells) / float(cells)
	var cube: Vector3 = frame[0] + frame[1] * u + frame[2] * v
	return cube.normalized()


static func height(realm: RealmDef, world_seed: int, direction: Vector3) -> float:
	return Field.new(realm, world_seed).height(direction)


## World-space surface point.
static func surface(realm: RealmDef, world_seed: int, direction: Vector3) -> Vector3:
	return realm.center + Field.new(realm, world_seed).surface(direction)


## Surface normal (unit, pointing out) from points a meter either side along the tangents.
static func normal(realm: RealmDef, world_seed: int, direction: Vector3) -> Vector3:
	return _normal(Field.new(realm, world_seed), direction)


static func _normal(field: Field, direction: Vector3) -> Vector3:
	var axis := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	var tangent := direction.cross(axis).normalized()
	var bitangent := direction.cross(tangent)
	var step := 1.0 / field.realm.radius
	var du := (
		field.surface((direction + tangent * step).normalized())
		- field.surface((direction - tangent * step).normalized())
	)
	var dv := (
		field.surface((direction + bitangent * step).normalized())
		- field.surface((direction - bitangent * step).normalized())
	)
	var n := du.cross(dv).normalized()
	return n if n.dot(direction) > 0.0 else -n


## Collision triangles of chunk (face, x, y), realm-relative. No scene tree access.
static func chunk_arrays(
	realm: RealmDef, world_seed: int, face: int, x: int, y: int
) -> PackedVector3Array:
	var field := Field.new(realm, world_seed)
	var cells := grid_cells(realm)
	var side := CHUNK_CELLS + 1
	var points := PackedVector3Array()
	points.resize(side * side)
	for b in side:
		for a in side:
			var i := x * CHUNK_CELLS + a
			var j := y * CHUNK_CELLS + b
			points[b * side + a] = field.surface(vertex_direction(face, i, j, cells))
	var tris := PackedVector3Array()
	tris.resize(CHUNK_CELLS * CHUNK_CELLS * 6)
	var n := 0
	for b in CHUNK_CELLS:
		for a in CHUNK_CELLS:
			var p00 := points[b * side + a]
			var p10 := points[b * side + a + 1]
			var p01 := points[(b + 1) * side + a]
			var p11 := points[(b + 1) * side + a + 1]
			tris[n] = p00
			tris[n + 1] = p01
			tris[n + 2] = p10
			tris[n + 3] = p10
			tris[n + 4] = p01
			tris[n + 5] = p11
			n += 6
	return tris


## n fixed unit directions from an integer generator (no trig, same on every platform).
static func sample_directions(count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var s := 12345
	while out.size() < count:
		var c := Vector3.ZERO
		for axis in 3:
			s = (s * 1103515245 + 12345) & 0x7fffffff
			c[axis] = float(s) / 1073741824.0 - 1.0
		if c.length_squared() > 0.01:
			out.append(c.normalized())
	return out


## A fingerprint of the ground: the heights (whole centimeters) at SAMPLES fixed directions.
static func fingerprint(realm: RealmDef, world_seed: int) -> int:
	var field := Field.new(realm, world_seed)
	var h := 1469598103934665603
	for d in sample_directions(SAMPLES):
		h = (h ^ roundi(field.height(d) * 100.0)) * 1099511628211
	return h
