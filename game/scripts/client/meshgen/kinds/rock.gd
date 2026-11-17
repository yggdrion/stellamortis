class_name RockKind
extends RefCounted
## A chipped rock: a displaced icosphere with corners cut off, and at full detail a second chunk
## beside it. Sample generator of M36; M37 replaces or extends it.

const RADIUS := 0.7
const NOISE := 0.25
const FLATTEN := 0.7
## Icosphere detail per level (full, half, far).
const DETAIL: Array[int] = [1, 1, 0]
const CHUNK := 0.45
const CHUNK_OFFSET := 0.45


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var size := RADIUS * rng.randf_range(0.8, 1.3)
	var flatten := FLATTEN * rng.randf_range(0.85, 1.15)
	var main := MeshKit.blob(size, DETAIL[lod], NOISE, flatten, rng)
	var cuts: Array[Plane] = []
	for i in 2:
		var normal := Vector3(rng.randfn(), rng.randf_range(0.2, 1.0), rng.randfn()).normalized()
		cuts.append(Plane(normal, size * rng.randf_range(0.7, 0.85)))
	main = MeshKit.chip(main, cuts)
	var look := MeshKit.jitter(rng)
	var parts: Array = [MeshKit.paint(main, palette.color(&"stone"), rng, Vector3.DOWN, look)]
	var chunk := MeshKit.blob(size * CHUNK, 1, NOISE, FLATTEN, rng)
	var angle := rng.randf_range(0.0, TAU)
	if lod == Budgets.FULL:
		var at := Vector3(cos(angle), -0.2, sin(angle)) * size * CHUNK_OFFSET
		var moved := PackedVector3Array()
		for p in chunk[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			moved.append(p + at)
		chunk[Mesh.ARRAY_VERTEX] = moved
		parts.append(MeshKit.paint(chunk, palette.color(&"stone_dark"), rng, Vector3.DOWN, look))
	return MeshKit.merge(parts)
