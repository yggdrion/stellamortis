class_name PropKit
extends RefCounted
## Shared parts of the M38 prop generators: moved and painted boxes and cylinders. Props are
## built from a few parts at the origin (feet at y 0) and use `MeshKit` for all geometry.


## `arrays` moved by `offset` after turning `yaw` radians around Y (normals turn with it).
static func moved(arrays: Array, offset: Vector3, yaw := 0.0) -> Array:
	var basis := Basis(Vector3.UP, yaw)
	var v: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var n: PackedVector3Array = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	for i in v.size():
		v[i] = basis * v[i] + offset
		n[i] = basis * n[i]
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	return out


## A painted box of `size` centered on `center`; chamfered on the full level only.
static func box(
	palette: Palette,
	rng: RandomNumberGenerator,
	role: StringName,
	size: Vector3,
	center: Vector3,
	look: Vector2,
	lod: int,
	bevel := 0.03
) -> Array:
	var part := MeshKit.box(size, bevel if lod == Budgets.FULL else 0.0)
	return MeshKit.paint(moved(part, center), palette.color(role), rng, Vector3.DOWN, look)


## A painted solid of revolution at `center`: `profile` is (radius, height) bottom to top and is
## closed here with a point on the axis at each end.
static func turned(
	palette: Palette,
	rng: RandomNumberGenerator,
	role: StringName,
	profile: PackedVector2Array,
	sides: int,
	center: Vector3,
	look: Vector2
) -> Array:
	var closed := PackedVector2Array([Vector2(0.0, profile[0].y)])
	closed.append_array(profile)
	closed.append(Vector2(0.0, profile[profile.size() - 1].y))
	var part := MeshKit.lathe(closed, sides, 0.0, rng)
	return MeshKit.paint(moved(part, center), palette.color(role), rng, Vector3.DOWN, look)


## Sides of a round part per level (full, half).
static func sides(lod: int, full: int) -> int:
	return full if lod == Budgets.FULL else maxi(full / 2, 4)


## A per-instance stretch (about 2 %) so no two props of one kind are the same; draw it first.
static func shape(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(
		rng.randf_range(0.98, 1.02), rng.randf_range(0.98, 1.02), rng.randf_range(0.98, 1.02)
	)


## `arrays` scaled about the origin by `stretch`.
static func shaped(arrays: Array, stretch: Vector3) -> Array:
	var v: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	for i in v.size():
		v[i] *= stretch
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = v
	return out
