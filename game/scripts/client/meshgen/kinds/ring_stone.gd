class_name RingStoneKind
extends RefCounted
## A stone of the arrival's ring: a chamfered slab with an aslant top, a little over twice a
## person's height. Fits `Arena.STONE_SOLID`.

const NOMINAL := Vector3(2.0, 2.4, 1.4)
const SINK := 0.25
## Outline corners (x, y) before the jitter; y 0 is the ground.
const OUTLINE: Array[Vector2] = [
	Vector2(-0.92, 0.0),
	Vector2(0.92, 0.0),
	Vector2(0.78, 1.5),
	Vector2(0.3, 2.25),
	Vector2(-0.45, 2.1),
	Vector2(-0.82, 1.25),
]


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var high := rng.randf_range(0.95, 1.03)
	var outline := PackedVector2Array()
	for p in OUTLINE:
		var q := p + Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.05, 0.05))
		q.y = maxf(q.y, 0.0) * high
		outline.append(q)
	outline[0].y = -SINK
	outline[1].y = -SINK
	var depth := NOMINAL.z * rng.randf_range(0.85, 0.95)
	var bevel := 0.08 if lod == Budgets.FULL else 0.0
	var slab := MeshKit.extrude(outline, depth, bevel)
	return MeshKit.paint(slab, palette.color(&"stone"), rng, Vector3.DOWN, look)
