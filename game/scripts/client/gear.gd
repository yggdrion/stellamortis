class_name Gear
extends RefCounted
## Who wears what (PLAN §3.2): players are rangers, the training squires peasants, the dead
## peasants in their dark set with grey skin and ember eyes (Quaternius outfits and base
## character heads, CC0), the Warden the UAL figure in black iron. Weapons are built in code (a
## steel sword, a crossbow) apart from the round wooden shield (Fantasy Props MegaKit, CC0).
## Every prop's origin is the grip, its long axis local +Y (the hand bone's axis toward the
## fingers).

const SHIELD := "res://assets/quaternius/props/Shield_Wooden.gltf"
## Enemy eyes and shots.
const EMBER := Color(1.0, 0.35, 0.1)
const STEEL := Color(0.62, 0.63, 0.65)
const IRON := Color(0.16, 0.16, 0.17)
const LEATHER := Color(0.2, 0.14, 0.1)
## The dead's skin and faded clothes.
const DEAD := Color(0.72, 0.78, 0.68)


## A knight: plate for the body, leather at the joints (the mannequin's second surface).
static func armor(plate := STEEL, joints := LEATHER) -> Array[Material]:
	# Half metal: full metal mirrors the black night sky and goes black.
	var plates := _metal(plate, 0.45)
	plates.metallic = 0.45
	var leather := StandardMaterial3D.new()
	leather.albedo_color = joints
	leather.roughness = 0.85
	return [plates, leather]


## A player: a ranger, male (bearded) or female in the second color set by peer id, with a dark
## or light skin by the next bit.
static func ranger(peer_id: int, held: Dictionary) -> CharacterModel:
	var male := peer_id % 2 == 0
	var light := (peer_id / 2) % 2 == 1
	var c := CharacterModel.CHARACTERS
	var outfit := CharacterModel.RANGER_MALE if male else CharacterModel.RANGER_FEMALE
	var model := CharacterModel.new(outfit, held)
	if male:
		model.wear_head(
			CharacterModel.BODY_MALE,
			[c + "Hair_Beard.gltf"],
			load(c + "T_Superhero_Male_Ligh.png") if light else null
		)
	else:
		model.wear_head(
			CharacterModel.BODY_FEMALE,
			[],
			load(c + "T_Superhero_Female_Light_BaseColor.png") if light else null
		)
		model.swap_albedo(
			"T_Ranger_BaseColor.png", load(CharacterModel.OUTFITS + "T_Ranger_3_BaseColor.png")
		)
	return model


## A training squire: a peasant with short or parted hair.
static func squire(index: int, held: Dictionary) -> CharacterModel:
	var c := CharacterModel.CHARACTERS
	var model := CharacterModel.new(CharacterModel.PEASANT_MALE, held)
	var hair := "Hair_SimpleParted.gltf" if index % 2 == 0 else "Hair_Buzzed.gltf"
	model.wear_head(CharacterModel.BODY_MALE, [c + hair], load(c + "T_Superhero_Male_Ligh.png"))
	return model


## One of the dead: a peasant in the dark set, grey-green, long or bound hair, ember eyes (male
## swordsmen, female crossbow archers).
static func dead(archer: bool, held: Dictionary) -> CharacterModel:
	var c := CharacterModel.CHARACTERS
	held["eyes"] = ["Head", eyes()]
	var outfit := CharacterModel.PEASANT_FEMALE if archer else CharacterModel.PEASANT_MALE
	var model := CharacterModel.new(outfit, held)
	if archer:
		model.wear_head(CharacterModel.BODY_FEMALE, [c + "Hair_Buns.gltf"])
	else:
		model.wear_head(CharacterModel.BODY_MALE, [c + "Hair_Long.gltf"])
	model.swap_albedo(
		"T_Peasant_BaseColor.png", load(CharacterModel.OUTFITS + "T_Peasant_2_BaseColor.png")
	)
	model.tint(DEAD)
	return model


## A rounded bascinet: a dome over a short cylinder, a dark eye slit and a nasal ridge, for
## the head bone.
static func helm(plate := STEEL) -> Node3D:
	var root := Node3D.new()
	var steel := _metal(plate, 0.4)
	steel.metallic = 0.5
	var shell := MeshInstance3D.new()
	var can := CylinderMesh.new()
	can.top_radius = 0.135
	can.bottom_radius = 0.14
	can.height = 0.17
	can.material = steel
	shell.mesh = can
	shell.position = Vector3(0, 0.06, 0.01)
	root.add_child(shell)
	var dome := MeshInstance3D.new()
	var cap := SphereMesh.new()
	cap.radius = 0.135
	cap.height = 0.17
	cap.is_hemisphere = true
	cap.material = steel
	dome.mesh = cap
	dome.position = Vector3(0, 0.145, 0.01)
	root.add_child(dome)
	root.add_child(_box(Vector3(0.19, 0.022, 0.03), Vector3(0, 0.1, 0.135), _metal(IRON, 0.9)))
	root.add_child(_box(Vector3(0.022, 0.13, 0.025), Vector3(0, 0.06, 0.145), steel))
	return root


