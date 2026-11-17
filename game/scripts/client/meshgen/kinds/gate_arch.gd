class_name GateArchKind
extends RefCounted
## The frame of a portal: two pillars on plinths and a lintel with a keystone. The veil (a shader
## quad, 2.8 x 3.9) hangs in the opening and is not part of this mesh. Origin: ground, center.

const NOMINAL := Vector3(4.2, 4.65, 0.8)
const PILLAR := Vector3(0.6, 4.0, 0.7)
const LINTEL := Vector3(4.2, 0.7, 0.8)
const PILLAR_X := 1.7
const LINTEL_Y := 4.3


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var parts: Array = []
	for side in [-1.0, 1.0]:
		var x: float = side * PILLAR_X
		parts.append(
			PropKit.box(
				palette, rng, &"stone", PILLAR, Vector3(x, PILLAR.y * 0.5, 0.0), look, lod, 0.05
			)
		)
		var plinth := Vector3(PILLAR.x + 0.2, 0.3, PILLAR.z + 0.1)
		parts.append(
			PropKit.box(
				palette,
				rng,
				&"stone_dark",
				plinth,
				Vector3(x, plinth.y * 0.5, 0.0),
				look,
				lod,
				0.04
			)
		)
	parts.append(
		PropKit.box(palette, rng, &"stone", LINTEL, Vector3(0.0, LINTEL_Y, 0.0), look, lod, 0.06)
	)
	var key := Vector3(0.7, 0.3, LINTEL.z + 0.1)
	parts.append(
		PropKit.box(
			palette, rng, &"stone_dark", key, Vector3(0.0, LINTEL_Y - 0.3, 0.0), look, lod, 0.04
		)
	)
	return PropKit.shaped(MeshKit.merge(parts), shape)
