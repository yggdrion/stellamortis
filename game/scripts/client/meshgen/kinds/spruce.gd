class_name SpruceKind
extends RefCounted
## Spruce: narrow, full to the ground, a tall stack of cone layers.

## Per id: trunk radius above the root flare and height in meters.
const NOMINAL := {
	"spruce_young": Vector2(0.11, 4.0),
	"spruce_grown": Vector2(0.24, 10.0),
	"spruce_old": Vector2(0.45, 19.0),
}
const FLARE: Array[float] = [1.0, 1.1, 1.4]
const LAYERS: Array[Vector3i] = [Vector3i(7, 5, 2), Vector3i(11, 8, 4), Vector3i(16, 11, 6)]
const SIDES: Array[Vector3i] = [Vector3i(8, 6, 5), Vector3i(10, 7, 5), Vector3i(12, 8, 5)]
## Widest layer radius as a fraction of the height.
const WIDTH := 0.23


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, age: int) -> Array:
	var a := TreeKit.axis(rng, NOMINAL["spruce_" + TreeKit.AGES[age]], 0.3, FLARE[age], 5.0)
	var h := a.height
	var look := MeshKit.jitter(rng)
	var jitter := PackedFloat32Array()
	for i in LAYERS[age].x:
		jitter.append(rng.randf_range(0.85, 1.15))
	var count := LAYERS[age][lod]
	var lowest := 0.05 * h + 0.3
	var top := 0.82 * h
	var spacing := (top - lowest) / (count - 1)
	var layers := PackedVector3Array()
	for i in count:
		var t := float(i) / (count - 1)
		var base := lerpf(lowest, top, t)
		var r := WIDTH * h * (pow(1.0 - t, 0.85) * 0.95 + 0.05) * jitter[i]
		var tall := spacing * 2.4 if i < count - 1 else h - base
		layers.append(Vector3(base, r, tall))
	var bark: Array = [TreeKit.trunk(a, rng, lod, h * 0.7, TreeKit.POINTS[age][lod])]
	bark.append_array(TreeKit.ridges(a, rng, TreeKit.RIDGES[age][lod]))
	var needles := TreeKit.cone_layers(a, rng, layers, SIDES[age][lod])
	return (
		MeshKit
		. merge(
			[
				TreeKit.painted(bark, &"bark", palette, rng, look),
				TreeKit.painted(needles, &"needle", palette, rng, look),
			]
		)
	)
