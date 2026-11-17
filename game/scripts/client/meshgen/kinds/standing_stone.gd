class_name StandingStoneKind
extends RefCounted
## A standing stone: a tall faceted slab, narrowing upward, leaning a few degrees, top cut aslant.

## Width, height above the ground, depth in meters: the kind's `ScatterShape` box.
const NOMINAL := Vector3(2.0, 4.0, 1.4)
const SINK := 0.5
## Radius at the top as a fraction of the base (STYLE: 60 to 80 %).
const TOP := Vector2(0.6, 0.8)
## Lean in degrees (STYLE allows 10; the box is narrower than the lean at its top).
const LEAN := 6.0
const WOBBLE := 0.1
## Per level (full, half, far).
const SIDES: Array[int] = [8, 6, 5]
const RINGS: Array[int] = [8, 6, 3]


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var h := NOMINAL.y * rng.randf_range(0.92, 1.05)
	var top := rng.randf_range(TOP.x, TOP.y)
	var look := MeshKit.jitter(rng)
	var tilt := tan(deg_to_rad(rng.randf_range(0.0, LEAN)))
	var lean := Vector2.from_angle(rng.randf_range(0.0, TAU)) * tilt
	var cut := Vector3(rng.randf_range(-0.4, 0.4), 1.0, rng.randf_range(-0.2, 0.2)).normalized()
	var phase := rng.randf_range(0.0, TAU)
	var profile := PackedVector2Array()
	for k in RINGS[lod] - 1:
		var y := lerpf(-SINK, h * 0.95, float(k) / (RINGS[lod] - 2))
		profile.append(Vector2(lerpf(1.0, top, (y + SINK) / (h + SINK)), y))
	profile.append(Vector2(0.0, h * 1.03))
	var stone := MeshKit.lathe(profile, SIDES[lod], WOBBLE, rng, phase)
	var scale := Vector3(NOMINAL.x * 0.5, 1.0, NOMINAL.z * 0.5)
	stone = RockKind.warp(stone, scale, Vector3.ZERO, lean)
	var planes: Array[Plane] = [Plane(cut, cut.y * h * 0.97)]
	stone = MeshKit.chip(stone, planes)
	return MeshKit.paint(stone, palette.color(&"stone"), rng, Vector3.DOWN, look)
