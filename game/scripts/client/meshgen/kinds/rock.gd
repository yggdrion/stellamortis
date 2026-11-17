class_name RockKind
extends RefCounted
## Rock (0.5 to 2 m), boulder (2 to 5 m) and outcrop (5 to 12 m): a displaced icosphere stretched
## to the kind's `ScatterShape` box, sunk into the ground, with corners chipped off and a few
## smaller chunks beside it. Also the shared lump and warp helpers of the other stone and cover
## kinds (M37 task 3).

## Per id: width, height above the ground, depth in meters. The same as the kind's
## `ScatterShape` box (data/scatter/), which `meshgen_test` holds it to.
const NOMINAL := {
	"rock": Vector3(1.2, 0.8, 1.2),
	"boulder": Vector3(3.2, 1.8, 3.2),
	"outcrop": Vector3(8.0, 3.2, 6.0),
}
## Share of the whole height that is under the ground (STYLE: 10 to 25 %).
const SINK := 0.15
## The main lump fills this much of the box (an ellipsoid plus chunks reach the rest).
const FILL := 0.92
## Displacement of a lump, a fraction of its radius.
const NOISE := 0.22
## Corners cut off the main lump (STYLE: 2 to 5).
const CUTS := Vector2i(2, 5)
const CUT_DRAWS := 5
## Per id, per level of detail (full, half, far).
const MAIN_DETAIL := {
	"rock": Vector3i(1, 1, 0), "boulder": Vector3i(2, 1, 0), "outcrop": Vector3i(2, 1, 0)
}
const CHUNKS := {
	"rock": Vector3i(1, 0, 0), "boulder": Vector3i(0, 2, 1), "outcrop": Vector3i(4, 4, 3)
}
const CHUNK_DETAIL := {
	"rock": Vector3i(1, 0, 0), "boulder": Vector3i(0, 0, 0), "outcrop": Vector3i(1, 0, 0)
}
## Chunk size as a fraction of the lump, and how far out (fraction of half the lump) it sits.
const CHUNK_SIZE := {"rock": 0.45, "boulder": 0.4, "outcrop": 0.4}
const CHUNK_REACH := Vector2(0.45, 0.7)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, id: String) -> Array:
	var nominal: Vector3 = NOMINAL[id]
	var whole := nominal.y / (1.0 - SINK) * rng.randf_range(0.92, 1.08)
	var size := Vector3(
		nominal.x * FILL * rng.randf_range(0.9, 1.1),
		whole,
		nominal.z * FILL * rng.randf_range(0.9, 1.1)
	)
	var at := Vector3(0.0, whole * (0.5 - SINK), 0.0)
	var look := MeshKit.jitter(rng)
	var planes := cuts(rng, size * 0.5, at)
	var counts: Vector3i = CHUNKS[id]
	var chunks: Array = []
	for i in maxi(counts.x, maxi(counts.y, counts.z)):
		var angle := rng.randf_range(0.0, TAU)
		var reach := rng.randf_range(CHUNK_REACH.x, CHUNK_REACH.y)
		var chunk_size: Vector3 = size * (CHUNK_SIZE[id] as float) * rng.randf_range(0.8, 1.2)
		var middle := (
			Vector3(cos(angle) * size.x * 0.5 * reach, 0.0, sin(angle) * size.z * 0.5 * reach)
			+ Vector3(0.0, chunk_size.y * 0.25, 0.0)
		)
		chunks.append([chunk_size, middle, rng.randi()])
	var main_detail: Vector3i = MAIN_DETAIL[id]
	var parts: Array = [
		MeshKit.paint(
			lump(rng, size, at, main_detail[lod], planes),
			palette.color(&"stone"),
			rng,
			Vector3.DOWN,
			look
		)
	]
	var chunk_detail: Vector3i = CHUNK_DETAIL[id]
	for i in counts[lod]:
		var chunk_rng := RandomNumberGenerator.new()
		chunk_rng.seed = chunks[i][2]
		var chunk := lump(chunk_rng, chunks[i][0], chunks[i][1], chunk_detail[lod], [])
		var role := &"stone_dark" if i % 2 == 0 else &"stone"
		parts.append(MeshKit.paint(chunk, palette.color(role), rng, Vector3.DOWN, look))
	return MeshKit.merge(parts)


## An ellipsoid of full extents `size` centered on `at`: a displaced icosphere, corners chipped.
static func lump(
	rng: RandomNumberGenerator, size: Vector3, at: Vector3, detail: int, planes: Array
) -> Array:
	var typed: Array[Plane] = []
	typed.assign(planes)
	var arrays := MeshKit.blob(1.0, detail, NOISE, 1.0, rng)
	return MeshKit.chip(warp(arrays, size * 0.5, at), typed)


## Corner cuts for an ellipsoid of half extents `half` at `at`: always CUT_DRAWS planes drawn, so
## the stream does not depend on the count.
static func cuts(rng: RandomNumberGenerator, half: Vector3, at: Vector3) -> Array:
	var count := rng.randi_range(CUTS.x, CUTS.y)
	var planes: Array = []
	for i in CUT_DRAWS:
		var normal := Vector3(rng.randfn(), rng.randf_range(0.2, 1.0), rng.randfn()).normalized()
		var reach := (normal * half).length() * rng.randf_range(0.7, 0.85)
		if i < count:
			planes.append(Plane(normal, normal.dot(at) + reach))
	return planes


## Scales the vertices, leans them (`shear`: x and z shift per meter of height) and moves them.
## Normals are stale afterwards: `MeshKit.chip` (also with no planes) recomputes them.
static func warp(arrays: Array, scale: Vector3, at: Vector3, shear := Vector2.ZERO) -> Array:
	var v: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	for i in v.size():
		var p := v[i] * scale
		p.x += shear.x * p.y
		p.z += shear.y * p.y
		v[i] = p + at
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = v
	return out
