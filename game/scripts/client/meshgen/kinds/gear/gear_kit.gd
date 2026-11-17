class_name GearKit
extends RefCounted
## Shared parts of the M39 gear generators. A gear generator is `build(rng, palette, lod, params)`
## like any kind, with the item's `look_params`: `role` (the main material, a palette role),
## `wear` (0 new .. 1 ruined, darkens faces), plus its own sizes. Hand gear has its origin at the
## grip and its long axis along +Y; shields face +Z. Worker safe, no resources.


static func role(params: Dictionary, key: String, fallback: StringName) -> StringName:
	return StringName(params.get(key, fallback))


## `arrays` moved by `at` after turning by `basis`; normals turn with it.
static func placed(arrays: Array, at: Vector3, basis := Basis.IDENTITY) -> Array:
	var v: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var n: PackedVector3Array = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	for i in v.size():
		v[i] = basis * v[i] + at
		n[i] = basis * n[i]
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	return out


## `arrays` painted with `role`, then darkened face by face by `wear` (params.wear).
static func paint(
	arrays: Array,
	palette: Palette,
	role_name: StringName,
	rng: RandomNumberGenerator,
	look: Vector2,
	params: Dictionary
) -> Array:
	MeshKit.paint(arrays, palette.color(role_name), rng, Vector3.DOWN, look)
	return worn(arrays, rng, params)


## `arrays` (already painted) darkened face by face by params.wear.
static func worn(arrays: Array, rng: RandomNumberGenerator, params: Dictionary) -> Array:
	var wear := float(params.get("wear", 0.0))
	if wear > 0.0:
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in range(0, colors.size(), 3):
			var dark := 1.0 - wear * rng.randf_range(0.1, 0.5)
			var c := colors[i]
			var worn := Color(c.r * dark, c.g * dark, c.b * dark, minf(c.a + wear * 0.2, 1.0))
			colors[i] = worn
			colors[i + 1] = worn
			colors[i + 2] = worn
		arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


## The body parts an armor piece covers, for bodies that hide what is below (M40): the item's
## `covers` param, else its look's own parts (a greave: `side` + "LowerLeg").
static func covers(look: StringName, params: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if params.has("covers"):
		for part: String in params["covers"]:
			out.append(StringName(part))
		return out
	match look:
		&"helm":
			out.append(&"Head")
		&"cuirass":
			out.append_array([&"UpperChest", &"Spine"] as Array[StringName])
		&"pauldrons":
			out.append_array([&"LeftUpperArm", &"RightUpperArm"] as Array[StringName])
		&"greaves":
			out.append(StringName(str(params.get("side", "Left")) + "LowerLeg"))
	return out


## A painted box (chamfered on the full level only), turned by `basis` around its center.
static func box(
	palette: Palette,
	rng: RandomNumberGenerator,
	look: Vector2,
	params: Dictionary,
	role_name: StringName,
	size: Vector3,
	center: Vector3,
	lod: int,
	basis := Basis.IDENTITY
) -> Array:
	var bevel := minf(size[size.min_axis_index()] * 0.2, 0.01) if lod == Budgets.FULL else 0.0
	var part := MeshKit.box(size, bevel)
	return paint(placed(part, center, basis), palette, role_name, rng, look, params)


## A painted prism of `outline` (XY plane) `depth` thick along Z, centered on `center`.
static func prism(
	palette: Palette,
	rng: RandomNumberGenerator,
	look: Vector2,
	params: Dictionary,
	role_name: StringName,
	outline: PackedVector2Array,
	depth: float,
	center: Vector3,
	lod: int
) -> Array:
	var bevel := depth * 0.25 if lod == Budgets.FULL else 0.0
	var part := MeshKit.extrude(outline, depth, bevel)
	return paint(placed(part, center), palette, role_name, rng, look, params)


## A painted solid of revolution around Z (`PropKit.turned` stands it on Y; turned here).
static func disc(
	palette: Palette,
	rng: RandomNumberGenerator,
	look: Vector2,
	params: Dictionary,
	role_name: StringName,
	profile: PackedVector2Array,
	sides: int,
	center: Vector3
) -> Array:
	var closed := PackedVector2Array([Vector2(0.0, profile[0].y)])
	closed.append_array(profile)
	closed.append(Vector2(0.0, profile[profile.size() - 1].y))
	var part := MeshKit.lathe(closed, sides, 0.0, rng)
	var basis := Basis(Vector3.RIGHT, PI / 2.0)
	return paint(placed(part, center, basis), palette, role_name, rng, look, params)


## A painted solid of revolution around Y (profile as `PropKit.turned`), worn by params.wear.
static func turned(
	palette: Palette,
	rng: RandomNumberGenerator,
	look: Vector2,
	params: Dictionary,
	role_name: StringName,
	profile: PackedVector2Array,
	sides: int,
	center: Vector3
) -> Array:
	var part := PropKit.turned(palette, rng, role_name, profile, sides, center, look)
	return worn(part, rng, params)
