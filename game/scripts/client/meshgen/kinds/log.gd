class_name LogKind
extends RefCounted
## A fallen log (a bowed trunk with branch stubs and a moss patch) and a stump (a flared cut trunk
## with root stubs).

## Per id: width (diameter or thickness), height, length in meters.
const NOMINAL := {"log": Vector3(0.6, 0.55, 3.0), "stump": Vector3(0.9, 0.6, 0.9)}
## Share of a log's diameter that is under the ground.
const SINK := 0.3
const WOBBLE := 0.1
## Per level (full, half, far).
const SIDES: Array[int] = [8, 6, 5]
const LOG_POINTS: Array[int] = [5, 3, 3]
const STUMP_POINTS: Array[int] = [4, 3, 3]
const STUBS: Array[int] = [2, 1, 0]
const ROOTS: Array[int] = [3, 2, 0]
const STUMP_SIDES: Array[int] = [10, 6, 5]
## Nothing is thinner than this radius (STYLE: 6 cm for props).
const MIN_LIMB := 0.07


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, id: String) -> Array:
	if id == "stump":
		return _stump(rng, palette, lod)
	return _log(rng, palette, lod)


static func _log(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var nominal: Vector3 = NOMINAL["log"]
	var length := nominal.z * rng.randf_range(0.8, 1.15)
	var r0 := nominal.x * 0.5 * rng.randf_range(0.9, 1.1)
	var r1 := r0 * rng.randf_range(0.65, 0.85)
	var y := r0 * (1.0 - SINK * 2.0)
	var bow := rng.randf_range(-0.08, 0.08) * length
	var look := MeshKit.jitter(rng)
	var stubs: Array = []
	for i in STUBS[0]:
		stubs.append([rng.randf_range(-0.3, 0.3) * length, rng.randf_range(0.0, TAU), rng.randi()])
	var moss_at := rng.randf_range(-0.25, 0.25) * length
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in LOG_POINTS[lod]:
		var t := float(k) / (LOG_POINTS[lod] - 1)
		path.append(Vector3((t - 0.5) * length, y, bow * sin(PI * t)))
		radii.append(lerpf(r0, r1, t))
	var bark: Array = [MeshKit.tube(path, radii, SIDES[lod], WOBBLE, rng)]
	for i in STUBS[lod]:
		var stub_rng := RandomNumberGenerator.new()
		stub_rng.seed = stubs[i][2]
		var angle: float = stubs[i][1]
		var from := Vector3(stubs[i][0], y + r0 * 0.5, 0.0)
		var to := from + Vector3(cos(angle) * 0.1, r0 + 0.1, sin(angle) * 0.1 + 0.15)
		var tip := PackedFloat32Array([maxf(r0 * 0.3, MIN_LIMB), MIN_LIMB])
		bark.append(MeshKit.tube(PackedVector3Array([from, to]), tip, 4, 0.1, stub_rng))
	var wood := MeshKit.paint(MeshKit.merge(bark), palette.color(&"bark"), rng, Vector3.DOWN, look)
	var patch := Vector3(length * 0.28, r0 * 0.6, r0 * 1.3)
	var moss := RockKind.lump(rng, patch, Vector3(moss_at, y + r0 * 0.75, 0.0), 0, [])
	moss = MeshKit.paint(moss, palette.color(&"moss"), rng, Vector3.DOWN, look)
	return MeshKit.merge([wood, moss])


static func _stump(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var nominal: Vector3 = NOMINAL["stump"]
	var r := nominal.x * 0.5 * rng.randf_range(0.85, 1.1)
	var h := nominal.y * rng.randf_range(0.85, 1.1)
	var look := MeshKit.jitter(rng)
	var roots: Array = []
	for i in ROOTS[0]:
		roots.append([TAU * (i + rng.randf_range(0.0, 0.6)) / ROOTS[0], rng.randi()])
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var points := STUMP_POINTS[lod]
	for k in points:
		var t := float(k) / (points - 1)
		path.append(Vector3(0.0, lerpf(-0.25, h, t), 0.0))
		radii.append(r * lerpf(1.1, 0.8, t))
	var bark: Array = [MeshKit.tube(path, radii, STUMP_SIDES[lod], WOBBLE, rng)]
	for i in ROOTS[lod]:
		var angle: float = roots[i][0]
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var ends := PackedVector3Array(
			[out * r * 1.7 + Vector3.DOWN * 0.05, out * r * 0.5 + Vector3(0.0, 0.2, 0.0)]
		)
		var root_rng := RandomNumberGenerator.new()
		root_rng.seed = roots[i][1]
		bark.append(MeshKit.tube(ends, PackedFloat32Array([MIN_LIMB, r * 0.3]), 4, 0.1, root_rng))
	return MeshKit.paint(MeshKit.merge(bark), palette.color(&"bark"), rng, Vector3.DOWN, look)
