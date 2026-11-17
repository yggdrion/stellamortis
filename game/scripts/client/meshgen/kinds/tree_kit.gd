class_name TreeKit
extends RefCounted
## Shared parts of the tree generators (M37 task 2, docs/STYLE.md section 6): the trunk axis (lean,
## bow, taper, root flare), trunk and root ridges, limbs, leaf clumps, cone layers, and the three
## ages (young, grown, old) every species registers. Rule for the species: draw every random
## number the shape depends on (sizes, positions) first, the same for every level of detail, then
## build only as many parts as the level allows, so the levels share one silhouette.

const AGES: Array[String] = ["young", "grown", "old"]
## The trunk starts this far below the root point, so it never floats on a slope.
const SINK := 0.25
## Per level (full, half, far).
const TRUNK_SIDES: Array[int] = [12, 7, 3]
const LIMB_SIDES: Array[int] = [6, 4, 3]
const LIMB_POINTS: Array[int] = [3, 3, 2]
## Segments above the root flare per age, per level.
const POINTS: Array[Vector3i] = [Vector3i(3, 2, 1), Vector3i(6, 4, 1), Vector3i(8, 5, 1)]
## Root ridges per age, per level (old trees only).
const RIDGES: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(0, 0, 0), Vector3i(5, 3, 0)]
## Nothing on a tree is thinner than this radius (15 cm across, docs/STYLE.md).
const MIN_LIMB := 0.075


## The trunk's center line and radius: leaning, bowed, tapering, flared at the root.
class Axis:
	extends RefCounted
	var height := 1.0
	var base_r := 0.1
	var top_r := 0.05
	var flare := 1.0
	var lean := Vector3.ZERO
	var bow := Vector3.ZERO

	func pos(y: float) -> Vector3:
		return Vector3(0.0, y, 0.0) + lean * y + bow * sin(PI * clampf(y / height, 0.0, 1.0))

	func radius(y: float) -> float:
		var base := lerpf(base_r, top_r, clampf(y / height, 0.0, 1.0))
		var hump := maxf(0.0, 1.0 - (y + TreeKit.SINK) / (base_r * 3.0 + TreeKit.SINK))
		return base * (1.0 + (flare - 1.0) * hump)


## Registers `<name>_young`, `_grown` and `_old`; `builder(rng, palette, lod, age)`.
static func register_all(species: String, builder: Callable) -> void:
	for age in 3:
		Generators.register("%s_%s" % [species, AGES[age]], "tree_" + AGES[age], builder.bind(age))


## `nominal` is (trunk radius above the flare, height) in meters. Six draws.
static func axis(
	rng: RandomNumberGenerator, nominal: Vector2, top_frac: float, flare: float, lean_max: float
) -> Axis:
	var a := Axis.new()
	a.height = nominal.y * rng.randf_range(0.88, 1.12)
	a.base_r = nominal.x * rng.randf_range(0.92, 1.08)
	a.top_r = a.base_r * top_frac
	a.flare = flare
	var yaw := rng.randf_range(0.0, TAU)
	a.lean = Vector3(cos(yaw), 0.0, sin(yaw)) * tan(deg_to_rad(rng.randf_range(0.0, lean_max)))
	var bow_yaw := rng.randf_range(0.0, TAU)
	a.bow = Vector3(cos(bow_yaw), 0.0, sin(bow_yaw)) * a.height * rng.randf_range(0.0, 0.025)
	return a


## The trunk from below the ground to `top_y`, `points` segments above the flare ring.
static func trunk(
	a: Axis, rng: RandomNumberGenerator, lod: int, top_y: float, points: int
) -> Array:
	var ys: Array[float] = [-SINK]
	if a.flare > 1.0 and lod < 2:
		ys.append(a.base_r * 1.5)
	var y0: float = ys.back()
	for k in range(1, points + 1):
		ys.append(lerpf(y0, top_y, float(k) / points))
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for y in ys:
		path.append(a.pos(y))
		radii.append(a.radius(y))
	return MeshKit.tube(path, radii, TRUNK_SIDES[lod], 0.1, rng)


## Buttress ridges that run from the trunk out into the ground.
static func ridges(a: Axis, rng: RandomNumberGenerator, count: int) -> Array:
	var parts: Array = []
	for i in count:
		var angle := TAU * (i + rng.randf_range(0.0, 0.6)) / count
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var tip := a.pos(0.0) + out * a.base_r * a.flare * 2.2 + Vector3.DOWN * 0.1
		var root := a.pos(a.base_r * 1.6) + out * a.base_r * 0.3
		var radii := PackedFloat32Array([MIN_LIMB, a.base_r * 0.45])
		parts.append(MeshKit.tube(PackedVector3Array([tip, root]), radii, 4, 0.15, rng))
	return parts


## A limb from `from` (inside the trunk) to `to`, arched upward by `arch` of its length.
static func limb(
	from: Vector3,
	to: Vector3,
	r0: float,
	r1: float,
	lod: int,
	rng: RandomNumberGenerator,
	arch := 0.12
) -> Array:
	var count := LIMB_POINTS[lod]
	var length := from.distance_to(to)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in count:
		var t := float(k) / (count - 1)
		path.append(from.lerp(to, t) + Vector3.UP * arch * length * sin(PI * t))
		radii.append(lerpf(maxf(r0, MIN_LIMB), maxf(r1, MIN_LIMB), t))
	return MeshKit.tube(path, radii, LIMB_SIDES[lod], 0.12, rng)


## A leaf or needle mass: a displaced icosphere at `center`.
static func clump(
	rng: RandomNumberGenerator, center: Vector3, radius: float, detail: int, flatten: float
) -> Array:
	return moved(MeshKit.blob(radius, detail, 0.3, flatten, rng), center)


## Conifer layers, each one following the axis; `layers` are (base height, base radius, height).
static func cone_layers(
	a: Axis, rng: RandomNumberGenerator, layers: PackedVector3Array, sides: int
) -> Array:
	var parts: Array = []
	for l in layers:
		var at := a.pos(l.x + l.z * 0.3)
		at += Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * l.y * 0.08
		at.y = 0.0
		parts.append(moved(MeshKit.cone_stack(PackedVector3Array([l]), sides, 0.15, rng), at))
	return parts


static func moved(arrays: Array, by: Vector3) -> Array:
	var v: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	for i in v.size():
		v[i] += by
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = v
	return out


## `count` indices spread evenly over `total` (first and last included).
static func pick(total: int, count: int) -> Array[int]:
	var out: Array[int] = []
	if count >= total:
		for i in total:
			out.append(i)
		return out
	for i in count:
		out.append(roundi(i * (total - 1.0) / maxf(count - 1.0, 1.0)))
	return out


static func painted(
	parts: Array, role: StringName, palette: Palette, rng: RandomNumberGenerator, look: Vector2
) -> Array:
	return MeshKit.paint(MeshKit.merge(parts), palette.color(role), rng, Vector3.DOWN, look)
