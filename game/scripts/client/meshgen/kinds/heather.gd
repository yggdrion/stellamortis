class_name HeatherKind
extends RefCounted
## Heather: a low purple mound of three small masses on the moor.

## Width, height, depth in meters.
const NOMINAL := Vector3(0.7, 0.35, 0.7)
const ROLES: Array[StringName] = [&"heather", &"heather", &"grass"]
## Masses per level (full, half, far).
const COUNTS := Vector3i(3, 1, 1)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	return BushKind.cluster(rng, palette, lod, NOMINAL, ROLES, COUNTS)
