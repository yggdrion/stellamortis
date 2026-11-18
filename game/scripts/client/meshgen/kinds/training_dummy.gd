class_name TrainingDummyKind
extends RefCounted
## A training dummy: a post on a crossed foot, a straw sack torso with a rope belt and a painted
## target, a sack head, a cross arm with a small round shield on one side (the side by seed).
## Origin: ground, center, the target faces +Z.

const NOMINAL := Vector3(1.2, 1.95, 0.7)


## Axis Y of `arrays` turned to +Z (a lathe disc lying on the chest).
static func _facing(arrays: Array) -> Array:
	var basis := Basis(Vector3.RIGHT, PI / 2.0)
	var v: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var n: PackedVector3Array = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	for i in v.size():
		v[i] = basis * v[i]
		n[i] = basis * n[i]
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	return out


## A painted flat disc of `radius` and `thickness` facing +Z, centered on `center`.
static func _disc(
	palette: Palette,
	rng: RandomNumberGenerator,
	role: StringName,
	radius: float,
	thickness: float,
	center: Vector3,
	look: Vector2,
	sides: int
) -> Array:
	var profile := PackedVector2Array(
		[
			Vector2(0.0, -thickness / 2.0),
			Vector2(radius, -thickness / 2.0),
			Vector2(radius, thickness / 2.0)
		]
	)
	profile.append(Vector2(0.0, thickness / 2.0))
	var part := _facing(MeshKit.lathe(profile, sides, 0.0, rng))
	return MeshKit.paint(PropKit.moved(part, center), palette.color(role), rng, Vector3.DOWN, look)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var full := lod == Budgets.FULL
	var sides := 8 if full else 3
	var parts: Array = []
	var foot := Vector3(0.7, 0.08, 0.12)
	parts.append(PropKit.box(palette, rng, &"wood", foot, Vector3(0, 0.04, 0), look, lod, 0.0))
	if full:
		var cross := Vector3(0.12, 0.08, 0.7)
		parts.append(PropKit.box(palette, rng, &"wood", cross, Vector3(0, 0.04, 0), look, lod, 0.0))
	var post := Vector3(0.1, 1.5, 0.1)
	parts.append(PropKit.box(palette, rng, &"wood", post, Vector3(0, 0.75, 0), look, lod, 0.0))
	var arm := Vector3(1.2, 0.08, 0.08)
	parts.append(PropKit.box(palette, rng, &"wood", arm, Vector3(0, 1.42, 0), look, lod, 0.0))
	var torso := PackedVector2Array([Vector2(0.2, 0.88), Vector2(0.3, 1.2), Vector2(0.14, 1.5)])
	parts.append(PropKit.turned(palette, rng, &"thatch", torso, sides, Vector3.ZERO, look))
	var head := PackedVector2Array([Vector2(0.14, 1.52), Vector2(0.18, 1.72), Vector2(0.05, 1.9)])
	parts.append(PropKit.turned(palette, rng, &"cloth", head, sides, Vector3.ZERO, look))
	if full:
		var belt := PackedVector2Array([Vector2(0.31, 1.0), Vector2(0.31, 1.08)])
		parts.append(PropKit.turned(palette, rng, &"leather", belt, sides, Vector3.ZERO, look))
	var chest := Vector3(0, 1.26, 0.27)
	parts.append(_disc(palette, rng, &"cloth_dark", 0.22, 0.04, chest, look, sides))
	parts.append(_disc(palette, rng, &"ember", 0.1, 0.04, chest + Vector3(0, 0, 0.01), look, sides))
	var shield_at := Vector3(0.52 * side, 1.36, 0.07)
	parts.append(_disc(palette, rng, &"wood", 0.2, 0.06, shield_at, look, sides))
	return PropKit.shaped(MeshKit.merge(parts), shape)