## Two horns curving up and out of the Warden's helm, for the head bone.
static func horns(size := 1.0) -> Node3D:
	var root := Node3D.new()
	var bone := _plain(Color(0.12, 0.1, 0.08), 0.6)
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * 0.12, 0.16, 0.0)
		var tilt := 0.0
		# Three tapering segments, each bent further out and up: a curved horn.
		for i in 3:
			var segment := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.bottom_radius = 0.045 - 0.013 * i
			cone.top_radius = 0.045 - 0.013 * (i + 1) if i < 2 else 0.0
			cone.height = 0.14
			cone.material = bone
			segment.mesh = cone
			tilt += 0.55 - 0.25 * i
			segment.rotation = Vector3(-0.25, 0.0, -side * tilt)
			var along := segment.basis.y * cone.height
			segment.position = at + along / 2.0
			at += along
			root.add_child(segment)
	root.scale = Vector3.ONE * size
	root.position.y = 0.16 * (1.0 - size)
	return root


## A crown of iron spikes around the helm, for the head bone.
static func crown(plate := IRON) -> Node3D:
	var root := Node3D.new()
	var iron := _metal(plate.lightened(0.1), 0.5)
	for i in 7:
		var angle := PI * (i / 6.0 - 0.5) * 0.9
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.bottom_radius = 0.018
		cone.top_radius = 0.0
		cone.height = 0.11 if i % 2 == 0 else 0.07
		cone.material = iron
		spike.mesh = cone
		var out := Vector3(sin(angle), 0.0, cos(angle))
		spike.position = Vector3(0, 0.2, 0.01) + out * 0.11 + Vector3.UP * cone.height / 2.0
		spike.rotation = Vector3(out.z * 0.3, 0.0, -out.x * 0.3)
		root.add_child(spike)
	return root


## A tattered black cape hanging from the shoulders, for the upper chest bone: strips of
## uneven length, so it reads ragged.
static func cape() -> Node3D:
	var root := Node3D.new()
	var cloth := _plain(Color(0.05, 0.04, 0.04), 0.95)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lengths := [0.95, 1.15, 0.8, 1.2, 1.0, 0.85, 1.1]
	for i in lengths.size():
		var length: float = lengths[i]
		var x := (i - (lengths.size() - 1) / 2.0) * 0.075
		var strip := _box(
			Vector3(0.08, length, 0.012), Vector3(x, 0.12 - length / 2.0, -0.17), cloth
		)
		strip.rotation.x = 0.12
		root.add_child(strip)
	return root


## Spiked pauldrons on both shoulders, for the upper chest bone.
static func pauldrons(plate := IRON) -> Node3D:
	var root := Node3D.new()
	var iron := _metal(plate, 0.45)
	for side: float in [-1.0, 1.0]:
		var shell := MeshInstance3D.new()
		var dome := SphereMesh.new()
		dome.radius = 0.12
		dome.height = 0.14
		dome.is_hemisphere = true
		dome.material = iron
		shell.mesh = dome
		shell.position = Vector3(side * 0.2, 0.1, 0.0)
		shell.rotation.z = -side * 0.35
		root.add_child(shell)
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.bottom_radius = 0.03
		cone.top_radius = 0.0
		cone.height = 0.16
		cone.material = _metal(plate.lightened(0.15), 0.5)
		spike.mesh = cone
		spike.position = Vector3(side * 0.25, 0.22, 0.0)
		spike.rotation.z = -side * 0.5
		root.add_child(spike)
	return root


## Two ember eyes, for the head bone of the dead.
static func eyes(color := EMBER, energy := 6.0) -> Node3D:
	var root := Node3D.new()
	for x: float in [-0.035, 0.035]:
		var eye := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.016
		ball.height = 0.032
		ball.material = _glow(color, energy)
		eye.mesh = ball
		eye.position = Vector3(x, 0.09, 0.09)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(eye)
	return root


## A straight double edged sword; rust for the dead's.
static func sword(blade_color := Color(0.62, 0.63, 0.65), length := 0.85) -> Node3D:
	var root := Node3D.new()
	root.add_child(_box(Vector3(0.035, 0.18, 0.035), Vector3.ZERO, _plain(LEATHER, 0.8)))
	root.add_child(_box(Vector3(0.05, 0.05, 0.05), Vector3(0, -0.11, 0), _metal(IRON, 0.5)))
	root.add_child(_box(Vector3(0.2, 0.03, 0.04), Vector3(0, 0.1, 0), _metal(IRON, 0.5)))
	root.add_child(
		_box(
			Vector3(0.055, length, 0.01),
			Vector3(0, 0.12 + length / 2.0, 0),
			_metal(blade_color, 0.3)
		)
	)
	return root


## The round wooden shield, its face turned outward from the forearm.
static func shield() -> Node3D:
	var node := CharacterModel.prop(SHIELD)
	node.rotation = Vector3(0, PI / 2.0, 0)
	node.position = Vector3(0.08, 0.0, 0.0)
	return node


## A crossbow: wooden stock along the hand, a steel bow across its front and the string.
static func crossbow() -> Node3D:
	var root := Node3D.new()
	var wood := _plain(Color(0.3, 0.2, 0.12), 0.7)
	root.add_child(_box(Vector3(0.05, 0.62, 0.06), Vector3(0, 0.2, 0.02), wood))
	var steel := _metal(STEEL, 0.4)
	for side: float in [-1.0, 1.0]:
		var limb := _box(Vector3(0.3, 0.025, 0.025), Vector3(side * 0.15, 0.46, 0.03), steel)
		limb.rotation.z = side * -0.25
		root.add_child(limb)
	root.add_child(
		_box(Vector3(0.58, 0.006, 0.006), Vector3(0, 0.38, 0.03), _plain(Color.BLACK, 1))
	)
	return root


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
	material.metallic = 0.85
	material.roughness = roughness
	return material


static func _plain(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.5)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
