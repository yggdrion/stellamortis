class_name GraveKind
extends RefCounted
## `grave_slab`: a flat stone laid over a grave with a moss patch. `grave_marker`: an upright
## headstone with a rounded top (a player's grave).

const NOMINAL := {"grave_slab": Vector3(1.0, 0.3, 2.0), "grave_marker": Vector3(0.6, 1.2, 0.15)}


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, id: String) -> Array:
	var look := MeshKit.jitter(rng)
	if id == "grave_marker":
		var top := rng.randf_range(1.1, 1.2)
		var lean := rng.randf_range(-0.04, 0.04)
		var outline := PackedVector2Array(
			[
				Vector2(-0.3, -0.1),
				Vector2(0.3, -0.1),
				Vector2(0.29 + lean, 0.9),
				Vector2(0.15 + lean, top - 0.05),
				Vector2(-0.12 + lean, top),
				Vector2(-0.28 + lean, 0.95),
			]
		)
		var stone := MeshKit.extrude(outline, 0.15, 0.03 if lod == Budgets.FULL else 0.0)
		return MeshKit.paint(stone, palette.color(&"stone"), rng, Vector3.DOWN, look)
	var length: float = (NOMINAL[id] as Vector3).z * rng.randf_range(0.85, 1.0)
	var slab := Vector3(0.8, 0.16, length)
	var kerb := Vector3(1.0, 0.12, length + 0.1)
	var parts: Array = [
		PropKit.box(palette, rng, &"stone_dark", kerb, Vector3(0, 0.0, 0), look, lod, 0.03),
		PropKit.box(palette, rng, &"stone", slab, Vector3(0, 0.07, 0), look, lod, 0.04),
	]
	var at := Vector3(rng.randf_range(-0.1, 0.1), 0.16, rng.randf_range(-0.4, 0.4))
	var moss := RockKind.lump(rng, Vector3(0.3, 0.05, 0.5), at, 0, [])
	parts.append(MeshKit.paint(moss, palette.color(&"moss"), rng, Vector3.DOWN, look))
	return MeshKit.merge(parts)
