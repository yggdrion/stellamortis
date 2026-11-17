class_name PebbleKind
extends RefCounted
## Pebbles: two small chipped stones lying together.

## Width, height, depth in meters.
const NOMINAL := Vector3(0.35, 0.14, 0.35)
const ROLES: Array[StringName] = [&"stone", &"stone_dark"]
## Stones per level (full, half, far).
const COUNTS := Vector3i(2, 1, 1)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	return BushKind.cluster(rng, palette, lod, NOMINAL, ROLES, COUNTS)
