class_name BushKind
extends RefCounted
## A bush (M41): up to eight small leaf clumps (icospheres) heaped so the crown is wider than the
## foot: a dark low ring inside, a green outer ring higher, one on top. Tips are pulled out
## so the outline is ragged, not round. `cluster` is also the heather's and pebbles' shape.

## Width, height, depth in meters.
const NOMINAL := Vector3(1.8, 1.2, 1.8)
## Per clump, the first ones stay on lower levels: radius and ring distance (shares of the
## width), center height (share of the height), angle (turns, plus the bush's own), role.
const CLUMPS := [
	[0.2, 0.0, 0.78, 0.0, &"leaf"],
	[0.2, 0.3, 0.58, 0.0, &"leaf"],
	[0.2, 0.3, 0.58, 0.25, &"leaf"],
	[0.2, 0.3, 0.58, 0.5, &"leaf"],
	[0.2, 0.3, 0.58, 0.75, &"leaf"],
	[0.22, 0.17, 0.3, 0.1, &"moss"],
	[0.22, 0.17, 0.3, 0.45, &"moss"],
	[0.22, 0.17, 0.3, 0.8, &"moss"],
]
## Clumps per level (full, half, far).
const COUNTS := Vector3i(8, 2, 1)
## Share of the vertices pulled out into tips, and by how much.
const TIPS := 0.3
const TIP_PULL := 1.4


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var turn := rng.randf()
	var parts: Array = []
	for i in COUNTS[lod]:
		var clump: Array = CLUMPS[i]
		var angle := TAU * (turn + clump[3] as float) + rng.randf_range(-0.3, 0.3)
		var out := NOMINAL.x * (clump[1] as float) * rng.randf_range(0.85, 1.15)
		var at := Vector3(
			cos(angle) * out,
			NOMINAL.y * (clump[2] as float) * rng.randf_range(0.9, 1.1),
			sin(angle) * out
		)
		var radius := NOMINAL.x * (clump[0] as float) * rng.randf_range(0.9, 1.15)
		var mass := MeshKit.blob(radius, 0, 0.3, 0.75, rng)
		var verts: PackedVector3Array = mass[Mesh.ARRAY_VERTEX]
		for k in verts.size():
			verts[k] = at + _ragged(verts[k], radius)
		mass[Mesh.ARRAY_VERTEX] = verts
		var color := palette.color(clump[4] as StringName)
		parts.append(MeshKit.paint(mass, color, rng, Vector3.DOWN, look))
	return MeshKit.merge(parts)


## A clump vertex (around its center), some pulled out; chosen by its place, so the faces that
## share a corner keep sharing it.
static func _ragged(v: Vector3, radius: float) -> Vector3:
	var h := fposmod(sin(v.dot(Vector3(12.9898, 78.233, 37.719)) * 1000.0 / radius) * 43758.5, 1.0)
	return v * TIP_PULL if h < TIPS else v


## Blobs of the given roles (the first is the biggest, in the middle) heaped into `nominal`'s
## box, `counts` of them per level. Every blob is drawn for every level.
static func cluster(
	rng: RandomNumberGenerator,
	palette: Palette,
	lod: int,
	nominal: Vector3,
	roles: Array[StringName],
	counts: Vector3i
) -> Array:
	var look := MeshKit.jitter(rng)
	var blobs: Array = []
	for i in roles.size():
		var angle := rng.randf_range(0.0, TAU)
		var spread := 0.0 if i == 0 else nominal.x * rng.randf_range(0.18, 0.3)
		var width := nominal.x * (0.62 if i == 0 else 0.5) * rng.randf_range(0.85, 1.15)
		var height := nominal.y * (1.0 if i == 0 else 0.8) * rng.randf_range(0.85, 1.0)
		var whole := height / (1.0 - RockKind.SINK)
		var at := Vector3(cos(angle) * spread, whole * (0.5 - RockKind.SINK), sin(angle) * spread)
		blobs.append([Vector3(width, whole, width), at, rng.randi()])
	var parts: Array = []
	for i in counts[lod]:
		var blob_rng := RandomNumberGenerator.new()
		blob_rng.seed = blobs[i][2]
		var mass := RockKind.lump(blob_rng, blobs[i][0], blobs[i][1], 0, [])
		parts.append(MeshKit.paint(mass, palette.color(roles[i]), rng, Vector3.DOWN, look))
	return MeshKit.merge(parts)
