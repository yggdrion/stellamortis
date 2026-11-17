class_name SwordKind
extends RefCounted
## A straight double edged sword, origin at the middle of the grip, blade along +Y. Params:
## `length` blade (0.85), `width` (0.055), `guard` span (0.2), `grip` (0.18), `pommel` ("ball" or
## "disc"), `role` blade metal (steel), `grip_role` (leather), `fitting` guard and pommel (iron),
## `wear`. Blade + grip must stay inside the weapon's attack reach (tests/gear_look_test.gd).

const DEFAULTS := {"length": 0.85, "width": 0.055, "guard": 0.2, "grip": 0.18, "pommel": "ball"}


## How far the tip is from the grip's middle.
static func total(params: Dictionary) -> float:
	var p := _merged(params)
	return float(p["length"]) + float(p["grip"]) * 0.5 + 0.03


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := _merged(params)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var length: float = p["length"]
	var width: float = p["width"]
	var grip: float = p["grip"]
	var top := grip * 0.5
	var fitting := GearKit.role(p, "fitting", &"iron")
	var parts: Array = []
	var handle := Vector3(0.035, grip, 0.035)
	var wrap := GearKit.role(p, "grip_role", &"leather")
	parts.append(GearKit.box(palette, rng, look, p, wrap, handle, Vector3.ZERO, lod))
	var pommel := Vector3(0.05, 0.05, 0.05)
	if p["pommel"] == "disc":
		pommel = Vector3(0.07, 0.03, 0.07)
	var knob := Vector3(0, -top - 0.02, 0)
	parts.append(GearKit.box(palette, rng, look, p, fitting, pommel, knob, lod))
	var guard := Vector3(float(p["guard"]), 0.03, 0.045)
	var cross := Vector3(0, top + 0.015, 0)
	parts.append(GearKit.box(palette, rng, look, p, fitting, guard, cross, lod))
	var outline := PackedVector2Array(
		[
			Vector2(-width * 0.5, 0.0),
			Vector2(width * 0.5, 0.0),
			Vector2(width * 0.5, length * 0.9),
			Vector2(0.0, length),
			Vector2(-width * 0.5, length * 0.9),
		]
	)
	var metal := GearKit.role(p, "role", &"steel")
	var at := Vector3(0, top + 0.03, 0)
	parts.append(GearKit.prism(palette, rng, look, p, metal, outline, 0.012, at, lod))
	return PropKit.shaped(MeshKit.merge(parts), shape)


static func _merged(params: Dictionary) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	return p
