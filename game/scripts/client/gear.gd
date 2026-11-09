class_name Gear
extends RefCounted
## What players and training mannequins wear and hold (PLAN §4.5): a dark armored suit with
## glowing seams and visor, a monomolecular blade, a hard-light shield and a slug revolver.
## Built in code apart from the revolver (Quaternius Sci-Fi Essentials, CC0); every prop's
## origin is the grip, and its long axis is local +Y (the hand bone's axis toward the fingers).

const REVOLVER := "res://assets/quaternius/guns/Gun_Revolver.gltf"
const ACCENT := Color(0.25, 0.85, 1.0)


## The suit: matte dark armor for the body, the accent color glowing at the joints.
static func suit(accent := ACCENT, armor := Color(0.16, 0.17, 0.19)) -> Array[Material]:
	var plates := StandardMaterial3D.new()
	plates.albedo_color = armor
	plates.metallic = 0.35
	plates.roughness = 0.45
	plates.clearcoat_enabled = true
	plates.clearcoat = 0.4
	plates.clearcoat_roughness = 0.3
	var seams := StandardMaterial3D.new()
	seams.albedo_color = accent.darkened(0.6)
	seams.emission_enabled = true
	seams.emission = accent
	seams.emission_energy_multiplier = 2.5
	return [plates, seams]


## A glowing visor strip across the face, for the head bone.
static func visor(accent := ACCENT) -> Node3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.035, 0.05)
	mesh.mesh = box
	mesh.material_override = _glow(accent, 4.0)
	mesh.position = Vector3(0, 0.1, 0.085)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## A long single edged blade with a glowing edge.
static func blade(accent := ACCENT) -> Node3D:
	var root := Node3D.new()
	var dark := _metal(Color(0.12, 0.12, 0.13), 0.3)
	root.add_child(_box(Vector3(0.035, 0.2, 0.035), Vector3(0, 0.0, 0), dark))
	root.add_child(_box(Vector3(0.13, 0.03, 0.05), Vector3(0, 0.11, 0), dark))
	root.add_child(
		_box(Vector3(0.05, 0.85, 0.012), Vector3(0, 0.55, 0), _metal(Color(0.5, 0.52, 0.55), 0.2))
	)
	root.add_child(_box(Vector3(0.008, 0.82, 0.016), Vector3(0.028, 0.55, 0), _glow(accent, 5.0)))
	return root


## A hard-light disc on a forearm emitter; set_shield() brightens it while blocking.
static func shield(accent := ACCENT) -> Node3D:
	var root := Node3D.new()
	root.add_child(
		_box(Vector3(0.07, 0.22, 0.06), Vector3.ZERO, _metal(Color(0.1, 0.1, 0.11), 0.4))
	)
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	disc.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/energy_shield.gdshader")
	material.set_shader_parameter("tint", accent)
	disc.material_override = material
	disc.rotation.y = PI / 2.0
	disc.position = Vector3(0.06, 0.0, 0.0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	return root


static func set_shield(shield_node: Node3D, raised: bool) -> void:
	var disc := shield_node.get_node("Disc") as MeshInstance3D
	(disc.material_override as ShaderMaterial).set_shader_parameter(
		"strength", 1.0 if raised else 0.35
	)


static func revolver() -> Node3D:
	return CharacterModel.prop(REVOLVER)


static func _box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material
	return mesh


static func _metal(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.9
	material.roughness = roughness
	return material


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.7)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
